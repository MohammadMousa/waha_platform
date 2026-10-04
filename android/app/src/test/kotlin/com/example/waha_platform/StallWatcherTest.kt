package com.example.waha_platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StallWatcherTest {
    private var now = 10_000L
    private var beat = 10_000L
    private var on = true
    private val logs = ArrayList<String>()

    private fun watcher(maxPerHour: Int = 30) = StallWatcher(
        lastBeat = { beat }, clock = { now }, enabled = { on },
        stack = { "    at Blocked.call(File.kt:1)" }, log = { logs.add(it) },
        maxDumpsPerHour = maxPerHour,
    )

    /** Advance time by one poll; the main thread beats only while [mainAlive]. */
    private fun tick(w: StallWatcher, mainAlive: Boolean) {
        now += 500
        if (mainAlive) beat = now
        w.step(now)
    }

    @Test fun aHealthyMainThreadNeverLogs() {
        val w = watcher()
        repeat(100) { tick(w, true) }
        assertTrue(logs.isEmpty())
    }

    @Test fun aBlockedMainThreadIsDumpedAt1_5s_3s_and_5sOnly() {
        val w = watcher()
        repeat(4) { tick(w, true) }
        repeat(40) { tick(w, false) } // 20 s of silence
        assertEquals(3, logs.size)
        assertTrue(logs.all { it.contains("MAIN THREAD BLOCKED") && it.contains("Blocked.call") })
    }

    @Test fun aNewStallAfterRecoveryIsDumpedAgain() {
        val w = watcher()
        repeat(10) { tick(w, false) }
        val first = logs.size
        repeat(4) { tick(w, true) }
        repeat(10) { tick(w, false) }
        assertTrue(logs.size > first)
    }

    @Test fun aPausedProcessIsNotCountedAsAMainThreadStall() {
        val w = watcher()
        repeat(4) { tick(w, true) }
        now += 30_000 // the whole app froze or the device slept; nothing beat meanwhile
        w.step(now)
        repeat(6) { tick(w, true) }
        assertEquals(1, logs.size)
        assertTrue(logs[0].startsWith("APP PAUSED"))
    }

    @Test fun nothingIsLoggedWhileLoggingIsOff() {
        val w = watcher()
        on = false
        repeat(40) { tick(w, false) }
        assertTrue(logs.isEmpty())
    }

    @Test fun dumpsAreCappedPerHour() {
        val w = watcher(maxPerHour = 4)
        repeat(20) { // 20 separate stalls
            repeat(3) { tick(w, true) }
            repeat(12) { tick(w, false) }
        }
        assertEquals(4, logs.count { it.contains("MAIN THREAD BLOCKED") })
        assertFalse(logs.any { it.contains("APP PAUSED") })
    }
}
