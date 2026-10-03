package com.example.waha_platform

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The "LOG FILE HEALTH" block at the top of an uploaded report. It exists so
 * whoever reads the log can see, without trusting anything else, that the
 * size-control (trim at the limit, clear after a good upload) is actually
 * running: the file size now against the limit, how big this report's trace
 * section is against the whole file, and when the file was last trimmed or
 * cleared and from/to what size.
 */
object LogHealth {
    class Snapshot(
        val fileBytesNow: Long,
        val limitBytes: Long,
        val keepBytes: Long,
        val traceBytesInReport: Long,
        val trimCount: Long,
        val lastTrimAtMs: Long,
        val lastTrimBeforeBytes: Long,
        val lastTrimAfterBytes: Long,
        val lastClearAtMs: Long,
        val lastClearedBytes: Long,
        val lastUploadAtMs: Long,
        val lastUploadReportBytes: Long,
        val writerDroppedLines: Long,
    )

    private fun time(ms: Long): String =
        if (ms <= 0L) "never" else SimpleDateFormat("yyyy-MM-dd HH:mm:ss Z", Locale.US).format(Date(ms))

    fun format(s: Snapshot): String {
        val over = if (s.fileBytesNow > s.limitBytes) "  <-- OVER THE LIMIT, trimming is not keeping up" else ""
        return buildString {
            append("=== LOG FILE HEALTH ===\n")
            append("traceFileNow=${s.fileBytesNow} bytes (limit ${s.limitBytes}, trims down to ${s.keepBytes})$over\n")
            append("traceIncludedInThisReport=${s.traceBytesInReport} bytes of ${s.fileBytesNow}\n")
            append("trims=${s.trimCount} lastTrim=${time(s.lastTrimAtMs)} from=${s.lastTrimBeforeBytes} to=${s.lastTrimAfterBytes}\n")
            append("lastClearAfterUpload=${time(s.lastClearAtMs)} cleared=${s.lastClearedBytes} bytes\n")
            append("previousUpload=${time(s.lastUploadAtMs)} reportBytes=${s.lastUploadReportBytes}\n")
            append("writerDroppedLines=${s.writerDroppedLines}\n\n")
        }
    }
}
