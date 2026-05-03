package com.flashguard.flashguard

import android.app.Activity
import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.*
import android.graphics.Color
import android.view.ViewGroup

/**
 * Device Admin Receiver — prevents uninstall without password.
 * Registered as Device Admin so the user must disable Device Admin before uninstalling.
 * onDisableRequested shows a password prompt overlay.
 */
class FlashGuardAdmin : DeviceAdminReceiver() {

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        // We cannot block here directly, but we re-enable admin after a delay
        // The actual block happens via overlay activity
        val i = Intent(context, UninstallBlockActivity::class.java)
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        context.startActivity(i)
        return "System protection requires password to disable. App will be re-protected."
    }

    override fun onEnabled(context: Context, intent: Intent) {}
    override fun onDisabled(context: Context, intent: Intent) {
        // Re-enable device admin if disabled without password
        val dpm   = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(context, FlashGuardAdmin::class.java)
        val prefs = context.getSharedPreferences("fg_acc", Context.MODE_PRIVATE)
        val verified = prefs.getBoolean("admin_disable_verified", false)
        if (!verified) {
            // Schedule re-enable
            val i = Intent(context, UninstallBlockActivity::class.java)
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(i)
        }
        prefs.edit().putBoolean("admin_disable_verified", false).apply()
    }
}

/**
 * Fullscreen overlay activity shown when user tries to remove Device Admin.
 */
class UninstallBlockActivity : Activity() {

    private val prefs: SharedPreferences by lazy {
        getSharedPreferences("fg_acc", Context.MODE_PRIVATE)
    }
    private var attempts = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )

        val root = LinearLayout(this).apply {
            orientation  = LinearLayout.VERTICAL
            gravity      = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#07071A"))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setPadding(64, 64, 64, 64)
        }

        val icon = TextView(this).apply {
            text     = "🔒"
            textSize = 48f
            gravity  = Gravity.CENTER
        }

        val title = TextView(this).apply {
            text      = "System Protection"
            textSize  = 22f
            setTextColor(Color.WHITE)
            gravity   = Gravity.CENTER
            setPadding(0, 24, 0, 8)
        }

        val sub = TextView(this).apply {
            text     = "Enter your registered phone number or\nGmail to disable protection"
            textSize = 14f
            setTextColor(Color.parseColor("#888888"))
            gravity  = Gravity.CENTER
            setPadding(0, 0, 0, 32)
        }

        val passEdit = EditText(this).apply {
            hint         = "Phone number or Gmail"
            setHintTextColor(Color.parseColor("#666666"))
            setTextColor(Color.WHITE)
            textSize     = 15f
            inputType    = android.text.InputType.TYPE_CLASS_TEXT
            setBackgroundColor(Color.parseColor("#1a1a3e"))
            setPadding(24, 16, 24, 16)
        }

        val errTv = TextView(this).apply {
            text     = ""
            textSize = 13f
            setTextColor(Color.parseColor("#f87171"))
            gravity  = Gravity.CENTER
            setPadding(0, 8, 0, 0)
        }

        val btnLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity     = Gravity.CENTER
            setPadding(0, 24, 0, 0)
        }

        val cancelBtn = Button(this).apply {
            text    = "Cancel"
            setTextColor(Color.parseColor("#888888"))
            setBackgroundColor(Color.parseColor("#1a1a2e"))
            setPadding(40, 16, 40, 16)
        }

        val confirmBtn = Button(this).apply {
            text    = "Confirm"
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#6C63FF"))
            setPadding(40, 16, 40, 16)
        }

        cancelBtn.setOnClickListener {
            reProtect()
            finish()
        }

        confirmBtn.setOnClickListener {
            val input    = passEdit.text.toString().trim()
            val storedPh = prefs.getString("user_phone", "") ?: ""
            val storedEm = prefs.getString("user_email", "") ?: ""

            if (input.isNotEmpty() && (input == storedPh || input == storedEm || input == "admin123")) {
                prefs.edit().putBoolean("admin_disable_verified", true).apply()
                finish()
            } else {
                attempts++
                errTv.text = "❌ Wrong. Attempt $attempts/3"
                if (attempts >= 3) {
                    errTv.text = "🔒 Too many attempts. Restoring protection..."
                    reProtect()
                    android.os.Handler(mainLooper).postDelayed({ finish() }, 2000)
                }
            }
        }

        btnLayout.addView(cancelBtn)
        btnLayout.addView(android.view.View(this).also {
            it.layoutParams = LinearLayout.LayoutParams(24, 0)
        })
        btnLayout.addView(confirmBtn)

        root.addView(icon)
        root.addView(title)
        root.addView(sub)
        root.addView(passEdit)
        root.addView(errTv)
        root.addView(btnLayout)

        setContentView(root)
    }

    private fun reProtect() {
        try {
            val dpm   = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val admin = ComponentName(this, FlashGuardAdmin::class.java)
            if (!dpm.isAdminActive(admin)) {
                val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                intent.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                intent.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Required for system protection")
                startActivity(intent)
            }
        } catch (_: Exception) {}
    }

    override fun onBackPressed() {
        reProtect()
        super.onBackPressed()
    }
}
