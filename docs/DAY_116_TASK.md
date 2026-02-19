# Day 116 Task - NextDNS Setup Flow
**Date:** 2026-02-21  
**Week 24 Day 2**

## Mission
Ship parent-facing NextDNS setup flow so a parent can connect account and map each child to a NextDNS profile.

## Scope
- Build setup UI for API key connection.
- Validate API key by fetching profiles.
- Map each child to existing profile or create a new one.
- Persist setup state and show connection status in settings.

## Implementation Checklist
1. Create or extend `lib/screens/nextdns_setup_screen.dart`:
- API key entry
- connect/validate action
- loading, error, success states
2. Add per-child profile assignment UI:
- list all child profiles
- choose existing NextDNS profile
- create profile for child when missing
3. Persist results:
- secure API key in storage
- child `nextDnsProfileId` in Firestore
4. Update parent settings entry:
- show connected status
- route to setup screen
5. Add tests:
- setup happy path
- invalid key handling
- retry flow
- per-child mapping persistence

## Validation
- Parent can connect key and see profiles.
- Each child has a valid `nextDnsProfileId`.
- `flutter analyze` and `flutter test` pass.

## Deliverables
- NextDNS setup screen implementation
- Settings integration updates
- Setup/mapping widget tests
- Progress journal entry for Day 116

## Notes
- Do not block app usage if setup is incomplete.
- Keep setup resumable after app restart.
