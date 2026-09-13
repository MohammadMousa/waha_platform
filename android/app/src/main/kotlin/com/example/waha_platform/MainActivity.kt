package com.example.waha_platform

import android.util.Log
import geidea.net.terminal_comm_api.Callback
import geidea.net.terminal_comm_api.GeideaSDK
import geidea.net.terminal_comm_api.TERMINAL_TRANSACTION_TYPES
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
 */
class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.waha/geidea"
    private val EVENT_CHANNEL = "com.waha/geidea/events"
    private val TAG = "GeideaBridge"

    private var terminalResponder: TerminalResponder? = null
    private var connectionEventSink: EventChannel.EventSink? = null
    private var isUsbConnected: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
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
    }

    private fun sendConnectionEvent(state: String, description: String? = null) {
        val sink = connectionEventSink ?: return
        runOnUiThread {
            sink.success(mapOf("state" to state, "description" to description))
        }
    }

    private fun initializeTerminal() {
        if (terminalResponder != null) return // already initialized
        GeideaSDK.initialize(this)
        val responder = TerminalResponder.getTerminalResponderInstance(
            this,
            TerminalResponder.TYPE_USB_SERIAL_CONNECTION
        )
        terminalResponder = responder
        responder.openUsbSerialConnection(object : USBConnectionListener {
            override fun onUSBServiceConnected() {
                // This only means the SDK's background service is bound — it
                // is NOT the physical USB connection. Geidea's own sample
                // (SerialCableConnectionActivty.onUSBServiceConnected) shows
                // a second, separate call is required here to actually make
                // Android enumerate the device and prompt for permission;
                // without it, onUSBConnected() never fires.
                Log.d(TAG, "USB Service Connected")
                sendConnectionEvent("serviceConnected")
                try {
                    terminalResponder?.connectUsbSerialConnection()
                } catch (e: USBSerialConnectionException) {
                    Log.e(TAG, "connectUsbSerialConnection failed", e)
                }
            }

            override fun onUSBConnected() {
                Log.d(TAG, "USB Device Connected")
                isUsbConnected = true
                sendConnectionEvent("usbConnected")
            }

            override fun onUSBDisconnected() {
                Log.d(TAG, "USB Device Disconnected")
                isUsbConnected = false
                sendConnectionEvent("usbDisconnected")
            }

            override fun onError(errorCode: Int, description: String) {
                Log.e(TAG, "USB error $errorCode: $description")
                isUsbConnected = false
                sendConnectionEvent("error", description)
                // Same retry Geidea's sample does: a denied/missed permission
                // prompt surfaces as this specific error code, and retrying
                // connectUsbSerialConnection() re-triggers the request.
                if (errorCode == TerminalResponder.ERROR_PERMISSION_NOT_GRANTED) {
                    try {
                        terminalResponder?.connectUsbSerialConnection()
                    } catch (e: USBSerialConnectionException) {
                        Log.e(TAG, "connectUsbSerialConnection retry failed", e)
                    }
                }
            }
        })
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
        terminalResponder?.closeUsbSerialConnection()
        super.onDestroy()
    }
}
