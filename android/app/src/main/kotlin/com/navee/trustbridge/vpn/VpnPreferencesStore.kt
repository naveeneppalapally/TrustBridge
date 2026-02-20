package com.navee.trustbridge.vpn

import android.content.Context
import org.json.JSONArray

internal data class PersistedVpnConfig(
    val enabled: Boolean,
    val blockedCategories: List<String>,
    val blockedDomains: List<String>,
    val temporaryAllowedDomains: List<String>,
    val upstreamDns: String
)

internal class VpnPreferencesStore(context: Context) {
    companion object {
        private const val PREFS_NAME = "trustbridge_vpn_prefs"
        private const val KEY_ENABLED = "vpn_enabled"
        private const val KEY_BLOCKED_CATEGORIES = "vpn_blocked_categories"
        private const val KEY_BLOCKED_DOMAINS = "vpn_blocked_domains"
        private const val KEY_TEMP_ALLOWED_DOMAINS = "vpn_temp_allowed_domains"
        private const val KEY_UPSTREAM_DNS = "vpn_upstream_dns"
        private const val DEFAULT_UPSTREAM_DNS = "45.90.28.0"
    }

    private val prefs = context.applicationContext.getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE
    )

    fun loadConfig(): PersistedVpnConfig {
        return PersistedVpnConfig(
            enabled = prefs.getBoolean(KEY_ENABLED, false),
            blockedCategories = decodeStringList(
                prefs.getString(KEY_BLOCKED_CATEGORIES, "[]")
            ),
            blockedDomains = decodeStringList(
                prefs.getString(KEY_BLOCKED_DOMAINS, "[]")
            ),
            temporaryAllowedDomains = decodeStringList(
                prefs.getString(KEY_TEMP_ALLOWED_DOMAINS, "[]")
            ),
            upstreamDns = normalizeUpstreamDns(
                prefs.getString(KEY_UPSTREAM_DNS, DEFAULT_UPSTREAM_DNS)
            )
        )
    }

    fun saveRules(
        categories: List<String>,
        domains: List<String>,
        temporaryAllowedDomains: List<String>,
        upstreamDns: String? = null
    ) {
        prefs.edit()
            .putString(KEY_BLOCKED_CATEGORIES, encodeStringList(categories))
            .putString(KEY_BLOCKED_DOMAINS, encodeStringList(domains))
            .putString(KEY_TEMP_ALLOWED_DOMAINS, encodeStringList(temporaryAllowedDomains))
            .putString(KEY_UPSTREAM_DNS, normalizeUpstreamDns(upstreamDns))
            .apply()
    }

    fun setEnabled(enabled: Boolean) {
        prefs.edit()
            .putBoolean(KEY_ENABLED, enabled)
            .apply()
    }

    private fun encodeStringList(values: List<String>): String {
        val uniqueValues = LinkedHashSet<String>()
        values.forEach { value ->
            val normalized = value.trim()
            if (normalized.isNotEmpty()) {
                uniqueValues.add(normalized)
            }
        }
        val jsonArray = JSONArray()
        uniqueValues.forEach { jsonArray.put(it) }
        return jsonArray.toString()
    }

    private fun decodeStringList(raw: String?): List<String> {
        if (raw.isNullOrBlank()) {
            return emptyList()
        }
        return try {
            val jsonArray = JSONArray(raw)
            buildList {
                for (index in 0 until jsonArray.length()) {
                    val value = jsonArray.optString(index)?.trim().orEmpty()
                    if (value.isNotEmpty()) {
                        add(value)
                    }
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun normalizeUpstreamDns(value: String?): String {
        val normalized = value?.trim().orEmpty()
        return if (normalized.isEmpty()) DEFAULT_UPSTREAM_DNS else normalized
    }
}
