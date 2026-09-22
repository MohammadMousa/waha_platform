package com.example.waha_platform

import org.junit.Assert.assertEquals
import org.junit.Test

class ExitReasonsTest {
    @Test fun knownReasonsHaveNames() {
        assertEquals("CRASH", ExitReasons.reasonName(4))
        assertEquals("CRASH_NATIVE", ExitReasons.reasonName(5))
        assertEquals("ANR", ExitReasons.reasonName(6))
        assertEquals("LOW_MEMORY", ExitReasons.reasonName(3))
        assertEquals("USER_REQUESTED", ExitReasons.reasonName(10))
        assertEquals("USER_STOPPED", ExitReasons.reasonName(11))
        assertEquals("EXIT_SELF", ExitReasons.reasonName(1))
    }

    @Test fun unknownReasonNeverThrows() {
        assertEquals("REASON_99", ExitReasons.reasonName(99))
        assertEquals("REASON_-1", ExitReasons.reasonName(-1))
    }
}
