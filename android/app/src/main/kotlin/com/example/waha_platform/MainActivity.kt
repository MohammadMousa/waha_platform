package com.example.waha_platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import java.io.File
import geidea.net.terminal_comm_api.Callback
import geidea.net.terminal_comm_api.GeideaSDK
import geidea.net.terminal_comm_api.TERMINAL_TRANSACTION_TYPES
import geidea.net.terminal_comm_api.TerminalDevice
import geidea.net.terminal_comm_api.TerminalResponder
import geidea.net.terminal_comm_api.USBConnectionListener
import geidea.net.terminal_comm_api.USBSerialConnectionException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Geidea USB Serial POS terminal bridge (waha-geidea-integration-specs.md).
 * No web API involved on this path — everything here talks to the SDK,
 * which talks to the terminal over USB; the terminal settles with Geidea's
 * own backend on its own. Waha's backend only ever sees the *result*,
 * reported separately over HTTP via the existing terminal-session
 * endpoints (see ApiClient.confirmTerminalSession in the Flutter app).
 *
 * Verified against the real net.geidea.sdk:pos-comm-sdk-ksa:1.3.0 binary
 * (decompiled with javap — the class names are obfuscated single letters
 * apart from the public API, so no source was available), not just the
 * spec docs, which both diverge from the real jar in places:
 *  - `Callback<T>` is a concrete class (extends Callable<T>), not a SAM
 *    interface — it must be subclassed with `object : Callback<Any?>()`,
 *    a bare trailing lambda does not work (the docs' Java sample reads
 *    like a lambda but is actually an anonymous inner class).
 *  - The purchase transaction type constant is
 *    `TERMINAL_TRANSACTION_TYPES.PURCHASE_TRANSACTION`, not `SALE`.
 *  - There is no USB-only `startCheckStatus` overload — only the TCP/IP
 *    4-arg one (`String ip, int port, TERMINAL_TRANSACTION_TYPES, Callback`)
 *    exists in this version. Confirmed via hardware testing this is not a
 *    missing overload to work around: `startCheckStatus` is TCP-only,
 *    full stop — calling it with empty ip/port silently hangs forever (it
 *    tries to open a TCP socket to nothing and the callback never fires).
 *    Geidea's own sample (SerialCableConnectionActivty) never calls this
 *    method for the USB flow at all — it just tracks a local
 *    `isUsbConnected` boolean from the USBConnectionListener callbacks.
 *    `checkCommunication()` below does the same.
 *  - Neither we nor Geidea's own sample retried `ERROR_NO_USB_ATTACHED`
 *    (only the permission-denied error was retried). On a real kiosk the
 *    app can start before the terminal is fully attached/enumerated, so a
 *    missed one-shot connect attempt meant "Terminal not connected" for
 *    the rest of the app's life. Detection now has three independent
 *    layers, deliberately non-overlapping in *when* they fire so they
 *    never fight each other over the same connection attempt:
 *     1. `usbAttachReceiver` — a runtime-registered BroadcastReceiver on
 *        `UsbManager.ACTION_USB_DEVICE_ATTACHED`. Event-driven, not
 *        polled: reacts the instant Android reports a new USB device,
 *        with zero idle cost while nothing changes. Handles the "cable
 *        plugged in while the app is already running" case, including
 *        replug after a disconnect. Registered in onStart/unregistered in
 *        onStop (must be a runtime receiver — Android 8+ blocks this
 *        intent for manifest-declared receivers).
 *     2. Bounded startup retry (`startupRetriesLeft`) — a same device
 *        that was already attached *before* this activity (and its
 *        receiver) ever started running fires no new attach broadcast,
 *        since nothing new got plugged in; same for a terminal that's
 *        still mid-boot and slower to come up than the kiosk app. Covers
 *        both with a few retries a short delay apart at startup only —
 *        NOT an indefinite background poll.
 *     3. `detectTerminal()` — an on-demand, explicit retry. Called both
 *        from Settings' "Detect Payment Terminals" test button and from
 *        the Dart side the moment a terminal payment is actually
 *        started (see GeideaTerminalBridge.detectTerminal), so any gap
 *        the first two layers somehow missed still gets one more try at
 *        the one moment it matters most to the customer.
 *    Every attempt from any of the three layers reports through
 *    `sendConnectionEvent`, including a "scanning" state that didn't
 *    exist before, so the Dart side can log/toast exactly what's
 *    happening (see GeideaUsbActivityLogger) instead of the app just
 *    going quiet while it works.
 */
class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.waha/geidea"
    private val EVENT_CHANNEL = "com.waha/geidea/events"
    private val TAG = "GeideaBridge"

    private var terminalResponder: TerminalResponder? = null
    private var connectionEventSink: EventChannel.EventSink? = null
    private var isUsbConnected: Boolean = false

    // Layer 1: event-driven attach detection — see class doc comment.
    private var receiverRegistered = false
    private val usbAttachReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != UsbManager.ACTION_USB_DEVICE_ATTACHED) return
            Log.d(TAG, "USB attach broadcast received")
            sendConnectionEvent("scanning", "USB device attached — connecting")
            tryConnect()
        }
    }

    // Layer 2: bounded startup retry — see class doc comment.
    private val startupRetryHandler = Handler(Looper.getMainLooper())
    private var startupRetriesLeft = 3
    private val startupRetryDelayMs = 10000L

    // Diagnostic-only, temporary: a tiny native-owned prefs store, separate
    // from Flutter's own SharedPreferences file, so logTrace() can check
    // this synchronously from onCreate/onStart — before Flutter/Dart has
    // necessarily run at all this launch. Dart tells this the current
    // effective value at startup and on every Settings toggle change (see
    // TraceLog.setEnabled) — persisted here, so it carries over correctly
    // from the previous launch onward. The one gap this can't close: a
    // brand-new install's very first-ever launch, before Dart has run even
    // once, defaults to the hardcoded `false` below.
    private fun loggingPrefs() = getSharedPreferences("waha_diagnostics", MODE_PRIVATE)
    private fun loggingEnabled() = loggingPrefs().getBoolean("logging_enabled", false)
    private fun setLoggingEnabled(enabled: Boolean) {
        loggingPrefs().edit().putBoolean("logging_enabled", enabled).apply()
    }

    /**
     * Diagnostic-only, temporary: writes a timestamped line to a plain text
     * file on external storage (readable via any file manager app without
     * adb — no cable/network access to the failing kiosk has worked so
     * far) AND to logcat, so a real device that crashes on startup still
     * leaves a trail of exactly how far it got. Every call is a fresh
     * open+append+close so the last line written survives even if the
     * process dies immediately after. No-ops entirely when loggingEnabled()
     * is false — see that function's doc comment; this app must not write
     * to disk on every kiosk in the field forever. Remove once the startup
     * crash is root-caused and fixed.
     */
    private fun logTrace(label: String) {
        if (!loggingEnabled()) return
        Log.e(TAG, "TRACE: $label")
        try {
            val dir = getExternalFilesDir(null) ?: filesDir
            File(dir, "waha_trace.log").appendText("${System.currentTimeMillis()} $label\n")
        } catch (e: Throwable) {
            // Best-effort only — never let logging itself be a new crash source.
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Diagnostic-only: catches any uncaught Kotlin/Java exception
        // anywhere on any thread, records it to waha_trace.log, then hands
        // off to the previous default handler so normal crash behavior
        // (Android's own crash dialog, process death) still happens
        // unchanged — this only adds a breadcrumb first. Does NOT catch a
        // genuine native (C/C++) crash, e.g. a graphics-driver segfault —
        // only JVM-level exceptions.
        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            logTrace("UNCAUGHT EXCEPTION on ${thread.name}: ${Log.getStackTraceString(throwable)}")
            previousHandler?.uncaughtException(thread, throwable)
        }
        logTrace("onCreate start")
        super.onCreate(savedInstanceState)
        logTrace("onCreate end")
    }

    override fun onStart() {
        logTrace("onStart start")
        super.onStart()
        if (!receiverRegistered) {
            ContextCompat.registerReceiver(
                this,
                usbAttachReceiver,
                IntentFilter(UsbManager.ACTION_USB_DEVICE_ATTACHED),
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
            receiverRegistered = true
        }
        logTrace("onStart end")
    }

    override fun onStop() {
        if (receiverRegistered) {
            unregisterReceiver(usbAttachReceiver)
            receiverRegistered = false
        }
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        logTrace("configureFlutterEngine start")
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initializeTerminal" -> {
                        initializeTerminal()
                        result.success(true)
                    }
                    "checkCommunication" -> checkCommunication { response ->
                        runOnUiThread { result.success(response) }
                    }
                    "detectTerminal" -> {
                        val source = call.argument<String>("source") ?: "manual"
                        detectTerminal(source)
                        result.success(true)
                    }
                    "logTrace" -> {
                        // Diagnostic-only: lets the Dart side (see
                        // lib/services/trace_log.dart) write into the same
                        // waha_trace.log as this class's own logTrace()
                        // calls, so a Flutter-level crash (e.g. a Navigator
                        // assertion) ends up in the same readable-without-
                        // adb log as native USB/lifecycle events.
                        val label = call.argument<String>("label") ?: ""
                        logTrace("DART: $label")
                        result.success(true)
                    }
                    "setLoggingEnabled" -> {
                        // Diagnostic-only: Dart tells us the current
                        // effective on/off state (dart-define OR Settings
                        // toggle — see TraceLog.setEnabled) so this
                        // persists natively and the earliest lines of the
                        // NEXT launch (before Dart can run) already know it.
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        setLoggingEnabled(enabled)
                        result.success(true)
                    }
                    "startPayment" -> {
                        val amount = call.argument<Double>("amount") ?: 0.0
                        val reference = call.argument<String>("reference") ?: ""
                        val isPrinterEnabled = call.argument<Boolean>("isPrinterEnabled") ?: false
                        startPayment(amount, reference, isPrinterEnabled) { response ->
                            runOnUiThread { result.success(response) }
                        }
                    }
                    "cancelPayment" -> {
                        // No in-flight-cancel call is documented by the SDK — a
                        // purchase transaction already handed to the terminal
                        // runs to completion regardless (see the Dart-side
                        // comment on GeideaTerminalBridge.cancelPayment / the
                        // Kiosk's own _cancel()). Acknowledged as a no-op.
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    connectionEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    connectionEventSink = null
                }
            })
        logTrace("configureFlutterEngine end")
    }

    private fun sendConnectionEvent(state: String, description: String? = null) {
        val sink = connectionEventSink ?: return
        runOnUiThread {
            sink.success(mapOf("state" to state, "description" to description))
        }
    }

    private fun initializeTerminal() {
        if (terminalResponder != null) return // already initialized
        logTrace("initializeTerminal start")
        // Confirmed against real hardware photo (mada A920Pro unit) — the
        // SDK only has two TerminalDevice constants (PAX_A920, OTHERS), no
        // separate "Pro" one, so this is the right constant for this unit.
        // Matches Geidea's own sample (GeideaApplication.java).
        //
        // Wrapped in try/catch(Throwable), diagnostic-only addition: this
        // whole block previously had zero exception handling, so any
        // exception the SDK itself throws here (e.g. a missing native .so
        // for the device's ABI, or a hardware-feature check failing on
        // non-phone hardware) would crash the entire app at startup with
        // no chance to even show "terminal not connected" instead. Turning
        // that into a graceful failure — connection event + breadcrumb, app
        // stays up — is strictly better regardless of whether this turns
        // out to be the actual root cause of the reported kiosk crash.
        try {
            logTrace("GeideaSDK.initialize start")
            GeideaSDK.initialize(this, TerminalDevice.PAX_A920)
            logTrace("GeideaSDK.initialize end")

            logTrace("getTerminalResponderInstance start")
            val responder = TerminalResponder.getTerminalResponderInstance(
                this,
                TerminalResponder.TYPE_USB_SERIAL_CONNECTION
            )
            terminalResponder = responder
            logTrace("getTerminalResponderInstance end")

            logTrace("openUsbSerialConnection start")
            responder.openUsbSerialConnection(buildUsbConnectionListener())
            logTrace("openUsbSerialConnection end")
        } catch (e: Throwable) {
            // If openUsbSerialConnection() throws partway through, the SDK's
            // internal receiver registration may never have completed even
            // though `terminalResponder` above is already assigned — leaving
            // it set would make onDestroy() call closeUsbSerialConnection()
            // on an object that isn't actually in a registered state (see
            // that function's own comment). Null it out so this responder is
            // never touched again; the next tryConnect() will just retry
            // initializeTerminal() from scratch.
            terminalResponder = null
            logTrace("initializeTerminal FAILED: ${Log.getStackTraceString(e)}")
            Log.e(TAG, "initializeTerminal failed", e)
            sendConnectionEvent("error", "Terminal init failed: ${e.message}")
        }
    }

    private fun buildUsbConnectionListener(): USBConnectionListener {
        return object : USBConnectionListener {
            override fun onUSBServiceConnected() {
                // This only means the SDK's background service is bound — it
                // is NOT the physical USB connection. Geidea's own sample
                // (SerialCableConnectionActivty.onUSBServiceConnected) shows
                // a second, separate call is required here to actually make
                // Android enumerate the device and prompt for permission;
                // without it, onUSBConnected() never fires.
                Log.d(TAG, "USB Service Connected")
                sendConnectionEvent("serviceConnected")
                sendConnectionEvent("scanning", "Checking for already-attached terminal")
                tryConnect()
            }

            override fun onUSBConnected() {
                Log.d(TAG, "USB Device Connected")
                isUsbConnected = true
                startupRetryHandler.removeCallbacksAndMessages(null)
                sendConnectionEvent("usbConnected")
            }

            override fun onUSBDisconnected() {
                Log.d(TAG, "USB Device Disconnected")
                isUsbConnected = false
                sendConnectionEvent("usbDisconnected")
                // No retry scheduled here on purpose — a genuine replug
                // fires usbAttachReceiver the instant it happens, so
                // polling for it here would just be redundant.
            }

            override fun onError(errorCode: Int, description: String) {
                Log.e(TAG, "USB error $errorCode: $description")
                isUsbConnected = false
                sendConnectionEvent("error", description)
                when (errorCode) {
                    TerminalResponder.ERROR_PERMISSION_NOT_GRANTED -> {
                        // Same retry Geidea's sample does: a denied/missed
                        // permission prompt surfaces as this specific error
                        // code, and retrying connectUsbSerialConnection()
                        // re-triggers the request. Safe to retry immediately —
                        // this only happens when a device is actually attached.
                        try {
                            terminalResponder?.connectUsbSerialConnection()
                        } catch (e: USBSerialConnectionException) {
                            Log.e(TAG, "connectUsbSerialConnection retry failed", e)
                        }
                    }
                    TerminalResponder.ERROR_NO_USB_ATTACHED -> {
                        // Bounded startup retry only — see class doc comment,
                        // layer 2. Live plug/unplug after this is handled
                        // entirely by usbAttachReceiver, not this loop.
                        if (startupRetriesLeft > 0) {
                            startupRetriesLeft--
                            val attempt = 3 - startupRetriesLeft
                            sendConnectionEvent("scanning", "Terminal not found yet, retry $attempt/3")
                            startupRetryHandler.postDelayed({ tryConnect() }, startupRetryDelayMs)
                        } else {
                            sendConnectionEvent(
                                "error",
                                "Terminal not found after startup retries — waiting for USB attach"
                            )
                        }
                    }
                }
            }
        }
    }

    /**
     * Shared "attempt a connection right now" used by every trigger: the
     * initial startup attempt, the bounded startup retries, the attach
     * broadcast receiver, and the manual/on-demand detectTerminal() calls.
     */
    private fun tryConnect() {
        val responder = terminalResponder
        if (responder == null) {
            initializeTerminal()
            return
        }
        try {
            responder.connectUsbSerialConnection()
        } catch (e: USBSerialConnectionException) {
            Log.e(TAG, "connectUsbSerialConnection failed", e)
        }
    }

    /**
     * Layer 3 (on-demand): [source] is "manual" for Settings' "Detect
     * Payment Terminals" test button, or "payment" when the Dart side
     * triggers this itself right as a terminal payment starts — only
     * changes the log text, not the behavior.
     */
    private fun detectTerminal(source: String) {
        val label = if (source == "payment") {
            "Payment started — checking terminal"
        } else {
            "Manual detect triggered"
        }
        sendConnectionEvent("scanning", label)
        tryConnect()
    }

    private fun checkCommunication(callback: (Map<String, Any?>) -> Unit) {
        // startCheckStatus is TCP-only (see class doc comment) — for USB,
        // "connected" is just whatever the USBConnectionListener last told
        // us, same as Geidea's own sample. No round-trip to the terminal.
        callback(mapOf("status" to if (isUsbConnected) "1" else "0"))
    }

    private fun startPayment(
        amount: Double,
        reference: String,
        isPrinterEnabled: Boolean,
        callback: (Map<String, Any?>) -> Unit
    ) {
        val responder = terminalResponder
        if (responder == null) {
            callback(mapOf("status" to "declined", "receipt" to "Terminal not initialized"))
            return
        }
        val responseCallback = object : Callback<Any?>() {
            override fun call(): Any? {
                @Suppress("UNCHECKED_CAST")
                val response = getParameter() as? Array<String> ?: emptyArray()
                val approved = response.getOrNull(0) == "1"
                val detailsJson = response.getOrNull(2)
                val details: Map<String, Any?> = if (approved && !detailsJson.isNullOrBlank()) {
                    try {
                        jsonObjectToMap(JSONObject(detailsJson))
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to parse transaction JSON", e)
                        emptyMap()
                    }
                } else {
                    emptyMap()
                }
                callback(mapOf(
                    "status" to (if (approved) "approved" else "declined"),
                    "receipt" to (response.getOrNull(1) ?: ""),
                    "details" to details,
                    "buffer" to (response.getOrNull(3) ?: "")
                ))
                return null
            }
        }
        responder.startPurchaseTransaction(
            TERMINAL_TRANSACTION_TYPES.PURCHASE_TRANSACTION,
            amount,
            reference,
            isPrinterEnabled,
            responseCallback
        )
    }

    private fun jsonObjectToMap(json: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        json.keys().forEach { key -> map[key] = json.get(key) }
        return map
    }

    override fun onDestroy() {
        startupRetryHandler.removeCallbacksAndMessages(null)
        // Defensive: closeUsbSerialConnection() unregisters a receiver the
        // SDK is expected to have registered in openUsbSerialConnection().
        // If that registration itself failed partway through (see the
        // catch block in initializeTerminal()), calling this would throw
        // IllegalArgumentException("Receiver not registered") — uncaught,
        // this crashes the app the moment it's backgrounded/destroyed.
        // initializeTerminal() already nulls terminalResponder on that
        // failure, so this null-check covers the normal case; the
        // try/catch is a second layer in case the SDK fails in some other
        // way we haven't seen yet.
        try {
            terminalResponder?.closeUsbSerialConnection()
        } catch (e: Throwable) {
            Log.e(TAG, "closeUsbSerialConnection failed", e)
        }
        super.onDestroy()
    }
}
