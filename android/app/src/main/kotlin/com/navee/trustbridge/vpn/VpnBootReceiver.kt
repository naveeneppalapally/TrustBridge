package com.navee.trustbridge.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class VpnBootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "VpnBootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (
            action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        val prefsStore = VpnPreferencesStore(context)
        val config = prefsStore.loadConfig()
        if (!config.enabled) {
            Log.d(TAG, "Boot restore skipped: VPN not enabled by user")
            return
        }

        Log.d(TAG, "Boot restore: starting VPN with persisted rules")
        val serviceIntent = Intent(context, DnsVpnService::class.java).apply {
            this.action = DnsVpnService.ACTION_START
            putStringArrayListExtra(
                DnsVpnService.EXTRA_BLOCKED_CATEGORIES,
                ArrayList(config.blockedCategories)
            )
            putStringArrayListExtra(
                DnsVpnService.EXTRA_BLOCKED_DOMAINS,
                ArrayList(config.blockedDomains)
            )
            putStringArrayListExtra(
                DnsVpnService.EXTRA_TEMP_ALLOWED_DOMAINS,
                ArrayList(config.temporaryAllowedDomains)
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
