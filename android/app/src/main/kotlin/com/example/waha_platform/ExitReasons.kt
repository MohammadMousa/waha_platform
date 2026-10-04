package com.example.waha_platform

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Why did the previous process(es) of this app die? Android keeps the last few
// exit reasons per app (crash, native crash, ANR, low memory, the user or a
// watchdog force-stopping it, ...), which is the only way to tell a real process
// death from the Activity merely being re-created. Diagnostics only — nothing
// here runs on the payment path.
//
// Crash-safety across Android versions:
//  - The API is Android 11+ (API 30). Everything that touches it lives in
//    [ExitReasonsApi30], a separate class that is only ever loaded after an
//    explicit Build.VERSION.SDK_INT check, so older devices (the app supports
//    down to Flutter's minSdk) never even load a class that mentions
//    ApplicationExitInfo.
//  - Every read is wrapped in try/catch(Throwable) and returns text instead of
//    throwing; callers also run it off the main thread.
object ExitReasons {
    class Entry(val timestamp: Long, val text: String, val reason: Int, val trace: String? = null)

    const val UNAVAILABLE_BELOW_API = 30

    // Reasons worth an automatic diagnostic upload (AutoLogUploader) — a real
    // crash/ANR, not a normal exit (user-requested, low-memory eviction, OS
    // package changes, ...). Values = ApplicationExitInfo.REASON_*.
    val CRASH_REASONS = setOf(4, 5, 6) // CRASH, CRASH_NATIVE, ANR

    /** Pure and Android-free, so it is unit-tested. Values = ApplicationExitInfo.REASON_*. */
    fun reasonName(reason: Int): String = when (reason) {
        0 -> "UNKNOWN"
        1 -> "EXIT_SELF"
        2 -> "SIGNALED"
        3 -> "LOW_MEMORY"
        4 -> "CRASH"
        5 -> "CRASH_NATIVE"
        6 -> "ANR"
        7 -> "INITIALIZATION_FAILURE"
        8 -> "PERMISSION_CHANGE"
        9 -> "EXCESSIVE_RESOURCE_USAGE"
        10 -> "USER_REQUESTED"
        11 -> "USER_STOPPED"
        12 -> "DEPENDENCY_DIED"
        13 -> "OTHER"
        14 -> "FREEZER"
        15 -> "PACKAGE_STATE_CHANGE"
        16 -> "PACKAGE_UPDATED"
        else -> "REASON_$reason"
    }

    /** The main thread's block from an ANR trace (Android's own dump of every
     * thread when the app stopped responding). Pure, so it is unit-tested. */
    fun mainThreadSection(trace: String, maxChars: Int = 6000): String {
        val lines = trace.lines()
        val start = lines.indexOfFirst { it.startsWith("\"main\" ") }
        if (start < 0) return trace.take(maxChars)
        val sb = StringBuilder()
        for (i in start until lines.size) {
            if (i > start && lines[i].isBlank()) break
            sb.append(lines[i]).append('\n')
            if (sb.length >= maxChars) break
        }
        return sb.toString().take(maxChars)
    }

    fun unavailableNote(): String =
        "EXIT REASONS: not available on Android ${Build.VERSION.RELEASE} (api ${Build.VERSION.SDK_INT}) — needs Android 11 (api 30) or newer"

    /** Newest first. Never throws. Empty list + a note is NOT returned here — see [text]. */
    fun entries(context: Context, limit: Int = 5): List<Entry> {
        if (Build.VERSION.SDK_INT < UNAVAILABLE_BELOW_API) return emptyList()
        return try {
            ExitReasonsApi30.read(context, limit)
        } catch (_: Throwable) {
            emptyList()
        }
    }

    /** Whole report as text, for the Settings tool. Never throws. */
    fun text(context: Context, limit: Int = 5): String {
        if (Build.VERSION.SDK_INT < UNAVAILABLE_BELOW_API) return unavailableNote()
        return try {
            val list = ExitReasonsApi30.read(context, limit)
            if (list.isEmpty()) "EXIT REASONS: Android has none recorded for this app yet."
            else list.joinToString("\n") { it.text }
        } catch (t: Throwable) {
            "EXIT REASONS: could not be read (${t.javaClass.simpleName}: ${t.message})"
        }
    }
}

// Only loaded on API 30+.
internal object ExitReasonsApi30 {
    fun read(context: Context, limit: Int): List<ExitReasons.Entry> {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        return am.getHistoricalProcessExitReasons(context.packageName, 0, limit).map { e: ApplicationExitInfo ->
            ExitReasons.Entry(
                e.timestamp,
                "EXIT REASON at ${fmt.format(Date(e.timestamp))} reason=${ExitReasons.reasonName(e.reason)}(${e.reason}) " +
                    "status=${e.status} importance=${e.importance} pid=${e.pid} process=${e.processName} " +
                    "pss=${e.pss}KB rss=${e.rss}KB description='${e.description}'",
                e.reason,
                traceOf(e),
            )
        }
    }

    // ANR: Android keeps a text dump of all threads. A native crash keeps a binary
    // tombstone, which is only noted (size), not decoded. Never throws; the stream
    // is null when the system kept no trace (or this vendor's build does not).
    private fun traceOf(e: ApplicationExitInfo): String? = try {
        when (e.reason) {
            6 -> e.traceInputStream?.use { s ->
                ExitReasons.mainThreadSection(String(s.readBytes().take(400_000).toByteArray(), Charsets.UTF_8))
            }?.takeIf { it.isNotBlank() } ?: "(no ANR trace kept by the system)"
            5 -> e.traceInputStream?.use { s -> "native crash tombstone kept by the system: ${s.readBytes().size} bytes (binary, not decoded here)" }
                ?: "(no native crash trace kept by the system)"
            else -> null
        }
    } catch (t: Throwable) {
        "(trace could not be read: ${t.javaClass.simpleName}: ${t.message})"
    }
}
