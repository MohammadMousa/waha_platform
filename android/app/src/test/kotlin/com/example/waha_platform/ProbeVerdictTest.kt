package com.example.waha_platform

import com.example.waha_platform.TerminalDiagnostics.ChannelResult
import org.junit.Assert.assertTrue
import org.junit.Test

class ProbeVerdictTest {
    private val none = ByteArray(0)
    private fun ch(iface: Int, written: Int, reply: ByteArray = none, claimed: Boolean = true) =
        ChannelResult(iface, claimed, written, reply, none)

    @Test fun clientResultsFromLog77_sdkChannelWriteFailedIsReportedFirstAndAlone() {
        // Interface #1 (the SDK's): bulk OUT returned -1; #3 and #5 accepted 7 bytes but never replied.
        val v = TerminalDiagnostics.probeVerdict(listOf(ch(1, -1), ch(3, 7), ch(5, 7)), 1)
        assertTrue(v, v.startsWith("B. THE SDK'S WRITE CANNOT REACH THE TERMINAL"))
        assertTrue(v, v.contains("SDK channel #1: our direct write FAILED"))
        assertTrue(v, v.contains("#3 accepted 7B, no reply") && v.contains("#5 accepted 7B, no reply"))
        // The old wording that hid the failure must be gone.
        assertTrue(v, !v.contains("every channel"))
    }

    @Test fun sdkChannelAcceptsButNoReply() {
        val v = TerminalDiagnostics.probeVerdict(listOf(ch(1, 7), ch(3, 7)), 1)
        assertTrue(v, v.startsWith("C. BYTES WRITTEN, NO TERMINAL RESPONSE on the SDK's channel"))
    }

    @Test fun terminalAnswersOnTheSdkChannelMeansTheSdkWriteWasDropped() {
        val v = TerminalDiagnostics.probeVerdict(listOf(ch(1, 7, byteArrayOf(0x06)), ch(3, 7)), 1)
        assertTrue(v, v.startsWith("B. WRITE DROPPED"))
    }

    @Test fun terminalAnswersOnlyOnAnotherChannelMeansWrongChannel() {
        val v = TerminalDiagnostics.probeVerdict(listOf(ch(1, 7), ch(3, 7, byteArrayOf(0x06))), 1)
        assertTrue(v, v.startsWith("C. WRONG CHANNEL") && v.contains("#3"))
    }

    @Test fun unopenableSdkChannelAndNoProbe() {
        assertTrue(TerminalDiagnostics.probeVerdict(listOf(ch(1, -1, claimed = false)), 1).startsWith("A."))
        assertTrue(TerminalDiagnostics.probeVerdict(null, 1).startsWith("B or C."))
    }
}
