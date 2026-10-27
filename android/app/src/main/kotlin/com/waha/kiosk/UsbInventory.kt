package com.waha.kiosk

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import com.felhr.usbserial.UsbSerialDevice
import java.io.File

// Passive, read-only snapshot of everything USB the kiosk can see. Touches
// nothing: no permission requests, no connections, no Geidea state. Exists to
// answer two questions on real hardware without adb:
//  1. Which devices are attached, and which one would Geidea's SDK pick?
//     (USBService.findSerialPortDevice walks getDeviceList() in list order and
//     takes the FIRST device for which the bundled serial library's
//     UsbSerialDevice.isSupported() is true — a known USB-serial chip or any
//     interface of class 10 / CDC data — then stops. Nothing is matched to
//     Geidea/PAX IDs. Confirmed by decompiling the SDK.)
//  2. Is this device acting as a USB host or as a USB peripheral (slave)?
object UsbInventory {
    fun report(context: Context): String {
        val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val sb = StringBuilder()

        val hostFeature = context.packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)
        val accessoryFeature = context.packageManager.hasSystemFeature(PackageManager.FEATURE_USB_ACCESSORY)
        sb.append("usb.host feature: $hostFeature, usb.accessory feature: $accessoryFeature\n")

        // Sticky broadcast, no receiver registered. connected=true means THIS
        // device's USB port is connected to a host, i.e. it is acting as the
        // peripheral (slave) — the opposite of what a kiosk needs.
        val state: Intent? = context.registerReceiver(null, IntentFilter("android.hardware.usb.action.USB_STATE"))
        if (state?.extras != null) {
            val e = state.extras!!
            sb.append("USB_STATE: " + e.keySet().sorted().joinToString(", ") { "$it=${e.get(it)}" } + "\n")
            val connected = e.getBoolean("connected", false)
            val hostConnected = e.getBoolean("host_connected", false)
            sb.append(
                when {
                    connected -> "ROLE: this device is acting as a USB PERIPHERAL (a host is attached to it)\n"
                    hostConnected -> "ROLE: this device is acting as a USB HOST\n"
                    else -> "ROLE: no USB peer connected in device mode\n"
                },
            )
        } else {
            sb.append("USB_STATE: not available\n")
        }

        val accessories = usb.accessoryList
        if (!accessories.isNullOrEmpty()) {
            sb.append("accessories: " + accessories.joinToString { "${it.manufacturer}/${it.model}" } + "\n")
        }

        val devices = usb.deviceList.values.toList()
        sb.append("attached devices: ${devices.size}\n")
        var sdkPick: UsbDevice? = null
        for (d in devices) {
            val serial = isSdkSerialDevice(d)
            if (serial && sdkPick == null) sdkPick = d
            val ifaces = (0 until d.interfaceCount).joinToString(" ") {
                val i = d.getInterface(it)
                "[c${i.interfaceClass}/s${i.interfaceSubclass}/p${i.interfaceProtocol} ep${i.endpointCount}]"
            }
            val names = try {
                listOfNotNull(d.manufacturerName, d.productName).joinToString(" ")
            } catch (_: Throwable) {
                ""
            }
            sb.append(
                String.format(
                    "  %s %04x:%04x devClass=%d perm=%s sdkSerial=%s %s %s\n",
                    d.deviceName, d.vendorId, d.productId, d.deviceClass,
                    usb.hasPermission(d), serial, names, ifaces,
                ),
            )
            if (serial) {
                appendInterfaceDetail(sb, d)
                appendPowerInfo(sb, d)
            }
        }
        sb.append(
            if (sdkPick != null) "Geidea SDK would pick (first sdkSerial=true in list order): ${sdkPick.deviceName} " +
                String.format("%04x:%04x", sdkPick.vendorId, sdkPick.productId) + "\n"
            else "Geidea SDK would find no serial device (it would report NO_USB)\n",
        )
        return sb.toString().trimEnd()
    }

    // One line per interface with its endpoints, marking the two the SDK's CDC
    // driver (felhr CDCSerialDevice) actually uses: the FIRST class-10 (CDC data)
    // interface for I/O and the FIRST class-2 (CDC control) interface for line
    // settings. A composite device with several CDC pairs only ever gets the first.
    private fun appendInterfaceDetail(sb: StringBuilder, d: UsbDevice) {
        val firstData = (0 until d.interfaceCount).firstOrNull { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_CDC_DATA }
        val firstControl = (0 until d.interfaceCount).firstOrNull { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_COMM }
        for (n in 0 until d.interfaceCount) {
            val i = d.getInterface(n)
            val eps = (0 until i.endpointCount).joinToString(" ") {
                val e = i.getEndpoint(it)
                String.format("0x%02X/type%d/%dB", e.address, e.type, e.maxPacketSize)
            }
            val mark = when (n) {
                firstData -> "  <-- SDK data channel (first class 10)"
                firstControl -> "  <-- SDK control interface (first class 2)"
                else -> ""
            }
            sb.append(
                String.format(
                    "      iface#%d id=%d class=%d/%d/%d endpoints: %s%s\n",
                    n, i.id, i.interfaceClass, i.interfaceSubclass, i.interfaceProtocol, eps.ifEmpty { "none" }, mark,
                ),
            )
        }
    }

    // Whether the tablet's kernel lets this port suspend when idle: the power
    // control, autosuspend delay and current runtime status of the terminal's
    // USB device. Read-only, a few tiny files; if the system hides them the
    // line just says so.
    private fun appendPowerInfo(sb: StringBuilder, d: UsbDevice) {
        try {
            val m = Regex("/dev/bus/usb/(\\d+)/(\\d+)").matchEntire(d.deviceName) ?: return
            val bus = m.groupValues[1].toInt()
            val dev = m.groupValues[2].toInt()
            val nodes = File("/sys/bus/usb/devices").listFiles()
            if (nodes == null) {
                sb.append("      power: /sys/bus/usb/devices not readable\n")
                return
            }
            val node = nodes.firstOrNull { readSys(File(it, "busnum")) == bus.toString() && readSys(File(it, "devnum")) == dev.toString() }
            if (node == null) {
                sb.append("      power: no sysfs entry found for this device\n")
                return
            }
            val p = File(node, "power")
            sb.append(
                "      power (sysfs ${node.name}): control=${readSys(File(p, "control"))} " +
                    "autosuspend_delay_ms=${readSys(File(p, "autosuspend_delay_ms"))} " +
                    "runtime_status=${readSys(File(p, "runtime_status"))}\n",
            )
        } catch (_: Throwable) {
            sb.append("      power: not readable\n")
        }
    }

    private fun readSys(f: File): String = try {
        f.readText().trim().ifEmpty { "?" }
    } catch (_: Throwable) {
        "?"
    }

    // The exact rule the SDK uses (UsbService.a -> UsbSerialDevice.isSupported).
    private fun isSdkSerialDevice(d: UsbDevice): Boolean = try {
        UsbSerialDevice.isSupported(d)
    } catch (_: Throwable) {
        (0 until d.interfaceCount).any { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_CDC_DATA }
    }
}
