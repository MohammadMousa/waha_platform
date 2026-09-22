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
    class Entry(val timestamp: Long, val text: String)

    const val UNAVAILABLE_BELOW_API = 30

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
            )
        }
    }
}
