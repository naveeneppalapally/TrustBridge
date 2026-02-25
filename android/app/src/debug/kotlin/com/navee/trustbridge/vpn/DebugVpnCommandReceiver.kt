package com.navee.trustbridge.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log

class DebugVpnCommandReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "DebugVpnReceiver"
        private const val ACTION_START = "com.navee.trustbridge.debug.START_VPN"
        private const val ACTION_STOP = "com.navee.trustbridge.debug.STOP_VPN"
        private const val ACTION_STATUS = "com.navee.trustbridge.debug.STATUS_VPN"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            ACTION_START -> handleStart(context, intent)
            ACTION_STOP -> handleStop(context)
            ACTION_STATUS -> handleStatus(context)
            else -> Unit
        }
    }

    private fun handleStart(context: Context, intent: Intent) {
        val rawDomains = intent.getStringExtra("blockedDomainsCsv").orEmpty()
        val blockedDomains = rawDomains
            .split(",")
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }
            .distinct()
        val categories = intent.getStringArrayListExtra("blockedCategories")?.toList() ?: emptyList()
        val allowedDomains =
            intent.getStringArrayListExtra("temporaryAllowedDomains")?.toList() ?: emptyList()

        Log.d(
            TAG,
            "START_VPN requested domains=$blockedDomains categories=$categories " +
                "allowed=$allowedDomains permission=${VpnService.prepare(context) == null}"
        )

        val startIntent = Intent(context, DnsVpnService::class.java).apply {
            action = DnsVpnService.ACTION_START
            putStringArrayListExtra(
                DnsVpnService.EXTRA_BLOCKED_CATEGORIES,
                ArrayList(categories)
            )
            putStringArrayListExtra(
                DnsVpnService.EXTRA_BLOCKED_DOMAINS,
                ArrayList(blockedDomains)
            )
            putStringArrayListExtra(
                DnsVpnService.EXTRA_TEMP_ALLOWED_DOMAINS,
                ArrayList(allowedDomains)
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(startIntent)
        } else {
            context.startService(startIntent)
        }
    }

    private fun handleStop(context: Context) {
        Log.d(TAG, "STOP_VPN requested")
        val stopIntent = Intent(context, DnsVpnService::class.java).apply {
            action = DnsVpnService.ACTION_STOP
        }
        context.startService(stopIntent)
    }

    private fun handleStatus(context: Context) {
        val permissionGranted = VpnService.prepare(context) == null
        val config = VpnPreferencesStore(context).loadConfig()
        Log.d(
            TAG,
            "STATUS permission=$permissionGranted running=${DnsVpnService.isRunning} " +
                "enabled=${config.enabled} blockedDomains=${config.blockedDomains.size} " +
                "blockedCategories=${config.blockedCategories.size} " +
                "allowed=${config.temporaryAllowedDomains.size}"
        )
    }
}
