# Two-Device Authenticated Acceptance Report

- Session start: 2026-02-25 10:55:27.042 +05:30
- Session end: 2026-02-25 11:09:42.327 +05:30
- Overall status: **FAIL**
- Run ID: 202602251055277527
- Parent device: 13973155520008G
- Child device: aae47d3e

## Executed Flow

1. Parent setup role (parent_setup) on parent device
2. Child validation role (child_validate) on child device
3. Parent verification role (parent_verify) on parent device

All steps were executed against the live Firebase project on physical devices.

## Failure

- Details: Command failed with exit code 1: flutter test integration_test/two_device_authenticated_acceptance_test.dart -d 13973155520008G --dart-define=TB_ROLE=parent_verify --dart-define=TB_RUN_ID=202602251055277527 --dart-define=TB_USE_EMULATORS=false

