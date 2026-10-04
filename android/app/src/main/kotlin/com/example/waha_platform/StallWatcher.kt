package com.example.waha_platform

/**
 * Names what the main (UI) thread is stuck on while it is stuck.
 *
 * The main thread keeps a heartbeat (a timestamp it refreshes every ~500 ms).
 * This watcher runs on its OWN thread, and when the heartbeat goes quiet for
 * 1.5 s it logs the main thread's current stack, again at 3 s and 5 s — so the
 * log shows the call it is sitting in (an SDK call, a file write, a system
 * call), not just that it froze.
 *
 * Safeguards: it ignores stretches where the watcher itself was delayed (the
 * whole app was paused or the device slept — not a main-thread stall), limits
 * itself to three dumps per stall and [maxDumpsPerHour] per hour, and does
 * nothing while [enabled] is false (logging off).
 *
 * [step] holds all the logic and is driven by a fake clock in the unit tests;
 * [start] only adds the thread that calls it.
 */
class StallWatcher(
    private val lastBeat: () -> Long,
    private val clock: () -> Long,
    private val enabled: () -> Boolean,
    private val stack: () -> String,
    private val log: (String) -> Unit,
    private val pollMs: Long = 500L,
    private val dumpAtMs: LongArray = longArrayOf(1500L, 3000L, 5000L),
    private val maxDumpsPerHour: Int = 30,
    private val pausedMs: Long = 1500L,
) {
    private var lastCheckAt = clock()
    private var graceUntil = 0L
    private var nextDump = 0
    private val dumpTimes = ArrayDeque<Long>()

    @Volatile private var running = false
    private var thread: Thread? = null

    fun step(now: Long) {
        val drift = now - lastCheckAt - pollMs
        lastCheckAt = now
        if (!enabled()) {
            nextDump = 0
            return
        }
        if (drift >= pausedMs) {
            log("APP PAUSED ~${drift}ms — the watcher itself was delayed (whole app frozen or device asleep), not counted as a main-thread stall")
            nextDump = 0
            graceUntil = now + 2 * pollMs
            return
        }
        if (now < graceUntil) return
        val quiet = now - lastBeat()
        if (quiet < 2 * pollMs) {
            nextDump = 0
            return
        }
        if (nextDump < dumpAtMs.size && quiet >= dumpAtMs[nextDump]) {
            nextDump++
            while (dumpTimes.isNotEmpty() && now - dumpTimes.first() > 3_600_000L) dumpTimes.removeFirst()
            if (dumpTimes.size < maxDumpsPerHour) {
                dumpTimes.addLast(now)
                log("MAIN THREAD BLOCKED ${quiet}ms — it is currently in:\n${stack()}")
            }
        }
    }

    fun start() {
        if (running) return
        running = true
        lastCheckAt = clock()
        val t = Thread {
            while (running) {
                try {
                    Thread.sleep(pollMs)
                    step(clock())
                } catch (_: InterruptedException) {
                    return@Thread
                } catch (_: Throwable) {
                    // Diagnostics must never be a crash source.
                }
            }
        }
        t.isDaemon = true
        t.name = "waha-stall-watcher"
        t.priority = Thread.MIN_PRIORITY
        thread = t
        t.start()
    }

    fun stop() {
        running = false
        thread?.interrupt()
        thread = null
    }

    companion object {
        /** Top frames of [t]'s current stack, one per line. */
        fun stackOf(t: Thread, maxFrames: Int = 40): String =
            t.stackTrace.take(maxFrames).joinToString("\n") { "    at $it" }
    }
}
