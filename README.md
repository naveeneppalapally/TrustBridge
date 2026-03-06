# TrustBridge App

Privacy-first parental controls for Android, built with Flutter, Firebase, and a native Android VPN layer.

## What It Does

- DNS-based filtering: Blocks inappropriate content at the network level
- Time-based schedules: Bedtime mode, homework mode, school hours
- Usage insights: See what your child is using (not spying on content)
- Request and Approve: Kids can request access, parents approve instantly
- Transparent: Kids know what's blocked and why

## Project Status

This repository is an active working app, not a starter template.

- Parent app and child app flows already exist.
- Firebase Auth, Firestore, FCM, App Check, and Android VPN code are already integrated.
- Ongoing work should preserve existing UX and architecture unless a task explicitly calls for deeper refactoring.

## Tech Stack

- Framework: Flutter 3.x
- Backend: Firebase (Auth, Firestore, FCM)
- DNS Filtering: NextDNS
- Local DB: SQLite
- Platform: Android 7+ (API 24+)

## Target Market

- Primary: Indian families with children aged 6-17
- Secondary: Global markets with similar parenting needs
- Compliance: DPDP Act 2023, Google Play policies

## Development Timeline

- Week 1-2: Authentication and Basic UI
- Week 3-4: Child Management and Policies
- Week 5-6: VPN Service and DNS Filtering
- Week 7-8: Schedules and Usage Tracking
- Week 9-10: Request-Approve and Child App
- Week 11-12: Polish and Launch Prep

## Documentation

- [Product Requirements](docs/PRODUCT_REQUIREMENTS_DOCUMENT.md)
- [Implementation Guide](docs/IMPLEMENTATION_GUIDE.md)
- [Quick Start Checklist](docs/QUICK_START_CHECKLIST.md)
- [Architecture Overview](docs/TRUSTBRIDGE_ARCHITECTURE.md)

## Working Rules

- Repository root is `parental_controls_app/`.
- If a sibling `../app_design/` folder exists, use it as the UI source of truth before changing screens.
- If no matching design exists, preserve the current UI instead of redesigning it.
- Do not commit screenshots, device logs, XML dumps, temp databases, or scratch files.
- Run `flutter analyze` before pushing. Run `flutter test` for non-trivial changes.

## UI Design Source of Truth

- For UI tasks, check `../app_design/` first if that folder exists in your local workspace.
- Use both assets from the selected design folder when available:
  - `screen.png` for the visual target
  - `code.html` for layout and token reference
- If no matching design exists, keep the existing UI stable and avoid introducing a new visual direction without an explicit request.

## Privacy Promise

- No reading of messages or browser history
- No location tracking
- No selling of data
- Parents control what's collected
- Kids see transparency logs

## Developer

Solo developer building in public. Follow the journey.

## License

Copyright (c) 2026. All rights reserved.
