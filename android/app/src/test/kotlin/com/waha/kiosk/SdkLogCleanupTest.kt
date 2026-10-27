package com.waha.kiosk

import org.junit.Assert.assertEquals
import org.junit.Test

class SdkLogCleanupTest {
    private val day = 24L * 60 * 60 * 1000
    private val now = 100 * day

    private fun e(name: String, ageDays: Int) = SdkLogCleanup.Entry(name, now - ageDays * day)

    @Test fun oldFilesBeyondTheNewestTwoAreRemoved() {
        val files = listOf(
            e("pending_3.log", 0), e("pending_2.log", 1), e("pending_1.log", 5), e("pending_0.log", 9),
            e("Android_TCP_SDK_3.log", 0), e("Android_TCP_SDK_2.log", 6),
        )
        assertEquals(listOf("pending_1.log", "pending_0.log"), SdkLogCleanup.namesToDelete(files, now))
    }

    @Test fun theNewestTwoOfAKindAreKeptEvenWhenOld() {
        val files = listOf(e("pending_2.log", 30), e("pending_1.log", 40))
        assertEquals(emptyList<String>(), SdkLogCleanup.namesToDelete(files, now))
    }

    @Test fun recentFilesAreKeptAndOtherFilesAreNeverTouched() {
        val files = listOf(
            e("pending_4.log", 0), e("pending_3.log", 1), e("pending_2.log", 2),
            e("notes.txt", 50), e("other.log", 50),
        )
        assertEquals(emptyList<String>(), SdkLogCleanup.namesToDelete(files, now))
    }
}
