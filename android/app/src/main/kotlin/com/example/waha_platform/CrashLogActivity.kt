package com.example.waha_platform

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.io.File

/**
 * Diagnostic-only, temporary: a plain Activity with its own launcher icon,
 * deliberately NOT a FlutterActivity and touching none of MainActivity's
 * Geidea/USB code — nothing here can fail for the same reasons MainActivity
 * fails to start. Reachable directly from the home screen/app drawer
 * regardless of whether MainActivity can start at all, so the trace trail
 * written by MainActivity.logTrace() (native side) and TraceLog (Dart
 * side, via the logTrace method channel case) before it died is still
 * readable and photographable/copyable/shareable — see the button rows
 * below. Both logTrace() and TraceLog respect LocalPrefs.loggingEnabled
 * (false by default); this screen just displays whatever's already there
 * regardless of the current flag value. Remove once the startup crash is
 * root-caused and fixed (alongside the rest of the trace-logging system).
 *
 * Five actions in two rows, because a single row of five no longer fits the
 * kiosk's screen width: Reload / Copy / Share on top, Upload / Clear below.
 * Upload sends the log to the Waha backend (see LogUploader) so a kiosk
 * nobody can reach can still be read remotely.
 */
class CrashLogActivity : Activity() {
    private lateinit var logText: TextView
    private lateinit var scroll: ScrollView
    private lateinit var uploadButton: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        logText = TextView(this).apply {
            text = readLog()
            textSize = 13f
            setTextColor(Color.WHITE)
            setPadding(32, 32, 32, 32)
            setTextIsSelectable(true)
        }

        scroll = ScrollView(this).apply {
            setBackgroundColor(Color.BLACK)
            addView(logText)
        }

        val copyButton = actionButton("Copy") {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText("Waha startup log", readLog()))
            Toast.makeText(this, "Copied to clipboard", Toast.LENGTH_SHORT).show()
        }

        val shareButton = actionButton("Share") {
            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_SUBJECT, "Waha startup log")
                putExtra(Intent.EXTRA_TEXT, readLog())
            }
            startActivity(Intent.createChooser(sendIntent, "Send startup log"))
        }

        val clearButton = actionButton("Clear log") {
            logFile().delete()
            recreate()
        }

        val reloadButton = actionButton("Reload") { reload() }

        uploadButton = actionButton("Upload to Waha") { upload() }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            addView(
                scroll,
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
            )
            addView(
                buttonRow(reloadButton, copyButton, shareButton),
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            )
            addView(
                buttonRow(uploadButton, clearButton),
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            )
        }

        setContentView(root)
    }

    // The log is written while this screen may already be open or
    // backgrounded, so re-read on every return to the foreground instead of
    // showing whatever onCreate saw.
    override fun onResume() {
        super.onResume()
        reload()
    }

    private fun reload() {
        logText.text = readLog()
        // Newest entries are appended at the bottom.
        scroll.post { scroll.fullScroll(ScrollView.FOCUS_DOWN) }
    }

    private fun upload() {
        uploadButton.isEnabled = false
        uploadButton.text = "Uploading…"
        Thread {
            val result = LogUploader.upload(applicationContext)
            runOnUiThread {
                uploadButton.isEnabled = true
                uploadButton.text = "Upload to Waha"
                if (isFinishing) return@runOnUiThread
                val message = if (result.ok) {
                    "Uploaded.\n\nLog ID: ${result.id}\n${result.url}\n\n${result.fileName} (${result.bytes} bytes)\n\nSend this ID to the developer."
                } else {
                    "Upload FAILED.\n\n${result.message}\n\nServer: ${result.baseUrl ?: "unknown"}"
                }
                AlertDialog.Builder(this)
                    .setTitle(if (result.ok) "Log uploaded" else "Upload failed")
                    .setMessage(message)
                    .setPositiveButton("OK", null)
                    .show()
            }
        }.start()
    }

    private fun buttonRow(vararg buttons: TextView): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        buttons.forEach { addView(it, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)) }
    }

    private fun actionButton(label: String, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            textSize = 14f
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.DKGRAY)
            gravity = Gravity.CENTER
            setPadding(16, 40, 16, 40)
            setOnClickListener { onClick() }
        }
    }

    private fun logFile(): File = LogUploader.traceFile(this)

    private fun readLog(): String {
        val file = logFile()
        if (!file.exists()) return "No waha_trace.log yet — either the app hasn't run since this build was installed, or nothing has been logged."
        // Intensive diagnostics can make this file several MB; showing,
        // copying or sharing all of it would freeze the screen or overflow the
        // share intent. Show the newest part only — Upload sends up to 1 MB.
        val len = file.length()
        val maxBytes = 300_000L
        val content = java.io.RandomAccessFile(file, "r").use { raf ->
            val start = maxOf(0L, len - maxBytes)
            raf.seek(start)
            val buf = ByteArray((len - start).toInt())
            raf.readFully(buf)
            val text = String(buf, Charsets.UTF_8)
            if (start > 0) "(showing the last ${maxBytes / 1000} KB of ${len / 1000} KB)\n" + text.substringAfter('\n', text) else text
        }
        return if (content.isBlank()) "waha_trace.log is empty." else content
    }
}
