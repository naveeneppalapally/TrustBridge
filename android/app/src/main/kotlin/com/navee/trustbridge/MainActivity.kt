package com.navee.trustbridge

import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.Intent
import android.content.ComponentName
import android.app.usage.UsageStatsManager
import android.app.usage.UsageEvents
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.os.UserManager
import android.net.Uri
import android.provider.Settings
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Base64
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.io.ByteArrayOutputStream
import com.navee.trustbridge.vpn.BlocklistStore
import com.navee.trustbridge.vpn.DnsFilterEngine
import com.navee.trustbridge.vpn.DnsVpnService
import com.navee.trustbridge.vpn.VpnEventDispatcher
import com.navee.trustbridge.vpn.VpnPreferencesStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private data class UsageSnapshot(
        val packageName: String,
        val durationMs: Long,
        val lastTimeUsedMs: Long
    )

    companion object {
        private const val VPN_PERMISSION_REQUEST_CODE = 44123
        private const val DEVICE_ADMIN_PERMISSION_REQUEST_CODE = 44124
        private const val OEM_PREFS = "trustbridge_oem_prefs"
        private const val KEY_VIVO_AUTOSTART_PROMPTED = "vivo_autostart_prompted"
        private val INFRASTRUCTURE_PACKAGES: Set<String> = setOf(
            "com.android.vending",
            "com.google.android.gms",
            "com.google.android.gsf",
            "com.google.android.googlequicksearchbox",
            "com.google.android.ext.services",
            "com.google.android.ext.shared",
            "com.android.providers.downloads"
        )
        private val CHANNEL_NAMES = listOf(
            "trustbridge/vpn",
            "com.navee.trustbridge/vpn"
        )
        private const val DEVICE_ADMIN_CHANNEL = "com.navee.trustbridge/device_admin"
        private const val DEVICE_OWNER_SETUP_COMMAND =
            "adb shell dpm set-device-owner com.navee.trustbridge/.TrustBridgeAdminReceiver"
        private const val AUTO_RESTORE_MIN_INTERVAL_MS = 8_000L
        private val USAGE_CHANNEL_NAMES = listOf(
            "com.navee.trustbridge/usage_stats"
        )
    }

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingDeviceAdminResult: MethodChannel.Result? = null
    private var primaryVpnChannel: MethodChannel? = null
    private var lastAutoRestoreAttemptElapsedMs: Long = 0L
    private val blocklistStore: BlocklistStore by lazy {
        BlocklistStore(applicationContext)
    }
    private val vpnPreferencesStore: VpnPreferencesStore by lazy {
        VpnPreferencesStore(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        CHANNEL_NAMES.forEach { channelName ->
            val channel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                channelName
            )
            channel.setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
            }
            if (channelName == "com.navee.trustbridge/vpn") {
                primaryVpnChannel = channel
                VpnEventDispatcher.attach(channel)
            }
        }

        USAGE_CHANNEL_NAMES.forEach { channelName ->
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                channelName
            ).setMethodCallHandler { call, result ->
                handleUsageMethodCall(call, result)
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_ADMIN_CHANNEL
        ).setMethodCallHandler { call, result ->
            handleDeviceAdminMethodCall(call, result)
        }
    }

    override fun onResume() {
        super.onResume()
        maybeAutoRestoreVpnOnForegroundEntry()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(
                DnsVpnService.statusSnapshot(permissionGranted = hasVpnPermission())
            )

            "hasVpnPermission" -> result.success(hasVpnPermission())

            "requestPermission", "requestVpnPermission" -> requestVpnPermission(result)

            "startVpn" -> {
                if (!hasVpnPermission()) {
                    result.error(
                        "permission_required",
                        "VPN permission is required before starting.",
                        null
                    )
                    return
                }

                val blockedCategories =
                    call.argument<List<String>>("blockedCategories") ?: emptyList()
                val blockedDomains =
                    call.argument<List<String>>("blockedDomains") ?: emptyList()
                val temporaryAllowedDomains =
                    call.argument<List<String>>("temporaryAllowedDomains") ?: emptyList()
                val upstreamDns = call.argument<String>("upstreamDns")
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                persistPolicyContext(call)

                val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
                    action = DnsVpnService.ACTION_START
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_BLOCKED_CATEGORIES,
                        ArrayList(blockedCategories)
                    )
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_BLOCKED_DOMAINS,
                        ArrayList(blockedDomains)
                    )
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_TEMP_ALLOWED_DOMAINS,
                        ArrayList(temporaryAllowedDomains)
                    )
                    if (upstreamDns != null) {
                        putExtra(DnsVpnService.EXTRA_UPSTREAM_DNS, upstreamDns)
                    }
                }
                startServiceCompat(serviceIntent)
                result.success(true)
            }

            "restartVpn" -> {
                if (!hasVpnPermission()) {
                    result.error(
                        "permission_required",
                        "VPN permission is required before restarting.",
                        null
                    )
                    return
                }

                val blockedCategories =
                    call.argument<List<String>>("blockedCategories")
                val blockedDomains =
                    call.argument<List<String>>("blockedDomains")
                val temporaryAllowedDomains =
                    call.argument<List<String>>("temporaryAllowedDomains")
                val upstreamDns = call.argument<String>("upstreamDns")
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                val usePersistedRules = call.argument<Boolean>("usePersistedRules") == true
                persistPolicyContext(call)

                val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
                    action = DnsVpnService.ACTION_RESTART
                    if (!usePersistedRules || blockedCategories != null) {
                        putStringArrayListExtra(
                            DnsVpnService.EXTRA_BLOCKED_CATEGORIES,
                            ArrayList(blockedCategories ?: emptyList())
                        )
                    }
                    if (!usePersistedRules || blockedDomains != null) {
                        putStringArrayListExtra(
                            DnsVpnService.EXTRA_BLOCKED_DOMAINS,
                            ArrayList(blockedDomains ?: emptyList())
                        )
                    }
                    if (!usePersistedRules || temporaryAllowedDomains != null) {
                        putStringArrayListExtra(
                            DnsVpnService.EXTRA_TEMP_ALLOWED_DOMAINS,
                            ArrayList(temporaryAllowedDomains ?: emptyList())
                        )
                    }
                    if (upstreamDns != null) {
                        putExtra(DnsVpnService.EXTRA_UPSTREAM_DNS, upstreamDns)
                    }
                }
                startServiceCompat(serviceIntent)
                result.success(true)
            }

            "stopVpn" -> {
                val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
                    action = DnsVpnService.ACTION_STOP
                }
                startServiceCompat(serviceIntent)
                result.success(true)
            }

            "isVpnRunning" -> result.success(DnsVpnService.isRunning)

            "isIgnoringBatteryOptimizations" -> {
                result.success(isIgnoringBatteryOptimizations())
            }

            "openBatteryOptimizationSettings" -> {
                result.success(openBatteryOptimizationSettings())
            }

            "openVpnSettings" -> {
                result.success(openVpnSettings())
            }

            "openPrivateDnsSettings" -> {
                result.success(openPrivateDnsSettings())
            }

            "getRecentDnsQueries" -> {
                val limit = call.argument<Int>("limit") ?: 100
                result.success(DnsVpnService.getRecentQueryLogs(limit = limit))
            }

            "clearDnsQueryLogs" -> {
                DnsVpnService.clearRecentQueryLogs()
                if (DnsVpnService.isRunning) {
                    val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
                        action = DnsVpnService.ACTION_CLEAR_QUERY_LOGS
                    }
                    startServiceCompat(serviceIntent)
                }
                result.success(true)
            }

            "flushDnsCache" -> {
                if (!DnsVpnService.isRunning) {
                    result.success(false)
                    return
                }
                val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
                    action = DnsVpnService.ACTION_FLUSH_DNS_CACHE
                }
                startServiceCompat(serviceIntent)
                maybeHandleFirstVpnStartOemFlows()
                result.success(true)
            }

            "getRuleCacheSnapshot" -> {
                val sampleLimit = call.argument<Int>("sampleLimit") ?: 5
                val metadata = blocklistStore.loadMetadata(sampleLimit = sampleLimit)
                result.success(
                    mapOf(
                        "categoryCount" to metadata.categoryCount,
                        "domainCount" to metadata.domainCount,
                        "lastUpdatedAtEpochMs" to metadata.lastUpdatedAtEpochMs,
                        "sampleCategories" to metadata.sampleCategories,
                        "sampleDomains" to metadata.sampleDomains
                    )
                )
            }

            "clearRuleCache" -> {
                blocklistStore.clearRules()
                if (DnsVpnService.isRunning) {
                    val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
                        action = DnsVpnService.ACTION_UPDATE_RULES
                        putStringArrayListExtra(
                            DnsVpnService.EXTRA_BLOCKED_CATEGORIES,
                            arrayListOf()
                        )
                        putStringArrayListExtra(
                            DnsVpnService.EXTRA_BLOCKED_DOMAINS,
                            arrayListOf()
                        )
                        putStringArrayListExtra(
                            DnsVpnService.EXTRA_TEMP_ALLOWED_DOMAINS,
                            arrayListOf()
                        )
                    }
                    startServiceCompat(serviceIntent)
                }
                result.success(true)
            }

            "evaluateDomainPolicy" -> {
                val domainInput = call.argument<String>("domain")?.trim().orEmpty()
                if (domainInput.isBlank()) {
                    result.error(
                        "invalid_domain",
                        "A non-empty domain value is required.",
                        null
                    )
                    return
                }

                val evaluator = DnsFilterEngine(this)
                try {
                    val evaluation = evaluator.evaluateDomain(domainInput)
                    result.success(
                        mapOf(
                            "inputDomain" to evaluation.inputDomain,
                            "normalizedDomain" to evaluation.normalizedDomain,
                            "blocked" to evaluation.blocked,
                            "matchedRule" to evaluation.matchedRule
                        )
                    )
                } finally {
                    evaluator.close()
                }
            }

            "updateFilterRules" -> {
                val blockedCategories =
                    call.argument<List<String>>("blockedCategories") ?: emptyList()
                val blockedDomains =
                    call.argument<List<String>>("blockedDomains") ?: emptyList()
                val temporaryAllowedDomains =
                    call.argument<List<String>>("temporaryAllowedDomains") ?: emptyList()
                val parentId = call.argument<String>("parentId")
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                val childId = call.argument<String>("childId")
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                persistPolicyContext(call)

                val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
                    action = DnsVpnService.ACTION_UPDATE_RULES
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_BLOCKED_CATEGORIES,
                        ArrayList(blockedCategories)
                    )
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_BLOCKED_DOMAINS,
                        ArrayList(blockedDomains)
                    )
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_TEMP_ALLOWED_DOMAINS,
                        ArrayList(temporaryAllowedDomains)
                    )
                    if (parentId != null) {
                        putExtra(DnsVpnService.EXTRA_PARENT_ID, parentId)
                    }
                    if (childId != null) {
                        putExtra(DnsVpnService.EXTRA_CHILD_ID, childId)
                    }
                }
                startServiceCompat(serviceIntent)
                result.success(true)
            }

            "savePolicyContext" -> {
                persistPolicyContext(call)
                result.success(true)
            }

            "setUpstreamDns" -> {
                val upstreamDns = call.argument<String>("upstreamDns")
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }

                if (DnsVpnService.isRunning) {
                    val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
                        action = DnsVpnService.ACTION_SET_UPSTREAM_DNS
                        if (upstreamDns != null) {
                            putExtra(DnsVpnService.EXTRA_UPSTREAM_DNS, upstreamDns)
                        }
                    }
                    startServiceCompat(serviceIntent)
                } else {
                    val config = vpnPreferencesStore.loadConfig()
                    vpnPreferencesStore.saveRules(
                        categories = config.blockedCategories,
                        domains = config.blockedDomains,
                        temporaryAllowedDomains = config.temporaryAllowedDomains,
                        blockedPackages = config.blockedPackages,
                        upstreamDns = upstreamDns
                    )
                }

                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    private fun persistPolicyContext(call: MethodCall) {
        val parentId = call.argument<String>("parentId")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        val childId = call.argument<String>("childId")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        if (parentId != null || childId != null) {
            vpnPreferencesStore.savePolicyContext(parentId = parentId, childId = childId)
        }
    }

    private fun handleDeviceAdminMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isDeviceAdminActive" -> result.success(isDeviceAdminActive())

            "isDeviceOwnerActive" -> result.success(isDeviceOwnerActive())

            "requestDeviceAdmin" -> requestDeviceAdmin(result)

            "removeDeviceAdmin" -> {
                removeDeviceAdmin()
                result.success(true)
            }

            "getPrivateDnsMode" -> result.success(getPrivateDnsMode())

            "getDeviceOwnerSetupCommand" -> result.success(DEVICE_OWNER_SETUP_COMMAND)

            "getMaximumProtectionStatus" -> result.success(buildMaximumProtectionStatus())

            "applyMaximumProtectionPolicies" -> result.success(applyMaximumProtectionPolicies())

            else -> result.notImplemented()
        }
    }

    private fun maybeAutoRestoreVpnOnForegroundEntry() {
        if (DnsVpnService.isRunning) {
            return
        }
        if (!hasVpnPermission()) {
            return
        }
        val config = try {
            vpnPreferencesStore.loadConfig()
        } catch (_: Exception) {
            return
        }
        if (!config.enabled) {
            return
        }
        val nowElapsed = SystemClock.elapsedRealtime()
        if (nowElapsed - lastAutoRestoreAttemptElapsedMs < AUTO_RESTORE_MIN_INTERVAL_MS) {
            return
        }
        lastAutoRestoreAttemptElapsedMs = nowElapsed
        val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
            action = DnsVpnService.ACTION_START
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
            putStringArrayListExtra(
                DnsVpnService.EXTRA_BLOCKED_PACKAGES,
                ArrayList(config.blockedPackages)
            )
            putExtra(DnsVpnService.EXTRA_UPSTREAM_DNS, config.upstreamDns)
        }
        startServiceCompat(serviceIntent)
    }

    private fun handleUsageMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasUsageStatsPermission" -> result.success(hasUsageStatsPermission())
            "openUsageStatsSettings" -> result.success(openUsageStatsSettings())
            "getUsageStats" -> {
                val pastDays = call.argument<Int>("pastDays") ?: 7
                result.success(getUsageStats(pastDays))
            }
            "getCurrentForegroundPackage" -> {
                result.success(getCurrentForegroundPackage())
            }
            "getInstalledLaunchableApps" -> {
                result.success(getInstalledLaunchableApps())
            }
            else -> result.notImplemented()
        }
    }

    private fun isDeviceAdminActive(): Boolean {
        val policyManager = getSystemService(DevicePolicyManager::class.java) ?: return false
        return policyManager.isAdminActive(deviceAdminComponent())
    }

    private fun isDeviceOwnerActive(): Boolean {
        val policyManager = getSystemService(DevicePolicyManager::class.java) ?: return false
        return try {
            policyManager.isDeviceOwnerApp(packageName)
        } catch (_: Exception) {
            false
        }
    }

    private fun buildMaximumProtectionStatus(): Map<String, Any> {
        val policyManager = getSystemService(DevicePolicyManager::class.java)
        val userManager = getSystemService(UserManager::class.java)
        val adminActive = isDeviceAdminActive()
        val ownerActive = isDeviceOwnerActive()

        val alwaysOnPackage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && policyManager != null) {
            try {
                policyManager.getAlwaysOnVpnPackage(deviceAdminComponent())
            } catch (_: Exception) {
                null
            }
        } else {
            null
        }

        val lockdownEnabled =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                policyManager != null &&
                adminActive
            ) {
                try {
                    policyManager.isAlwaysOnVpnLockdownEnabled(deviceAdminComponent())
                } catch (_: Exception) {
                    false
                }
            } else {
                false
            }

        val uninstallBlocked = if (policyManager != null && adminActive) {
            try {
                policyManager.isUninstallBlocked(deviceAdminComponent(), packageName)
            } catch (_: Exception) {
                false
            }
        } else {
            false
        }

        val appsControlRestricted = if (userManager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                userManager.hasUserRestriction(UserManager.DISALLOW_APPS_CONTROL)
            } catch (_: Exception) {
                false
            }
        } else {
            false
        }

        return mapOf(
            "vpnRunning" to DnsVpnService.isRunning,
            "deviceAdminActive" to adminActive,
            "deviceOwnerActive" to ownerActive,
            "alwaysOnVpnPackage" to (alwaysOnPackage ?: ""),
            "alwaysOnVpnEnabled" to (alwaysOnPackage == packageName),
            "lockdownEnabled" to lockdownEnabled,
            "uninstallBlocked" to uninstallBlocked,
            "appsControlRestricted" to appsControlRestricted,
            "setupCommand" to DEVICE_OWNER_SETUP_COMMAND
        )
    }

    private fun applyMaximumProtectionPolicies(): Map<String, Any> {
        val base = buildMaximumProtectionStatus().toMutableMap()
        if (!isDeviceOwnerActive()) {
            base["success"] = false
            base["message"] = "Device Owner not active on this phone."
            return base
        }

        val policyManager = getSystemService(DevicePolicyManager::class.java)
        if (policyManager == null) {
            base["success"] = false
            base["message"] = "Device policy service unavailable."
            return base
        }

        val admin = deviceAdminComponent()
        val errors = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                policyManager.setAlwaysOnVpnPackage(admin, packageName, true)
            } catch (error: Exception) {
                errors.add("always_on_vpn:${error.javaClass.simpleName}")
            }
        } else {
            errors.add("always_on_vpn:unsupported_sdk")
        }

        try {
            policyManager.setUninstallBlocked(admin, packageName, true)
        } catch (error: Exception) {
            errors.add("uninstall_block:${error.javaClass.simpleName}")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                policyManager.addUserRestriction(admin, UserManager.DISALLOW_APPS_CONTROL)
                policyManager.addUserRestriction(admin, UserManager.DISALLOW_UNINSTALL_APPS)
            } catch (error: Exception) {
                errors.add("user_restrictions:${error.javaClass.simpleName}")
            }
        }

        val refreshed = buildMaximumProtectionStatus().toMutableMap()
        refreshed["success"] = errors.isEmpty()
        refreshed["message"] = if (errors.isEmpty()) {
            "Maximum protection policies applied."
        } else {
            "Applied with warnings: ${errors.joinToString(", ")}"
        }
        refreshed["errors"] = errors
        return refreshed
    }

    private fun requestDeviceAdmin(result: MethodChannel.Result) {
        if (isDeviceAdminActive()) {
            result.success(true)
            return
        }
        if (pendingDeviceAdminResult != null) {
            result.error(
                "request_in_progress",
                "Device admin request already in progress.",
                null
            )
            return
        }

        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, deviceAdminComponent())
            putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "This prevents your child from uninstalling TrustBridge."
            )
        }
        pendingDeviceAdminResult = result
        @Suppress("DEPRECATION")
        startActivityForResult(intent, DEVICE_ADMIN_PERMISSION_REQUEST_CODE)
    }

    private fun removeDeviceAdmin() {
        val policyManager = getSystemService(DevicePolicyManager::class.java) ?: return
        val componentName = deviceAdminComponent()
        if (policyManager.isAdminActive(componentName)) {
            policyManager.removeActiveAdmin(componentName)
        }
    }

    private fun getPrivateDnsMode(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return ""
        }
        return try {
            Settings.Global.getString(contentResolver, "private_dns_mode") ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun deviceAdminComponent(): ComponentName {
        return ComponentName(this, TrustBridgeAdminReceiver::class.java)
    }

    private fun hasUsageStatsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return false
        }
        val appOpsManager = getSystemService(AppOpsManager::class.java) ?: return false
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOpsManager.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOpsManager.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        }
        if (mode == AppOpsManager.MODE_ALLOWED) {
            return true
        }

        // Some OEM builds report MODE_DEFAULT even when usage access works.
        return try {
            val usageStatsManager = getSystemService(UsageStatsManager::class.java) ?: return false
            val endTime = System.currentTimeMillis()
            val startTime = endTime - 24L * 60L * 60L * 1000L
            val hasStats = !usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startTime,
                endTime
            ).isNullOrEmpty()
            val hasEvents = usageStatsManager.queryEvents(startTime, endTime).hasNextEvent()
            hasStats || hasEvents
        } catch (_: Exception) {
            false
        }
    }

    private fun openUsageStatsSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun getUsageStats(pastDays: Int): List<Map<String, Any>> {
        if (!hasUsageStatsPermission()) {
            return emptyList()
        }

        val usageStatsManager = getSystemService(UsageStatsManager::class.java)
            ?: return emptyList()
        val safePastDays = pastDays.coerceIn(1, 30)
        val endTime = System.currentTimeMillis()
        val dayMillis = 24L * 60L * 60L * 1000L
        val todayStart = dayStartEpochMs(endTime)

        val aggregates = mutableMapOf<String, MutableMap<String, Any>>()
        val reportableCache = mutableMapOf<String, Boolean>()
        val appNameCache = mutableMapOf<String, String>()
        for (offset in 0 until safePastDays) {
            val dayStart = todayStart - (offset * dayMillis)
            val dayEnd = minOf(dayStart + dayMillis, endTime)
            val dayKey = formatDateKey(dayStart)
            val eventSnapshots = collectEventUsageSnapshots(
                usageStatsManager = usageStatsManager,
                dayStart = dayStart,
                dayEnd = dayEnd
            )
            val daySnapshots = if (eventSnapshots.isNotEmpty()) {
                // OEMs like Vivo can over-report aggregate totals for explicit
                // ranges. Foreground events track real app transitions more
                // reliably, so prefer them whenever they exist.
                eventSnapshots
            } else {
                collectAggregatedUsageSnapshots(
                    usageStatsManager = usageStatsManager,
                    dayStart = dayStart,
                    dayEnd = dayEnd
                )
            }
            if (daySnapshots.isEmpty()) {
                continue
            }

            daySnapshots.values.forEach { snapshot ->
                val packageName = snapshot.packageName
                val foregroundMs = snapshot.durationMs
                if (packageName.isBlank() || foregroundMs <= 0L) {
                    return@forEach
                }
                val normalizedPackage = packageName.trim()
                val isReportable = reportableCache.getOrPut(normalizedPackage) {
                    isUsageReportableApp(normalizedPackage)
                }
                if (!isReportable) {
                    return@forEach
                }
                val appName = appNameCache.getOrPut(normalizedPackage) {
                    try {
                        val appInfo = packageManager.getApplicationInfo(normalizedPackage, 0)
                        packageManager.getApplicationLabel(appInfo).toString()
                    } catch (_: Exception) {
                        normalizedPackage
                    }
                }

                val item = aggregates.getOrPut(normalizedPackage) {
                    mutableMapOf(
                        "packageName" to normalizedPackage,
                        "appName" to appName,
                        "totalForegroundTimeMs" to 0L,
                        "lastTimeUsedEpochMs" to 0L,
                        "dailyUsageMs" to mutableMapOf<String, Long>()
                    )
                }

                val previousTotal = (item["totalForegroundTimeMs"] as? Long) ?: 0L
                item["totalForegroundTimeMs"] = previousTotal + foregroundMs

                val previousLastUsed = (item["lastTimeUsedEpochMs"] as? Long) ?: 0L
                item["lastTimeUsedEpochMs"] = maxOf(previousLastUsed, snapshot.lastTimeUsedMs)

                val dailyMap = item["dailyUsageMs"] as MutableMap<String, Long>
                val previousDayTotal = dailyMap[dayKey] ?: 0L
                dailyMap[dayKey] = previousDayTotal + foregroundMs
            }
        }

        return aggregates.values
            .sortedByDescending { (it["totalForegroundTimeMs"] as? Long) ?: 0L }
            .take(250)
            .map { item ->
                val dailyMap = item["dailyUsageMs"] as MutableMap<String, Long>
                mapOf(
                    "packageName" to (item["packageName"] as String),
                    "appName" to (item["appName"] as String),
                    "totalForegroundTimeMs" to ((item["totalForegroundTimeMs"] as? Long)
                        ?: 0L),
                    "lastTimeUsedEpochMs" to ((item["lastTimeUsedEpochMs"] as? Long)
                        ?: 0L),
                    "dailyUsageMs" to dailyMap
                )
            }
    }

    private fun isUsageReportableApp(packageName: String): Boolean {
        val normalizedPackage = packageName.trim()
        if (normalizedPackage.isEmpty()) {
            return false
        }
        val applicationInfo = try {
            packageManager.getApplicationInfo(normalizedPackage, 0)
        } catch (_: Exception) {
            null
        }
        if (!isParentControllableApp(normalizedPackage, applicationInfo)) {
            return false
        }
        return try {
            packageManager.getLaunchIntentForPackage(normalizedPackage) != null
        } catch (_: Exception) {
            false
        }
    }

    private fun collectAggregatedUsageSnapshots(
        usageStatsManager: UsageStatsManager,
        dayStart: Long,
        dayEnd: Long
    ): Map<String, UsageSnapshot> {
        val snapshots = mutableMapOf<String, UsageSnapshot>()
        val stats = usageStatsManager.queryAndAggregateUsageStats(dayStart, dayEnd)
        if (stats.isNullOrEmpty()) {
            return snapshots
        }
        stats.values.forEach { stat ->
            val packageName = stat.packageName?.trim().orEmpty()
            val durationMs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                stat.totalTimeVisible
            } else {
                stat.totalTimeInForeground
            }
            if (packageName.isEmpty() || durationMs <= 0L) {
                return@forEach
            }
            snapshots[packageName] = UsageSnapshot(
                packageName = packageName,
                durationMs = durationMs,
                lastTimeUsedMs = stat.lastTimeUsed
            )
        }
        return snapshots
    }

    private fun collectEventUsageSnapshots(
        usageStatsManager: UsageStatsManager,
        dayStart: Long,
        dayEnd: Long
    ): Map<String, UsageSnapshot> {
        val usageEvents = usageStatsManager.queryEvents(dayStart, dayEnd)
        val event = UsageEvents.Event()
        val durationsByPackage = mutableMapOf<String, Long>()
        val lastUsedByPackage = mutableMapOf<String, Long>()
        var currentForegroundPackage: String? = null
        var currentForegroundStart = 0L

        fun closeForegroundWindow(closedAt: Long) {
            val packageName = currentForegroundPackage ?: return
            if (currentForegroundStart <= 0L) {
                currentForegroundPackage = null
                currentForegroundStart = 0L
                return
            }
            val clampedEnd = closedAt.coerceAtMost(dayEnd)
            val duration = (clampedEnd - currentForegroundStart).coerceAtLeast(0L)
            if (duration > 0L) {
                durationsByPackage[packageName] =
                    (durationsByPackage[packageName] ?: 0L) + duration
                lastUsedByPackage[packageName] =
                    maxOf(lastUsedByPackage[packageName] ?: 0L, clampedEnd)
            }
            currentForegroundPackage = null
            currentForegroundStart = 0L
        }

        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            val packageName = event.packageName?.trim().orEmpty()
            if (packageName.isEmpty()) {
                continue
            }
            val isForegroundEvent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                event.eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                    event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
            } else {
                event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
            }
            val isBackgroundEvent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                event.eventType == UsageEvents.Event.ACTIVITY_PAUSED ||
                    event.eventType == UsageEvents.Event.MOVE_TO_BACKGROUND
            } else {
                event.eventType == UsageEvents.Event.MOVE_TO_BACKGROUND
            }

            if (isForegroundEvent) {
                if (currentForegroundPackage != null && currentForegroundPackage != packageName) {
                    closeForegroundWindow(event.timeStamp)
                }
                currentForegroundPackage = packageName
                currentForegroundStart = event.timeStamp.coerceAtLeast(dayStart)
                lastUsedByPackage[packageName] =
                    maxOf(lastUsedByPackage[packageName] ?: 0L, event.timeStamp)
                continue
            }

            if (isBackgroundEvent && currentForegroundPackage == packageName) {
                closeForegroundWindow(event.timeStamp)
            }
        }

        closeForegroundWindow(dayEnd)

        return durationsByPackage.mapValues { (packageName, durationMs) ->
            UsageSnapshot(
                packageName = packageName,
                durationMs = durationMs,
                lastTimeUsedMs = lastUsedByPackage[packageName] ?: dayEnd
            )
        }
    }

    private fun dayStartEpochMs(epochMs: Long): Long {
        val calendar = Calendar.getInstance().apply {
            timeInMillis = epochMs
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return calendar.timeInMillis
    }

    private fun getInstalledLaunchableApps(): List<Map<String, Any>> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveInfos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                launcherIntent,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(launcherIntent, PackageManager.MATCH_ALL)
        }

        if (resolveInfos.isNullOrEmpty()) {
            return emptyList()
        }

        val nowEpochMs = System.currentTimeMillis()
        val seenPackages = mutableSetOf<String>()
        val apps = mutableListOf<Map<String, Any>>()
        resolveInfos.forEach { resolveInfo ->
            val packageName = resolveInfo.activityInfo?.packageName?.trim().orEmpty()
            if (packageName.isEmpty()) {
                return@forEach
            }
            if (packageName == this.packageName) {
                return@forEach
            }
            if (!seenPackages.add(packageName)) {
                return@forEach
            }

            val appName = try {
                resolveInfo.loadLabel(packageManager)?.toString()?.trim().orEmpty()
            } catch (_: Exception) {
                ""
            }
            val appIconBase64 = try {
                drawableToPngBase64(resolveInfo.loadIcon(packageManager))
            } catch (_: Exception) {
                null
            }

            val applicationInfo = try {
                packageManager.getApplicationInfo(packageName, 0)
            } catch (_: Exception) {
                null
            }
            if (!isParentControllableApp(packageName, applicationInfo)) {
                return@forEach
            }
            val hasInternetPermission = try {
                packageManager.checkPermission(
                    android.Manifest.permission.INTERNET,
                    packageName
                ) == PackageManager.PERMISSION_GRANTED
            } catch (_: Exception) {
                false
            }
            if (!hasInternetPermission) {
                return@forEach
            }

            val appPayload = mutableMapOf<String, Any>(
                "packageName" to packageName.lowercase(),
                "appName" to (if (appName.isEmpty()) packageName else appName),
                "isSystemApp" to false,
                "hasInternetPermission" to hasInternetPermission,
                "isLaunchable" to true,
                "firstSeenAt" to nowEpochMs,
                "lastSeenAt" to nowEpochMs
            )
            if (!appIconBase64.isNullOrBlank()) {
                appPayload["appIconBase64"] = appIconBase64
            }
            apps.add(appPayload)
        }

        return apps.sortedBy { (it["appName"] as? String)?.lowercase().orEmpty() }
    }

    private fun isParentControllableApp(
        packageName: String,
        applicationInfo: ApplicationInfo?
    ): Boolean {
        val normalizedPackage = packageName.trim().lowercase()
        if (normalizedPackage in INFRASTRUCTURE_PACKAGES ||
            normalizedPackage.startsWith("com.vivo.") ||
            normalizedPackage.startsWith("com.bbk.")
        ) {
            return false
        }
        applicationInfo ?: return false
        val isSystem = applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM != 0
        if (!isSystem) {
            return true
        }
        val isUpdatedSystem =
            applicationInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP != 0
        if (!isUpdatedSystem) {
            return false
        }
        val installer = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(packageName)
            }
        } catch (_: Exception) {
            null
        }?.trim()?.lowercase()
        return installer == "com.android.vending"
    }

    private fun drawableToPngBase64(drawable: Drawable?): String? {
        drawable ?: return null
        return try {
            val bitmap = when (drawable) {
                is BitmapDrawable -> drawable.bitmap
                else -> {
                    val width = drawable.intrinsicWidth.coerceAtLeast(1)
                    val height = drawable.intrinsicHeight.coerceAtLeast(1)
                    Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { canvasBitmap ->
                        val canvas = Canvas(canvasBitmap)
                        drawable.setBounds(0, 0, canvas.width, canvas.height)
                        drawable.draw(canvas)
                    }
                }
            }
            val targetSize = 96
            val normalizedBitmap = if (bitmap.width > targetSize || bitmap.height > targetSize) {
                Bitmap.createScaledBitmap(bitmap, targetSize, targetSize, true)
            } else {
                bitmap
            }
            val output = ByteArrayOutputStream()
            normalizedBitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            val encoded = Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
            output.close()
            encoded
        } catch (_: Exception) {
            null
        }
    }

    private fun getCurrentForegroundPackage(): String? {
        if (!hasUsageStatsPermission()) {
            return null
        }
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
                latestPackage = packageName.trim()
            }
        }
        return latestPackage
    }

    private fun formatDateKey(epochMs: Long): String {
        if (epochMs <= 0L) {
            return "1970-01-01"
        }
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(epochMs))
    }

    private fun hasVpnPermission(): Boolean {
        return android.net.VpnService.prepare(this) == null
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val prepareIntent = android.net.VpnService.prepare(this)
        if (prepareIntent == null) {
            result.success(true)
            return
        }

        if (pendingPermissionResult != null) {
            result.error(
                "permission_in_progress",
                "VPN permission request already in progress.",
                null
            )
            return
        }

        pendingPermissionResult = result
        @Suppress("DEPRECATION")
        startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST_CODE)
    }

    private fun startServiceCompat(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val requiresForegroundStart = when (intent.action) {
                DnsVpnService.ACTION_START,
                DnsVpnService.ACTION_RESTART -> true
                else -> false
            }

            if (requiresForegroundStart) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } else {
            startService(intent)
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        val powerManager = getSystemService(PowerManager::class.java)
        return powerManager?.isIgnoringBatteryOptimizations(packageName) == true
    }

    private fun openBatteryOptimizationSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }

        fun launch(intent: Intent): Boolean {
            return try {
                startActivity(intent.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })
                true
            } catch (_: Exception) {
                false
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return launch(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName")
                )
            )
        }

        val directRequest = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        if (launch(directRequest)) {
            return true
        }

        // Some OEM builds block the direct request intent; fall back to broader settings.
        if (launch(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))) {
            return true
        }

        return launch(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
        )
    }

    private fun openVpnSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_VPN_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openPrivateDnsSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return false
        }
        return try {
            val intent = Intent("android.settings.PRIVATE_DNS_SETTINGS").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun maybeHandleFirstVpnStartOemFlows() {
        if (!isVivoDevice()) {
            return
        }
        val prefs = getSharedPreferences(OEM_PREFS, MODE_PRIVATE)
        if (prefs.getBoolean(KEY_VIVO_AUTOSTART_PROMPTED, false)) {
            return
        }
        val launched = openVivoAutoStartSettings()
        // Mark as prompted to avoid repeatedly stealing focus on every VPN start.
        prefs.edit().putBoolean(KEY_VIVO_AUTOSTART_PROMPTED, true).apply()
        if (!launched) {
            android.util.Log.w(
                "MainActivity",
                "Vivo autostart settings intent unavailable on this build"
            )
        }
    }

    private fun isVivoDevice(): Boolean {
        val manufacturer = Build.MANUFACTURER?.trim()?.lowercase().orEmpty()
        val brand = Build.BRAND?.trim()?.lowercase().orEmpty()
        return manufacturer.contains("vivo") || brand.contains("vivo") || brand.contains("iqoo")
    }

    private fun openVivoAutoStartSettings(): Boolean {
        val intentCandidates = listOf(
            Intent("com.vivo.permissionmanager").apply {
                setPackage("com.vivo.permissionmanager")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
            Intent().apply {
                component = ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                )
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
            Intent().apply {
                component = ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"
                )
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )

        for (intent in intentCandidates) {
            val resolved = intent.resolveActivity(packageManager) ?: continue
            val launched = try {
                intent.setClassName(resolved.packageName, resolved.className)
                startActivity(intent)
                true
            } catch (_: Exception) {
                false
            }
            if (launched) {
                return true
            }
        }
        return false
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_REQUEST_CODE) {
            val granted = hasVpnPermission()
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
            return
        }
        if (requestCode == DEVICE_ADMIN_PERMISSION_REQUEST_CODE) {
            pendingDeviceAdminResult?.success(isDeviceAdminActive())
            pendingDeviceAdminResult = null
        }
    }

    override fun onDestroy() {
        VpnEventDispatcher.detach(primaryVpnChannel)
        primaryVpnChannel = null
        try {
            blocklistStore.close()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }
}
