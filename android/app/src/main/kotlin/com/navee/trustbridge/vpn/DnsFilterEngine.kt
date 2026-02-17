package com.navee.trustbridge.vpn

import android.content.Context
import android.util.Log

class DnsFilterEngine(private val context: Context) {
    companion object {
        private const val TAG = "DnsFilterEngine"
    }

    private val blocklistStore = BlocklistStore(context)
    private val blockedDomains = mutableSetOf<String>()
    private val blockedCategories = mutableSetOf<String>()

    data class DomainEvaluation(
        val inputDomain: String,
        val normalizedDomain: String,
        val blocked: Boolean,
        val matchedRule: String?
    )

    init {
        hydrateRulesFromDisk()
    }

    @Synchronized
    fun shouldBlock(domain: String): Boolean {
        if (domain.isBlank()) {
            return false
        }

        val normalizedDomain = normalizeDomain(domain)
        return findMatchingRule(normalizedDomain) != null
    }

    @Synchronized
    fun updateFilterRules(categories: List<String>, customDomains: List<String>) {
        val nextCategories = categories
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toSet()

        val nextDomains = mutableSetOf<String>()
        nextDomains.addAll(customDomains.map(::normalizeDomain).filter { it.isNotEmpty() })
        nextCategories.forEach { category ->
            nextDomains.addAll(loadCategoryDomains(category).map(::normalizeDomain))
        }

        applyRules(
            categories = nextCategories,
            domains = nextDomains,
            persist = true
        )

        Log.d(
            TAG,
            "Filter rules updated. categories=${blockedCategories.size}, domains=${blockedDomains.size}"
        )
    }

    @Synchronized
    fun blockedDomainCount(): Int = blockedDomains.size

    @Synchronized
    fun blockedCategoryCount(): Int = blockedCategories.size

    @Synchronized
    fun clearAllRules() {
        try {
            blocklistStore.clearRules()
            blockedCategories.clear()
            blockedDomains.clear()
            Log.d(TAG, "Cleared persisted and in-memory blocklist rules")
        } catch (error: Exception) {
            Log.e(TAG, "Failed clearing blocklist rules", error)
        }
    }

    @Synchronized
    fun evaluateDomain(domain: String): DomainEvaluation {
        val normalizedDomain = normalizeDomain(domain)
        val matchedRule = if (normalizedDomain.isBlank()) {
            null
        } else {
            findMatchingRule(normalizedDomain)
        }
        return DomainEvaluation(
            inputDomain = domain,
            normalizedDomain = normalizedDomain,
            blocked = matchedRule != null,
            matchedRule = matchedRule
        )
    }

    @Synchronized
    private fun applyRules(
        categories: Set<String>,
        domains: Set<String>,
        persist: Boolean
    ) {
        blockedCategories.clear()
        blockedCategories.addAll(categories)
        blockedDomains.clear()
        blockedDomains.addAll(domains)

        if (persist) {
            try {
                blocklistStore.replaceRules(
                    categories = blockedCategories,
                    domains = blockedDomains
                )
            } catch (error: Exception) {
                Log.e(TAG, "Failed to persist blocklist rules", error)
            }
        }
    }

    private fun hydrateRulesFromDisk() {
        try {
            val snapshot = blocklistStore.loadSnapshot()
            applyRules(
                categories = snapshot.categories,
                domains = snapshot.domains,
                persist = false
            )
            Log.d(
                TAG,
                "Loaded persisted rules. categories=${blockedCategories.size}, domains=${blockedDomains.size}"
            )
        } catch (error: Exception) {
            Log.e(TAG, "Failed to load persisted rules. Falling back to empty rules.", error)
            applyRules(
                categories = emptySet(),
                domains = emptySet(),
                persist = false
            )
        }
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
                "discord.com",
                "pinterest.com"
            )

            "adult-content" -> listOf(
                "pornhub.com",
                "xvideos.com",
                "xnxx.com",
                "xhamster.com"
            )

            "gambling" -> listOf(
                "bet365.com",
                "1xbet.com",
                "betway.com",
                "draftkings.com",
                "fanduel.com"
            )

            "weapons" -> listOf(
                "guns.com",
                "brownells.com",
                "cheaperthandirt.com"
            )

            "drugs" -> listOf(
                "weedmaps.com",
                "leafly.com",
                "erowid.org"
            )

            "violence" -> listOf(
                "bestgore.fun",
                "worldstarhiphop.com"
            )

            "dating" -> listOf(
                "tinder.com",
                "bumble.com",
                "hinge.co"
            )

            "chat" -> listOf(
                "omegle.com",
                "chatroulette.com"
            )

            "streaming" -> listOf(
                "youtube.com",
                "twitch.tv",
                "netflix.com"
            )

            "games" -> listOf(
                "roblox.com",
                "epicgames.com",
                "steamcommunity.com"
            )

            "shopping" -> listOf(
                "amazon.com",
                "ebay.com",
                "walmart.com"
            )

            "forums" -> listOf(
                "reddit.com",
                "quora.com"
            )

            "news" -> listOf(
                "cnn.com",
                "bbc.com",
                "nytimes.com"
            )

            else -> emptyList()
        }
    }

    private fun normalizeDomain(domain: String): String {
        var value = domain.trim().lowercase()
        if (value.startsWith("*.")) {
            value = value.removePrefix("*.")
        }
        if (value.startsWith("www.")) {
            value = value.removePrefix("www.")
        }
        while (value.endsWith(".")) {
            value = value.dropLast(1)
        }
        return value
    }

    private fun findMatchingRule(normalizedDomain: String): String? {
        if (blockedDomains.contains(normalizedDomain)) {
            return normalizedDomain
        }
        for (blocked in blockedDomains) {
            if (normalizedDomain.endsWith(".$blocked")) {
                return blocked
            }
        }
        return null
    }

    fun close() {
        try {
            blocklistStore.close()
        } catch (_: Exception) {
        }
    }
}
