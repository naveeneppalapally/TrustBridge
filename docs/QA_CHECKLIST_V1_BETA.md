# TrustBridge QA Checklist (v1 Beta)

Date: 2026-02-19  
Owner: Codex + Navee

## Environment

- Device discovery run: `flutter devices`
- Available in this run:
  - Windows desktop
  - Chrome
  - Edge
- Android 14 physical device: **not connected during this run**.

## Automated QA Snapshot

- `flutter analyze`: PASS
- `flutter test`: PARTIAL (suite mostly green, 3 known failures in `test/navigation_test.dart`)

Known failing tests:
1. `Navigation Tests AddChildScreen can be instantiated`
2. `Navigation Tests ChildDetailScreen displays child info`
3. `Navigation Tests Back button navigation works`

Reason: outdated text expectations after UI copy/layout redesigns.

## Flow Checklist

### Onboarding

- [x] Onboarding screen tests pass
- [x] Revisit entry from Settings exists
- [ ] Fresh-install Android 14 validation (manual, physical device pending)
- [ ] Skip flow Android 14 validation (manual, physical device pending)

### VPN Flow

- [x] VPN screen widget tests pass (permission/start/stop/sync/test hooks)
- [x] DNS query log screen tests pass (incognito + clear + empty state)
- [ ] Android system VPN permission dialog validation (manual, physical device pending)
- [ ] Blocked domain live interception validation (manual, physical device pending)
- [ ] Reboot recovery validation (manual, physical device pending)

### Request/Approval Flow

- [x] Child request screen tests pass
- [x] Parent requests screen tests pass
- [x] Active approved-access rendering tests pass
- [ ] Push notification on physical devices validation (manual, physical device pending)

### Theme / UI

- [x] Light/dark token tests pass (`app_theme_test.dart`, `dark_theme_test.dart`)
- [x] Dashboard/Settings/VPN dark-mode widget tests pass
- [ ] Android 14 system-theme switch visual QA (manual, physical device pending)

### Motion / Animations

- [x] Spring utility tests pass (`spring_animation_test.dart`)
- [x] Animated screens compile and widget tests pass
- [ ] 60fps verification on Android physical hardware (manual, physical device pending)

## Pre-Beta Manual Run Plan (When Android Device is Connected)

1. `flutter run -d <android-device-id>`
2. Run onboarding fresh-install checklist.
3. Run VPN real-network checklist (blocked/allowed/exception expiry/reboot).
4. Run request-notification-approval loop across child/parent devices.
5. Capture any Crashlytics entries and attach screenshots.

## Sign-off

- Automated gate (analyze): PASS
- Automated gate (tests): PARTIAL, non-critical navigation-test expectations need update
- Physical Android 14 gate: PENDING
