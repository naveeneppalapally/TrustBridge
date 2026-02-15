# Project Dependencies

This document explains why each dependency was added and how it's used.

## Firebase Packages

### firebase_core (^2.24.2)
**Purpose:** Core Firebase functionality  
**Used for:** Initializing Firebase in main.dart  
**First used:** Week 1 Day 3  
**Critical:** Yes - Nothing else works without this

### firebase_auth (^4.15.3)
**Purpose:** User authentication  
**Used for:** Phone number OTP login  
**First used:** Week 1 Day 4  
**Critical:** Yes - App requires authentication

### cloud_firestore (^4.13.6)
**Purpose:** Cloud database  
**Used for:** Storing child profiles, policies, schedules, usage reports  
**First used:** Week 2 Day 1  
**Critical:** Yes - All data storage

### firebase_messaging (^14.7.9)
**Purpose:** Push notifications  
**Used for:** Notifying parents when child requests access  
**First used:** Week 9 Day 3  
**Critical:** No - App works without it, but UX is worse

---

## State Management

### provider (^6.1.1)
**Purpose:** State management  
**Used for:** Managing auth state, child profiles, current policy  
**First used:** Week 2 Day 5  
**Critical:** Yes - Makes app architecture clean

**Why Provider?**
- Recommended by Flutter team
- Simpler than BLoC or Redux
- Perfect for medium-sized apps
- Well-documented

---

## HTTP & API

### http (^1.1.2)
**Purpose:** HTTP client  
**Used for:** Calling NextDNS API to configure DNS policies  
**First used:** Week 6 Day 3  
**Critical:** No - Only if using NextDNS integration

---

## Local Storage

### shared_preferences (^2.2.2)
**Purpose:** Simple key-value storage  
**Used for:** Saving "is logged in", "last opened child", onboarding status  
**First used:** Week 1 Day 5  
**Critical:** Yes - For user preferences

### sqflite (^2.3.0)
**Purpose:** Local SQLite database  
**Used for:** Blocklist (10,000+ domains), usage logs, blocked attempts  
**First used:** Week 6 Day 1  
**Critical:** Yes - DNS filtering needs fast local lookup

### path (^1.8.3)
**Purpose:** File path utilities  
**Used for:** Finding correct database file location on Android  
**First used:** Week 6 Day 1  
**Critical:** Yes - Required by sqflite

---

## Utilities

### intl (^0.18.1)
**Purpose:** Internationalization  
**Used for:** Date/time formatting, currency (for premium), number formatting  
**First used:** Week 2 Day 3  
**Critical:** No - But makes dates look professional

**Examples:**
```dart
DateFormat('hh:mm a').format(DateTime.now());  // 9:30 PM
DateFormat('MMM dd, yyyy').format(date);       // Jan 15, 2024
```

### uuid (^4.2.2)
**Purpose:** Generate unique IDs  
**Used for:** Child profile IDs, policy IDs, request IDs  
**First used:** Week 3 Day 1  
**Critical:** Yes - Firestore needs unique document IDs

**Example:**
```dart
final childId = Uuid().v4();  // e.g., "f47ac10b-58cc-4372-a567-0e02b2c3d479"
```

---

## UI Packages

### fl_chart (^0.65.0)
**Purpose:** Beautiful charts  
**Used for:** Usage reports (daily usage chart, category breakdown)  
**First used:** Week 8 Day 3  
**Critical:** No - Could use text reports instead

**Why fl_chart?**
- Flutter native (fast)
- Beautiful out of the box
- Highly customizable
- Active maintenance

### shimmer (^3.0.0)
**Purpose:** Loading animations  
**Used for:** While loading child list, reports, schedules  
**First used:** Week 2 Day 4  
**Critical:** No - Could use CircularProgressIndicator instead

**Why shimmer?**
- Looks professional
- Users know data is loading
- Better UX than blank screens

---

## Development Dependencies

### flutter_test
**Purpose:** Testing framework  
**Included by default**

### flutter_lints (^3.0.1)
**Purpose:** Dart code quality rules  
**Used for:** Keeping code clean and consistent  
**Critical:** No - But highly recommended

---

## Packages We Considered But Didn't Add

### dio (HTTP client)
**Why not:** `http` package is simpler and sufficient for our needs

### get (State management)
**Why not:** Provider is more standard and better documented

### hive (Local database)
**Why not:** SQLite is more powerful for our blocklist needs

### go_router (Navigation)
**Why not:** Named routes are sufficient for our app size

---

## Total Package Count

- **Production dependencies:** 13
- **Dev dependencies:** 2
- **Total:** 15

**App size impact:** ~8-10 MB  
**Build time impact:** +30-60 seconds first time

---

## Update Strategy

**When to update packages:**
- Security vulnerabilities announced
- Major features needed
- Every 3-6 months for maintenance

**How to check for updates:**
```bash
flutter pub outdated
```

**How to update:**
```bash
flutter pub upgrade
```

**Never update packages:**
- Right before a launch
- Without testing thoroughly
- Just because a new version exists

---

## Troubleshooting

### "Package not found"
- Check spelling
- Check internet connection
- Try `flutter pub cache repair`

### "Version conflict"
- Run `flutter pub upgrade`
- Check if package still maintained
- Consider alternative package

### "Build fails after adding package"
- Run `flutter clean`
- Run `flutter pub get`
- Check package's README for platform-specific setup

---

Last updated: February 15, 2026
