package com.waha.kiosk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RepeatCollapserTest {
    private val clock: (Long) -> String = { "t$it" }

    @Test fun firstOfferIsReturnedInFull() {
        val c = RepeatCollapser()
        assertEquals("inventory A", c.offer("usb", "USB inventory", "inventory A", 10, clock))
    }

    @Test fun anUnchangedBlockBecomesOneLineWithCountAndTimes() {
        val c = RepeatCollapser()
        c.offer("usb", "USB inventory", "A", 10, clock)
        assertEquals("USB inventory unchanged: seen x2, first t10, last t20", c.offer("usb", "USB inventory", "A", 20, clock))
        assertEquals("USB inventory unchanged: seen x3, first t10, last t35", c.offer("usb", "USB inventory", "A", 35, clock))
    }

    @Test fun aChangedBlockIsWrittenInFullAndRestartsTheCount() {
        val c = RepeatCollapser()
        c.offer("usb", "USB inventory", "A", 10, clock)
        c.offer("usb", "USB inventory", "A", 20, clock)
        assertEquals("B", c.offer("usb", "USB inventory", "B", 30, clock))
        assertTrue(c.offer("usb", "USB inventory", "B", 40, clock).contains("first t30"))
    }

    @Test fun resetMakesTheNextOfferFullAgain() {
        val c = RepeatCollapser()
        c.offer("usb", "USB inventory", "A", 10, clock)
        c.reset()
        assertEquals("A", c.offer("usb", "USB inventory", "A", 20, clock))
    }
}
