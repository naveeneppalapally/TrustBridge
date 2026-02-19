# Day 118 Task - Add Device v2
**Date:** 2026-02-23  
**Week 24 Day 4**

## Mission
Fix Add Device end-to-end with real setup guidance, profile linkage, and verification.

## Scope
- Replace plain device-id entry with guided setup.
- Provide child-specific DNS hostname instructions.
- Add copy/share and QR-driven setup helper.
- Persist richer device metadata and verification state.

## Implementation Checklist
1. Build Device Setup Wizard:
- child selection
- display `{profileId}.dns.nextdns.io`
- copy and share actions
- QR section for setup instructions
2. Add verification flow:
- mark setup complete after verification handshake/check
- show verified/pending status in UI
3. Persist device metadata:
- alias
- model/manufacturer (when available)
- linked child/profile
- `lastSeenAt`
4. Update `child_devices_screen` to new model and actions.
5. Add tests:
- wizard steps
- device add/verify transitions
- metadata persistence

## Validation
- A new device can be onboarded from app instructions.
- Device appears under correct child with status.
- `flutter analyze` and `flutter test` pass.

## Deliverables
- Device wizard UI and supporting logic
- Updated child device management screen
- Tests for onboarding and persistence
- Progress journal entry for Day 118

## Notes
- Keep legacy device-id entries readable/migratable.
- Do not break existing child-device associations.
