package com.navee.trustbridge

import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.Intent
import android.content.ComponentName
import android.app.usage.UsageStatsManager
import android.app.usage.UsageEvents
import android.os.Build
import android.os.PowerManager
import android.net.Uri
import android.provider.Settings
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
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
    companion object {
        private const val VPN_PERMISSION_REQUEST_CODE = 44123
        private const val DEVICE_ADMIN_PERMISSION_REQUEST_CODE = 44124
        private val CHANNEL_NAMES = listOf(
            "trustbridge/vpn",
            "com.navee.trustbridge/vpn"
        )
        private const val DEVICE_ADMIN_CHANNEL = "com.navee.trustbridge/device_admin"
        private val USAGE_CHANNEL_NAMES = listOf(
            "com.navee.trustbridge/usage_stats"
        )
    }

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingDeviceAdminResult: MethodChannel.Result? = null
    private var primaryVpnChannel: MethodChannel? = null
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
                    action = DnsVpnService.ACTION_RESTART
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
                }
                startServiceCompat(serviceIntent)
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

            "requestDeviceAdmin" -> requestDeviceAdmin(result)

            "removeDeviceAdmin" -> {
                removeDeviceAdmin()
                result.success(true)
            }

            "getPrivateDnsMode" -> result.success(getPrivateDnsMode())

            else -> result.notImplemented()
        }
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
            else -> result.notImplemented()
        }
    }

    private fun isDeviceAdminActive(): Boolean {
        val policyManager = getSystemService(DevicePolicyManager::class.java) ?: return false
        return policyManager.isAdminActive(deviceAdminComponent())
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
                "Keeps parental protection active on this device."
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
        return mode == AppOpsManager.MODE_ALLOWED
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
        val startTime = endTime - safePastDays * 24L * 60L * 60L * 1000L
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        )

        if (stats.isNullOrEmpty()) {
            return emptyList()
        }

        val aggregates = mutableMapOf<String, MutableMap<String, Any>>()
        stats.forEach { stat ->
            val packageName = stat.packageName ?: return@forEach
            if (stat.totalTimeInForeground <= 0L) {
                return@forEach
            }
            val appName = try {
                val appInfo = packageManager.getApplicationInfo(packageName, 0)
                packageManager.getApplicationLabel(appInfo).toString()
            } catch (_: Exception) {
                packageName
            }

            val item = aggregates.getOrPut(packageName) {
                mutableMapOf(
                    "packageName" to packageName,
                    "appName" to appName,
                    "totalForegroundTimeMs" to 0L,
                    "lastTimeUsedEpochMs" to 0L,
                    "dailyUsageMs" to mutableMapOf<String, Long>()
                )
            }

            val previousTotal = (item["totalForegroundTimeMs"] as? Long) ?: 0L
            item["totalForegroundTimeMs"] = previousTotal + stat.totalTimeInForeground

            val previousLastUsed = (item["lastTimeUsedEpochMs"] as? Long) ?: 0L
            item["lastTimeUsedEpochMs"] = maxOf(previousLastUsed, stat.lastTimeUsed)

            val dailyMap = item["dailyUsageMs"] as MutableMap<String, Long>
            val dayKey = formatDateKey(stat.lastTimeUsed)
            val previousDayTotal = dailyMap[dayKey] ?: 0L
            dailyMap[dayKey] = previousDayTotal + stat.totalTimeInForeground
        }

        return aggregates.values
            .sortedByDescending { (it["totalForegroundTimeMs"] as? Long) ?: 0L }
            .take(30)
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
