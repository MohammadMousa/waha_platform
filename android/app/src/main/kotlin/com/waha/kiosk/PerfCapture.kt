package com.waha.kiosk

import android.app.ActivityManager
import android.content.Context
import android.os.Process
import android.os.SystemClock
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The performance snapshot that is added to every upload (and written once at
 * each scheduled restart): memory, load, process uptime and the log level
 * from this side, and the counters Flutter keeps (frame times, database and
 * sync timing, sounds played) from the other.
 *
 * Taken just before an upload is built, not on a timer. The upload waits for
 * Flutter's answer, but only [FRESH_TIMEOUT_MS]: the app may be frozen — the
 * very case worth seeing — or not running at all (crash screen). Then the
 * last snapshot Flutter handed over (at the end of a payment, of a sync pull,
 * or at a heartbeat) is used and its age is printed.
 *
 * Counting happens only while logging is on; with logging off Flutter reports
 * "off" and nothing is measured.
 */
object PerfCapture {
    const val FRESH_TIMEOUT_MS = 3000L

    /** Set by MainActivity: asks Flutter for its snapshot, answers through the callback. */
    @Volatile var requester: ((callback: (String?) -> Unit) -> Unit)? = null

    @Volatile private var cached: String? = null
    @Volatile private var cachedAt = 0L

    /** Flutter hands over its counters (end of a payment, of a pull, heartbeat). */
    fun push(text: String, nowMs: Long = System.currentTimeMillis()) {
        cached = text
        cachedAt = nowMs
    }

    private fun clock(ms: Long) = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date(ms))

    /** What Flutter counted: fresh if it answers in time, otherwise the last one, with its age. Blocking — not for the main thread. */
    fun flutterPart(nowMs: Long = System.currentTimeMillis()): String {
        val ask = requester
        var timedOut = false
        if (ask != null) {
            val latch = CountDownLatch(1)
            var got: String? = null
            try {
                ask { v -> got = v; latch.countDown() }
                if (latch.await(FRESH_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                    val v = got
                    if (v != null) {
                        push(v, nowMs)
                        return "captured just now: $v"
                    }
                } else {
                    timedOut = true
                }
            } catch (_: Throwable) {
                timedOut = true
            }
        }
        val c = cached
        val note = if (ask == null) "the app screen is not running" else if (timedOut) "fresh capture timed out after ${FRESH_TIMEOUT_MS / 1000}s" else "fresh capture not available"
        return if (c == null) "no snapshot available ($note)"
        else "as of ${clock(cachedAt)}, ${(nowMs - cachedAt) / 60000} min ago ($note): $c"
    }

    /** Tablet and app numbers read now. Cheap file reads and one system call; run on a background thread. */
    fun nativePart(context: Context, level: String): String {
        val sb = StringBuilder()
        sb.append("log_level=").append(level)
        try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val mi = ActivityManager.MemoryInfo()
            am.getMemoryInfo(mi)
            sb.append(" | tablet memory free=").append(mi.availMem / 1048576).append("MB of ").append(mi.totalMem / 1048576).append("MB")
            val pss = am.getProcessMemoryInfo(intArrayOf(Process.myPid())).firstOrNull()?.totalPss
            if (pss != null) sb.append(" | app memory=").append(pss / 1024).append("MB")
        } catch (t: Throwable) {
            sb.append(" | memory not readable (").append(t.javaClass.simpleName).append(')')
        }
        sb.append(" | ").append(SystemSnapshot.compact())
        try {
            val age = SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime()
            sb.append(" | app uptime=").append(age / 60000).append("min")
        } catch (_: Throwable) {
        }
        return sb.toString()
    }

    /** The block printed at the top of an upload, and once at each scheduled restart. */
    fun block(context: Context, level: String): String =
        "=== PERFORMANCE SNAPSHOT ===\ntablet/app: ${nativePart(context, level)}\nscreen/database/sync/sounds: ${flutterPart()}\n"
}
