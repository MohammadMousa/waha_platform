package com.example.waha_platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class TraceWriterTest {
    @Test
    fun linesAreWrittenInTheOrderTheyWereQueued() {
        val w = TraceWriter()
        val out = java.util.Collections.synchronizedList(ArrayList<Int>())
        for (i in 0 until 2000) w.post { out.add(i) }
        assertTrue(w.flush(5000))
        assertEquals((0 until 2000).toList(), out.toList())
    }

    @Test
    fun postReturnsImmediatelyEvenWhenTheWriterIsBusy() {
        val w = TraceWriter()
        val release = CountDownLatch(1)
        w.post { release.await(5, TimeUnit.SECONDS) } // a stalled disk
        val t0 = System.nanoTime()
        repeat(100) { w.post { } }
        val tookMs = (System.nanoTime() - t0) / 1_000_000
        assertTrue("post blocked the caller for ${tookMs}ms", tookMs < 200)
        release.countDown()
        assertTrue(w.flush(5000))
    }

    @Test
    fun aFullQueueDropsAndCountsInsteadOfBlocking() {
        val w = TraceWriter(capacity = 10)
        val release = CountDownLatch(1)
        val started = CountDownLatch(1)
        w.post { started.countDown(); release.await(5, TimeUnit.SECONDS) }
        assertTrue(started.await(2, TimeUnit.SECONDS))
        repeat(50) { w.post { } } // 10 fit, the rest are dropped
        assertEquals(40L, w.droppedCount())
        assertEquals(40L, w.takeDropped())
        assertEquals(0L, w.takeDropped())
        release.countDown()
        assertTrue(w.flush(5000))
    }

    @Test
    fun aThrowingTaskDoesNotStopLaterOnes() {
        val w = TraceWriter()
        var ran = false
        w.post { throw IllegalStateException("disk gone") }
        w.post { ran = true }
        assertTrue(w.flush(5000))
        assertTrue(ran)
    }

    @Test
    fun flushGivesUpAtTheTimeoutWhenTheWriterIsStuck() {
        val w = TraceWriter()
        val release = CountDownLatch(1)
        w.post { release.await(5, TimeUnit.SECONDS) }
        assertFalse(w.flush(100))
        release.countDown()
        assertTrue(w.flush(5000))
    }

    @Test
    fun healthBlockShowsSizesAndFlagsAFileOverTheLimit() {
        fun snap(now: Long) = LogHealth.Snapshot(now, 3_000_000, 1_500_000, 1_000_000, 2, 0, 3_100_000, 1_500_000, 0, 0, 0, 0, 0)
        val ok = LogHealth.format(snap(2_000_000))
        assertTrue(ok.contains("traceFileNow=2000000 bytes (limit 3000000, trims down to 1500000)"))
        assertTrue(ok.contains("traceIncludedInThisReport=1000000 bytes of 2000000"))
        assertTrue(ok.contains("trims=2 lastTrim=never from=3100000 to=1500000"))
        assertFalse(ok.contains("OVER THE LIMIT"))
        assertTrue(LogHealth.format(snap(3_500_000)).contains("OVER THE LIMIT"))
    }
}
