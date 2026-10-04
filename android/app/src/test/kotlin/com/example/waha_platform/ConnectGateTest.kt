package com.example.waha_platform

import com.example.waha_platform.ConnectGate.Decision
import org.junit.Assert.assertEquals
import org.junit.Test

class ConnectGateTest {
    private var now = 1_000L
    private fun gate(expiry: Long = 15_000L) = ConnectGate(expiry) { now }

    @Test fun firstRequestGoes() {
        assertEquals(Decision.GO, gate().request(false))
    }

    @Test fun secondRequestWhileOnePendingIsSkipped() {
        val g = gate()
        g.request(false)
        now += 2_000
        assertEquals(Decision.SKIP, g.request(false))
        assertEquals(2_000L, g.pendingForMs())
    }

    @Test fun anOutcomeClearsThePendingRequest() {
        val g = gate()
        g.request(false)
        g.outcome()
        assertEquals(0L, g.pendingForMs())
        assertEquals(Decision.GO, g.request(false))
    }

    @Test fun aRequestThatNeverReportsBackExpiresAndNeverBlocksForGood() {
        val g = gate(15_000)
        g.request(false)
        now += 14_999
        assertEquals(Decision.SKIP, g.request(false))
        now += 1
        assertEquals(Decision.GO_AFTER_EXPIRY, g.request(false))
        // and the new one is pending again, with its own expiry
        now += 1_000
        assertEquals(Decision.SKIP, g.request(false))
    }

    @Test fun anExplicitRequestIsNeverSkipped() {
        val g = gate()
        g.request(false)
        now += 100
        assertEquals(Decision.GO, g.request(true))
    }
}
