package com.example.waha_platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExitReasonsTest {
    @Test fun knownReasonsHaveNames() {
        assertEquals("CRASH", ExitReasons.reasonName(4))
        assertEquals("CRASH_NATIVE", ExitReasons.reasonName(5))
        assertEquals("ANR", ExitReasons.reasonName(6))
        assertEquals("LOW_MEMORY", ExitReasons.reasonName(3))
        assertEquals("USER_REQUESTED", ExitReasons.reasonName(10))
        assertEquals("USER_STOPPED", ExitReasons.reasonName(11))
        assertEquals("EXIT_SELF", ExitReasons.reasonName(1))
    }

    @Test fun unknownReasonNeverThrows() {
        assertEquals("REASON_99", ExitReasons.reasonName(99))
        assertEquals("REASON_-1", ExitReasons.reasonName(-1))
    }

    @Test fun mainThreadSectionPicksTheMainThreadBlockOnly() {
        val trace = """
            ----- pid 3419 at 2026-09-30 07:34:52 -----
            Cmd line: com.example.waha_platform

            "Signal Catcher" daemonprio=5 tid=2 Runnable
              native: #00 pc 0001

            "main" prio=5 tid=1 Blocked
              at geidea.net.Foo.disconnectUsbSerialConnection(Foo.java:10)
              at com.example.waha_platform.MainActivity.prepare(MainActivity.kt:700)

            "Binder:3419_1" prio=5 tid=5 Native
              native: #00 pc 0002
        """.trimIndent()
        val out = ExitReasons.mainThreadSection(trace)
        assertTrue(out.startsWith("\"main\" prio=5"))
        assertTrue(out.contains("disconnectUsbSerialConnection"))
        assertFalse(out.contains("Binder:3419_1"))
        assertFalse(out.contains("Signal Catcher"))
    }

    @Test fun mainThreadSectionFallsBackToTheStartWhenThereIsNoMainBlock() {
        assertEquals("abc", ExitReasons.mainThreadSection("abcdef", 3))
    }
}
