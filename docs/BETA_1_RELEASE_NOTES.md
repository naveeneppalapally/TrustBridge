# TrustBridge Beta 1 Release Notes

Version: `1.0.0-beta.1+114`  
Date: 2026-02-19  
Platform: Android

## What's New Since Alpha

### Stability & platform hardening

- Android 14 VPN/service hardening updates.
- Improved permission and readiness guidance in protection flows.
- Crashlytics and performance instrumentation integrated.

### Onboarding & navigation

- First-time onboarding improvements and setup guidance refinements.
- Parent/child shell navigation structure for clearer flow.
- Settings and security controls redesigned for faster access.

### Parent experience redesign

- Dashboard rebuilt with trust-summary hero and managed-device cards.
- Security quick actions added (pause-all, bedtime shortcut).
- Family management and premium screens introduced.
- DNS analytics and duplicate analytics dashboards expanded.

### Child experience redesign

- Child status and request flows modernized.
- Block overlay and guided tutorial added.
- Motion and micro-animation polish with spring transitions.

### UX polish

- Loading skeleton system added across high-traffic screens.
- Illustrated empty states standardized across list and log experiences.
- Dark theme token alignment and readability fixes.

## Known Issues

1. Full physical Android 14 QA run is pending when device is connected.
2. Beta tester group currently has no tester emails configured yet.

## Beta Feedback

- Use in-app `Settings -> Beta Feedback`.
- Include: device model, Android version, exact steps, expected vs actual behavior.

## High-Priority Beta Validation Areas

1. VPN enable/disable and reboot recovery.
2. Blocked-site overlay and access-request approval loop.
3. Push notification delivery/tap routing.
4. Dark/light visual consistency.
5. Performance smoothness on mid-range Android devices.

## Distribution Status

- Firestore rules deployed to `trustbridge-navee`.
- Release `1.0.0-beta.1 (114)` uploaded to Firebase App Distribution.
- Distributed to App Distribution group: `beta-testers`.
