package com.example.waha_platform

import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * One background thread that does the trace log's disk work (trim check,
 * open, append), so callers — often the UI thread — only queue the line and
 * return. A single thread keeps the lines in the order they were queued.
 *
 * The queue is bounded: if the disk stalls long enough to fill it, new lines
 * are dropped and counted instead of growing memory without limit or blocking
 * the caller. The count is reported with [takeDropped].
 *
 * Diagnostic-only plumbing: a task that throws is swallowed — logging must
 * never become a crash source (same rule as the old inline write).
 */
class TraceWriter(capacity: Int = 20_000, threadName: String = "waha-trace-writer") {
    private val executor = ThreadPoolExecutor(
        1, 1, 0L, TimeUnit.MILLISECONDS,
        LinkedBlockingQueue<Runnable>(capacity),
        { r -> Thread(r, threadName).apply { isDaemon = true } },
        ThreadPoolExecutor.AbortPolicy(),
    )
    private val dropped = AtomicLong(0)

    /** Queue [task] to run on the writer thread. Never blocks, never throws. */
    fun post(task: () -> Unit) {
        try {
            executor.execute {
                try {
                    task()
                } catch (_: Throwable) {
                    // best-effort
                }
            }
        } catch (_: RejectedExecutionException) {
            dropped.incrementAndGet()
        }
    }

    /** Waits until everything queued before this call has been written, or
     * [timeoutMs] passes. True if the queue was drained in time. */
    fun flush(timeoutMs: Long): Boolean {
        val done = CountDownLatch(1)
        try {
            executor.execute { done.countDown() }
        } catch (_: RejectedExecutionException) {
            return false
        }
        return try {
            done.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
    }

    /** Lines dropped (queue full) since the last call; resets to zero. */
    fun takeDropped(): Long = dropped.getAndSet(0)

    /** Lines dropped so far and not yet taken, without resetting. */
    fun droppedCount(): Long = dropped.get()
}

/** The one writer shared by every logTrace() caller in the process. */
object TraceLogWriter {
    val writer = TraceWriter()
}
