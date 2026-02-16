package com.navee.trustbridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build

class TrustBridgeVpnService : android.net.VpnService() {
    companion object {
        const val ACTION_START = "com.navee.trustbridge.vpn.START"
        const val ACTION_STOP = "com.navee.trustbridge.vpn.STOP"
        private const val CHANNEL_ID = "trustbridge_vpn_channel"
        private const val NOTIFICATION_ID = 42001

        @Volatile
        var isRunning: Boolean = false
            private set
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
                .setContentText("Network filtering foundation is running.")
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("TrustBridge Protection Active")
                .setContentText("Network filtering foundation is running.")
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setOngoing(true)
                .build()
        }
    }
}
