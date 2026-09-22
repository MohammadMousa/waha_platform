package com.example.waha_platform

// Decides what ONE callback of the Geidea SDK means for a purchase. The SDK
// (TerminalResponder.readAndSendCallbcak) calls back several times for a
// single payment:
//   ["1","","", "06"]            1 word   = the terminal received the command (ack)
//   ["1","","", <6-10 words>]    terminal step codes (card, PIN, ...)
//   ["1", receiptHtml, json, raw] the FINAL result — approved OR declined; the
//                                json carries TransactionStatusCode 1 / 0
//   ["0", "<code>", "", ""]      an SDK/terminal error (16 invalid reference,
//                                14 USB not connected, 10 terminal failure ...)
// A payment is decided only by a callback that carries a definite outcome,
// whether that is the first callback or the thousandth; everything else is
// progress and must never be reported to the app as a result.
//
// Pure Kotlin (no Android or SDK types) so it can be unit-tested.
object PaymentCallbackClassifier {
    enum class Outcome { PROGRESS, APPROVED, DECLINED }

    class Result(val outcome: Outcome, val message: String)

    private val statusCode = Regex("\"TransactionStatusCode\"\\s*:\\s*(\\d+)")
    private val approvalCode = Regex("\"approvalCode\"\\s*:\\s*\"([^\"]*)\"")
    private val statusMessage = Regex("\"TransactionStatusMessageEnglish\"\\s*:\\s*\"([^\"]*)\"")
    private val hostCode = Regex("\"hostResponseCode\"\\s*:\\s*\"([^\"]*)\"")

    fun classify(response: Array<String?>): Result {
        val status = response.getOrNull(0)
        val receipt = response.getOrNull(1).orEmpty()
        val json = response.getOrNull(2).orEmpty()
        val buffer = response.getOrNull(3).orEmpty()
        return when {
            // Error shape from getErrorOutputArrary: the code is in field 1.
            status == "0" -> Result(Outcome.DECLINED, errorText(receipt))
            // "1" without a receipt is an ack or a step code — still in
            // progress, EXCEPT "07" terminal busy, which Geidea's own sample
            // (SerialCableConnectionActivty) treats as final: the terminal has
            // refused the command outright, nothing was charged, and there is
            // no SDK retry — waiting the full timeout would just leave the
            // customer looking at a spinner for nothing.
            status == "1" && receipt.isBlank() && isBusyCode(buffer) ->
                Result(Outcome.DECLINED, "Terminal busy, please try again")
            status == "1" && receipt.isNotBlank() -> finalResult(json)
            else -> Result(Outcome.PROGRESS, "progress")
        }
    }

    // The ack/step buffer is either the raw code itself ("07") or a
    // space-separated hex dump ending in "... 07" (readAndSendCallbcak's
    // 6-10 word shape) — same field Geidea's sample reads as code_array[len-2].
    private fun isBusyCode(buffer: String): Boolean {
        val words = buffer.trim().split(" ").filter { it.isNotEmpty() }
        val code = when {
            words.size <= 2 -> buffer.trim()
            words.size in 3..10 -> words[words.size - 2]
            else -> return false
        }
        return code.equals("07", ignoreCase = true)
    }

    // Geidea's error list (Geidea_Android_SDK_v1.3.0.pdf §8) in plain words,
    // checked against the decompiled SDK for 3, 8, 10, 14 and 16. 16 is worded
    // for both meanings it has in the SDK (invalid ECR reference; the PDF calls
    // it invalid card number). The code stays in the text for support.
    fun errorText(code: String): String {
        val text = when (code.trim()) {
            "1" -> "No permission to use the internet"
            "2" -> "Network is down or no internet connection"
            "3" -> "Invalid purchase amount"
            "4" -> "Invalid NAQD amount"
            "5" -> "Invalid RRN"
            "6" -> "TCP connection error"
            "7" -> "TCP connection timeout"
            "8" -> "Invalid transaction type"
            "10" -> "The terminal's reply could not be read"
            "11" -> "Terminal verification failed"
            "13" -> "Invalid connection type"
            "14" -> "Payment terminal not connected (USB)"
            "15" -> "Invalid last-transaction buffer"
            "16" -> "Invalid payment reference or card number"
            "" -> "Payment terminal error"
            else -> "Payment terminal error"
        }
        return if (code.isBlank()) text else "$text (code ${code.trim()})"
    }

    private fun finalResult(json: String): Result {
        val code = statusCode.find(json)?.groupValues?.get(1)?.toIntOrNull()
        val approval = approvalCode.find(json)?.groupValues?.get(1).orEmpty().trim().let { if (it == "?") "" else it }
        // TransactionStatusCode is the SDK's own approved(1)/declined(0) flag.
        // Without it, fall back to an approval code being present.
        val approved = code == 1 || (code == null && approval.isNotEmpty())
        if (approved) return Result(Outcome.APPROVED, "approved")
        val text = statusMessage.find(json)?.groupValues?.get(1)?.trim().orEmpty().ifBlank { "Declined" }
        val host = hostCode.find(json)?.groupValues?.get(1)?.trim().orEmpty()
        return Result(Outcome.DECLINED, if (host.isNotBlank() && host != "?") "$text (host code $host)" else text)
    }
}
