package com.example.waha_platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbManager
import android.os.Bundle
import android.os.Handler
import android.os.Build
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import geidea.net.terminal_comm_api.Callback
import geidea.net.terminal_comm_api.GeideaSDK
import geidea.net.terminal_comm_api.TERMINAL_TRANSACTION_TYPES
import geidea.net.terminal_comm_api.TerminalDevice
import geidea.net.terminal_comm_api.TerminalResponder
import geidea.net.terminal_comm_api.USBConnectionListener
import geidea.net.terminal_comm_api.USBService
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
 *  - There is no USB-only `startCheckStatus` overload — only the 4-arg
 *    `(String ip, int port, TERMINAL_TRANSACTION_TYPES, Callback)` one. An
 *    earlier version of this comment claimed it is TCP-only and "hangs
 *    forever" for USB. Decompiling the SDK shows that is wrong: it passes
 *    the raw check frame (010003FF0104F9) to calculateAndSendCommand, which
 *    has a USB branch (CONNECTION_TYPE 101) and ignores ip/port there. The
 *    earlier "hang" was the SDK's silent-drop behaviour (the write is
 *    discarded when its serial port is not open) — the same symptom a
 *    payment shows — not proof the call is unsupported. It is now used as a
 *    real terminal handshake: see checkStatus() below, Settings → Developer
 *    Tools. `checkCommunication()` still only reports the local
 *    `isUsbConnected` flag (Geidea's own sample does the same) — that flag
 *    is set on the permission-granted broadcast, before the serial port
 *    opens, and is NOT proof the terminal answers.
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

    // Diagnostics: a payment (or handshake) currently waiting on the SDK.
    // Only ever read for logging / to refuse a probe mid-payment.
    @Volatile private var paymentInFlight = false
    private val diagHandler = Handler(Looper.getMainLooper())
    private var paymentHeartbeat: Runnable? = null
    private var lastHandshakeOk: Boolean? = null
    @Volatile private var paymentStartEpoch = 0L
    @Volatile private var lastPaymentCalledBack = false
    // True once Dart timed out and gave up on the payment (set from sdkDump
    // "payment:timeout"): a result that still arrives afterwards means the
    // customer paid but the order was not recorded — see startPayment.
    @Volatile private var dartGaveUp = false

    // Layer 1: event-driven attach detection — see class doc comment.
    private var receiverRegistered = false
    private val usbAttachReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != UsbManager.ACTION_USB_DEVICE_ATTACHED) return
            Log.d(TAG, "USB attach broadcast received")
            sendConnectionEvent("scanning", "USB device attached — connecting")
            // A new device node: whatever was pending belongs to the old one.
            connectGate.outcome()
            // The SDK also reacts to the attach by itself. Connecting at the same
            // instant makes both claim the same interface, so give the SDK a moment
            // and only connect ourselves if it did not manage to.
            attachHandler.postDelayed({
                if (!sdkServiceBound()) tryConnect() // re-opens the lost service
                else if (!isUsbConnected) tryConnect()
                else logTrace("attach: the SDK already connected by itself — no extra connect")
            }, ATTACH_GRACE_MS)
        }
    }

    private val attachHandler = Handler(Looper.getMainLooper())
    private val ATTACH_GRACE_MS = 1200L

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
    // Writes slower than this (measured on the background writer) are counted
    // and summarised by the stall watchdog below; see uiStallWatchdog.
    private val SLOW_LOG_WRITE_MS = 100L
    @Volatile private var slowLogWrites = 0
    @Volatile private var slowLogWriteMaxMs = 0L

    // The disk work (trim check + open + append) happens on TraceLogWriter's
    // own thread, in queued order — callers, often the UI thread, only queue
    // the line. The timestamp is taken here so it is the moment of the event,
    // not of the write.
    private fun logTrace(label: String) {
        if (!loggingEnabled()) return
        Log.e(TAG, "TRACE: $label")
        val ts = System.currentTimeMillis()
        val ctx = applicationContext
        TraceLogWriter.writer.post {
            val writeStart = SystemClock.elapsedRealtime()
            LogUploader.trimIfOversized(ctx)
            val dir = ctx.getExternalFilesDir(null) ?: ctx.filesDir
            val file = File(dir, "waha_trace.log")
            val dropped = TraceLogWriter.writer.takeDropped()
            if (dropped > 0) file.appendText("$ts TRACE WRITER: $dropped lines were dropped (writer queue was full)\n")
            file.appendText("$ts $label\n")
            val took = SystemClock.elapsedRealtime() - writeStart
            if (took >= SLOW_LOG_WRITE_MS) {
                slowLogWrites++
                if (took > slowLogWriteMaxMs) slowLogWriteMaxMs = took
            }
        }
    }

    // Which process is this, and how old? A brand-new process (small age) after
    // a previous one vanished means the process DIED; a large age on a fresh
    // onCreate means the Activity was only re-created inside a running process.
    // Process.getStartElapsedRealtime() is API 24+, so it is guarded; never throws.
    private fun processInfo(): String = try {
        val age = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            "${SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime()}ms"
        } else {
            "n/a(api<24)"
        }
        "pid=${Process.myPid()} processAge=$age deviceUptime=${SystemClock.elapsedRealtime() / 1000}s api=${Build.VERSION.SDK_INT}"
    } catch (t: Throwable) {
        "pid=? (${t.javaClass.simpleName})"
    }

    // Logs Android's recorded reasons why earlier processes of this app ended,
    // each entry ONCE (newest logged timestamp is remembered in the native
    // prefs). Off the main thread, everything caught — see ExitReasons for the
    // Android-version safety. Trace lines only.
    private fun logPreviousExitReasons() {
        val t = Thread {
            try {
                if (Build.VERSION.SDK_INT < ExitReasons.UNAVAILABLE_BELOW_API) {
                    logTrace(ExitReasons.unavailableNote())
                    return@Thread
                }
                val prefs = loggingPrefs()
                val last = prefs.getLong("last_exit_ts", 0L)
                val entries = ExitReasons.entries(applicationContext, 5)
                val fresh = entries.filter { it.timestamp > last }.sortedBy { it.timestamp }
                fresh.forEach {
                    logTrace(it.text)
                    // The system's own record of what the app was doing when it was
                    // killed (ANR: every thread's stack; we log the main thread's).
                    it.trace?.let { tr -> logTrace("EXIT TRACE for the entry above:\n$tr") }
                }
                fresh.firstOrNull { it.reason in ExitReasons.CRASH_REASONS }?.let {
                    AutoLogUploader.trigger(applicationContext, "crash:${ExitReasons.reasonName(it.reason)}") { s -> logTrace(s) }
                }
                entries.maxOfOrNull { it.timestamp }?.let { if (it > last) prefs.edit().putLong("last_exit_ts", it).apply() }
            } catch (_: Throwable) {
                // Diagnostics must never be a crash source.
            }
        }
        t.isDaemon = true
        t.name = "ExitReasonsLogger"
        t.start()
    }

    // Memory-pressure signals, for the "why did it restart" question.
    override fun onTrimMemory(level: Int) {
        logTrace("onTrimMemory level=$level")
        super.onTrimMemory(level)
    }

    override fun onLowMemory() {
        logTrace("onLowMemory")
        super.onLowMemory()
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
            // The line is queued for the writer thread; the process is about
            // to die, so give it a moment to reach the disk first.
            TraceLogWriter.writer.flush(1500)
            previousHandler?.uncaughtException(thread, throwable)
        }
        logTrace("onCreate start ${processInfo()} restoredState=${savedInstanceState != null}")
        super.onCreate(savedInstanceState)
        logTrace("onCreate end")
        logPreviousExitReasons()
        Thread {
            try {
                logTrace(SystemSnapshot.full(applicationContext))
            } catch (_: Throwable) {
            }
        }.also { it.isDaemon = true; it.name = "SystemSnapshot" }.start()
        startUiStallWatchdog()
    }

    override fun onStart() {
        logTrace("onStart start")
        super.onStart()
        activityStarted = true
        // Back in the foreground: if the SDK destroyed its service while the app
        // was stopped, open it again now.
        if (terminalResponder != null && !sdkServiceBound()) reopenSdkService("app back in the foreground")
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
        activityStarted = false
        logTrace("onStop isFinishing=$isFinishing changingConfigurations=$isChangingConfigurations")
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
                    "monotonicNow" -> {
                        // Time since boot (never jumps when the clock is corrected)
                        // plus the boot counter, so Dart can tell "same boot, this
                        // much time has passed" from "the tablet restarted".
                        result.success(mapOf("elapsed" to SystemClock.elapsedRealtime(), "boot" to bootCount()))
                    }
                    "ensureTerminalService" -> {
                        // Before a payment: make sure the SDK's USB service is bound,
                        // re-opening it if the SDK destroyed it. Waits off the main thread.
                        Thread {
                            val check = ensureTerminalServiceBlocking(15_000L)
                            runOnUiThread { result.success(check) }
                        }.start()
                    }
                    "prepareTerminal" -> {
                        val reason = call.argument<String>("reason") ?: "payment"
                        // Blocking wait for the port event — off the main thread.
                        Thread {
                            val ready = prepareTerminalBlocking(reason)
                            runOnUiThread { result.success(ready) }
                        }.start()
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
                    "checkStatus" -> {
                        val timeoutMs = (call.argument<Number>("timeoutMs") ?: 6000).toLong()
                        checkStatus(timeoutMs) { response -> runOnUiThread { result.success(response) } }
                    }
                    "sdkState" -> result.success(sdkReport("settings", logToTrace = false))
                    "sdkDump" -> {
                        val reason = call.argument<String>("reason") ?: "dart"
                        if (reason.startsWith("payment:")) {
                            stopPaymentHeartbeat()
                            if (reason == "payment:timeout") dartGaveUp = true
                            if (!lastPaymentCalledBack) {
                                logTrace("PAYMENT VERDICT (no SDK callback, $reason): " +
                                    TerminalDiagnostics.paymentVerdict(paymentStartEpoch, false, null, null, lastHandshakeOk))
                                // A silent hang, not a disconnect: the SDK never called back at
                                // all — neither USB trigger below would ever catch this case.
                                AutoLogUploader.trigger(applicationContext, "payment:$reason:no-callback") { logTrace(it) }
                            }
                        }
                        sdkReport(reason, logToTrace = true)
                        result.success(true)
                    }
                    "probeChannels" -> {
                        if (paymentInFlight) {
                            result.success("Refused: a payment is waiting on the terminal.")
                        } else {
                            Thread {
                                val text = try {
                                    TerminalDiagnostics.probe(
                                        applicationContext,
                                        disconnectSdk = { terminalResponder?.disconnectUsbSerialConnection() },
                                        reconnectSdk = { runOnUiThread { isUsbConnected = false; tryConnect(force = true) } },
                                        trace = { logTrace(it) },
                                    ).text
                                } catch (t: Throwable) {
                                    "Probe failed: ${t.javaClass.simpleName}: ${t.message}"
                                }
                                runOnUiThread { result.success(text) }
                            }.start()
                        }
                    }
                    "fullDiagnostic" -> fullDiagnostic { text -> runOnUiThread { result.success(text) } }
                    "exitReasons" -> Thread {
                        val text = ExitReasons.text(applicationContext)
                        runOnUiThread { result.success(text) }
                    }.start()
                    "setApiBaseUrl" -> {
                        LogUploader.setBaseUrl(applicationContext, call.argument<String>("url") ?: "")
                        result.success(true)
                    }
                    "setOrgId" -> {
                        AutoLogUploader.setOrgId(applicationContext, call.argument<Number>("orgId")?.toLong())
                        result.success(true)
                    }
                    "uploadLog" -> Thread {
                        val r = LogUploader.upload(applicationContext)
                        logTrace("uploadLog: ok=${r.ok} id=${r.id} bytes=${r.bytes} server=${r.baseUrl} message=${r.message}")
                        runOnUiThread {
                            result.success(
                                mapOf(
                                    "ok" to r.ok, "id" to r.id, "url" to r.url, "fileName" to r.fileName,
                                    "bytes" to r.bytes, "baseUrl" to r.baseUrl, "message" to r.message,
                                )
                            )
                        }
                    }.start()
                    "clearLog" -> {
                        val deleted = LogUploader.traceFile(applicationContext).delete()
                        result.success(deleted)
                    }
                    "openLogViewer" -> {
                        startActivity(Intent(this, CrashLogActivity::class.java))
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
                        // Kiosk's own _cancel()). What we CAN do: stop waiting
                        // on it, and remember that we walked away, so a late
                        // approval is logged as "customer paid, order not
                        // recorded" (same breadcrumb as a timeout). The USB
                        // connection itself is cleaned up by the next
                        // prepareTerminal() at the start of the next payment.
                        if (paymentInFlight) {
                            logTrace("cancelPayment: payment abandoned by the user while waiting on the terminal")
                            dartGaveUp = true
                            stopPaymentHeartbeat()
                        }
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
        // Observers run from app start regardless of the trace-logging switch —
        // the on-screen diagnostic tools depend on them; only writes to
        // waha_trace.log are gated (logTrace).
        SdkLogCapture.start { line ->
            logTrace(line)
            onSdkLogLine(line)
        }
        UsbMilestones.register(this, trace = { logTrace(it) }, onEvent = { name ->
            if (name in AutoLogUploader.USB_TRIGGER_NAMES) {
                AutoLogUploader.trigger(applicationContext, "usb:$name") { logTrace(it) }
            }
        })
        // Read-only USB snapshot channel — separate from everything Geidea above.
        UsbDiagnosticsChannel.register(flutterEngine, this) { logTrace(it) }
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
                logTrace("SDK callback: onUSBServiceConnected")
                sendConnectionEvent("serviceConnected")
                sendConnectionEvent("scanning", "Checking for already-attached terminal")
                tryConnect()
            }

            override fun onUSBConnected() {
                Log.d(TAG, "USB Device Connected")
                logTrace("SDK callback: onUSBConnected (permission granted; serial port not proven open) | ${TerminalDiagnostics.sdkState(terminalResponder)}")
                connectGate.outcome()
                isUsbConnected = true
                startupRetryHandler.removeCallbacksAndMessages(null)
                sendConnectionEvent("usbConnected")
            }

            override fun onUSBDisconnected() {
                Log.d(TAG, "USB Device Disconnected")
                logTrace("SDK callback: onUSBDisconnected")
                connectGate.outcome()
                isUsbConnected = false
                sendConnectionEvent("usbDisconnected")
                // No retry scheduled here on purpose — a genuine replug
                // fires usbAttachReceiver the instant it happens, so
                // polling for it here would just be redundant.
            }

            override fun onError(errorCode: Int, description: String) {
                Log.e(TAG, "USB error $errorCode: $description")
                logTrace("SDK callback: onError code=$errorCode desc=$description")
                connectGate.outcome()
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

    // ---- SDK USB service recovery (see ServiceRecovery) -------------------

    @Volatile private var activityStarted = false
    private val reopenLimiter = ReopenLimiter(clock = { SystemClock.elapsedRealtime() })

    /** Whether the SDK's background USB service is bound right now. */
    private fun sdkServiceBound(): Boolean = try {
        USBService.SERVICE_CONNECTED
    } catch (_: Throwable) {
        true // cannot tell — behave as before rather than loop on re-opens
    }

    /**
     * The SDK destroyed its USB service (it does so about a minute after the
     * app was stopped) and nothing re-binds it. From then on commands go
     * nowhere and a reconnect throws "USB Service not connected" — so the app's
     * "connected" flag is stale. Called for every SDK log line, with logging on
     * or off.
     */
    private fun onSdkLogLine(line: String) {
        if (!ServiceRecovery.isServiceLostLine(line)) return
        if (sdkServiceBound()) return // a stale line from our own re-open
        isUsbConnected = false
        connectGate.outcome()
        if (activityStarted) runOnUiThread { reopenSdkService("SDK reported its service destroyed") }
    }

    /**
     * Opens the SDK's USB service again, the way a fresh app start does
     * (close what is left, then initialise and open). Main thread only. At most
     * one every few seconds. Does nothing if the service is bound.
     */
    private fun reopenSdkService(reason: String) {
        val responder = terminalResponder
        if (responder == null) {
            initializeTerminal()
            return
        }
        if (sdkServiceBound()) return
        if (!reopenLimiter.tryAcquire()) return
        logTrace("SDK USB service is gone ($reason) — opening it again | ${TerminalDiagnostics.sdkState(responder)}")
        isUsbConnected = false
        connectGate.outcome()
        try {
            responder.closeUsbSerialConnection()
        } catch (t: Throwable) {
            logTrace("re-open: close threw ${t.javaClass.simpleName}: ${t.message}")
        }
        terminalResponder = null
        initializeTerminal()
        sendConnectionEvent("scanning", "Re-opening the terminal service")
    }

    /**
     * For the payment path (worker thread): if the service is gone, open it
     * again and wait up to [maxMs] for it to bind and the terminal to connect.
     * Returns whether the terminal is ready. A healthy service returns at once.
     */
    private fun ensureTerminalServiceBlocking(maxMs: Long): Map<String, Boolean> {
        if (terminalResponder != null && sdkServiceBound()) return mapOf("ready" to true, "reopened" to false)
        runOnUiThread { reopenSdkService("before payment") }
        val ready = ServiceRecovery.waitUntil(maxMs) { sdkServiceBound() && isUsbConnected }
        logTrace("ensureTerminalService: ${if (ready) "ready" else "NOT ready"} (service had been lost) | ${TerminalDiagnostics.sdkState(terminalResponder)}")
        return mapOf("ready" to ready, "reopened" to true)
    }

    /**
     * Shared "attempt a connection right now" used by every trigger: the
     * initial startup attempt, the bounded startup retries, the attach
     * broadcast receiver, and the manual/on-demand detectTerminal() calls.
     */
    private fun tryConnect(force: Boolean = false) {
        if (terminalResponder != null && !sdkServiceBound()) {
            // A connect would only throw "USB Service not connected".
            reopenSdkService("connect requested")
            return
        }
        when (connectGate.request(force)) {
            ConnectGate.Decision.SKIP -> {
                logTrace("tryConnect: skipped — a connect requested ${connectGate.pendingForMs()}ms ago has not reported an outcome yet")
                return
            }
            ConnectGate.Decision.GO_AFTER_EXPIRY ->
                logTrace("tryConnect: the previous connect never reported an outcome — allowing a new one")
            ConnectGate.Decision.GO -> {}
        }
        val responder = terminalResponder
        if (responder == null) {
            logTrace("tryConnect: responder null -> initializeTerminal")
            initializeTerminal()
            return
        }
        try {
            logTrace("tryConnect: connectUsbSerialConnection() | ${TerminalDiagnostics.sdkState(responder)}")
            val callStart = SystemClock.elapsedRealtime()
            responder.connectUsbSerialConnection()
            val callMs = SystemClock.elapsedRealtime() - callStart
            if (callMs >= 250) logTrace("SLOW SDK CALL connectUsbSerialConnection: call took ${callMs}ms on ${Thread.currentThread().name}")
        } catch (e: USBSerialConnectionException) {
            Log.e(TAG, "connectUsbSerialConnection failed", e)
            logTrace("tryConnect: connectUsbSerialConnection threw ${e.message}")
            if (ServiceRecovery.isServiceNotConnectedMessage(e.message)) reopenSdkService("connect threw: service not connected")
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
        tryConnect(force = true)
        // What the SDK believes a moment after the reconnect attempt.
        diagHandler.postDelayed({ logTrace("detect($source)+1.5s ${TerminalDiagnostics.sdkState(terminalResponder)}") }, 1500)
    }

    // Diagnostic-only: proves or disproves "the UI thread is being blocked
    // (by an SDK call or by log writes)". Posts to the main looper once a
    // second and compares when it actually ran; a late run means the UI
    // thread was busy for that long. Logs only stalls of STALL_LOG_MS or
    // more, plus a one-line summary of slow log writes seen since last time.
    private val STALL_TICK_MS = 500L
    private val STALL_LOG_MS = 1500L
    private var stallWatchdog: Runnable? = null

    // The main thread's heartbeat, read by the separate StallWatcher thread.
    @Volatile private var mainBeat = SystemClock.elapsedRealtime()
    private var stallWatcher: StallWatcher? = null

    private fun startUiStallWatchdog() {
        if (stallWatchdog != null) return
        var expectedAt = SystemClock.elapsedRealtime() + STALL_TICK_MS
        val tick = object : Runnable {
            override fun run() {
                val now = SystemClock.elapsedRealtime()
                mainBeat = now
                val late = now - expectedAt
                if (late >= STALL_LOG_MS) {
                    logTrace("UI STALL: main thread was blocked ~${late}ms | payment=${paymentInFlight} | ${TerminalDiagnostics.sdkState(terminalResponder)}")
                }
                val writes = slowLogWrites
                if (writes > 0) {
                    logTrace("SLOW LOG WRITES (background writer, not the UI thread): $writes writes took >=${SLOW_LOG_WRITE_MS}ms since last report, worst ${slowLogWriteMaxMs}ms")
                    slowLogWrites = 0
                    slowLogWriteMaxMs = 0
                }
                expectedAt = SystemClock.elapsedRealtime() + STALL_TICK_MS
                diagHandler.postDelayed(this, STALL_TICK_MS)
            }
        }
        stallWatchdog = tick
        diagHandler.postDelayed(tick, STALL_TICK_MS)

        // A second thread that, while the main thread is silent, logs the call
        // it is stuck in (see StallWatcher).
        mainBeat = SystemClock.elapsedRealtime()
        val mainThread = Looper.getMainLooper().thread
        stallWatcher = StallWatcher(
            lastBeat = { mainBeat },
            clock = { SystemClock.elapsedRealtime() },
            enabled = { loggingEnabled() },
            stack = { StallWatcher.stackOf(mainThread) },
            log = { text ->
                // A freeze report also gets the tablet's load and pressure at that moment.
                logTrace(if (text.startsWith("MAIN THREAD BLOCKED")) text + "\n    " + SystemSnapshot.compact() else text)
                // The app may be killed any moment now — get it onto disk.
                TraceLogWriter.writer.flush(300)
            },
        ).also { it.start() }
    }

    private fun stopUiStallWatchdog() {
        stallWatcher?.stop()
        stallWatcher = null
        stallWatchdog?.let { diagHandler.removeCallbacks(it) }
        stallWatchdog = null
    }

    /**
     * Clean start for a payment: drop whatever USB connection the SDK still
     * holds (from app start, an earlier payment, a cancel or a timeout), open
     * a fresh one and wait until the serial port REALLY opens. Returns true
     * only on PORT_OPEN_OK — never on the SDK's "connected" flag, which
     * doesn't prove the port opened. Without the disconnect first, the new
     * open collides with the connection we already hold and the SDK logs
     * "Interface could not be claimed", after which a payment written to it
     * gets no reply. Same disconnect/reconnect the diagnostics use.
     *
     * Runs on a worker thread (it waits); SDK calls hop to the main thread.
     */
    private fun prepareTerminalBlocking(reason: String): Boolean {
        return synchronized(prepareLock) {
            sendConnectionEvent("scanning", "Preparing terminal ($reason)")
            logTrace("prepareTerminal($reason): disconnect + reconnect | ${TerminalDiagnostics.sdkState(terminalResponder)}")
            stopPaymentHeartbeat() // an abandoned payment must not keep the wait/refuse flags up
            val disconnected = CountDownLatch(1)
            val postedAt = SystemClock.elapsedRealtime()
            runOnUiThread {
                val ranAt = SystemClock.elapsedRealtime()
                try {
                    terminalResponder?.disconnectUsbSerialConnection()
                } catch (t: Throwable) {
                    logTrace("prepareTerminal: disconnect threw ${t.javaClass.simpleName}: ${t.message}")
                }
                isUsbConnected = false
                val callMs = SystemClock.elapsedRealtime() - ranAt
                // Timing for the "does the SDK disconnect block the UI thread"
                // question: queue delay = how long the UI thread was busy
                // before it could even start the call; call = how long the
                // SDK call itself held it.
                if (ranAt - postedAt >= 250 || callMs >= 250) {
                    logTrace("SLOW SDK CALL disconnectUsbSerialConnection: waited ${ranAt - postedAt}ms for the UI thread, call took ${callMs}ms")
                }
                disconnected.countDown()
            }
            disconnected.await(2, TimeUnit.SECONDS)
            Thread.sleep(400) // let Android release the interface
            val since = System.currentTimeMillis()
            runOnUiThread { tryConnect(force = true) }
            val outcome = waitPortEvent(since, PORT_OPEN_WAIT_MS)
            val ready = outcome.startsWith("PORT_OPEN_OK")
            logTrace("prepareTerminal($reason): ${if (ready) "READY" else "NOT READY"} — $outcome")
            if (!ready) {
                AutoLogUploader.trigger(applicationContext, "prepareTerminal:$reason:$outcome") { logTrace(it) }
            }
            ready
        }
    }

    private val prepareLock = Any()

    private fun bootCount(): Int = try {
        if (Build.VERSION.SDK_INT >= 24) {
            android.provider.Settings.Global.getInt(contentResolver, android.provider.Settings.Global.BOOT_COUNT, -1)
        } else -1
    } catch (_: Throwable) {
        -1
    }

    // How long a reset waits for the serial port to open. The port has been seen
    // opening 6-11 s after a slow disconnect, so a short limit turned a slow
    // reconnect into a failed sale.
    private val PORT_OPEN_WAIT_MS = 15_000L

    // One automatic connect attempt at a time — see ConnectGate.
    private val connectGate = ConnectGate(clock = { SystemClock.elapsedRealtime() })

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
            logTrace("startPayment: refused — terminalResponder is null")
            callback(mapOf("status" to "declined", "receipt" to "Terminal not initialized"))
            return
        }
        val startedAt = SystemClock.elapsedRealtime()
        paymentInFlight = true
        paymentStartEpoch = System.currentTimeMillis()
        lastPaymentCalledBack = false
        dartGaveUp = false
        logTrace("startPayment: BEGIN amount=$amount reference=$reference printer=$isPrinterEnabled | ${TerminalDiagnostics.sdkState(responder)}")
        startPaymentHeartbeat(startedAt)
        // The SDK calls this callback SEVERAL times for ONE payment (see
        // PaymentCallbackClassifier): an ack, terminal step codes, then the
        // final result. We answer Dart exactly ONCE, on the first callback
        // that carries a definite outcome — approved, declined, or an SDK
        // error code — whether that is the first callback or the thousandth.
        // Acks, step codes and any "1" without a receipt are progress only:
        // logged, ignored, and the wait (and the heartbeat) continues. A
        // repeat after the answer is ignored too.
        //
        // PRODUCT RULE (details in invoice_screen.dart): once the terminal
        // has approved, the customer HAS paid. We must never fine them a
        // second time for a failure of ours, and sales keep going as long as
        // the kiosk can make orders and the POS can process transactions. If
        // the approval arrives after Dart gave up (timeout), or the backend
        // cannot record it, that is our reconciliation problem — hence the
        // PAYMENT LATE APPROVAL breadcrumb below.
        val answered = AtomicBoolean(false)
        val responseCallback = object : Callback<Any?>() {
            override fun call(): Any? {
                @Suppress("UNCHECKED_CAST")
                val response = getParameter() as? Array<String?> ?: emptyArray()
                val result = PaymentCallbackClassifier.classify(response)
                logTrace(
                    "startPayment: SDK CALLBACK after ${SystemClock.elapsedRealtime() - startedAt}ms " +
                        "outcome=${result.outcome} fields=${response.size} status='${response.getOrNull(0)}' " +
                        "code/receipt='${response.getOrNull(1)?.take(120)}' " +
                        "detailsLen=${response.getOrNull(2)?.length} buffer='${response.getOrNull(3)?.take(300)}'"
                )
                if (result.outcome == PaymentCallbackClassifier.Outcome.PROGRESS) {
                    logTrace("startPayment: progress only (ack / step codes) — still waiting for the final result")
                    return null
                }
                if (!answered.compareAndSet(false, true)) {
                    logTrace("startPayment: extra callback after the result was already delivered — ignored")
                    return null
                }
                stopPaymentHeartbeat()
                lastPaymentCalledBack = true
                val approved = result.outcome == PaymentCallbackClassifier.Outcome.APPROVED
                logTrace("PAYMENT VERDICT: " + TerminalDiagnostics.paymentVerdict(
                    paymentStartEpoch, true,
                    if (approved) "approved" else "declined",
                    result.message, lastHandshakeOk,
                ))
                logTrace("PAYMENT LADDER\n" + TerminalDiagnostics.ladder(applicationContext, paymentStartEpoch, true))
                logTrace("PAYMENT TIMELINE\n" + TerminalDiagnostics.timeline(paymentStartEpoch))
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
                if (approved && dartGaveUp) {
                    logTrace(
                        "PAYMENT LATE APPROVAL — the terminal approved AFTER the app gave up waiting: the customer HAS PAID " +
                            "but the order was NOT recorded. Reconcile by hand: reference=$reference amount=$amount " +
                            "approvalCode=${details["approvalCode"]} rrn=${details["rrn"]} terminalId=${details["terminalId"]}"
                    )
                }
                callback(mapOf(
                    "status" to (if (approved) "approved" else "declined"),
                    // Approved keeps the receipt; a decline/error gets a short
                    // human message (the Dart side shows it as the failure text).
                    "receipt" to (if (approved) (response.getOrNull(1) ?: "") else result.message),
                    "details" to details,
                    "buffer" to (response.getOrNull(3) ?: "")
                ))
                return null
            }
        }
        try {
            responder.startPurchaseTransaction(
                TERMINAL_TRANSACTION_TYPES.PURCHASE_TRANSACTION,
                amount,
                reference,
                isPrinterEnabled,
                responseCallback
            )
            logTrace("startPayment: startPurchaseTransaction() returned after ${SystemClock.elapsedRealtime() - startedAt}ms — command handed to SDK, waiting for its callback")
        } catch (t: Throwable) {
            stopPaymentHeartbeat()
            logTrace("startPayment: startPurchaseTransaction THREW ${Log.getStackTraceString(t)}")
            callback(mapOf("status" to "declined", "receipt" to "SDK exception: ${t.message}"))
        }
    }

    // Every 5 s while the SDK has not answered: what it believes, plus its own
    // log file and the USB inventory at ~5 s and ~20 s. Capped at 2 minutes.
    private fun startPaymentHeartbeat(startedAt: Long) {
        stopPaymentHeartbeat()
        paymentInFlight = true
        val beat = object : Runnable {
            override fun run() {
                val elapsed = SystemClock.elapsedRealtime() - startedAt
                logTrace("startPayment: still waiting ${elapsed / 1000}s | ${TerminalDiagnostics.sdkState(terminalResponder)}")
                if (elapsed in 4000..6999 || elapsed in 19000..21999) {
                    TerminalDiagnostics.sdkLogFileTail(applicationContext, 3000).lines().forEach { logTrace(it) }
                    UsbInventory.report(applicationContext).lines().forEach { logTrace("USB[payment:wait] $it") }
                }
                if (elapsed < 120000) diagHandler.postDelayed(this, 5000) else paymentInFlight = false
            }
        }
        paymentHeartbeat = beat
        diagHandler.postDelayed(beat, 5000)
    }

    private fun stopPaymentHeartbeat() {
        paymentHeartbeat?.let { diagHandler.removeCallbacks(it) }
        paymentHeartbeat = null
        paymentInFlight = false
    }

    /**
     * Real terminal handshake over USB: sends the SDK's own check-connection
     * frame through startCheckStatus and waits for the terminal's reply. The
     * SDK has no timeout of its own — if the frame is dropped (serial port
     * not open) or the terminal stays silent, the callback never fires, so
     * we time out ourselves. Refused while a payment waits, because the SDK
     * keeps a single response callback: a reply to this would be handed to
     * that payment.
     *
     * The result carries a millisecond timeline (request started → request
     * handed to the SDK → SDK's own FINAL BUFFER / DATA FROM USB lines and
     * port events → callback or timeout), the six-signal ladder and a
     * verdict (A–D).
     */
    private fun checkStatus(timeoutMs: Long, done: (Map<String, Any?>) -> Unit) {
        val responder = terminalResponder
        if (responder == null) {
            done(mapOf("status" to "not_initialized", "message" to "SDK terminal responder is not initialised"))
            return
        }
        if (paymentInFlight) {
            done(mapOf("status" to "busy", "message" to "A payment is waiting on the terminal — try again after it ends"))
            return
        }
        val startEpoch = System.currentTimeMillis()
        val startedAt = SystemClock.elapsedRealtime()
        val marks = java.util.Collections.synchronizedList(ArrayList<Pair<Long, String>>())
        marks.add(startEpoch to "REQUEST STARTED — about to call startCheckStatus() (frame 01 00 03 FF 01 04 F9)")
        val finished = AtomicBoolean(false)
        fun finish(map: Map<String, Any?>) {
            if (!finished.compareAndSet(false, true)) return
            val status = map["status"] as? String ?: "?"
            marks.add(System.currentTimeMillis() to if (status == "timeout") "TIMEOUT — the SDK never called back" else "SDK CALLBACK status=$status")
            if (status == "timeout") {
                AutoLogUploader.trigger(applicationContext, "checkStatus:timeout") { logTrace(it) }
            }
            val sdkIface = TerminalDiagnostics.sdkDevice(applicationContext)?.let { TerminalDiagnostics.firstDataInterface(it) }
            val timeline = TerminalDiagnostics.timeline(startEpoch, synchronized(marks) { ArrayList(marks) })
            val verdict = TerminalDiagnostics.statusVerdict(startEpoch, status, map["message"] as? String ?: "", null, sdkIface)
            val ladder = TerminalDiagnostics.ladder(applicationContext, startEpoch, if (status == "timeout") false else true)
            lastHandshakeOk = status == "ok"
            val full = map + mapOf(
                "elapsedMs" to (SystemClock.elapsedRealtime() - startedAt),
                "startEpoch" to startEpoch,
                "timeline" to timeline,
                "verdict" to verdict,
                "ladder" to ladder,
            )
            logTrace("checkStatus: RESULT status=$status elapsedMs=${full["elapsedMs"]} message='${map["message"]}' raw='${map["raw"]}'")
            logTrace("checkStatus: VERDICT $verdict")
            logTrace("checkStatus: LADDER\n$ladder")
            logTrace("checkStatus: TIMELINE\n$timeline")
            logTrace("checkStatus: ${TerminalDiagnostics.sdkState(terminalResponder)}")
            done(full)
        }
        logTrace("checkStatus: SEND (timeout ${timeoutMs}ms) | ${TerminalDiagnostics.sdkState(responder)}")
        val cb = object : Callback<Any?>() {
            override fun call(): Any? {
                @Suppress("UNCHECKED_CAST")
                val r = getParameter() as? Array<String> ?: emptyArray()
                val ok = r.getOrNull(0) == "1"
                finish(
                    mapOf(
                        "status" to if (ok) "ok" else "error",
                        "message" to (r.getOrNull(1) ?: "").replace(Regex("<[^>]+>"), " ").replace(Regex("\\s+"), " ").trim(),
                        "json" to (r.getOrNull(2) ?: ""),
                        "raw" to (r.getOrNull(3) ?: ""),
                    )
                )
                return null
            }
        }
        diagHandler.postDelayed({
            finish(mapOf("status" to "timeout", "message" to "No reply from the terminal within ${timeoutMs}ms"))
        }, timeoutMs)
        try {
            responder.startCheckStatus("", 0, TERMINAL_TRANSACTION_TYPES.CHECK_STATUS, cb)
            marks.add(System.currentTimeMillis() to "startCheckStatus() RETURNED — request sent to the SDK (it now writes it, or silently drops it)")
        } catch (t: Throwable) {
            finish(mapOf("status" to "exception", "message" to "${t.javaClass.simpleName}: ${t.message}"))
        }
    }

    // ---- full diagnostic --------------------------------------------------------

    private fun waitPortEvent(since: Long, maxMs: Long): String {
        val portEvents = setOf("PORT_OPEN_OK", "PORT_OPEN_FAILED_CDC", "PORT_OPEN_FAILED_DEVICE", "SERIAL_CREATE_FAILED", "NO_SERIAL_DEVICE")
        val end = SystemClock.elapsedRealtime() + maxMs
        while (SystemClock.elapsedRealtime() < end) {
            val ev = UsbMilestones.since(since).firstOrNull { it.name in portEvents }
            if (ev != null) return "${ev.name} after ${ev.at - since}ms"
            Thread.sleep(100)
        }
        return "NO port event within ${maxMs}ms (the SDK reported neither success nor failure)"
    }

    private fun reconnectSdkAndWait(): String {
        val since = System.currentTimeMillis()
        runOnUiThread { isUsbConnected = false; tryConnect(force = true) }
        return waitPortEvent(since, PORT_OPEN_WAIT_MS)
    }

    private fun checkStatusBlocking(timeoutMs: Long): Map<String, Any?> {
        val latch = CountDownLatch(1)
        var out: Map<String, Any?> = emptyMap()
        runOnUiThread { checkStatus(timeoutMs) { out = it; latch.countDown() } }
        latch.await(timeoutMs + 5000, TimeUnit.MILLISECONDS)
        return out
    }

    /**
     * One button, one complete report: USB environment, the SDK's own view,
     * a forced reconnect and whether the port really opens, the real
     * startCheckStatus() request with timeline, a raw probe of every serial
     * channel (exact bytes written/received, independent of the SDK), the SDK
     * status request again after the reconnect, the six-signal ladder and a
     * verdict A–D. Also written line by line to the trace log. E/F (purchase)
     * are classified per real payment: PAYMENT VERDICT in the trace log.
     */
    private fun fullDiagnostic(done: (String) -> Unit) {
        if (paymentInFlight) {
            done("Refused: a payment is waiting on the terminal.")
            return
        }
        Thread {
            val sb = StringBuilder()
            fun line(text: String) {
                sb.append(text).append('\n')
                logTrace("FULLDIAG $text")
            }
            try {
                val t0 = System.currentTimeMillis()
                line("=== GEIDEA FULL DIAGNOSTIC ===")
                line("time=${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date())} " +
                    "device=${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL} android=${android.os.Build.VERSION.RELEASE}(api ${android.os.Build.VERSION.SDK_INT})")
                line("")
                line("[1] USB ENVIRONMENT (host role, every device, the device + interface the SDK selects, endpoints)")
                UsbInventory.report(applicationContext).lines().forEach { line("  $it") }
                line("")
                line("[2] WHAT THE SDK REPORTED BEFORE THIS TEST")
                line("  ${TerminalDiagnostics.sdkState(terminalResponder)}")
                line("  port state: ${UsbMilestones.portState()}")
                UsbMilestones.since(0).takeLast(25).forEach { line("  event t=${it.at % 100000000} ${it.name} ${it.detail}") }
                line("")
                if (terminalResponder == null) {
                    line("SDK terminal responder is not initialised — cannot continue past this point.")
                    done(sb.toString().trimEnd())
                    return@Thread
                }
                line("[3] FORCED RECONNECT — does the serial port really open?")
                line("  result: ${reconnectSdkAndWait()}")
                line("  ${TerminalDiagnostics.sdkState(terminalResponder)}")
                line("")
                line("[4] REAL GEIDEA STATUS REQUEST (startCheckStatus over USB)")
                val hs1 = checkStatusBlocking(6000)
                line("  status=${hs1["status"]} elapsed=${hs1["elapsedMs"]}ms message='${hs1["message"]}' raw='${hs1["raw"]}'")
                line("  timeline:")
                "${hs1["timeline"] ?: ""}".lines().forEach { line("  $it") }
                line("")
                line("[5] RAW CHANNEL PROBE (independent of the SDK; exact bytes)")
                val probe = TerminalDiagnostics.probe(
                    applicationContext,
                    disconnectSdk = { terminalResponder?.disconnectUsbSerialConnection() },
                    reconnectSdk = { runOnUiThread { isUsbConnected = false; tryConnect(force = true) } },
                    trace = { logTrace(it) },
                )
                probe.text.lines().forEach { line("  $it") }
                line("")
                line("[6] SDK STATUS REQUEST AGAIN, after the probe reconnected the SDK")
                line("  reconnect: ${waitPortEvent(System.currentTimeMillis() - 200, 6000)}")
                val hs2 = checkStatusBlocking(6000)
                line("  status=${hs2["status"]} elapsed=${hs2["elapsedMs"]}ms message='${hs2["message"]}'")
                line("")
                line("[7] SIGNAL LADDER (each fact separate — isUSBConnected is NOT proof)")
                line(TerminalDiagnostics.ladder(applicationContext, (hs1["startEpoch"] as? Long) ?: t0, hs1["status"] != "timeout"))
                line("")
                val sdkIface = TerminalDiagnostics.sdkDevice(applicationContext)?.let { TerminalDiagnostics.firstDataInterface(it) }
                line("[8] VERDICT")
                line("  " + TerminalDiagnostics.statusVerdict(
                    (hs1["startEpoch"] as? Long) ?: t0, hs1["status"] as? String ?: "?", hs1["message"] as? String ?: "",
                    probe.channels, sdkIface,
                ))
                if (hs1["status"] != hs2["status"]) line("  NOTE: status request #1 was '${hs1["status"]}' but #2 (after reconnect) was '${hs2["status"]}' — reconnecting changes the outcome.")
                line("  E/F (purchase): not exercised here. Run one payment; the trace log then holds 'PAYMENT VERDICT' with the same signals for the purchase.")
                line("=== END (took ${(System.currentTimeMillis() - t0) / 1000}s) ===")
            } catch (t: Throwable) {
                line("DIAGNOSTIC FAILED: ${Log.getStackTraceString(t)}")
            }
            done(sb.toString().trimEnd())
        }.start()
    }

    /**
     * Everything we can observe about the SDK right now as one text block:
     * internal state, the six-signal ladder, port history, its own log file
     * tail, recently captured log lines and the USB inventory. Returned to
     * Settings; also written to the trace log when [logToTrace].
     */
    private fun sdkReport(reason: String, logToTrace: Boolean): String {
        val sb = StringBuilder()
        sb.append(TerminalDiagnostics.sdkState(terminalResponder)).append('\n')
        sb.append("LADDER (since last payment start)\n").append(TerminalDiagnostics.ladder(applicationContext, paymentStartEpoch, if (paymentStartEpoch == 0L) null else lastPaymentCalledBack)).append('\n')
        sb.append("PORT EVENTS\n")
        UsbMilestones.since(0).takeLast(25).forEach { sb.append("  ${it.at % 100000000} ${it.name} ${it.detail}\n") }
        sb.append(TerminalDiagnostics.sdkLogFileTail(applicationContext)).append('\n')
        sb.append(SdkLogCapture.recentLines()).append('\n')
        sb.append(UsbInventory.report(applicationContext))
        val text = sb.toString()
        if (logToTrace) text.lines().forEach { logTrace("REPORT[$reason] $it") }
        return text
    }

    private fun jsonObjectToMap(json: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        json.keys().forEach { key -> map[key] = json.get(key) }
        return map
    }

    override fun onDestroy() {
        stopUiStallWatchdog()
        logTrace("onDestroy isFinishing=$isFinishing changingConfigurations=$isChangingConfigurations ${processInfo()}")
        startupRetryHandler.removeCallbacksAndMessages(null)
        stopPaymentHeartbeat()
        SdkLogCapture.stop()
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
