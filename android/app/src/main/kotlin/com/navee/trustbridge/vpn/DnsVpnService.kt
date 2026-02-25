package com.navee.trustbridge.vpn

import android.app.AlarmManager
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
import android.provider.Settings
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
        private const val FALLBACK_DNS_PRIMARY = "1.1.1.1"
        private const val FALLBACK_DNS_SECONDARY = "8.8.8.8"
        private const val DEFAULT_UPSTREAM_DNS = "1.1.1.1"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "dns_vpn_channel"
        private const val RECOVERY_NOTIFICATION_ID = 1002
        private const val RECOVERY_CHANNEL_ID = "dns_vpn_recovery_channel"
        private const val MAX_RECONNECT_ATTEMPTS = 3
        private const val MAX_BOOT_RESTORE_RETRY_ATTEMPTS = 4
        private const val MAX_TRANSIENT_START_RETRY_ATTEMPTS = 3
        private const val WATCHDOG_REQUEST_CODE = 4100
        private const val WATCHDOG_INTERVAL_MS = 60_000L
        private val BOOT_RESTORE_RETRY_DELAYS_MS = longArrayOf(
            15_000L,
            30_000L,
            60_000L,
            120_000L
        )
        private val TRANSIENT_START_RETRY_DELAYS_MS = longArrayOf(
            5_000L,
            15_000L,
            30_000L
        )

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
        const val EXTRA_BOOT_RESTORE = "bootRestore"
        const val EXTRA_BOOT_RESTORE_ATTEMPT = "bootRestoreAttempt"
        const val EXTRA_TRANSIENT_RETRY_ATTEMPT = "transientRetryAttempt"

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

        @Volatile
        private var privateDnsMode: String = ""

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
                "upstreamDns" to currentUpstreamDns,
                "privateDnsMode" to privateDnsMode,
                "privateDnsActive" to isPrivateDnsActive()
            )
        }

        private fun isPrivateDnsActive(): Boolean {
            return privateDnsMode == "opportunistic" || privateDnsMode == "hostname"
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
    @Volatile
    private var reconnectAttemptCount: Int = 0
    @Volatile
    private var activeBootRestoreStart: Boolean = false
    @Volatile
    private var activeBootRestoreAttempt: Int = 0
    @Volatile
    private var activeTransientRetryAttempt: Int = 0
    @Volatile
    private var lastScheduledBootRetryAttempt: Int = -1
    @Volatile
    private var lastScheduledTransientRetryAttempt: Int = -1
    private var lastAppliedCategories: List<String> = emptyList()
    private var lastAppliedDomains: List<String> = emptyList()
    private var lastAppliedAllowedDomains: List<String> = emptyList()
    private var lastAppliedUpstreamDns: String = DEFAULT_UPSTREAM_DNS

    @Volatile
    private var serviceRunning: Boolean = false
    @Volatile
    private var foregroundActive: Boolean = false

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
        blockedDomainCount = filterEngine.effectiveBlockedDomainCount()
        lastRuleUpdateEpochMs = System.currentTimeMillis()
        Log.d(TAG, "DNS VPN service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        Log.d(TAG, "onStartCommand action=$action")

        return when (action) {
            ACTION_START -> {
                activeBootRestoreStart =
                    intent?.getBooleanExtra(EXTRA_BOOT_RESTORE, false) == true
                activeBootRestoreAttempt =
                    intent?.getIntExtra(EXTRA_BOOT_RESTORE_ATTEMPT, 0) ?: 0
                activeTransientRetryAttempt =
                    intent?.getIntExtra(EXTRA_TRANSIENT_RETRY_ATTEMPT, 0) ?: 0
                vpnPreferencesStore.setEnabled(true)
                reconnectScheduledFromRevoke = false
                ensureForegroundStarted()
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
                scheduleWatchdogPing()
                START_STICKY
            }

            ACTION_UPDATE_RULES -> {
                val categories =
                    intent?.getStringArrayListExtra(EXTRA_BLOCKED_CATEGORIES) ?: arrayListOf()
                val domains = intent?.getStringArrayListExtra(EXTRA_BLOCKED_DOMAINS) ?: arrayListOf()
                val allowedDomains =
                    intent?.getStringArrayListExtra(EXTRA_TEMP_ALLOWED_DOMAINS)?.toList()
                        ?: emptyList()
                applyFilterRules(categories, domains, allowedDomains)
                scheduleWatchdogPing()
                START_STICKY
            }

            ACTION_RESTART -> {
                activeBootRestoreStart =
                    intent?.getBooleanExtra(EXTRA_BOOT_RESTORE, false) == true
                activeBootRestoreAttempt =
                    intent?.getIntExtra(EXTRA_BOOT_RESTORE_ATTEMPT, 0) ?: 0
                activeTransientRetryAttempt =
                    intent?.getIntExtra(EXTRA_TRANSIENT_RETRY_ATTEMPT, 0) ?: 0
                vpnPreferencesStore.setEnabled(true)
                reconnectScheduledFromRevoke = false
                ensureForegroundStarted()
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
                scheduleWatchdogPing()
                START_STICKY
            }

            ACTION_SET_UPSTREAM_DNS -> {
                val upstreamDns = intent?.getStringExtra(EXTRA_UPSTREAM_DNS)
                applyUpstreamDns(upstreamDns)
                if (serviceRunning) {
                    stopVpn(stopService = false, markDisabled = false)
                    startVpn()
                }
                scheduleWatchdogPing()
                START_STICKY
            }

            ACTION_CLEAR_QUERY_LOGS -> {
                clearRecentQueryLogs()
                packetHandler?.clearRecentQueries()
                START_STICKY
            }

            ACTION_STOP -> {
                activeBootRestoreStart = false
                activeBootRestoreAttempt = 0
                activeTransientRetryAttempt = 0
                lastScheduledBootRetryAttempt = -1
                lastScheduledTransientRetryAttempt = -1
                vpnPreferencesStore.setEnabled(false)
                cancelWatchdogPing()
                dismissProtectionAttentionNotification()
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
            ensureForegroundStarted()
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
                val hasPersistedPermission = VpnService.prepare(this) == null
                val bootRestore = activeBootRestoreStart
                Log.e(
                    TAG,
                    "Failed to establish VPN interface " +
                        "(bootRestore=$bootRestore " +
                        "attempt=$activeBootRestoreAttempt " +
                        "transientAttempt=$activeTransientRetryAttempt " +
                        "permissionPersisted=$hasPersistedPermission)"
                )
                var retryScheduled = false
                if (hasPersistedPermission) {
                    retryScheduled = if (bootRestore) {
                        scheduleBootRestoreRetry()
                    } else {
                        scheduleTransientStartRetry()
                    }
                }
                if (retryScheduled) {
                    Log.w(TAG, "VPN establish failed; retry scheduled and service kept alive")
                    return
                } else {
                    showProtectionAttentionNotification(
                        "Protection is off. Open TrustBridge and tap Restore Protection."
                    )
                }
                stopVpn(stopService = true, markDisabled = false)
                return
            }

            packetHandler = DnsPacketHandler(
                filterEngine = filterEngine,
                upstreamDns = lastAppliedUpstreamDns,
                protectSocket = { socket ->
                    protect(socket)
                },
                onBlockedDomain = { domain ->
                    VpnEventDispatcher.notifyBlockedDomain(
                        domain = domain,
                        modeName = currentModeNameForBlockedEvent()
                    )
                }
            )

            serviceRunning = true
            isRunning = true
            vpnPreferencesStore.setEnabled(true)
            reconnectAttemptCount = 0
            activeBootRestoreAttempt = 0
            activeTransientRetryAttempt = 0
            lastScheduledBootRetryAttempt = -1
            lastScheduledTransientRetryAttempt = -1
            dismissProtectionAttentionNotification()
            startedAtEpochMs = System.currentTimeMillis()
            queriesProcessed = 0
            queriesBlocked = 0
            queriesAllowed = 0
            upstreamFailureCount = 0
            fallbackQueryCount = 0
            clearRecentQueryLogs()
            packetHandler?.clearRecentQueries()
            currentUpstreamDns = lastAppliedUpstreamDns

            registerNetworkCallback()
            detectPrivateDns()
            startPacketProcessing()
            Log.d(TAG, "DNS VPN started (upstream=$lastAppliedUpstreamDns, privateDns=$privateDnsMode)")
        } catch (error: Exception) {
            Log.e(TAG, "Failed to start VPN", error)
            showProtectionAttentionNotification(
                "Protection is off. Open TrustBridge and tap Restore Protection."
            )
            stopVpn(stopService = true, markDisabled = false)
        }
    }

    private fun scheduleBootRestoreRetry(): Boolean {
        val nextAttempt = activeBootRestoreAttempt + 1
        if (nextAttempt > MAX_BOOT_RESTORE_RETRY_ATTEMPTS) {
            Log.w(TAG, "Boot restore retries exhausted")
            showProtectionAttentionNotification(
                "Protection did not restart after reboot. Open TrustBridge to restore."
            )
            return false
        }

        val config = vpnPreferencesStore.loadConfig()
        if (!config.enabled) {
            Log.d(TAG, "Boot restore retry skipped: VPN no longer enabled")
            return false
        }

        val delayMs = BOOT_RESTORE_RETRY_DELAYS_MS.getOrElse(nextAttempt - 1) {
            BOOT_RESTORE_RETRY_DELAYS_MS.last()
        }
        Log.w(
            TAG,
            "Scheduling boot restore retry attempt=$nextAttempt in ${delayMs}ms"
        )
        val inProcessScheduled = scheduleInProcessStartRetry(
            delayMs = maxOf(5_000L, delayMs / 3),
            config = config,
            bootRestore = true,
            bootRestoreAttempt = nextAttempt,
            transientRetryAttempt = 0
        )
        val alarmScheduled = scheduleStartRetry(
            requestCode = 2000 + nextAttempt,
            delayMs = delayMs,
            config = config,
            bootRestore = true,
            bootRestoreAttempt = nextAttempt,
            transientRetryAttempt = 0
        )
        return inProcessScheduled || alarmScheduled
    }

    private fun scheduleTransientStartRetry(): Boolean {
        val nextAttempt = activeTransientRetryAttempt + 1
        if (nextAttempt > MAX_TRANSIENT_START_RETRY_ATTEMPTS) {
            Log.w(TAG, "Transient VPN start retries exhausted")
            showProtectionAttentionNotification(
                "Protection could not start. Open TrustBridge and tap Restore Protection."
            )
            return false
        }

        val config = vpnPreferencesStore.loadConfig()
        if (!config.enabled) {
            Log.d(TAG, "Transient retry skipped: VPN no longer enabled")
            return false
        }

        val delayMs = TRANSIENT_START_RETRY_DELAYS_MS.getOrElse(nextAttempt - 1) {
            TRANSIENT_START_RETRY_DELAYS_MS.last()
        }
        Log.w(
            TAG,
            "Scheduling transient VPN start retry attempt=$nextAttempt in ${delayMs}ms"
        )
        val inProcessScheduled = scheduleInProcessStartRetry(
            delayMs = delayMs,
            config = config,
            bootRestore = false,
            bootRestoreAttempt = 0,
            transientRetryAttempt = nextAttempt
        )
        val alarmScheduled = scheduleStartRetry(
            requestCode = 3000 + nextAttempt,
            delayMs = delayMs,
            config = config,
            bootRestore = false,
            bootRestoreAttempt = 0,
            transientRetryAttempt = nextAttempt
        )
        return inProcessScheduled || alarmScheduled
    }

    private fun scheduleStartRetry(
        requestCode: Int,
        delayMs: Long,
        config: PersistedVpnConfig,
        bootRestore: Boolean,
        bootRestoreAttempt: Int,
        transientRetryAttempt: Int
    ): Boolean {
        val retryIntent = buildStartIntent(
            config = config,
            bootRestore = bootRestore,
            bootRestoreAttempt = bootRestoreAttempt,
            transientRetryAttempt = transientRetryAttempt
        )

        val pendingIntent = createServicePendingIntent(
            requestCode = requestCode,
            intent = retryIntent,
            flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(AlarmManager::class.java)
        if (alarmManager == null) {
            Log.w(TAG, "Retry scheduling skipped: AlarmManager unavailable")
            return false
        }

        val triggerAtMs = System.currentTimeMillis() + delayMs
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val canUseExact =
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                        alarmManager.canScheduleExactAlarms()
                if (canUseExact) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMs,
                        pendingIntent
                    )
                } else {
                    Log.w(
                        TAG,
                        "Exact alarms not permitted; using inexact allow-while-idle alarm"
                    )
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMs,
                        pendingIntent
                    )
                }
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
            }
            true
        } catch (error: Exception) {
            Log.e(TAG, "Unable to schedule VPN retry", error)
            false
        }
    }

    private fun scheduleInProcessStartRetry(
        delayMs: Long,
        config: PersistedVpnConfig,
        bootRestore: Boolean,
        bootRestoreAttempt: Int,
        transientRetryAttempt: Int
    ): Boolean {
        if (bootRestore) {
            if (bootRestoreAttempt <= lastScheduledBootRetryAttempt) {
                return true
            }
            lastScheduledBootRetryAttempt = bootRestoreAttempt
        } else {
            if (transientRetryAttempt <= lastScheduledTransientRetryAttempt) {
                return true
            }
            lastScheduledTransientRetryAttempt = transientRetryAttempt
        }

        thread(
            name = "dns-vpn-inprocess-retry-" +
                if (bootRestore) "boot-$bootRestoreAttempt" else "transient-$transientRetryAttempt"
        ) {
            try {
                Thread.sleep(delayMs)
            } catch (_: InterruptedException) {
                return@thread
            }

            val latestConfig = vpnPreferencesStore.loadConfig()
            if (!latestConfig.enabled) {
                Log.d(TAG, "In-process retry skipped: VPN no longer enabled")
                return@thread
            }

            val retryIntent = buildStartIntent(
                config = latestConfig,
                bootRestore = bootRestore,
                bootRestoreAttempt = bootRestoreAttempt,
                transientRetryAttempt = transientRetryAttempt
            )
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(retryIntent)
                } else {
                    startService(retryIntent)
                }
            } catch (error: Exception) {
                Log.e(TAG, "In-process retry launch failed", error)
            }
        }
        return true
    }

    private fun scheduleWatchdogPing() {
        val config = try {
            vpnPreferencesStore.loadConfig()
        } catch (_: Exception) {
            return
        }
        if (!config.enabled) {
            return
        }

        val alarmManager = getSystemService(AlarmManager::class.java) ?: return
        val watchdogIntent = buildStartIntent(
            config = config,
            bootRestore = false,
            bootRestoreAttempt = 0,
            transientRetryAttempt = 0
        )
        val pendingIntent = createServicePendingIntent(
            requestCode = WATCHDOG_REQUEST_CODE,
            intent = watchdogIntent,
            flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val triggerAtMs = System.currentTimeMillis() + WATCHDOG_INTERVAL_MS
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMs,
                    pendingIntent
                )
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
            }
        } catch (error: Exception) {
            Log.e(TAG, "Unable to schedule VPN watchdog ping", error)
        }
    }

    private fun cancelWatchdogPing() {
        val alarmManager = getSystemService(AlarmManager::class.java) ?: return
        val pendingIntent = findExistingServicePendingIntent(
            requestCode = WATCHDOG_REQUEST_CODE,
            intent = Intent(this, DnsVpnService::class.java).apply {
                action = ACTION_START
            },
            flags = PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        ) ?: return
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun createServicePendingIntent(
        requestCode: Int,
        intent: Intent,
        flags: Int
    ): PendingIntent {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(this, requestCode, intent, flags)
        } else {
            PendingIntent.getService(this, requestCode, intent, flags)
        }
    }

    private fun findExistingServicePendingIntent(
        requestCode: Int,
        intent: Intent,
        flags: Int
    ): PendingIntent? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(this, requestCode, intent, flags)
        } else {
            PendingIntent.getService(this, requestCode, intent, flags)
        }
    }

    private fun buildStartIntent(
        config: PersistedVpnConfig,
        bootRestore: Boolean,
        bootRestoreAttempt: Int,
        transientRetryAttempt: Int
    ): Intent {
        return Intent(this, DnsVpnService::class.java).apply {
            action = ACTION_START
            putExtra(EXTRA_BOOT_RESTORE, bootRestore)
            putExtra(EXTRA_BOOT_RESTORE_ATTEMPT, bootRestoreAttempt)
            putExtra(EXTRA_TRANSIENT_RETRY_ATTEMPT, transientRetryAttempt)
            putStringArrayListExtra(
                EXTRA_BLOCKED_CATEGORIES,
                ArrayList(config.blockedCategories)
            )
            putStringArrayListExtra(
                EXTRA_BLOCKED_DOMAINS,
                ArrayList(config.blockedDomains)
            )
            putStringArrayListExtra(
                EXTRA_TEMP_ALLOWED_DOMAINS,
                ArrayList(config.temporaryAllowedDomains)
            )
            putExtra(EXTRA_UPSTREAM_DNS, config.upstreamDns)
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
        if (!serviceRunning && vpnInterface == null && !foregroundActive) {
            if (markDisabled) {
                vpnPreferencesStore.setEnabled(false)
                cancelWatchdogPing()
            }
            return
        }

        Log.d(TAG, "Stopping DNS VPN")
        serviceRunning = false
        isRunning = false
        if (markDisabled) {
            vpnPreferencesStore.setEnabled(false)
            cancelWatchdogPing()
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

        if (foregroundActive) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            foregroundActive = false
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
        val normalizedCategories = categories
            .map(::normalizeCategoryToken)
            .filter { it.isNotEmpty() }
            .distinct()
        val normalizedDomains = domains
            .map(::normalizeDomainToken)
            .filter { it.isNotEmpty() }
            .distinct()
        val normalizedAllowedDomains = temporaryAllowedDomains
            .map(::normalizeDomainToken)
            .filter { it.isNotEmpty() }
            .distinct()

        lastAppliedCategories = normalizedCategories
        lastAppliedDomains = normalizedDomains
        lastAppliedAllowedDomains = normalizedAllowedDomains
        vpnPreferencesStore.saveRules(
            categories = normalizedCategories,
            domains = normalizedDomains,
            temporaryAllowedDomains = normalizedAllowedDomains,
            upstreamDns = lastAppliedUpstreamDns
        )
        filterEngine.updateFilterRules(
            normalizedCategories,
            normalizedDomains,
            normalizedAllowedDomains
        )
        blockedCategoryCount = filterEngine.blockedCategoryCount()
        blockedDomainCount = filterEngine.effectiveBlockedDomainCount()
        lastRuleUpdateEpochMs = System.currentTimeMillis()
    }

    private fun normalizeCategoryToken(rawCategory: String): String {
        val normalized = rawCategory.trim().lowercase()
        return when (normalized) {
            "social" -> "social-networks"
            "adult" -> "adult-content"
            else -> normalized
        }
    }

    private fun normalizeDomainToken(rawDomain: String): String {
        var normalized = rawDomain.trim().lowercase()
        if (normalized.startsWith("*.")) {
            normalized = normalized.removePrefix("*.")
        }
        while (normalized.endsWith(".")) {
            normalized = normalized.dropLast(1)
        }
        return normalized
    }

    private fun currentModeNameForBlockedEvent(): String {
        if (lastAppliedCategories.contains("__block_all__")) {
            return "Pause Mode"
        }

        val focusCategoryHit = lastAppliedCategories.any { category ->
            category == "social" ||
                category == "social-networks" ||
                category == "chat" ||
                category == "streaming" ||
                category == "games"
        }
        if (focusCategoryHit) {
            return "Focus Mode"
        }

        return "Protection Mode"
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

    private fun detectPrivateDns() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            privateDnsMode = ""
            return
        }
        try {
            val mode = Settings.Global.getString(contentResolver, "private_dns_mode")
                ?: ""
            privateDnsMode = mode
            if (mode == "opportunistic" || mode == "hostname") {
                Log.w(
                    TAG,
                    "⚠️ Private DNS is ACTIVE (mode=$mode). " +
                        "DNS-over-TLS will bypass VPN's UDP/53 interception. " +
                        "Blocking may not work until Private DNS is disabled."
                )
            } else {
                Log.d(TAG, "Private DNS mode=$mode (OK – DNS interception should work)")
            }
        } catch (error: Exception) {
            Log.w(TAG, "Could not read private_dns_mode setting", error)
            privateDnsMode = ""
        }
    }

    @Synchronized
    private fun ensureForegroundStarted() {
        if (foregroundActive) {
            return
        }
        startForeground(NOTIFICATION_ID, createNotification())
        foregroundActive = true
    }

    private fun createNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "DNS Filter Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "TrustBridge protection is active"
                setShowBadge(false)
            }
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
            .setContentText("🛡️ TrustBridge is protecting this device")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun showProtectionAttentionNotification(message: String) {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val recoveryChannel = NotificationChannel(
                RECOVERY_CHANNEL_ID,
                "Protection Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts when TrustBridge protection needs attention"
                setShowBadge(true)
            }
            manager.createNotificationChannel(recoveryChannel)
        }

        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            1,
            openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, RECOVERY_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("TrustBridge protection is off")
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        manager.notify(RECOVERY_NOTIFICATION_ID, notification)
    }

    private fun dismissProtectionAttentionNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.cancel(RECOVERY_NOTIFICATION_ID)
    }

    override fun onRevoke() {
        super.onRevoke()
        val config = vpnPreferencesStore.loadConfig()
        val shouldReconnect = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            config.enabled

        if (!shouldReconnect || reconnectScheduledFromRevoke) {
            Log.d(TAG, "VPN permission revoked")
            logBypassEvent("vpn_disabled")
            showProtectionAttentionNotification(
                "Protection was turned off. Open TrustBridge to restore VPN permission."
            )
            stopVpn(stopService = true, markDisabled = true)
            return
        }

        if (reconnectAttemptCount >= MAX_RECONNECT_ATTEMPTS) {
            Log.w(TAG, "Reconnect attempts exhausted after revoke")
            logBypassEvent("vpn_disabled")
            showProtectionAttentionNotification(
                "Protection could not reconnect. Open TrustBridge to restore."
            )
            stopVpn(stopService = true, markDisabled = true)
            return
        }

        reconnectScheduledFromRevoke = true
        reconnectAttemptCount += 1
        Log.w(TAG, "VPN revoked on Android 14; scheduling reconnect attempt")
        logBypassEvent("vpn_disabled")
        stopVpn(stopService = false, markDisabled = false)

        thread(name = "dns-vpn-reconnect") {
            try {
                Thread.sleep(5000)
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
            reconnectScheduledFromRevoke = false
        }
    }

    private fun logBypassEvent(type: String) {
        try {
            val prefs = getSharedPreferences("trustbridge_bypass_queue", MODE_PRIVATE)
            val existing = prefs.getStringSet("events", mutableSetOf())?.toMutableSet()
                ?: mutableSetOf()
            existing.add("$type|${System.currentTimeMillis()}")
            prefs.edit().putStringSet("events", existing).apply()
        } catch (_: Exception) {
            // Never throw from revoke path.
        }
    }

    override fun onDestroy() {
        scheduleUnexpectedStopRecovery(reason = "onDestroy")
        stopVpn(stopService = false, markDisabled = false)
        try {
            filterEngine.close()
        } catch (_: Exception) {
        }
        super.onDestroy()
        Log.d(TAG, "DNS VPN service destroyed")
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        scheduleUnexpectedStopRecovery(reason = "onTaskRemoved")
    }

    private fun scheduleUnexpectedStopRecovery(reason: String) {
        val config = try {
            vpnPreferencesStore.loadConfig()
        } catch (_: Exception) {
            return
        }
        if (!config.enabled) {
            Log.d(TAG, "Unexpected-stop recovery skipped ($reason): VPN disabled")
            return
        }

        if (VpnService.prepare(this) != null) {
            Log.w(TAG, "Unexpected-stop recovery skipped ($reason): VPN permission missing")
            showProtectionAttentionNotification(
                "Protection was turned off. Open TrustBridge to restore VPN permission."
            )
            return
        }

        val nextTransientAttempt = maxOf(1, activeTransientRetryAttempt + 1)
        val inProcessScheduled = scheduleInProcessStartRetry(
            delayMs = 5_000L,
            config = config,
            bootRestore = false,
            bootRestoreAttempt = 0,
            transientRetryAttempt = nextTransientAttempt
        )
        val alarmScheduled = scheduleStartRetry(
            requestCode = 4000 + nextTransientAttempt,
            delayMs = 15_000L,
            config = config,
            bootRestore = false,
            bootRestoreAttempt = 0,
            transientRetryAttempt = nextTransientAttempt
        )

        if (inProcessScheduled || alarmScheduled) {
            Log.w(
                TAG,
                "Scheduled unexpected-stop recovery ($reason) " +
                    "attempt=$nextTransientAttempt inProcess=$inProcessScheduled alarm=$alarmScheduled"
            )
            return
        }

        showProtectionAttentionNotification(
            "Protection is off. Open TrustBridge and tap Restore Protection."
        )
    }
}
