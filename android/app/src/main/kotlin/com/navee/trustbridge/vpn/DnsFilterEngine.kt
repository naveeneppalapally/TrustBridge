package com.navee.trustbridge.vpn

import android.content.Context
import android.util.Log

class DnsFilterEngine(private val context: Context) {
    companion object {
        private const val TAG = "DnsFilterEngine"
        private val SOCIAL_MEDIA_DOMAINS = setOf(
            "instagram.com",
            "cdninstagram.com",
            "i.instagram.com",
            "graph.instagram.com",
            "tiktok.com",
            "tiktokcdn.com",
            "muscdn.com",
            "tiktokv.com",
            "byteoversea.com",
            "twitter.com",
            "t.co",
            "twimg.com",
            "api.twitter.com",
            "x.com",
            "abs.twimg.com",
            "snapchat.com",
            "snap.com",
            "sc-cdn.net",
            "snapkit.com",
            "facebook.com",
            "fb.com",
            "fbcdn.net",
            "connect.facebook.net",
            "facebook.net",
            "youtube.com",
            "youtu.be",
            "googlevideo.com",
            "ytimg.com",
            "youtube-nocookie.com",
            "reddit.com",
            "redd.it",
            "redditmedia.com",
            "reddituploads.com",
            "redditstatic.com",
            "roblox.com",
            "rbxcdn.com",
            "robloxlabs.com"
        )
    }

    private val blocklistStore = BlocklistStore(context)
    private val localBlocklistDb = LocalBlocklistDbReader(context)
    private val blockedDomains = mutableSetOf<String>()
    private val blockedCategories = mutableSetOf<String>()
    private val temporaryAllowedDomains = mutableSetOf<String>()

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
        if (findMatchingAllowRule(normalizedDomain) != null) {
            return false
        }
        if (findMatchingRule(normalizedDomain) != null) {
            return true
        }
        if (isInstantSocialBlock(normalizedDomain)) {
            return true
        }
        val dbCategory = localBlocklistDb.getCategory(normalizedDomain)
        if (dbCategory != null && isDbCategoryEnabled(dbCategory)) {
            return true
        }
        return false
    }

    @Synchronized
    fun updateFilterRules(
        categories: List<String>,
        customDomains: List<String>,
        allowedDomains: List<String> = emptyList()
    ) {
        val nextCategories = categories
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toSet()

        val nextDomains = mutableSetOf<String>()
        nextDomains.addAll(customDomains.map(::normalizeDomain).filter { it.isNotEmpty() })
        val nextAllowedDomains = allowedDomains
            .map(::normalizeDomain)
            .filter { it.isNotEmpty() }
            .toSet()

        applyRules(
            categories = nextCategories,
            domains = nextDomains,
            allowedDomains = nextAllowedDomains,
            persist = true
        )

        Log.d(
            TAG,
            "Filter rules updated. categories=${blockedCategories.size}, domains=${blockedDomains.size}, temporaryAllowed=${temporaryAllowedDomains.size}"
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
            temporaryAllowedDomains.clear()
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
        allowedDomains: Set<String>,
        persist: Boolean
    ) {
        blockedCategories.clear()
        blockedCategories.addAll(categories)
        blockedDomains.clear()
        blockedDomains.addAll(domains)
        temporaryAllowedDomains.clear()
        temporaryAllowedDomains.addAll(allowedDomains)

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
                allowedDomains = emptySet(),
                persist = false
            )
            Log.d(
                TAG,
                "Loaded persisted rules. categories=${blockedCategories.size}, domains=${blockedDomains.size}, temporaryAllowed=${temporaryAllowedDomains.size}"
            )
        } catch (error: Exception) {
            Log.e(TAG, "Failed to load persisted rules. Falling back to empty rules.", error)
            applyRules(
                categories = emptySet(),
                domains = emptySet(),
                allowedDomains = emptySet(),
                persist = false
            )
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

    private fun findMatchingAllowRule(normalizedDomain: String): String? {
        if (temporaryAllowedDomains.contains(normalizedDomain)) {
            return normalizedDomain
        }
        for (allowed in temporaryAllowedDomains) {
            if (normalizedDomain.endsWith(".$allowed")) {
                return allowed
            }
        }
        return null
    }

    private fun isInstantSocialBlock(normalizedDomain: String): Boolean {
        if (!isSocialCategoryEnabled()) {
            return false
        }

        if (SOCIAL_MEDIA_DOMAINS.contains(normalizedDomain)) {
            return true
        }
        for (blocked in SOCIAL_MEDIA_DOMAINS) {
            if (normalizedDomain.endsWith(".$blocked")) {
                return true
            }
        }
        return false
    }

    private fun isSocialCategoryEnabled(): Boolean {
        return blockedCategories.contains("social") ||
            blockedCategories.contains("social-networks")
    }

    private fun isDbCategoryEnabled(category: String): Boolean {
        return when (category) {
            "social" -> isSocialCategoryEnabled()
            "adult" -> blockedCategories.contains("adult-content")
            "gambling" -> blockedCategories.contains("gambling")
            "malware" -> blockedCategories.contains("malware")
            "ads" -> blockedCategories.contains("ads")
            "custom" -> true
            else -> false
        }
    }

    fun close() {
        try {
            blocklistStore.close()
        } catch (_: Exception) {
        }
        try {
            localBlocklistDb.close()
        } catch (_: Exception) {
        }
    }
}
