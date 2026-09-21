package com.example.waha_platform

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Read-only USB snapshot channel (see UsbInventory). Its own channel and no
// state shared with the Geidea bridge in MainActivity: it never opens,
// claims or requests permission for anything, it only reports.
object UsbDiagnosticsChannel {
    private const val CHANNEL = "com.waha/usbdiag"

    fun register(engine: FlutterEngine, context: Context, trace: (String) -> Unit) {
        val appContext = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "inventory") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val reason = call.argument<String>("reason")
            val text = try {
                UsbInventory.report(appContext)
            } catch (e: Throwable) {
                "USB inventory failed: ${e.javaClass.simpleName}: ${e.message}"
            }
            // With a reason the snapshot is also written to the trace log
            // (gated natively by the same logging switch as everything else).
            if (reason != null) text.lines().forEach { trace("USB[$reason] $it") }
            result.success(text)
        }
    }
}
