package com.navee.trustbridge.vpn

import android.app.AlarmManager
import android.app.AppOpsManager
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import com.navee.trustbridge.MainActivity
import com.navee.trustbridge.R
import com.google.firebase.FirebaseApp
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.FirebaseFirestoreSettings
import com.google.firebase.firestore.ListenerRegistration
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetAddress
import java.util.LinkedHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

class DnsVpnService : VpnService() {
    companion object {
        private const val TAG = "DnsVpnService"
        private const val VPN_ADDRESS = "10.111.111.1"
        private const val INTERCEPT_DNS = "10.111.111.111"
        private const val DEFAULT_UPSTREAM_DNS = "1.1.1.1"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "dns_vpn_channel"
        private const val RECOVERY_NOTIFICATION_ID = 1002
        private const val RECOVERY_CHANNEL_ID = "dns_vpn_recovery_channel"
        private const val ATTENTION_NOTIFICATION_THROTTLE_MS = 120_000L
        private const val MAX_RECONNECT_ATTEMPTS = 3
        private const val MAX_BOOT_RESTORE_RETRY_ATTEMPTS = 4
        private const val MAX_TRANSIENT_START_RETRY_ATTEMPTS = 3
        private const val WATCHDOG_REQUEST_CODE = 4100
        private const val WATCHDOG_INTERVAL_MS = 5_000L
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
        private const val APP_GUARD_POLL_INTERVAL_MS = 350L
        private const val APP_GUARD_COOLDOWN_MS = 5_000L
        private const val APP_GUARD_ENFORCE_RETRIES = 4
        private const val APP_GUARD_ENFORCE_RETRY_DELAY_MS = 180L
        private const val APP_GUARD_EVENT_LOOKBACK_MS = 30_000L
        private const val APP_GUARD_BLOCKED_EVENT_WINDOW_MS = 4_000L
        private const val EFFECTIVE_POLICY_POLL_INTERVAL_MS = 5_000L
        private const val EFFECTIVE_POLICY_POLL_TIMEOUT_MS = 6_000L
        private const val INTERFACE_REFRESH_DELAY_MS = 200L
        private const val ENABLE_FORCE_SYSTEM_DNS_FLUSH = true
        private const val APP_DOMAIN_USAGE_MAX_PACKAGES = 180
        private const val APP_DOMAIN_USAGE_MAX_DOMAINS_PER_PACKAGE = 120
        private const val BLOCK_ALL_CATEGORY_TOKEN = "__block_all__"
        private val DISTRACTING_MODE_CATEGORIES = setOf(
            "social-networks",
            "chat",
            "streaming",
            "games"
        )
        private val INFRASTRUCTURE_PACKAGES = setOf(
            "com.android.vending",
            "com.google.android.gms",
            "com.google.android.gsf",
            "com.google.android.googlequicksearchbox",
            "com.google.android.ext.services",
            "com.google.android.ext.shared",
            "com.android.providers.downloads"
        )

        const val ACTION_START = "com.navee.trustbridge.vpn.START"
        const val ACTION_STOP = "com.navee.trustbridge.vpn.STOP"
        const val ACTION_RESTART = "com.navee.trustbridge.vpn.RESTART"
        const val ACTION_UPDATE_RULES = "com.navee.trustbridge.vpn.UPDATE_RULES"
        const val ACTION_INCREMENTAL_UPDATE = "com.navee.trustbridge.vpn.INCREMENTAL_UPDATE"
        const val ACTION_APPLY_POLICY = "com.navee.trustbridge.vpn.APPLY_POLICY"
        const val ACTION_POLICY_PUSH_SYNC = "com.navee.trustbridge.vpn.POLICY_PUSH_SYNC"
        const val ACTION_SET_UPSTREAM_DNS = "com.navee.trustbridge.vpn.SET_UPSTREAM_DNS"
        const val ACTION_CLEAR_QUERY_LOGS = "com.navee.trustbridge.vpn.CLEAR_QUERY_LOGS"
        const val ACTION_FLUSH_DNS = "com.navee.trustbridge.vpn.FLUSH_DNS"
        const val ACTION_FLUSH_DNS_CACHE = "com.navee.trustbridge.vpn.FLUSH_DNS_CACHE"
        const val EXTRA_BLOCKED_CATEGORIES = "blockedCategories"
        const val EXTRA_BLOCKED_DOMAINS = "blockedDomains"
        const val EXTRA_BLOCKED_PACKAGES = "blockedPackages"
        const val EXTRA_TEMP_ALLOWED_DOMAINS = "temporaryAllowedDomains"
        const val EXTRA_ADD_BLOCKED_CATEGORIES = "addBlockedCategories"
        const val EXTRA_REMOVE_BLOCKED_CATEGORIES = "removeBlockedCategories"
        const val EXTRA_ADD_BLOCKED_DOMAINS = "addBlockedDomains"
        const val EXTRA_REMOVE_BLOCKED_DOMAINS = "removeBlockedDomains"
        const val EXTRA_ADD_TEMP_ALLOWED_DOMAINS = "addTemporaryAllowedDomains"
        const val EXTRA_REMOVE_TEMP_ALLOWED_DOMAINS = "removeTemporaryAllowedDomains"
        const val EXTRA_UPSTREAM_DNS = "upstreamDns"
        const val EXTRA_PARENT_ID = "parentId"
        const val EXTRA_CHILD_ID = "childId"
        const val EXTRA_POLICY_JSON = "policyJson"
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
    private var lastAppliedBlockedPackages: List<String> = emptyList()
    private var lastAppliedUpstreamDns: String = DEFAULT_UPSTREAM_DNS

    @Volatile
    private var serviceRunning: Boolean = false
    @Volatile
    private var foregroundActive: Boolean = false
    @Volatile
    private var lastAttentionNotificationMessage: String = ""
    @Volatile
    private var lastAttentionNotificationEpochMs: Long = 0L
    @Volatile
    private var appGuardRunning: Boolean = false
    private var appGuardThread: Thread? = null
    @Volatile
    private var lastAppGuardActionEpochMs: Long = 0L
    @Volatile
    private var lastAppGuardedPackage: String = ""
    @Volatile
    private var appGuardPermissionWarningLogged: Boolean = false
    @Volatile
    private var appGuardPermissionAlertShown: Boolean = false
    private var effectivePolicyListener: ListenerRegistration? = null
    private var effectivePolicyChildId: String? = null
    @Volatile
    private var effectivePolicyPollRunning: Boolean = false
    private var effectivePolicyPollThread: Thread? = null
    @Volatile
    private var effectivePolicyPollChildId: String? = null
    @Volatile
    private var effectivePolicyPollParentId: String? = null
    @Volatile
    private var lastEffectivePolicyVersion: Long = 0L
    @Volatile
    private var lastPolicySnapshotSeenVersion: Long = 0L
    @Volatile
    private var lastPolicySnapshotSeenAtEpochMs: Long = 0L
    @Volatile
    private var lastPolicySnapshotSource: String = ""
    @Volatile
    private var lastPolicyApplyAttemptAtEpochMs: Long = 0L
    @Volatile
    private var lastPolicyApplySuccessAtEpochMs: Long = 0L
    @Volatile
    private var lastPolicyApplySource: String = ""
    @Volatile
    private var lastPolicyApplySkipReason: String = ""
    @Volatile
    private var lastPolicyApplyErrorMessage: String = ""
    @Volatile
    private var lastPolicyListenerEventAtEpochMs: Long = 0L
    @Volatile
    private var lastPolicyPollSuccessAtEpochMs: Long = 0L
    @Volatile
    private var lastPolicyTriggerVersion: Long = 0L
    @Volatile
    private var policySyncAuthBootstrapInFlight: Boolean = false
    @Volatile
    private var lastPolicySyncAuthBootstrapAtEpochMs: Long = 0L
    @Volatile
    private var cachedPolicyAckDeviceId: String? = null
    private val policyApplyExecutor = Executors.newSingleThreadExecutor()
    private val vpnExecutor = Executors.newSingleThreadScheduledExecutor()
    private val webDiagnosticsExecutor = Executors.newSingleThreadExecutor()
    private val appDomainUsageExecutor = Executors.newSingleThreadExecutor()
    @Volatile
    private var interfaceRefreshScheduled: Boolean = false
    @Volatile
    private var vpnInterfaceRebuildInFlight: Boolean = false
    @Volatile
    private var dnsFlushReceiverRegistered: Boolean = false
    private var lastKnownActivelyBlockedIps: Set<String> = emptySet()
    private val dnsFlushReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_FLUSH_DNS) {
                return
            }
            flushDnsCacheBestEffort()
        }
    }
    private val appDomainUsageByPackage = linkedMapOf<String, LinkedHashMap<String, Long>>()
    @Volatile
    private var appDomainUsageWriteQueued = false
    @Volatile
    private var appDomainUsageDirty = false
    @Volatile
    private var lastAppDomainUsageWriteEpochMs: Long = 0L
    @Volatile
    private var appInventoryWriteQueued = false
    @Volatile
    private var lastAppInventoryWriteEpochMs: Long = 0L
    @Volatile
    private var lastAppInventoryHash: String = ""
    @Volatile
    private var webDiagnosticsWriteQueued = false
    @Volatile
    private var lastWebDiagnosticsWriteEpochMs: Long = 0L
    @Volatile
    private var lastWebDiagnosticsSignature: String = ""
    @Volatile
    private var lastBrowserDnsBypassSignalEpochMs: Long = 0L
    @Volatile
    private var lastBrowserDnsBypassSignalReasonCode: String = ""
    @Volatile
    private var lastBrowserDnsBypassSignalForegroundPackage: String? = null
    private lateinit var networkIdentityResolver: NetworkIdentityResolver
    private lateinit var telemetryManager: VpnTelemetryManager
    private lateinit var policyApplyManager: PolicyApplyManager
    private lateinit var policySyncManager: PolicySyncManager

    private fun registerDnsFlushReceiver() {
        if (dnsFlushReceiverRegistered) {
            return
        }
        try {
            val filter = IntentFilter(ACTION_FLUSH_DNS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(
                    dnsFlushReceiver,
                    filter,
                    Context.RECEIVER_NOT_EXPORTED
                )
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(dnsFlushReceiver, filter)
            }
            dnsFlushReceiverRegistered = true
        } catch (error: Exception) {
            Log.w(TAG, "Unable to register DNS flush receiver", error)
        }
    }

    private fun unregisterDnsFlushReceiver() {
        if (!dnsFlushReceiverRegistered) {
            return
        }
        try {
            unregisterReceiver(dnsFlushReceiver)
        } catch (_: Exception) {
            // Ignore receiver cleanup failures.
        } finally {
            dnsFlushReceiverRegistered = false
        }
    }

    override fun onCreate() {
        super.onCreate()
        try {
            FirebaseApp.initializeApp(this)
            val firestore = FirebaseFirestore.getInstance()
            firestore.firestoreSettings = FirebaseFirestoreSettings.Builder()
                .setPersistenceEnabled(false)
                .build()
        } catch (error: Exception) {
            Log.w(TAG, "Firebase init failed in VPN process", error)
        }
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
        if (persisted.blockedPackages.isNotEmpty()) {
            lastAppliedBlockedPackages = persisted.blockedPackages
        }
        if (!hasChildProtectionContext(persisted)) {
            // Parent-only devices should never show child protection-off alerts.
            dismissProtectionAttentionNotification()
        }
        networkIdentityResolver = createNetworkIdentityResolver()
        telemetryManager = createTelemetryManager()
        policyApplyManager = createPolicyApplyManager()
        policySyncManager = createPolicySyncManager()
        filterEngine = DnsFilterEngine(this)
        blockedCategoryCount = filterEngine.blockedCategoryCount()
        blockedDomainCount = filterEngine.effectiveBlockedDomainCount()
        lastRuleUpdateEpochMs = System.currentTimeMillis()
        registerDnsFlushReceiver()
        Log.d(TAG, "DNS VPN service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        Log.d(TAG, "onStartCommand action=$action")
        if (action != ACTION_STOP) {
            // Keep notification pinned whenever protection is enabled so OEM
            // battery managers are less likely to reclaim the service.
            ensureForegroundStarted()
            // Health-check scheduling is only needed for lifecycle transitions.
            // Scheduling on every push/apply intent can exceed platform limits.
            if (action == ACTION_START || action == ACTION_RESTART) {
                VpnHealthCheckJobService.schedule(this)
            }
        }

        return when (action) {
            ACTION_START -> {
                if (serviceRunning) {
                    // Watchdog/start intents can arrive while VPN is already active. Reapplying
                    // rule extras here can resurrect stale persisted rules and clobber the
                    // live effective-policy state.
                    vpnPreferencesStore.setEnabled(true)
                    startEffectivePolicyListenerIfConfigured()
                    maybeWriteWebDiagnosticsTelemetry(force = true)
                    scheduleInstalledAppInventoryWrite()
                    scheduleWatchdogPing()
                    return START_STICKY
                }
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
                val blockedPackages =
                    intent?.getStringArrayListExtra(EXTRA_BLOCKED_PACKAGES)?.toList()
                        ?: lastAppliedBlockedPackages
                val upstreamDns =
                    intent?.getStringExtra(EXTRA_UPSTREAM_DNS) ?: lastAppliedUpstreamDns
                val configured = vpnPreferencesStore.loadConfig()
                val contextParentId = intent?.getStringExtra(EXTRA_PARENT_ID)
                    ?.trim()
                    .orEmpty()
                val contextChildId = intent?.getStringExtra(EXTRA_CHILD_ID)
                    ?.trim()
                    .orEmpty()
                val resolvedParentId = if (contextParentId.isNotEmpty()) {
                    contextParentId
                } else {
                    configured.parentId?.trim().orEmpty()
                }
                val resolvedChildId = if (contextChildId.isNotEmpty()) {
                    contextChildId
                } else {
                    configured.childId?.trim().orEmpty()
                }
                applyUpstreamDns(upstreamDns)
                startVpn()
                applyPolicySnapshotFromRuleInputs(
                    parentId = resolvedParentId,
                    childId = resolvedChildId,
                    categories = categories,
                    domains = domains,
                    temporaryAllowedDomains = allowedDomains,
                    blockedPackages = blockedPackages,
                    source = "start_intent",
                    incomingVersion = null
                )
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
                val blockedPackages =
                    intent?.getStringArrayListExtra(EXTRA_BLOCKED_PACKAGES)?.toList()
                        ?: emptyList()
                val contextParentId = intent?.getStringExtra(EXTRA_PARENT_ID)
                    ?.trim()
                    .orEmpty()
                val contextChildId = intent?.getStringExtra(EXTRA_CHILD_ID)
                    ?.trim()
                    .orEmpty()
                val hasChildPolicyContext =
                    contextParentId.isNotEmpty() && contextChildId.isNotEmpty()
                vpnPreferencesStore.setEnabled(true)
                if (!serviceRunning && hasChildPolicyContext) {
                    val hasPermission = VpnService.prepare(this) == null
                    if (hasPermission) {
                        activeBootRestoreStart = false
                        activeBootRestoreAttempt = 0
                        activeTransientRetryAttempt = 0
                        reconnectScheduledFromRevoke = false
                        ensureForegroundStarted()
                        startVpn()
                    } else {
                        Log.w(
                            TAG,
                            "Skipping VPN auto-start on rule update: permission missing"
                        )
                        showProtectionAttentionNotification(
                            "Protection is off. Open TrustBridge and tap Restore Protection."
                        )
                    }
                } else if (!serviceRunning) {
                    Log.d(
                        TAG,
                        "Skipping VPN auto-start on rule update: missing child policy context"
                    )
                }
                val configured = vpnPreferencesStore.loadConfig()
                val resolvedParentId = if (contextParentId.isNotEmpty()) {
                    contextParentId
                } else {
                    configured.parentId?.trim().orEmpty()
                }
                val resolvedChildId = if (contextChildId.isNotEmpty()) {
                    contextChildId
                } else {
                    configured.childId?.trim().orEmpty()
                }
                applyPolicySnapshotFromRuleInputs(
                    parentId = resolvedParentId,
                    childId = resolvedChildId,
                    categories = categories,
                    domains = domains,
                    temporaryAllowedDomains = allowedDomains,
                    blockedPackages = blockedPackages,
                    source = "update_rules",
                    incomingVersion = null
                )
                startEffectivePolicyListenerIfConfigured()
                flushDnsCacheBestEffort()
                scheduleInstalledAppInventoryWrite()
                scheduleWatchdogPing()
                START_STICKY
            }

            ACTION_INCREMENTAL_UPDATE -> {
                applyIncrementalUpdate(intent)
                startEffectivePolicyListenerIfConfigured()
                flushDnsCacheBestEffort()
                scheduleWatchdogPing()
                START_STICKY
            }

            ACTION_APPLY_POLICY -> {
                val policyJson = intent?.getStringExtra(EXTRA_POLICY_JSON)
                    ?.trim()
                    .orEmpty()
                if (policyJson.isEmpty()) {
                    Log.w(TAG, "applyPolicy ignored: empty policy payload")
                    return START_STICKY
                }

                val contextParentId = intent?.getStringExtra(EXTRA_PARENT_ID)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                val contextChildId = intent?.getStringExtra(EXTRA_CHILD_ID)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                if (contextParentId != null || contextChildId != null) {
                    vpnPreferencesStore.savePolicyContext(
                        parentId = contextParentId,
                        childId = contextChildId
                    )
                }

                maybeBootstrapPolicySyncAuth("apply_policy")
                if (!serviceRunning) {
                    val hasPermission = VpnService.prepare(this) == null
                    if (hasPermission) {
                        ensureForegroundStarted()
                        startVpn()
                    } else {
                        Log.w(TAG, "Skipping applyPolicy: VPN permission missing")
                        return START_STICKY
                    }
                }

                val snapshotData = parsePolicyJson(policyJson)
                if (snapshotData == null) {
                    Log.w(TAG, "applyPolicy ignored: invalid JSON payload")
                    return START_STICKY
                }

                val configured = vpnPreferencesStore.loadConfig()
                val payloadParentId = (snapshotData["parentId"] as? String)
                    ?.trim()
                    .orEmpty()
                val payloadChildId = (snapshotData["childId"] as? String)
                    ?.trim()
                    .orEmpty()
                val resolvedParentId = contextParentId
                    ?: payloadParentId.takeIf { it.isNotEmpty() }
                    ?: configured.parentId?.trim()
                    ?: ""
                val resolvedChildId = contextChildId
                    ?: payloadChildId.takeIf { it.isNotEmpty() }
                    ?: configured.childId?.trim()
                    ?: ""
                if (resolvedChildId.isEmpty()) {
                    Log.w(TAG, "applyPolicy ignored: missing childId context")
                    return START_STICKY
                }
                val incomingVersion = parsePolicyVersion(snapshotData["version"])
                if (incomingVersion == null || incomingVersion <= 0L) {
                    Log.w(TAG, "applyPolicy ignored: missing/non-positive version")
                    return START_STICKY
                }
                snapshotData["childId"] = resolvedChildId
                if (resolvedParentId.isNotEmpty()) {
                    snapshotData["parentId"] = resolvedParentId
                }

                startEffectivePolicyListenerIfConfigured()
                policyApplyExecutor.execute {
                    try {
                        applyEffectivePolicySnapshot(
                            childId = resolvedChildId,
                            snapshotData = snapshotData,
                            incomingVersion = incomingVersion,
                            source = "apply_policy"
                        )
                    } catch (error: Exception) {
                        Log.w(TAG, "applyPolicy failed", error)
                        recordPolicyApplyError(
                            source = "apply_policy",
                            version = parsePolicyVersion(snapshotData["version"]),
                            errorMessage = error.message
                        )
                    }
                }
                scheduleInstalledAppInventoryWrite()
                scheduleWatchdogPing()
                START_STICKY
            }

            ACTION_POLICY_PUSH_SYNC -> {
                val parentId = intent?.getStringExtra(EXTRA_PARENT_ID)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                val childId = intent?.getStringExtra(EXTRA_CHILD_ID)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                if (parentId != null || childId != null) {
                    vpnPreferencesStore.savePolicyContext(parentId = parentId, childId = childId)
                }
                maybeBootstrapPolicySyncAuth("policy_push")
                if (!serviceRunning) {
                    val hasPermission = VpnService.prepare(this) == null
                    if (hasPermission) {
                        ensureForegroundStarted()
                        startVpn()
                    } else {
                        Log.w(TAG, "Skipping policy push sync: VPN permission missing")
                        return START_STICKY
                    }
                }
                startEffectivePolicyListenerIfConfigured()
                policyApplyExecutor.execute {
                    try {
                        pollEffectivePolicySnapshotOnce()
                    } catch (error: Exception) {
                        Log.w(TAG, "policy push sync failed", error)
                    }
                }
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
                val hasBlockedPackages = intent?.hasExtra(EXTRA_BLOCKED_PACKAGES) == true
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
                val blockedPackages = if (hasBlockedPackages) {
                    intent?.getStringArrayListExtra(EXTRA_BLOCKED_PACKAGES)
                        ?.toList() ?: emptyList()
                } else {
                    lastAppliedBlockedPackages
                }
                val upstreamDns = if (hasUpstreamDns) {
                    intent?.getStringExtra(EXTRA_UPSTREAM_DNS)
                } else {
                    lastAppliedUpstreamDns
                }
                val configured = vpnPreferencesStore.loadConfig()
                val contextParentId = intent?.getStringExtra(EXTRA_PARENT_ID)
                    ?.trim()
                    .orEmpty()
                val contextChildId = intent?.getStringExtra(EXTRA_CHILD_ID)
                    ?.trim()
                    .orEmpty()
                val resolvedParentId = if (contextParentId.isNotEmpty()) {
                    contextParentId
                } else {
                    configured.parentId?.trim().orEmpty()
                }
                val resolvedChildId = if (contextChildId.isNotEmpty()) {
                    contextChildId
                } else {
                    configured.childId?.trim().orEmpty()
                }

                stopVpn(stopService = false, markDisabled = false)
                applyUpstreamDns(upstreamDns)
                startVpn()
                applyPolicySnapshotFromRuleInputs(
                    parentId = resolvedParentId,
                    childId = resolvedChildId,
                    categories = categories,
                    domains = domains,
                    temporaryAllowedDomains = allowedDomains,
                    blockedPackages = blockedPackages,
                    source = "restart",
                    incomingVersion = null
                )
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

            ACTION_FLUSH_DNS,
            ACTION_FLUSH_DNS_CACHE -> {
                flushDnsCacheBestEffort()
                START_STICKY
            }

            ACTION_STOP -> {
                activeBootRestoreStart = false
                activeBootRestoreAttempt = 0
                activeTransientRetryAttempt = 0
                lastScheduledBootRetryAttempt = -1
                lastScheduledTransientRetryAttempt = -1
                vpnPreferencesStore.setEnabled(false)
                VpnHealthCheckJobService.cancel(this)
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
                .addAddress(VPN_ADDRESS, 24)
                .setMtu(1500)
                .addDnsServer(INTERCEPT_DNS)

            setInitialUnderlyingNetwork(builder)

            // DNS-only VPN: route our synthetic DNS endpoint plus active network DNS
            // addresses into TUN so resolver traffic cannot bypass interception.
            val dnsCaptureRoutes = collectDnsCaptureRoutes(activeUnderlyingNetwork)
            Log.d(TAG, "DNS capture routes=$dnsCaptureRoutes")
            dnsCaptureRoutes.forEach { dnsRoute ->
                builder.addRoute(dnsRoute, 32)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setBlocking(true)
            }

            try {
                // Prevent routing loops for service sockets on OEM stacks (notably Vivo).
                builder.addDisallowedApplication(packageName)
            } catch (_: PackageManager.NameNotFoundException) {
                // Should never happen for own package; ignore if it does.
            } catch (error: Exception) {
                Log.w(TAG, "Could not exclude app from VPN", error)
            }

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
                },
                onQueryObserved = { observation ->
                    recordObservedAppDomain(
                        sourcePort = observation.sourcePort,
                        sourceIp = observation.sourceIp,
                        destPort = observation.destPort,
                        destIp = observation.destIp,
                        domain = observation.domain
                    )
                }
            )
            packetHandler?.updateBlockedDomains(lastAppliedDomains.toSet())
            packetHandler?.seedActivelyBlockedIps(lastKnownActivelyBlockedIps)

            serviceRunning = true
            isRunning = true
            vpnPreferencesStore.setEnabled(true)
            VpnHealthCheckJobService.schedule(this)
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
            maybeWriteWebDiagnosticsTelemetry(force = true)
            startPacketProcessing()
            startBlockedAppGuardLoop()
            startEffectivePolicyListenerIfConfigured()
            scheduleInstalledAppInventoryWrite(force = true)
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
                val canUseExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                    alarmManager.canScheduleExactAlarms()
                if (canUseExact) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMs,
                        pendingIntent
                    )
                } else {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMs,
                        pendingIntent
                    )
                }
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
            putStringArrayListExtra(
                EXTRA_BLOCKED_PACKAGES,
                ArrayList(config.blockedPackages)
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
                    maybeWriteWebDiagnosticsTelemetry()
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

    private fun flushDnsCacheBestEffort(): Boolean {
        var flushed = false

        try {
            val clearMethod = InetAddress::class.java.getDeclaredMethod("clearDnsCache")
            clearMethod.isAccessible = true
            clearMethod.invoke(null)
            flushed = true
            Log.d(TAG, "DNS cache flush via InetAddress.clearDnsCache()")
        } catch (_: Exception) {
            // Hidden API on many builds; ignore and continue best-effort.
        }

        try {
            val dispatcherClass = Class.forName("libcore.net.event.NetworkEventDispatcher")
            val dispatcher = dispatcherClass.getMethod("getInstance").invoke(null)
            dispatcherClass.getMethod("onNetworkConfigurationChanged").invoke(dispatcher)
            flushed = true
            Log.d(TAG, "DNS cache flush via NetworkEventDispatcher")
        } catch (_: Exception) {
            // Optional fallback.
        }

        if (flushed) {
            return true
        }

        val commandCandidates = listOf(
            listOf("cmd", "connectivity", "flush-dns-cache"),
            listOf("ndc", "resolver", "flushdefaultif")
        )
        for (command in commandCandidates) {
            try {
                val process = ProcessBuilder(command)
                    .redirectErrorStream(true)
                    .start()
                val completed = process.waitFor(300, TimeUnit.MILLISECONDS)
                if (completed && process.exitValue() == 0) {
                    flushed = true
                    Log.d(TAG, "DNS cache flush command succeeded: ${command.joinToString(" ")}")
                    break
                }
                if (!completed) {
                    process.destroy()
                }
            } catch (_: Exception) {
                // Best-effort shell command fallback.
            }
        }

        if (!flushed) {
            Log.w(TAG, "DNS cache flush unavailable on this device/build")
        }
        return flushed
    }

    private fun forceSystemDnsFlush() {
        if (!ENABLE_FORCE_SYSTEM_DNS_FLUSH) {
            return
        }
        try {
            sendBroadcast(
                Intent(ACTION_FLUSH_DNS).setPackage(packageName)
            )
        } catch (_: Exception) {
            // Broadcast dispatch is best-effort.
        }
        flushDnsCacheBestEffort()

        try {
            val network = connectivityManager.activeNetwork
            if (network != null) {
                connectivityManager.reportNetworkConnectivity(network, false)
                connectivityManager.reportNetworkConnectivity(network, true)
            }
        } catch (_: Exception) {
            // Not supported on every build.
        }

        scheduleInterfaceRefresh()
    }

    private fun scheduleInterfaceRefresh() {
        if (!serviceRunning || !isRunning || interfaceRefreshScheduled) {
            return
        }
        interfaceRefreshScheduled = true
        vpnExecutor.schedule(
            {
                interfaceRefreshScheduled = false
                if (serviceRunning && isRunning) {
                    rebuildVpnInterface()
                }
            },
            INTERFACE_REFRESH_DELAY_MS,
            TimeUnit.MILLISECONDS
        )
    }

    private fun rebuildVpnInterface() {
        if (!serviceRunning || vpnInterfaceRebuildInFlight) {
            return
        }
        vpnInterfaceRebuildInFlight = true
        val blockedDomainSnapshot = lastAppliedDomains.toSet()
        val blockedIpSnapshot = lastKnownActivelyBlockedIps.toSet()
        try {
            stopVpn(stopService = false, markDisabled = false)
            startVpn()
            packetHandler?.updateBlockedDomains(blockedDomainSnapshot)
            packetHandler?.seedActivelyBlockedIps(blockedIpSnapshot)
            Log.d(TAG, "Rebuilt VPN interface to force DNS re-resolution")
        } catch (error: Exception) {
            Log.w(TAG, "Failed rebuilding VPN interface for DNS flush", error)
        } finally {
            vpnInterfaceRebuildInFlight = false
        }
    }

    private fun collectDnsCaptureRoutes(network: Network?): Set<String> {
        val routes = linkedSetOf<String>()
        routes.add(INTERCEPT_DNS)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP || network == null) {
            return routes
        }

        val linkProperties = try {
            connectivityManager.getLinkProperties(network)
        } catch (error: Exception) {
            Log.w(TAG, "Unable to read link properties for DNS capture routes", error)
            null
        } ?: return routes

        for (dnsServer in linkProperties.dnsServers) {
            val hostAddress = dnsServer.hostAddress ?: continue
            val normalized = hostAddress.substringBefore('%').trim()
            if (normalized.isEmpty()) {
                continue
            }
            // Current packet parser handles IPv4 UDP DNS packets only.
            if (normalized.contains(":")) {
                continue
            }
            routes.add(normalized)
        }

        return routes
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
        scheduleObservedAppDomainWrite(force = true)
        serviceRunning = false
        isRunning = false
        if (markDisabled) {
            vpnPreferencesStore.setEnabled(false)
            cancelWatchdogPing()
        }
        unregisterNetworkCallback()
        stopBlockedAppGuardLoop()
        stopEffectivePolicyListener()

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

    private fun startBlockedAppGuardLoop() {
        if (appGuardRunning) {
            return
        }
        appGuardRunning = true
        appGuardThread = thread(name = "dns-vpn-app-guard") {
            while (appGuardRunning) {
                try {
                    enforceBlockedForegroundAppIfNeeded()
                } catch (_: Exception) {
                    // App-guard is best-effort and must never crash VPN service.
                }

                try {
                    Thread.sleep(APP_GUARD_POLL_INTERVAL_MS)
                } catch (_: InterruptedException) {
                    break
                }
            }
        }
    }

    private fun stopBlockedAppGuardLoop() {
        appGuardRunning = false
        appGuardThread?.interrupt()
        appGuardThread = null
    }

    private fun recentQueryLogsSnapshot(limit: Int): List<Map<String, Any>> {
        return DnsVpnService.Companion.getRecentQueryLogs(limit)
    }

    private fun telemetryPrivateDnsModeSnapshot(): String = privateDnsMode
    private fun telemetryStartedAtEpochMsSnapshot(): Long? = startedAtEpochMs
    private fun telemetryQueriesProcessedSnapshot(): Long = queriesProcessed
    private fun telemetryQueriesBlockedSnapshot(): Long = queriesBlocked
    private fun telemetryQueriesAllowedSnapshot(): Long = queriesAllowed
    private fun telemetryUpstreamFailureCountSnapshot(): Long = upstreamFailureCount
    private fun telemetryFallbackQueryCountSnapshot(): Long = fallbackQueryCount
    private fun telemetryBlockedCategoryCountSnapshot(): Int = blockedCategoryCount
    private fun telemetryBlockedDomainCountSnapshot(): Int = blockedDomainCount

    private fun createNetworkIdentityResolver(): NetworkIdentityResolver {
        return NetworkIdentityResolver(
            object : NetworkIdentityResolver.Host {
                override val appPackageName: String
                    get() = this@DnsVpnService.packageName
                override val packageManager: PackageManager
                    get() = this@DnsVpnService.packageManager
                override val infrastructurePackages: Set<String>
                    get() = INFRASTRUCTURE_PACKAGES

                override fun connectivityManagerOrNull(): ConnectivityManager? {
                    return this@DnsVpnService.getSystemService(Context.CONNECTIVITY_SERVICE)
                        as? ConnectivityManager
                }
            }
        )
    }

    private fun createTelemetryManager(): VpnTelemetryManager {
        return VpnTelemetryManager(
            object : VpnTelemetryManager.Host {
                override val tag: String
                    get() = TAG
                override val serviceRunning: Boolean
                    get() = this@DnsVpnService.serviceRunning
                override val vpnPreferencesStore: VpnPreferencesStore
                    get() = this@DnsVpnService.vpnPreferencesStore
                override val webDiagnosticsExecutor = this@DnsVpnService.webDiagnosticsExecutor
                override val appDomainUsageExecutor = this@DnsVpnService.appDomainUsageExecutor
                override val packageManager: PackageManager
                    get() = this@DnsVpnService.packageManager
                override val appPackageName: String
                    get() = this@DnsVpnService.packageName
                override val privateDnsMode: String
                    get() = this@DnsVpnService.telemetryPrivateDnsModeSnapshot()
                override val privateDnsActive: Boolean
                    get() = privateDnsMode == "opportunistic" || privateDnsMode == "hostname"
                override val startedAtEpochMs: Long?
                    get() = this@DnsVpnService.telemetryStartedAtEpochMsSnapshot()

                override val queriesProcessed: Long
                    get() = this@DnsVpnService.telemetryQueriesProcessedSnapshot()
                override val queriesBlocked: Long
                    get() = this@DnsVpnService.telemetryQueriesBlockedSnapshot()
                override val queriesAllowed: Long
                    get() = this@DnsVpnService.telemetryQueriesAllowedSnapshot()
                override val upstreamFailureCount: Long
                    get() = this@DnsVpnService.telemetryUpstreamFailureCountSnapshot()
                override val fallbackQueryCount: Long
                    get() = this@DnsVpnService.telemetryFallbackQueryCountSnapshot()
                override val blockedCategoryCount: Int
                    get() = this@DnsVpnService.telemetryBlockedCategoryCountSnapshot()
                override val blockedDomainCount: Int
                    get() = this@DnsVpnService.telemetryBlockedDomainCountSnapshot()
                override val lastAppliedCategories: List<String>
                    get() = this@DnsVpnService.lastAppliedCategories
                override val lastAppliedDomains: List<String>
                    get() = this@DnsVpnService.lastAppliedDomains
                override val lastAppliedBlockedPackages: List<String>
                    get() = this@DnsVpnService.lastAppliedBlockedPackages

                override val lastPolicySnapshotSeenVersion: Long
                    get() = this@DnsVpnService.lastPolicySnapshotSeenVersion
                override val lastEffectivePolicyVersion: Long
                    get() = this@DnsVpnService.lastEffectivePolicyVersion
                override val lastPolicySnapshotSeenAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicySnapshotSeenAtEpochMs
                override val lastPolicyApplyAttemptAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicyApplyAttemptAtEpochMs
                override val lastPolicyApplySuccessAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicyApplySuccessAtEpochMs
                override val lastPolicyApplySource: String
                    get() = this@DnsVpnService.lastPolicyApplySource
                override val lastPolicySnapshotSource: String
                    get() = this@DnsVpnService.lastPolicySnapshotSource
                override val lastPolicyApplySkipReason: String
                    get() = this@DnsVpnService.lastPolicyApplySkipReason
                override val lastPolicyApplyErrorMessage: String
                    get() = this@DnsVpnService.lastPolicyApplyErrorMessage
                override val effectivePolicyListenerAttached: Boolean
                    get() = this@DnsVpnService.effectivePolicyListener != null
                override val effectivePolicyPollRunning: Boolean
                    get() = this@DnsVpnService.effectivePolicyPollRunning
                override val lastPolicyListenerEventAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicyListenerEventAtEpochMs
                override val lastPolicyPollSuccessAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicyPollSuccessAtEpochMs

                override var cachedPolicyAckDeviceId: String?
                    get() = this@DnsVpnService.cachedPolicyAckDeviceId
                    set(value) {
                        this@DnsVpnService.cachedPolicyAckDeviceId = value
                    }

                override var lastWebDiagnosticsWriteEpochMs: Long
                    get() = this@DnsVpnService.lastWebDiagnosticsWriteEpochMs
                    set(value) {
                        this@DnsVpnService.lastWebDiagnosticsWriteEpochMs = value
                    }

                override var webDiagnosticsWriteQueued: Boolean
                    get() = this@DnsVpnService.webDiagnosticsWriteQueued
                    set(value) {
                        this@DnsVpnService.webDiagnosticsWriteQueued = value
                    }

                override var lastWebDiagnosticsSignature: String
                    get() = this@DnsVpnService.lastWebDiagnosticsSignature
                    set(value) {
                        this@DnsVpnService.lastWebDiagnosticsSignature = value
                    }

                override var lastBrowserDnsBypassSignalEpochMs: Long
                    get() = this@DnsVpnService.lastBrowserDnsBypassSignalEpochMs
                    set(value) {
                        this@DnsVpnService.lastBrowserDnsBypassSignalEpochMs = value
                    }

                override var lastBrowserDnsBypassSignalReasonCode: String
                    get() = this@DnsVpnService.lastBrowserDnsBypassSignalReasonCode
                    set(value) {
                        this@DnsVpnService.lastBrowserDnsBypassSignalReasonCode = value
                    }

                override var lastBrowserDnsBypassSignalForegroundPackage: String?
                    get() = this@DnsVpnService.lastBrowserDnsBypassSignalForegroundPackage
                    set(value) {
                        this@DnsVpnService.lastBrowserDnsBypassSignalForegroundPackage = value
                    }

                override var appDomainUsageWriteQueued: Boolean
                    get() = this@DnsVpnService.appDomainUsageWriteQueued
                    set(value) {
                        this@DnsVpnService.appDomainUsageWriteQueued = value
                    }

                override var appDomainUsageDirty: Boolean
                    get() = this@DnsVpnService.appDomainUsageDirty
                    set(value) {
                        this@DnsVpnService.appDomainUsageDirty = value
                    }

                override var lastAppDomainUsageWriteEpochMs: Long
                    get() = this@DnsVpnService.lastAppDomainUsageWriteEpochMs
                    set(value) {
                        this@DnsVpnService.lastAppDomainUsageWriteEpochMs = value
                    }

                override var appInventoryWriteQueued: Boolean
                    get() = this@DnsVpnService.appInventoryWriteQueued
                    set(value) {
                        this@DnsVpnService.appInventoryWriteQueued = value
                    }

                override var lastAppInventoryWriteEpochMs: Long
                    get() = this@DnsVpnService.lastAppInventoryWriteEpochMs
                    set(value) {
                        this@DnsVpnService.lastAppInventoryWriteEpochMs = value
                    }

                override var lastAppInventoryHash: String
                    get() = this@DnsVpnService.lastAppInventoryHash
                    set(value) {
                        this@DnsVpnService.lastAppInventoryHash = value
                    }

                override val appDomainUsageByPackage: MutableMap<String, LinkedHashMap<String, Long>>
                    get() = this@DnsVpnService.appDomainUsageByPackage

                override fun maybeBootstrapPolicySyncAuth(reason: String): Boolean {
                    return this@DnsVpnService.maybeBootstrapPolicySyncAuth(reason)
                }

                override fun ensurePolicySyncDeviceRegistration() {
                    this@DnsVpnService.ensurePolicySyncDeviceRegistration()
                }

                override fun hasUsageStatsPermissionForGuard(): Boolean {
                    return this@DnsVpnService.hasUsageStatsPermissionForGuard()
                }

                override fun currentForegroundPackageFromUsageStats(): String? {
                    return this@DnsVpnService.currentForegroundPackageFromUsageStats()
                }

                override fun getRecentQueryLogs(limit: Int): List<Map<String, Any>> {
                    return this@DnsVpnService.recentQueryLogsSnapshot(limit)
                }

                override fun isParentControllablePackage(packageName: String): Boolean {
                    return this@DnsVpnService.networkIdentityResolver
                        .isParentControllablePackage(packageName)
                }

                override fun hasInternetPermission(packageName: String): Boolean {
                    return this@DnsVpnService.networkIdentityResolver
                        .hasInternetPermission(packageName)
                }
            }
        )
    }

    private fun createPolicyApplyManager(): PolicyApplyManager {
        return PolicyApplyManager(
            object : PolicyApplyManager.Host {
                override val tag: String
                    get() = TAG
                override val serviceRunning: Boolean
                    get() = this@DnsVpnService.serviceRunning
                override val policyApplyExecutor = this@DnsVpnService.policyApplyExecutor
                override val blockAllCategoryToken: String
                    get() = BLOCK_ALL_CATEGORY_TOKEN
                override val distractingModeCategories: Set<String>
                    get() = DISTRACTING_MODE_CATEGORIES

                override var lastEffectivePolicyVersion: Long
                    get() = this@DnsVpnService.lastEffectivePolicyVersion
                    set(value) {
                        this@DnsVpnService.lastEffectivePolicyVersion = value
                    }
                override var lastPolicySnapshotSeenVersion: Long
                    get() = this@DnsVpnService.lastPolicySnapshotSeenVersion
                    set(value) {
                        this@DnsVpnService.lastPolicySnapshotSeenVersion = value
                    }
                override var lastPolicySnapshotSeenAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicySnapshotSeenAtEpochMs
                    set(value) {
                        this@DnsVpnService.lastPolicySnapshotSeenAtEpochMs = value
                    }
                override var lastPolicySnapshotSource: String
                    get() = this@DnsVpnService.lastPolicySnapshotSource
                    set(value) {
                        this@DnsVpnService.lastPolicySnapshotSource = value
                    }
                override var lastPolicyApplyAttemptAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicyApplyAttemptAtEpochMs
                    set(value) {
                        this@DnsVpnService.lastPolicyApplyAttemptAtEpochMs = value
                    }
                override var lastPolicyApplySuccessAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicyApplySuccessAtEpochMs
                    set(value) {
                        this@DnsVpnService.lastPolicyApplySuccessAtEpochMs = value
                    }
                override var lastPolicyApplySource: String
                    get() = this@DnsVpnService.lastPolicyApplySource
                    set(value) {
                        this@DnsVpnService.lastPolicyApplySource = value
                    }
                override var lastPolicyApplySkipReason: String
                    get() = this@DnsVpnService.lastPolicyApplySkipReason
                    set(value) {
                        this@DnsVpnService.lastPolicyApplySkipReason = value
                    }
                override var lastPolicyApplyErrorMessage: String
                    get() = this@DnsVpnService.lastPolicyApplyErrorMessage
                    set(value) {
                        this@DnsVpnService.lastPolicyApplyErrorMessage = value
                    }
                override var cachedPolicyAckDeviceId: String?
                    get() = this@DnsVpnService.cachedPolicyAckDeviceId
                    set(value) {
                        this@DnsVpnService.cachedPolicyAckDeviceId = value
                    }

                override val lastAppliedCategories: List<String>
                    get() = this@DnsVpnService.lastAppliedCategories
                override val lastAppliedDomains: List<String>
                    get() = this@DnsVpnService.lastAppliedDomains
                override val lastAppliedAllowedDomains: List<String>
                    get() = this@DnsVpnService.lastAppliedAllowedDomains
                override val lastAppliedBlockedPackages: List<String>
                    get() = this@DnsVpnService.lastAppliedBlockedPackages
                override val blockedCategoryCount: Int
                    get() = this@DnsVpnService.telemetryBlockedCategoryCountSnapshot()
                override val blockedDomainCount: Int
                    get() = this@DnsVpnService.telemetryBlockedDomainCountSnapshot()

                override fun normalizeCategoryToken(rawCategory: String): String {
                    return this@DnsVpnService.normalizeCategoryToken(rawCategory)
                }

                override fun normalizeDomainToken(rawDomain: String): String {
                    return this@DnsVpnService.normalizeDomainToken(rawDomain)
                }

                override fun applyFilterRules(
                    categories: List<String>,
                    domains: List<String>,
                    temporaryAllowedDomains: List<String>,
                    blockedPackages: List<String>
                ) {
                    this@DnsVpnService.applyFilterRules(
                        categories = categories,
                        domains = domains,
                        temporaryAllowedDomains = temporaryAllowedDomains,
                        blockedPackages = blockedPackages
                    )
                }

                override fun forceSystemDnsFlush() {
                    this@DnsVpnService.forceSystemDnsFlush()
                }

                override fun hasUsageStatsPermissionForGuard(): Boolean {
                    return this@DnsVpnService.hasUsageStatsPermissionForGuard()
                }
            }
        )
    }

    private fun createPolicySyncManager(): PolicySyncManager {
        return PolicySyncManager(
            object : PolicySyncManager.Host {
                override val tag: String
                    get() = TAG
                override val serviceRunning: Boolean
                    get() = this@DnsVpnService.serviceRunning
                override val vpnPreferencesStore: VpnPreferencesStore
                    get() = this@DnsVpnService.vpnPreferencesStore
                override val policyApplyExecutor = this@DnsVpnService.policyApplyExecutor

                override var policySyncAuthBootstrapInFlight: Boolean
                    get() = this@DnsVpnService.policySyncAuthBootstrapInFlight
                    set(value) {
                        this@DnsVpnService.policySyncAuthBootstrapInFlight = value
                    }

                override var lastPolicySyncAuthBootstrapAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicySyncAuthBootstrapAtEpochMs
                    set(value) {
                        this@DnsVpnService.lastPolicySyncAuthBootstrapAtEpochMs = value
                    }

                override var cachedPolicyAckDeviceId: String?
                    get() = this@DnsVpnService.cachedPolicyAckDeviceId
                    set(value) {
                        this@DnsVpnService.cachedPolicyAckDeviceId = value
                    }

                override var effectivePolicyListener: ListenerRegistration?
                    get() = this@DnsVpnService.effectivePolicyListener
                    set(value) {
                        this@DnsVpnService.effectivePolicyListener = value
                    }

                override var effectivePolicyChildId: String?
                    get() = this@DnsVpnService.effectivePolicyChildId
                    set(value) {
                        this@DnsVpnService.effectivePolicyChildId = value
                    }

                override var effectivePolicyPollRunning: Boolean
                    get() = this@DnsVpnService.effectivePolicyPollRunning
                    set(value) {
                        this@DnsVpnService.effectivePolicyPollRunning = value
                    }

                override var effectivePolicyPollThread: Thread?
                    get() = this@DnsVpnService.effectivePolicyPollThread
                    set(value) {
                        this@DnsVpnService.effectivePolicyPollThread = value
                    }

                override var effectivePolicyPollChildId: String?
                    get() = this@DnsVpnService.effectivePolicyPollChildId
                    set(value) {
                        this@DnsVpnService.effectivePolicyPollChildId = value
                    }

                override var effectivePolicyPollParentId: String?
                    get() = this@DnsVpnService.effectivePolicyPollParentId
                    set(value) {
                        this@DnsVpnService.effectivePolicyPollParentId = value
                    }

                override var lastEffectivePolicyVersion: Long
                    get() = this@DnsVpnService.lastEffectivePolicyVersion
                    set(value) {
                        this@DnsVpnService.lastEffectivePolicyVersion = value
                    }

                override var lastPolicySnapshotSeenVersion: Long
                    get() = this@DnsVpnService.lastPolicySnapshotSeenVersion
                    set(value) {
                        this@DnsVpnService.lastPolicySnapshotSeenVersion = value
                    }

                override var lastPolicySnapshotSeenAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicySnapshotSeenAtEpochMs
                    set(value) {
                        this@DnsVpnService.lastPolicySnapshotSeenAtEpochMs = value
                    }

                override var lastPolicySnapshotSource: String
                    get() = this@DnsVpnService.lastPolicySnapshotSource
                    set(value) {
                        this@DnsVpnService.lastPolicySnapshotSource = value
                    }

                override var lastPolicyApplyAttemptAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicyApplyAttemptAtEpochMs
                    set(value) {
                        this@DnsVpnService.lastPolicyApplyAttemptAtEpochMs = value
                    }

                override var lastPolicyApplySuccessAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicyApplySuccessAtEpochMs
                    set(value) {
                        this@DnsVpnService.lastPolicyApplySuccessAtEpochMs = value
                    }

                override var lastPolicyApplySource: String
                    get() = this@DnsVpnService.lastPolicyApplySource
                    set(value) {
                        this@DnsVpnService.lastPolicyApplySource = value
                    }

                override var lastPolicyApplySkipReason: String
                    get() = this@DnsVpnService.lastPolicyApplySkipReason
                    set(value) {
                        this@DnsVpnService.lastPolicyApplySkipReason = value
                    }

                override var lastPolicyApplyErrorMessage: String
                    get() = this@DnsVpnService.lastPolicyApplyErrorMessage
                    set(value) {
                        this@DnsVpnService.lastPolicyApplyErrorMessage = value
                    }

                override var lastPolicyListenerEventAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicyListenerEventAtEpochMs
                    set(value) {
                        this@DnsVpnService.lastPolicyListenerEventAtEpochMs = value
                    }

                override var lastPolicyPollSuccessAtEpochMs: Long
                    get() = this@DnsVpnService.lastPolicyPollSuccessAtEpochMs
                    set(value) {
                        this@DnsVpnService.lastPolicyPollSuccessAtEpochMs = value
                    }

                override var lastPolicyTriggerVersion: Long
                    get() = this@DnsVpnService.lastPolicyTriggerVersion
                    set(value) {
                        this@DnsVpnService.lastPolicyTriggerVersion = value
                    }

                override fun scheduleInstalledAppInventoryWrite(force: Boolean) {
                    this@DnsVpnService.scheduleInstalledAppInventoryWrite(force)
                }

                override fun applyEffectivePolicySnapshotFromManager(
                    childId: String,
                    snapshotData: HashMap<String, Any>,
                    incomingVersion: Long?,
                    source: String
                ) {
                    this@DnsVpnService.applyEffectivePolicySnapshot(
                        childId = childId,
                        snapshotData = snapshotData,
                        incomingVersion = incomingVersion,
                        source = source
                    )
                }

                override fun recordPolicySnapshotSeen(source: String, version: Long?) {
                    this@DnsVpnService.recordPolicySnapshotSeen(source = source, version = version)
                }

                override fun recordPolicyApplySkip(source: String, version: Long?, reason: String) {
                    this@DnsVpnService.recordPolicyApplySkip(
                        source = source,
                        version = version,
                        reason = reason
                    )
                }

                override fun recordPolicyApplyError(
                    source: String,
                    version: Long?,
                    errorMessage: String?
                ) {
                    this@DnsVpnService.recordPolicyApplyError(
                        source = source,
                        version = version,
                        errorMessage = errorMessage
                    )
                }

                override fun writePolicyApplyAck(
                    childId: String,
                    parentId: String,
                    appliedVersion: Long?,
                    applyStatus: String,
                    errorMessage: String?,
                    applyLatencyMs: Int?,
                    servicesExpectedCount: Int
                ) {
                    this@DnsVpnService.writePolicyApplyAck(
                        childId = childId,
                        parentId = parentId,
                        appliedVersion = appliedVersion,
                        applyStatus = applyStatus,
                        errorMessage = errorMessage,
                        applyLatencyMs = applyLatencyMs,
                        servicesExpectedCount = servicesExpectedCount
                    )
                }
            }
        )
    }

    private fun maybeBootstrapPolicySyncAuth(reason: String): Boolean {
        return policySyncManager.maybeBootstrapPolicySyncAuth(reason)
    }

    private fun ensurePolicySyncDeviceRegistration() {
        policySyncManager.ensurePolicySyncDeviceRegistration()
    }

    private fun startEffectivePolicyListenerIfConfigured() {
        policySyncManager.startEffectivePolicyListenerIfConfigured()
    }

    private fun stopEffectivePolicyListener() {
        policySyncManager.stopEffectivePolicyListener()
    }

    private fun pollEffectivePolicySnapshotOnce() {
        policySyncManager.pollEffectivePolicySnapshotOnce()
    }

    private fun parsePolicyStringList(raw: Any?): List<String> {
        return policyApplyManager.parsePolicyStringList(raw)
    }

    private fun parsePolicyVersion(raw: Any?): Long? {
        return policyApplyManager.parsePolicyVersion(raw)
    }

    private fun parsePolicyJson(raw: String): HashMap<String, Any>? {
        return policyApplyManager.parsePolicyJson(raw)
    }

    private fun parseEpochMillis(raw: Any?): Long? {
        return policyApplyManager.parseEpochMillis(raw)
    }

    private fun applyPolicySnapshotFromRuleInputs(
        parentId: String,
        childId: String,
        categories: List<String>,
        domains: List<String>,
        temporaryAllowedDomains: List<String>,
        blockedPackages: List<String>,
        source: String,
        incomingVersion: Long?
    ) {
        policyApplyManager.applyPolicySnapshotFromRuleInputs(
            parentId = parentId,
            childId = childId,
            categories = categories,
            domains = domains,
            temporaryAllowedDomains = temporaryAllowedDomains,
            blockedPackages = blockedPackages,
            source = source,
            incomingVersion = incomingVersion
        )
    }

    private fun recordPolicySnapshotSeen(source: String, version: Long?) {
        policyApplyManager.recordPolicySnapshotSeen(source, version)
    }

    private fun recordPolicyApplySkip(source: String, version: Long?, reason: String) {
        policyApplyManager.recordPolicyApplySkip(source, version, reason)
    }

    private fun recordPolicyApplyError(source: String, version: Long?, errorMessage: String?) {
        policyApplyManager.recordPolicyApplyError(source, version, errorMessage)
    }

    private fun applyEffectivePolicySnapshot(
        childId: String,
        snapshotData: Map<String, Any>,
        incomingVersion: Long?,
        source: String
    ) {
        policyApplyManager.applyEffectivePolicySnapshot(
            childId = childId,
            snapshotData = snapshotData,
            incomingVersion = incomingVersion,
            source = source
        )
    }

    private fun writePolicyApplyAck(
        childId: String,
        parentId: String,
        appliedVersion: Long?,
        applyStatus: String,
        errorMessage: String?,
        applyLatencyMs: Int?,
        servicesExpectedCount: Int
    ) {
        policyApplyManager.writePolicyApplyAck(
            childId = childId,
            parentId = parentId,
            appliedVersion = appliedVersion,
            applyStatus = applyStatus,
            errorMessage = errorMessage,
            applyLatencyMs = applyLatencyMs,
            servicesExpectedCount = servicesExpectedCount
        )
    }

    private fun maybeWriteWebDiagnosticsTelemetry(force: Boolean = false) {
        telemetryManager.maybeWriteWebDiagnosticsTelemetry(force = force)
    }

    private fun enforceBlockedForegroundAppIfNeeded() {
        if (!serviceRunning) {
            return
        }
        if (lastAppliedBlockedPackages.isEmpty()) {
            lastAppGuardedPackage = ""
            return
        }
        if (!hasUsageStatsPermissionForGuard()) {
            if (!appGuardPermissionWarningLogged) {
                appGuardPermissionWarningLogged = true
                Log.w(TAG, "Usage access missing; app-level blocking guard is inactive.")
            }
            if (!appGuardPermissionAlertShown) {
                appGuardPermissionAlertShown = true
                showProtectionAttentionNotification(
                    "App blocking needs Usage Access. Open TrustBridge on this phone and enable Usage Access."
                )
            }
            return
        }
        if (appGuardPermissionWarningLogged || appGuardPermissionAlertShown) {
            appGuardPermissionWarningLogged = false
            appGuardPermissionAlertShown = false
        }

        val blockedSet = lastAppliedBlockedPackages
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }
            .toSet()
        if (blockedSet.isEmpty()) {
            lastAppGuardedPackage = ""
            return
        }

        val usageForegroundPackage = currentForegroundPackageFromUsageStats()
            ?.trim()
            ?.lowercase()
            ?.takeIf { it.isNotEmpty() }
        val blockedForegroundFromProcess = blockedSet.firstOrNull { blockedPackage ->
            !isGuardExemptPackage(blockedPackage) && isPackageLikelyForeground(blockedPackage)
        }
        val packageToGuard = when {
            usageForegroundPackage != null &&
                !isGuardExemptPackage(usageForegroundPackage) &&
                blockedSet.contains(usageForegroundPackage) -> {
                usageForegroundPackage
            }
            blockedForegroundFromProcess != null -> blockedForegroundFromProcess
            else -> recentBlockedForegroundPackageFromUsageEvents(blockedSet)
        }
        if (packageToGuard == null) {
            if (usageForegroundPackage != null &&
                lastAppGuardedPackage == usageForegroundPackage
            ) {
                lastAppGuardedPackage = ""
            }
            return
        }

        val now = System.currentTimeMillis()
        if (now - lastAppGuardActionEpochMs < APP_GUARD_COOLDOWN_MS &&
            packageToGuard == lastAppGuardedPackage
        ) {
            return
        }
        lastAppGuardActionEpochMs = now
        lastAppGuardedPackage = packageToGuard
        Log.w(TAG, "Blocked foreground app detected package=$packageToGuard")
        showProtectionAttentionNotification(
            "Blocked app detected. Open TrustBridge to review active limits."
        )
        pushBlockedAppToHomeStrict(blockedPackage = packageToGuard)
    }

    private fun recentBlockedForegroundPackageFromUsageEvents(
        blockedPackages: Set<String>
    ): String? {
        if (blockedPackages.isEmpty()) {
            return null
        }
        val usageStatsManager = getSystemService(UsageStatsManager::class.java) ?: return null
        val endTime = System.currentTimeMillis()
        val startTime = endTime - APP_GUARD_EVENT_LOOKBACK_MS
        val usageEvents = usageStatsManager.queryEvents(startTime, endTime)
        val event = UsageEvents.Event()
        var latestBlockedPackage: String? = null
        var latestTimestamp = 0L

        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            val isForegroundEvent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                event.eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                    event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
            } else {
                event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
            }
            if (!isForegroundEvent) {
                continue
            }
            val packageName = event.packageName
                ?.trim()
                ?.lowercase()
                ?.takeIf { it.isNotEmpty() }
                ?: continue
            if (!blockedPackages.contains(packageName)) {
                continue
            }
            if (event.timeStamp >= latestTimestamp) {
                latestTimestamp = event.timeStamp
                latestBlockedPackage = packageName
            }
        }

        if (latestBlockedPackage == null) {
            return null
        }
        if (endTime - latestTimestamp > APP_GUARD_BLOCKED_EVENT_WINDOW_MS) {
            return null
        }
        if (!isPackageLikelyForeground(latestBlockedPackage)) {
            return null
        }
        return latestBlockedPackage
    }

    private fun isGuardExemptPackage(normalizedPackage: String): Boolean {
        if (normalizedPackage.isEmpty()) {
            return true
        }
        if (normalizedPackage == packageName ||
            normalizedPackage.startsWith("$packageName.") ||
            normalizedPackage == "com.android.systemui"
        ) {
            return true
        }
        if (normalizedPackage.contains("launcher")) {
            return true
        }
        if (normalizedPackage == "android" ||
            normalizedPackage == "com.android.phone" ||
            normalizedPackage == "com.android.dialer" ||
            normalizedPackage == "com.google.android.dialer"
        ) {
            return true
        }
        return false
    }

    private fun pushBlockedAppToHomeStrict(blockedPackage: String) {
        var launched = moveBlockedAppToHome()
        if (!launched) {
            Log.w(TAG, "Failed to move blocked app to home screen")
            return
        }

        repeat(APP_GUARD_ENFORCE_RETRIES - 1) {
            try {
                Thread.sleep(APP_GUARD_ENFORCE_RETRY_DELAY_MS)
            } catch (_: InterruptedException) {
                return
            }

            val currentForeground = currentForegroundPackageFromUsageStats()
                ?.trim()
                ?.lowercase()
                ?.takeIf { it.isNotEmpty() }
                ?: return
            if (currentForeground == packageName ||
                currentForeground.startsWith("$packageName.") ||
                currentForeground == "com.android.systemui" ||
                currentForeground.contains("launcher")
            ) {
                return
            }
            if (currentForeground != blockedPackage) {
                return
            }
            launched = moveBlockedAppToHome() || launched
        }
    }

    private fun moveBlockedAppToHome(): Boolean {
        return try {
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(homeIntent)
            true
        } catch (error: Exception) {
            Log.w(TAG, "Failed to move blocked app to home screen", error)
            false
        }
    }

    private fun hasUsageStatsPermissionForGuard(): Boolean {
        return try {
            val appOpsManager = getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
                ?: return false
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOpsManager.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOpsManager.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) {
            false
        }
    }

    private fun currentForegroundPackageFromUsageStats(): String? {
        val usageStatsManager = getSystemService(UsageStatsManager::class.java) ?: return null
        val endTime = System.currentTimeMillis()
        val startTime = endTime - 20_000L
        val usageEvents = usageStatsManager.queryEvents(startTime, endTime)
        val event = UsageEvents.Event()
        var latestPackage: String? = null
        var latestTimestamp = 0L

        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            val isForegroundEvent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                event.eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                    event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
            } else {
                event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
            }
            if (!isForegroundEvent) {
                continue
            }
            val packageName = event.packageName ?: continue
            if (event.timeStamp >= latestTimestamp) {
                latestTimestamp = event.timeStamp
                latestPackage = packageName
            }
        }
        val eventPackage = latestPackage
            ?.trim()
            ?.lowercase()
            ?.takeIf { it.isNotEmpty() }
        if (eventPackage != null) {
            return eventPackage
        }

        // Fallback for OEM builds that provide sparse usage events.
        return try {
            val statsWindowStart = endTime - 120_000L
            val usageStats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                statsWindowStart,
                endTime
            )
            val best = usageStats
                .asSequence()
                .mapNotNull { stat ->
                    val pkg = stat.packageName?.trim()?.lowercase().orEmpty()
                    if (pkg.isEmpty()) {
                        return@mapNotNull null
                    }
                    if (pkg == packageName ||
                        pkg.startsWith("$packageName.") ||
                        pkg == "com.android.systemui"
                    ) {
                        return@mapNotNull null
                    }
                    val lastUsed = maxOf(stat.lastTimeUsed, stat.lastTimeVisible)
                    if (lastUsed <= 0L || lastUsed < statsWindowStart) {
                        return@mapNotNull null
                    }
                    pkg to lastUsed
                }
                .maxByOrNull { it.second }
            best?.first
        } catch (_: Exception) {
            null
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
        temporaryAllowedDomains: List<String>,
        blockedPackages: List<String> = emptyList()
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
        val normalizedBlockedPackages = if (blockedPackages.isNotEmpty()) {
            blockedPackages
                .map { it.trim().lowercase() }
                .filter { it.isNotEmpty() }
                .distinct()
                .sorted()
        } else {
            deriveBlockedPackages(
                domains = normalizedDomains.toSet(),
                allowedDomains = normalizedAllowedDomains.toSet()
            )
        }

        lastAppliedCategories = normalizedCategories
        lastAppliedDomains = normalizedDomains
        lastAppliedAllowedDomains = normalizedAllowedDomains
        lastAppliedBlockedPackages = normalizedBlockedPackages
        vpnPreferencesStore.saveRules(
            categories = normalizedCategories,
            domains = normalizedDomains,
            temporaryAllowedDomains = normalizedAllowedDomains,
            blockedPackages = normalizedBlockedPackages,
            upstreamDns = lastAppliedUpstreamDns
        )
        filterEngine.updateFilterRules(
            normalizedCategories,
            normalizedDomains,
            normalizedAllowedDomains
        )
        packetHandler?.let { handler ->
            handler.updateBlockedDomains(normalizedDomains.toSet())
            lastKnownActivelyBlockedIps = handler.snapshotActivelyBlockedIps()
        }
        blockedCategoryCount = filterEngine.blockedCategoryCount()
        blockedDomainCount = filterEngine.effectiveBlockedDomainCount()
        lastRuleUpdateEpochMs = System.currentTimeMillis()
        maybeWriteWebDiagnosticsTelemetry(force = true)
    }

    private fun applyIncrementalUpdate(intent: Intent?) {
        val addCategories =
            intent?.getStringArrayListExtra(EXTRA_ADD_BLOCKED_CATEGORIES)?.toList() ?: emptyList()
        val removeCategories =
            intent?.getStringArrayListExtra(EXTRA_REMOVE_BLOCKED_CATEGORIES)?.toList() ?: emptyList()
        val addDomains =
            intent?.getStringArrayListExtra(EXTRA_ADD_BLOCKED_DOMAINS)?.toList() ?: emptyList()
        val removeDomains =
            intent?.getStringArrayListExtra(EXTRA_REMOVE_BLOCKED_DOMAINS)?.toList() ?: emptyList()
        val addAllowed =
            intent?.getStringArrayListExtra(EXTRA_ADD_TEMP_ALLOWED_DOMAINS)?.toList()
                ?: emptyList()
        val removeAllowed =
            intent?.getStringArrayListExtra(EXTRA_REMOVE_TEMP_ALLOWED_DOMAINS)?.toList()
                ?: emptyList()

        if (addCategories.isEmpty() &&
            removeCategories.isEmpty() &&
            addDomains.isEmpty() &&
            removeDomains.isEmpty() &&
            addAllowed.isEmpty() &&
            removeAllowed.isEmpty()
        ) {
            return
        }

        addCategories.forEach { raw ->
            filterEngine.addBlockedCategory(normalizeCategoryToken(raw))
        }
        removeCategories.forEach { raw ->
            filterEngine.removeBlockedCategory(normalizeCategoryToken(raw))
        }
        addDomains.forEach { raw ->
            filterEngine.addBlockedDomain(normalizeDomainToken(raw))
        }
        removeDomains.forEach { raw ->
            filterEngine.removeBlockedDomain(normalizeDomainToken(raw))
        }
        addAllowed.forEach { raw ->
            filterEngine.addTemporaryAllowedDomain(normalizeDomainToken(raw))
        }
        removeAllowed.forEach { raw ->
            filterEngine.removeTemporaryAllowedDomain(normalizeDomainToken(raw))
        }

        val nextCategories = filterEngine.snapshotBlockedCategories().toList().sorted()
        val nextDomains = filterEngine.snapshotBlockedDomains().toList().sorted()
        val nextAllowedDomains = filterEngine.snapshotTemporaryAllowedDomains().toList().sorted()
        val nextBlockedPackages = deriveBlockedPackages(
            domains = nextDomains.toSet(),
            allowedDomains = nextAllowedDomains.toSet()
        )
        packetHandler?.let { handler ->
            handler.updateBlockedDomains(nextDomains.toSet())
            lastKnownActivelyBlockedIps = handler.snapshotActivelyBlockedIps()
        }

        lastAppliedCategories = nextCategories
        lastAppliedDomains = nextDomains
        lastAppliedAllowedDomains = nextAllowedDomains
        lastAppliedBlockedPackages = nextBlockedPackages
        vpnPreferencesStore.saveRules(
            categories = nextCategories,
            domains = nextDomains,
            temporaryAllowedDomains = nextAllowedDomains,
            blockedPackages = nextBlockedPackages,
            upstreamDns = lastAppliedUpstreamDns
        )
        blockedCategoryCount = filterEngine.blockedCategoryCount()
        blockedDomainCount = filterEngine.effectiveBlockedDomainCount()
        lastRuleUpdateEpochMs = System.currentTimeMillis()
        maybeWriteWebDiagnosticsTelemetry(force = true)
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

    private fun deriveBlockedPackages(
        domains: Set<String>,
        allowedDomains: Set<String>
    ): List<String> {
        val normalizedDomains = domains
            .map(::normalizeDomainToken)
            .filter { it.isNotEmpty() }
            .toSet()
        val normalizedAllowedDomains = allowedDomains
            .map(::normalizeDomainToken)
            .filter { it.isNotEmpty() }
            .toSet()
        if (normalizedDomains.isEmpty()) {
            return emptyList()
        }

        val blockedPackages = linkedSetOf<String>()
        val observedSnapshot = synchronized(appDomainUsageByPackage) {
            appDomainUsageByPackage.mapValues { entry -> entry.value.keys.toSet() }
        }
        for ((packageName, observedDomains) in observedSnapshot) {
            if (packageName.isBlank() || observedDomains.isEmpty()) {
                continue
            }
            val blockedHit = observedDomains.any { domain ->
                matchesDomainRule(domain, normalizedDomains)
            }
            if (!blockedHit) {
                continue
            }
            val explicitlyAllowed = observedDomains.any { domain ->
                matchesDomainRule(domain, normalizedAllowedDomains)
            }
            if (!explicitlyAllowed) {
                blockedPackages.add(packageName)
            }
        }
        return blockedPackages.toList().sorted()
    }

    private fun matchesDomainRule(marker: String, domainSet: Set<String>): Boolean {
        if (domainSet.isEmpty()) {
            return false
        }
        val normalizedMarker = normalizeDomainToken(marker)
        if (normalizedMarker.isEmpty()) {
            return false
        }
        if (domainSet.contains(normalizedMarker)) {
            return true
        }
        for (candidate in domainSet) {
            if (candidate.endsWith(".$normalizedMarker")) {
                return true
            }
        }
        return false
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
            blockedPackages = lastAppliedBlockedPackages,
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
        if (!hasChildProtectionContext()) {
            // Suppress child protection-off notifications on parent-only devices.
            dismissProtectionAttentionNotification()
            return
        }
        if (serviceRunning && isRunning) {
            // Avoid surfacing stale "protection off" alerts once protection has
            // already recovered.
            return
        }
        val now = System.currentTimeMillis()
        if (message == lastAttentionNotificationMessage &&
            now - lastAttentionNotificationEpochMs < ATTENTION_NOTIFICATION_THROTTLE_MS
        ) {
            return
        }
        lastAttentionNotificationMessage = message
        lastAttentionNotificationEpochMs = now

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

    private fun hasChildProtectionContext(config: PersistedVpnConfig? = null): Boolean {
        val activeConfig = config ?: try {
            vpnPreferencesStore.loadConfig()
        } catch (_: Exception) {
            return false
        }
        val childId = activeConfig.childId?.trim().orEmpty()
        val parentId = activeConfig.parentId?.trim().orEmpty()
        return childId.isNotEmpty() && parentId.isNotEmpty()
    }

    private fun dismissProtectionAttentionNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.cancel(RECOVERY_NOTIFICATION_ID)
        lastAttentionNotificationMessage = ""
        lastAttentionNotificationEpochMs = 0L
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
                putStringArrayListExtra(EXTRA_BLOCKED_PACKAGES, ArrayList(lastAppliedBlockedPackages))
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
        scheduleObservedAppDomainWrite(force = true)
        scheduleInstalledAppInventoryWrite(force = true)
        scheduleUnexpectedStopRecovery(reason = "onDestroy")
        stopVpn(stopService = false, markDisabled = false)
        unregisterDnsFlushReceiver()
        policyApplyExecutor.shutdownNow()
        vpnExecutor.shutdownNow()
        webDiagnosticsExecutor.shutdownNow()
        appDomainUsageExecutor.shutdownNow()
        try {
            filterEngine.close()
        } catch (_: Exception) {
        }
        super.onDestroy()
        Log.d(TAG, "DNS VPN service destroyed")
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val immediateRestartRequested = requestImmediateSelfRestart(reason = "onTaskRemoved")
        if (!immediateRestartRequested) {
            Log.w(TAG, "Immediate task-removal restart could not be requested; using fallback recovery")
        }
        scheduleUnexpectedStopRecovery(reason = "onTaskRemoved")
        super.onTaskRemoved(rootIntent)
    }

    private fun requestImmediateSelfRestart(reason: String): Boolean {
        val config = try {
            vpnPreferencesStore.loadConfig()
        } catch (_: Exception) {
            return false
        }
        if (!config.enabled) {
            Log.d(TAG, "Immediate restart skipped ($reason): VPN disabled")
            return false
        }

        if (VpnService.prepare(this) != null) {
            Log.w(TAG, "Immediate restart skipped ($reason): VPN permission missing")
            return false
        }

        val nextTransientAttempt = maxOf(1, activeTransientRetryAttempt + 1)
        val restartIntent = buildStartIntent(
            config = config,
            bootRestore = false,
            bootRestoreAttempt = 0,
            transientRetryAttempt = nextTransientAttempt
        )
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(restartIntent)
            } else {
                startService(restartIntent)
            }
            Log.w(
                TAG,
                "Requested immediate VPN restart ($reason) attempt=$nextTransientAttempt"
            )
            true
        } catch (error: Exception) {
            Log.e(TAG, "Immediate restart request failed ($reason)", error)
            false
        }
    }

    private fun recordObservedAppDomain(
        sourcePort: Int,
        sourceIp: String,
        destPort: Int,
        destIp: String,
        domain: String
    ) {
        if (!serviceRunning) {
            return
        }
        val normalizedDomain = normalizeDomainToken(domain)
        if (normalizedDomain.isEmpty() || normalizedDomain == "<unknown>") {
            return
        }
        val packageName = networkIdentityResolver.resolvePackageForQuery(
            sourcePort = sourcePort,
            sourceIp = sourceIp,
            destPort = destPort,
            destIp = destIp
        )
        if (packageName.isNullOrEmpty()) {
            Log.d(
                TAG,
                "App-domain observe skipped: no package for " +
                    "src=$sourceIp:$sourcePort dst=$destIp:$destPort domain=$normalizedDomain"
            )
            return
        }
        val now = System.currentTimeMillis()
        synchronized(appDomainUsageByPackage) {
            val domains =
                appDomainUsageByPackage.getOrPut(packageName) { linkedMapOf() }
            domains[normalizedDomain] = now
            if (domains.size > APP_DOMAIN_USAGE_MAX_DOMAINS_PER_PACKAGE) {
                val oldest = domains.entries.minByOrNull { it.value }?.key
                if (oldest != null) {
                    domains.remove(oldest)
                }
            }
            if (appDomainUsageByPackage.size > APP_DOMAIN_USAGE_MAX_PACKAGES) {
                val oldestPackage = appDomainUsageByPackage.entries
                    .minByOrNull { entry ->
                        entry.value.values.minOrNull() ?: Long.MAX_VALUE
                    }
                    ?.key
                if (oldestPackage != null) {
                    appDomainUsageByPackage.remove(oldestPackage)
                }
            }
        }
        appDomainUsageDirty = true
        Log.d(
            TAG,
            "App-domain observed package=$packageName domain=$normalizedDomain port=$sourcePort"
        )
        maybeEnforceBlockedObservedPackage(packageName)
        scheduleObservedAppDomainWrite()
        scheduleInstalledAppInventoryWrite()
    }

    private fun maybeEnforceBlockedObservedPackage(packageName: String) {
        if (!serviceRunning) {
            return
        }
        val normalizedPackage = packageName.trim().lowercase()
        if (normalizedPackage.isEmpty() || isGuardExemptPackage(normalizedPackage)) {
            return
        }
        if (!lastAppliedBlockedPackages.contains(normalizedPackage)) {
            return
        }
        val likelyForeground = isPackageLikelyForeground(normalizedPackage)
        val hasRecentDnsBurst = hasRecentDnsBurstForPackage(
            packageName = normalizedPackage,
            minHits = 4,
            windowMs = 2_500L
        )
        if (!likelyForeground && !hasRecentDnsBurst) {
            return
        }
        if (!likelyForeground && hasRecentDnsBurst) {
            val powerManager = getSystemService(PowerManager::class.java)
            if (powerManager?.isInteractive != true) {
                return
            }
        }
        val now = System.currentTimeMillis()
        if (now - lastAppGuardActionEpochMs < APP_GUARD_COOLDOWN_MS &&
            normalizedPackage == lastAppGuardedPackage
        ) {
            return
        }
        lastAppGuardActionEpochMs = now
        lastAppGuardedPackage = normalizedPackage
        Log.w(
            TAG,
            "Blocked app traffic detected from foreground package=$normalizedPackage"
        )
        showProtectionAttentionNotification(
            "Blocked app detected. Open TrustBridge to review active limits."
        )
        pushBlockedAppToHomeStrict(blockedPackage = normalizedPackage)
    }

    private fun hasRecentDnsBurstForPackage(
        packageName: String,
        minHits: Int,
        windowMs: Long
    ): Boolean {
        if (packageName.isBlank() || minHits <= 0 || windowMs <= 0L) {
            return false
        }
        val now = System.currentTimeMillis()
        val cutoff = now - windowMs
        val timestamps = synchronized(appDomainUsageByPackage) {
            appDomainUsageByPackage[packageName]?.values?.toList()
        } ?: return false
        var hits = 0
        for (ts in timestamps) {
            if (ts >= cutoff) {
                hits += 1
                if (hits >= minHits) {
                    return true
                }
            }
        }
        return false
    }

    private fun isPackageLikelyForeground(packageName: String): Boolean {
        val normalizedPackage = packageName.trim().lowercase()
        if (normalizedPackage.isEmpty()) {
            return false
        }
        val usageForeground = currentForegroundPackageFromUsageStats()
            ?.trim()
            ?.lowercase()
            ?.takeIf { it.isNotEmpty() }
        if (usageForeground == normalizedPackage) {
            return true
        }

        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return false
        val runningProcesses = activityManager.runningAppProcesses ?: return false
        for (processInfo in runningProcesses) {
            val importance = processInfo.importance
            val isForegroundImportance =
                importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND ||
                    importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE ||
                    importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_PERCEPTIBLE
            if (!isForegroundImportance) {
                continue
            }
            val processName = processInfo.processName?.trim()?.lowercase().orEmpty()
            if (processName == normalizedPackage) {
                return true
            }
            val packageList = processInfo.pkgList ?: emptyArray()
            if (packageList.any { pkg ->
                    pkg.trim().lowercase() == normalizedPackage
                }
            ) {
                return true
            }
        }
        return false
    }

    private fun scheduleObservedAppDomainWrite(force: Boolean = false) {
        telemetryManager.scheduleObservedAppDomainWrite(force = force)
    }

    private fun scheduleInstalledAppInventoryWrite(force: Boolean = false) {
        telemetryManager.scheduleInstalledAppInventoryWrite(force = force)
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
        val inProcessDelayMs = if (reason == "onTaskRemoved") 1_000L else 5_000L
        val alarmDelayMs = if (reason == "onTaskRemoved") 5_000L else 15_000L
        val inProcessScheduled = scheduleInProcessStartRetry(
            delayMs = inProcessDelayMs,
            config = config,
            bootRestore = false,
            bootRestoreAttempt = 0,
            transientRetryAttempt = nextTransientAttempt
        )
        val alarmScheduled = scheduleStartRetry(
            requestCode = 4000 + nextTransientAttempt,
            delayMs = alarmDelayMs,
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
