# TrustBridge Workflow And Data Reference

Last updated: 2026-02-20
Codebase: `parental_controls_app`

## 1) Executive Summary

TrustBridge currently runs in a **hybrid protection model**:

1. **Local VPN model (always available)**: on-device DNS filtering and policy enforcement.
2. **NextDNS model (optional, profile-linked)**: cloud-side policy controls, analytics, and denylist/service controls.

If NextDNS is disabled or not configured, the app still works through the local model.

## 2) App Workflow (High Level)

| Stage | What happens | Key files |
|---|---|---|
| App startup | Firebase init, Crashlytics/Performance init, MaterialApp boot | `lib/main.dart` |
| Auth routing | Logged-out -> Login, logged-in -> onboarding check -> Parent shell | `lib/main.dart` |
| Onboarding | New parent completes setup flow before dashboard | `lib/screens/onboarding_screen.dart` |
| Parent shell navigation | 5 tabs: Dashboard, Schedule, Reports, Block Apps, Settings | `lib/widgets/parent_shell.dart` |
| Policy changes | Parent edits categories/domains/schedules | `lib/screens/block_categories_screen.dart`, `lib/screens/schedule_creator_screen.dart` |
| Runtime enforcement | Policy sync service pushes rules to VPN | `lib/services/policy_vpn_sync_service.dart`, `lib/services/vpn_service.dart` |
| Request flow | Child sends request, parent approves/denies, policy sync updates | `lib/models/access_request.dart`, `lib/services/firestore_service.dart` |
| Notifications | FCM token saved, queue doc created, notification opens parent requests | `lib/services/notification_service.dart`, `lib/services/firestore_service.dart` |

## 3) Parent-Side User Flow

## 3.1 Login And Launch

1. Parent signs in.
2. App ensures parent profile exists in Firestore.
3. Onboarding completion is checked (cloud + local reconciliation).
4. Parent lands in `ParentShell` when onboarding is complete.

## 3.2 ParentShell Tab Flow

| Tab | Purpose | Main screen |
|---|---|---|
| Dashboard | Overview, child cards, quick actions | `DashboardScreen` |
| Schedule | Routine/rules time windows | `ScheduleCreatorScreen` |
| Reports | Usage + NextDNS analytics card | `UsageReportsScreen` |
| Block Apps | Category/domain controls (merged with NextDNS controls) | `BlockCategoriesScreen` |
| Settings | Account, privacy, security controls, NextDNS setup access | `ParentSettingsScreen` |

## 3.3 Block Apps Flow (Merged Local + NextDNS)

When child has `nextDnsProfileId`, the same screen manages both:

1. Local category/domain toggles (for VPN filtering).
2. NextDNS service/category toggles.
3. SafeSearch / YouTube restricted / bypass toggles.
4. Domain denylist add/remove on NextDNS.
5. Persisted `nextDnsControls` on child profile.

If NextDNS is not linked, local controls still work.

## 3.4 Access Request Flow

1. Child submits access request under parent subcollection.
2. Parent views pending requests.
3. Parent approves/denies (optional duration/reply).
4. Sync service refreshes active exception domains for VPN.
5. Expiry transitions request to expired behavior.

## 4) Child And Device Workflow

## 4.1 Child Profile Lifecycle

1. Parent creates child (age band preset policy).
2. Child document stores policy, device IDs, optional NextDNS profile ID.
3. Parent can update categories/domains/schedules.

## 4.2 Child Device + NextDNS Setup

Child device flow supports:

1. Device ID assignment to child.
2. NextDNS hostname display and QR code.
3. Deep link to Android private DNS settings.
4. Verification via `https://test.nextdns.io`.

## 5) Data Model Tables

## 5.1 Firestore Collections (Current)

| Path | Purpose | Access pattern |
|---|---|---|
| `parents/{parentId}` | Parent account/profile/preferences/security/onboarding | owner read/write |
| `children/{childId}` | Child profiles and policy | filtered by `parentId` in app logic |
| `parents/{parentId}/access_requests/{requestId}` | Access request inbox/history | parent + child-device workflow |
| `notification_queue/{docId}` | Queue payload for push processing | client write, backend processing |
| `supportTickets/{ticketId}` | Feedback/support/duplicate workflow | parent-scoped queries |

## 5.2 Parent Document Key Fields

| Field | Type | Notes |
|---|---|---|
| `parentId` | string | uid linkage |
| `phone` | string? | auth phone |
| `subscription` | map | tier/validity/renewal |
| `preferences.language` | string | UI language |
| `preferences.biometricLoginEnabled` | bool | app lock convenience |
| `preferences.vpnProtectionEnabled` | bool | parent preference flag |
| `preferences.nextDnsEnabled` | bool | NextDNS feature toggle |
| `preferences.nextDnsProfileId` | string? | profile reference |
| `fcmToken` | string? | push token |
| `onboardingComplete` | bool | launch routing gate |
| `security.*` | map | pin/two-factor/session metadata |

## 5.3 Child Document Key Fields

| Field | Type | Notes |
|---|---|---|
| `id` | string | document id |
| `parentId` | string | ownership binding |
| `nickname` | string | child display name |
| `ageBand` | string | `6-9`, `10-13`, `14-17` |
| `deviceIds` | list<string> | linked devices |
| `policy` | map | categories/domains/schedules/safe-search |
| `nextDnsProfileId` | string? | optional NextDNS profile |
| `nextDnsControls` | map | merged NextDNS toggle state |
| `pausedUntil` | timestamp? | global pause control |

## 5.4 Access Request Fields

| Field | Type | Notes |
|---|---|---|
| `childId` | string | child reference |
| `parentId` | string | parent reference |
| `childNickname` | string | denormalized display |
| `appOrSite` | string | requested target |
| `durationMinutes` | int? | nullable for schedule-end |
| `durationLabel` | string | user-facing duration |
| `reason` | string? | optional child reason |
| `status` | string | `pending/approved/denied/expired` |
| `parentReply` | string? | optional parent message |
| `requestedAt` | timestamp | created time |
| `respondedAt` | timestamp? | parent action time |
| `expiresAt` | timestamp? | approval expiry |

## 5.5 Notification Queue Fields

| Field | Type | Notes |
|---|---|---|
| `parentId` | string | destination parent |
| `title` | string | notification title |
| `body` | string | notification body |
| `route` | string | deep-link route |
| `sentAt` | timestamp | enqueue time |
| `processed` | bool | backend processing flag |

## 6) NextDNS Integration Details

## 6.1 Local To NextDNS Category Mapping

| Local category id | NextDNS category id |
|---|---|
| `social-networks` | `social-networks` |
| `games` | `games` |
| `streaming` | `streaming` |
| `adult-content` | `porn` |

## 6.2 Service Toggles Currently Wired

| Service id |
|---|
| `youtube` |
| `instagram` |
| `tiktok` |
| `facebook` |
| `netflix` |
| `roblox` |

## 6.3 DNS Upstream Defaults (Native)

| Role | Value |
|---|---|
| Primary anycast | `45.90.28.0` |
| Secondary anycast | `45.90.30.0` |

These defaults are set in native VPN code and used to avoid Google DNS bypass.

## 7) Sync And Enforcement Workflow

1. Parent changes policy.
2. Firestore updates child policy.
3. `PolicyVpnSyncService` listens and triggers sync.
4. Sync aggregates categories/domains + active approved exceptions.
5. `VpnService` receives rule update.
6. Active VPN applies new rule set.

Important: sync can also be triggered by access-request state changes.

## 8) Observability And Reliability

| Area | What is implemented |
|---|---|
| Crash tracking | Firebase Crashlytics + user/custom keys |
| Performance | Firebase Performance traces and custom trace points |
| Push notifications | FCM token save + refresh handling |
| Security | App lock PIN/biometric, Firestore rules hardening |
| Testing | Widget/service tests + analyzer clean baseline |

## 9) Build/Test Workflow

| Command | Purpose |
|---|---|
| `flutter analyze` | static checks |
| `flutter test` | full test suite |
| `flutter build apk --release --target-platform android-arm64` | release artifact |

Release APK location:

`build/app/outputs/flutter-apk/app-release.apk`

## 10) Important Points (Do Not Miss)

1. App is hybrid; NextDNS is not the only enforcement path.
2. NextDNS requires profile linkage (`nextDnsProfileId`) for per-child controls.
3. Keep Firestore parent and child ownership constraints strict.
4. Do not show fake usage numbers; show permission/empty states.
5. Policy changes must always be followed by sync verification.
6. Validate on real device for VPN and private DNS behaviors.
7. Keep API keys in secure storage only; never hardcode.
8. Preserve signing config secrets outside git.
9. Use release APK for real QA, not debug.
10. Keep `PROGRESS_JOURNAL.md` updated per implemented batch.

## 11) Recommended QA Scenarios (Fast)

1. Login -> onboarding -> parent shell tab navigation.
2. Block Apps tab: toggle category and verify sync.
3. Request flow: child request -> parent approve -> expiry behavior.
4. Usage Reports with and without Usage Access permission.
5. NextDNS linked child: service toggle + domain denylist + verify endpoint.
6. VPN start/stop and telemetry refresh.

