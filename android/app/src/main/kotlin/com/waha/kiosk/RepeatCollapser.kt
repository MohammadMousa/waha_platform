package com.waha.kiosk

/**
 * Keeps a repeated block of log text from being written again and again.
 *
 * The first time a block is offered (or when it differs from the last one) it
 * is returned in full. When it is the same as the last one, a one-line note
 * with the count and the first and last time is returned instead. The state
 * must be [reset] whenever the log file is emptied or trimmed, otherwise the
 * next report would only say "unchanged" about text that is no longer in the
 * file.
 *
 * Lines that differ per payment are never passed through here — only heavy
 * dumps that are identical from one report to the next (the USB inventory).
 */
class RepeatCollapser {
    private class State(var text: String, val firstAt: Long, var lastAt: Long, var count: Int)

    private val states = HashMap<String, State>()

    @Synchronized
    fun offer(key: String, label: String, text: String, nowMs: Long, clock: (Long) -> String): String {
        val s = states[key]
        if (s != null && s.text == text) {
            s.count++
            s.lastAt = nowMs
            return "$label unchanged: seen x${s.count}, first ${clock(s.firstAt)}, last ${clock(nowMs)}"
        }
        states[key] = State(text, nowMs, nowMs, 1)
        return text
    }

    @Synchronized
    fun reset() = states.clear()

    companion object {
        /** The one shared by every report in the process. */
        val shared = RepeatCollapser()
    }
}
