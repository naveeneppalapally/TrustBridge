package com.navee.trustbridge.vpn

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log

internal data class BlocklistSnapshot(
    val categories: Set<String>,
    val domains: Set<String>
) {
    fun isEmpty(): Boolean = categories.isEmpty() && domains.isEmpty()
}

internal data class BlocklistMetadata(
    val categoryCount: Int,
    val domainCount: Int,
    val lastUpdatedAtEpochMs: Long?,
    val sampleCategories: List<String>,
    val sampleDomains: List<String>
)

internal class BlocklistStore(context: Context) : SQLiteOpenHelper(
    context.applicationContext,
    DB_NAME,
    null,
    DB_VERSION
) {
    companion object {
        private const val TAG = "BlocklistStore"
        private const val DB_NAME = "dns_blocklist.db"
        private const val DB_VERSION = 1
        private const val TABLE_DOMAINS = "blocked_domains"
        private const val TABLE_CATEGORIES = "blocked_categories"
        private const val COLUMN_DOMAIN = "domain"
        private const val COLUMN_CATEGORY = "category"
        private const val COLUMN_UPDATED_AT = "updated_at_epoch_ms"
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE_DOMAINS (
                $COLUMN_DOMAIN TEXT PRIMARY KEY NOT NULL,
                $COLUMN_UPDATED_AT INTEGER NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE TABLE $TABLE_CATEGORIES (
                $COLUMN_CATEGORY TEXT PRIMARY KEY NOT NULL,
                $COLUMN_UPDATED_AT INTEGER NOT NULL
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        Log.w(TAG, "Upgrading blocklist store from $oldVersion to $newVersion")
        db.execSQL("DROP TABLE IF EXISTS $TABLE_DOMAINS")
        db.execSQL("DROP TABLE IF EXISTS $TABLE_CATEGORIES")
        onCreate(db)
    }

    @Synchronized
    fun loadSnapshot(): BlocklistSnapshot {
        val categories = linkedSetOf<String>()
        val domains = linkedSetOf<String>()

        readableDatabase.query(
            TABLE_CATEGORIES,
            arrayOf(COLUMN_CATEGORY),
            null,
            null,
            null,
            null,
            null
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val category = cursor.getString(0)?.trim().orEmpty()
                if (category.isNotEmpty()) {
                    categories.add(category)
                }
            }
        }

        readableDatabase.query(
            TABLE_DOMAINS,
            arrayOf(COLUMN_DOMAIN),
            null,
            null,
            null,
            null,
            null
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val domain = cursor.getString(0)?.trim()?.lowercase().orEmpty()
                if (domain.isNotEmpty()) {
                    domains.add(domain)
                }
            }
        }

        return BlocklistSnapshot(
            categories = categories,
            domains = domains
        )
    }

    @Synchronized
    fun replaceRules(categories: Set<String>, domains: Set<String>) {
        val now = System.currentTimeMillis()
        val writableDb = writableDatabase

        writableDb.beginTransaction()
        try {
            writableDb.delete(TABLE_CATEGORIES, null, null)
            writableDb.delete(TABLE_DOMAINS, null, null)

            categories.forEach { category ->
                val values = ContentValues().apply {
                    put(COLUMN_CATEGORY, category)
                    put(COLUMN_UPDATED_AT, now)
                }
                writableDb.insertOrThrow(TABLE_CATEGORIES, null, values)
            }

            domains.forEach { domain ->
                val values = ContentValues().apply {
                    put(COLUMN_DOMAIN, domain)
                    put(COLUMN_UPDATED_AT, now)
                }
                writableDb.insertOrThrow(TABLE_DOMAINS, null, values)
            }

            writableDb.setTransactionSuccessful()
        } finally {
            writableDb.endTransaction()
        }
    }

    @Synchronized
    fun clearRules() {
        val writableDb = writableDatabase
        writableDb.beginTransaction()
        try {
            writableDb.delete(TABLE_CATEGORIES, null, null)
            writableDb.delete(TABLE_DOMAINS, null, null)
            writableDb.setTransactionSuccessful()
        } finally {
            writableDb.endTransaction()
        }
    }

    @Synchronized
    fun loadMetadata(sampleLimit: Int = 5): BlocklistMetadata {
        val safeSampleLimit = if (sampleLimit <= 0) 1 else sampleLimit
        var categoryCount = 0
        var domainCount = 0
        var maxUpdatedAt: Long? = null
        val sampleCategories = mutableListOf<String>()
        val sampleDomains = mutableListOf<String>()

        readableDatabase.query(
            TABLE_CATEGORIES,
            arrayOf(COLUMN_CATEGORY, COLUMN_UPDATED_AT),
            null,
            null,
            null,
            null,
            "$COLUMN_CATEGORY ASC"
        ).use { cursor ->
            while (cursor.moveToNext()) {
                categoryCount += 1
                val category = cursor.getString(0)?.trim().orEmpty()
                val updatedAt = cursor.getLong(1)
                if (category.isNotEmpty() && sampleCategories.size < safeSampleLimit) {
                    sampleCategories.add(category)
                }
                if (maxUpdatedAt == null || updatedAt > maxUpdatedAt!!) {
                    maxUpdatedAt = updatedAt
                }
            }
        }

        readableDatabase.query(
            TABLE_DOMAINS,
            arrayOf(COLUMN_DOMAIN, COLUMN_UPDATED_AT),
            null,
            null,
            null,
            null,
            "$COLUMN_DOMAIN ASC"
        ).use { cursor ->
            while (cursor.moveToNext()) {
                domainCount += 1
                val domain = cursor.getString(0)?.trim()?.lowercase().orEmpty()
                val updatedAt = cursor.getLong(1)
                if (domain.isNotEmpty() && sampleDomains.size < safeSampleLimit) {
                    sampleDomains.add(domain)
                }
                if (maxUpdatedAt == null || updatedAt > maxUpdatedAt!!) {
                    maxUpdatedAt = updatedAt
                }
            }
        }

        return BlocklistMetadata(
            categoryCount = categoryCount,
            domainCount = domainCount,
            lastUpdatedAtEpochMs = maxUpdatedAt,
            sampleCategories = sampleCategories,
            sampleDomains = sampleDomains
        )
    }
}
