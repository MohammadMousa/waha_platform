package com.example.waha_platform

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import androidx.core.content.ContextCompat
import com.waha.link.ErrorCode
import com.waha.link.FrameCodec
import com.waha.link.FrameDecoder
import com.waha.link.LinkMessage
import com.waha.link.LinkMessages
import com.waha.link.LinkProtocolException
import com.waha.link.MsgType
import com.waha.link.Status
import com.waha.link.WahaLink
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

// Failures that only exist on the host side (AOA bring-up / device discovery).
// The shared ErrorCode list in WahaLinkProtocol.kt stays the wire-level set.
object HostError {
    const val NO_DEVICE = "NO_DEVICE"
    const val MULTIPLE_DEVICES = "MULTIPLE_DEVICES"
    const val OPEN_FAILED = "OPEN_FAILED"
    const val NO_ENDPOINTS = "NO_ENDPOINTS"
    const val AOA_UNSUPPORTED = "AOA_UNSUPPORTED"
    const val AOA_NO_REENUMERATION = "AOA_NO_REENUMERATION"
}

class LinkResult(
    val ok: Boolean,
    val status: String? = null,
    val errorCode: String? = null,
    val message: String? = null,
    val approvalCode: String? = null,
    val details: JSONObject? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "ok" to ok,
        "status" to status,
        "errorCode" to errorCode,
        "message" to message,
        "approvalCode" to approvalCode,
        "details" to details?.let { jsonToMap(it) },
    )

    companion object {
        fun ok(): LinkResult = LinkResult(true)
        fun fail(code: String, message: String? = null): LinkResult =
            LinkResult(false, status = Status.ERROR, errorCode = code, message = message)

        private fun jsonToMap(o: JSONObject): Map<String, Any?> {
            val m = HashMap<String, Any?>()
            o.keys().forEach { k -> m[k] = unwrap(o.opt(k)) }
            return m
        }

        private fun unwrap(v: Any?): Any? = when (v) {
            null, JSONObject.NULL -> null
            is JSONObject -> jsonToMap(v)
            is JSONArray -> (0 until v.length()).map { unwrap(v.opt(it)) }
            else -> v
        }
    }
}

// USB HOST side of the Waha kiosk <-> Waha Terminal link. Mirrors the shape
// of the Geidea integration (kiosk is host, terminal is the device, kiosk
// drives every step) but is entirely generic — Android platform APIs only:
// AOA handshake to switch the terminal phone into accessory mode, then
// length-prefixed JSON frames over its bulk endpoints (see
// com.waha.link.WahaLinkProtocol).
//
// Deliberately passive: nothing here touches USB until Dart calls connect().
// It never runs unless the internal "Waha POS over USB" setting is on. It
// refuses to poke a device when more than one non-hub USB device is attached
// (MULTIPLE_DEVICES) so it cannot send AOA requests to something else — e.g.
// a Geidea terminal — that happens to be plugged in alongside.
//
// Lessons carried over from the Geidea integration:
//  - connection state is derived live, never trusted from a cached flag;
//  - connect() always tears down and reconnects fresh;
//  - detach or a write failure tears down immediately (idempotent, every
//    close in try/catch, references nulled);
//  - PendingIntent is FLAG_IMMUTABLE with an explicit intent, and permission
//    is re-checked live via hasPermission() instead of reading
//    EXTRA_PERMISSION_GRANTED (missing/false on an immutable PendingIntent);
//  - receivers registered via ContextCompat with RECEIVER_NOT_EXPORTED;
//  - one distinct error code per failure.
class WahaUsbHost(
    private val context: Context,
    private val trace: (String) -> Unit,
    private val emit: (state: String, code: String?, description: String?) -> Unit,
) {
    companion object {
        private const val ACTION_PERMISSION = "com.example.waha_platform.WAHA_LINK_USB_PERMISSION"
        private const val AOA_VID = 0x18D1
        private val AOA_PIDS = setOf(0x2D00, 0x2D01, 0x2D04, 0x2D05)
        private const val AOA_GET_PROTOCOL = 51
        private const val AOA_SEND_STRING = 52
        private const val AOA_START = 53
        private const val CHUNK = 16384
        // A first bring-up needs a human to accept the "open Waha Terminal for
        // this accessory" prompt on the terminal phone, so the terminal app
        // can open its side well after ours. Re-send our hello while waiting
        // (one sent before the terminal started reading can be lost).
        private const val HELLO_TIMEOUT_MS = 15000L
        private const val HELLO_RESEND_MS = 3000L
    }

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager

    private val opLock = Any()
    private val stateLock = Any()
    private val writeLock = Any()

    @Volatile private var conn: UsbDeviceConnection? = null
    @Volatile private var dev: UsbDevice? = null
    @Volatile private var iface: UsbInterface? = null
    @Volatile private var epIn: UsbEndpoint? = null
    @Volatile private var epOut: UsbEndpoint? = null
    @Volatile private var running = false
    @Volatile private var peerHello: LinkMessage? = null
    @Volatile private var helloLatch = CountDownLatch(1)
    @Volatile private var permissionLatch: CountDownLatch? = null
    private val busy = AtomicBoolean(false)
    @Volatile private var generation = 0
    @Volatile private var cancelSentAt = 0L
    @Volatile private var receiversRegistered = false

    private val pendingPings = ConcurrentHashMap<String, CountDownLatch>()
    private val responses = LinkedBlockingQueue<LinkMessage>()

    private val receiver = object : BroadcastReceiver() {
        @Suppress("DEPRECATION")
        override fun onReceive(c: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val d = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
                    trace("USB detached ${d?.deviceName}")
                    // Only our current link matters. The original phone also
                    // detaches during AOA re-enumeration, but by then we hold
                    // no state for it.
                    if (d != null && d.deviceName == dev?.deviceName) {
                        teardown("detached")
                        emit("usbDisconnected", null, "Terminal disconnected")
                    }
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    val d = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
                    trace("USB attached ${d?.deviceName} vid=${d?.vendorId} pid=${d?.productId}")
                }
                ACTION_PERMISSION -> permissionLatch?.countDown()
            }
        }
    }

    fun start() {
        if (receiversRegistered) return
        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(ACTION_PERMISSION)
        }
        ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        receiversRegistered = true
        trace("host started")
    }

    fun stop() {
        teardown("stop")
        if (receiversRegistered) {
            try { context.unregisterReceiver(receiver) } catch (_: Throwable) {}
            receiversRegistered = false
        }
        trace("host stopped")
    }

    // Live, never cached: the link object must exist, the hello exchange must
    // have completed, and the device must still be physically enumerated.
    fun isConnected(): Boolean {
        val d = dev ?: return false
        if (conn == null || !running || peerHello == null) return false
        return usbManager.deviceList.values.any { it.deviceName == d.deviceName }
    }

    // ── connect ──────────────────────────────────────────────────────────────

    fun connect(): LinkResult = synchronized(opLock) { connectLocked() }

    private fun connectLocked(): LinkResult {
        teardown("reconnect") // never trust old state
        emit("scanning", null, "Looking for Waha terminal…")

        // Always log everything attached — a real kiosk carries built-in USB
        // devices (barcode scanner, hubs, touch controller), so this is the
        // first thing to read when a link does not come up.
        val attached = usbManager.deviceList.values.toList()
        trace("attached devices: " + attached.joinToString { describe(it) }.ifEmpty { "none" })

        var accessory = findAccessoryDevice()
        if (accessory == null) {
            // Only consider devices that could plausibly be a phone. Built-in
            // kiosk peripherals (HID scanners/keyboards, printers, hubs,
            // smart-card readers) are never sent AOA requests.
            val candidates = attached.filter { isPhoneCandidate(it) }
            if (candidates.isEmpty()) {
                return failEmit(
                    HostError.NO_DEVICE,
                    "No phone-like USB device found. Attached: " + attached.joinToString { label(it) }.ifEmpty { "nothing" },
                )
            }
            if (candidates.size > 1) {
                return failEmit(
                    HostError.MULTIPLE_DEVICES,
                    "More than one possible terminal attached (" + candidates.joinToString { label(it) } +
                        ") — unplug all but the terminal phone so AOA is not sent to the wrong device",
                )
            }
            val started = startAccessoryMode(candidates[0])
            if (!started.ok) return started
            accessory = waitForAccessoryDevice(6000)
                ?: return failEmit(
                    HostError.AOA_NO_REENUMERATION,
                    "AOA start was sent but the phone never re-enumerated as an accessory — " +
                        "check USB roles (this device must be host) and that Waha Terminal is installed",
                )
        }
        return openAccessoryDevice(accessory)
    }

    private fun label(d: UsbDevice): String = String.format("%04x:%04x", d.vendorId, d.productId)

    private fun describe(d: UsbDevice): String {
        val classes = (0 until d.interfaceCount).joinToString("/") { d.getInterface(it).interfaceClass.toString() }
        return "${label(d)} devClass=${d.deviceClass} ifaceClasses=[$classes]"
    }

    private fun isPhoneCandidate(d: UsbDevice): Boolean {
        if (d.deviceClass == UsbConstants.USB_CLASS_HUB) return false
        for (i in 0 until d.interfaceCount) {
            when (d.getInterface(i).interfaceClass) {
                UsbConstants.USB_CLASS_HID, UsbConstants.USB_CLASS_PRINTER,
                UsbConstants.USB_CLASS_HUB, UsbConstants.USB_CLASS_CSCID -> return false
            }
        }
        return true
    }

    private fun findAccessoryDevice(): UsbDevice? =
        usbManager.deviceList.values.firstOrNull { it.vendorId == AOA_VID && it.productId in AOA_PIDS }

    private fun waitForAccessoryDevice(timeoutMs: Long): UsbDevice? {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            findAccessoryDevice()?.let { return it }
            Thread.sleep(200)
        }
        return null
    }

    private fun ensurePermission(d: UsbDevice): Boolean {
        if (usbManager.hasPermission(d)) return true
        val latch = CountDownLatch(1)
        permissionLatch = latch
        emit("permissionRequested", null, "Waiting for USB permission…")
        val pi = PendingIntent.getBroadcast(
            context, 0,
            Intent(ACTION_PERMISSION).setPackage(context.packageName),
            PendingIntent.FLAG_IMMUTABLE,
        )
        usbManager.requestPermission(d, pi)
        latch.await(60, TimeUnit.SECONDS)
        permissionLatch = null
        // Live re-check — do not read EXTRA_PERMISSION_GRANTED.
        val granted = usbManager.hasPermission(d)
        trace("permission for ${d.deviceName}: $granted")
        return granted
    }

    // AOA handshake (Android Open Accessory protocol 1+): read the protocol
    // version, send the identifying strings, then the start request. On
    // success the phone drops off the bus and re-enumerates as 0x18D1/0x2D00.
    private fun startAccessoryMode(target: UsbDevice): LinkResult {
        if (!ensurePermission(target)) {
            return failEmit(ErrorCode.PERMISSION_DENIED, "USB permission was not granted")
        }
        val c = usbManager.openDevice(target)
            ?: return failEmit(HostError.OPEN_FAILED, "Could not open USB device")
        try {
            val buf = ByteArray(2)
            val n = c.controlTransfer(
                UsbConstants.USB_DIR_IN or UsbConstants.USB_TYPE_VENDOR, AOA_GET_PROTOCOL, 0, 0, buf, 2, 2000,
            )
            if (n != 2) return failEmit(HostError.AOA_UNSUPPORTED, "Device did not answer the AOA protocol query")
            val version = ((buf[1].toInt() and 0xFF) shl 8) or (buf[0].toInt() and 0xFF)
            trace("AOA protocol version $version")
            if (version < 1) return failEmit(HostError.AOA_UNSUPPORTED, "AOA protocol version $version < 1")

            val strings = listOf(
                WahaLink.ACCESSORY_MANUFACTURER, WahaLink.ACCESSORY_MODEL,
                "Waha Terminal link", WahaLink.ACCESSORY_VERSION, "https://waha.local", "0001",
            )
            for ((index, s) in strings.withIndex()) {
                val bytes = (s + " ").toByteArray(Charsets.UTF_8)
                val r = c.controlTransfer(
                    UsbConstants.USB_DIR_OUT or UsbConstants.USB_TYPE_VENDOR,
                    AOA_SEND_STRING, 0, index, bytes, bytes.size, 2000,
                )
                if (r < 0) return failEmit(HostError.AOA_UNSUPPORTED, "AOA string $index rejected")
            }
            val r = c.controlTransfer(
                UsbConstants.USB_DIR_OUT or UsbConstants.USB_TYPE_VENDOR, AOA_START, 0, 0, null, 0, 2000,
            )
            if (r < 0) return failEmit(HostError.AOA_UNSUPPORTED, "AOA start request rejected")
            emit("aoaStarted", null, "Accessory mode requested")
            trace("AOA start sent")
            return LinkResult.ok()
        } finally {
            try { c.close() } catch (_: Throwable) {}
        }
    }

    private fun openAccessoryDevice(d: UsbDevice): LinkResult {
        if (!ensurePermission(d)) {
            return failEmit(ErrorCode.PERMISSION_DENIED, "USB permission was not granted")
        }
        var chosen: UsbInterface? = null
        var inEp: UsbEndpoint? = null
        var outEp: UsbEndpoint? = null
        for (i in 0 until d.interfaceCount) {
            val itf = d.getInterface(i)
            // Skip the ADB interface some accessory PIDs expose alongside.
            if (itf.interfaceClass == 0xFF && itf.interfaceSubclass == 0x42) continue
            var bi: UsbEndpoint? = null
            var bo: UsbEndpoint? = null
            for (e in 0 until itf.endpointCount) {
                val ep = itf.getEndpoint(e)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                    if (ep.direction == UsbConstants.USB_DIR_IN) bi = ep else bo = ep
                }
            }
            if (bi != null && bo != null) { chosen = itf; inEp = bi; outEp = bo; break }
        }
        if (chosen == null) return failEmit(HostError.NO_ENDPOINTS, "Accessory has no bulk IN/OUT interface")

        val c = usbManager.openDevice(d) ?: return failEmit(HostError.OPEN_FAILED, "Could not open accessory device")
        if (!c.claimInterface(chosen, true)) {
            try { c.close() } catch (_: Throwable) {}
            return failEmit(HostError.OPEN_FAILED, "claimInterface failed")
        }

        val decoder = FrameDecoder()
        var myGeneration = 0
        synchronized(stateLock) {
            conn = c; dev = d; iface = chosen; epIn = inEp; epOut = outEp
            peerHello = null
            helloLatch = CountDownLatch(1)
            responses.clear()
            running = true
            generation += 1
            myGeneration = generation
        }
        Thread({ readLoop(decoder, myGeneration) }, "WahaLinkReader").apply { isDaemon = true }.start()
        trace("accessory opened ${d.deviceName}")
        emit("usbConnected", null, "Accessory link opened")

        emit("awaitingTerminal", null, "Waiting for Waha Terminal — accept the prompt on the terminal phone if shown")
        val helloDeadline = System.currentTimeMillis() + HELLO_TIMEOUT_MS
        var lastHelloSent = 0L
        while (peerHello == null && running && System.currentTimeMillis() < helloDeadline) {
            val now = System.currentTimeMillis()
            if (now - lastHelloSent >= HELLO_RESEND_MS) {
                if (!send(LinkMessages.hello(WahaLink.APP_KIOSK))) {
                    teardown("hello write failed")
                    return failEmit(ErrorCode.WRITE_FAILED, "Could not send hello")
                }
                trace("hello sent")
                lastHelloSent = now
            }
            helloLatch.await(200, TimeUnit.MILLISECONDS)
        }
        val hello = peerHello
        if (hello == null) {
            val gone = !running
            teardown("no hello")
            return failEmit(
                ErrorCode.NOT_CONNECTED,
                if (gone) "Link closed before the terminal answered hello"
                else "Terminal app did not answer hello within ${HELLO_TIMEOUT_MS / 1000}s — is Waha Terminal open and set to USB?",
            )
        }
        if (hello.protocol != WahaLink.PROTOCOL_VERSION || hello.app != WahaLink.APP_TERMINAL) {
            teardown("bad hello")
            return failEmit(
                ErrorCode.UNSUPPORTED_VERSION,
                "Terminal speaks protocol ${hello.protocol} (app ${hello.app}), kiosk speaks ${WahaLink.PROTOCOL_VERSION}",
            )
        }
        emit("ready", null, "Terminal ready")
        trace("link ready")
        return LinkResult.ok()
    }

    // ── IO ───────────────────────────────────────────────────────────────────

    // [gen] ties this reader to one specific link. teardown() bumps the
    // generation, so a reader left over from a previous link exits on its next
    // iteration even if a new connect() has already set running = true again.
    private fun readLoop(decoder: FrameDecoder, gen: Int) {
        val buf = ByteArray(CHUNK)
        while (running && gen == generation) {
            val c = conn ?: break
            val ep = epIn ?: break
            val n = c.bulkTransfer(ep, buf, buf.size, 1000)
            if (n > 0) {
                try {
                    for (json in decoder.feed(buf, n)) handleFrame(LinkMessages.parse(json))
                } catch (e: LinkProtocolException) {
                    trace("protocol error: ${e.message}")
                    teardown("protocol error")
                    emit("error", ErrorCode.INVALID_RESPONSE, e.message)
                    break
                }
            } else if (n < 0 && running && gen == generation && !physicallyPresent()) {
                teardown("device gone")
                emit("usbDisconnected", null, "Terminal disconnected")
                break
            }
            // n < 0 with the device still present is an ordinary read timeout.
        }
    }

    private fun physicallyPresent(): Boolean {
        val d = dev ?: return false
        return usbManager.deviceList.values.any { it.deviceName == d.deviceName }
    }

    private fun handleFrame(msg: LinkMessage) {
        trace("rx ${msg.type}${msg.reference?.let { " ref=$it" } ?: ""}")
        when (msg.type) {
            MsgType.HELLO -> { peerHello = msg; helloLatch.countDown() }
            MsgType.PING -> send(LinkMessages.pong(msg.id))
            MsgType.PONG -> pendingPings.remove(msg.id)?.countDown()
            MsgType.PAYMENT_RESPONSE -> responses.offer(msg)
            else -> trace("ignored unexpected ${msg.type} from terminal")
        }
    }

    private fun send(json: JSONObject): Boolean {
        val bytes = try { FrameCodec.encode(json) } catch (e: LinkProtocolException) { return false }
        synchronized(writeLock) {
            val c = conn
            val ep = epOut
            if (c == null || ep == null) return false
            var offset = 0
            while (offset < bytes.size) {
                val n = c.bulkTransfer(ep, bytes, offset, minOf(bytes.size - offset, CHUNK), 2000)
                if (n <= 0) return false
                offset += n
            }
        }
        return true
    }

    // Idempotent. Every close is in try/catch and every reference is nulled so
    // a half-torn-down link can never be mistaken for a live one.
    private fun teardown(reason: String) {
        synchronized(stateLock) {
            val c = conn
            running = false
            generation += 1
            if (c == null) return
            trace("teardown: $reason")
            try { iface?.let { c.releaseInterface(it) } } catch (_: Throwable) {}
            try { c.close() } catch (_: Throwable) {}
            conn = null; dev = null; iface = null; epIn = null; epOut = null
            peerHello = null
            pendingPings.values.forEach { it.countDown() }
            pendingPings.clear()
            responses.offer(LinkMessage("closed", "closed", JSONObject()))
            helloLatch.countDown()
        }
    }

    private fun failEmit(code: String, message: String): LinkResult {
        trace("failure $code: $message")
        emit("error", code, message)
        return LinkResult.fail(code, message)
    }

    // ── payment ──────────────────────────────────────────────────────────────

    fun requestPayment(reference: String, amount: Double, currency: String, timeoutMs: Long): LinkResult {
        if (!busy.compareAndSet(false, true)) {
            return LinkResult.fail(ErrorCode.BUSY, "A payment is already in flight")
        }
        try {
            synchronized(opLock) { return requestPaymentLocked(reference, amount, currency, timeoutMs) }
        } finally {
            busy.set(false)
        }
    }

    private fun requestPaymentLocked(reference: String, amount: Double, currency: String, timeoutMs: Long): LinkResult {
        if (!isConnected()) return LinkResult.fail(ErrorCode.NOT_CONNECTED, "Link is not connected")
        responses.clear()
        cancelSentAt = 0L

        // Live end-to-end probe before EVERY payment — replaces Geidea's
        // cached-flag check with a real round trip to the terminal app.
        val pingId = WahaLink.newId()
        val pong = CountDownLatch(1)
        pendingPings[pingId] = pong
        if (!send(LinkMessages.ping(pingId))) {
            pendingPings.remove(pingId)
            teardown("ping write failed")
            return LinkResult.fail(ErrorCode.WRITE_FAILED, "Could not send liveness probe")
        }
        if (!pong.await(2, TimeUnit.SECONDS) || !isConnected()) {
            pendingPings.remove(pingId)
            teardown("liveness probe failed")
            return LinkResult.fail(ErrorCode.NOT_CONNECTED, "Terminal did not answer the liveness probe")
        }

        val request = LinkMessages.paymentRequest(reference, WahaLink.formatAmount(amount), currency)
        if (!send(request)) {
            teardown("request write failed")
            return LinkResult.fail(ErrorCode.WRITE_FAILED, "Could not send payment request")
        }
        trace("payment request sent ref=$reference")

        val deadline = System.currentTimeMillis() + timeoutMs
        var timedOut = false
        var cancelDeadline = 0L // when to stop waiting for the terminal's answer to a cancel
        while (true) {
            val now = System.currentTimeMillis()
            // A user cancel (cancel()) sets cancelSentAt from another thread.
            if (cancelSentAt != 0L && cancelDeadline == 0L) cancelDeadline = cancelSentAt + 3000
            // Kiosk owns the payment timeout: tell the terminal to stop, then
            // give it a short grace period to answer.
            if (!timedOut && cancelSentAt == 0L && now >= deadline) {
                timedOut = true
                cancelSentAt = now
                cancelDeadline = now + 3000
                send(LinkMessages.cancel(reference))
                trace("payment timeout, cancel sent ref=$reference")
            }
            if (cancelDeadline != 0L && now >= cancelDeadline) {
                return if (timedOut) LinkResult.fail(ErrorCode.TIMEOUT, "Terminal did not answer in time")
                else LinkResult(false, Status.CANCELLED, ErrorCode.CANCELLED, "Cancelled")
            }
            val m = responses.poll(300, TimeUnit.MILLISECONDS) ?: continue
            if (m.type == "closed") return LinkResult.fail(ErrorCode.NOT_CONNECTED, "Link closed during payment")
            if (m.reference != reference) {
                trace("dropped late response for ${m.reference}")
                continue
            }
            trace("payment response ref=$reference status=${m.status}")
            // Approved always wins — the card may have been charged just as
            // the timeout/cancel fired.
            return when (m.status) {
                Status.APPROVED -> LinkResult(true, Status.APPROVED, null, m.message, m.approvalCode, m.details)
                Status.CANCELLED ->
                    if (timedOut) LinkResult.fail(ErrorCode.TIMEOUT, "Payment timed out")
                    else LinkResult(false, Status.CANCELLED, ErrorCode.CANCELLED, m.message)
                else -> LinkResult(false, m.status, m.errorCode, m.message, null, m.details)
            }
        }
    }

    fun cancel(reference: String) {
        if (!isConnected()) return
        cancelSentAt = System.currentTimeMillis()
        trace("cancel requested ref=$reference")
        send(LinkMessages.cancel(reference))
    }
}
