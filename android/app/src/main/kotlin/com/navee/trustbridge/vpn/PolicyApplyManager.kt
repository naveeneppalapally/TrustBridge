package com.navee.trustbridge.vpn

import android.util.Log
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import java.util.concurrent.ExecutorService
import org.json.JSONArray
import org.json.JSONObject

internal class PolicyApplyManager(
    private val host: Host
) {
    internal interface Host {
        val tag: String
        val serviceRunning: Boolean
        val policyApplyExecutor: ExecutorService
        val blockAllCategoryToken: String
        val distractingModeCategories: Set<String>

        var lastEffectivePolicyVersion: Long
        var lastPolicySnapshotSeenVersion: Long
        var lastPolicySnapshotSeenAtEpochMs: Long
        var lastPolicySnapshotSource: String
        var lastPolicyApplyAttemptAtEpochMs: Long
        var lastPolicyApplySuccessAtEpochMs: Long
        var lastPolicyApplySource: String
        var lastPolicyApplySkipReason: String
        var lastPolicyApplyErrorMessage: String
        var cachedPolicyAckDeviceId: String?

        val lastAppliedCategories: List<String>
        val lastAppliedDomains: List<String>
        val lastAppliedAllowedDomains: List<String>
        val lastAppliedBlockedPackages: List<String>
        val blockedCategoryCount: Int
        val blockedDomainCount: Int

        fun normalizeCategoryToken(rawCategory: String): String
        fun normalizeDomainToken(rawDomain: String): String

        fun applyFilterRules(
            categories: List<String>,
            domains: List<String>,
            temporaryAllowedDomains: List<String>,
            blockedPackages: List<String>
        )

        fun forceSystemDnsFlush()
        fun hasUsageStatsPermissionForGuard(): Boolean
    }

    fun parsePolicyStringList(raw: Any?): List<String> {
        if (raw !is List<*>) {
            return emptyList()
        }
        return raw.mapNotNull { item ->
            (item as? String)?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        }
    }

    fun parsePolicyVersion(raw: Any?): Long? {
        return when (raw) {
            is Long -> raw
            is Int -> raw.toLong()
            is Double -> raw.toLong()
            is String -> raw.toLongOrNull()
            else -> null
        }
    }

    fun parsePolicyJson(raw: String): HashMap<String, Any>? {
        return try {
            val jsonObject = JSONObject(raw)
            jsonToMap(jsonObject)
        } catch (_: Exception) {
            null
        }
    }

    fun parseEpochMillis(raw: Any?): Long? {
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

    fun applyPolicySnapshotFromRuleInputs(
        parentId: String,
        childId: String,
        categories: List<String>,
        domains: List<String>,
        temporaryAllowedDomains: List<String>,
        blockedPackages: List<String>,
        source: String,
        incomingVersion: Long?
    ) {
        if (!host.serviceRunning) {
            return
        }
        if (childId.trim().isEmpty()) {
            return
        }

        val snapshotData = hashMapOf<String, Any>(
            "childId" to childId.trim(),
            "blockedCategories" to categories,
            "blockedServices" to emptyList<String>(),
            "blockedDomainsResolved" to domains,
            "blockedDomains" to domains,
            "blockedPackagesResolved" to blockedPackages,
            "blockedPackages" to blockedPackages,
            "temporaryAllowedDomainsResolved" to temporaryAllowedDomains,
            "modeBlockedDomainsResolved" to emptyList<String>(),
            "modeAllowedDomainsResolved" to emptyList<String>(),
            "modeBlockedPackagesResolved" to emptyList<String>(),
            "modeAllowedPackagesResolved" to emptyList<String>(),
            "version" to (incomingVersion ?: System.currentTimeMillis())
        )
        if (parentId.trim().isNotEmpty()) {
            snapshotData["parentId"] = parentId.trim()
        }

        host.policyApplyExecutor.execute {
            try {
                applyEffectivePolicySnapshot(
                    childId = childId.trim(),
                    snapshotData = snapshotData,
                    incomingVersion = parsePolicyVersion(snapshotData["version"]),
                    source = source
                )
            } catch (error: Exception) {
                Log.w(host.tag, "Failed applying policy snapshot from $source", error)
            }
        }
    }

    fun recordPolicySnapshotSeen(source: String, version: Long?) {
        val now = System.currentTimeMillis()
        host.lastPolicySnapshotSeenAtEpochMs = now
        host.lastPolicySnapshotSource = source
        if (version != null && version > 0L) {
            host.lastPolicySnapshotSeenVersion = version
        }
    }

    fun recordPolicyApplySkip(source: String, version: Long?, reason: String) {
        host.lastPolicyApplyAttemptAtEpochMs = System.currentTimeMillis()
        host.lastPolicyApplySource = source
        host.lastPolicyApplySkipReason = reason
        host.lastPolicyApplyErrorMessage = ""
        if (version != null && version > 0L) {
            host.lastPolicySnapshotSeenVersion = version
        }
    }

    fun recordPolicyApplyError(source: String, version: Long?, errorMessage: String?) {
        host.lastPolicyApplyAttemptAtEpochMs = System.currentTimeMillis()
        host.lastPolicyApplySource = source
        host.lastPolicyApplySkipReason = ""
        host.lastPolicyApplyErrorMessage = errorMessage?.trim().orEmpty()
        if (version != null && version > 0L) {
            host.lastPolicySnapshotSeenVersion = version
        }
    }

    fun applyEffectivePolicySnapshot(
        childId: String,
        snapshotData: Map<String, Any>,
        incomingVersion: Long?,
        source: String
    ) {
        if (!host.serviceRunning) {
            recordPolicyApplySkip(source, incomingVersion, "service_not_running")
            return
        }
        host.lastPolicyApplyAttemptAtEpochMs = System.currentTimeMillis()
        host.lastPolicyApplySource = source
        host.lastPolicyApplyErrorMessage = ""

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
        val activeModeKey = (snapshotData["activeModeKey"] as? String)
            ?.trim()
            ?.lowercase()
            .orEmpty()
        val nowEpochMs = System.currentTimeMillis()
        val pausedUntilEpochMs = parseEpochMillis(snapshotData["pausedUntil"])
        val pauseActive = pausedUntilEpochMs != null && pausedUntilEpochMs > nowEpochMs
        val activeManualMode = parseActiveManualMode(snapshotData["manualMode"], nowEpochMs)
        val suppressModeForceBlocks = activeModeKey == "free" || activeManualMode == "free"

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
            }).map(host::normalizeDomainToken)
                .filter { it.isNotEmpty() }
        )
        if (suppressModeForceBlocks) {
            domainSet.removeAll(
                modeBlockedDomains
                    .map(host::normalizeDomainToken)
                    .filter { it.isNotEmpty() }
                    .toSet()
            )
        }
        if (!suppressModeForceBlocks) {
            domainSet.addAll(
                modeBlockedDomains
                    .map(host::normalizeDomainToken)
                    .filter { it.isNotEmpty() }
            )
        }
        domainSet.removeAll(
            modeAllowedDomains
                .map(host::normalizeDomainToken)
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
        if (suppressModeForceBlocks) {
            blockedPackageSet.removeAll(
                modeBlockedPackages
                    .map { it.trim().lowercase() }
                    .filter { it.isNotEmpty() }
                    .toSet()
            )
        }
        if (!suppressModeForceBlocks) {
            blockedPackageSet.addAll(
                modeBlockedPackages
                    .map { it.trim().lowercase() }
                    .filter { it.isNotEmpty() }
            )
        }
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
                host.lastAppliedAllowedDomains
                    .map(host::normalizeDomainToken)
                    .filter { it.isNotEmpty() }
            )
        }
        allowedDomainSet.addAll(
            resolvedAllowedDomains
                .map(host::normalizeDomainToken)
                .filter { it.isNotEmpty() }
        )
        allowedDomainSet.addAll(
            modeAllowedDomains
                .map(host::normalizeDomainToken)
                .filter { it.isNotEmpty() }
        )
        val allowedDomains = allowedDomainSet.toList().sorted()

        val stateUnchanged =
            categories == host.lastAppliedCategories &&
                domains == host.lastAppliedDomains &&
                blockedPackages == host.lastAppliedBlockedPackages &&
                allowedDomains == host.lastAppliedAllowedDomains

        val hasIncomingVersion = incomingVersion != null && incomingVersion > 0L
        val versionRegressedOrDuplicate =
            hasIncomingVersion && incomingVersion!! <= host.lastEffectivePolicyVersion
        if (versionRegressedOrDuplicate && stateUnchanged) {
            recordPolicyApplySkip(
                source = source,
                version = incomingVersion,
                reason = "version_not_new_and_state_unchanged"
            )
            return
        }
        if (versionRegressedOrDuplicate && !stateUnchanged) {
            Log.w(
                host.tag,
                "Applying effective_policy with non-increasing version because state changed " +
                    "version=${incomingVersion ?: 0L} last=${host.lastEffectivePolicyVersion} source=$source"
            )
        }

        if (stateUnchanged) {
            if (incomingVersion != null && incomingVersion > host.lastEffectivePolicyVersion) {
                host.lastEffectivePolicyVersion = incomingVersion
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
        Log.i(
            host.tag,
            "Applying effective_policy from $source " +
                "childId=$childId version=${incomingVersion ?: 0L} " +
                "manualMode=${activeManualMode ?: "none"} pauseActive=$pauseActive " +
                "cats=${categories.size} domains=${domains.size} packages=${blockedPackages.size} " +
                "allowed=${allowedDomains.size}"
        )
        host.applyFilterRules(
            categories = categories,
            domains = domains,
            temporaryAllowedDomains = allowedDomains,
            blockedPackages = blockedPackages
        )
        host.forceSystemDnsFlush()
        if (incomingVersion != null && incomingVersion > host.lastEffectivePolicyVersion) {
            host.lastEffectivePolicyVersion = incomingVersion
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

    fun writePolicyApplyAck(
        childId: String,
        parentId: String,
        appliedVersion: Long?,
        applyStatus: String,
        errorMessage: String?,
        applyLatencyMs: Int?,
        servicesExpectedCount: Int
    ) {
        if (!host.serviceRunning) {
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
        val cachedDeviceId = host.cachedPolicyAckDeviceId?.trim().orEmpty()
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
                    Log.w(host.tag, "Skipping policy_apply_acks write: no registered child device doc")
                    return@addOnSuccessListener
                }
                host.cachedPolicyAckDeviceId = resolvedDeviceId
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
                Log.w(host.tag, "Failed resolving child device ID for policy_apply_acks", error)
            }
    }

    private fun jsonToMap(jsonObject: JSONObject): HashMap<String, Any> {
        val output = hashMapOf<String, Any>()
        val keys = jsonObject.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = jsonObject.opt(key) ?: continue
            when (value) {
                JSONObject.NULL -> Unit
                is JSONObject -> output[key] = jsonToMap(value)
                is JSONArray -> output[key] = jsonToList(value)
                else -> output[key] = value
            }
        }
        return output
    }

    private fun jsonToList(jsonArray: JSONArray): List<Any> {
        val output = arrayListOf<Any>()
        for (index in 0 until jsonArray.length()) {
            val value = jsonArray.opt(index) ?: continue
            when (value) {
                JSONObject.NULL -> Unit
                is JSONObject -> output.add(jsonToMap(value))
                is JSONArray -> output.add(jsonToList(value))
                else -> output.add(value)
            }
        }
        return output
    }

    private fun recordPolicyApplySuccess(source: String, version: Long?) {
        val now = System.currentTimeMillis()
        host.lastPolicyApplyAttemptAtEpochMs = now
        host.lastPolicyApplySuccessAtEpochMs = now
        host.lastPolicyApplySource = source
        host.lastPolicyApplySkipReason = ""
        host.lastPolicyApplyErrorMessage = ""
        if (version != null && version > 0L) {
            host.lastPolicySnapshotSeenVersion = version
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
                .map(host::normalizeCategoryToken)
                .filter { it.isNotEmpty() }
        )
        if (pauseActive) {
            effective.add(host.blockAllCategoryToken)
        } else {
            when (activeManualMode) {
                "bedtime" -> effective.add(host.blockAllCategoryToken)
                "homework" -> effective.addAll(host.distractingModeCategories)
                "free" -> {
                    // Explicit free mode only keeps baseline policy categories.
                }
            }
        }
        return effective.toList().sorted()
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
            "vpnRunning" to host.serviceRunning,
            "appliedBlockedDomainsCount" to host.lastAppliedDomains.size,
            "appliedBlockedPackagesCount" to host.lastAppliedBlockedPackages.size,
            "applyLatencyMs" to applyLatencyMs,
            "usageAccessGranted" to host.hasUsageStatsPermissionForGuard(),
            "ruleCounts" to hashMapOf<String, Any>(
                "categoriesExpected" to host.lastAppliedCategories.size,
                "domainsExpected" to host.lastAppliedDomains.size,
                "servicesExpected" to servicesExpectedCount,
                "packagesExpected" to host.lastAppliedBlockedPackages.size,
                "categoriesCached" to host.blockedCategoryCount,
                "domainsCached" to host.blockedDomainCount
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
                Log.w(host.tag, "policy_apply_acks write failed", error)
            }
    }
}
