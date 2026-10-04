package com.example.waha_platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ServiceRecoveryTest {
    @Test fun recognisesTheSdkServiceLostLines() {
        assertTrue(ServiceRecovery.isServiceLostLine("SDK[USBService] SERVICE UNBOUNDED"))
        assertTrue(ServiceRecovery.isServiceLostLine("SDK[USB Service] Service destroyed"))
        assertFalse(ServiceRecovery.isServiceLostLine("SDK[USBService] SERVICE BOUNDED"))
        assertFalse(ServiceRecovery.isServiceLostLine("SDK[L] SERVICE CONNECTED"))
        assertFalse(ServiceRecovery.isServiceLostLine("startPayment: BEGIN amount=1.5"))
    }

    @Test fun recognisesTheConnectExceptionForALostService() {
        assertTrue(ServiceRecovery.isServiceNotConnectedMessage(
            "USB Service Connection Error: USB Service not connected. Call openUsbSerialConnection(USBConnectionListener) before connecting."))
        assertFalse(ServiceRecovery.isServiceNotConnectedMessage("No USB Attached"))
        assertFalse(ServiceRecovery.isServiceNotConnectedMessage(null))
    }

    @Test fun waitUntilReturnsAsSoonAsTheConditionHolds() {
        var t = 0L
        var polls = 0
        val ok = ServiceRecovery.waitUntil(15_000, 100, now = { t }, sleep = { t += it }) { ++polls >= 4 }
        assertTrue(ok)
        assertEquals(300L, t)
    }

    @Test fun waitUntilGivesUpAtTheLimitAndNeverWaitsLonger() {
        var t = 0L
        val ok = ServiceRecovery.waitUntil(1_000, 100, now = { t }, sleep = { t += it }) { false }
        assertFalse(ok)
        assertEquals(1_000L, t)
    }

    @Test fun waitUntilChecksOnceEvenWithNoTime() {
        var t = 0L
        assertTrue(ServiceRecovery.waitUntil(0, 100, now = { t }, sleep = { t += it }) { true })
    }

    @Test fun reopenIsLimitedSoItCannotLoop() {
        var now = 1_000L
        val l = ReopenLimiter(3_000) { now }
        assertTrue(l.tryAcquire())
        now += 2_999
        assertFalse(l.tryAcquire())
        now += 1
        assertTrue(l.tryAcquire())
        assertFalse(l.tryAcquire())
    }
}
