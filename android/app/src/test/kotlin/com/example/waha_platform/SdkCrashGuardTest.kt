package com.example.waha_platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SdkCrashGuardTest {
    private fun sdkNpe() = NullPointerException("queue on a null object").apply {
        stackTrace = arrayOf(
            StackTraceElement("geidea.net.terminal_comm_api.Q", "run", "Q.java", 1),
            StackTraceElement("java.lang.Thread", "run", "Thread.java", 1),
        )
    }

    private fun appNpe() = NullPointerException("our own bug").apply {
        stackTrace = arrayOf(
            StackTraceElement("com.example.waha_platform.MainActivity", "foo", "MainActivity.kt", 1),
            StackTraceElement("java.lang.Thread", "run", "Thread.java", 1),
        )
    }

    @Test fun anSdkThreadFailureIsContained() {
        assertTrue(SdkCrashGuard().contain(false, sdkNpe(), 1_000))
    }

    @Test fun theMainThreadIsNeverContained() {
        assertFalse(SdkCrashGuard().contain(true, sdkNpe(), 1_000))
    }

    @Test fun ourOwnCodeIsNeverContained() {
        assertFalse(SdkCrashGuard().contain(false, appNpe(), 1_000))
    }

    @Test fun anErrorIsNeverContained() {
        val oom = OutOfMemoryError().apply {
            stackTrace = arrayOf(StackTraceElement("geidea.net.terminal_comm_api.Q", "run", "Q.java", 1))
        }
        assertFalse(SdkCrashGuard().contain(false, oom, 1_000))
    }

    @Test fun theSdkFrameMayBeDeeperInTheStack() {
        val e = IllegalStateException("x").apply {
            stackTrace = arrayOf(
                StackTraceElement("java.util.ArrayList", "get", "ArrayList.java", 1),
                StackTraceElement("i2.a", "queue", "a.java", 1),
                StackTraceElement("geidea.net.terminal_comm_api.Q", "run", "Q.java", 1),
            )
        }
        assertTrue(SdkCrashGuard().contain(false, e, 1_000))
    }

    @Test fun thirdTimeInAMinuteIsStillContainedButTheFourthIsNot() {
        val g = SdkCrashGuard()
        assertTrue(g.contain(false, sdkNpe(), 1_000))
        assertTrue(g.contain(false, sdkNpe(), 2_000))
        assertTrue(g.contain(false, sdkNpe(), 3_000))
        assertFalse(g.contain(false, sdkNpe(), 4_000))
        assertEquals(3, g.recent(4_000))
    }

    @Test fun theLimitResetsWhenTheWindowPasses() {
        val g = SdkCrashGuard()
        repeat(3) { assertTrue(g.contain(false, sdkNpe(), 1_000L + it)) }
        assertFalse(g.contain(false, sdkNpe(), 30_000))
        assertTrue(g.contain(false, sdkNpe(), 62_000))
    }
}
