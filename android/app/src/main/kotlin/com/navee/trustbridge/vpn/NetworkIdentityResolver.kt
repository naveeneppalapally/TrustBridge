package com.navee.trustbridge.vpn

import android.Manifest
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.system.OsConstants
import java.io.File
import java.net.InetSocketAddress

internal class NetworkIdentityResolver(
    private val host: Host
) {
    internal interface Host {
        val appPackageName: String
        val packageManager: PackageManager
        val infrastructurePackages: Set<String>

        fun connectivityManagerOrNull(): ConnectivityManager?
    }

    companion object {
        private const val PORT_UID_CACHE_TTL_MS = 15_000L
        private const val UID_PACKAGE_CACHE_TTL_MS = 60_000L
        private const val CACHE_SIZE_LIMIT = 512
    }

    private val sourcePortUidCache = linkedMapOf<Int, Pair<Int, Long>>()
    private val uidPackageCache = linkedMapOf<Int, Pair<String, Long>>()

    fun resolvePackageForQuery(
        sourcePort: Int,
        sourceIp: String,
        destPort: Int,
        destIp: String
    ): String? {
        val connectivityUid = resolveUidForConnection(
            sourcePort = sourcePort,
            sourceIp = sourceIp,
            destPort = destPort,
            destIp = destIp
        )
        if (connectivityUid != null) {
            val packageFromConnectivity = resolvePackageForUid(
                uid = connectivityUid,
                now = System.currentTimeMillis()
            )
            if (!packageFromConnectivity.isNullOrBlank()) {
                return packageFromConnectivity
            }
        }
        return resolvePackageForSourcePort(sourcePort)
    }

    fun isParentControllablePackage(packageName: String): Boolean {
        val normalizedPackage = packageName.trim().lowercase()
        if (normalizedPackage in host.infrastructurePackages ||
            normalizedPackage.startsWith("com.vivo.") ||
            normalizedPackage.startsWith("com.bbk.")
        ) {
            return false
        }
        return try {
            val appInfo = host.packageManager.getApplicationInfo(packageName, 0)
            val isSystem = appInfo.flags and ApplicationInfo.FLAG_SYSTEM != 0
            if (!isSystem) {
                return true
            }

            val isUpdatedSystem =
                appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP != 0
            if (!isUpdatedSystem) {
                return false
            }

            val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                host.packageManager.getInstallSourceInfo(packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                host.packageManager.getInstallerPackageName(packageName)
            }?.trim()?.lowercase()
            installer == "com.android.vending"
        } catch (_: Exception) {
            false
        }
    }

    fun hasInternetPermission(packageName: String): Boolean {
        return try {
            host.packageManager.checkPermission(
                Manifest.permission.INTERNET,
                packageName
            ) == PackageManager.PERMISSION_GRANTED
        } catch (_: Exception) {
            false
        }
    }

    private fun resolvePackageForSourcePort(sourcePort: Int): String? {
        if (sourcePort <= 0) {
            return null
        }
        val now = System.currentTimeMillis()
        val cachedUid = synchronized(sourcePortUidCache) {
            val cached = sourcePortUidCache[sourcePort]
            if (cached != null && now - cached.second <= PORT_UID_CACHE_TTL_MS) {
                cached.first
            } else {
                null
            }
        }
        val uid = cachedUid ?: findUidForSourcePort(sourcePort)?.also { resolved ->
            synchronized(sourcePortUidCache) {
                sourcePortUidCache[sourcePort] = resolved to now
                if (sourcePortUidCache.size > CACHE_SIZE_LIMIT) {
                    val oldestKey = sourcePortUidCache.entries
                        .minByOrNull { it.value.second }
                        ?.key
                    if (oldestKey != null) {
                        sourcePortUidCache.remove(oldestKey)
                    }
                }
            }
        } ?: return null

        return resolvePackageForUid(uid = uid, now = now)
    }

    private fun resolveUidForConnection(
        sourcePort: Int,
        sourceIp: String,
        destPort: Int,
        destIp: String
    ): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return null
        }
        if (sourcePort <= 0 || destPort <= 0 || sourceIp.isBlank() || destIp.isBlank()) {
            return null
        }
        val connectivityManager = host.connectivityManagerOrNull() ?: return null
        return try {
            val uid = connectivityManager.getConnectionOwnerUid(
                OsConstants.IPPROTO_UDP,
                InetSocketAddress(sourceIp, sourcePort),
                InetSocketAddress(destIp, destPort)
            )
            if (uid > 0) uid else null
        } catch (_: SecurityException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun resolvePackageForUid(uid: Int, now: Long): String? {
        if (uid <= 0) {
            return null
        }
        val cachedPackage = synchronized(uidPackageCache) {
            val cached = uidPackageCache[uid]
            if (cached != null && now - cached.second <= UID_PACKAGE_CACHE_TTL_MS) {
                cached.first
            } else {
                null
            }
        }
        if (!cachedPackage.isNullOrBlank()) {
            return cachedPackage
        }

        val packages = try {
            host.packageManager.getPackagesForUid(uid)
        } catch (_: Exception) {
            null
        } ?: return null
        val resolvedPackage = packages
            .mapNotNull { it?.trim()?.lowercase()?.takeIf { value -> value.isNotEmpty() } }
            .firstOrNull { packageName ->
                packageName != host.appPackageName &&
                    isParentControllablePackage(packageName) &&
                    hasInternetPermission(packageName)
            } ?: return null

        synchronized(uidPackageCache) {
            uidPackageCache[uid] = resolvedPackage to now
            if (uidPackageCache.size > CACHE_SIZE_LIMIT) {
                val oldestKey = uidPackageCache.entries
                    .minByOrNull { it.value.second }
                    ?.key
                if (oldestKey != null) {
                    uidPackageCache.remove(oldestKey)
                }
            }
        }
        return resolvedPackage
    }

    private fun findUidForSourcePort(sourcePort: Int): Int? {
        return parseUidFromProcNet(path = "/proc/net/udp", sourcePort = sourcePort)
            ?: parseUidFromProcNet(path = "/proc/net/udp6", sourcePort = sourcePort)
    }

    private fun parseUidFromProcNet(path: String, sourcePort: Int): Int? {
        return try {
            var matchedUid: Int? = null
            File(path).useLines { lines ->
                for (line in lines.drop(1)) {
                    val fields = line.trim().split(Regex("\\s+"))
                    if (fields.size < 8) {
                        continue
                    }
                    val localAddress = fields[1]
                    val localPortHex = localAddress.substringAfterLast(':', "")
                    val localPort = localPortHex.toIntOrNull(16) ?: continue
                    if (localPort != sourcePort) {
                        continue
                    }
                    val uid = fields[7].toIntOrNull()
                    if (uid != null && uid > 0) {
                        matchedUid = uid
                        break
                    }
                }
            }
            matchedUid
        } catch (_: Exception) {
            null
        }
    }
}
