package com.waha.kiosk

import com.waha.kiosk.RepairRestartGate.Record
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SdkRepairTest {
    private var now = 1_000L
    private fun state() = SdkPortState(clock = { now })

    private var connects = 0
    private var gaveUp = 0
    private val logs = mutableListOf<String>()

    /** A runner on a fake clock: waiting advances [now] instead of sleeping. */
    private fun runner(s: SdkPortState, settled: () -> Boolean = { true }, onConnect: () -> Unit = {}) =
        SdkRepairRunner(
            state = s,
            usbSettled = settled,
            connect = { connects++; onConnect() },
            log = { logs.add(it) },
            onGaveUp = { gaveUp++ },
            waitUntil = { maxMs, condition ->
                ServiceRecovery.waitUntil(maxMs, pollMs = 1_000L, now = { now }, sleep = { now += it }, condition = condition)
            },
        )

    @Test fun aCrashMarksThePortBrokenAndStartsOneWorker() {
        val s = state()
        assertFalse(s.broken)
        assertTrue(s.onSdkCrash())
        assertTrue(s.broken)
        assertFalse(s.onSdkCrash())
    }

    @Test fun repairEndsWhenThePortOpens() {
        val s = state()
        s.onSdkCrash()
        runner(s, onConnect = { s.onPortHealthy() }).run()
        assertEquals(1, connects)
        assertEquals(0, gaveUp)
        assertFalse(s.broken)
        assertFalse(s.repairFailed)
        assertTrue("a later crash starts a new worker", s.onSdkCrash())
    }

    @Test fun threeAttemptsThenItGivesUp() {
        val s = state()
        s.onSdkCrash()
        runner(s).run()
        assertEquals(3, connects)
        assertEquals(1, gaveUp)
        assertTrue(s.broken)
        assertTrue(s.repairFailed)
    }

    @Test fun aPortThatOpensAndFailsAgainStillCountsEveryAttempt() {
        val s = state()
        repeat(3) {
            assertTrue(s.onSdkCrash())
            runner(s, onConnect = { s.onPortHealthy() }).run()
        }
        s.onSdkCrash()
        runner(s).run()
        assertEquals(3, connects)
        assertEquals(1, gaveUp)
        assertTrue(s.repairFailed)
    }

    @Test fun attemptsComeBackAfterTenMinutes() {
        val s = state()
        repeat(3) { assertTrue(s.tryAcquireAttempt()) }
        assertFalse(s.tryAcquireAttempt())
        now += 10 * 60_000L
        assertTrue(s.tryAcquireAttempt())
    }

    @Test fun noConnectWhileUsbKeepsDropping() {
        val s = state()
        s.onSdkCrash()
        runner(s, settled = { false }).run()
        assertEquals(0, connects)
        assertTrue(s.repairFailed)
    }

    @Test fun waitsForUsbToSettleBeforeConnecting() {
        val s = state()
        s.onSdkCrash()
        val settledAt = now + 5_000L
        var connectedAt = 0L
        runner(s, settled = { now >= settledAt }, onConnect = { connectedAt = now; s.onPortHealthy() }).run()
        assertTrue(connectedAt >= settledAt)
    }

    @Test fun aPortOpenedByTheLibraryItselfNeedsNoConnect() {
        val s = state()
        s.onSdkCrash()
        runner(s, settled = { s.onPortHealthy(); false }).run()
        assertEquals(0, connects)
        assertEquals(0, gaveUp)
    }

    @Test fun aLatePortOpenClearsAFailedRepair() {
        val s = state()
        s.onSdkCrash()
        runner(s).run()
        assertTrue(s.onPortHealthy())
        assertFalse(s.repairFailed)
        assertFalse(s.broken)
    }

    // ---- the restart limit ---------------------------------------------------

    private val gap = RepairRestartGate.MIN_GAP_MS
    private fun decide(r: Record?, elapsed: Long, boot: Int = 7) =
        RepairRestartGate.decide(r?.encode(), elapsed, boot)

    @Test fun theFirstRepairRestartIsAllowed() {
        assertTrue(decide(null, 5_000).allowed)
    }

    @Test fun noSecondRestartWithoutAnApprovedPaymentHoweverLong() {
        val r = Record(1_000, 7, approvedSince = false)
        assertFalse(decide(r, 1_000 + gap).allowed)
        assertFalse(decide(r, 1_000 + 48 * gap).allowed)
    }

    @Test fun anApprovalStillWaitsThirtyMinutes() {
        val r = Record(1_000, 7, approvedSince = true)
        assertFalse(decide(r, 1_000 + gap - 1).allowed)
        assertTrue(decide(r, 1_000 + gap).allowed)
    }

    @Test fun aTabletRestartStartsTheThirtyMinutesAgain() {
        val d = decide(Record(1_000, 7, approvedSince = true), 5 * gap, boot = 8)
        assertFalse(d.allowed)
        assertEquals(Record(5 * gap, 8, true), d.save)
        assertTrue(decide(d.save, 6 * gap, boot = 8).allowed)
    }

    @Test fun timeSinceBootGoingBackCountsAsATabletRestart() {
        val d = decide(Record(10 * gap, -1, approvedSince = true), gap, boot = -1)
        assertFalse(d.allowed)
        assertEquals(Record(gap, -1, true), d.save)
    }

    @Test fun anUnreadableRecordAllowsNothing() {
        assertFalse(RepairRestartGate.decide("garbage", 10 * gap, 7).allowed)
        assertFalse(RepairRestartGate.decide("1|2|maybe", 10 * gap, 7).allowed)
        assertNull(Record.decode(""))
    }

    @Test fun aRecordSurvivesSaving() {
        val r = Record(123, 4, true)
        assertEquals(r, Record.decode(r.encode()))
    }
}
