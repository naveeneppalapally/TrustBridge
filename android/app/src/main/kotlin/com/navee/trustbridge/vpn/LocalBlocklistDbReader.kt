package com.navee.trustbridge.vpn

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log

/**
 * Read-only lookup helper for the Flutter-managed trustbridge_blocklist.db file.
 */
internal class LocalBlocklistDbReader(context: Context) {
    companion object {
        private const val TAG = "LocalBlocklistDbReader"
        private const val DB_NAME = "trustbridge_blocklist.db"
    }

    private val appContext = context.applicationContext
    @Volatile
    private var database: SQLiteDatabase? = null

    fun isDomainBlocked(domain: String): Boolean {
        return getCategory(domain) != null
    }

    fun getCategory(domain: String): String? {
        val normalized = normalizeDomain(domain)
        if (normalized.isBlank()) {
            return null
        }

        val db = openDatabaseOrNull() ?: return null
        val candidates = candidateDomains(normalized)
        for (candidate in candidates) {
            val cursor = db.query(
                "blocked_domains",
                arrayOf("category"),
                "domain = ?",
                arrayOf(candidate),
                null,
                null,
                null,
                "1"
            )
            cursor.use { c ->
                if (c.moveToFirst()) {
                    return c.getString(0)?.trim()?.lowercase()
                }
            }
        }
        return null
    }

    fun countDomainsForEnabledCategories(enabledCategories: Set<String>): Int {
        val db = openDatabaseOrNull() ?: return 0
        val mapped = mutableSetOf<String>()
        if (enabledCategories.contains("social") || enabledCategories.contains("social-networks")) {
            mapped.add("social")
        }
        if (enabledCategories.contains("ads")) {
            mapped.add("ads")
        }
        if (enabledCategories.contains("adult-content") || enabledCategories.contains("adult")) {
            mapped.add("adult")
        }
        if (enabledCategories.contains("gambling")) {
            mapped.add("gambling")
        }
        if (enabledCategories.contains("malware")) {
            mapped.add("malware")
        }
        if (mapped.isEmpty()) {
            return 0
        }

        val placeholders = mapped.joinToString(",") { "?" }
        val args = mapped.toTypedArray()
        val cursor = db.rawQuery(
            "SELECT COUNT(*) FROM blocked_domains WHERE category IN ($placeholders)",
            args
        )
        cursor.use { c ->
            return if (c.moveToFirst()) c.getInt(0) else 0
        }
    }

    @Synchronized
    fun close() {
        try {
            database?.close()
        } catch (_: Exception) {
        } finally {
            database = null
        }
    }

    @Synchronized
    private fun openDatabaseOrNull(): SQLiteDatabase? {
        val existing = database
        if (existing != null && existing.isOpen) {
            return existing
        }

        val dbPath = appContext.getDatabasePath(DB_NAME)
        if (!dbPath.exists()) {
            return null
        }

        return try {
            SQLiteDatabase.openDatabase(
                dbPath.absolutePath,
                null,
                SQLiteDatabase.OPEN_READONLY
            ).also { opened ->
                database = opened
            }
        } catch (error: Exception) {
            Log.w(TAG, "Unable to open blocklist DB", error)
            null
        }
    }

    private fun normalizeDomain(domain: String): String {
        var value = domain.trim().lowercase()
        if (value.startsWith("www.")) {
            value = value.removePrefix("www.")
        }
        while (value.endsWith(".")) {
            value = value.dropLast(1)
        }
        return value
    }

    private fun candidateDomains(normalizedDomain: String): List<String> {
        val candidates = mutableListOf<String>()
        var current = normalizedDomain
        while (current.contains('.')) {
            candidates.add(current)
            current = current.substringAfter('.', "")
            if (current.isBlank()) {
                break
            }
        }
        if (!candidates.contains(normalizedDomain)) {
            candidates.add(normalizedDomain)
        }
        return candidates
    }
}
