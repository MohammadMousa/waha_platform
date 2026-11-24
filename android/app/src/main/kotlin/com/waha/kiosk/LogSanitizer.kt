package com.waha.kiosk

import java.util.concurrent.atomic.AtomicLong

/**
 * Removes card and receipt content from log text, at every log level.
 *
 * What the Geidea SDK hands back after a payment carries the receipt (HTML and
 * a JSON block with the masked card number, expiry, approval code, RRN and the
 * merchant) and a long result frame whose bytes spell the card number. None of
 * that belongs in a log. What stays: the terminal's short status frames (a few
 * bytes, e.g. `01 00 02 45 39 7E`) and our own outgoing command line — they are
 * the payment timeline.
 *
 * Pure text rules, no Android types, so they are unit-tested on the JVM.
 * Nothing here touches the real data the payment code uses; it only shapes
 * what is written to the log.
 */
object LogSanitizer {
    /** A hex frame longer than this many bytes is not a short status frame. */
    const val MAX_FRAME_BYTES = 16

    /** Lines (or whole SDK entries) removed since the last [takeRemoved]. */
    private val removed = AtomicLong(0)
    fun takeRemoved(): Long = removed.getAndSet(0)

    // `Output[1]` is the HTML receipt, `Output[2]` the JSON receipt.
    private val receiptOutput = Regex("""Output\[[12]] ->""")
    private val cardFields = Regex(""""(cardNumber|cardExpiryDate|approvalCode|rrn|merchantName\w*|merchantAddress\w*|applicationCryptoProgram|PAR|FPanSuffix)"\s*:""")
    private val htmlTag = Regex("""</?(html|head|body|table|tr|td|font|style|meta)[\s>/]""", RegexOption.IGNORE_CASE)
    private val spacedHex = Regex("""\b(?:[0-9A-Fa-f]{2} ){$MAX_FRAME_BYTES}[0-9A-Fa-f]{2}(?: [0-9A-Fa-f]{2})*\b""")
    private val unspacedHex = Regex("""\b[0-9A-Fa-f]{80,}\b""")
    private val approvalCode = Regex("""approvalCode=[^\s,;)]+""")

    // Per-byte lines of the SDK's receive path: single bytes of whatever the
    // terminal sends, the result frame included, so they cannot be told apart.
    private const val PER_BYTE_PREFIX = "SDK[LAST BYTE]"

    /** True when [s] still holds card or receipt content. */
    private fun hasReceiptContent(s: String): Boolean =
        receiptOutput.containsMatchIn(s) || cardFields.containsMatchIn(s) || htmlTag.containsMatchIn(s)

    /** Long hex runs replaced by a count; [keepUnspaced] leaves our own command line alone. */
    private fun cutHex(s: String, keepUnspaced: Boolean): String {
        var out = spacedHex.replace(s) { m ->
            "<${m.value.split(' ').size} bytes removed>"
        }
        if (!keepUnspaced) out = unspacedHex.replace(out) { m -> "<${m.value.length} hex chars removed>" }
        return out
    }

    /**
     * One trace line. Returns the text to write, or null when the line is
     * dropped (it is counted, see [takeRemoved]).
     */
    fun line(raw: String): String? {
        if (raw.startsWith(PER_BYTE_PREFIX)) {
            removed.incrementAndGet()
            return null
        }
        val callback = raw.startsWith("startPayment: SDK CALLBACK")
        if (!callback && hasReceiptContent(raw)) {
            removed.incrementAndGet()
            return null
        }
        val keepCommand = raw.startsWith("SDK[FINAL BUFFER]")
        return approvalCode.replace(cutHex(raw, keepCommand), "approvalCode=<removed>")
    }

    /**
     * A free-text field of a log line (the receipt text or buffer of an SDK
     * callback). Text with markup is replaced; long frames are cut.
     */
    fun field(raw: String?, maxLength: Int): String {
        if (raw == null) return ""
        if (hasReceiptContent(raw) || raw.contains('<')) return "<removed>"
        return cutHex(raw, keepUnspaced = false).take(maxLength)
    }

    /**
     * A block of text copied from the SDK's own log file. Entries start with
     * `Trace >>`; an entry that carries a receipt (its HTML or JSON block runs
     * over several lines) is dropped as a whole, the rest is kept with long
     * hex cut. Returns the text and a note when something was removed.
     */
    fun sdkText(text: String): String {
        if (text.isEmpty()) return text
        val entries = ArrayList<StringBuilder>()
        for (l in text.lines()) {
            if (l.startsWith("Trace >>") || entries.isEmpty()) entries.add(StringBuilder())
            else entries.last().append('\n')
            entries.last().append(l)
        }
        val kept = ArrayList<String>()
        var dropped = 0
        for (e in entries) {
            val s = e.toString()
            if (hasReceiptContent(s) || longOutputFrame(s)) {
                dropped++
            } else {
                kept.add(approvalCode.replace(cutHex(s, keepUnspaced = false), "approvalCode=<removed>"))
            }
        }
        if (dropped > 0) removed.addAndGet(dropped.toLong())
        val body = kept.joinToString("\n")
        return if (dropped > 0) "$body\n[card/receipt entries removed: $dropped]" else body
    }

    // `Output[3] -> 01 01 C6 FF ...` is the result frame; the short status
    // frames after the arrow stay.
    private val outputFrame = Regex("""Output\[\d] -> ((?:[0-9A-Fa-f]{2} ?)+)""")
    private fun longOutputFrame(entry: String): Boolean {
        val m = outputFrame.find(entry) ?: return false
        return m.groupValues[1].trim().split(' ').size > MAX_FRAME_BYTES
    }
}
