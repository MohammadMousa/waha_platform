package com.example.waha_platform

/**
 * Lets only one automatic USB connect attempt be outstanding at a time.
 *
 * Several triggers ask for a connect (USB attach, the SDK's service-ready
 * callback, the startup retries). When one is already waiting for its outcome,
 * another one on top of it makes the SDK claim the same interface twice. So a
 * new automatic request is skipped while one is pending — but the pending state
 * ALWAYS expires: if the first attempt never reports back (no connected, no
 * disconnected, no error), a later request goes through after [expiryMs], so
 * a lost callback can never block connecting for good.
 *
 * An explicit request (a payment reset, a manual detect, a diagnostic) passes
 * `force = true` and is never skipped.
 */
class ConnectGate(private val expiryMs: Long = 15_000L, private val clock: () -> Long) {
    enum class Decision { GO, GO_AFTER_EXPIRY, SKIP }

    private val none = Long.MIN_VALUE
    private var requestedAt = none

    @Synchronized
    fun request(force: Boolean): Decision {
        val now = clock()
        val since = requestedAt
        val decision = when {
            force || since == none -> Decision.GO
            now - since >= expiryMs -> Decision.GO_AFTER_EXPIRY
            else -> Decision.SKIP
        }
        if (decision != Decision.SKIP) requestedAt = now
        return decision
    }

    /** The SDK reported an outcome (connected, disconnected or error). */
    @Synchronized
    fun outcome() {
        requestedAt = none
    }

    /** How long the pending request has been waiting, 0 if none. */
    @Synchronized
    fun pendingForMs(): Long = if (requestedAt == none) 0L else clock() - requestedAt
}
