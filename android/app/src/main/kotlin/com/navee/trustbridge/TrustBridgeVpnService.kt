package com.navee.trustbridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import com.navee.trustbridge.vpn.LocalBlocklistDbReader

class TrustBridgeVpnService : android.net.VpnService() {
    companion object {
        const val ACTION_START = "com.navee.trustbridge.vpn.START"
        const val ACTION_STOP = "com.navee.trustbridge.vpn.STOP"
        private const val CHANNEL_ID = "trustbridge_vpn_channel"
        private const val NOTIFICATION_ID = 42001

        @Volatile
        var isRunning: Boolean = false
            private set

        private val SOCIAL_MEDIA_DOMAINS = setOf(
            "instagram.com",
            "cdninstagram.com",
            "i.instagram.com",
            "graph.instagram.com",
            "tiktok.com",
            "tiktokcdn.com",
            "muscdn.com",
            "tiktokv.com",
            "byteoversea.com",
            "twitter.com",
            "t.co",
            "twimg.com",
            "api.twitter.com",
            "x.com",
            "abs.twimg.com",
            "snapchat.com",
            "snap.com",
            "sc-cdn.net",
            "snapkit.com",
            "facebook.com",
            "fb.com",
            "fbcdn.net",
            "connect.facebook.net",
            "facebook.net",
            "youtube.com",
            "youtu.be",
            "googlevideo.com",
            "ytimg.com",
            "youtube-nocookie.com",
            "reddit.com",
            "redd.it",
            "redditmedia.com",
            "reddituploads.com",
            "redditstatic.com",
            "roblox.com",
            "rbxcdn.com",
            "robloxlabs.com"
        )
    }

    private val blockedCategories = mutableSetOf<String>()
    private var nextDnsHostname: String? = null
    private val blocklistDb: LocalBlocklistDbReader by lazy {
        LocalBlocklistDbReader(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopVpn()
                return START_NOT_STICKY
            }

            ACTION_START, null -> {
                startVpn()
                return START_STICKY
            }

            else -> return START_NOT_STICKY
        }
    }

    override fun onDestroy() {
        stopVpn()
        blocklistDb.close()
        super.onDestroy()
    }

    private fun startVpn() {
        if (!isRunning) {
            val notification = createNotification()
            startForeground(NOTIFICATION_ID, notification)
            isRunning = true
        }
    }

    private fun stopVpn() {
        if (isRunning) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            isRunning = false
        }
        stopSelf()
    }

    private fun createNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "TrustBridge VPN",
                NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(channel)
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("TrustBridge Protection Active")
                .setContentText("🛡️ TrustBridge is protecting this device")
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("TrustBridge Protection Active")
                .setContentText("🛡️ TrustBridge is protecting this device")
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setOngoing(true)
                .build()
        }
    }

    private fun isDomainBlocked(domain: String): Boolean {
        val normalized = domain.trim().lowercase()
        if (normalized.isBlank()) {
            return false
        }

        if (isSocialCategoryEnabled()) {
            if (SOCIAL_MEDIA_DOMAINS.contains(normalized)) {
                return true
            }
            for (blocked in SOCIAL_MEDIA_DOMAINS) {
                if (normalized.endsWith(".$blocked")) {
                    return true
                }
            }
        }

        return blocklistDb.isDomainBlocked(normalized)
    }

    private fun getUpstreamDns(): String {
        val nextDns = nextDnsHostname?.trim()
        return if (nextDns.isNullOrEmpty()) "1.1.1.1" else nextDns
    }

    private fun isSocialCategoryEnabled(): Boolean {
        return blockedCategories.contains("social") ||
            blockedCategories.contains("social-networks")
    }
}
