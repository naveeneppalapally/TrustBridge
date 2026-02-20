package com.navee.trustbridge.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.navee.trustbridge.MainActivity
import com.navee.trustbridge.R
import java.io.FileInputStream
import java.io.FileOutputStream
import kotlin.concurrent.thread

class DnsVpnService : VpnService() {
    companion object {
        private const val TAG = "DnsVpnService"
        private const val VPN_ADDRESS = "10.0.0.1"
        private const val INTERCEPT_DNS = "45.90.28.0"
        private const val FALLBACK_DNS_PRIMARY = "45.90.30.0"
        private const val FALLBACK_DNS_SECONDARY = "45.90.30.0"
        private const val DEFAULT_UPSTREAM_DNS = "45.90.28.0"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "dns_vpn_channel"

        const val ACTION_START = "com.navee.trustbridge.vpn.START"
        const val ACTION_STOP = "com.navee.trustbridge.vpn.STOP"
        const val ACTION_RESTART = "com.navee.trustbridge.vpn.RESTART"
        const val ACTION_UPDATE_RULES = "com.navee.trustbridge.vpn.UPDATE_RULES"
        const val ACTION_SET_UPSTREAM_DNS = "com.navee.trustbridge.vpn.SET_UPSTREAM_DNS"
        const val ACTION_CLEAR_QUERY_LOGS = "com.navee.trustbridge.vpn.CLEAR_QUERY_LOGS"
        const val EXTRA_BLOCKED_CATEGORIES = "blockedCategories"
        const val EXTRA_BLOCKED_DOMAINS = "blockedDomains"
        const val EXTRA_TEMP_ALLOWED_DOMAINS = "temporaryAllowedDomains"
        const val EXTRA_UPSTREAM_DNS = "upstreamDns"

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        private var queriesProcessed: Long = 0

        @Volatile
        private var queriesBlocked: Long = 0

        @Volatile
        private var queriesAllowed: Long = 0

        @Volatile
        private var upstreamFailureCount: Long = 0

        @Volatile
        private var fallbackQueryCount: Long = 0

        @Volatile
        private var blockedCategoryCount: Int = 0

        @Volatile
        private var blockedDomainCount: Int = 0

        @Volatile
        private var startedAtEpochMs: Long? = null

        @Volatile
        private var lastRuleUpdateEpochMs: Long? = null

        @Volatile
        private var recentQueryLogs: List<Map<String, Any>> = emptyList()

        @Volatile
        private var currentUpstreamDns: String = DEFAULT_UPSTREAM_DNS

        fun statusSnapshot(permissionGranted: Boolean): Map<String, Any?> {
            return mapOf(
                "supported" to true,
                "permissionGranted" to permissionGranted,
                "isRunning" to isRunning,
                "queriesProcessed" to queriesProcessed,
                "queriesBlocked" to queriesBlocked,
                "queriesAllowed" to queriesAllowed,
                "upstreamFailureCount" to upstreamFailureCount,
                "fallbackQueryCount" to fallbackQueryCount,
                "blockedCategoryCount" to blockedCategoryCount,
                "blockedDomainCount" to blockedDomainCount,
                "startedAtEpochMs" to startedAtEpochMs,
                "lastRuleUpdateEpochMs" to lastRuleUpdateEpochMs,
                "recentQueryCount" to recentQueryLogs.size,
                "upstreamDns" to currentUpstreamDns
            )
        }

        @Synchronized
        private fun updatePacketStats(stats: DnsPacketHandler.PacketStats) {
            queriesProcessed = stats.processedQueries
            queriesBlocked = stats.blockedQueries
            queriesAllowed = stats.allowedQueries
            upstreamFailureCount = stats.upstreamFailures
            fallbackQueryCount = stats.fallbackQueries
        }

        @Synchronized
        private fun updateRecentQueryLogs(logs: List<Map<String, Any>>) {
            recentQueryLogs = logs
        }

        @Synchronized
        fun getRecentQueryLogs(limit: Int = 100): List<Map<String, Any>> {
            if (recentQueryLogs.isEmpty()) {
                return emptyList()
            }
            val safeLimit = if (limit <= 0) 1 else limit
            return recentQueryLogs.take(safeLimit)
        }

        @Synchronized
        fun clearRecentQueryLogs() {
            recentQueryLogs = emptyList()
        }
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var packetThread: Thread? = null
    private var packetHandler: DnsPacketHandler? = null
    private lateinit var filterEngine: DnsFilterEngine
    private lateinit var vpnPreferencesStore: VpnPreferencesStore
    private lateinit var connectivityManager: ConnectivityManager
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var activeUnderlyingNetwork: Network? = null
    @Volatile
    private var reconnectScheduledFromRevoke: Boolean = false
    private var lastAppliedCategories: List<String> = emptyList()
    private var lastAppliedDomains: List<String> = emptyList()
    private var lastAppliedAllowedDomains: List<String> = emptyList()
    private var lastAppliedUpstreamDns: String = DEFAULT_UPSTREAM_DNS

    @Volatile
    private var serviceRunning: Boolean = false

    override fun onCreate() {
        super.onCreate()
        vpnPreferencesStore = VpnPreferencesStore(this)
        connectivityManager = getSystemService(ConnectivityManager::class.java)
        val persisted = vpnPreferencesStore.loadConfig()
        lastAppliedUpstreamDns = normalizeUpstreamDns(persisted.upstreamDns)
        currentUpstreamDns = lastAppliedUpstreamDns
        if (persisted.blockedCategories.isNotEmpty() || persisted.blockedDomains.isNotEmpty()) {
            lastAppliedCategories = persisted.blockedCategories
            lastAppliedDomains = persisted.blockedDomains
        }
        if (persisted.temporaryAllowedDomains.isNotEmpty()) {
            lastAppliedAllowedDomains = persisted.temporaryAllowedDomains
        }
        filterEngine = DnsFilterEngine(this)
        blockedCategoryCount = filterEngine.blockedCategoryCount()
        blockedDomainCount = filterEngine.blockedDomainCount()
        lastRuleUpdateEpochMs = System.currentTimeMillis()
        Log.d(TAG, "DNS VPN service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        Log.d(TAG, "onStartCommand action=$action")

        return when (action) {
            ACTION_START -> {
                vpnPreferencesStore.setEnabled(true)
                reconnectScheduledFromRevoke = false
                val categories =
                    intent?.getStringArrayListExtra(EXTRA_BLOCKED_CATEGORIES)?.toList()
                        ?: lastAppliedCategories
                val domains =
                    intent?.getStringArrayListExtra(EXTRA_BLOCKED_DOMAINS)?.toList()
                        ?: lastAppliedDomains
                val allowedDomains =
                    intent?.getStringArrayListExtra(EXTRA_TEMP_ALLOWED_DOMAINS)?.toList()
                        ?: lastAppliedAllowedDomains
                val upstreamDns =
                    intent?.getStringExtra(EXTRA_UPSTREAM_DNS) ?: lastAppliedUpstreamDns
                applyUpstreamDns(upstreamDns)
                applyFilterRules(categories, domains, allowedDomains)
                startVpn()
                START_STICKY
            }

            ACTION_UPDATE_RULES -> {
                val categories =
                    intent?.getStringArrayListExtra(EXTRA_BLOCKED_CATEGORIES) ?: arrayListOf()
                val domains = intent?.getStringArrayListExtra(EXTRA_BLOCKED_DOMAINS) ?: arrayListOf()
                val allowedDomains =
                    intent?.getStringArrayListExtra(EXTRA_TEMP_ALLOWED_DOMAINS)?.toList()
                        ?: lastAppliedAllowedDomains
                applyFilterRules(categories, domains, allowedDomains)
                START_STICKY
            }

            ACTION_RESTART -> {
                vpnPreferencesStore.setEnabled(true)
                reconnectScheduledFromRevoke = false
                val hasCategories = intent?.hasExtra(EXTRA_BLOCKED_CATEGORIES) == true
                val hasDomains = intent?.hasExtra(EXTRA_BLOCKED_DOMAINS) == true
                val hasAllowedDomains = intent?.hasExtra(EXTRA_TEMP_ALLOWED_DOMAINS) == true
                val hasUpstreamDns = intent?.hasExtra(EXTRA_UPSTREAM_DNS) == true
                val categories = if (hasCategories) {
                    intent?.getStringArrayListExtra(EXTRA_BLOCKED_CATEGORIES)
                        ?.toList() ?: emptyList()
                } else {
                    lastAppliedCategories
                }
                val domains = if (hasDomains) {
                    intent?.getStringArrayListExtra(EXTRA_BLOCKED_DOMAINS)
                        ?.toList() ?: emptyList()
                } else {
                    lastAppliedDomains
                }
                val allowedDomains = if (hasAllowedDomains) {
                    intent?.getStringArrayListExtra(EXTRA_TEMP_ALLOWED_DOMAINS)
                        ?.toList() ?: emptyList()
                } else {
                    lastAppliedAllowedDomains
                }
                val upstreamDns = if (hasUpstreamDns) {
                    intent?.getStringExtra(EXTRA_UPSTREAM_DNS)
                } else {
                    lastAppliedUpstreamDns
                }

                stopVpn(stopService = false, markDisabled = false)
                applyUpstreamDns(upstreamDns)
                applyFilterRules(categories, domains, allowedDomains)
                startVpn()
                START_STICKY
            }

            ACTION_SET_UPSTREAM_DNS -> {
                val upstreamDns = intent?.getStringExtra(EXTRA_UPSTREAM_DNS)
                applyUpstreamDns(upstreamDns)
                if (serviceRunning) {
                    stopVpn(stopService = false, markDisabled = false)
                    startVpn()
                }
                START_STICKY
            }

            ACTION_CLEAR_QUERY_LOGS -> {
                clearRecentQueryLogs()
                packetHandler?.clearRecentQueries()
                START_STICKY
            }

            ACTION_STOP -> {
                vpnPreferencesStore.setEnabled(false)
                stopVpn(stopService = true, markDisabled = true)
                START_NOT_STICKY
            }

            else -> START_NOT_STICKY
        }
    }

    private fun startVpn() {
        if (serviceRunning) {
            Log.d(TAG, "VPN is already running")
            return
        }

        try {
            val builder = Builder()
                .setSession("TrustBridge DNS Filter")
                .addAddress(VPN_ADDRESS, 32)
                .setMtu(1500)
                // Route only the DNS interception endpoint through the tunnel.
                // Full-tunnel routing would break all non-DNS traffic until
                // generic packet forwarding is implemented.
                .addRoute(INTERCEPT_DNS, 32)
                .addDnsServer(INTERCEPT_DNS)
                .addDnsServer(FALLBACK_DNS_PRIMARY)
                .addDnsServer(FALLBACK_DNS_SECONDARY)

            setInitialUnderlyingNetwork(builder)

            vpnInterface = builder.establish()
            if (vpnInterface == null) {
                Log.e(TAG, "Failed to establish VPN interface")
                stopSelf()
                return
            }

            packetHandler = DnsPacketHandler(
                filterEngine = filterEngine,
                upstreamDns = lastAppliedUpstreamDns,
                protectSocket = { socket ->
                    protect(socket)
                }
            )

            serviceRunning = true
            isRunning = true
            vpnPreferencesStore.setEnabled(true)
            startedAtEpochMs = System.currentTimeMillis()
            queriesProcessed = 0
            queriesBlocked = 0
            queriesAllowed = 0
            upstreamFailureCount = 0
            fallbackQueryCount = 0
            clearRecentQueryLogs()
            packetHandler?.clearRecentQueries()
            currentUpstreamDns = lastAppliedUpstreamDns

            startForeground(NOTIFICATION_ID, createNotification())
            registerNetworkCallback()
            startPacketProcessing()
            Log.d(TAG, "DNS VPN started (upstream=$lastAppliedUpstreamDns)")
        } catch (error: Exception) {
            Log.e(TAG, "Failed to start VPN", error)
            stopVpn(stopService = true, markDisabled = false)
        }
    }

    private fun startPacketProcessing() {
        val fileDescriptor = vpnInterface?.fileDescriptor ?: return
        val inputStream = FileInputStream(fileDescriptor)
        val outputStream = FileOutputStream(fileDescriptor)
        val handler = packetHandler ?: return

        packetThread = thread(name = "dns-vpn-packet-loop") {
            val buffer = ByteArray(32767)
            while (serviceRunning) {
                try {
                    val length = inputStream.read(buffer)
                    if (length <= 0) {
                        Thread.sleep(10)
                        continue
                    }

                    val response = handler.handlePacket(buffer, length)
                    updatePacketStats(handler.statsSnapshot())
                    updateRecentQueryLogs(handler.recentQueriesSnapshot(limit = 120))
                    if (response != null && response.isNotEmpty()) {
                        outputStream.write(response)
                    }
                } catch (error: Exception) {
                    if (serviceRunning) {
                        Log.e(TAG, "Packet processing error", error)
                    }
                    break
                }
            }

            try {
                inputStream.close()
            } catch (_: Exception) {
            }
            try {
                outputStream.close()
            } catch (_: Exception) {
            }
            Log.d(TAG, "Packet processing loop ended")
        }
    }

    private fun stopVpn(stopService: Boolean, markDisabled: Boolean) {
        if (!serviceRunning && vpnInterface == null) {
            if (markDisabled) {
                vpnPreferencesStore.setEnabled(false)
            }
            return
        }

        Log.d(TAG, "Stopping DNS VPN")
        serviceRunning = false
        isRunning = false
        if (markDisabled) {
            vpnPreferencesStore.setEnabled(false)
        }
        unregisterNetworkCallback()

        try {
            packetHandler?.close()
            packetHandler = null
        } catch (error: Exception) {
            Log.e(TAG, "Error closing packet handler", error)
        }

        try {
            vpnInterface?.close()
            vpnInterface = null
        } catch (error: Exception) {
            Log.e(TAG, "Error closing VPN interface", error)
        }

        packetThread?.interrupt()
        packetThread = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }

        if (stopService) {
            stopSelf()
        }
    }

    private fun setInitialUnderlyingNetwork(builder: Builder) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return
        }

        val network = try {
            connectivityManager.activeNetwork
        } catch (_: Exception) {
            null
        }
        activeUnderlyingNetwork = network
        try {
            builder.setUnderlyingNetworks(network?.let { arrayOf(it) })
        } catch (error: Exception) {
            Log.w(TAG, "Unable to set initial underlying network", error)
        }
    }

    private fun registerNetworkCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return
        }
        if (networkCallback != null) {
            return
        }

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                updateUnderlyingNetwork(network)
            }

            override fun onLost(network: Network) {
                if (network == activeUnderlyingNetwork) {
                    val fallbackNetwork = try {
                        connectivityManager.activeNetwork
                    } catch (_: Exception) {
                        null
                    }
                    updateUnderlyingNetwork(fallbackNetwork)
                }
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities
            ) {
                if (networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                    updateUnderlyingNetwork(network)
                }
            }
        }

        try {
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            connectivityManager.registerNetworkCallback(request, callback)
            networkCallback = callback
        } catch (error: Exception) {
            Log.w(TAG, "Unable to register network callback", error)
            networkCallback = null
        }
    }

    private fun unregisterNetworkCallback() {
        val callback = networkCallback ?: return
        try {
            connectivityManager.unregisterNetworkCallback(callback)
        } catch (_: Exception) {
            // Ignore cleanup errors.
        } finally {
            networkCallback = null
            activeUnderlyingNetwork = null
        }
    }

    private fun updateUnderlyingNetwork(network: Network?) {
        if (!serviceRunning) {
            return
        }
        if (activeUnderlyingNetwork == network) {
            return
        }
        activeUnderlyingNetwork = network
        try {
            setUnderlyingNetworks(network?.let { arrayOf(it) })
        } catch (error: Exception) {
            Log.w(TAG, "Unable to update underlying network", error)
        }
    }

    private fun applyFilterRules(
        categories: List<String>,
        domains: List<String>,
        temporaryAllowedDomains: List<String>
    ) {
        lastAppliedCategories = categories
        lastAppliedDomains = domains
        lastAppliedAllowedDomains = temporaryAllowedDomains
        vpnPreferencesStore.saveRules(
            categories = categories,
            domains = domains,
            temporaryAllowedDomains = temporaryAllowedDomains,
            upstreamDns = lastAppliedUpstreamDns
        )
        filterEngine.updateFilterRules(categories, domains, temporaryAllowedDomains)
        blockedCategoryCount = filterEngine.blockedCategoryCount()
        blockedDomainCount = filterEngine.blockedDomainCount()
        lastRuleUpdateEpochMs = System.currentTimeMillis()
    }

    private fun applyUpstreamDns(upstreamDns: String?) {
        lastAppliedUpstreamDns = normalizeUpstreamDns(upstreamDns)
        currentUpstreamDns = lastAppliedUpstreamDns
        vpnPreferencesStore.saveRules(
            categories = lastAppliedCategories,
            domains = lastAppliedDomains,
            temporaryAllowedDomains = lastAppliedAllowedDomains,
            upstreamDns = lastAppliedUpstreamDns
        )
        lastRuleUpdateEpochMs = System.currentTimeMillis()
    }

    private fun normalizeUpstreamDns(value: String?): String {
        val normalized = value?.trim().orEmpty()
        return if (normalized.isEmpty()) DEFAULT_UPSTREAM_DNS else normalized
    }

    private fun createNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "DNS Filter Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "TrustBridge DNS filtering is active"
                setShowBadge(false)
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        val openAppIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("TrustBridge Protection Active")
            .setContentText("DNS filtering is running")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    override fun onRevoke() {
        super.onRevoke()
        val config = vpnPreferencesStore.loadConfig()
        val shouldReconnect = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            config.enabled

        if (!shouldReconnect || reconnectScheduledFromRevoke) {
            Log.d(TAG, "VPN permission revoked")
            stopVpn(stopService = true, markDisabled = true)
            return
        }

        reconnectScheduledFromRevoke = true
        Log.w(TAG, "VPN revoked on Android 14; scheduling reconnect attempt")
        stopVpn(stopService = false, markDisabled = false)

        thread(name = "dns-vpn-reconnect") {
            try {
                Thread.sleep(1200)
            } catch (_: InterruptedException) {
            }

            val restartIntent = Intent(this@DnsVpnService, DnsVpnService::class.java).apply {
                action = ACTION_START
                putStringArrayListExtra(EXTRA_BLOCKED_CATEGORIES, ArrayList(lastAppliedCategories))
                putStringArrayListExtra(EXTRA_BLOCKED_DOMAINS, ArrayList(lastAppliedDomains))
                putStringArrayListExtra(EXTRA_TEMP_ALLOWED_DOMAINS, ArrayList(lastAppliedAllowedDomains))
                putExtra(EXTRA_UPSTREAM_DNS, lastAppliedUpstreamDns)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(restartIntent)
            } else {
                startService(restartIntent)
            }
        }
    }

    override fun onDestroy() {
        stopVpn(stopService = false, markDisabled = false)
        try {
            filterEngine.close()
        } catch (_: Exception) {
        }
        super.onDestroy()
        Log.d(TAG, "DNS VPN service destroyed")
    }
}
