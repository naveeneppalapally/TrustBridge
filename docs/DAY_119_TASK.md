# Day 119 Task - Real Telemetry and Reports
**Date:** 2026-02-24  
**Week 24 Day 5**

## Mission
Remove remaining mock metrics and power reports with real device/network telemetry.

## Scope
- Integrate Android usage stats permission and data pipeline.
- Replace usage report placeholders with real aggregates.
- Improve DNS analytics/log screens with real metrics.
- Add graceful fallback when permissions are unavailable.

## Implementation Checklist
1. Integrate UsageStatsManager pipeline:
- Android permission declaration
- method channel hooks
- Flutter service wrapper
2. Add user permission flow:
- explain why usage access is needed
- route to usage access settings
- handle denied state cleanly
3. Update `usage_reports_screen`:
- real totals and trend calculations
- remove hardcoded values
4. Improve DNS analytics/logs:
- real blocked/allowed counts
- top domains and trend data
5. Add tests:
- parsing and aggregation logic
- denied permission UI state
- report rendering with real data models

## Validation
- Reports show real data or explicit unavailable state.
- No fake static numbers remain in core report widgets.
- `flutter analyze` and `flutter test` pass.

## Deliverables
- Usage stats native + Flutter integration
- Updated reports and analytics screens
- Tests for telemetry/report data paths
- Progress journal entry for Day 119

## Notes
- Respect privacy constraints and minimize retained raw data.
- Keep analytics performant on low-end devices.
