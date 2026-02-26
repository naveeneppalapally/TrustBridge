package com.navee.trustbridge.vpn

import android.content.Context
import android.util.Log

class DnsFilterEngine(private val context: Context) {
    companion object {
        private const val TAG = "DnsFilterEngine"
        private const val BLOCK_ALL_CATEGORY_TOKEN = "__block_all__"
        private val ENCRYPTED_DNS_RESOLVER_DOMAINS = setOf(
            // Google / Chrome Secure DNS
            "dns.google",
            "dns.google.com",
            "dns64.dns.google",
            "chrome.cloudflare-dns.com",
            "mozilla.cloudflare-dns.com",
            // Cloudflare
            "cloudflare-dns.com",
            "dns.cloudflare.com",
            "one.one.one.one",
            "security.cloudflare-dns.com",
            "family.cloudflare-dns.com",
            "odoh.cloudflare-dns.com",
            // Quad9
            "dns.quad9.net",
            "dns9.quad9.net",
            "dns10.quad9.net",
            // OpenDNS / Cisco Umbrella
            "doh.opendns.com",
            "doh.umbrella.com",
            // NextDNS
            "dns.nextdns.io",
            // AdGuard
            "dns.adguard-dns.com",
            "unfiltered.adguard-dns.com",
            "dns-unfiltered.adguard.com",
            "family.adguard-dns.com",
            "dns-family.adguard.com",
            // CleanBrowsing
            "doh.cleanbrowsing.org",
            "security-filter-dns.cleanbrowsing.org",
            "family-filter-dns.cleanbrowsing.org",
            "adult-filter-dns.cleanbrowsing.org",
            // Mullvad / common public resolvers
            "doh.mullvad.net",
            "base.dns.mullvad.net",
            "dns.sb",
            "doh.applied-privacy.net",
            "dnsforge.de",
            "dns0.eu",
            "zero.dns0.eu",
            "doh.libredns.gr",
            "doh.tiar.app",
            "dns.twnic.tw",
            "doh.pub",
            "dot.pub"
        )
        private val CONTROL_PLANE_ALLOWED_DOMAINS = setOf(
            // Firestore / Auth / Installations
            "firestore.googleapis.com",
            "identitytoolkit.googleapis.com",
            "securetoken.googleapis.com",
            "firebaseinstallations.googleapis.com",
            // FCM transport and registration
            "mtalk.google.com",
            "fcmregistrations.googleapis.com",
            // Crashlytics / telemetry (non-user browsing traffic)
            "firebase-settings.crashlytics.com",
            "crashlyticsreports-pa.googleapis.com",
            "firebaselogging-pa.googleapis.com"
        )
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
            "youtubei.googleapis.com",
            "youtube.googleapis.com",
            "youtubeandroidplayer.googleapis.com",
            "yt3.ggpht.com",
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

    data class BlockDecision(
        val blocked: Boolean,
        val reasonCode: String,
        val matchedRule: String? = null
    )

    init {
        hydrateRulesFromDisk()
    }

    @Synchronized
    fun shouldBlock(domain: String): Boolean {
        return evaluateBlockDecision(domain).blocked
    }

    @Synchronized
    fun evaluateBlockDecision(domain: String): BlockDecision {
        if (domain.isBlank()) {
            return BlockDecision(
                blocked = false,
                reasonCode = "invalid_domain",
                matchedRule = null
            )
        }

        val normalizedDomain = normalizeDomain(domain)
        Log.d(
            TAG,
            "shouldBlock($normalizedDomain) cats=$blockedCategories customDomains=${blockedDomains.size} allowed=${temporaryAllowedDomains.size}"
        )

        val controlPlaneAllowRule = findMatchingControlPlaneAllowRule(normalizedDomain)
        if (controlPlaneAllowRule != null) {
            Log.d(TAG, "ALLOWED by control-plane rule: $controlPlaneAllowRule")
            return BlockDecision(
                blocked = false,
                reasonCode = "allow_control_plane",
                matchedRule = controlPlaneAllowRule
            )
        }

        val allowRule = findMatchingAllowRule(normalizedDomain)
        if (allowRule != null) {
            Log.d(TAG, "ALLOWED by temp-allow rule: $allowRule")
            return BlockDecision(
                blocked = false,
                reasonCode = "allow_temp_allowlist",
                matchedRule = allowRule
            )
        }
        if (blockedCategories.contains(BLOCK_ALL_CATEGORY_TOKEN)) {
            Log.d(TAG, "BLOCKED by block-all mode token")
            return BlockDecision(
                blocked = true,
                reasonCode = "block_all_mode",
                matchedRule = BLOCK_ALL_CATEGORY_TOKEN
            )
        }
        val encryptedDnsRule = findMatchingEncryptedDnsResolverRule(normalizedDomain)
        if (encryptedDnsRule != null && hasActiveProtectionRules()) {
            Log.d(TAG, "BLOCKED by anti-bypass encrypted-DNS resolver rule: $encryptedDnsRule")
            return BlockDecision(
                blocked = true,
                reasonCode = "block_encrypted_dns_resolver",
                matchedRule = encryptedDnsRule
            )
        }
        val domainRule = findMatchingRule(normalizedDomain)
        if (domainRule != null) {
            Log.d(TAG, "BLOCKED by custom domain rule: $domainRule")
            return BlockDecision(
                blocked = true,
                reasonCode = "block_custom_domain_rule",
                matchedRule = domainRule
            )
        }
        if (isInstantSocialBlock(normalizedDomain)) {
            Log.d(TAG, "BLOCKED by instant social-media list")
            return BlockDecision(
                blocked = true,
                reasonCode = "block_instant_social_category",
                matchedRule = "social-networks"
            )
        }
        val dbCategory = localBlocklistDb.getCategory(normalizedDomain)
        if (dbCategory != null && isDbCategoryEnabled(dbCategory)) {
            Log.d(TAG, "BLOCKED by blocklist DB category=$dbCategory")
            return BlockDecision(
                blocked = true,
                reasonCode = "block_blocklist_db_category",
                matchedRule = dbCategory
            )
        }
        Log.d(TAG, "ALLOWED (no matching rule) domain=$normalizedDomain")
        return BlockDecision(
            blocked = false,
            reasonCode = "allow_no_match",
            matchedRule = null
        )
    }

    @Synchronized
    fun updateFilterRules(
        categories: List<String>,
        customDomains: List<String>,
        allowedDomains: List<String> = emptyList()
    ) {
        val nextCategories = categories
            .map(::normalizeCategoryToken)
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
    fun effectiveBlockedDomainCount(): Int {
        val dbCount = localBlocklistDb.countDomainsForEnabledCategories(blockedCategories)
        return blockedDomains.size + dbCount
    }

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

    private fun normalizeCategoryToken(category: String): String {
        val normalized = category.trim().lowercase()
        return when (normalized) {
            "social" -> "social-networks"
            "adult" -> "adult-content"
            else -> normalized
        }
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

    private fun findMatchingControlPlaneAllowRule(normalizedDomain: String): String? {
        if (CONTROL_PLANE_ALLOWED_DOMAINS.contains(normalizedDomain)) {
            return normalizedDomain
        }
        for (allowed in CONTROL_PLANE_ALLOWED_DOMAINS) {
            if (normalizedDomain.endsWith(".$allowed")) {
                return allowed
            }
        }
        return null
    }

    private fun findMatchingEncryptedDnsResolverRule(normalizedDomain: String): String? {
        if (ENCRYPTED_DNS_RESOLVER_DOMAINS.contains(normalizedDomain)) {
            return normalizedDomain
        }
        for (resolver in ENCRYPTED_DNS_RESOLVER_DOMAINS) {
            if (normalizedDomain.endsWith(".$resolver")) {
                return resolver
            }
        }
        return null
    }

    private fun hasActiveProtectionRules(): Boolean {
        if (blockedCategories.isNotEmpty()) {
            return true
        }
        if (blockedDomains.isNotEmpty()) {
            return true
        }
        return false
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
