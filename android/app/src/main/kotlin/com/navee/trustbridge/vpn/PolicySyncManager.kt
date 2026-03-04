package com.navee.trustbridge.vpn

import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.SetOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

internal class PolicySyncManager(
    private val host: Host
) {
    internal interface Host {
        val tag: String
        val serviceRunning: Boolean
        val vpnPreferencesStore: VpnPreferencesStore
        val policyApplyExecutor: ExecutorService

        var policySyncAuthBootstrapInFlight: Boolean
        var lastPolicySyncAuthBootstrapAtEpochMs: Long
        var cachedPolicyAckDeviceId: String?

        var effectivePolicyListener: ListenerRegistration?
        var effectivePolicyChildId: String?
        var effectivePolicyPollRunning: Boolean
        var effectivePolicyPollThread: Thread?
        var effectivePolicyPollChildId: String?
        var effectivePolicyPollParentId: String?

        var lastEffectivePolicyVersion: Long
        var lastPolicySnapshotSeenVersion: Long
        var lastPolicySnapshotSeenAtEpochMs: Long
        var lastPolicySnapshotSource: String
        var lastPolicyApplyAttemptAtEpochMs: Long
        var lastPolicyApplySuccessAtEpochMs: Long
        var lastPolicyApplySource: String
        var lastPolicyApplySkipReason: String
        var lastPolicyApplyErrorMessage: String
        var lastPolicyListenerEventAtEpochMs: Long
        var lastPolicyPollSuccessAtEpochMs: Long
        var lastPolicyTriggerVersion: Long

        fun scheduleInstalledAppInventoryWrite(force: Boolean)
        fun applyEffectivePolicySnapshotFromManager(
            childId: String,
            snapshotData: HashMap<String, Any>,
            incomingVersion: Long?,
            source: String
        )

        fun recordPolicySnapshotSeen(source: String, version: Long?)
        fun recordPolicyApplySkip(source: String, version: Long?, reason: String)
        fun recordPolicyApplyError(source: String, version: Long?, errorMessage: String?)

        fun writePolicyApplyAck(
            childId: String,
            parentId: String,
            appliedVersion: Long?,
            applyStatus: String,
            errorMessage: String?,
            applyLatencyMs: Int?,
            servicesExpectedCount: Int
        )
    }

    companion object {
        private const val EFFECTIVE_POLICY_POLL_INTERVAL_MS = 5_000L
        private const val EFFECTIVE_POLICY_POLL_TIMEOUT_MS = 6_000L
    }

    fun maybeBootstrapPolicySyncAuth(reason: String): Boolean {
        if (firestoreAuthReadyForPolicySync()) {
            return true
        }

        val now = System.currentTimeMillis()
        if (host.policySyncAuthBootstrapInFlight) {
            return false
        }
        if (now - host.lastPolicySyncAuthBootstrapAtEpochMs < 8_000L) {
            return false
        }

        host.lastPolicySyncAuthBootstrapAtEpochMs = now
        host.policySyncAuthBootstrapInFlight = true
        val auth = try {
            FirebaseAuth.getInstance()
        } catch (error: Exception) {
            host.policySyncAuthBootstrapInFlight = false
            Log.w(host.tag, "Policy sync auth bootstrap unavailable", error)
            return false
        }

        Log.w(host.tag, "Policy sync auth missing. Bootstrapping anonymous auth ($reason)")
        auth.signInAnonymously()
            .addOnSuccessListener {
                host.policySyncAuthBootstrapInFlight = false
                Log.i(host.tag, "Policy sync auth bootstrap succeeded ($reason)")
                if (host.serviceRunning) {
                    ensurePolicySyncDeviceRegistration()
                    startEffectivePolicyListenerIfConfigured()
                    host.scheduleInstalledAppInventoryWrite(force = true)
                }
            }
            .addOnFailureListener { error ->
                host.policySyncAuthBootstrapInFlight = false
                Log.w(host.tag, "Policy sync auth bootstrap failed ($reason)", error)
            }
        return false
    }

    fun ensurePolicySyncDeviceRegistration() {
        val authUid = try {
            FirebaseAuth.getInstance().currentUser?.uid?.trim().orEmpty()
        } catch (_: Exception) {
            ""
        }
        if (authUid.isEmpty()) {
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

        host.cachedPolicyAckDeviceId = authUid
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
                        Log.w(
                            host.tag,
                            "Failed to refresh child deviceIds for policy sync auth",
                            error
                        )
                    }
            }
            .addOnFailureListener { error ->
                Log.w(host.tag, "Failed to upsert child device record for policy sync auth", error)
            }
    }

    fun startEffectivePolicyListenerIfConfigured() {
        if (!host.serviceRunning) {
            return
        }
        val config = host.vpnPreferencesStore.loadConfig()
        val childId = config.childId?.trim().orEmpty()
        if (childId.isEmpty()) {
            stopEffectivePolicyListener()
            return
        }
        if (!maybeBootstrapPolicySyncAuth("listener_start")) {
            return
        }
        ensurePolicySyncDeviceRegistration()
        if (host.effectivePolicyListener != null && host.effectivePolicyChildId == childId) {
            startEffectivePolicyPollingFallback(
                childId = childId,
                configuredParentId = config.parentId?.trim().orEmpty()
            )
            return
        }

        stopEffectivePolicyListener()
        host.effectivePolicyChildId = childId
        val configuredParentId = config.parentId?.trim().orEmpty()
        startEffectivePolicyPollingFallback(
            childId = childId,
            configuredParentId = configuredParentId
        )
        host.effectivePolicyListener = FirebaseFirestore.getInstance()
            .collection("children")
            .document(childId)
            .collection("trigger")
            .document("sync")
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.w(host.tag, "policy trigger listener error", error)
                    if (isPolicySyncAuthError(error)) {
                        maybeBootstrapPolicySyncAuth("listener_error")
                    }
                    return@addSnapshotListener
                }
                val data = snapshot?.data ?: return@addSnapshotListener
                if (!host.serviceRunning) {
                    return@addSnapshotListener
                }
                host.lastPolicyListenerEventAtEpochMs = System.currentTimeMillis()

                val snapshotParentId = (data["parentId"] as? String)?.trim().orEmpty()
                if (configuredParentId.isNotEmpty() &&
                    snapshotParentId.isNotEmpty() &&
                    snapshotParentId != configuredParentId
                ) {
                    host.recordPolicyApplySkip(
                        source = "trigger",
                        version = parsePolicyVersion(data["policyVersion"]),
                        reason = "parent_id_mismatch"
                    )
                    return@addSnapshotListener
                }

                val triggerVersion = parsePolicyVersion(data["version"]) ?: 0L
                if (triggerVersion <= 0L || triggerVersion <= host.lastPolicyTriggerVersion) {
                    return@addSnapshotListener
                }
                host.lastPolicyTriggerVersion = triggerVersion
                host.recordPolicySnapshotSeen(
                    source = "trigger",
                    version = parsePolicyVersion(data["policyVersion"])
                )
                host.policyApplyExecutor.execute {
                    try {
                        pollEffectivePolicySnapshotOnce()
                    } catch (error: Exception) {
                        Log.w(host.tag, "Failed to poll effective policy after trigger", error)
                        host.recordPolicyApplyError(
                            source = "trigger",
                            version = parsePolicyVersion(data["policyVersion"]),
                            errorMessage = error.message
                        )
                    }
                }
            }
        Log.d(host.tag, "Started policy trigger listener childId=$childId")
        host.policyApplyExecutor.execute {
            try {
                pollEffectivePolicySnapshotOnce()
            } catch (error: Exception) {
                Log.w(host.tag, "Initial effective policy poll failed", error)
            }
        }
    }

    fun stopEffectivePolicyListener() {
        host.effectivePolicyListener?.remove()
        host.effectivePolicyListener = null
        stopEffectivePolicyPollingFallback()
        host.effectivePolicyChildId = null
        host.lastEffectivePolicyVersion = 0L
        host.lastPolicySnapshotSeenVersion = 0L
        host.lastPolicySnapshotSeenAtEpochMs = 0L
        host.lastPolicySnapshotSource = ""
        host.lastPolicyApplyAttemptAtEpochMs = 0L
        host.lastPolicyApplySuccessAtEpochMs = 0L
        host.lastPolicyApplySource = ""
        host.lastPolicyApplySkipReason = ""
        host.lastPolicyApplyErrorMessage = ""
        host.lastPolicyListenerEventAtEpochMs = 0L
        host.lastPolicyPollSuccessAtEpochMs = 0L
        host.lastPolicyTriggerVersion = 0L
        host.cachedPolicyAckDeviceId = null
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
        if (host.effectivePolicyPollRunning &&
            host.effectivePolicyPollChildId == normalizedChildId &&
            host.effectivePolicyPollParentId == normalizedParentId
        ) {
            return
        }

        stopEffectivePolicyPollingFallback()
        host.effectivePolicyPollRunning = true
        host.effectivePolicyPollChildId = normalizedChildId
        host.effectivePolicyPollParentId = normalizedParentId
        host.effectivePolicyPollThread = thread(name = "dns-vpn-policy-poll") {
            while (host.effectivePolicyPollRunning) {
                try {
                    pollEffectivePolicySnapshotOnce()
                } catch (error: Exception) {
                    Log.w(host.tag, "effective_policy poll error", error)
                }
                try {
                    Thread.sleep(EFFECTIVE_POLICY_POLL_INTERVAL_MS)
                } catch (_: InterruptedException) {
                    break
                }
            }
        }
        Log.d(host.tag, "Started effective_policy polling fallback childId=$normalizedChildId")
    }

    private fun stopEffectivePolicyPollingFallback() {
        host.effectivePolicyPollRunning = false
        host.effectivePolicyPollThread?.interrupt()
        host.effectivePolicyPollThread = null
        host.effectivePolicyPollChildId = null
        host.effectivePolicyPollParentId = null
    }

    fun pollEffectivePolicySnapshotOnce() {
        if (!host.serviceRunning) {
            return
        }
        val childId = host.effectivePolicyPollChildId?.trim().orEmpty()
        if (childId.isEmpty()) {
            return
        }
        val configuredParentId = host.effectivePolicyPollParentId?.trim().orEmpty()

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
            Log.w(host.tag, "effective_policy poll get failed childId=$childId", error)
            if (isPolicySyncAuthError(error)) {
                maybeBootstrapPolicySyncAuth("poll_get")
            }
            return
        }
        val data = snapshot.data ?: return
        if (!host.serviceRunning) {
            return
        }

        val snapshotParentId = (data["parentId"] as? String)?.trim().orEmpty()
        if (configuredParentId.isNotEmpty() &&
            snapshotParentId.isNotEmpty() &&
            snapshotParentId != configuredParentId
        ) {
            host.recordPolicyApplySkip(
                source = "poll",
                version = parsePolicyVersion(data["version"]),
                reason = "parent_id_mismatch"
            )
            return
        }
        val incomingVersion = parsePolicyVersion(data["version"])
        host.lastPolicyPollSuccessAtEpochMs = System.currentTimeMillis()
        host.recordPolicySnapshotSeen("poll", incomingVersion)

        val snapshotData = HashMap(data)
        host.policyApplyExecutor.execute {
            try {
                host.applyEffectivePolicySnapshotFromManager(
                    childId = childId,
                    snapshotData = snapshotData,
                    incomingVersion = incomingVersion,
                    source = "poll"
                )
            } catch (error: Exception) {
                Log.w(host.tag, "Failed to apply effective policy snapshot from poll", error)
                host.recordPolicyApplyError(
                    source = "poll",
                    version = incomingVersion,
                    errorMessage = error.message
                )
                host.writePolicyApplyAck(
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

    private fun firestoreAuthReadyForPolicySync(): Boolean {
        return try {
            FirebaseAuth.getInstance().currentUser != null
        } catch (_: Exception) {
            false
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
}
