package com.navee.trustbridge

import android.app.AppOpsManager
import android.content.Intent
import android.app.usage.UsageStatsManager
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
import com.navee.trustbridge.vpn.VpnPreferencesStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val VPN_PERMISSION_REQUEST_CODE = 44123
        private val CHANNEL_NAMES = listOf(
            "trustbridge/vpn",
            "com.navee.trustbridge/vpn"
        )
        private val USAGE_CHANNEL_NAMES = listOf(
            "com.navee.trustbridge/usage_stats"
        )
    }

    private var pendingPermissionResult: MethodChannel.Result? = null
    private val blocklistStore: BlocklistStore by lazy {
        BlocklistStore(applicationContext)
    }
    private val vpnPreferencesStore: VpnPreferencesStore by lazy {
        VpnPreferencesStore(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        CHANNEL_NAMES.forEach { channelName ->
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                channelName
            ).setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
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
                        upstreamDns = upstreamDns
                    )
                }

                result.success(true)
            }

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
            else -> result.notImplemented()
        }
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
            startForegroundService(intent)
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

        return try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName")
                )
            } else {
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
            }.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
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
        }
    }

    override fun onDestroy() {
        try {
            blocklistStore.close()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }
}
