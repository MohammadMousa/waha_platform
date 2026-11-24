package com.waha.kiosk

/**
 * Which bytes of the SDK's own log file a report should add: only what is new
 * since the last report, never more than [cap]. When the file is not the one
 * read last time (the SDK starts a new file at each run) or is shorter than
 * before (truncated), reading starts again from the end window.
 *
 * Pure arithmetic so it can be unit-tested; the file reading is in
 * [TerminalDiagnostics.sdkLogFileTail].
 */
object SdkTailWindow {
    /** [start] to [end] is the range to read; [skipped] bytes of new text were left out by the cap. */
    class Range(val start: Long, val end: Long, val skipped: Long)

    fun next(name: String, size: Long, lastName: String?, lastOffset: Long, cap: Long): Range {
        val sameFile = name == lastName && size >= lastOffset
        val from = if (sameFile) lastOffset else 0L
        val newBytes = size - from
        if (newBytes <= cap) return Range(from, size, 0L)
        return Range(size - cap, size, newBytes - cap)
    }
}
