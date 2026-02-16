package com.navee.trustbridge.vpn

import android.content.Context
import android.util.Log

class DnsFilterEngine(private val context: Context) {
    companion object {
        private const val TAG = "DnsFilterEngine"
    }

    private val blockedDomains = mutableSetOf<String>()
    private val blockedCategories = mutableSetOf<String>()

    init {
        loadFilterRules()
    }

    @Synchronized
    fun shouldBlock(domain: String): Boolean {
        if (domain.isBlank()) {
            return false
        }

        val normalizedDomain = normalizeDomain(domain)
        if (blockedDomains.contains(normalizedDomain)) {
            return true
        }

        for (blocked in blockedDomains) {
            if (normalizedDomain.endsWith(".$blocked")) {
                return true
            }
        }
        return false
    }

    @Synchronized
    fun updateFilterRules(categories: List<String>, customDomains: List<String>) {
        blockedCategories.clear()
        blockedCategories.addAll(categories.map { it.trim() }.filter { it.isNotEmpty() })

        blockedDomains.clear()
        blockedDomains.addAll(customDomains.map(::normalizeDomain).filter { it.isNotEmpty() })

        blockedCategories.forEach { category ->
            blockedDomains.addAll(loadCategoryDomains(category).map(::normalizeDomain))
        }

        Log.d(
            TAG,
            "Filter rules updated. categories=${blockedCategories.size}, domains=${blockedDomains.size}"
        )
    }

    @Synchronized
    fun blockedDomainCount(): Int = blockedDomains.size

    private fun loadFilterRules() {
        // Bootstrap with conservative defaults until dynamic policy sync is wired.
        blockedDomains.addAll(
            listOf(
                "facebook.com",
                "instagram.com",
                "tiktok.com",
                "snapchat.com",
                "x.com",
                "pornhub.com",
                "xvideos.com"
            ).map(::normalizeDomain)
        )
        Log.d(TAG, "Loaded ${blockedDomains.size} default blocked domains")
    }

    private fun loadCategoryDomains(category: String): List<String> {
        return when (category) {
            "social-networks" -> listOf(
                "facebook.com",
                "instagram.com",
                "x.com",
                "tiktok.com",
                "snapchat.com",
                "reddit.com",
                "discord.com"
            )

            "adult-content" -> listOf(
                "pornhub.com",
                "xvideos.com",
                "xnxx.com"
            )

            "gambling" -> listOf(
                "bet365.com",
                "1xbet.com",
                "betway.com"
            )

            else -> emptyList()
        }
    }

    private fun normalizeDomain(domain: String): String {
        var value = domain.trim().lowercase()
        while (value.endsWith(".")) {
            value = value.dropLast(1)
        }
        return value
    }
}
