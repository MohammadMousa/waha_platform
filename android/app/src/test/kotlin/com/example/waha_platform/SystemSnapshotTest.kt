package com.example.waha_platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class SystemSnapshotTest {
    @Test fun readsTheStartOfAFileAndCapsIt() {
        val f = File.createTempFile("snap", ".txt").apply { writeText("0123456789".repeat(100)); deleteOnExit() }
        assertEquals(10, SystemSnapshot.readSmall(f.path, 10).length)
    }

    @Test fun anEmptyFileIsReportedAsEmpty() {
        val f = File.createTempFile("snap", ".txt").apply { deleteOnExit() }
        assertEquals("(empty)", SystemSnapshot.readSmall(f.path))
    }

    @Test fun aMissingFileNeverThrows() {
        assertEquals("(missing)", SystemSnapshot.readSmall("/definitely/not/here"))
    }

    @Test fun aUnreadableFileNeverThrows() {
        val f = File.createTempFile("snap", ".txt").apply { writeText("x"); deleteOnExit(); setReadable(false) }
        val out = SystemSnapshot.readSmall(f.path)
        assertTrue(out == "x" || out.startsWith("(not readable")) // running as root can still read it
    }

    @Test fun compactAlwaysProducesTheThreeSections() {
        val out = SystemSnapshot.compact()
        assertTrue(out.contains("loadavg="))
        assertTrue(out.contains("psi.cpu="))
        assertTrue(out.contains("psi.memory="))
        assertTrue(out.contains("psi.io="))
    }
}
