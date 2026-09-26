package com.example.waha_platform

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Uploads the diagnostic log to the Waha backend so a kiosk that nobody can
// physically reach can still be inspected. Uses the backend's plain
// `POST /api/resources` (multipart field "file"), which stores the bytes and
// answers {id, sha256}; the text is then readable at
// `<server>/api/logs/<id>` (admin-only; device uploads are no longer public at /api/resources/<id>).
//
// TEMPORARY DIAGNOSTIC TOOL — must not reach production as it is. It uses the
// backend's open, unauthenticated `POST /api/resources` (anyone can upload up
// to 10 MB and read it back by id), and every upload stays in the database.
// Before production either remove it, or replace it with a proper
// authenticated log-upload API (kiosk login, size limits, per-device
// retention). Agreed with the user; do not build features on this endpoint.
//
// Deliberately plain native code with no Flutter dependency, shared by the
// log viewer activity (which must work even when Flutter cannot start) and
// the Settings quick-action. The server URL is pushed here by Dart at startup
// (setBaseUrl); with none pushed yet it falls back to Flutter's own stored
// value.
object LogUploader {
    private const val PREFS = "waha_diagnostics"
    private const val KEY_BASE = "api_base_url"

    class Result(val ok: Boolean, val id: Long?, val url: String?, val fileName: String, val bytes: Int, val baseUrl: String?, val message: String)

    fun setBaseUrl(context: Context, url: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_BASE, url).apply()
    }

    fun baseUrl(context: Context): String? {
        val pushed = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_BASE, null)
        if (!pushed.isNullOrBlank()) return pushed.trimEnd('/')
        // Flutter's shared_preferences file; key = "flutter." + LocalPrefs key.
        val stored = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.waha.api_base_url", null)
        return stored?.takeIf { it.isNotBlank() }?.trimEnd('/')
    }

    // The device's own login token, read straight from LocalPrefs' backing
    // file (same as baseUrl's fallback above) — no live push needed: it's
    // written synchronously by LocalPrefs.setAuthToken on every successful
    // login (kiosk or normal), so it's already current whenever this runs,
    // including from CrashLogActivity with no live Flutter session at all.
    // POST /api/resources now requires a valid session; without this the
    // upload gets a 401.
    fun authToken(context: Context): String? =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.waha.auth_token", null)
            ?.takeIf { it.isNotBlank() }

    fun traceFile(context: Context): File = File(context.getExternalFilesDir(null) ?: context.filesDir, "waha_trace.log")

    /** Last [maxBytes] of [file], starting on a line boundary. */
    private fun tail(file: File, maxBytes: Int): Pair<String, Long> {
        if (!file.exists()) return "(no waha_trace.log)" to 0L
        val len = file.length()
        java.io.RandomAccessFile(file, "r").use { raf ->
            val start = maxOf(0L, len - maxBytes)
            raf.seek(start)
            val buf = ByteArray((len - start).toInt())
            raf.readFully(buf)
            var text = String(buf, Charsets.UTF_8)
            if (start > 0) text = text.substringAfter('\n', text)
            return text to len
        }
    }

    /** Everything worth reading, in one text file. */
    fun buildReport(context: Context, maxTraceBytes: Int = 1_000_000): String {
        val sb = StringBuilder()
        val version = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        } catch (_: Throwable) {
            "?"
        }
        sb.append("=== WAHA LOG UPLOAD ===\n")
        sb.append("time=").append(SimpleDateFormat("yyyy-MM-dd HH:mm:ss Z", Locale.US).format(Date())).append('\n')
        sb.append("device=${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL} android=${android.os.Build.VERSION.RELEASE} (api ${android.os.Build.VERSION.SDK_INT})\n")
        sb.append("app=${context.packageName} version=$version server=${baseUrl(context)}\n\n")
        val (trace, total) = tail(traceFile(context), maxTraceBytes)
        sb.append("=== TRACE LOG (last ${minOf(total, maxTraceBytes.toLong())} of $total bytes) ===\n").append(trace).append("\n\n")
        sb.append("=== SDK LOG FILE ===\n").append(TerminalDiagnostics.sdkLogFileTail(context, 60000)).append("\n\n")
        sb.append("=== SDK LOG LINES CAPTURED THIS RUN ===\n").append(SdkLogCapture.recentLines()).append("\n\n")
        sb.append("=== USB INVENTORY NOW ===\n").append(
            try {
                UsbInventory.report(context)
            } catch (t: Throwable) {
                "failed: ${t.message}"
            },
        ).append('\n')
        return sb.toString()
    }

    /** Blocking — call from a background thread. */
    fun upload(context: Context): Result {
        val base = baseUrl(context)
        val name = "logs_" + SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) + ".txt"
        if (base == null) return Result(false, null, null, name, 0, null, "No server URL known yet — open the kiosk app once (or set Settings → Server Connection) and retry.")
        val token = authToken(context)
        if (token == null) return Result(false, null, null, name, 0, base, "Not logged in yet — open the kiosk app and log in, then retry.")
        return try {
            val body = buildReport(context).toByteArray(Charsets.UTF_8)
            val boundary = "----waha${System.currentTimeMillis()}"
            val head = ("--$boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"$name\"\r\n" +
                "Content-Type: text/plain; charset=utf-8\r\n\r\n").toByteArray()
            val tailBytes = "\r\n--$boundary--\r\n".toByteArray()
            val conn = URL("$base/api/resources").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = 15000
            conn.readTimeout = 60000
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            conn.setFixedLengthStreamingMode(head.size + body.size + tailBytes.size)
            conn.outputStream.use {
                it.write(head)
                it.write(body)
                it.write(tailBytes)
            }
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText().orEmpty()
            if (code !in 200..299) return Result(false, null, null, name, body.size, base, "Server answered HTTP $code: ${text.take(200)}")
            val id = JSONObject(text).getLong("id")
            // Device uploads are no longer public at /api/resources/<id>; admins read them at /api/logs/<id> (needs an admin login).
            Result(true, id, "$base/api/logs/$id", name, body.size, base, "Uploaded")
        } catch (t: Throwable) {
            Result(false, null, null, name, 0, base, "${t.javaClass.simpleName}: ${t.message}")
        }
    }
}
