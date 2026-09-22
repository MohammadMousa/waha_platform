package com.example.waha_platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbManager
import androidx.core.content.ContextCompat
import com.felhr.usbserial.UsbSerialDevice
import geidea.net.terminal_comm_api.TerminalResponder
import geidea.net.terminal_comm_api.USBService
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.ArrayDeque

// Active detection tools for the Geidea USB path. The SDK hides almost
// everything (its "connected" flag is set on the permission broadcast, before
// the serial port opens; a write to a closed port is dropped without any
// error; it has no timeouts). These objects observe what it does underneath
// and probe the terminal directly, so a single build can say WHERE the
// communication stops:
//   A port never opens            B port opens but the write is dropped
//   C bytes written, no response  D terminal responds, SDK fails to decode
//   E status works, purchase fails  F purchase reaches terminal, terminal rejects
// Nothing here changes interface selection or any payment behaviour.

// ---- lifecycle milestones the SDK broadcasts but nobody listens to ----------

object UsbMilestones {
    class Event(val at: Long, val name: String, val detail: String)

    private val events = ArrayDeque<Event>()
    private var registered = false

    // SDK-internal broadcast actions (USBService / L.J receiver / felhr demo
    // service). USB_READY is sent by Q.run only AFTER UsbSerialDevice.open()
    // succeeded and the line settings were applied — it is the SDK's real
    // "serial port is open" signal. The two *_NOT_WORKING ones are sent when
    // open() fails and are handled by no SDK receiver at all.
    private val names = mapOf(
        "com.felhr.usbservice.USB_PERMISSION_GRANTED" to "PERMISSION_GRANTED",
        "com.felhr.usbservice.USB_PERMISSION_NOT_GRANTED" to "PERMISSION_DENIED",
        "com.felhr.connectivityservices.USB_READY" to "PORT_OPEN_OK",
        "com.felhr.connectivityservices.ACTION_CDC_DRIVER_NOT_WORKING" to "PORT_OPEN_FAILED_CDC",
        "com.felhr.connectivityservices.ACTION_USB_DEVICE_NOT_WORKING" to "PORT_OPEN_FAILED_DEVICE",
        "com.felhr.usbservice.USB_NOT_SUPPORTED" to "SERIAL_CREATE_FAILED",
        "com.felhr.usbservice.NO_USB" to "NO_SERIAL_DEVICE",
        "com.felhr.usbservice.USB_DISCONNECTED" to "SDK_USB_DISCONNECTED",
        "com.android.example.USB_PERMISSION" to "PERMISSION_RESULT",
        "android.hardware.usb.action.USB_DEVICE_ATTACHED" to "USB_ATTACHED",
        "android.hardware.usb.action.USB_DEVICE_DETACHED" to "USB_DETACHED",
    )

    fun add(name: String, detail: String = "", trace: ((String) -> Unit)? = null) {
        val e = Event(System.currentTimeMillis(), name, detail)
        synchronized(events) {
            events.addLast(e)
            while (events.size > 300) events.removeFirst()
        }
        trace?.invoke(("MILESTONE $name $detail").trim())
    }

    fun since(t: Long): List<Event> = synchronized(events) { events.filter { it.at >= t } }

    fun last(vararg n: String): Event? = synchronized(events) { events.lastOrNull { it.name in n } }

    fun count(name: String, since: Long = 0): Int = synchronized(events) { events.count { it.name == name && it.at >= since } }

    /** OPEN when the latest port event is PORT_OPEN_OK, else CLOSED:<why>, or UNKNOWN. */
    fun portState(): String {
        val ev = last(
            "PORT_OPEN_OK", "PORT_OPEN_FAILED_CDC", "PORT_OPEN_FAILED_DEVICE",
            "SERIAL_CREATE_FAILED", "NO_SERIAL_DEVICE", "SDK_USB_DISCONNECTED", "USB_DETACHED",
        ) ?: return "UNKNOWN (no port event seen)"
        return if (ev.name == "PORT_OPEN_OK") "OPEN" else "CLOSED:${ev.name}"
    }

    @Suppress("DEPRECATION")
    fun register(context: Context, trace: (String) -> Unit) {
        if (registered) return
        registered = true
        val filter = IntentFilter().also { f -> names.keys.forEach { f.addAction(it) } }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                val action = intent?.action ?: return
                val name = names[action] ?: return
                val detail = buildString {
                    val dev = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
                    if (dev != null) append("%s %04x:%04x".format(dev.deviceName, dev.vendorId, dev.productId))
                    if (intent.extras?.containsKey("permission") == true) append(" permission=${intent.extras?.getBoolean("permission")}")
                }
                add(name, detail, trace)
            }
        }
        ContextCompat.registerReceiver(context.applicationContext, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
    }
}

// ---- the SDK's own Android log lines -----------------------------------------

// The SDK's tags: FINAL BUFFER = command handed to the USB service for writing,
// DATA FROM USB = bytes received from the terminal, RESPONSE BUFFER = what it
// parsed, plus the felhr CDC driver's "Interface claimed / could not be
// claimed". An app can read only its OWN process's log, which is exactly where
// the SDK runs, so no permission is needed. Runs from app start regardless of
// the trace-logging switch (the on-screen tools need it); only the writes to
// waha_trace.log are gated, by [trace].
object SdkLogCapture {
    class Line(val at: Long, val tag: String, val msg: String)

    private val tags = setOf(
        "FINAL BUFFER", "DATA FROM USB", "RESPONSE BUFFER", "CONFIRMATION =", "EVENT MESSAGES =",
        "EVENT MESSAGES", "USB Service", "USBService", "Bind Result", "L", "SEE THE ACK OUTPUT",
        "LAST BYTE", "TRANSACTION STATUS", "RECONCILIATION BUFFER", "CDCSerialDevice",
        "UsbSerialDevice", "UsbSerialInterface", "System.out",
    )
    private val lineRegex = Regex("^([VDIWEF])/(.+?)\\(\\s*\\d+\\): (.*)$")
    private val recent = ArrayDeque<Line>()
    @Volatile private var process: Process? = null

    fun start(trace: (String) -> Unit) {
        if (process != null) return
        val t = Thread {
            // First try "-T 1" (follow, skipping history); if this logcat
            // rejects it and exits at once, follow with the full buffer.
            for (args in listOf(arrayOf("logcat", "-v", "brief", "-T", "1"), arrayOf("logcat", "-v", "brief"))) {
                val began = System.currentTimeMillis()
                try {
                    val p = Runtime.getRuntime().exec(args)
                    process = p
                    p.inputStream.bufferedReader().useLines { lines ->
                        for (raw in lines) {
                            val m = lineRegex.find(raw) ?: continue
                            val tag = m.groupValues[2].trim()
                            if (tag !in tags) continue
                            val msg = m.groupValues[3].take(600)
                            if (tag == "System.out" && !msg.startsWith("Hex Value")) continue
                            synchronized(recent) {
                                recent.addLast(Line(System.currentTimeMillis(), tag, msg))
                                while (recent.size > 400) recent.removeFirst()
                            }
                            trace("SDK[$tag] $msg")
                        }
                    }
                } catch (_: Throwable) {
                    // Best-effort observer — never a crash source.
                } finally {
                    process = null
                }
                if (System.currentTimeMillis() - began > 3000) break // ran normally, then stopped
            }
        }
        t.isDaemon = true
        t.name = "SdkLogCapture"
        t.start()
    }

    fun stop() {
        process?.destroy()
        process = null
    }

    fun linesSince(t: Long): List<Line> = synchronized(recent) { recent.filter { it.at >= t } }

    fun has(tag: String, since: Long): Boolean = synchronized(recent) { recent.any { it.tag == tag && it.at >= since } }

    fun recentLines(): String = synchronized(recent) {
        if (recent.isEmpty()) "SDKLOG (no SDK log lines captured yet)"
        else "SDKLOG last ${recent.size} lines:\n" + recent.joinToString("\n") { "${it.at % 100000000} [${it.tag}] ${it.msg}" }
    }
}

// ---- state, log file, probe, ladder, verdict ------------------------------------

object TerminalDiagnostics {

    // ---- SDK internal state (read-only reflection) --------------------------

    private fun field(obj: Any?, name: String): Any? {
        if (obj == null) return null
        var c: Class<*>? = obj.javaClass
        while (c != null) {
            try {
                val f = c.getDeclaredField(name)
                f.isAccessible = true
                return f.get(obj)
            } catch (_: NoSuchFieldException) {
                c = c.superclass
            }
        }
        throw NoSuchFieldException(name)
    }

    private fun safe(block: () -> Any?): String = try {
        block().toString()
    } catch (e: Throwable) {
        "n/a(${e.javaClass.simpleName})"
    }

    /**
     * What the SDK itself believes right now. `isUSBConnected` flips true on
     * the permission-granted broadcast, BEFORE the serial port is opened, so
     * it is NOT proof of communication — see [ladder] for the honest signals.
     */
    fun sdkState(responder: TerminalResponder?): String {
        if (responder == null) return "SDKSTATE responder=null (not initialised)"
        val conn = runCatching { field(responder, "usbConnection") }.getOrNull()
        return "SDKSTATE " +
            "isUSBConnected(flag only, NOT proof)=${safe { field(responder, "isUSBConnected") }} " +
            "terminalVerified=${safe { field(responder, "isTerminalVerifiedInSerialConnection") }} " +
            "connType=${safe { field(responder, "CONNECTION_TYPE") }} " +
            "txType=${safe { field(responder, "TRANSACTION_TYPE") }} " +
            "ecrRef=${safe { field(responder, "EcrReferenceNumber") }} " +
            "cbSet=${safe { field(responder, "generalCallBack") != null }} " +
            "serviceBound=${USBService.SERVICE_CONNECTED} " +
            "usbSvcMessenger=${safe { field(conn, "d") != null }} " +
            "respCb=${safe { field(conn, "f") != null }} " +
            "listener=${safe { field(conn, "g") != null }}"
    }

    // ---- the SDK's own log file --------------------------------------------

    // Path taken from the SDK's logger (a.d): <filesDir>/<f>, files end in .log.
    private const val SDK_LOG_SUBDIR = "za52BZx1qweDbat/az2wsxA5xZavet"

    /** Directory listing plus the tail of the newest SDK log file. */
    fun sdkLogFileTail(context: Context, maxBytes: Int = 5000): String {
        val dir = File(context.filesDir, SDK_LOG_SUBDIR)
        if (!dir.isDirectory) return "SDKLOGFILE none (dir ${dir.path} does not exist — SDK file logging not started)"
        val files = dir.listFiles()?.filter { it.isFile }?.sortedByDescending { it.lastModified() }.orEmpty()
        if (files.isEmpty()) return "SDKLOGFILE dir exists but has no files"
        val sb = StringBuilder()
        sb.append("SDKLOGFILE files: ")
        sb.append(files.take(5).joinToString { "${it.name}(${it.length()}B, ${(System.currentTimeMillis() - it.lastModified()) / 1000}s ago)" })
        sb.append('\n')
        val newest = files.first()
        try {
            val len = newest.length()
            java.io.RandomAccessFile(newest, "r").use { raf ->
                val start = maxOf(0L, len - maxBytes)
                raf.seek(start)
                val buf = ByteArray((len - start).toInt())
                raf.readFully(buf)
                sb.append("SDKLOGFILE tail of ${newest.name}:\n")
                sb.append(String(buf, Charsets.UTF_8).trimEnd())
            }
        } catch (e: Throwable) {
            sb.append("SDKLOGFILE read failed: ${e.javaClass.simpleName}: ${e.message}")
        }
        return sb.toString()
    }

    // ---- shared helpers ------------------------------------------------------

    /** The device the SDK would pick (first with UsbSerialDevice.isSupported). */
    fun sdkDevice(context: Context): UsbDevice? {
        val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
        return usb.deviceList.values.firstOrNull {
            try {
                UsbSerialDevice.isSupported(it)
            } catch (_: Throwable) {
                false
            }
        }
    }

    fun firstDataInterface(d: UsbDevice): Int? =
        (0 until d.interfaceCount).firstOrNull { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_CDC_DATA }

    private fun firstControlInterface(d: UsbDevice): Int =
        (0 until d.interfaceCount).firstOrNull { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_COMM } ?: 0

    fun hex(b: ByteArray) = if (b.isEmpty()) "none" else b.joinToString(" ") { "%02X".format(it) }

    /** Timeline of everything observed since [since]: milestones + SDK log lines + [extra] marks. */
    fun timeline(since: Long, extra: List<Pair<Long, String>> = emptyList()): String {
        val rows = ArrayList<Pair<Long, String>>()
        rows.addAll(extra)
        UsbMilestones.since(since).forEach { rows.add(it.at to "milestone ${it.name} ${it.detail}".trim()) }
        SdkLogCapture.linesSince(since).forEach { rows.add(it.at to "SDK[${it.tag}] ${it.msg.take(160)}") }
        return rows.sortedBy { it.first }.joinToString("\n") { "  +${it.first - since}ms  ${it.second}" }
    }

    // ---- raw channel probe (independent of the SDK, exact byte counts) -----------

    class ChannelResult(val iface: Int, val claimed: Boolean, val written: Int, val reply: ByteArray, val passive: ByteArray)
    class ProbeReport(val text: String, val channels: List<ChannelResult>)

    // CHECK_CONNECTION_BUFFER from TerminalResponder: 0100 | len 03 | FF0104 | LRC F9.
    private const val CHECK_FRAME_HEX = "010003FF0104F9"
    private fun hexToBytes(hex: String) = ByteArray(hex.length / 2) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    private fun readFor(conn: android.hardware.usb.UsbDeviceConnection, inEp: UsbEndpoint, ms: Long): ByteArray {
        val out = ByteArrayOutputStream()
        val buf = ByteArray(inEp.maxPacketSize.coerceAtLeast(64))
        val end = System.currentTimeMillis() + ms
        while (System.currentTimeMillis() < end) {
            val n = conn.bulkTransfer(inEp, buf, buf.size, 100)
            if (n > 0) out.write(buf, 0, n)
        }
        return out.toByteArray()
    }

    /**
     * Talks to EVERY CDC-data interface of the device the SDK would pick, one
     * at a time, replicating what the SDK's driver does when it opens a port
     * (claim interface with force, SET_LINE_CODING 115200 8N1, DTR|RTS), then
     * listens passively, writes the SDK's own check frame and listens again.
     * Uses raw bulk transfers so "bytes written" and "bytes received" are exact
     * counts, not assumptions. Blocking (~3 s per channel): background thread
     * only. The SDK must not hold the interfaces meanwhile, so [disconnectSdk]
     * runs first and [reconnectSdk] last.
     */
    fun probe(
        context: Context,
        disconnectSdk: () -> Unit,
        reconnectSdk: () -> Unit,
        trace: (String) -> Unit,
    ): ProbeReport {
        val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val out = StringBuilder()
        val results = ArrayList<ChannelResult>()
        fun say(line: String) {
            out.append(line).append('\n')
            trace("PROBE $line")
        }

        val device = sdkDevice(context)
        if (device == null) {
            say("No serial/CDC device attached — nothing to probe.")
            return ProbeReport(out.toString().trimEnd(), results)
        }
        say("Device ${device.deviceName} %04x:%04x hasPermission=${usb.hasPermission(device)}".format(device.vendorId, device.productId))
        if (!usb.hasPermission(device)) {
            say("No USB permission for this device — probe aborted.")
            return ProbeReport(out.toString().trimEnd(), results)
        }
        val dataIfaces = (0 until device.interfaceCount).filter { device.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_CDC_DATA }
        val ctrl = firstControlInterface(device)
        say("CDC data interfaces $dataIfaces; the SDK binds the FIRST (#${dataIfaces.firstOrNull()}); control interface used for line settings: #$ctrl")

        try {
            disconnectSdk()
        } catch (e: Throwable) {
            say("SDK disconnect threw ${e.javaClass.simpleName}: ${e.message} (continuing)")
        }
        Thread.sleep(800)

        try {
            for (idx in dataIfaces) {
                val iface = device.getInterface(idx)
                say("--- interface #$idx" + if (idx == dataIfaces.first()) " (the one the SDK uses)" else "")
                val conn = usb.openDevice(device)
                if (conn == null) {
                    say("openDevice() returned null")
                    results.add(ChannelResult(idx, false, -1, ByteArray(0), ByteArray(0)))
                    continue
                }
                try {
                    val claimed = conn.claimInterface(iface, true)
                    say("claimInterface(force)=$claimed")
                    var inEp: UsbEndpoint? = null
                    var outEp: UsbEndpoint? = null
                    for (e in 0 until iface.endpointCount) {
                        val ep = iface.getEndpoint(e)
                        if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                            if (ep.direction == UsbConstants.USB_DIR_IN) inEp = ep else outEp = ep
                        }
                    }
                    say("bulk IN=${inEp?.let { "0x%02X/%dB".format(it.address, it.maxPacketSize) }} OUT=${outEp?.let { "0x%02X/%dB".format(it.address, it.maxPacketSize) }}")
                    if (!claimed || inEp == null || outEp == null) {
                        say("=> port cannot be opened on this interface")
                        results.add(ChannelResult(idx, false, -1, ByteArray(0), ByteArray(0)))
                        continue
                    }
                    val lineCoding = byteArrayOf(0x00, 0xC2.toByte(), 0x01, 0x00, 0x00, 0x00, 0x08)
                    val r1 = conn.controlTransfer(0x21, 0x20, 0, ctrl, lineCoding, lineCoding.size, 2000)
                    val r2 = conn.controlTransfer(0x21, 0x22, 3, ctrl, null, 0, 2000)
                    say("SET_LINE_CODING(115200 8N1)=$r1  SET_CONTROL_LINE_STATE(DTR|RTS)=$r2  (negative = failed)")
                    val passive = readFor(conn, inEp, 500)
                    say("passive read 500ms: ${hex(passive)}")
                    val frame = hexToBytes(CHECK_FRAME_HEX)
                    val written = conn.bulkTransfer(outEp, frame, frame.size, 2000)
                    say("WROTE check frame ${hex(frame)}: bulkTransfer returned $written of ${frame.size} bytes")
                    val reply = readFor(conn, inEp, 2000)
                    say("reply within 2s: ${if (reply.isEmpty()) "NONE" else hex(reply)}")
                    results.add(ChannelResult(idx, true, written, reply, passive))
                    conn.controlTransfer(0x21, 0x22, 0, ctrl, null, 0, 1000)
                } catch (e: Throwable) {
                    say("probe error ${e.javaClass.simpleName}: ${e.message}")
                } finally {
                    try {
                        conn.releaseInterface(iface)
                        conn.close()
                    } catch (_: Throwable) {
                    }
                }
            }
        } finally {
            say("reconnecting the SDK…")
            try {
                reconnectSdk()
            } catch (e: Throwable) {
                say("SDK reconnect threw ${e.javaClass.simpleName}: ${e.message}")
            }
        }
        return ProbeReport(out.toString().trimEnd(), results)
    }

    // ---- the signal ladder: what is actually proven -------------------------------

    /**
     * The six distinct facts, each with its OWN evidence — never conflated:
     * permission, device detected, serial port opened, command written,
     * terminal response received, SDK callback received.
     */
    fun ladder(context: Context, since: Long, callbackReceived: Boolean?): String {
        val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val dev = sdkDevice(context)
        val sb = StringBuilder()
        sb.append("  1 USB device detected .......... ").append(if (dev != null) "YES %s %04x:%04x".format(dev.deviceName, dev.vendorId, dev.productId) else "NO (no serial/CDC device in the USB list)").append('\n')
        val perm = dev?.let { usb.hasPermission(it) }
        val grant = UsbMilestones.last("PERMISSION_GRANTED")
        sb.append("  2 USB permission ............... ").append(if (perm == true) "YES (system grants it)" else if (perm == false) "NO" else "n/a").append(if (grant != null) "; SDK saw the grant ${(System.currentTimeMillis() - grant.at) / 1000}s ago" else "; SDK grant broadcast not seen this run").append('\n')
        val ports = UsbMilestones.last(
            "PORT_OPEN_OK", "PORT_OPEN_FAILED_CDC", "PORT_OPEN_FAILED_DEVICE",
            "SERIAL_CREATE_FAILED", "NO_SERIAL_DEVICE", "SDK_USB_DISCONNECTED", "USB_DETACHED",
        )
        sb.append("  3 Serial port opened ........... ").append(UsbMilestones.portState())
        if (ports != null) sb.append(" (last event ${ports.name} ${(System.currentTimeMillis() - ports.at) / 1000}s ago)")
        sb.append("; opens OK=${UsbMilestones.count("PORT_OPEN_OK")} failed=${UsbMilestones.count("PORT_OPEN_FAILED_CDC") + UsbMilestones.count("PORT_OPEN_FAILED_DEVICE") + UsbMilestones.count("SERIAL_CREATE_FAILED")}\n")
        val handed = SdkLogCapture.has("FINAL BUFFER", since)
        sb.append("  4 Command written ............. ").append(if (handed) "YES — handed to the SDK's USB service for writing (SDK logs FINAL BUFFER). The SDK does not report the byte count; whether it reached the wire is inferred in the verdict." else "NO — the SDK produced no command in this window").append('\n')
        val bytes = SdkLogCapture.has("DATA FROM USB", since)
        sb.append("  5 Terminal response received .. ").append(if (bytes) "YES — bytes arrived from the terminal (SDK logs DATA FROM USB)" else "NO — no bytes from the terminal in this window").append('\n')
        sb.append("  6 SDK callback received ....... ").append(
            when (callbackReceived) {
                true -> "YES"
                false -> "NO (timed out)"
                null -> "n/a"
            },
        ).append('\n')
        return sb.toString().trimEnd()
    }

    // ---- verdicts -------------------------------------------------------------

    /** Classifies a status-request outcome (A–D). */
    fun statusVerdict(
        since: Long,
        status: String,
        message: String,
        probe: List<ChannelResult>?,
        sdkIface: Int?,
    ): String {
        val port = UsbMilestones.portState()
        if (!port.startsWith("OPEN")) {
            val why = port.removePrefix("CLOSED:")
            val detail = when {
                why.startsWith("PORT_OPEN_FAILED") -> "the SDK's UsbSerialDevice.open() failed (interface claim or endpoints) and the SDK ignores that failure"
                why == "SERIAL_CREATE_FAILED" -> "the SDK could not create a serial device for the selected USB device"
                why == "NO_SERIAL_DEVICE" -> "the SDK found no serial device"
                why.startsWith("UNKNOWN") -> "no port-open event was ever seen"
                else -> "the port was closed ($why)"
            }
            return "A. SERIAL PORT NEVER OPENED — $detail. (SDK's isUSBConnected can still say true.)"
        }
        val handed = SdkLogCapture.has("FINAL BUFFER", since)
        val bytes = SdkLogCapture.has("DATA FROM USB", since)
        return when (status) {
            "ok" -> "OK — port open, command written, terminal answered and the SDK decoded the reply. If a payment still fails, it is E or F: see the PAYMENT VERDICT lines in the trace log."
            "error" -> if (bytes) "D. TERMINAL RESPONDED but the SDK returned an error/could not use the reply: '$message'."
            else "SDK returned an error without any terminal bytes ('$message') — it rejected the request locally."
            else -> when {
                !handed -> "B0. The SDK never produced a command (no FINAL BUFFER) — it rejected/dropped the request before writing."
                bytes -> "D. TERMINAL BYTES ARRIVED (DATA FROM USB) but the SDK produced no callback — it could not decode the reply."
                else -> probeVerdict(probe, sdkIface)
            }
        }
    }

    /**
     * What the raw probe says once the SDK got no reply. The SDK uses ONE
     * channel only (the first CDC data interface, [sdkIface]), so that channel
     * gets its own line first; the others are context. Pure, so it is
     * unit-tested against the client's real probe results.
     */
    fun probeVerdict(probe: List<ChannelResult>?, sdkIface: Int?): String {
        if (probe == null) {
            return "B or C. Port open and command handed to the SDK, but no terminal bytes came back. Run the full diagnostic (raw probe) to separate a dropped write (B) from a silent terminal (C)."
        }
        val onSdk = probe.firstOrNull { it.iface == sdkIface }
        val others = probe.filter { it.iface != sdkIface }
        val othersLine = if (others.isEmpty()) "" else "\n  Other channels (context only, the SDK does not use them): " + others.joinToString("; ") { c ->
            "#${c.iface} " + when {
                !c.claimed -> "could not be opened"
                c.written < 0 -> "write FAILED"
                c.reply.isNotEmpty() -> "wrote ${c.written}B and REPLIED (${hex(c.reply)})"
                else -> "accepted ${c.written}B, no reply"
            }
        }
        val sdkLine = when {
            onSdk == null -> "SDK channel #$sdkIface: not probed."
            !onSdk.claimed -> "SDK channel #${onSdk.iface}: the probe could not open it (claim/endpoints failed)."
            onSdk.written < 0 -> "SDK channel #${onSdk.iface}: our direct write FAILED (bulk OUT returned ${onSdk.written}, it timed out) — the terminal does not accept data on the channel the SDK uses."
            onSdk.reply.isNotEmpty() -> "SDK channel #${onSdk.iface}: the terminal ANSWERED our direct write (${hex(onSdk.reply)})."
            else -> "SDK channel #${onSdk.iface}: our write was accepted (${onSdk.written}B) but the terminal did not answer."
        }
        val head = when {
            onSdk == null -> "A/B. The SDK's channel could not be probed."
            !onSdk.claimed -> "A. THE SDK'S CHANNEL CANNOT BE OPENED by the probe."
            onSdk.written < 0 -> "B. THE SDK'S WRITE CANNOT REACH THE TERMINAL — the write fails on the SDK's own channel, so its payment/status commands are never delivered."
            onSdk.reply.isNotEmpty() -> "B. WRITE DROPPED — the terminal answers a direct write on the SDK's channel, but the SDK's identical command got nothing; the SDK's port object is not the open one."
            others.any { it.reply.isNotEmpty() } -> "C. WRONG CHANNEL — the terminal answers only on interface #${others.first { it.reply.isNotEmpty() }.iface}, not on #${onSdk.iface} which the SDK binds."
            else -> "C. BYTES WRITTEN, NO TERMINAL RESPONSE on the SDK's channel — the terminal accepted the bytes but is not in a state/mode that answers this protocol."
        }
        return "$head\n  $sdkLine$othersLine"
    }

    /** Classifies one real purchase attempt (E/F, or where it stopped). */
    fun paymentVerdict(since: Long, callbackReceived: Boolean, status: String?, code: String?, statusHandshakeOk: Boolean?): String {
        val handed = SdkLogCapture.has("FINAL BUFFER", since)
        val bytes = SdkLogCapture.has("DATA FROM USB", since)
        val port = UsbMilestones.portState()
        return when {
            !handed && callbackReceived -> "Rejected locally by the SDK before any USB write (code=$code) — nothing reached the terminal."
            !handed -> "The SDK never produced the purchase command (no FINAL BUFFER). Port state: $port."
            !bytes && !callbackReceived ->
                (if (statusHandshakeOk == true) "E. STATUS WORKED EARLIER BUT THE PURCHASE GOT NO TERMINAL RESPONSE" else "B/C. PURCHASE COMMAND HANDED TO THE SDK, NO TERMINAL BYTES BACK") +
                    " — port state $port. Run 'Run Full Geidea Diagnostic' to separate a dropped write from a silent terminal."
            bytes && callbackReceived && status == "approved" -> "Purchase approved."
            bytes && callbackReceived -> "F. THE TERMINAL RESPONDED TO THE PURCHASE and it (or the SDK) reports failure: status=$status code/receipt=$code."
            bytes -> "D. TERMINAL BYTES ARRIVED for the purchase but the SDK produced no callback."
            else -> "Purchase ended without terminal bytes (callback=$callbackReceived status=$status code=$code)."
        }
    }
}
