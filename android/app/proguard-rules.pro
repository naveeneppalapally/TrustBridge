# Flutter wrapper and generated plugin registrations
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase / Play services used across auth, firestore, and messaging
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# TrustBridge VPN native classes must remain intact in release
-keep class com.navee.trustbridge.vpn.** { *; }
-keep class com.navee.trustbridge.MainActivity { *; }

# Kotlin coroutine dispatcher metadata
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# Flutter deferred components references (safe to ignore in this app)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
