package com.navee.trustbridge.vpn

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import java.util.concurrent.ExecutorService

internal class VpnTelemetryManager(
    private val host: Host
) {
    internal interface Host {
        val tag: String
        val serviceRunning: Boolean
        val vpnPreferencesStore: VpnPreferencesStore
        val webDiagnosticsExecutor: ExecutorService
        val appDomainUsageExecutor: ExecutorService
        val packageManager: PackageManager
        val appPackageName: String
        val privateDnsMode: String
        val privateDnsActive: Boolean
        val startedAtEpochMs: Long?

        val queriesProcessed: Long
        val queriesBlocked: Long
        val queriesAllowed: Long
        val upstreamFailureCount: Long
        val fallbackQueryCount: Long
        val blockedCategoryCount: Int
        val blockedDomainCount: Int
        val lastAppliedCategories: List<String>
        val lastAppliedDomains: List<String>
        val lastAppliedBlockedPackages: List<String>

        val lastPolicySnapshotSeenVersion: Long
        val lastEffectivePolicyVersion: Long
        val lastPolicySnapshotSeenAtEpochMs: Long
        val lastPolicyApplyAttemptAtEpochMs: Long
        val lastPolicyApplySuccessAtEpochMs: Long
        val lastPolicyApplySource: String
        val lastPolicySnapshotSource: String
        val lastPolicyApplySkipReason: String
        val lastPolicyApplyErrorMessage: String
        val effectivePolicyListenerAttached: Boolean
        val effectivePolicyPollRunning: Boolean
        val lastPolicyListenerEventAtEpochMs: Long
        val lastPolicyPollSuccessAtEpochMs: Long

        var cachedPolicyAckDeviceId: String?
        var lastWebDiagnosticsWriteEpochMs: Long
        var webDiagnosticsWriteQueued: Boolean
        var lastWebDiagnosticsSignature: String
        var lastBrowserDnsBypassSignalEpochMs: Long
        var lastBrowserDnsBypassSignalReasonCode: String
        var lastBrowserDnsBypassSignalForegroundPackage: String?

        var appDomainUsageWriteQueued: Boolean
        var appDomainUsageDirty: Boolean
        var lastAppDomainUsageWriteEpochMs: Long
        var appInventoryWriteQueued: Boolean
        var lastAppInventoryWriteEpochMs: Long
        var lastAppInventoryHash: String

        val appDomainUsageByPackage: MutableMap<String, LinkedHashMap<String, Long>>

        fun maybeBootstrapPolicySyncAuth(reason: String): Boolean
        fun ensurePolicySyncDeviceRegistration()
        fun hasUsageStatsPermissionForGuard(): Boolean
        fun currentForegroundPackageFromUsageStats(): String?
        fun getRecentQueryLogs(limit: Int): List<Map<String, Any>>
        fun isParentControllablePackage(packageName: String): Boolean
        fun hasInternetPermission(packageName: String): Boolean
    }

    companion object {
        private const val WEB_DIAGNOSTICS_WRITE_MIN_INTERVAL_MS = 5_000L
        private const val WEB_DIAGNOSTICS_RECENT_DNS_WINDOW_MS = 20_000L
        private const val APP_DOMAIN_USAGE_WRITE_MIN_INTERVAL_MS = 5_000L
        private const val APP_INVENTORY_WRITE_MIN_INTERVAL_MS = 2 * 60 * 1000L
        private const val APP_DOMAIN_USAGE_MAX_PACKAGES = 180
        private const val APP_DOMAIN_USAGE_MAX_DOMAINS_PER_PACKAGE = 120
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
        private val INFRASTRUCTURE_PACKAGES = setOf(
            "com.android.vending",
            "com.google.android.gms",
            "com.google.android.gsf",
            "com.google.android.googlequicksearchbox",
            "com.google.android.ext.services",
            "com.google.android.ext.shared",
            "com.android.providers.downloads"
        )
    }

    fun maybeWriteWebDiagnosticsTelemetry(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force) {
            if (!host.serviceRunning) {
                return
            }
            if (now - host.lastWebDiagnosticsWriteEpochMs < WEB_DIAGNOSTICS_WRITE_MIN_INTERVAL_MS) {
                return
            }
            if (host.webDiagnosticsWriteQueued) {
                return
            }
        }

        host.webDiagnosticsWriteQueued = true
        host.webDiagnosticsExecutor.execute {
            try {
                writeWebDiagnosticsTelemetry(force = force)
            } catch (error: Exception) {
                Log.w(host.tag, "vpn_diagnostics telemetry write failed", error)
            } finally {
                host.webDiagnosticsWriteQueued = false
            }
        }
    }

    fun scheduleObservedAppDomainWrite(force: Boolean = false) {
        if (!host.serviceRunning && !force) {
            return
        }
        val now = System.currentTimeMillis()
        if (!force &&
            (host.appDomainUsageWriteQueued ||
                !host.appDomainUsageDirty ||
                now - host.lastAppDomainUsageWriteEpochMs < APP_DOMAIN_USAGE_WRITE_MIN_INTERVAL_MS)
        ) {
            return
        }
        host.appDomainUsageWriteQueued = true
        host.appDomainUsageExecutor.execute {
            try {
                writeObservedAppDomainUsage(force = force)
            } catch (error: Exception) {
                Log.w(host.tag, "app_domain_usage write failed", error)
            } finally {
                host.appDomainUsageWriteQueued = false
            }
        }
    }

    fun scheduleInstalledAppInventoryWrite(force: Boolean = false) {
        if (!host.serviceRunning && !force) {
            return
        }
        val now = System.currentTimeMillis()
        if (!force &&
            (host.appInventoryWriteQueued ||
                now - host.lastAppInventoryWriteEpochMs < APP_INVENTORY_WRITE_MIN_INTERVAL_MS)
        ) {
            return
        }
        host.appInventoryWriteQueued = true
        host.appDomainUsageExecutor.execute {
            try {
                writeInstalledAppInventory(force = force)
            } catch (error: Exception) {
                Log.w(host.tag, "app_inventory write failed", error)
            } finally {
                host.appInventoryWriteQueued = false
            }
        }
    }

    private fun writeWebDiagnosticsTelemetry(force: Boolean) {
        val config = try {
            host.vpnPreferencesStore.loadConfig()
        } catch (_: Exception) {
            return
        }
        val childId = config.childId?.trim().orEmpty()
        val parentId = config.parentId?.trim().orEmpty()
        if (childId.isEmpty() || parentId.isEmpty()) {
            return
        }
        if (!host.maybeBootstrapPolicySyncAuth("web_diagnostics_write")) {
            return
        }
        host.ensurePolicySyncDeviceRegistration()

        val now = System.currentTimeMillis()
        val usageAccessGranted = host.hasUsageStatsPermissionForGuard()
        val foregroundPackage = if (usageAccessGranted) {
            host.currentForegroundPackageFromUsageStats()
                ?.trim()
                ?.lowercase()
                ?.takeIf { it.isNotEmpty() }
        } else {
            null
        }
        val browserForeground = isLikelyBrowserPackage(foregroundPackage)
        val privateDnsActive = host.privateDnsActive
        val protectionActive = (
            host.lastAppliedCategories.isNotEmpty() ||
                host.lastAppliedDomains.isNotEmpty() ||
                host.blockedCategoryCount > 0 ||
                host.blockedDomainCount > 0
            )

        val recentLogs = host.getRecentQueryLogs(limit = 60)
        val recentQueriesForLog = host.getRecentQueryLogs(limit = 100)
            .mapNotNull { queryLogMapForDiagnostics(it) }
        val recentCutoff = now - WEB_DIAGNOSTICS_RECENT_DNS_WINDOW_MS
        var recentVpnDnsQueriesInWindow = 0
        for (entry in recentLogs) {
            val timestamp = (entry["timestampEpochMs"] as? Number)?.toLong() ?: continue
            if (timestamp >= recentCutoff) {
                recentVpnDnsQueriesInWindow += 1
            }
        }

        val vpnWarmupActive = host.startedAtEpochMs?.let { now - it < 8_000L } == true
        val bypassReasonCode = when {
            !host.serviceRunning -> "vpn_not_running"
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
            host.lastBrowserDnsBypassSignalEpochMs = now
            host.lastBrowserDnsBypassSignalReasonCode = bypassReasonCode
            host.lastBrowserDnsBypassSignalForegroundPackage = foregroundPackage
        }

        val lastDnsQuery = recentLogs.firstOrNull()
        val lastBlockedDnsQuery = recentLogs.firstOrNull { it["blocked"] == true }
        val signature = buildString {
            append(host.serviceRunning)
            append('|')
            append(host.privateDnsMode)
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
        if (!force && signature == host.lastWebDiagnosticsSignature) {
            return
        }

        val payload = hashMapOf<String, Any?>(
            "parentId" to parentId,
            "childId" to childId,
            "deviceId" to host.cachedPolicyAckDeviceId,
            "vpnRunning" to host.serviceRunning,
            "privateDnsMode" to host.privateDnsMode.takeIf { it.isNotBlank() },
            "privateDnsActive" to privateDnsActive,
            "protectionActive" to protectionActive,
            "usageAccessGranted" to usageAccessGranted,
            "foregroundPackage" to foregroundPackage?.takeIf { it.isNotBlank() },
            "browserForeground" to browserForeground,
            "recentVpnDnsQueriesInWindow" to recentVpnDnsQueriesInWindow,
            "likelyDnsBypass" to likelyDnsBypass,
            "bypassReasonCode" to bypassReasonCode,
            "lastBypassSignalAtEpochMs" to (
                if (host.lastBrowserDnsBypassSignalEpochMs > 0L) {
                    host.lastBrowserDnsBypassSignalEpochMs
                } else {
                    null
                }
                ),
            "lastBypassSignalReasonCode" to (
                host.lastBrowserDnsBypassSignalReasonCode.takeIf { it.isNotBlank() }
                ),
            "lastBypassSignalForegroundPackage" to (
                host.lastBrowserDnsBypassSignalForegroundPackage?.takeIf { it.isNotBlank() }
                ),
            "packetCounters" to hashMapOf<String, Any>(
                "queriesProcessed" to host.queriesProcessed.toInt().coerceAtLeast(0),
                "queriesBlocked" to host.queriesBlocked.toInt().coerceAtLeast(0),
                "queriesAllowed" to host.queriesAllowed.toInt().coerceAtLeast(0),
                "upstreamFailureCount" to host.upstreamFailureCount.toInt().coerceAtLeast(0),
                "fallbackQueryCount" to host.fallbackQueryCount.toInt().coerceAtLeast(0)
            ),
            "lastDnsQuery" to queryLogMapForDiagnostics(lastDnsQuery),
            "lastBlockedDnsQuery" to queryLogMapForDiagnostics(lastBlockedDnsQuery),
            "recentQueries" to recentQueriesForLog,
            "policySync" to hashMapOf<String, Any?>(
                "lastSeenVersion" to (
                    if (host.lastPolicySnapshotSeenVersion > 0L) host.lastPolicySnapshotSeenVersion else null
                    ),
                "lastAppliedVersion" to (
                    if (host.lastEffectivePolicyVersion > 0L) host.lastEffectivePolicyVersion else null
                    ),
                "lastSnapshotSeenAtEpochMs" to (
                    if (host.lastPolicySnapshotSeenAtEpochMs > 0L) host.lastPolicySnapshotSeenAtEpochMs else null
                    ),
                "lastApplyAttemptAtEpochMs" to (
                    if (host.lastPolicyApplyAttemptAtEpochMs > 0L) host.lastPolicyApplyAttemptAtEpochMs else null
                    ),
                "lastApplySuccessAtEpochMs" to (
                    if (host.lastPolicyApplySuccessAtEpochMs > 0L) host.lastPolicyApplySuccessAtEpochMs else null
                    ),
                "lastSource" to host.lastPolicyApplySource.takeIf { it.isNotBlank() },
                "lastSnapshotSource" to host.lastPolicySnapshotSource.takeIf { it.isNotBlank() },
                "lastSkipReason" to host.lastPolicyApplySkipReason.takeIf { it.isNotBlank() },
                "lastError" to host.lastPolicyApplyErrorMessage.takeIf { it.isNotBlank() },
                "listenerAttached" to host.effectivePolicyListenerAttached,
                "pollingActive" to host.effectivePolicyPollRunning,
                "lastListenerEventAtEpochMs" to (
                    if (host.lastPolicyListenerEventAtEpochMs > 0L) host.lastPolicyListenerEventAtEpochMs else null
                    ),
                "lastPollSuccessAtEpochMs" to (
                    if (host.lastPolicyPollSuccessAtEpochMs > 0L) host.lastPolicyPollSuccessAtEpochMs else null
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
                Log.w(host.tag, "vpn_diagnostics/current write failed", error)
            }

        writeProtectionStatusSnapshot(
            parentId = parentId,
            childId = childId,
            nowEpochMs = now
        )

        host.lastWebDiagnosticsWriteEpochMs = now
        host.lastWebDiagnosticsSignature = signature
        Log.d(
            host.tag,
            "[web-diag] childId=$childId bypass=$likelyDnsBypass reason=$bypassReasonCode " +
                "fg=${foregroundPackage ?: "unknown"} recentDns=$recentVpnDnsQueriesInWindow " +
                "lastDns=${lastDnsQuery?.get("domain") ?: "-"} " +
                "lastDnsReason=${lastDnsQuery?.get("reasonCode") ?: "-"}"
        )
    }

    private fun writeProtectionStatusSnapshot(
        parentId: String,
        childId: String,
        nowEpochMs: Long
    ) {
        val deviceId = resolvePolicySyncDeviceId()
        if (deviceId.isEmpty()) {
            return
        }

        val payload = hashMapOf<String, Any?>(
            "deviceId" to deviceId,
            "parentId" to parentId,
            "childId" to childId,
            "lastSeen" to Timestamp.now(),
            "lastSeenEpochMs" to nowEpochMs,
            "vpnActive" to host.serviceRunning,
            "queriesProcessed" to host.queriesProcessed.toInt().coerceAtLeast(0),
            "queriesBlocked" to host.queriesBlocked.toInt().coerceAtLeast(0),
            "queriesAllowed" to host.queriesAllowed.toInt().coerceAtLeast(0),
            "upstreamFailureCount" to host.upstreamFailureCount.toInt().coerceAtLeast(0),
            "fallbackQueryCount" to host.fallbackQueryCount.toInt().coerceAtLeast(0),
            "blockedCategoryCount" to host.blockedCategoryCount,
            "blockedDomainCount" to host.blockedDomainCount,
            "vpnStatusUpdatedAt" to Timestamp.now(),
            "updatedAt" to Timestamp.now()
        )

        val firestore = FirebaseFirestore.getInstance()
        firestore.collection("devices")
            .document(deviceId)
            .set(payload, SetOptions.merge())
            .addOnFailureListener { error ->
                Log.w(host.tag, "devices/$deviceId status write failed", error)
            }

        firestore.collection("children")
            .document(childId)
            .collection("devices")
            .document(deviceId)
            .set(payload, SetOptions.merge())
            .addOnFailureListener { error ->
                Log.w(host.tag, "children/$childId/devices/$deviceId status write failed", error)
            }
    }

    private fun resolvePolicySyncDeviceId(): String {
        val cached = host.cachedPolicyAckDeviceId?.trim().orEmpty()
        if (cached.isNotEmpty()) {
            return cached
        }
        val authUid = try {
            FirebaseAuth.getInstance().currentUser?.uid?.trim().orEmpty()
        } catch (_: Exception) {
            ""
        }
        if (authUid.isNotEmpty()) {
            host.cachedPolicyAckDeviceId = authUid
        }
        return authUid
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

    private fun writeObservedAppDomainUsage(force: Boolean) {
        if (!force && !host.serviceRunning) {
            return
        }
        if (!force && !host.appDomainUsageDirty) {
            return
        }
        val config = try {
            host.vpnPreferencesStore.loadConfig()
        } catch (_: Exception) {
            return
        }
        val childId = config.childId?.trim().orEmpty()
        val parentId = config.parentId?.trim().orEmpty()
        if (childId.isEmpty() || parentId.isEmpty()) {
            Log.d(host.tag, "app_domain_usage write skipped: missing parent/child ids")
            return
        }
        if (!host.maybeBootstrapPolicySyncAuth("app_domain_usage_write")) {
            Log.d(host.tag, "app_domain_usage write skipped: auth bootstrap unavailable")
            return
        }
        host.ensurePolicySyncDeviceRegistration()

        val snapshot = synchronized(host.appDomainUsageByPackage) {
            host.appDomainUsageByPackage.mapValues { entry ->
                entry.value.toMap()
            }
        }
        if (snapshot.isEmpty()) {
            Log.d(host.tag, "app_domain_usage write skipped: snapshot empty")
            return
        }

        val packageEntries = snapshot.entries
            .map { (packageName, domains) ->
                val sortedDomains = domains.entries
                    .sortedByDescending { it.value }
                    .map { it.key }
                hashMapOf<String, Any>(
                    "packageName" to packageName,
                    "domains" to sortedDomains,
                    "domainCount" to sortedDomains.size,
                    "lastSeenAtEpochMs" to (domains.values.maxOrNull() ?: System.currentTimeMillis())
                )
            }
            .sortedBy { (it["packageName"] as? String).orEmpty() }

        val packageDomainMap = hashMapOf<String, Any>()
        for ((packageName, domains) in snapshot) {
            val sortedDomains = domains.entries
                .sortedByDescending { it.value }
                .map { it.key }
            packageDomainMap[packageName] = sortedDomains
        }

        val payload = hashMapOf<String, Any?>(
            "parentId" to parentId,
            "childId" to childId,
            "deviceId" to host.cachedPolicyAckDeviceId,
            "packages" to packageEntries,
            "packageDomains" to packageDomainMap,
            "updatedAt" to Timestamp.now()
        )

        FirebaseFirestore.getInstance()
            .collection("children")
            .document(childId)
            .collection("app_domain_usage")
            .document("current")
            .set(payload)
            .addOnSuccessListener {
                host.appDomainUsageDirty = false
                host.lastAppDomainUsageWriteEpochMs = System.currentTimeMillis()
                Log.d(
                    host.tag,
                    "app_domain_usage/current write ok childId=$childId packages=${snapshot.size}"
                )
            }
            .addOnFailureListener { error ->
                Log.w(host.tag, "app_domain_usage/current write failed", error)
            }
    }

    private fun writeInstalledAppInventory(force: Boolean) {
        if (!force && !host.serviceRunning) {
            return
        }
        val config = try {
            host.vpnPreferencesStore.loadConfig()
        } catch (_: Exception) {
            return
        }
        val childId = config.childId?.trim().orEmpty()
        val parentId = config.parentId?.trim().orEmpty()
        if (childId.isEmpty() || parentId.isEmpty()) {
            return
        }
        if (!host.maybeBootstrapPolicySyncAuth("app_inventory_write")) {
            return
        }
        host.ensurePolicySyncDeviceRegistration()

        val nowEpochMs = System.currentTimeMillis()
        val appEntries = collectParentControllableInstalledApps(nowEpochMs)
        val inventoryHash = appEntries.joinToString(separator = "\n") { entry ->
            val pkg = (entry["packageName"] as? String).orEmpty()
            val name = (entry["appName"] as? String).orEmpty().lowercase()
            val launchable = if (entry["isLaunchable"] == true) "1" else "0"
            "$pkg|$name|$launchable"
        }
        if (!force &&
            inventoryHash == host.lastAppInventoryHash &&
            nowEpochMs - host.lastAppInventoryWriteEpochMs < APP_INVENTORY_WRITE_MIN_INTERVAL_MS
        ) {
            return
        }

        val deviceId = host.cachedPolicyAckDeviceId?.trim().orEmpty().ifEmpty {
            try {
                FirebaseAuth.getInstance().currentUser?.uid?.trim().orEmpty()
            } catch (_: Exception) {
                ""
            }
        }

        val payload = hashMapOf<String, Any>(
            "version" to nowEpochMs,
            "hash" to inventoryHash,
            "capturedAt" to FieldValue.serverTimestamp(),
            "apps" to appEntries,
            "inventoryStatus" to hashMapOf<String, Any>(
                "source" to "vpn_service",
                "appCount" to appEntries.size,
                "updatedAtEpochMs" to nowEpochMs
            )
        )
        if (deviceId.isNotEmpty()) {
            payload["deviceId"] = deviceId
        }

        host.lastAppInventoryWriteEpochMs = nowEpochMs
        host.lastAppInventoryHash = inventoryHash

        FirebaseFirestore.getInstance()
            .collection("children")
            .document(childId)
            .collection("app_inventory")
            .document("current")
            .set(payload, SetOptions.merge())
            .addOnSuccessListener {
                Log.d(host.tag, "app_inventory/current write ok childId=$childId apps=${appEntries.size}")
            }
            .addOnFailureListener { error ->
                host.lastAppInventoryWriteEpochMs = 0L
                host.lastAppInventoryHash = ""
                Log.w(host.tag, "app_inventory/current write failed childId=$childId", error)
            }
    }

    private fun collectParentControllableInstalledApps(nowEpochMs: Long): List<HashMap<String, Any>> {
        val results = mutableListOf<HashMap<String, Any>>()
        val seen = linkedSetOf<String>()
        val installedApps = try {
            host.packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
        } catch (_: Exception) {
            emptyList<ApplicationInfo>()
        }
        for (appInfo in installedApps) {
            val packageName = appInfo.packageName?.trim()?.lowercase().orEmpty()
            if (packageName.isEmpty() || packageName == host.appPackageName) {
                continue
            }
            if (!seen.add(packageName)) {
                continue
            }
            if (packageName in INFRASTRUCTURE_PACKAGES ||
                packageName.startsWith("com.vivo.") ||
                packageName.startsWith("com.bbk.")
            ) {
                continue
            }
            if (!host.isParentControllablePackage(packageName)) {
                continue
            }
            if (!host.hasInternetPermission(packageName)) {
                continue
            }
            val appName = try {
                host.packageManager.getApplicationLabel(appInfo)?.toString()?.trim().orEmpty()
            } catch (_: Exception) {
                ""
            }.ifEmpty { packageName }
            val launchIntent = try {
                host.packageManager.getLaunchIntentForPackage(packageName)
            } catch (_: Exception) {
                null
            }
            val packageInfo = try {
                host.packageManager.getPackageInfo(packageName, 0)
            } catch (_: Exception) {
                null
            }
            results.add(
                hashMapOf<String, Any>(
                    "packageName" to packageName,
                    "appName" to appName,
                    "isSystemApp" to false,
                    "isLaunchable" to (launchIntent != null),
                    "firstSeenAtEpochMs" to (packageInfo?.firstInstallTime ?: nowEpochMs),
                    "lastSeenAtEpochMs" to (packageInfo?.lastUpdateTime ?: nowEpochMs)
                )
            )
        }
        return results.sortedBy { (it["appName"] as? String)?.lowercase().orEmpty() }
    }
}
