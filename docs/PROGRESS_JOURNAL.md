# TrustBridge Progress Journal

This file tracks work by program day and by commit so progress can be audited with exact timestamps.

## Logging Rule (from now on)

After each new commit, append one entry to this file with:
- Date/time
- Commit hash
- What changed
- Validation done

For UI-related commits, also include:
- Design folder(s) used
- Design assets checked (`screen.png`, `code.html`)
- UI fidelity note (one line: what matched or what intentionally differed)

UI commit message convention:
- Add suffix: `[design: <folder_name>]`
- Example: `Implement login screen OTP flow [design: parent_login_mobile_light]`

### UI Entry Template (copy-paste for UI commits)

- Date/time:
- Commit hash:
- What changed:
- Validation done:
- Design folder(s) used:
- Design assets checked: `screen.png`, `code.html`
- UI fidelity note:

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

## Day 4 - Authentication Service (OTP)

Program goal: implement Day 4 AuthService methods for phone OTP, verification, and parent profile creation.

### Commit entries

1. **2026-02-15 22:20:34 +05:30**  
   Commit: `(this commit - see latest git log)`  
   Message: `Implement Day 4 AuthService with OTP and parent profile creation`  
   Changes:
   - Implemented `lib/services/auth_service.dart` with:
     - `currentUser`, `authStateChanges`
     - `sendOTP(...)` with +91 normalization for non-E.164 inputs
     - `verifyOTP(...)` for manual code verification
     - `signOut()`
     - internal Firestore parent profile creation for first-time users
   - Added callback handling for:
     - `verificationCompleted` (auto verification)
     - `verificationFailed`
     - `codeSent`
     - `codeAutoRetrievalTimeout`
   Validation:
   - `flutter pub get` succeeded.
   - `flutter analyze` reported no issues.
   - `flutter test` passed.
   - `flutter run -d emulator-5554 --no-resident` succeeded.
   - Manual real-phone OTP test: pending (must be completed on physical device).

---

## Day 5 - Login Screen UI (OTP Flow)

Program goal: implement parent login UI from design source, wire Day 4 AuthService, and support derived dark/tablet variants.

### Commit entries

1. **2026-02-15 22:45:58 +05:30**  
   Commit: `(this commit - see latest git log)`  
   Message: `Implement Day 5 login screen OTP flow and integration [design: parent_login_mobile_light]`  
   Changes:
   - Implemented `lib/screens/login_screen.dart` as a stateful, two-step OTP flow:
     - Phone input step (`Send OTP`)
     - OTP verification step (`Verify OTP`, `Change Number`, `Resend OTP`)
     - Inline loading and error states
   - Wired login actions to `AuthService.sendOTP(...)` and `AuthService.verifyOTP(...)`.
   - Added temporary post-login target in `lib/screens/dashboard_screen.dart`.
   - Updated `lib/main.dart`:
     - Home now points to `LoginScreen`
     - Added `themeMode: ThemeMode.system` and explicit light/dark theme seeds.
   - Updated `test/widget_test.dart` to a Firebase-safe constructibility test for `MyApp`.
   Validation:
   - `flutter analyze` reported no issues.
   - `flutter test` passed.
   - `flutter run -d emulator-5554 --no-resident` built and installed successfully; service protocol connection closed on emulator during attach phase.
   Design folder(s) used:
   - `parent_login_mobile_light`
   - `design_system_tokens_spec`
   - `parent_dashboard_mobile_dark`
   - `parent_dashboard_tablet_light_1`
   Design assets checked:
   - `screen.png`, `code.html`
   UI fidelity note:
   - Matched mobile-light structure and spacing hierarchy; dark/tablet variants were derived from token spec and existing parent dark/tablet patterns while keeping the same component order.

---

## Day 6 - Firestore Setup (Backend-Only)

Program goal: enable Firestore backend with strict owner-only rules and wire parent profile repository into auth flow.

### Commit entries

1. **2026-02-15 23:20:00 +05:30**  
   Commit: `(this commit - see latest git log)`  
   Message: `Set up Firestore backend and parent profile repository`  
   Changes:
   - Provisioned Firestore backend for `trustbridge-navee`:
     - Enabled Firestore API
     - Created `(default)` Firestore Native database in `asia-south1`
   - Added Firebase config files:
     - `.firebaserc` (default project set)
     - `firestore.rules` (strict owner-only rules for `parents` and `children`)
     - `firestore.indexes.json` (minimal baseline)
   - Updated `firebase.json` to include Firestore rules/indexes config while preserving FlutterFire config.
   - Implemented `lib/services/firestore_service.dart`:
     - `ensureParentProfile(...)`
     - `getParentProfile(...)`
     - `watchParentProfile(...)`
   - Refactored `lib/services/auth_service.dart`:
     - Injected/used `FirestoreService`
     - Replaced direct Firestore parent creation with `ensureParentProfile(...)`
   Validation:
   - `firebase firestore:databases:list --project trustbridge-navee --json` succeeded and confirmed `locationId: asia-south1`.
   - `firebase deploy --only firestore:rules,firestore:indexes --project trustbridge-navee` succeeded.
   - `flutter pub get` succeeded.
   - `flutter analyze` passed with no issues.
   - `flutter test` passed.
   - `flutter run -d emulator-5554 --no-resident` could not run because no emulator/device with id `emulator-5554` was available at execution time.
   - Android build fallback validation: `flutter build apk --debug` succeeded.
   Notes:
   - Non-UI commit (design fields not applicable).
   - Manual OTP login + Firestore rules simulator checks: pending (requires running device/emulator + Firebase Console).

---

## Day 7 - Data Models (Week 2 Day 2)

Program goal: implement essential child/policy/schedule data models with Firestore serialization and basic tests.

### Commit entries

1. **2026-02-16 08:36:15 +05:30**  
   Commit: `(this commit - see latest git log)`  
   Message: `Implement Day 7 essential data models`  
   Changes:
   - Created `lib/models/child_profile.dart` with:
     - `ChildProfile` model
     - `AgeBand` enum (`6-9`, `10-13`, `14-17`)
     - Firestore serialization (`fromFirestore`, `toFirestore`)
     - `create(...)` and `copyWith(...)` factories
   - Created `lib/models/schedule.dart` with:
     - `Schedule` model
     - `Day`, `ScheduleType`, `ScheduleAction` enums
     - Bedtime and school factory constructors
     - Firestore serialization (`fromMap`, `toMap`)
   - Created `lib/models/policy.dart` with:
     - `Policy` model
     - age-based presets for young/middle/teen
     - Firestore serialization (`fromMap`, `toMap`)
     - `copyWith(...)`
   - Added `test/models_test.dart` with 6 pragmatic tests covering:
     - child creation
     - policy presets
     - schedule factories
     - serialization shape checks
   Validation:
   - `flutter analyze` passed.
   - `flutter test test/models_test.dart` passed (6/6).
   - All three models support Firestore round-trip serialization maps.
   Notes:
   - Non-UI commit (design fields not applicable).
   - Complex schedule/time logic intentionally deferred.

---

## Current Summary (after Day 7)

- Day 1 completed: foundation, naming, structure, git + GitHub.
- Day 2 completed: dependencies and Provider baseline.
- Day 3 completed: Firebase Android configuration and initialization.
- Day 4 implementation completed in code; real-device OTP validation pending.
- Day 5 completed in code: login screen UI, OTP interaction wiring, dark/tablet derived variants, and app-entry integration.
- Day 6 completed in code and infra: Firestore database/rules/indexes configured, parent profile repository added, and auth integration refactored.
- Day 7 completed in code: essential data models and tests added for child, policy, and schedule domains.

Last updated: 2026-02-16
