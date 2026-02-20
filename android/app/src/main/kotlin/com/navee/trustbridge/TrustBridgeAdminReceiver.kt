package com.navee.trustbridge

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

class TrustBridgeAdminReceiver : DeviceAdminReceiver() {
    companion object {
        private const val PREFS = "trustbridge_admin_prefs"
        private const val KEY_ACTIVE = "device_admin_active"
        private const val KEY_DISABLE_REQUESTED_AT = "device_admin_disable_requested_at"
    }

    override fun onEnabled(context: Context, intent: Intent) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ACTIVE, true)
            .apply()
    }

    override fun onDisabled(context: Context, intent: Intent) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ACTIVE, false)
            .apply()
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_DISABLE_REQUESTED_AT, System.currentTimeMillis())
            .apply()
        return "Contact your parent to remove TrustBridge."
    }
}
