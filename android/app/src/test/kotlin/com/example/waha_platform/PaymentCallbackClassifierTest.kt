package com.example.waha_platform

import com.example.waha_platform.PaymentCallbackClassifier.Outcome
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentCallbackClassifierTest {
    private fun classify(vararg f: String?) = PaymentCallbackClassifier.classify(arrayOf(*f))

    private val approvedJson = "{\"approvalCode\":\"987654\",\"rrn\":\"829912090119\",\"hostResponseCode\":\"000\",\"TransactionStatusCode\":1,\"TransactionStatusMessageEnglish\":\"APPROVED\"}"
    private val declinedJson = "{\"approvalCode\":\"\",\"hostResponseCode\":\"051\",\"TransactionStatusCode\":0,\"TransactionStatusMessageEnglish\":\"DECLINED\"}"

    @Test fun ackIsProgress() = assertEquals(Outcome.PROGRESS, classify("1", "", "", "06").outcome)

    @Test fun terminalBusyOneWordEndsTheAttempt() {
        val r = classify("1", "", "", "07")
        assertEquals(Outcome.DECLINED, r.outcome)
        assertEquals("Terminal busy, please try again", r.message)
    }

    @Test fun terminalBusySixWordFrameAlsoEndsTheAttempt() =
        assertEquals(Outcome.DECLINED, classify("1", "", "", "4D 7A 79 44 07 00").outcome)

    @Test fun connectionClosed51StaysProgress() =
        assertEquals(Outcome.PROGRESS, classify("1", "", "", "51").outcome)

    @Test fun stepCodesAreProgress() =
        assertEquals(Outcome.PROGRESS, classify("1", "", "", "0A 0B 0C 0D 0E 0F 10").outcome)

    @Test fun nullsAndEmptyAreProgress() {
        assertEquals(Outcome.PROGRESS, classify(null, null, null, null).outcome)
        assertEquals(Outcome.PROGRESS, PaymentCallbackClassifier.classify(emptyArray()).outcome)
    }

    @Test fun sdkErrorIsADefiniteFailureWithItsCode() {
        val r = classify("0", "16", "", "")
        assertEquals(Outcome.DECLINED, r.outcome)
        assertEquals("Invalid payment reference or card number (code 16)", r.message)
        assertEquals(Outcome.DECLINED, classify("0", "10", "", "").outcome)
    }

    @Test fun errorCodesGetReadableTexts() {
        assertEquals("Payment terminal not connected (USB) (code 14)", PaymentCallbackClassifier.errorText("14"))
        assertEquals("Invalid purchase amount (code 3)", PaymentCallbackClassifier.errorText("3"))
        assertEquals("The terminal's reply could not be read (code 10)", classify("0", "10", "", "").message)
        assertEquals("Payment terminal error (code 99)", PaymentCallbackClassifier.errorText("99"))
        assertEquals("Payment terminal error", PaymentCallbackClassifier.errorText(""))
    }

    @Test fun finalWithStatusCodeOneIsApproved() =
        assertEquals(Outcome.APPROVED, classify("1", "<html>receipt</html>", approvedJson, "raw").outcome)

    @Test fun finalDeclinedIsDeclinedNotApproved() {
        val r = classify("1", "<html>receipt</html>", declinedJson, "raw")
        assertEquals(Outcome.DECLINED, r.outcome)
        assertTrue(r.message.contains("DECLINED") && r.message.contains("051"))
    }

    @Test fun finalWithoutStatusCodeFallsBackOnApprovalCode() {
        assertEquals(Outcome.APPROVED, classify("1", "<html/>", "{\"approvalCode\":\"123456\"}", "").outcome)
        assertEquals(Outcome.DECLINED, classify("1", "<html/>", "{\"approvalCode\":\"?\"}", "").outcome)
        assertEquals(Outcome.DECLINED, classify("1", "<html/>", "{}", "").outcome)
    }

    @Test fun anAckAfterTheResultDoesNotChangeTheOutcomeOfEitherCall() {
        // The classifier is per call: the caller answers once, on the first non-progress call.
        val calls = listOf(classify("1", "", "", "06"), classify("1", "", "", "0A 0B 0C 0D 0E 0F"), classify("1", "<html/>", approvedJson, ""))
        assertEquals(listOf(Outcome.PROGRESS, Outcome.PROGRESS, Outcome.APPROVED), calls.map { it.outcome })
    }
}
