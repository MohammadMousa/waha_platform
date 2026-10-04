package com.example.waha_platform

/**
 * Helpers for re-opening the Geidea SDK's background USB service when the SDK
 * has lost it.
 *
 * The SDK binds that service once, when the app opens the USB connection at
 * start. About a minute after the app is stopped (covered or sent to the
 * background) the SDK destroys it, and nothing re-binds it when the app comes
 * back. From then on every command written goes nowhere, a reconnect throws
 * "USB Service not connected", and only restarting the app brings it back —
 * while the app's own "connected" flag keeps saying true.
 */
object ServiceRecovery {
    /** True for an SDK log line saying its USB service was unbound or destroyed. */
    fun isServiceLostLine(line: String): Boolean =
        line.contains("SERVICE UNBOUNDED") || line.contains("Service destroyed")

    /** True for the exception text of a connect attempted while the service is gone. */
    fun isServiceNotConnectedMessage(message: String?): Boolean =
        message?.contains("USB Service not connected") == true

    /**
     * Polls [condition] every [pollMs] until it is true or [maxMs] have passed.
     * Returns whether it became true. Clock and sleep are injectable so the
     * tests need no real waiting.
     */
    fun waitUntil(
        maxMs: Long,
        pollMs: Long = 100L,
        now: () -> Long = { System.currentTimeMillis() },
        sleep: (Long) -> Unit = { Thread.sleep(it) },
        condition: () -> Boolean,
    ): Boolean {
        val deadline = now() + maxMs
        while (true) {
            if (condition()) return true
            if (now() >= deadline) return false
            sleep(pollMs)
        }
    }
}

/**
 * Stops two re-open requests from overlapping or looping: a new one is allowed
 * only [minGapMs] after the previous one. (Re-opening makes the SDK log "service
 * unbound/destroyed" for the old binding — that must not trigger another re-open.)
 */
class ReopenLimiter(private val minGapMs: Long = 3_000L, private val clock: () -> Long) {
    private val none = Long.MIN_VALUE
    private var last = none

    @Synchronized
    fun tryAcquire(): Boolean {
        val now = clock()
        if (last != none && now - last < minGapMs) return false
        last = now
        return true
    }
}
