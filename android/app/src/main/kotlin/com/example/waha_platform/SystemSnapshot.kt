package com.example.waha_platform

import android.app.ActivityManager
import android.content.Context
import java.io.File

/**
 * A cheap look at the tablet's health, for the log: CPU load, memory/CPU/IO
 * pressure, temperatures, the last boot reason and any kernel crash records
 * left behind. Meant to explain freezes and unexplained reboots. Every read is
 * capped and guarded — a file the app may not read just reports "not readable".
 */
object SystemSnapshot {
    /** First [maxBytes] of [path] as text; a short note if it cannot be read. */
    fun readSmall(path: String, maxBytes: Int = 2000): String = try {
        val f = File(path)
        if (!f.exists()) "(missing)"
        else f.inputStream().use { s ->
            val buf = ByteArray(maxBytes)
            val n = s.read(buf)
            if (n <= 0) "(empty)" else String(buf, 0, n, Charsets.UTF_8).trim()
        }
    } catch (t: Throwable) {
        "(not readable: ${t.javaClass.simpleName})"
    }

    /** One line per entry, flattening newlines. */
    private fun oneLine(s: String) = s.replace('\n', ' ').replace(Regex("\\s+"), " ").trim()

    /** Short, for adding to a freeze report: load and pressure only. */
    fun compact(): String = buildString {
        append("loadavg=").append(oneLine(readSmall("/proc/loadavg", 100)))
        for (name in listOf("cpu", "memory", "io")) {
            append(" | psi.").append(name).append("=").append(oneLine(readSmall("/proc/pressure/$name", 200)))
        }
    }

    /** Fuller, once at app start. */
    fun full(context: Context): String = buildString {
        append("SYSTEM SNAPSHOT\n")
        append("  ").append(compact()).append('\n')
        try {
            val mi = ActivityManager.MemoryInfo()
            (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(mi)
            append("  memory: avail=${mi.availMem / 1048576}MB total=${mi.totalMem / 1048576}MB lowMemory=${mi.lowMemory} threshold=${mi.threshold / 1048576}MB\n")
        } catch (t: Throwable) {
            append("  memory: (not readable: ${t.javaClass.simpleName})\n")
        }
        append("  meminfo: ").append(oneLine(readSmall("/proc/meminfo", 400))).append('\n')
        val zones = try {
            File("/sys/class/thermal").listFiles { f -> f.name.startsWith("thermal_zone") }?.sortedBy { it.name }.orEmpty()
        } catch (_: Throwable) {
            emptyList()
        }
        append("  thermal: ")
        if (zones.isEmpty()) append("(none readable)")
        else zones.take(8).forEach { z ->
            append(oneLine(readSmall("${z.path}/type", 40))).append('=')
                .append(oneLine(readSmall("${z.path}/temp", 20))).append(' ')
        }
        append('\n')
        append("  boot reason: ").append(prop("sys.boot.reason")).append(" / ").append(prop("ro.boot.bootreason")).append('\n')
        val pstore = try {
            File("/sys/fs/pstore").list()?.toList()
        } catch (_: Throwable) {
            null
        }
        append("  pstore (kernel crash records): ").append(
            when {
                pstore == null -> "(not readable)"
                pstore.isEmpty() -> "none"
                else -> pstore.joinToString(", ")
            }
        )
        val lastKmsg = readSmall("/proc/last_kmsg", 1500)
        if (lastKmsg != "(missing)" && !lastKmsg.startsWith("(not readable")) append("\n  last_kmsg: ").append(oneLine(lastKmsg))
    }

    private fun prop(name: String): String = try {
        val p = Runtime.getRuntime().exec(arrayOf("getprop", name))
        p.inputStream.bufferedReader().readText().trim().ifEmpty { "(unset)" }
    } catch (t: Throwable) {
        "(not readable)"
    }
}
