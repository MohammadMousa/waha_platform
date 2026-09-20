package com.example.waha_platform

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

// Flutter bridge for the generic Waha kiosk <-> Waha Terminal USB link (see
// WahaUsbHost). Completely separate from the Geidea channels in MainActivity:
// its own MethodChannel/EventChannel, its own executor, its own host object.
// MainActivity only calls register() once and shutdown() on destroy.
object WahaLinkChannel {
    private const val METHOD_CHANNEL = "com.waha/wahalink"
    private const val EVENT_CHANNEL = "com.waha/wahalink/events"

    private val main = Handler(Looper.getMainLooper())
    // Blocking work (permission dialogs, AOA re-enumeration wait, payments)
    // must never run on the platform thread.
    private val pool = Executors.newCachedThreadPool()

    private var host: WahaUsbHost? = null
    private var sink: EventChannel.EventSink? = null

    fun register(engine: FlutterEngine, context: Context, trace: (String) -> Unit) {
        val appContext = context.applicationContext

        fun hostOrCreate(): WahaUsbHost =
            host ?: WahaUsbHost(
                appContext,
                trace = { trace("LINK: $it") },
                emit = { state, code, description ->
                    main.post {
                        sink?.success(mapOf("state" to state, "code" to code, "description" to description))
                    }
                },
            ).also { host = it }

        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                fun async(block: () -> Any?) {
                    pool.execute {
                        val value = try {
                            block()
                        } catch (e: Throwable) {
                            LinkResult.fail("INTERNAL_ERROR", e.message ?: e.javaClass.simpleName).toMap()
                        }
                        main.post { result.success(value) }
                    }
                }

                when (call.method) {
                    "start" -> { hostOrCreate().start(); result.success(true) }
                    "stop" -> { host?.stop(); result.success(true) }
                    "isConnected" -> result.success(host?.isConnected() ?: false)
                    // Passive USB snapshot (see UsbInventory) — never touches the
                    // link or Geidea. With a reason it is also written to the
                    // trace log so it lines up with the other events.
                    "usbInventory" -> {
                        val reason = call.argument<String>("reason")
                        val text = try {
                            UsbInventory.report(appContext)
                        } catch (e: Throwable) {
                            "USB inventory failed: ${e.javaClass.simpleName}: ${e.message}"
                        }
                        if (reason != null) text.lines().forEach { trace("USB[$reason] $it") }
                        result.success(text)
                    }
                    "connect" -> async { hostOrCreate().connect().toMap() }
                    "requestPayment" -> {
                        val reference = call.argument<String>("reference")
                        val amount = call.argument<Double>("amount")
                        val currency = call.argument<String>("currency")
                        val timeoutMs = (call.argument<Number>("timeoutMs") ?: 90000).toLong()
                        if (reference == null || amount == null || currency == null) {
                            result.success(LinkResult.fail("INVALID_ARGUMENTS", "reference/amount/currency required").toMap())
                        } else {
                            async { hostOrCreate().requestPayment(reference, amount, currency, timeoutMs).toMap() }
                        }
                    }
                    "cancel" -> {
                        val reference = call.argument<String>("reference") ?: ""
                        async { host?.cancel(reference); mapOf("ok" to true) }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
                override fun onCancel(arguments: Any?) { sink = null }
            })
    }

    fun shutdown() {
        try { host?.stop() } catch (_: Throwable) {}
        host = null
    }
}
