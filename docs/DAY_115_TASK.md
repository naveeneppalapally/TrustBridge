# Day 115 Task - NextDNS API Foundation
**Date:** 2026-02-20  
**Week 24 Day 1**

## Mission
Build a production-grade NextDNS integration foundation with secure key handling and per-child profile support.

## Scope
- Create a real NextDNS API service layer.
- Store and read NextDNS API key securely.
- Prepare Firestore model fields for per-child profile mapping.
- Add tests for service behavior and API failure handling.

## Implementation Checklist
1. Create `lib/services/nextdns_api_service.dart` with:
- profile fetch/create methods
- service/category toggle methods
- denylist/allowlist add/remove methods
- analytics status/domain query methods
2. Use `flutter_secure_storage` for API key read/write:
- `setNextDnsApiKey()`
- `getNextDnsApiKey()`
- `clearNextDnsApiKey()`
3. Update Firestore shape:
- add `nextDnsProfileId` on child docs
- add parent-level metadata needed for setup status
4. Add tests:
- `test/services/nextdns_api_service_test.dart`
- include success, timeout, auth failure, invalid profile scenarios
5. Add minimal logging and error normalization for UI-friendly errors.

## Validation
- `flutter analyze` passes.
- `flutter test` passes.
- Manual smoke call works against a test NextDNS profile.

## Deliverables
- `lib/services/nextdns_api_service.dart`
- Any required model/service updates for secure key storage
- `test/services/nextdns_api_service_test.dart`
- Progress journal entry for Day 115

## Notes
- Do not store NextDNS API key in plain Firestore.
- Keep networking retry-safe and non-blocking for UI.
