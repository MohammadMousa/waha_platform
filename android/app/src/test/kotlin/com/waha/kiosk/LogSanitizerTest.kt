package com.waha.kiosk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class LogSanitizerTest {
    @Before fun clear() { LogSanitizer.takeRemoved() }

    // Shapes copied from the 2026-11-23 device logs; digits are made up.
    private val resultFrame = "Trace >> [v1.3.1] [23-11-2026 04:45:27.962 \\0000000000000000] [Path: /TerminalResponder/sendResponse(), Line: #-1] :: Output[3] -> " +
        "01 01 C6 FF 01 00 DF 02 10 31 32 33 34 35 36 2A 2A 2A 2A 2A 2A 37 38 39 30 DF 04 06 00 00 00 00 03 70"
    private val statusFrame = "Trace >> [v1.3.1] [23-11-2026 04:45:20.100 \\0000000000000000] [Path: /TerminalResponder/sendResponse(), Line: #-1] :: Output[3] -> 01 00 02 45 39 7E"
    private val jsonReceipt = "Trace >> [v1.3.1] [23-11-2026 04:45:27.900 \\0000000000000000] [Path: /TerminalResponder/sendResponse(), Line: #-1] :: Output[2] -> {\"merchantName\":\"Shop\",\"cardNumber\":\"123456******7890\",\"approvalCode\":\"111111\"}"
    private val htmlReceipt = "Trace >> [v1.3.1] [23-11-2026 04:45:27.800 \\0000000000000000] [Path: /TerminalResponder/sendResponse(), Line: #-1] :: Output[1] -> <html>\n <head>\n <style type=\"text/css\">\n body { margin: 0 }\n</style>\n</head><body>\n<table align='center'>\n<tr>\n<td colspan='2'>Shop</td>\n</tr>"

    @Test fun shortStatusFramesAreKept() {
        assertEquals(statusFrame, LogSanitizer.sdkText(statusFrame))
        assertEquals(0, LogSanitizer.takeRemoved())
    }

    @Test fun theResultFrameWithTheCardNumberIsRemoved() {
        val out = LogSanitizer.sdkText(statusFrame + "\n" + resultFrame)
        assertFalse(out.contains("31 32 33 34"))
        assertTrue(out.contains("01 00 02 45 39 7E"))
        assertTrue(out.contains("[card/receipt entries removed: 1]"))
    }

    @Test fun jsonAndHtmlReceiptEntriesAreRemovedWholeIncludingTheirContinuationLines() {
        val out = LogSanitizer.sdkText(statusFrame + "\n" + htmlReceipt + "\n" + jsonReceipt + "\n" + statusFrame)
        assertFalse(out.contains("<td"))
        assertFalse(out.contains("123456"))
        assertFalse(out.contains("Shop"))
        assertEquals(2, out.lines().count { it.contains("01 00 02 45 39 7E") })
        assertTrue(out.contains("[card/receipt entries removed: 2]"))
    }

    @Test fun traceLineWithAReceiptIsDroppedAndCounted() {
        assertNull(LogSanitizer.line("Output[2] -> {\"cardNumber\":\"123456******7890\"}"))
        assertNull(LogSanitizer.line("SDK[System.out] <td colspan='2'>x</td>"))
        assertEquals(2, LogSanitizer.takeRemoved())
    }

    @Test fun perByteLinesAreDropped() {
        assertNull(LogSanitizer.line("SDK[LAST BYTE] 01"))
    }

    @Test fun longHexIsCutButShortFramesAndTheOutgoingCommandStay() {
        val long = "SDK[RESPONSE BUFFER] 01 01 C6 FF 01 00 DF 02 10 31 32 33 34 35 36 2A 2A 2A 2A 2A 2A 37 38"
        val cut = LogSanitizer.line(long)!!
        assertTrue(cut.contains("bytes removed"))
        assertFalse(cut.contains("31 32 33"))
        assertEquals("SDK[DATA FROM USB] 01 00 02 45 39 7E", LogSanitizer.line("SDK[DATA FROM USB] 01 00 02 45 39 7E"))
        val cmd = "SDK[FINAL BUFFER] 01002DFF0100DF0406000000000357DF610A30FFFFFFFFFFFFFFFFFFDF811030316132303864383434386537353239112C"
        assertEquals(cmd, LogSanitizer.line(cmd))
    }

    @Test fun approvalCodeInOurOwnLinesIsHidden() {
        assertEquals("Terminal: SDK result approved=true approvalCode=<removed> error=null",
            LogSanitizer.line("Terminal: SDK result approved=true approvalCode=843801 error=null"))
    }

    @Test fun theCallbackLineIsKeptEvenWhenItsFieldsWereAReceipt() {
        val l = "startPayment: SDK CALLBACK after 7771ms outcome=APPROVED fields=4 status='1' code/receipt='<removed>' detailsLen=1512 buffer='01 01 C6 FF'"
        assertNotNull(LogSanitizer.line(l))
        assertEquals("<removed>", LogSanitizer.field("<html><td>x</td></html>", 120))
        assertEquals("01 00 02 45 39 7E", LogSanitizer.field("01 00 02 45 39 7E", 30))
        assertTrue(LogSanitizer.field("01 01 C6 FF 01 00 DF 02 10 31 32 33 34 35 36 2A 2A 2A 2A 2A 2A 37 38", 300).contains("bytes removed"))
    }

    @Test fun ordinaryPaymentLinesPassUnchanged() {
        for (l in listOf(
            "startPayment: still waiting 10s | SDKSTATE isUSBConnected(flag only, NOT proof)=true terminalVerified=false",
            "DART: Terminal: ← SDK replied after 5585ms status=approved receipt=(hidden)",
            "MILESTONE USB_DETACHED /dev/bus/usb/007/003 2fb8:224e",
        )) assertEquals(l, LogSanitizer.line(l))
    }
}
