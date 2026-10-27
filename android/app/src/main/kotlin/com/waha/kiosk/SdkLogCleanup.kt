package com.waha.kiosk

import android.content.Context
import java.io.File

// The Geidea SDK writes its own log files (pending_<time>.log, about 1 MB
// each, and Android_TCP_SDK_<time>.log) and never removes them. They hold
// terminal and card data, so old ones are deleted at app start: a file goes
// only when it is older than [MAX_AGE_MS] AND is not one of the newest
// [KEEP_NEWEST] files of its kind (the files of the current and the previous
// run are always kept). The selection is pure so it can be unit-tested.
object SdkLogCleanup {
    const val MAX_AGE_MS = 3L * 24 * 60 * 60 * 1000
    const val KEEP_NEWEST = 2

    class Entry(val name: String, val lastModified: Long)

    private val kinds = listOf("pending_", "Android_TCP_SDK_")

    fun namesToDelete(files: List<Entry>, now: Long, maxAgeMs: Long = MAX_AGE_MS, keepNewest: Int = KEEP_NEWEST): List<String> =
        kinds.flatMap { prefix ->
            files.filter { it.name.startsWith(prefix) && it.name.endsWith(".log") }
                .sortedByDescending { it.lastModified }
                .drop(keepNewest)
                .filter { now - it.lastModified > maxAgeMs }
                .map { it.name }
        }

    /** Deletes the old files; returns a one-line summary for the trace log. */
    fun run(context: Context, now: Long = System.currentTimeMillis()): String {
        val dir = File(context.filesDir, TerminalDiagnostics.SDK_LOG_SUBDIR)
        if (!dir.isDirectory) return "SDK log cleanup: no SDK log folder"
        val files = dir.listFiles()?.filter { it.isFile }.orEmpty()
        val doomed = namesToDelete(files.map { Entry(it.name, it.lastModified()) }, now)
        var freed = 0L
        var removed = 0
        for (name in doomed) {
            val f = File(dir, name)
            val size = f.length()
            if (f.delete()) {
                removed++
                freed += size
            }
        }
        return "SDK log cleanup: removed $removed old file(s), freed ${freed / 1024} KB, ${files.size - removed} kept"
    }
}
