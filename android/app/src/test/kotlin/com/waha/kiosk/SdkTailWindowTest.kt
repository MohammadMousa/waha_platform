package com.waha.kiosk

import org.junit.Assert.assertEquals
import org.junit.Test

class SdkTailWindowTest {
    @Test fun firstReadTakesTheEndWindow() {
        val r = SdkTailWindow.next("a.log", 100_000, null, 0, 5_000)
        assertEquals(95_000L, r.start); assertEquals(100_000L, r.end); assertEquals(95_000L, r.skipped)
    }

    @Test fun smallFileIsReadWholeTheFirstTime() {
        val r = SdkTailWindow.next("a.log", 3_000, null, 0, 5_000)
        assertEquals(0L, r.start); assertEquals(0L, r.skipped)
    }

    @Test fun nextReadAddsOnlyNewBytes() {
        val r = SdkTailWindow.next("a.log", 8_000, "a.log", 6_500, 5_000)
        assertEquals(6_500L, r.start); assertEquals(8_000L, r.end); assertEquals(0L, r.skipped)
    }

    @Test fun capLimitsWhatIsAddedAndSaysWhatWasSkipped() {
        val r = SdkTailWindow.next("a.log", 20_000, "a.log", 6_500, 5_000)
        assertEquals(15_000L, r.start); assertEquals(8_500L, r.skipped)
    }

    @Test fun aNewFileNameStartsOver() {
        val r = SdkTailWindow.next("b.log", 2_000, "a.log", 6_500, 5_000)
        assertEquals(0L, r.start); assertEquals(0L, r.skipped)
    }

    @Test fun aTruncatedFileStartsOver() {
        val r = SdkTailWindow.next("a.log", 1_000, "a.log", 6_500, 5_000)
        assertEquals(0L, r.start); assertEquals(1_000L, r.end)
    }
}
