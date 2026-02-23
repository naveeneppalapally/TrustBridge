package com.navee.trustbridge.vpn

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges native VPN runtime events back to Flutter when an engine is active.
 *
 * The dispatcher is intentionally best-effort:
 * - if no Flutter channel is attached, events are dropped silently
 * - repeated events are throttled to avoid UI spam
 */
object VpnEventDispatcher {
    private const val TAG = "VpnEventDispatcher"
    private const val MIN_REPEAT_WINDOW_MS = 1500L
    private const val MAX_REPEAT_WINDOW_MS = 5000L

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var channel: MethodChannel? = null

    @Volatile
    private var lastDomain: String? = null

    @Volatile
    private var lastEventAtMs: Long = 0L

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    fun detach(channel: MethodChannel?) {
        if (this.channel == channel) {
            this.channel = null
        }
    }

    fun notifyBlockedDomain(
        domain: String,
        modeName: String = "Protection Mode",
        remainingLabel: String? = null
    ) {
        val normalizedDomain = domain.trim().lowercase()
        if (normalizedDomain.isEmpty()) {
            return
        }

        val now = System.currentTimeMillis()
        val lastDomainSnapshot = lastDomain
        val lastEventSnapshot = lastEventAtMs
        val repeatWindow = if (normalizedDomain == lastDomainSnapshot) {
            MIN_REPEAT_WINDOW_MS
        } else {
            MAX_REPEAT_WINDOW_MS
        }
        if (now - lastEventSnapshot < repeatWindow) {
            return
        }

        lastDomain = normalizedDomain
        lastEventAtMs = now

        val payload = hashMapOf<String, Any>(
            "domain" to normalizedDomain,
            "modeName" to modeName.trim().ifEmpty { "Protection Mode" }
        )
        val trimmedRemaining = remainingLabel?.trim()
        if (!trimmedRemaining.isNullOrEmpty()) {
            payload["remainingLabel"] = trimmedRemaining
        }

        mainHandler.post {
            try {
                channel?.invokeMethod("onBlockedDomain", payload)
            } catch (error: Exception) {
                Log.d(TAG, "Unable to dispatch blocked-domain event", error)
            }
        }
    }
}
