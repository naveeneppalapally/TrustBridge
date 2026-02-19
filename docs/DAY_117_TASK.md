# Day 117 Task - Blocking Controls Wiring
**Date:** 2026-02-22  
**Week 24 Day 3**

## Mission
Make blocking controls real: toggles in app must update NextDNS profiles and affect filtering behavior.

## Scope
- Service-level blocking toggles (YouTube, TikTok, Instagram, etc.).
- Category-level blocking toggles.
- SafeSearch, YouTube Restricted Mode, and block-bypass controls.
- Retry and fallback handling for failed writes.

## Implementation Checklist
1. Extend policy UI to include service toggles with clear states.
2. Wire service toggles to NextDNS service endpoints.
3. Wire category toggles to NextDNS category endpoints.
4. Add parental control toggles:
- SafeSearch
- YouTube Restricted Mode
- Block bypass
5. Add robust error handling:
- optimistic update rollback on failure
- retry action
- offline-safe messaging
6. Add tests:
- policy save success
- API failure rollback
- toggle state persistence

## Validation
- Toggle in app updates NextDNS profile.
- Changes take effect after policy sync.
- `flutter analyze` and `flutter test` pass.

## Deliverables
- Updated policy and blocking screens
- NextDNS wiring in service layer usage points
- Integration/unit tests for control flows
- Progress journal entry for Day 117

## Notes
- Prioritize deterministic state over aggressive UI optimism.
- Keep all failed syncs visible to parent.
