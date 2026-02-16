package com.navee.trustbridge

import android.content.Intent
import android.os.Build
import com.navee.trustbridge.vpn.DnsVpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val VPN_PERMISSION_REQUEST_CODE = 44123
        private val CHANNEL_NAMES = listOf(
            "trustbridge/vpn",
            "com.navee.trustbridge/vpn"
        )
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        CHANNEL_NAMES.forEach { channelName ->
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                channelName
            ).setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
            }
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(
                mapOf(
                    "supported" to true,
                    "permissionGranted" to hasVpnPermission(),
                    "isRunning" to DnsVpnService.isRunning
                )
            )

            "hasVpnPermission" -> result.success(hasVpnPermission())

            "requestPermission", "requestVpnPermission" -> requestVpnPermission(result)

            "startVpn" -> {
                if (!hasVpnPermission()) {
                    result.error(
                        "permission_required",
                        "VPN permission is required before starting.",
                        null
                    )
                    return
                }

                val blockedCategories =
                    call.argument<List<String>>("blockedCategories") ?: emptyList()
                val blockedDomains =
                    call.argument<List<String>>("blockedDomains") ?: emptyList()

                val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
                    action = DnsVpnService.ACTION_START
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_BLOCKED_CATEGORIES,
                        ArrayList(blockedCategories)
                    )
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_BLOCKED_DOMAINS,
                        ArrayList(blockedDomains)
                    )
                }
                startServiceCompat(serviceIntent)
                result.success(true)
            }

            "stopVpn" -> {
                val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
                    action = DnsVpnService.ACTION_STOP
                }
                startServiceCompat(serviceIntent)
                result.success(true)
            }

            "isVpnRunning" -> result.success(DnsVpnService.isRunning)

            "updateFilterRules" -> {
                val blockedCategories =
                    call.argument<List<String>>("blockedCategories") ?: emptyList()
                val blockedDomains =
                    call.argument<List<String>>("blockedDomains") ?: emptyList()

                val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
                    action = DnsVpnService.ACTION_UPDATE_RULES
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_BLOCKED_CATEGORIES,
                        ArrayList(blockedCategories)
                    )
                    putStringArrayListExtra(
                        DnsVpnService.EXTRA_BLOCKED_DOMAINS,
                        ArrayList(blockedDomains)
                    )
                }
                startServiceCompat(serviceIntent)
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    private fun hasVpnPermission(): Boolean {
        return android.net.VpnService.prepare(this) == null
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val prepareIntent = android.net.VpnService.prepare(this)
        if (prepareIntent == null) {
            result.success(true)
            return
        }

        if (pendingPermissionResult != null) {
            result.error(
                "permission_in_progress",
                "VPN permission request already in progress.",
                null
            )
            return
        }

        pendingPermissionResult = result
        @Suppress("DEPRECATION")
        startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST_CODE)
    }

    private fun startServiceCompat(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_REQUEST_CODE) {
            val granted = hasVpnPermission()
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }
}
