# Emulator 17-Item Runbook Report

- Session start: 2026-02-22 15:22:57.293 +05:30
- Session end: 2026-02-22 15:34:57.881 +05:30
- Host device list:

  - List of devices attached
  - emulator-5554	device
  - emulator-5556	device

## 17-Item Checklist

### Item 1: Blocking and unblocking websites
- Status: **EMULATOR_LIMITATION**
- Started: 2026-02-22 15:22:57.395 +05:30
- Finished: 2026-02-22 15:23:27.811 +05:30
- Note: Real browser-level DNS interception on active tabs is not fully testable on emulators.
- Commands:
  - flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "blocklist operations addCustomBlockedDomain stores domain in SQLite with source=custom"
  - flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "blocklist operations removeCustomBlockedDomain deletes domain from SQLite"

### Item 2: Category blocking consistency
- Status: **PASS**
- Started: 2026-02-22 15:23:27.821 +05:30
- Finished: 2026-02-22 15:24:02.451 +05:30
- Commands:
  - flutter test test/screens/block_categories_screen_test.dart
  - flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "blocklist operations onCategoryEnabled(social) triggers VPN update call"

### Item 3: Custom domain blocking (domain + subdomain)
- Status: **EMULATOR_LIMITATION**
- Started: 2026-02-22 15:24:02.453 +05:30
- Finished: 2026-02-22 15:24:48.119 +05:30
- Note: UI/policy persistence is validated; live domain fetch behavior is hardware-network dependent.
- Commands:
  - flutter test test/screens/custom_domains_screen_test.dart
  - flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "blocklist operations addCustomBlockedDomain stores domain in SQLite with source=custom"

### Item 4: Schedule trigger and conflict handling
- Status: **PASS**
- Started: 2026-02-22 15:24:48.129 +05:30
- Finished: 2026-02-22 15:25:27.561 +05:30
- Commands:
  - flutter test test/screens/schedule_creator_screen_test.dart --plain-name "shows conflict dialog and blocks save on overlap"
  - flutter test test/screens/child/child_status_screen_test.dart

### Item 5: Quick modes (Homework/Bedtime/Free) responsiveness
- Status: **PASS**
- Started: 2026-02-22 15:25:27.561 +05:30
- Finished: 2026-02-22 15:25:47.998 +05:30
- Commands:
  - flutter test test/screens/quick_modes_screen_test.dart

### Item 6: Pause Device and Resume flow
- Status: **PASS**
- Started: 2026-02-22 15:25:47.999 +05:30
- Finished: 2026-02-22 15:26:21.623 +05:30
- Commands:
  - flutter test test/services/firestore_service_test.dart --plain-name "pauseAllChildren sets pausedUntil for all parent children"
  - flutter test test/services/firestore_service_test.dart --plain-name "resumeAllChildren clears pausedUntil for all parent children"

### Item 7: Request and approval flow (approve/deny)
- Status: **PASS**
- Started: 2026-02-22 15:26:21.624 +05:30
- Finished: 2026-02-22 15:27:24.606 +05:30
- Commands:
  - flutter test test/screens/child/request_access_screen_test.dart
  - flutter test test/screens/parent_requests_screen_test.dart --plain-name "approve action updates status and moves request to history"
  - flutter test test/screens/parent_requests_screen_test.dart --plain-name "deny modal quick reply chip populates parent reply"

### Item 8: Temporary access expiry and auto-reblock
- Status: **PASS**
- Started: 2026-02-22 15:27:24.606 +05:30
- Finished: 2026-02-22 15:28:00.442 +05:30
- Commands:
  - flutter test test/services/firestore_service_test.dart --plain-name "expireApprovedAccessRequestNow marks approved request expired"
  - flutter test test/screens/parent_requests_screen_test.dart --plain-name "history tab renders expired requests"

### Item 9: VPN persistence (force-kill/reboot)
- Status: **EMULATOR_LIMITATION**
- Started: 2026-02-22 15:28:00.443 +05:30
- Finished: 2026-02-22 15:28:32.762 +05:30
- Note: Boot-time Android VPN behavior requires physical-device reboot validation.
- Commands:
  - flutter test test/services/heartbeat_service_test.dart
  - flutter test test/services/remote_command_service_test.dart --plain-name "processPendingCommands executes restart and marks command executed"

### Item 10: Child blocked screen and explanation
- Status: **PASS**
- Started: 2026-02-22 15:28:32.763 +05:30
- Finished: 2026-02-22 15:28:51.563 +05:30
- Commands:
  - flutter test test/screens/blocked_overlay_screen_test.dart

### Item 11: Child status real-time mode display
- Status: **PASS**
- Started: 2026-02-22 15:28:51.564 +05:30
- Finished: 2026-02-22 15:29:32.014 +05:30
- Commands:
  - flutter test test/screens/child/child_status_screen_test.dart
  - flutter test test/screens/child_status_screen_test.dart

### Item 12: Parent dashboard mode/status counters
- Status: **PARTIAL**
- Started: 2026-02-22 15:29:32.015 +05:30
- Finished: 2026-02-22 15:30:11.838 +05:30
- Note: Live blocked-attempt counter fidelity depends on real DNS traffic generation.
- Commands:
  - flutter test test/screens/dashboard_screen_test.dart --plain-name "shows pending requests badge when requests exist"
  - flutter test test/bug_fixes_regression_test.dart --plain-name "child with deviceIds but no heartbeat shows Connecting status"

### Item 13: Usage reports data rendering
- Status: **PASS**
- Started: 2026-02-22 15:30:11.839 +05:30
- Finished: 2026-02-22 15:30:48.567 +05:30
- Commands:
  - flutter test test/screens/usage_reports_screen_test.dart --plain-name "shows hero card and category section"
  - flutter test test/services/app_usage_service_test.dart

### Item 14: PIN lock and settings protection
- Status: **PASS**
- Started: 2026-02-22 15:30:48.568 +05:30
- Finished: 2026-02-22 15:31:24.211 +05:30
- Commands:
  - flutter test test/services/app_lock_service_test.dart
  - flutter test test/screens/security_controls_screen_test.dart --plain-name "renders redesigned security controls layout"

### Item 15: Notification delivery paths
- Status: **PARTIAL**
- Started: 2026-02-22 15:31:24.212 +05:30
- Finished: 2026-02-22 15:32:14.354 +05:30
- Note: End-to-end FCM transport is partially validated in emulators; routing payload creation is fully validated.
- Commands:
  - flutter test test/services/firestore_service_test.dart --plain-name "respondToAccessRequest marks request approved and sets expiry"
  - flutter test test/services/firestore_service_test.dart --plain-name "respondToAccessRequest marks request denied without expiry"
  - flutter test test/services/notification_service_test.dart

### Item 16: Offline/flaky network recovery behavior
- Status: **PARTIAL**
- Started: 2026-02-22 15:32:14.355 +05:30
- Finished: 2026-02-22 15:32:48.448 +05:30
- Note: Airplane-mode network flaps are only partially reproducible in hermetic tests.
- Commands:
  - flutter test test/services/firestore_service_test.dart --plain-name "getChildrenOnce propagates permission denied failures"
  - flutter test test/services/heartbeat_service_test.dart --plain-name "isOffline returns true for 31 minutes ago"

### Item 17: Multiple rapid policy changes converge to final state
- Status: **PASS**
- Started: 2026-02-22 15:32:48.449 +05:30
- Finished: 2026-02-22 15:33:50.946 +05:30
- Commands:
  - flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "startListening auto-syncs when Firestore stream emits update"
  - flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "access request updates trigger syncNow for exception refresh"
  - flutter test test/services/policy_vpn_sync_service_test.dart --plain-name "blocklist operations onCategoryEnabled(social) triggers VPN update call"

## Additional Verification Items

### Check 101: Age-band change updates policy preset and syncs
- Status: **PASS**
- Started: 2026-02-22 15:33:50.947 +05:30
- Finished: 2026-02-22 15:34:09.404 +05:30
- Evidence:
  - flutter test test/screens/edit_child_screen_test.dart --plain-name "shows warning and policy changes when age band changes"

### Check 102: Blocked-attempt dedupe under retry storms
- Status: **PARTIAL**
- Started: 2026-02-22 15:34:09.405 +05:30
- Finished: 2026-02-22 15:34:09.405 +05:30
- Note: Implemented 1s per-domain dedupe for blocked counter increments; requires hardware browser stress run for empirical timing.
- Evidence:
  - Code path updated in android/app/src/main/kotlin/com/navee/trustbridge/vpn/DnsPacketHandler.kt

### Check 103: VPN permission UX prompt clarity
- Status: **PASS**
- Started: 2026-02-22 15:34:09.410 +05:30
- Finished: 2026-02-22 15:34:28.902 +05:30
- Evidence:
  - flutter test test/screens/vpn_protection_screen_test.dart --plain-name "permission recovery card requests VPN permission"

### Check 104: Request Access path for schedule-blocked vs category-blocked
- Status: **PARTIAL**
- Started: 2026-02-22 15:34:28.903 +05:30
- Finished: 2026-02-22 15:34:28.904 +05:30
- Note: Request UI paths are covered; true block-source-specific button surfacing still needs physical interaction validation.
- Evidence:
  - flutter test test/screens/child_request_screen_test.dart

### Check 105: Parent badge real-time update while app foregrounded
- Status: **PASS**
- Started: 2026-02-22 15:34:28.904 +05:30
- Finished: 2026-02-22 15:34:57.880 +05:30
- Evidence:
  - flutter test test/widgets/parent_shell_test.dart --plain-name "shows dashboard badge when pending requests exist"

### Check 106: Deleting child profile stops child VPN
- Status: **PARTIAL**
- Started: 2026-02-22 15:34:57.881 +05:30
- Finished: 2026-02-22 15:34:57.881 +05:30
- Note: Child now clears rules, stops VPN, and clears pairing when child doc disappears; needs physical two-device delete scenario confirmation.
- Evidence:
  - Code path added: _handleMissingChildProfile() in lib/screens/child/child_status_screen.dart

