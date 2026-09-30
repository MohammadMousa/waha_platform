package com.example.waha_platform

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Auto-captures a diagnostic log on specific trouble signs (real USB
 * disconnect/failure, a payment or handshake that got no SDK callback at
 * all, a crash on the previous run) — WITHOUT anyone noticing and scanning
 * the `cmd=upload-logs` QR (ScannerManager) or opening Settings. Built for
 * exactly the case those two can't cover: something that happens while
 * nobody is watching.
 *
 * Controlled entirely from the backend, no app update needed either way:
 *  - `auto_log_upload_enabled` (org property, "true"/"false", default off) —
 *    re-read fresh right before every upload, never cached, so turning it
 *    off from the dashboard takes effect on the very next occurrence.
 *  - `max_log_uploads_per_hour` (org property, integer, default [DEFAULT_CAP]) —
 *    a rolling one-hour cap this device enforces on ITSELF before ever
 *    sending a request, so a flapping kiosk (or a forgotten switch) can't
 *    hammer the server. Manual uploads (Settings, the QR) are not capped —
 *    a human can't scan a QR fast enough for that to matter.
 *  - `log_harvest_seconds` (org property, integer seconds, default
 *    [DEFAULT_HARVEST_SECONDS]) — how long a new sign of trouble resets the
 *    wait for, i.e. the size of the inactivity gap below. Read fresh at
 *    upload time same as the other two, but — unlike them — USED one
 *    incident later: it has to be known at the moment a NEW incident opens,
 *    before any config fetch for that incident has happened yet, so each
 *    incident uses whatever value the previous one's fetch learned (cached
 *    to disk), not a value fetched for itself. A brand new install with no
 *    prior incident uses [DEFAULT_HARVEST_SECONDS].
 *
 * [trigger] is inactivity-based, not fire-after-first-signal: every new sign
 * within the same incident pushes the check out another `log_harvest_seconds`,
 * so a still-unfolding episode collects into ONE upload instead of
 * fragmenting into several thin ones — capped by [MAX_INCIDENT_LIFETIME_MS]
 * so a port that never stops flapping still closes and uploads rather than
 * waiting forever. Nothing here touches payment/USB behavior; it only reads
 * state that already exists elsewhere (UsbMilestones, ExitReasons,
 * MainActivity's own payment/handshake state) and uploads via the same
 * LogUploader the manual tools already use.
 */
object AutoLogUploader {
    private const val DEFAULT_HARVEST_SECONDS = 30
    private const val MIN_HARVEST_SECONDS = 10
    private const val MAX_HARVEST_SECONDS = 240 // stays well under the 5-minute lifetime cap below
    // A continuously-flapping port must not hold an incident open forever —
    // this bounds it regardless of log_harvest_seconds. Once the incident
    // has run this long, the NEXT trigger fires almost immediately instead
    // of getting another full gap, so it always closes at (or just after)
    // this ceiling, not later. Fixed, not configurable — see the user
    // decision in this file's history for why.
    private const val MAX_INCIDENT_LIFETIME_MS = 5 * 60_000L
    private const val DEFAULT_CAP = 3
    private const val PREFS = "waha_diagnostics"
    private const val KEY_ORG_ID = "org_id"
    private const val KEY_TIMESTAMPS = "autolog_timestamps"
    private const val KEY_HARVEST_SECONDS = "autolog_harvest_seconds_cached"
    private const val HOUR_MS = 60 * 60 * 1000L

    // USB milestone names (TerminalDiagnostics.UsbMilestones) worth waking up
    // for — a genuine disconnect/failure, never our own deliberate reset
    // before a payment (that one calls the SDK's listener directly, with no
    // milestone broadcast behind it, so it never reaches this set at all).
    val USB_TRIGGER_NAMES = setOf(
        "SDK_USB_DISCONNECTED", "USB_DETACHED",
        "PORT_OPEN_FAILED_CDC", "PORT_OPEN_FAILED_DEVICE", "SERIAL_CREATE_FAILED",
    )

    private val handler = Handler(Looper.getMainLooper())
    private var pendingReasons = LinkedHashSet<String>()
    private var pendingRunnable: Runnable? = null
    private var incidentStartedAt: Long = 0L

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Pushed from Dart once the kiosk's session is known (see MainActivity's
     * "setOrgId"); null clears it (logout) — with no org id, nothing fires. */
    fun setOrgId(context: Context, orgId: Long?) {
        val p = prefs(context).edit()
        if (orgId == null) p.remove(KEY_ORG_ID) else p.putLong(KEY_ORG_ID, orgId)
        p.apply()
    }

    private fun orgId(context: Context): Long? =
        prefs(context).getLong(KEY_ORG_ID, -1L).takeIf { it >= 0 }

    private fun harvestMs(context: Context): Long =
        prefs(context).getInt(KEY_HARVEST_SECONDS, DEFAULT_HARVEST_SECONDS).toLong() * 1000L

    /** Call from any trouble-sign call site. Cheap and safe to call often —
     * it only ever (re)schedules work, the real cost (network) happens once
     * per incident. Inactivity-based: every new signal pushes the check out
     * another `log_harvest_seconds`, so a still-unfolding episode keeps
     * collecting reasons into ONE upload instead of fragmenting into several
     * — capped by [MAX_INCIDENT_LIFETIME_MS] so a port that never stops
     * flapping still closes and uploads instead of waiting forever. */
    fun trigger(context: Context, reason: String, trace: (String) -> Unit) {
        val now = System.currentTimeMillis()
        if (pendingRunnable == null) incidentStartedAt = now
        pendingReasons.add(reason)
        pendingRunnable?.let { handler.removeCallbacks(it) }
        val elapsed = now - incidentStartedAt
        val delay = minOf(harvestMs(context), MAX_INCIDENT_LIFETIME_MS - elapsed).coerceAtLeast(0L)
        val runnable = Runnable { fire(context.applicationContext, trace) }
        pendingRunnable = runnable
        handler.postDelayed(runnable, delay)
        trace("AUTOLOG: '$reason' — incident open ${elapsed / 1000}s, next check in ${delay / 1000}s")
    }

    private fun fire(context: Context, trace: (String) -> Unit) {
        val reasons = pendingReasons.toList()
        pendingReasons = LinkedHashSet()
        pendingRunnable = null
        incidentStartedAt = 0L
        val t = Thread {
            try {
                checkAndUpload(context, reasons, trace)
            } catch (e: Throwable) {
                trace("AUTOLOG: failed ${e.javaClass.simpleName}: ${e.message}")
            }
        }
        t.isDaemon = true
        t.name = "AutoLogUploader"
        t.start()
    }

    private fun checkAndUpload(context: Context, reasons: List<String>, trace: (String) -> Unit) {
        val base = LogUploader.baseUrl(context)
        if (base == null) {
            trace("AUTOLOG: skipped [${reasons.joinToString(",")}] — no server URL known yet")
            return
        }
        val orgId = orgId(context)
        if (orgId == null) {
            trace("AUTOLOG: skipped [${reasons.joinToString(",")}] — organization id not known yet")
            return
        }
        val props = fetchConfig(base, orgId)
        if (props == null) {
            trace("AUTOLOG: skipped [${reasons.joinToString(",")}] — could not read organization properties")
            return
        }
        // Cache log_harvest_seconds regardless of enabled/cap below — it drives
        // the NEXT incident's inactivity gap, so it must be learned even from
        // a check that itself ends up skipping the upload.
        val harvest = props["log_harvest_seconds"]?.trim()?.toIntOrNull()
            ?.coerceIn(MIN_HARVEST_SECONDS, MAX_HARVEST_SECONDS) ?: DEFAULT_HARVEST_SECONDS
        prefs(context).edit().putInt(KEY_HARVEST_SECONDS, harvest).apply()
        if (!(props["auto_log_upload_enabled"]?.trim()?.equals("true", ignoreCase = true) ?: false)) {
            trace("AUTOLOG: skipped [${reasons.joinToString(",")}] — auto_log_upload_enabled is off")
            return
        }
        val cap = props["max_log_uploads_per_hour"]?.trim()?.toIntOrNull()?.takeIf { it > 0 } ?: DEFAULT_CAP
        val recent = recentUploadCount(context)
        if (recent >= cap) {
            trace("AUTOLOG: skipped [${reasons.joinToString(",")}] — hourly cap reached ($recent/$cap in the last hour)")
            return
        }
        val tag = reasons.joinToString(",").replace(Regex("[^A-Za-z0-9,_:-]"), "_").take(60)
        recordUpload(context) // record the attempt, not just a success — repeated failures must not bypass the cap
        val result = LogUploader.upload(context, namePrefix = "autolog_$tag")
        trace(
            "AUTOLOG: upload for [${reasons.joinToString(", ")}] -> " +
                "ok=${result.ok} id=${result.id} bytes=${result.bytes} message=${result.message}",
        )
    }

    /** GET /api/config?orgId= — the same public endpoint the kiosk already
     * uses for default_language etc.; a free-form key needs no backend change. */
    private fun fetchConfig(baseUrl: String, orgId: Long): Map<String, String>? {
        return try {
            val conn = URL("$baseUrl/api/config?orgId=$orgId").openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            val code = conn.responseCode
            if (code !in 200..299) return null
            val text = conn.inputStream.bufferedReader().readText()
            val json = JSONObject(text)
            json.keys().asSequence().associateWith { json.optString(it) }
        } catch (_: Throwable) {
            null
        }
    }

    private fun recentUploadCount(context: Context): Int {
        val cutoff = System.currentTimeMillis() - HOUR_MS
        val kept = prefs(context).getString(KEY_TIMESTAMPS, "")!!
            .split(",").mapNotNull { it.toLongOrNull() }.filter { it >= cutoff }
        prefs(context).edit().putString(KEY_TIMESTAMPS, kept.joinToString(",")).apply()
        return kept.size
    }

    private fun recordUpload(context: Context) {
        val cutoff = System.currentTimeMillis() - HOUR_MS
        val kept = prefs(context).getString(KEY_TIMESTAMPS, "")!!
            .split(",").mapNotNull { it.toLongOrNull() }.filter { it >= cutoff }
        val updated = kept + System.currentTimeMillis()
        prefs(context).edit().putString(KEY_TIMESTAMPS, updated.joinToString(",")).apply()
    }
}
