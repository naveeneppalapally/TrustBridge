# Child Connection Diagnostic

- Started: 2026-02-22 15:55:41.357 +05:30
- Ended: 2026-02-22 15:59:29.196 +05:30
- Status: **PASS**
- Device: emulator-5556
- Parent email: tb.diag.connection@trustbridge.local
- Child ID: (auto-resolved)
- Firebase target: Emulators (10.0.2.2:9099 / 10.0.2.2:8080)

## Diagnostic Log

- [36m[1mi  emulators:[22m[39m Starting emulators: auth, firestore
- [36m[1mi  firestore:[22m[39m Firestore Emulator logging to [1mfirestore-debug.log[22m
- [32m[1m+  firestore:[22m[39m Firestore Emulator UI websocket is running on 9150.
- [36m[1mi [22m[39m Running script: [1mflutter test integration_test/child_parent_account_connection_diagnostic_test.dart -d emulator-5556 --dart-define=TB_DIAG_PARENT_EMAIL=tb.diag.connection@trustbridge.local --dart-define=TB_DIAG_PARENT_PASSWORD=TbDiag1234! --dart-define=TB_DIAG_AUTO_CREATE_PARENT=true --dart-define=TB_DIAG_AUTO_CREATE_CHILD=true --dart-define=TB_DIAG_EMULATOR_HOST=10.0.2.2 --dart-define=TB_DIAG_AUTH_PORT=9099 --dart-define=TB_DIAG_FIRESTORE_PORT=8080[22m
- 00:00 +0: loading C:/Users/navee/Documents/TrustBridge/parental_controls_app/integration_test/child_parent_account_connection_diagnostic_test.dart
- Running Gradle task 'assembleDebug'...                             75.5s
- √ Built build\app\outputs\flutter-apk\app-debug.apk
- Installing build\app\outputs\flutter-apk\app-debug.apk...           7.7s
- 00:00 +0: child mode same-account connection diagnostic
- [DIAG] Using Firebase emulators auth=10.0.2.2:9099 firestore=10.0.2.2:8080
- [DIAG] Signed in parent UID: 7IXoymWEgCSyBJmmTbIYVJmSXJDl
- [DIAG] Created diagnostic child profile at children/diag_child_1771756152880
- [DIAG] Target childId: diag_child_1771756152880
- [DIAG] Child profile read OK: children/diag_child_1771756152880
- [DIAG] Local deviceId: fc3d98cf-6401-4b84-9141-feb38317e090
- [DIAG] Device registration OK: children/diag_child_1771756152880/devices/fc3d98cf-6401-4b84-9141-feb38317e090 fields=[diagnosticUpdatedAt, osVersion, model, parentId, pairedAt]
- [DIAG] Root heartbeat doc write OK: devices/fc3d98cf-6401-4b84-9141-feb38317e090
- [DIAG] Child policy field is readable with keys: [schedules, blockedCategories, safeSearchEnabled, blockedDomains]
- [DIAG] children/diag_child_1771756152880/policy subcollection docs: 0
- [DIAG] FCM token write OK: children/diag_child_1771756152880/devices/fc3d98cf-6401-4b84-9141-feb38317e090/fcmToken
- 00:28 +1: (tearDownAll)
- 00:35 +1: All tests passed!
- [32m[1m+ [22m[39m Script exited successfully (code 0)
- [36m[1mi  emulators:[22m[39m Shutting down emulators.
- [36m[1mi  firestore:[22m[39m Stopping Firestore Emulator
- [33m[1m! [22m[39m Firestore Emulator has exited upon receiving signal: SIGINT
- [36m[1mi  auth:[22m[39m Stopping Authentication Emulator
- [36m[1mi  hub:[22m[39m Stopping emulator hub
- [36m[1mi  logging:[22m[39m Stopping Logging Emulator

