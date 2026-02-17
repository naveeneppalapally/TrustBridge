package com.navee.trustbridge

import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
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
                        upstreamDns = upstreamDns
                    )
                }

                result.success(true)
            }

            else -> result.notImplemented()
        }
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
        return try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
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
