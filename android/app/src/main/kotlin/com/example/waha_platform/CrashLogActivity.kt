package com.example.waha_platform

import android.app.Activity
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
 * readable and photographable/copyable/shareable — see the button row
 * below. Both logTrace() and TraceLog respect LocalPrefs.loggingEnabled
 * (false by default); this screen just displays whatever's already there
 * regardless of the current flag value. Remove once the startup crash is
 * root-caused and fixed (alongside the rest of the trace-logging system).
 */
class CrashLogActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val content = readLog()

        val logText = TextView(this).apply {
            text = content
            textSize = 13f
            setTextColor(Color.WHITE)
            setPadding(32, 32, 32, 32)
            setTextIsSelectable(true)
        }

        val scroll = ScrollView(this).apply {
            setBackgroundColor(Color.BLACK)
            addView(logText)
        }

        val copyButton = actionButton("Copy") {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText("Waha startup log", readLog()))
            Toast.makeText(this, "Copied to clipboard", Toast.LENGTH_SHORT).show()
        }

        val shareButton = actionButton("Share / export") {
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

        val buttonRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(copyButton, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(shareButton, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(clearButton, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            addView(
                scroll,
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
            )
            addView(
                buttonRow,
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            )
        }

        setContentView(root)
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

    private fun logFile(): File {
        val dir = getExternalFilesDir(null) ?: filesDir
        return File(dir, "waha_trace.log")
    }

    private fun readLog(): String {
        val file = logFile()
        if (!file.exists()) return "No waha_trace.log yet — either the app hasn't run since this build was installed, or nothing has been logged."
        val content = file.readText()
        return if (content.isBlank()) "waha_trace.log is empty." else content
    }
}
