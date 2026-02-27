package com.navee.trustbridge.vpn

import android.app.AlarmManager
import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Process
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import com.navee.trustbridge.MainActivity
import com.navee.trustbridge.R
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.SetOptions
import com.google.android.gms.tasks.Tasks
import java.io.FileInputStream
import java.io.FileOutputStream
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
        private const val APP_GUARD_POLL_INTERVAL_MS = 1_200L
        private const val APP_GUARD_COOLDOWN_MS = 1_500L
        private const val EFFECTIVE_POLICY_POLL_INTERVAL_MS = 5_000L
        private const val EFFECTIVE_POLICY_POLL_TIMEOUT_MS = 6_000L
        private const val WEB_DIAGNOSTICS_WRITE_MIN_INTERVAL_MS = 5_000L
        private const val WEB_DIAGNOSTICS_RECENT_DNS_WINDOW_MS = 20_000L
        private const val BLOCK_ALL_CATEGORY_TOKEN = "__block_all__"
        private val DISTRACTING_MODE_CATEGORIES = setOf(
            "social-networks",
            "chat",
            "streaming",
            "games"
        )
        private val WEB_DIAGNOSTIC_BROWSER_PACKAGES = setOf(
            "com.android.chrome",
            "org.chromium.chrome",
            "com.chrome.beta",
            "com.chrome.dev",
            "com.microsoft.emmx",
            "org.mozilla.firefox",
            "org.mozilla.firefox_beta",
            "org.mozilla.fenix",
            "com.opera.browser",
            "com.opera.mini.native",
            "com.brave.browser",
            "com.sec.android.app.sbrowser",
            "com.vivo.browser",
            "com.heytap.browser",
            "com.mi.globalbrowser",
            "com.kiwibrowser.browser"
        )

        const val ACTION_START = "com.navee.trustbridge.vpn.START"
        const val ACTION_STOP = "com.navee.trustbridge.vpn.STOP"
        const val ACTION_RESTART = "com.navee.trustbridge.vpn.RESTART"
        const val ACTION_UPDATE_RULES = "com.navee.trustbridge.vpn.UPDATE_RULES"
        const val ACTION_SET_UPSTREAM_DNS = "com.navee.trustbridge.vpn.SET_UPSTREAM_DNS"
        const val ACTION_CLEAR_QUERY_LOGS = "com.navee.trustbridge.vpn.CLEAR_QUERY_LOGS"
        const val EXTRA_BLOCKED_CATEGORIES = "blockedCategories"
        const val EXTRA_BLOCKED_DOMAINS = "blockedDomains"
        const val EXTRA_BLOCKED_PACKAGES = "blockedPackages"
        const val EXTRA_TEMP_ALLOWED_DOMAINS = "temporaryAllowedDomains"
        const val EXTRA_UPSTREAM_DNS = "upstreamDns"
        const val EXTRA_PARENT_ID = "parentId"
        const val EXTRA_CHILD_ID = "childId"
        const val EXTRA_BOOT_RESTORE = "bootRestore"
        const val EXTRA_BOOT_RESTORE_ATTEMPT = "bootRestoreAttempt"
        const val EXTRA_TRANSIENT_RETRY_ATTEMPT = "transientRetryAttempt"

        private val APP_BLOCK_RULES = listOf(
            AppBlockRule(
                categories = setOf("social", "social-networks"),
                domainMarkers = setOf(
                    "instagram.com",
                    "tiktok.com",
                    "facebook.com",
                    "snapchat.com",
                    "twitter.com",
                    "x.com"
                ),
                packages = setOf(
                    "com.instagram.android",
                    "com.zhiliaoapp.musically",
                    "com.facebook.katana",
                    "com.facebook.lite",
                    "com.snapchat.android",
                    "com.twitter.android",
                    "com.xcorp.android"
                )
            ),
            AppBlockRule(
                categories = setOf("streaming"),
                domainMarkers = setOf("youtube.com", "m.youtube.com", "youtubei.googleapis.com"),
                packages = setOf(
                    "com.google.android.youtube",
                    "app.revanced.android.youtube",
                    "com.google.android.apps.youtube.music"
                )
            ),
            AppBlockRule(
                categories = setOf("forums"),
                domainMarkers = setOf("reddit.com", "redd.it"),
                packages = setOf("com.reddit.frontpage")
            ),
            AppBlockRule(
                categories = setOf("games"),
                domainMarkers = setOf("roblox.com"),
                packages = setOf("com.roblox.client")
            ),
            AppBlockRule(
                categories = setOf("chat"),
                domainMarkers = setOf("whatsapp.com", "telegram.org", "discord.com"),
                packages = setOf(
                    "com.whatsapp",
                    "com.whatsapp.w4b",
                    "org.telegram.messenger",
                    "com.discord"
                )
            )
        )

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
    private var appGuardRunning: Boolean = false
    private var appGuardThread: Thread? = null
    @Volatile
    private var lastAppGuardActionEpochMs: Long = 0L
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
    private var policySyncAuthBootstrapInFlight: Boolean = false
    @Volatile
    private var lastPolicySyncAuthBootstrapAtEpochMs: Long = 0L
    @Volatile
    private var cachedPolicyAckDeviceId: String? = null
    private val policyApplyExecutor = Executors.newSingleThreadExecutor()
    private val webDiagnosticsExecutor = Executors.newSingleThreadExecutor()
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
        if (persisted.blockedPackages.isNotEmpty()) {
            lastAppliedBlockedPackages = persisted.blockedPackages
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
        if (action != ACTION_STOP) {
            // Keep notification pinned whenever protection is enabled so OEM
            // battery managers are less likely to reclaim the service.
            ensureForegroundStarted()
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
                applyUpstreamDns(upstreamDns)
                applyFilterRules(categories, domains, allowedDomains, blockedPackages)
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
                applyFilterRules(categories, domains, allowedDomains, blockedPackages)
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
                startEffectivePolicyListenerIfConfigured()
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

                stopVpn(stopService = false, markDisabled = false)
                applyUpstreamDns(upstreamDns)
                applyFilterRules(categories, domains, allowedDomains, blockedPackages)
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
                .addAddress(VPN_ADDRESS, 24)
                .setMtu(1500)
                .addDnsServer(INTERCEPT_DNS)

            setInitialUnderlyingNetwork(builder)

            // DNS-only VPN: route our synthetic DNS endpoint plus active network DNS
            // addresses into TUN so resolver traffic cannot bypass interception.
            val dnsCaptureRoutes = collectDnsCaptureRoutes(activeUnderlyingNetwork)
            Log.e(TAG, "DNS capture routes=$dnsCaptureRoutes")
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
            maybeWriteWebDiagnosticsTelemetry(force = true)
            startPacketProcessing()
            startBlockedAppGuardLoop()
            startEffectivePolicyListenerIfConfigured()
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

                    Log.e(TAG, "TUN_PACKET_READ bytes=$length")

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

    private fun firestoreAuthReadyForPolicySync(): Boolean {
        return try {
            FirebaseAuth.getInstance().currentUser != null
        } catch (_: Exception) {
            false
        }
    }

    private fun maybeBootstrapPolicySyncAuth(reason: String): Boolean {
        if (firestoreAuthReadyForPolicySync()) {
            return true
        }

        val now = System.currentTimeMillis()
        if (policySyncAuthBootstrapInFlight) {
            return false
        }
        if (now - lastPolicySyncAuthBootstrapAtEpochMs < 8_000L) {
            return false
        }

        lastPolicySyncAuthBootstrapAtEpochMs = now
        policySyncAuthBootstrapInFlight = true
        val auth = try {
            FirebaseAuth.getInstance()
        } catch (error: Exception) {
            policySyncAuthBootstrapInFlight = false
            Log.w(TAG, "Policy sync auth bootstrap unavailable", error)
            return false
        }

        Log.w(TAG, "Policy sync auth missing. Bootstrapping anonymous auth ($reason)")
        auth.signInAnonymously()
            .addOnSuccessListener {
                policySyncAuthBootstrapInFlight = false
                Log.i(TAG, "Policy sync auth bootstrap succeeded ($reason)")
                if (serviceRunning) {
                    ensurePolicySyncDeviceRegistration()
                    startEffectivePolicyListenerIfConfigured()
                }
            }
            .addOnFailureListener { error ->
                policySyncAuthBootstrapInFlight = false
                Log.w(TAG, "Policy sync auth bootstrap failed ($reason)", error)
            }
        return false
    }

    private fun ensurePolicySyncDeviceRegistration() {
        val authUid = try {
            FirebaseAuth.getInstance().currentUser?.uid?.trim().orEmpty()
        } catch (_: Exception) {
            ""
        }
        if (authUid.isEmpty()) {
            return
        }

        val config = try {
            vpnPreferencesStore.loadConfig()
        } catch (_: Exception) {
            return
        }
        val childId = config.childId?.trim().orEmpty()
        val parentId = config.parentId?.trim().orEmpty()
        if (childId.isEmpty() || parentId.isEmpty()) {
            return
        }

        cachedPolicyAckDeviceId = authUid
        val firestore = FirebaseFirestore.getInstance()
        firestore.collection("children")
            .document(childId)
            .collection("devices")
            .document(authUid)
            .set(
                mapOf(
                    "parentId" to parentId,
                    "pairedAt" to Timestamp.now()
                ),
                SetOptions.merge()
            )
            .addOnSuccessListener {
                firestore.collection("children")
                    .document(childId)
                    .update(
                        mapOf(
                            "deviceIds" to FieldValue.arrayUnion(authUid),
                            "updatedAt" to Timestamp.now()
                        )
                    )
                    .addOnFailureListener { error ->
                        Log.w(TAG, "Failed to refresh child deviceIds for policy sync auth", error)
                    }
            }
            .addOnFailureListener { error ->
                Log.w(TAG, "Failed to upsert child device record for policy sync auth", error)
            }
    }

    private fun extractFirestoreException(error: Throwable?): FirebaseFirestoreException? {
        if (error == null) {
            return null
        }
        if (error is FirebaseFirestoreException) {
            return error
        }
        return extractFirestoreException(error.cause)
    }

    private fun isPolicySyncAuthError(error: Throwable?): Boolean {
        val firestoreError = extractFirestoreException(error) ?: return false
        return firestoreError.code == FirebaseFirestoreException.Code.UNAUTHENTICATED ||
            firestoreError.code == FirebaseFirestoreException.Code.PERMISSION_DENIED
    }

    private fun startEffectivePolicyListenerIfConfigured() {
        if (!serviceRunning) {
            return
        }
        val config = vpnPreferencesStore.loadConfig()
        val childId = config.childId?.trim().orEmpty()
        if (childId.isEmpty()) {
            stopEffectivePolicyListener()
            return
        }
        if (!maybeBootstrapPolicySyncAuth("listener_start")) {
            return
        }
        ensurePolicySyncDeviceRegistration()
        if (effectivePolicyListener != null && effectivePolicyChildId == childId) {
            startEffectivePolicyPollingFallback(
                childId = childId,
                configuredParentId = config.parentId?.trim().orEmpty()
            )
            return
        }

        stopEffectivePolicyListener()
        effectivePolicyChildId = childId
        val configuredParentId = config.parentId?.trim().orEmpty()
        effectivePolicyListener = FirebaseFirestore.getInstance()
            .collection("children")
            .document(childId)
            .collection("effective_policy")
            .document("current")
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.w(TAG, "effective_policy listener error", error)
                    if (isPolicySyncAuthError(error)) {
                        maybeBootstrapPolicySyncAuth("listener_error")
                    }
                    return@addSnapshotListener
                }
                val data = snapshot?.data ?: return@addSnapshotListener
                if (!serviceRunning) {
                    return@addSnapshotListener
                }
                lastPolicyListenerEventAtEpochMs = System.currentTimeMillis()

                val snapshotParentId = (data["parentId"] as? String)?.trim().orEmpty()
                if (configuredParentId.isNotEmpty() &&
                    snapshotParentId.isNotEmpty() &&
                    snapshotParentId != configuredParentId
                ) {
                    recordPolicyApplySkip(
                        source = "listener",
                        version = parsePolicyVersion(data["version"]),
                        reason = "parent_id_mismatch"
                    )
                    return@addSnapshotListener
                }

                val incomingVersion = parsePolicyVersion(data["version"])
                recordPolicySnapshotSeen("listener", incomingVersion)
                val snapshotData = HashMap(data)
                policyApplyExecutor.execute {
                    try {
                        applyEffectivePolicySnapshot(
                            childId = childId,
                            snapshotData = snapshotData,
                            incomingVersion = incomingVersion,
                            source = "listener"
                        )
                    } catch (error: Exception) {
                        Log.w(TAG, "Failed to apply effective policy snapshot", error)
                        recordPolicyApplyError(
                            source = "listener",
                            version = incomingVersion,
                            errorMessage = error.message
                        )
                        writePolicyApplyAck(
                            childId = childId,
                            parentId = snapshotParentId,
                            appliedVersion = incomingVersion,
                            applyStatus = "error",
                            errorMessage = error.message,
                            applyLatencyMs = null,
                            servicesExpectedCount = parsePolicyStringList(snapshotData["blockedServices"]).size
                        )
                    }
                }
            }
        Log.d(TAG, "Started effective_policy listener childId=$childId")
        startEffectivePolicyPollingFallback(
            childId = childId,
            configuredParentId = configuredParentId
        )
    }

    private fun stopEffectivePolicyListener() {
        effectivePolicyListener?.remove()
        effectivePolicyListener = null
        stopEffectivePolicyPollingFallback()
        effectivePolicyChildId = null
        lastEffectivePolicyVersion = 0L
        lastPolicySnapshotSeenVersion = 0L
        lastPolicySnapshotSeenAtEpochMs = 0L
        lastPolicySnapshotSource = ""
        lastPolicyApplyAttemptAtEpochMs = 0L
        lastPolicyApplySuccessAtEpochMs = 0L
        lastPolicyApplySource = ""
        lastPolicyApplySkipReason = ""
        lastPolicyApplyErrorMessage = ""
        lastPolicyListenerEventAtEpochMs = 0L
        lastPolicyPollSuccessAtEpochMs = 0L
        cachedPolicyAckDeviceId = null
    }

    private fun startEffectivePolicyPollingFallback(
        childId: String,
        configuredParentId: String
    ) {
        val normalizedChildId = childId.trim()
        if (normalizedChildId.isEmpty()) {
            stopEffectivePolicyPollingFallback()
            return
        }
        val normalizedParentId = configuredParentId.trim()
        if (effectivePolicyPollRunning &&
            effectivePolicyPollChildId == normalizedChildId &&
            effectivePolicyPollParentId == normalizedParentId
        ) {
            return
        }

        stopEffectivePolicyPollingFallback()
        effectivePolicyPollRunning = true
        effectivePolicyPollChildId = normalizedChildId
        effectivePolicyPollParentId = normalizedParentId
        effectivePolicyPollThread = thread(name = "dns-vpn-policy-poll") {
            while (effectivePolicyPollRunning) {
                try {
                    pollEffectivePolicySnapshotOnce()
                } catch (error: Exception) {
                    Log.w(TAG, "effective_policy poll error", error)
                }
                try {
                    Thread.sleep(EFFECTIVE_POLICY_POLL_INTERVAL_MS)
                } catch (_: InterruptedException) {
                    break
                }
            }
        }
        Log.d(TAG, "Started effective_policy polling fallback childId=$normalizedChildId")
    }

    private fun stopEffectivePolicyPollingFallback() {
        effectivePolicyPollRunning = false
        effectivePolicyPollThread?.interrupt()
        effectivePolicyPollThread = null
        effectivePolicyPollChildId = null
        effectivePolicyPollParentId = null
    }

    private fun pollEffectivePolicySnapshotOnce() {
        if (!serviceRunning) {
            return
        }
        val childId = effectivePolicyPollChildId?.trim().orEmpty()
        if (childId.isEmpty()) {
            return
        }
        val configuredParentId = effectivePolicyPollParentId?.trim().orEmpty()

        val snapshot = try {
            Tasks.await(
                FirebaseFirestore.getInstance()
                    .collection("children")
                    .document(childId)
                    .collection("effective_policy")
                    .document("current")
                    .get(),
                EFFECTIVE_POLICY_POLL_TIMEOUT_MS,
                TimeUnit.MILLISECONDS
            )
        } catch (error: Exception) {
            Log.w(TAG, "effective_policy poll get failed childId=$childId", error)
            if (isPolicySyncAuthError(error)) {
                maybeBootstrapPolicySyncAuth("poll_get")
            }
            return
        }
        val data = snapshot.data ?: return
        if (!serviceRunning) {
            return
        }

        val snapshotParentId = (data["parentId"] as? String)?.trim().orEmpty()
        if (configuredParentId.isNotEmpty() &&
            snapshotParentId.isNotEmpty() &&
            snapshotParentId != configuredParentId
        ) {
            recordPolicyApplySkip(
                source = "poll",
                version = parsePolicyVersion(data["version"]),
                reason = "parent_id_mismatch"
            )
            return
        }
        val incomingVersion = parsePolicyVersion(data["version"])
        lastPolicyPollSuccessAtEpochMs = System.currentTimeMillis()
        recordPolicySnapshotSeen("poll", incomingVersion)

        val snapshotData = HashMap(data)
        policyApplyExecutor.execute {
            try {
                applyEffectivePolicySnapshot(
                    childId = childId,
                    snapshotData = snapshotData,
                    incomingVersion = incomingVersion,
                    source = "poll"
                )
            } catch (error: Exception) {
                Log.w(TAG, "Failed to apply effective policy snapshot from poll", error)
                recordPolicyApplyError(
                    source = "poll",
                    version = incomingVersion,
                    errorMessage = error.message
                )
                writePolicyApplyAck(
                    childId = childId,
                    parentId = snapshotParentId,
                    appliedVersion = incomingVersion,
                    applyStatus = "error",
                    errorMessage = error.message,
                    applyLatencyMs = null,
                    servicesExpectedCount = parsePolicyStringList(snapshotData["blockedServices"]).size
                )
            }
        }
    }

    private fun parsePolicyStringList(raw: Any?): List<String> {
        if (raw !is List<*>) {
            return emptyList()
        }
        return raw.mapNotNull { item ->
            (item as? String)?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        }
    }

    private fun parsePolicyVersion(raw: Any?): Long? {
        return when (raw) {
            is Long -> raw
            is Int -> raw.toLong()
            is Double -> raw.toLong()
            is String -> raw.toLongOrNull()
            else -> null
        }
    }

    private fun parseEpochMillis(raw: Any?): Long? {
        return when (raw) {
            is Timestamp -> raw.toDate().time
            is java.util.Date -> raw.time
            is Long -> raw
            is Int -> raw.toLong()
            is Double -> raw.toLong()
            is String -> raw.toLongOrNull()
            else -> null
        }
    }

    private fun recordPolicySnapshotSeen(source: String, version: Long?) {
        val now = System.currentTimeMillis()
        lastPolicySnapshotSeenAtEpochMs = now
        lastPolicySnapshotSource = source
        if (version != null && version > 0L) {
            lastPolicySnapshotSeenVersion = version
        }
    }

    private fun recordPolicyApplySkip(source: String, version: Long?, reason: String) {
        lastPolicyApplyAttemptAtEpochMs = System.currentTimeMillis()
        lastPolicyApplySource = source
        lastPolicyApplySkipReason = reason
        lastPolicyApplyErrorMessage = ""
        if (version != null && version > 0L) {
            lastPolicySnapshotSeenVersion = version
        }
    }

    private fun recordPolicyApplyError(source: String, version: Long?, errorMessage: String?) {
        lastPolicyApplyAttemptAtEpochMs = System.currentTimeMillis()
        lastPolicyApplySource = source
        lastPolicyApplySkipReason = ""
        lastPolicyApplyErrorMessage = errorMessage?.trim().orEmpty()
        if (version != null && version > 0L) {
            lastPolicySnapshotSeenVersion = version
        }
    }

    private fun recordPolicyApplySuccess(source: String, version: Long?) {
        val now = System.currentTimeMillis()
        lastPolicyApplyAttemptAtEpochMs = now
        lastPolicyApplySuccessAtEpochMs = now
        lastPolicyApplySource = source
        lastPolicyApplySkipReason = ""
        lastPolicyApplyErrorMessage = ""
        if (version != null && version > 0L) {
            lastPolicySnapshotSeenVersion = version
        }
    }

    private fun parseActiveManualMode(raw: Any?, nowEpochMs: Long): String? {
        if (raw !is Map<*, *>) {
            return null
        }
        val mode = (raw["mode"] as? String)?.trim()?.lowercase().orEmpty()
        if (mode.isEmpty()) {
            return null
        }
        val expiresAtEpochMs = parseEpochMillis(raw["expiresAt"])
        if (expiresAtEpochMs != null && expiresAtEpochMs <= nowEpochMs) {
            return null
        }
        return mode
    }

    private fun buildEffectiveListenerCategories(
        baseCategories: List<String>,
        activeManualMode: String?,
        pauseActive: Boolean
    ): List<String> {
        val effective = linkedSetOf<String>()
        effective.addAll(
            baseCategories
                .map(::normalizeCategoryToken)
                .filter { it.isNotEmpty() }
        )
        if (pauseActive) {
            effective.add(BLOCK_ALL_CATEGORY_TOKEN)
        } else {
            when (activeManualMode) {
                "bedtime" -> effective.add(BLOCK_ALL_CATEGORY_TOKEN)
                "homework" -> effective.addAll(DISTRACTING_MODE_CATEGORIES)
                "free" -> {
                    // Explicit free mode only keeps baseline policy categories.
                }
            }
        }
        return effective.toList().sorted()
    }

    private fun applyEffectivePolicySnapshot(
        childId: String,
        snapshotData: Map<String, Any>,
        incomingVersion: Long?,
        source: String
    ) {
        if (!serviceRunning) {
            recordPolicyApplySkip(source, incomingVersion, "service_not_running")
            return
        }
        lastPolicyApplyAttemptAtEpochMs = System.currentTimeMillis()
        lastPolicyApplySource = source
        lastPolicyApplyErrorMessage = ""

        val baseCategories = parsePolicyStringList(snapshotData["blockedCategories"])
        val blockedServices = parsePolicyStringList(snapshotData["blockedServices"])
        val resolvedDomains = parsePolicyStringList(snapshotData["blockedDomainsResolved"])
        val fallbackDomains = parsePolicyStringList(snapshotData["blockedDomains"])
        val resolvedPackages = parsePolicyStringList(snapshotData["blockedPackagesResolved"])
        val fallbackPackages = parsePolicyStringList(snapshotData["blockedPackages"])
        val resolvedAllowedDomains =
            parsePolicyStringList(snapshotData["temporaryAllowedDomainsResolved"])
        val modeBlockedDomains = parsePolicyStringList(snapshotData["modeBlockedDomainsResolved"])
        val modeAllowedDomains = parsePolicyStringList(snapshotData["modeAllowedDomainsResolved"])
        val modeBlockedPackages =
            parsePolicyStringList(snapshotData["modeBlockedPackagesResolved"])
        val modeAllowedPackages =
            parsePolicyStringList(snapshotData["modeAllowedPackagesResolved"])
        val snapshotParentId = (snapshotData["parentId"] as? String)?.trim().orEmpty()
        val nowEpochMs = System.currentTimeMillis()
        val pausedUntilEpochMs = parseEpochMillis(snapshotData["pausedUntil"])
        val pauseActive = pausedUntilEpochMs != null && pausedUntilEpochMs > nowEpochMs
        val activeManualMode = parseActiveManualMode(snapshotData["manualMode"], nowEpochMs)

        val categories = buildEffectiveListenerCategories(
            baseCategories = baseCategories,
            activeManualMode = activeManualMode,
            pauseActive = pauseActive
        )
        val domainSet = linkedSetOf<String>()
        domainSet.addAll(
            (if (resolvedDomains.isNotEmpty()) {
                resolvedDomains
            } else {
                fallbackDomains
            }).map(::normalizeDomainToken)
                .filter { it.isNotEmpty() }
        )
        domainSet.addAll(
            modeBlockedDomains
                .map(::normalizeDomainToken)
                .filter { it.isNotEmpty() }
        )
        domainSet.removeAll(
            modeAllowedDomains
                .map(::normalizeDomainToken)
                .filter { it.isNotEmpty() }
                .toSet()
        )
        val domains = domainSet.toList().sorted()

        val blockedPackageSet = linkedSetOf<String>()
        blockedPackageSet.addAll(
            (if (resolvedPackages.isNotEmpty()) {
                resolvedPackages
            } else {
                fallbackPackages
            }).map { it.trim().lowercase() }
                .filter { it.isNotEmpty() }
        )
        blockedPackageSet.addAll(
            modeBlockedPackages
                .map { it.trim().lowercase() }
                .filter { it.isNotEmpty() }
        )
        blockedPackageSet.removeAll(
            modeAllowedPackages
                .map { it.trim().lowercase() }
                .filter { it.isNotEmpty() }
                .toSet()
        )
        val blockedPackages = blockedPackageSet.toList().sorted()

        val allowedDomainSet = linkedSetOf<String>()
        val hasPolicyAllowedDomainFields =
            snapshotData.containsKey("temporaryAllowedDomainsResolved") ||
                snapshotData.containsKey("modeAllowedDomainsResolved")
        if (!hasPolicyAllowedDomainFields) {
            allowedDomainSet.addAll(
                lastAppliedAllowedDomains
                    .map(::normalizeDomainToken)
                    .filter { it.isNotEmpty() }
            )
        }
        allowedDomainSet.addAll(
            resolvedAllowedDomains
                .map(::normalizeDomainToken)
                .filter { it.isNotEmpty() }
        )
        allowedDomainSet.addAll(
            modeAllowedDomains
                .map(::normalizeDomainToken)
                .filter { it.isNotEmpty() }
        )
        val allowedDomains = allowedDomainSet.toList().sorted()

        val stateUnchanged =
            categories == lastAppliedCategories &&
                domains == lastAppliedDomains &&
                blockedPackages == lastAppliedBlockedPackages &&
                allowedDomains == lastAppliedAllowedDomains

        val hasIncomingVersion = incomingVersion != null && incomingVersion > 0L
        if (!hasIncomingVersion && lastEffectivePolicyVersion > 0L) {
            recordPolicyApplySkip(
                source = source,
                version = incomingVersion,
                reason = "missing_version_after_initial_apply"
            )
            return
        }

        val versionRegressedOrDuplicate =
            hasIncomingVersion && incomingVersion!! <= lastEffectivePolicyVersion
        if (versionRegressedOrDuplicate) {
            if (!stateUnchanged) {
                Log.w(
                    TAG,
                    "Ignoring effective_policy with non-increasing version " +
                        "version=${incomingVersion ?: 0L} last=$lastEffectivePolicyVersion source=$source " +
                        "(state changed)"
                )
            }
            recordPolicyApplySkip(
                source = source,
                version = incomingVersion,
                reason = if (stateUnchanged) {
                    "version_not_new_and_state_unchanged"
                } else {
                    "version_not_new_state_changed_ignored"
                }
            )
            return
        }

        if (stateUnchanged) {
            if (incomingVersion != null && incomingVersion > 0L) {
                lastEffectivePolicyVersion = incomingVersion
            }
            recordPolicyApplySuccess(source, incomingVersion)
            writePolicyApplyAck(
                childId = childId,
                parentId = snapshotParentId,
                appliedVersion = incomingVersion,
                applyStatus = "applied",
                errorMessage = null,
                applyLatencyMs = 0,
                servicesExpectedCount = blockedServices.size
            )
            return
        }

        val applyStartedAt = System.currentTimeMillis()
        Log.d(
            TAG,
            "Applying effective_policy from $source " +
                "childId=$childId version=${incomingVersion ?: 0L} " +
                "manualMode=${activeManualMode ?: "none"} pauseActive=$pauseActive " +
                "cats=${categories.size} domains=${domains.size} packages=${blockedPackages.size} " +
                "allowed=${allowedDomains.size}"
        )
        applyFilterRules(
            categories = categories,
            domains = domains,
            temporaryAllowedDomains = allowedDomains,
            blockedPackages = blockedPackages
        )
        if (incomingVersion != null && incomingVersion > 0L) {
            lastEffectivePolicyVersion = incomingVersion
        }
        recordPolicyApplySuccess(source, incomingVersion)
        writePolicyApplyAck(
            childId = childId,
            parentId = snapshotParentId,
            appliedVersion = incomingVersion,
            applyStatus = "applied",
            errorMessage = null,
            applyLatencyMs = (System.currentTimeMillis() - applyStartedAt).toInt(),
            servicesExpectedCount = blockedServices.size
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
        if (!serviceRunning) {
            return
        }
        val version = appliedVersion ?: return
        if (version <= 0L) {
            return
        }
        val normalizedChildId = childId.trim()
        val normalizedParentId = parentId.trim()
        if (normalizedChildId.isEmpty() || normalizedParentId.isEmpty()) {
            return
        }
        val cachedDeviceId = cachedPolicyAckDeviceId?.trim().orEmpty()
        if (cachedDeviceId.isNotEmpty()) {
            writePolicyApplyAckToDocument(
                childId = normalizedChildId,
                parentId = normalizedParentId,
                deviceId = cachedDeviceId,
                appliedVersion = version,
                applyStatus = applyStatus,
                errorMessage = errorMessage,
                applyLatencyMs = applyLatencyMs,
                servicesExpectedCount = servicesExpectedCount
            )
            return
        }

        FirebaseFirestore.getInstance()
            .collection("children")
            .document(normalizedChildId)
            .collection("devices")
            .limit(1)
            .get()
            .addOnSuccessListener { snapshot ->
                val resolvedDeviceId = snapshot.documents
                    .firstOrNull()
                    ?.id
                    ?.trim()
                    .orEmpty()
                if (resolvedDeviceId.isEmpty()) {
                    Log.w(TAG, "Skipping policy_apply_acks write: no registered child device doc")
                    return@addOnSuccessListener
                }
                cachedPolicyAckDeviceId = resolvedDeviceId
                writePolicyApplyAckToDocument(
                    childId = normalizedChildId,
                    parentId = normalizedParentId,
                    deviceId = resolvedDeviceId,
                    appliedVersion = version,
                    applyStatus = applyStatus,
                    errorMessage = errorMessage,
                    applyLatencyMs = applyLatencyMs,
                    servicesExpectedCount = servicesExpectedCount
                )
            }
            .addOnFailureListener { error ->
                Log.w(TAG, "Failed resolving child device ID for policy_apply_acks", error)
            }
    }

    private fun writePolicyApplyAckToDocument(
        childId: String,
        parentId: String,
        deviceId: String,
        appliedVersion: Long,
        applyStatus: String,
        errorMessage: String?,
        applyLatencyMs: Int?,
        servicesExpectedCount: Int
    ) {
        val payload = hashMapOf<String, Any?>(
            "parentId" to parentId,
            "childId" to childId,
            "deviceId" to deviceId,
            "appliedVersion" to appliedVersion,
            "appliedAt" to Timestamp.now(),
            "vpnRunning" to serviceRunning,
            "appliedBlockedDomainsCount" to lastAppliedDomains.size,
            "appliedBlockedPackagesCount" to lastAppliedBlockedPackages.size,
            "applyLatencyMs" to applyLatencyMs,
            "usageAccessGranted" to hasUsageStatsPermissionForGuard(),
            "ruleCounts" to hashMapOf<String, Any>(
                "categoriesExpected" to lastAppliedCategories.size,
                "domainsExpected" to lastAppliedDomains.size,
                "servicesExpected" to servicesExpectedCount,
                "packagesExpected" to lastAppliedBlockedPackages.size,
                "categoriesCached" to blockedCategoryCount,
                "domainsCached" to blockedDomainCount
            ),
            "applyStatus" to applyStatus,
            "error" to errorMessage,
            "updatedAt" to Timestamp.now()
        )

        FirebaseFirestore.getInstance()
            .collection("children")
            .document(childId)
            .collection("policy_apply_acks")
            .document(deviceId)
            .set(payload)
            .addOnFailureListener { error ->
                Log.w(TAG, "policy_apply_acks write failed", error)
            }
    }

    private fun maybeWriteWebDiagnosticsTelemetry(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force) {
            if (!serviceRunning) {
                return
            }
            if (now - lastWebDiagnosticsWriteEpochMs < WEB_DIAGNOSTICS_WRITE_MIN_INTERVAL_MS) {
                return
            }
            if (webDiagnosticsWriteQueued) {
                return
            }
        }

        webDiagnosticsWriteQueued = true
        webDiagnosticsExecutor.execute {
            try {
                writeWebDiagnosticsTelemetry(force = force)
            } catch (error: Exception) {
                Log.w(TAG, "vpn_diagnostics telemetry write failed", error)
            } finally {
                webDiagnosticsWriteQueued = false
            }
        }
    }

    private fun writeWebDiagnosticsTelemetry(force: Boolean) {
        val config = try {
            vpnPreferencesStore.loadConfig()
        } catch (_: Exception) {
            return
        }
        val childId = config.childId?.trim().orEmpty()
        val parentId = config.parentId?.trim().orEmpty()
        if (childId.isEmpty() || parentId.isEmpty()) {
            return
        }
        if (!maybeBootstrapPolicySyncAuth("web_diagnostics_write")) {
            return
        }
        ensurePolicySyncDeviceRegistration()

        val now = System.currentTimeMillis()
        val usageAccessGranted = hasUsageStatsPermissionForGuard()
        val foregroundPackage = if (usageAccessGranted) {
            currentForegroundPackageFromUsageStats()?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        } else {
            null
        }
        val browserForeground = isLikelyBrowserPackage(foregroundPackage)
        val privateDnsActive = isPrivateDnsActive()
        val protectionActive = (
            lastAppliedCategories.isNotEmpty() ||
                lastAppliedDomains.isNotEmpty() ||
                blockedCategoryCount > 0 ||
                blockedDomainCount > 0
            )

        val recentLogs = getRecentQueryLogs(limit = 60)
        val recentQueriesForLog = getRecentQueryLogs(limit = 100)
            .mapNotNull { queryLogMapForDiagnostics(it) }
        val recentCutoff = now - WEB_DIAGNOSTICS_RECENT_DNS_WINDOW_MS
        var recentVpnDnsQueriesInWindow = 0
        for (entry in recentLogs) {
            val timestamp = (entry["timestampEpochMs"] as? Number)?.toLong() ?: continue
            if (timestamp >= recentCutoff) {
                recentVpnDnsQueriesInWindow += 1
            }
        }

        val vpnWarmupActive = startedAtEpochMs?.let { now - it < 8_000L } == true
        val bypassReasonCode = when {
            !serviceRunning -> "vpn_not_running"
            privateDnsActive -> "private_dns_active"
            !protectionActive -> "protection_rules_inactive"
            !usageAccessGranted -> "usage_access_unavailable"
            !browserForeground -> "browser_not_foreground"
            vpnWarmupActive -> "vpn_warmup"
            recentVpnDnsQueriesInWindow > 0 -> "ok"
            else -> "no_recent_vpn_dns_while_browser_foreground"
        }
        val likelyDnsBypass = bypassReasonCode == "no_recent_vpn_dns_while_browser_foreground"
        if (likelyDnsBypass) {
            lastBrowserDnsBypassSignalEpochMs = now
            lastBrowserDnsBypassSignalReasonCode = bypassReasonCode
            lastBrowserDnsBypassSignalForegroundPackage = foregroundPackage
        }

        val lastDnsQuery = recentLogs.firstOrNull()
        val lastBlockedDnsQuery = recentLogs.firstOrNull { it["blocked"] == true }
        val signature = buildString {
            append(serviceRunning)
            append('|')
            append(privateDnsMode)
            append('|')
            append(privateDnsActive)
            append('|')
            append(protectionActive)
            append('|')
            append(usageAccessGranted)
            append('|')
            append(foregroundPackage ?: "")
            append('|')
            append(recentVpnDnsQueriesInWindow)
            append('|')
            append((lastDnsQuery?.get("timestampEpochMs") as? Number)?.toLong() ?: 0L)
            append('|')
            append((lastDnsQuery?.get("reasonCode") as? String) ?: "")
            append('|')
            append((lastBlockedDnsQuery?.get("timestampEpochMs") as? Number)?.toLong() ?: 0L)
            append('|')
            append((lastBlockedDnsQuery?.get("reasonCode") as? String) ?: "")
            append('|')
            append(bypassReasonCode)
            append('|')
            append(likelyDnsBypass)
        }
        if (!force && signature == lastWebDiagnosticsSignature) {
            return
        }

        val payload = hashMapOf<String, Any?>(
            "parentId" to parentId,
            "childId" to childId,
            "deviceId" to cachedPolicyAckDeviceId,
            "vpnRunning" to serviceRunning,
            "privateDnsMode" to privateDnsMode?.takeIf { it.isNotBlank() },
            "privateDnsActive" to privateDnsActive,
            "protectionActive" to protectionActive,
            "usageAccessGranted" to usageAccessGranted,
            "foregroundPackage" to foregroundPackage?.takeIf { it.isNotBlank() },
            "browserForeground" to browserForeground,
            "recentVpnDnsQueriesInWindow" to recentVpnDnsQueriesInWindow,
            "likelyDnsBypass" to likelyDnsBypass,
            "bypassReasonCode" to bypassReasonCode,
            "lastBypassSignalAtEpochMs" to (
                if (lastBrowserDnsBypassSignalEpochMs > 0L) {
                    lastBrowserDnsBypassSignalEpochMs
                } else {
                    null
                }
                ),
            "lastBypassSignalReasonCode" to (
                lastBrowserDnsBypassSignalReasonCode.takeIf { it.isNotBlank() }
                ),
            "lastBypassSignalForegroundPackage" to (
                lastBrowserDnsBypassSignalForegroundPackage?.takeIf { it.isNotBlank() }
                ),
            "packetCounters" to hashMapOf<String, Any>(
                "queriesProcessed" to queriesProcessed.toInt().coerceAtLeast(0),
                "queriesBlocked" to queriesBlocked.toInt().coerceAtLeast(0),
                "queriesAllowed" to queriesAllowed.toInt().coerceAtLeast(0),
                "upstreamFailureCount" to upstreamFailureCount.toInt().coerceAtLeast(0),
                "fallbackQueryCount" to fallbackQueryCount.toInt().coerceAtLeast(0)
            ),
            "lastDnsQuery" to queryLogMapForDiagnostics(lastDnsQuery),
            "lastBlockedDnsQuery" to queryLogMapForDiagnostics(lastBlockedDnsQuery),
            "recentQueries" to recentQueriesForLog,
            "policySync" to hashMapOf<String, Any?>(
                "lastSeenVersion" to (if (lastPolicySnapshotSeenVersion > 0L) lastPolicySnapshotSeenVersion else null),
                "lastAppliedVersion" to (if (lastEffectivePolicyVersion > 0L) lastEffectivePolicyVersion else null),
                "lastSnapshotSeenAtEpochMs" to (
                    if (lastPolicySnapshotSeenAtEpochMs > 0L) lastPolicySnapshotSeenAtEpochMs else null
                    ),
                "lastApplyAttemptAtEpochMs" to (
                    if (lastPolicyApplyAttemptAtEpochMs > 0L) lastPolicyApplyAttemptAtEpochMs else null
                    ),
                "lastApplySuccessAtEpochMs" to (
                    if (lastPolicyApplySuccessAtEpochMs > 0L) lastPolicyApplySuccessAtEpochMs else null
                    ),
                "lastSource" to lastPolicyApplySource.takeIf { it.isNotBlank() },
                "lastSnapshotSource" to lastPolicySnapshotSource.takeIf { it.isNotBlank() },
                "lastSkipReason" to lastPolicyApplySkipReason.takeIf { it.isNotBlank() },
                "lastError" to lastPolicyApplyErrorMessage.takeIf { it.isNotBlank() },
                "listenerAttached" to (effectivePolicyListener != null),
                "pollingActive" to effectivePolicyPollRunning,
                "lastListenerEventAtEpochMs" to (
                    if (lastPolicyListenerEventAtEpochMs > 0L) lastPolicyListenerEventAtEpochMs else null
                    ),
                "lastPollSuccessAtEpochMs" to (
                    if (lastPolicyPollSuccessAtEpochMs > 0L) lastPolicyPollSuccessAtEpochMs else null
                    )
            ),
            "updatedAt" to Timestamp.now()
        )

        FirebaseFirestore.getInstance()
            .collection("children")
            .document(childId)
            .collection("vpn_diagnostics")
            .document("current")
            .set(payload)
            .addOnFailureListener { error ->
                Log.w(TAG, "vpn_diagnostics/current write failed", error)
            }

        lastWebDiagnosticsWriteEpochMs = now
        lastWebDiagnosticsSignature = signature
        Log.d(
            TAG,
            "[web-diag] childId=$childId bypass=$likelyDnsBypass reason=$bypassReasonCode " +
                "fg=${foregroundPackage ?: "unknown"} recentDns=$recentVpnDnsQueriesInWindow " +
                "lastDns=${lastDnsQuery?.get("domain") ?: "-"} " +
                "lastDnsReason=${lastDnsQuery?.get("reasonCode") ?: "-"}"
        )
    }

    private fun queryLogMapForDiagnostics(entry: Map<String, Any>?): Map<String, Any>? {
        entry ?: return null
        val domain = (entry["domain"] as? String)?.trim().orEmpty()
        if (domain.isEmpty()) {
            return null
        }
        val output = hashMapOf<String, Any>(
            "domain" to domain,
            "blocked" to (entry["blocked"] == true),
            "timestampEpochMs" to ((entry["timestampEpochMs"] as? Number)?.toLong() ?: 0L),
            "reasonCode" to ((entry["reasonCode"] as? String)?.trim().takeUnless { it.isNullOrEmpty() }
                ?: if (entry["blocked"] == true) "blocked_unknown" else "allow_unknown")
        )
        val matchedRule = (entry["matchedRule"] as? String)?.trim().orEmpty()
        if (matchedRule.isNotEmpty()) {
            output["matchedRule"] = matchedRule
        }
        return output
    }

    private fun isLikelyBrowserPackage(packageName: String?): Boolean {
        val normalized = packageName?.trim()?.lowercase().orEmpty()
        if (normalized.isEmpty()) {
            return false
        }
        if (WEB_DIAGNOSTIC_BROWSER_PACKAGES.contains(normalized)) {
            return true
        }
        return normalized.contains("browser") ||
            normalized.contains("chrome") ||
            normalized.contains("firefox")
    }

    private fun enforceBlockedForegroundAppIfNeeded() {
        if (!serviceRunning) {
            return
        }
        if (lastAppliedBlockedPackages.isEmpty()) {
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

        val foregroundPackage = currentForegroundPackageFromUsageStats() ?: return
        val normalizedForeground = foregroundPackage.trim().lowercase()
        if (normalizedForeground.isEmpty()) {
            return
        }
        if (normalizedForeground == packageName ||
            normalizedForeground.startsWith("$packageName.") ||
            normalizedForeground == "com.android.systemui"
        ) {
            return
        }
        if (!lastAppliedBlockedPackages.contains(normalizedForeground)) {
            return
        }

        val now = System.currentTimeMillis()
        if (now - lastAppGuardActionEpochMs < APP_GUARD_COOLDOWN_MS) {
            return
        }
        lastAppGuardActionEpochMs = now
        Log.w(TAG, "Blocked foreground app detected package=$normalizedForeground")
        showProtectionAttentionNotification(
            "Blocked app detected. Open TrustBridge to review active limits."
        )
        try {
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(homeIntent)
        } catch (error: Exception) {
            Log.w(TAG, "Failed to move blocked app to home screen", error)
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
        val startTime = endTime - 120_000L
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
        return latestPackage
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
                categories = normalizedCategories.toSet(),
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
        categories: Set<String>,
        domains: Set<String>,
        allowedDomains: Set<String>
    ): List<String> {
        val normalizedCategories = categories
            .map(::normalizeCategoryToken)
            .toSet()
        val normalizedDomains = domains
            .map(::normalizeDomainToken)
            .filter { it.isNotEmpty() }
            .toSet()
        val normalizedAllowedDomains = allowedDomains
            .map(::normalizeDomainToken)
            .filter { it.isNotEmpty() }
            .toSet()

        val blockedPackages = linkedSetOf<String>()
        for (rule in APP_BLOCK_RULES) {
            val categoryHit = rule.categories.any { normalizedCategories.contains(it) }
            val domainHit = rule.domainMarkers.any { marker ->
                matchesDomainRule(marker, normalizedDomains)
            }
            if (!categoryHit && !domainHit) {
                continue
            }

            val explicitlyAllowed = rule.domainMarkers.any { marker ->
                matchesDomainRule(marker, normalizedAllowedDomains)
            }
            if (explicitlyAllowed) {
                continue
            }
            blockedPackages.addAll(rule.packages)
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
        scheduleUnexpectedStopRecovery(reason = "onDestroy")
        stopVpn(stopService = false, markDisabled = false)
        policyApplyExecutor.shutdownNow()
        webDiagnosticsExecutor.shutdownNow()
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

    private data class AppBlockRule(
        val categories: Set<String>,
        val domainMarkers: Set<String>,
        val packages: Set<String>
    )
}
