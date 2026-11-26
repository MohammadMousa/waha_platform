package com.waha.kiosk

/**
 * Repair of the terminal's USB port after a thread inside the Geidea SDK died
 * while opening it.
 *
 * The SDK is then left holding a half-made port object. Anything that closes it
 * (closeUsbSerialConnection, disconnectUsbSerialConnection, or stopping its USB
 * service) fails on the missing USB connection and takes the whole app down.
 * connectUsbSerialConnection does not close it first: it opens a new port that
 * replaces the broken one. So while the port is broken this app only connects.
 * It never closes or disconnects.
 *
 * Pure logic, so the tests need no device, SDK or real waiting.
 */
class SdkPortState(
    private val maxAttempts: Int = 3,
    private val windowMs: Long = 10 * 60_000L,
    private val clock: () -> Long,
) {
    private val attempts = ArrayDeque<Long>()
    private var working = false

    /** True from an SDK crash until a port really opens or a payment is approved. */
    @get:Synchronized
    var broken = false
        private set

    /** True when the reconnect attempts are used up and the port is still broken. */
    @get:Synchronized
    var repairFailed = false
        private set

    /** Marks the port broken. True when the caller must start the repair worker. */
    @Synchronized
    fun onSdkCrash(): Boolean {
        broken = true
        repairFailed = false
        if (working) return false
        working = true
        return true
    }

    /** The port opened, or a payment was approved over it. True if it was broken. */
    @Synchronized
    fun onPortHealthy(): Boolean {
        val was = broken
        broken = false
        repairFailed = false
        return was
    }

    /** One reconnect attempt, if the limit for the window allows another. */
    @Synchronized
    fun tryAcquireAttempt(): Boolean {
        val now = clock()
        while (attempts.isNotEmpty() && now - attempts.first() >= windowMs) attempts.removeFirst()
        if (attempts.size >= maxAttempts) return false
        attempts.addLast(now)
        return true
    }

    /** Ends the worker if the port is healthy. False: it broke again, carry on. */
    @Synchronized
    fun finishIfHealthy(): Boolean {
        if (broken) return false
        working = false
        return true
    }

    /** Ends the worker without a repair. False if the port turned healthy meanwhile. */
    @Synchronized
    fun giveUp(): Boolean {
        working = false
        if (!broken) return false
        repairFailed = true
        return true
    }
}

/**
 * The repair worker: wait until USB has settled, connect, wait for the port to
 * open, and repeat while the attempt limit allows. Runs on its own thread.
 */
class SdkRepairRunner(
    private val state: SdkPortState,
    private val usbSettled: () -> Boolean,
    private val connect: () -> Unit,
    private val log: (String) -> Unit,
    private val onGaveUp: () -> Unit,
    private val waitUntil: (Long, () -> Boolean) -> Boolean =
        { maxMs, condition -> ServiceRecovery.waitUntil(maxMs, condition = condition) },
    private val settleMaxMs: Long = 60_000L,
    private val openMaxMs: Long = 15_000L,
) {
    fun run() {
        while (true) {
            if (state.finishIfHealthy()) {
                log("SDK REPAIR: the port is open again, no restart needed")
                return
            }
            // A connect while the terminal is still dropping in and out is what
            // broke the port in the first place.
            if (!waitUntil(settleMaxMs) { !state.broken || usbSettled() }) {
                giveUp("USB did not stay connected")
                return
            }
            if (!state.broken) continue
            if (!state.tryAcquireAttempt()) {
                giveUp("no reconnect attempts left")
                return
            }
            log("SDK REPAIR: connecting again (the broken port is not closed first)")
            connect()
            if (!waitUntil(openMaxMs) { !state.broken }) {
                log("SDK REPAIR: the port did not open within ${openMaxMs / 1000}s")
            }
        }
    }

    private fun giveUp(why: String) {
        if (!state.giveUp()) {
            log("SDK REPAIR: the port is open again, no restart needed")
            return
        }
        log("SDK REPAIR: failed ($why)")
        onGaveUp()
    }
}

/**
 * Limits restarts asked for by the repair. After one, another is allowed only
 * when a payment has been approved since AND [minGapMs] have passed. An open
 * port alone never re-arms it, so a port that opens and fails again cannot make
 * the kiosk restart over and over.
 *
 * Time is the tablet's time since boot, never the wall clock. [Record] is saved
 * before the restart.
 */
object RepairRestartGate {
    const val MIN_GAP_MS = 30 * 60_000L

    data class Record(val elapsedMs: Long, val boot: Int, val approvedSince: Boolean) {
        fun encode(): String = "$elapsedMs|$boot|$approvedSince"

        companion object {
            fun decode(text: String): Record? {
                val p = text.split('|')
                if (p.size != 3) return null
                val elapsed = p[0].toLongOrNull() ?: return null
                val boot = p[1].toIntOrNull() ?: return null
                val approved = p[2].toBooleanStrictOrNull() ?: return null
                return Record(elapsed, boot, approved)
            }
        }
    }

    /** [save] is a changed record to store, or null. */
    data class Decision(val allowed: Boolean, val reason: String, val save: Record? = null)

    /** [stored] is null when no repair restart ever happened. */
    fun decide(stored: String?, nowElapsedMs: Long, boot: Int, minGapMs: Long = MIN_GAP_MS): Decision {
        if (stored == null) return Decision(true, "first repair restart")
        val r = Record.decode(stored) ?: return Decision(false, "the saved limit cannot be read")
        // The tablet restarted: how long ago the last one was is unknown, so the gap starts again.
        if (r.boot != boot || nowElapsedMs < r.elapsedMs) {
            return Decision(false, "the tablet restarted, the 30 minutes start again", r.copy(elapsedMs = nowElapsedMs, boot = boot))
        }
        if (!r.approvedSince) return Decision(false, "no payment was approved since the last repair restart")
        if (nowElapsedMs - r.elapsedMs < minGapMs) return Decision(false, "less than 30 minutes since the last repair restart")
        return Decision(true, "a payment was approved and 30 minutes have passed")
    }
}
