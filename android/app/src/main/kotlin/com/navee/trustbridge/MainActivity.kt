package com.navee.trustbridge

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val VPN_PERMISSION_REQUEST_CODE = 44123
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "trustbridge/vpn"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> {
                    val permissionGranted = android.net.VpnService.prepare(this) == null
                    result.success(
                        mapOf(
                            "supported" to true,
                            "permissionGranted" to permissionGranted,
                            "isRunning" to TrustBridgeVpnService.isRunning
                        )
                    )
                }

                "requestPermission" -> {
                    val prepareIntent = android.net.VpnService.prepare(this)
                    if (prepareIntent == null) {
                        result.success(true)
                        return@setMethodCallHandler
                    }

                    if (pendingPermissionResult != null) {
                        result.error(
                            "permission_in_progress",
                            "VPN permission request already in progress.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    pendingPermissionResult = result
                    @Suppress("DEPRECATION")
                    startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST_CODE)
                }

                "startVpn" -> {
                    val prepareIntent = android.net.VpnService.prepare(this)
                    if (prepareIntent != null) {
                        result.error(
                            "permission_required",
                            "VPN permission is required before starting.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    val serviceIntent = Intent(
                        this,
                        TrustBridgeVpnService::class.java
                    ).apply {
                        action = TrustBridgeVpnService.ACTION_START
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    result.success(true)
                }

                "stopVpn" -> {
                    val serviceIntent = Intent(
                        this,
                        TrustBridgeVpnService::class.java
                    ).apply {
                        action = TrustBridgeVpnService.ACTION_STOP
                    }
                    startService(serviceIntent)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_REQUEST_CODE) {
            val granted = android.net.VpnService.prepare(this) == null
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }
}
