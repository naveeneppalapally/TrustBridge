# TrustBridge - Days 115 to 120 Task Plan
**Date prepared:** 2026-02-19  
**Inputs compared:**
- `docs/DAYS_85_TO_114_TASK_PLAN.md` (implemented baseline)
- `C:\Users\navee\Downloads\REVISED_DAYS_85_TO_120_PLAN.md` (revised strategy)

---

## 1) 85-114 Discrepancy Audit (Implemented vs Revised)

### A. Areas that align or are largely complete
- Dark theme/token cleanup and readability improvements (implemented around Days 111+).
- Onboarding flow and setup guide implementation (implemented, with current local fallback fixes).
- Android VPN hardening and diagnostics iterations completed in the 85-114 window.
- Parent/child shells exist (`lib/widgets/parent_shell.dart`, `lib/widgets/child_shell.dart`).
- Missing UX screens from the prior plan exist:
  - `lib/screens/blocked_overlay_screen.dart`
  - `lib/screens/child_tutorial_screen.dart`
  - `lib/screens/family_management_screen.dart`
  - `lib/screens/premium_screen.dart`
  - skeleton/empty/polish work.

### B. Partial matches (implemented but not at revised depth)
- Parent/child separation:
  - Revised plan expects strict route/tree and folder split (`/parent/*`, `/child/*`).
  - Current code still keeps many shared screen/service paths.
- Add Device:
  - Current flow in `lib/screens/child_devices_screen.dart` saves device IDs.
  - Revised expects full device onboarding (NextDNS profile mapping, DNS hostname, QR/setup flow).
- Usage reports:
  - `lib/screens/usage_reports_screen.dart` exists.
  - Current screen still uses placeholder values; revised expects real UsageStats-backed data.

### C. Clear gaps vs revised plan (not implemented in 85-114 scope)
- Full NextDNS API integration layer is missing:
  - Current `lib/services/nextdns_service.dart` only validates/formats profile IDs.
  - No service/category toggle API PATCH flow, denylist/allowlist sync, or analytics pull.
- Real Android UsageStatsManager pipeline is missing:
  - No `PACKAGE_USAGE_STATS` permission flow or native usage stats method channel.
- NextDNS-backed analytics/logs are not fully wired:
  - DNS logs/analytics currently do not reflect full live NextDNS API-backed coverage from revised plan.
- Temporary access pass lifecycle is not fully NextDNS allowlist-driven end-to-end:
  - Approval flow needs explicit allowlist add/remove automation and expiry worker alignment per revised plan.

---

## 2) Execution Plan for Days 115-120

## Day 115 - 2026-02-20
**Theme:** NextDNS foundation and secure account model  
**Goal:** Add production-grade NextDNS API service and secure key handling.

**Tasks**
1. Create `lib/services/nextdns_api_service.dart` with methods for:
- profile fetch/create
- service/category toggle patch
- denylist/allowlist add/remove
- analytics status/domain queries
2. Add secure API key storage using `flutter_secure_storage`.
3. Add Firestore schema fields for per-child `nextDnsProfileId`.
4. Add unit tests: `test/services/nextdns_api_service_test.dart`.

**Validation**
- `flutter analyze`
- `flutter test`
- Manual API smoke against a test profile.

---

## Day 116 - 2026-02-21
**Theme:** Parent NextDNS setup flow  
**Goal:** Parent can connect NextDNS account and map each child to a profile.

**Tasks**
1. Build `lib/screens/nextdns_setup_screen.dart`:
- API key connect and validation
- profile list fetch
- per-child profile link/create
2. Add migration helper for existing children without `nextDnsProfileId`.
3. Add Settings entry point and status card update.
4. Add widget tests for connect/link/error states.

**Validation**
- Parent can connect key.
- Each child has a valid linked profile ID.

---

## Day 117 - 2026-02-22
**Theme:** Real blocking controls wiring  
**Goal:** Category/service toggles actually call NextDNS APIs.

**Tasks**
1. Extend policy UI to include service-level toggles (YouTube, TikTok, Instagram, etc.).
2. Wire category toggles to NextDNS category endpoints.
3. Add SafeSearch, YouTube Restricted Mode, and block-bypass toggles.
4. Add retry and offline queue behavior for failed API writes.
5. Add integration tests around policy-save workflows.

**Validation**
- Toggle in app -> NextDNS profile reflects change.
- Blocking behavior updates on device after policy sync.

---

## Day 118 - 2026-02-23
**Theme:** Add Device v2 (actual onboarding)  
**Goal:** Fix Add Device flow end-to-end.

**Tasks**
1. Build Device Setup Wizard:
- per-child hostname display (`{profileId}.dns.nextdns.io`)
- copy/share actions
- QR code for setup instructions
2. Add device verification step (last seen handshake + profile mapping confirmation).
3. Persist device metadata (model, alias, lastSeen, profileId link).
4. Update `child_devices_screen` to use new setup model.

**Validation**
- New device can be configured from wizard and verified in app.

---

## Day 119 - 2026-02-24
**Theme:** Real telemetry and analytics  
**Goal:** Remove remaining mock metrics and use real usage/network data.

**Tasks**
1. Integrate Android UsageStatsManager:
- manifest permission declaration
- native method channel
- permission prompt flow
2. Replace hardcoded Usage Reports values with real usage aggregates.
3. Enhance DNS analytics/logs:
- fetch top blocked/allowed domains
- real query counts and trends from NextDNS/local telemetry
4. Add fallback empty states when permissions are denied.

**Validation**
- Reports show real values (or explicit unavailable state), no fake metrics.

---

## Day 120 - 2026-02-25
**Theme:** E2E hardening + Beta 2 readiness  
**Goal:** Close revised-plan gaps and prepare next beta cut.

**Tasks**
1. Complete strict parent/child route hardening and access checks.
2. Finalize temporary access pass lifecycle:
- approve -> allowlist add
- expiry/end-now -> allowlist remove
3. Run full regression checklist and targeted physical-device QA.
4. Prepare Beta 2 release notes and rollout checklist.
5. Update `docs/PROGRESS_JOURNAL.md` with 115-120 progress entries.

**Validation**
- `flutter analyze` clean
- `flutter test` full pass
- device QA critical paths pass
- beta artifact ready.

---

## 3) Priority Order (Must-Do Sequence)
1. Day 115
2. Day 116
3. Day 117
4. Day 118
5. Day 119
6. Day 120

Rationale: revised-plan core value is real, parent-controlled blocking. Days 115-117 unlock that; 118-119 operationalize it; 120 stabilizes and ships.
