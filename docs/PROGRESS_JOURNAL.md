# TrustBridge Progress Journal

This file tracks work by program day and by commit so progress can be audited with exact timestamps.

## Logging Rule (from now on)

After each new commit, append one entry to this file with:
- Date/time
- Commit hash
- What changed
- Validation done

---

## Day 1 - Foundation

Program goal: project setup, git setup, branding baseline, folder structure.

### Commit entries

1. **2026-02-15 21:00:09 +0530**  
   Commit: `18e675d`  
   Message: `Initial commit: Flutter project created`  
   Changes:
   - Created Flutter project scaffold across Android/iOS/web/desktop.
   - Added updated `.gitignore` setup for Flutter/Android/Firebase/secrets.
   Validation:
   - Flutter project created successfully.
   - Initial app run verified during setup.

2. **2026-02-15 21:03:24 +0530**  
   Commit: `88982cc`  
   Message: `Add comprehensive README`  
   Changes:
   - Replaced default README with TrustBridge project overview and roadmap.
   Validation:
   - README reviewed and saved in repo root.

3. **2026-02-15 21:03:45 +0530**  
   Commit: `580a0e8`  
   Message: `Update Android package ID and app name`  
   Changes:
   - Updated Android package from default to `com.navee.parentalcontrols` (later renamed in Day 1).
   - Updated Android app label.
   - Moved `MainActivity.kt` package path to match package ID.
   Validation:
   - Android build and run succeeded after package rename.

4. **2026-02-15 21:04:01 +0530**  
   Commit: `88f5310`  
   Message: `Create project folder structure`  
   Changes:
   - Added `docs/` copies of planning documents.
   - Added initial app folders and stubs:
     - `lib/models/`
     - `lib/services/`
     - `lib/screens/`
   Validation:
   - Folder structure present and tracked in git.

5. **2026-02-15 21:04:23 +0530**  
   Commit: `f33a51e`  
   Message: `Track empty widgets and utils folders`  
   Changes:
   - Added `.gitkeep` files under:
     - `lib/widgets/`
     - `lib/utils/`
   Validation:
   - Empty folders now persist in repo.

6. **2026-02-15 21:21:24 +0530**  
   Commit: `07a40a5`  
   Message: `Rename app branding and identifiers to TrustBridge`  
   Changes:
   - Renamed app identity across platforms from parental-controls naming to TrustBridge naming.
   - Updated package/app identifiers to:
     - Dart package: `trustbridge_app`
     - Android package: `com.navee.trustbridge`
     - Android label: `TrustBridge`
   - Updated platform metadata files (Android/iOS/web/windows/linux/macos).
   Validation:
   - Android `flutter run` succeeded after global rename.

---

## Day 2 - Dependencies and Setup Baseline

Program goal: install all required packages, wire Provider baseline, and document dependency decisions.

### Commit entries

1. **2026-02-15 21:38:52 +0530**  
   Commit: `9455b9c`  
   Message: `Add Day 2 dependencies and dependency documentation`  
   Changes:
   - Updated `pubspec.yaml` with required dependencies:
     - Firebase: `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_messaging`
     - State: `provider`
     - Networking: `http`
     - Local storage: `shared_preferences`, `sqflite`, `path`
     - Utilities: `intl`, `uuid`
     - UI: `fl_chart`, `shimmer`
   - Added `docs/dependencies.md` with package rationale and usage notes.
   - Reworked `lib/main.dart` baseline and Provider setup.
   Validation:
   - `flutter pub get` succeeded.
   - `flutter pub deps` confirmed package graph.
   - `flutter test` passed.
   - `flutter run -d emulator-5554 --no-resident` succeeded.

---

## Day 3 - Firebase Setup (Android)

Program goal: configure Firebase for Android with FlutterFire CLI and initialize Firebase at startup.

### Commit entries

1. **2026-02-15 21:58:12 +0530**  
   Commit: `e9cafa3`  
   Message: `Configure Firebase for Android and initialize app startup`  
   Changes:
   - Created Firebase project:
     - Display name: `TrustBridge`
     - Project ID: `trustbridge-navee`
   - Installed and used FlutterFire CLI to configure Android app:
     - Android package: `com.navee.trustbridge`
     - Firebase App ID: `1:1086399599434:android:1bd0fb529f0510120b67b3`
   - Added generated Firebase config files:
     - `lib/firebase_options.dart`
     - `firebase.json`
     - Local `android/app/google-services.json` (not committed by design)
   - Updated Android Gradle KTS config for Google Services plugin:
     - `android/settings.gradle.kts`
     - `android/app/build.gradle.kts`
   - Updated app startup in `lib/main.dart`:
     - `WidgetsFlutterBinding.ensureInitialized()`
     - `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`
   Validation:
   - `flutter pub get` succeeded.
   - `flutter analyze` reported no issues.
   - `flutter run -d emulator-5554 --no-resident` succeeded.

---

## Current Summary (after Day 3)

- Day 1 completed: foundation, naming, structure, git + GitHub.
- Day 2 completed: dependencies and Provider baseline.
- Day 3 completed: Firebase Android configuration and initialization.

Last updated: 2026-02-15
