package com.example.waha_platform

/**
 * Decides whether an uncaught exception may be CONTAINED instead of killing the
 * app.
 *
 * The Geidea SDK runs its own threads, and on a USB re-attach one of them has
 * been seen to die with a NullPointerException deep inside the SDK, which took
 * the whole kiosk app down (and left it down until someone restarted it). This
 * lets exactly that kind of failure — and nothing else — be survived:
 *  - the thread is NOT the main thread;
 *  - the exception is a RuntimeException (never an Error such as out-of-memory);
 *  - one of the top stack frames is inside the SDK package (`geidea.net.`);
 *  - and it has not happened more than [maxPerWindow] times within [windowMs].
 *
 * Anything that fails one of these goes to the normal crash path. The caller
 * must always log the full stack and trigger an upload, so containing a crash
 * never hides it.
 */
class SdkCrashGuard(
    private val maxPerWindow: Int = 3,
    private val windowMs: Long = 60_000L,
    private val sdkPackage: String = "geidea.net.",
    private val framesToCheck: Int = 10,
) {
    private val times = ArrayDeque<Long>()

    /** True if the crash was contained (and counted); false = let it crash. */
    @Synchronized
    fun contain(isMainThread: Boolean, error: Throwable, nowMs: Long): Boolean {
        if (isMainThread) return false
        if (error !is RuntimeException) return false
        if (error.stackTrace.take(framesToCheck).none { it.className.startsWith(sdkPackage) }) return false
        while (times.isNotEmpty() && nowMs - times.first() > windowMs) times.removeFirst()
        if (times.size >= maxPerWindow) return false
        times.addLast(nowMs)
        return true
    }

    /** How many contained crashes are inside the current window. */
    @Synchronized
    fun recent(nowMs: Long): Int {
        while (times.isNotEmpty() && nowMs - times.first() > windowMs) times.removeFirst()
        return times.size
    }
}
