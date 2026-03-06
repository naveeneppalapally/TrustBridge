package com.navee.trustbridge

import android.app.Application
import io.flutter.FlutterInjector

class TrustBridgeApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Ensure Flutter loader initialization starts at process creation time.
        // This avoids rare startup crashes where the activity requests the app
        // bundle path before FlutterApplicationInfo is prepared.
        try {
            FlutterInjector.instance().flutterLoader().startInitialization(this)
        } catch (_: Throwable) {
            // Keep process alive; FlutterActivity will retry initialization.
        }
    }
}
