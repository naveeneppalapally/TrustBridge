# TrustBridge — Days 85 to 114 Task Plan
**Based on:** App Audit (2026-02-19) · Design files in project folder · Physical device testing on Android 14

---

## Overview

| Week | Days | Theme | Goal |
|------|------|-------|------|
| Week 18 | 85–89 | 🔴 Critical Bug Fixes | Fix VPN on Android 14 + onboarding race condition + design system foundation |
| Week 19 | 90–94 | 🟠 Parent Core UI Redesign | Dashboard, Settings, Security Controls — match design files |
| Week 20 | 95–99 | 🟠 Child Side Redesign | Child home, request flow, approval modal, success screens |
| Week 21 | 100–104 | 🟠 Policy & Reports Redesign | Add Child, Category Blocking, Schedule Editor, Child Detail, Usage Reports |
| Week 22 | 105–109 | 🟡 Missing Screens | Blocked overlay, Child tutorial, Family Management, Premium screen, Skeletons |
| Week 23 | 110–114 | 🟢 Polish, Dark Mode & Beta Release | Empty states, dark theme, animations, QA on device, v1.0.0-beta.1 |

---

## 🔴 WEEK 18 — Critical Bug Fixes + Design System Foundation

---

### Day 85 — Fix Onboarding Race Condition + Android 14 Foreground Service Type
**Week 18 Day 1**

**Program goal:** Fix the setup guide never showing on first launch, and add the Android 14 mandatory foreground service type declaration that's preventing VPN from starting.

**Tasks:**
1. **Onboarding race condition fix** in `lib/main.dart`:
   - Convert `AuthWrapper` to a `FutureBuilder` that awaits both auth state AND `getParentPreferences()` before routing
   - Only navigate to `/dashboard` after confirming `onboardingComplete == true`
   - If false or null → navigate to `/onboarding`
   - Handle the case where Firestore is slow (show loading spinner, not blank screen)

2. **Firestore default fix** in `lib/services/firestore_service.dart`:
   - Confirm `ensureParentProfile()` explicitly sets `onboardingComplete: false`
   - Add a safety null-check: treat missing field as `false`

3. **Android 14 foreground service type** in `android/app/src/main/AndroidManifest.xml`:
   - Add `android:foregroundServiceType="specialUse"` to `DnsVpnService` declaration
   - Add `<property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="parental_controls_vpn"/>` inside the service tag
   - Add `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` to manifest

4. **Tests:**
   - Update `test/screens/onboarding_screen_test.dart` to verify routing logic
   - Verify `test/services/firestore_service_test.dart` covers `onboardingComplete: false` default

**Validation:**
- Fresh install → onboarding screen appears before dashboard
- `flutter analyze` passes
- `flutter test` passes
- `flutter build apk --debug` passes

---

### Day 86 — Fix VPN on Android 14 (TUN + Notifications + Underlying Networks)
**Week 18 Day 2**

**Program goal:** Make VPN DNS filtering actually work on Android 14 by fixing three breaking changes in the OS.

**Tasks:**
1. **POST_NOTIFICATIONS runtime permission** in `lib/screens/vpn_protection_screen.dart`:
   - Add `permission_handler` to `pubspec.yaml` if not present
   - Request `Permission.notification` before calling `startVpn()`
   - Show informative snackbar if denied: "Notification permission is required for VPN to run in background"

2. **TUN interface fix** in `android/.../vpn/DnsVpnService.kt`:
   - Change `addAddress` to `"10.0.0.1", 32` (specific, not broad subnet)
   - After `Builder()` calls, add `setUnderlyingNetworks(arrayOf(activeNetwork))` using `ConnectivityManager.activeNetwork`
   - Register a `ConnectivityManager.NetworkCallback` to update underlying networks on network changes (WiFi ↔ mobile data switch)

3. **DNS server fallback** in `DnsVpnService.kt`:
   - Add `addDnsServer("1.1.1.1")` and `addDnsServer("8.8.8.8")` as explicit fallbacks in the TUN builder
   - Set MTU to exactly 1500

4. **Tests:**
   - Update `test/services/vpn_service_test.dart` with Android 14 path coverage
   - Update fake VPN service in all related screen tests

**Validation:**
- `flutter analyze` passes
- `flutter test` passes
- `flutter build apk --debug` passes
- **Physical device test (Android 14):** VPN starts, DNS queries counter increments, blocking works

---

### Day 87 — Fix Battery Optimization + VPN Boot on Android 14
**Week 18 Day 3**

**Program goal:** Fix battery optimization settings intent for Android 14 and ensure boot recovery works correctly on Android 14.

**Tasks:**
1. **Battery optimization intent fix** in `android/.../MainActivity.kt`:
   - Use `Build.VERSION_CODES.UPSIDE_DOWN_CAKE` check (Android 14 = API 34)
   - For Android 14+: use `ACTION_APPLICATION_DETAILS_SETTINGS` with package URI
   - For Android <14: keep existing `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`

2. **Boot receiver update** in `android/.../vpn/VpnBootReceiver.kt`:
   - Add `android:exported="true"` to boot receiver in manifest (required Android 12+)
   - Add `android:directBootAware="false"` (safe default for Firestore-dependent logic)

3. **VPN connection state persistence** in `DnsVpnService.kt`:
   - On Android 14, `onRevoke()` fires more aggressively — add reconnect logic
   - Save `vpnEnabled` flag to `VpnPreferencesStore` on every `onStartCommand`

4. **In-app diagnostics update** in `lib/screens/vpn_protection_screen.dart`:
   - Update the "Battery Optimization" card to show correct status for Android 14
   - Add a "Readiness" check item: "POST_NOTIFICATIONS permission"

5. **Tests:**
   - Update `test/screens/vpn_protection_screen_test.dart` for new permission check item

**Validation:**
- `flutter analyze` passes
- `flutter test` passes
- `flutter build apk --debug` passes
- **Physical device:** Battery optimization card shows correct status; VPN survives device restart

---

### Day 88 — Design System Foundation (Colors, Typography, Theme Tokens)
**Week 18 Day 4**

**Program goal:** Implement the full design token system from `design_system_tokens_spec` as a Flutter theme — correct colors, Inter font, corner radii, and card styles — so every screen inherits the right look from Day 89 onwards.

**Tasks:**
1. **Add google_fonts** to `pubspec.yaml`:
   - `google_fonts: ^6.1.0`

2. **Create `lib/theme/app_theme.dart`:**
   ```dart
   // Color tokens from design_system_tokens_spec
   static const primary = Color(0xFF207CF8);      // Primary Action blue
   static const bgLight = Color(0xFFF0F4F8);       // Light background
   static const bgDark = Color(0xFF0D1117);        // Dark background  
   static const surfaceDark = Color(0xFF1E3A22);   // Dark success surface
   static const success = Color(0xFF68B901);       // Status Success green
   static const error = Color(0xFFF41F5C);         // Status Error red
   static const cardLight = Colors.white;
   static const cardDark = Color(0xFF161B22);
   ```

3. **Update `lib/main.dart` themes:**
   - Light theme: `background: bgLight`, card: white, Inter font, radius 16px
   - Dark theme: `background: bgDark`, card: cardDark, Inter font, radius 16px
   - Both themes: primary `#207CF8`, success `#68B901`, error `#F41F5C`
   - `themeMode: ThemeMode.system` (respect device setting)

4. **Create `lib/theme/app_text_styles.dart`:**
   - `displayLarge`: Inter Bold 32px, 1.2 line height
   - `headlineMedium`: Inter SemiBold 24px, 1.2 line height
   - `bodyMedium`: Inter Medium 16px, 1.4 line height

5. **Create `lib/theme/app_spacing.dart`:**
   - Steps: 4, 8, 12, 16, 24, 32
   - Corner radii: `sm=8`, `md=16`, `lg=24`, `xl=32`

6. **Tests:**
   - Add `test/theme/app_theme_test.dart` verifying color token values

**Validation:**
- `flutter analyze` passes
- `flutter test` passes
- Visual check on emulator: background is now `#F0F4F8` light, cards are white, text is Inter

---

### Day 89 — Bottom Navigation Bar Shell (Parent App)
**Week 18 Day 5**

**Program goal:** Implement the persistent bottom navigation bar for the parent app that the design requires on every screen — the single biggest structural gap identified in the audit.

**Design reference:** `parent_dashboard_mobile_light` → DASHBOARD | SCHEDULE | REPORTS | SECURITY

**Tasks:**
1. **Create `lib/widgets/parent_shell.dart`:**
   - `StatefulWidget` wrapping an `IndexedStack` with 4 tabs
   - Tab 0: `DashboardScreen`
   - Tab 1: `ScheduleCreatorScreen` (existing)
   - Tab 2: `UsageReportsScreen` (placeholder until Day 104)
   - Tab 3: `VpnProtectionScreen` (Security tab)

2. **Bottom nav styling:**
   ```dart
   BottomNavigationBar(
     type: BottomNavigationBarType.fixed,
     selectedItemColor: Color(0xFF207CF8),
     unselectedItemColor: Color(0xFF8B95A3),
     backgroundColor: Colors.white,  // dark: Color(0xFF161B22)
     elevation: 8,
     items: [
       BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
       BottomNavigationBarItem(icon: Icon(Icons.schedule_rounded), label: 'Schedule'),
       BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Reports'),
       BottomNavigationBarItem(icon: Icon(Icons.security_rounded), label: 'Security'),
     ],
   )
   ```

3. **Update routing** in `lib/main.dart`:
   - `/dashboard` now points to `ParentShell` (not `DashboardScreen` directly)
   - Preserve deep-link routes for all sub-screens

4. **Notification bell badge** on Dashboard tab:
   - Show red dot when `pendingRequestCount > 0` (reuse existing stream)

5. **Child app bottom nav** — create `lib/widgets/child_shell.dart`:
   - HOME / ACTIVITY / HELP tabs (design: `child_home_mobile_light`)
   - Tab 0: `ChildStatusScreen`
   - Tab 1: `ChildRequestsScreen`
   - Tab 2: `ChildHelpScreen` (placeholder)

6. **Tests:**
   - `test/widgets/parent_shell_test.dart`
   - `test/widgets/child_shell_test.dart`

**Validation:**
- `flutter analyze` passes
- `flutter test` passes
- `flutter run` on device: bottom nav appears, all 4 tabs switch correctly

---

## 🟠 WEEK 19 — Parent Core UI Redesign

---

### Day 90 — Dashboard Redesign: Greeting + Hero Trust Summary Card
**Week 19 Day 1**

**Program goal:** Replace the plain 3-stats row at the top of the dashboard with the greeting header and "Trust Summary" hero card from the design.

**Design reference:** `parent_dashboard_mobile_dark` → "Good Evening, Sarah Jenkins" + "Trust Summary — SHIELD ACTIVE"

**Tasks:**
1. **Greeting header** in `lib/screens/dashboard_screen.dart`:
   - Display time-of-day greeting: "Good Morning / Afternoon / Evening, {parentName}"
   - Pull parent name from Firestore `parentProfile.displayName`
   - Show notification bell icon top-right with badge

2. **Trust Summary hero card:**
   - Card with "Trust Summary" title + "SHIELD ACTIVE" badge pill (blue when VPN on, grey when off)
   - Two sub-cards in a row: "TOTAL SCREEN TIME: 5h 42m" + "ACTIVE THREATS: None"
   - Screen time sourced from aggregate of children's usage (or "--" if no data)
   - Progress bar under screen time sub-card

3. **Remove old stats row** (MANAGED PROFILES / BLOCKED CATEGORIES / SCHEDULES numbers row)

4. **Tests:**
   - Update `test/screens/dashboard_screen_test.dart` with greeting + hero card assertions

**Validation:**
- `flutter analyze` passes · `flutter test` passes · `flutter build apk --debug` passes
- Design reference: greeting, shield badge, trust summary card visible

---

### Day 91 — Dashboard Redesign: Child Cards with Mode Badge + Activity Bar
**Week 19 Day 2**

**Program goal:** Redesign child cards to match the design — avatar, online/offline status dot, current mode badge, time usage progress bar, and Pause/Resume action buttons.

**Design reference:** `parent_dashboard_mobile_dark` → Leo (Online, Roblox, 1h 45m / 2h bar, Pause + Lock buttons)

**Tasks:**
1. **ChildCard widget redesign** in `lib/widgets/child_card.dart` (create if not exists):
   - Left: circular avatar with colored initial + green/grey online dot overlay
   - Top-right: "ONLINE" / "OFFLINE" badge + device name (if linked)
   - Current activity text: mode or last-known active app
   - TIME USAGE label + "1h 45m / 2h" + `LinearProgressIndicator`
   - Two action buttons: **Pause Internet** (blue filled) + **Locate** (outlined)
   - If paused: show **Resume** button instead

2. **Mode badge** under child name:
   - Pill badge: "● Free Time" (green), "● Focus Mode" (orange), "● Bedtime" (purple), "● School" (blue)
   - Source: derive from active schedules for that child

3. **"MANAGED DEVICES — View All" section header** above the child list

4. **"+ Connect New Device" CTA** at bottom of list (dashed border style)

5. **Tests:**
   - Update `test/screens/dashboard_screen_test.dart` for new child card layout

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Visual: child cards match dark design

---

### Day 92 — Dashboard Redesign: Security Quick-Actions Section
**Week 19 Day 3**

**Program goal:** Add the "Security Quick-Actions" section at the bottom of the dashboard with Pause All Devices toggle and Bedtime Schedule shortcut.

**Design reference:** `parent_dashboard_mobile_light` → "Pause All Devices" toggle + "Bedtime Schedule · Active starting at 9:00 PM"

**Tasks:**
1. **Security Quick-Actions section** in `lib/screens/dashboard_screen.dart`:
   - Section header "Security Quick-Actions"
   - Row 1: Red circle icon + "Pause All Devices" title + "Instantly stop all screen time" subtitle + `Switch`
     - Toggle pauses internet for all children via `FirestoreService.pauseAllChildren()`
   - Row 2: Moon icon + "Bedtime Schedule" + "Active starting at {time}" + "+" action button
     - Tapping navigates to Schedule tab

2. **Pause All logic** in `lib/services/firestore_service.dart`:
   - Add `pauseAllChildren(parentId)` — sets `paused: true` on all children documents
   - Add `resumeAllChildren(parentId)`

3. **Dashboard scroll behavior:**
   - Full screen is a `CustomScrollView` with `SliverAppBar` (collapses on scroll) + `SliverList`

4. **Tests:**
   - Verify Pause All toggle persists to Firestore
   - Verify security quick-actions section renders

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Pause All toggle works end-to-end

---

### Day 93 — Settings Screen Redesign
**Week 19 Day 4**

**Program goal:** Redesign the settings screen to match the design — large profile card at top, correct section grouping (ACCOUNT / SUBSCRIPTION / SECURITY & PRIVACY / ABOUT), proper bottom nav integration.

**Design reference:** `parent_settings_mobile_light`

**Tasks:**
1. **Profile card** at top of `lib/screens/parent_settings_screen.dart`:
   - White card with 56px avatar, bold name (18px), email subtitle, chevron → 
   - Taps to a personal information editor (stub for now)

2. **ACCOUNT section:**
   - Email Address row (with current email, → chevron)
   - Change Password → (existing functionality)
   - Phone → (shows "No phone linked" with → to link)

3. **SUBSCRIPTION section** (new):
   - "Family Subscription" row with "FREE" or "PREMIUM" pill badge
   - → navigates to Premium upgrade screen (Day 108)

4. **SECURITY & PRIVACY section:**
   - Biometric Login toggle (existing)
   - Privacy Center → (existing)
   - Incognito Mode toggle (existing)
   - Italic note: "TrustBridge never sells your family's data."

5. **ABOUT section** (new):
   - Terms of Service → (open URL)
   - Privacy Policy → (open URL)
   - Version: "1.0.0-alpha.1 (Build 60)"

6. **Remove or regroup:** App Lock, Analytics, Support sections — fold into correct design sections

7. **Tests:**
   - Update `test/screens/parent_settings_screen_test.dart` for new layout

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Settings matches design profile card + sections

---

### Day 94 — Security Controls Screen Redesign
**Week 19 Day 5**

**Program goal:** Redesign Security Controls to match the design — "Security" large heading, ACCESS CONTROL section with biometric card, CONFIGURATION section with Change PIN / Login History / Two-Factor Auth, encryption info card.

**Design reference:** `security_settings_light`

**Tasks:**
1. **Header** in `lib/screens/security_controls_screen.dart`:
   - Large "Security" display heading (32px bold)
   - Subtitle: "Manage your access and privacy settings"

2. **ACCESS CONTROL section:**
   - White card: icon + "Biometric Unlock" + "Face ID or Fingerprint" + `Switch`
   - Explanatory text below card

3. **CONFIGURATION section:**
   - Row 1: `123` icon + "Change PIN" + "Last changed {N} days ago" + →
     - Currently app has "Change Password" — keep both, rename this to "App PIN"
   - Row 2: history icon + "Login History" + "N Active Sessions" + → (stub screen)
   - Row 3: phone icon + "Two-Factor Auth" + "Enabled/Disabled" + → (stub screen)

4. **ENCRYPTION info card:**
   - Blue info card: "Encryption Active — Your biometric data is stored locally and encrypted."

5. **Tests:**
   - Update `test/screens/security_controls_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Screen matches `security_settings_light` design

---

## 🟠 WEEK 20 — Child Side Redesign

---

### Day 95 — Child Home Screen Redesign (Circular Timer + Category Chips)
**Week 20 Day 1**

**Program goal:** Completely rebuild the child home screen to match the design — circular timer ring with remaining time, mode badge, "What's blocked?" category chips, motivational quote card.

**Design reference:** `child_home_mobile_light`

**Tasks:**
1. **Greeting header** in `lib/screens/child_status_screen.dart`:
   - Child avatar (circle with initial + colored border) + "Good afternoon, {childName}! 👋"
   - Shield icon top-right

2. **Hero circular timer card:**
   - White card containing:
     - "● HOMEWORK MODE" pill badge (blue dot, uppercase)
     - `CustomPaint` circular progress ring (blue stroke, 200px diameter)
     - Center text: "2h 15m" bold + "REMAINING" caption
     - Below ring: "Until **Free Time** begins. Keep it up!" — with bold mode name
   - Time sourced from active schedule remaining duration (or "Free Time" if no active schedule)

3. **"What's blocked?" section:**
   - Section header with info (ℹ) icon
   - Wrap of icon chips: Social 🔒, Games 🔒, Videos 🔒 — each is a rounded chip with icon + label + lock icon
   - Only shows blocked categories from child's active policy

4. **Motivational quote card** at bottom:
   - ✨ sparkle icon + italic quote: "Focused effort leads to faster rewards. You're doing great, {name}!"

5. **Bottom nav** (from `ChildShell` — Day 89)

6. **Tests:**
   - Update `test/screens/child_status_screen_test.dart` for circular ring + chips

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Child home matches design

---

### Day 96 — Child Request Screen Redesign (App Icons + Draft Preview)
**Week 20 Day 2**

**Program goal:** Rebuild the child access request screen to match the design — "Ask your parent" blue header, quick-select app icons, duration chips, reason field, animated draft preview at bottom.

**Design reference:** `child_request_mobile_light`

**Tasks:**
1. **Hero banner** in `lib/screens/child_request_screen.dart`:
   - Blue gradient card: speech bubble icon + "Ask your parent" bold + subtitle
   
2. **"Which app?" section:**
   - Search bar: "Search apps..."
   - 4-icon row of quick-select apps (Roblox, YouTube, TikTok, Instagram) with rounded square icons
   - Selected app gets blue ring border
   - Manual text input below for unlisted apps

3. **"For how long?" section:**
   - Pill chips: **15m** (selected, filled blue) | 30m | 1h | 2h | Until schedule ends
   - Spring animation on selection

4. **"Why do you need it?" field:**
   - Multiline text area with placeholder: "I'm finishing a game with Leo..."

5. **Draft preview bar** (sticky bottom):
   - Small card: app icon + "Requesting access · {App} for {duration}" + "Draft" badge
   - Transitions to "Send Request →" full-width blue button when all fields filled

6. **Tests:**
   - Update `test/screens/child_request_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Screen matches `child_request_mobile_light`

---

### Day 97 — Request Sent Success Screen (Paper Plane Animation)
**Week 20 Day 3**

**Program goal:** Replace the current plain success state with the designed "Request Sent!" screen — paper plane illustration, "Waiting for approval" status card, View Status + Back to Home actions.

**Design reference:** `child_request_sent_success`

**Tasks:**
1. **Create `lib/screens/request_sent_screen.dart`:**
   - White background, centered layout
   - Top: animated paper plane icon in blue circle (use `AnimationController` for float animation)
     - Floating dots around the circle (decorative)
   - **"Request Sent! ✉"** bold heading (28px)
   - Subtitle: "Mom usually responds in **15 mins**. We'll let you know as soon as there is an update."
   - **CURRENT STATUS card:** hourglass icon + "CURRENT STATUS" caption + "Waiting for approval" + animated pulsing dot
   - **"View Status →"** full-width blue button (navigates to `ChildRequestsScreen`)
   - **"Back to Home"** text button
   - Bottom: "🛡 TRUSTBRIDGE SECURE" caption

2. **Wire into `child_request_screen.dart`:**
   - On successful submit → navigate to `RequestSentScreen` (replace instead of push)
   - Pass `childName` as parameter for the response-time hint

3. **Tests:**
   - `test/screens/request_sent_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Matches `child_request_sent_success` design

---

### Day 98 — Parent Approval Modal Redesign (Bottom Sheet + Child Avatar)
**Week 20 Day 4**

**Program goal:** Replace the plain tab-based approval card with the designed bottom sheet modal — "NEW REQUEST" badge, child avatar, bold app name in blue, large Approve/Deny buttons.

**Design reference:** `approval_modal_mobile_light`

**Tasks:**
1. **Redesign approval bottom sheet** in `lib/screens/parent_requests_screen.dart`:
   - Trigger: tapping any pending request card opens `showModalBottomSheet`
   - **Sheet layout:**
     - Handle bar at top
     - "NEW REQUEST" pill badge (light blue background)
     - "Access Request" bold heading
     - Circular child avatar (80px, shows initial with color)
     - "{childName} is asking to use **{appName}**" — app name in `#207CF8` blue, bold
     - "🕐 Requested {duration}" with clock icon
     - Italic reason quote card: "{reason text}"
     - Spacing
     - **"✓ Approve Request"** full-width green button (`#68B901`)
     - **"⊘ Deny"** full-width outlined button
     - Caption: "REQUESTED {N} MINUTES AGO"

2. **Preserve existing functionality:**
   - Duration override chips (Day 78) — add below approve button in collapsed section
   - Quick reply chips (Day 79)
   - All existing Firestore logic unchanged

3. **Tests:**
   - Update `test/screens/parent_requests_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Modal matches `approval_modal_mobile_light`

---

### Day 99 — Approval Success Animation Screen
**Week 20 Day 5**

**Program goal:** Implement the post-approval animated success screen that was designed but never built — animated green checkmark, app name confirmation, "Sent to {child}" confirmation.

**Design reference:** `approval_success_animation`

**Tasks:**
1. **Create `lib/screens/approval_success_screen.dart`:**
   - Full-screen white/light background
   - **Animated green circle with checkmark:**
     - Use `AnimationController` + `ScaleTransition`
     - Expanding circle from center, then checkmark draws in
     - Particle dots scatter outward (simple `Transform.translate` animations)
   - **"Success!"** heading (28px bold)
   - **"{appName} approved for {duration}"** — app name bold green
   - **"➤ Sent to {childName}"** — green pill chip
   - Spacing
   - **"Done"** full-width dark button

2. **Wire into approval flow** in `lib/screens/parent_requests_screen.dart`:
   - On successful approval → close bottom sheet → push `ApprovalSuccessScreen`
   - Pass `appName`, `duration`, `childName` as parameters

3. **Tests:**
   - `test/screens/approval_success_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Animation runs smoothly (60fps)

---

## 🟠 WEEK 21 — Policy & Reports Redesign

---

### Day 100 — Add Child Screen Redesign (Avatar Picker + Protection Level Cards)
**Week 21 Day 1**

**Program goal:** Redesign the Add Child screen to match the design — step indicator, avatar picker with camera button, protection level selection cards (Strict/Moderate/Light), "Continue to Pairing" CTA.

**Design reference:** `add_child_mobile_light`

**Tasks:**
1. **Step indicator** in `lib/screens/add_child_screen.dart`:
   - "Add Child · STEP 1 OF 2" header
   - Linear progress bar (50% filled for step 1)

2. **Avatar picker:**
   - Large circular avatar (100px) with illustrated placeholder
   - Blue camera button overlay (bottom-right)
   - "Choose an avatar" caption
   - Tapping opens emoji avatar selector (6 options: boy, girl variants by age)

3. **Child's Nickname field** (existing, keep styling)

4. **PROTECTION LEVEL section** (replaces old age band dropdown):
   - Three selectable cards:
     - 🔴 **Strict** — "Highest safety & content filtering · Manual approval for all new apps"
     - 🔵 **Moderate** — "Balanced freedom & automation · Automated safe-search & filtering"
     - 🟢 **Light** — "Trust-based monitoring · Activity logging without blocks"
   - Selected card: blue border + filled background tint
   - Maps to existing `AgeBand` presets internally

5. **"Continue to Pairing →"** full-width blue button + "PRIVACY-FIRST ENCRYPTION ENABLED" caption

6. **Tests:**
   - Update `test/screens/add_child_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Add Child matches `add_child_mobile_light`

---

### Day 101 — Category Blocking Redesign (Icons + Search + Save Bar)
**Week 21 Day 2**

**Program goal:** Redesign category blocking to match the design — category icon cards, search bar, custom blocked sites section, sticky "Save Changes" bar at bottom.

**Design reference:** `category_blocking_mobile_light`

**Tasks:**
1. **Search bar** at top of `lib/screens/category_blocking_screen.dart`:
   - "🔍 Search categories or apps"

2. **APP CATEGORIES section:**
   - Each category as a full-width card:
     - Left: colored rounded-square icon (Social=blue, Games=green, Video=red, Adult=orange, Shopping=yellow)
     - Category name bold + example apps subtitle (e.g., "Instagram, TikTok, Snapchat")
     - Right: `Switch` (blue when blocked)

3. **CUSTOM BLOCKED SITES section:**
   - List of custom domains: globe icon + "www.reddit.com" + minus "⊖" button to remove
   - Dashed border "+ Add Custom Site" button at bottom

4. **Sticky bottom bar:**
   - "● Safe Mode Active — 4 Categories Restricted" on left
   - "Save Changes" blue button on right
   - Only shows when there are unsaved changes

5. **Tests:**
   - Update `test/screens/category_blocking_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Matches `category_blocking_mobile_light`

---

### Day 102 — Schedule Editor Redesign (Routine Type + Restriction Level Cards)
**Week 21 Day 3**

**Program goal:** Redesign the schedule editor to match the design — ROUTINE TYPE segmented chips, large STARTS/ENDS time display, day selector circles, RESTRICTION LEVEL cards, dark summary bar.

**Design reference:** `schedule_editor_mobile_light`

**Tasks:**
1. **Routine Type chips** in `lib/screens/schedule_creator_screen.dart`:
   - Segmented pill row: **Bedtime** | School | Study | Custom
   - Selected: white filled, others: transparent

2. **Time display card:**
   - Large card with "STARTS · 09:00 PM" and "ENDS · 07:30 AM" side by side
   - Divider between them
   - Tapping each opens `showTimePicker`
   - "10h 30m total" right-aligned label

3. **Day selector row:**
   - 7 circles (M T W T F S S)
   - Selected: filled blue circle with white letter
   - Unselected: outlined grey

4. **RESTRICTION LEVEL section:**
   - Selectable cards (radio style):
     - 🔵 **Block Distractions** — "Social media, games, and streaming apps restricted..."
     - 🔴 **Block Everything** — "Total lockout. Only Emergency Calls..."
   - Selected card: blue border

5. **"Remind child 5m before"** toggle row

6. **Dark summary bar at bottom:**
   - Dark card: "ROUTINE SUMMARY · Mon–Fri, 9:00 PM – 7:30 AM · Bedtime Filter" + "ACTIVE" blue pill

7. **Tests:**
   - Update `test/screens/schedule_creator_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Matches `schedule_editor_mobile_light`

---

### Day 103 — Child Detail Screen Redesign (Circular Ring + Quick Actions Grid + Activity Bars)
**Week 21 Day 4**

**Program goal:** Redesign the child detail screen to match the design — device status/mode header, circular time ring, 2×2 quick-action grid, Today's Activity bars, Active Schedules with toggles.

**Design reference:** `child_detail_mobile_light`

**Tasks:**
1. **Header section** in `lib/screens/child_detail_screen.dart`:
   - "CHILD PROFILE" caption + "{childName}" bold title + "⋯" action menu
   - Device Status card: avatar + "Homework Mode ●" + "ACTIVE" badge

2. **Circular time ring:**
   - Same `CustomPaint` ring as Day 95
   - Center: "1h 34m" + "REMAINING" caption
   - Below: italic quote from parent or mode description

3. **Quick Actions 2×2 grid:**
   - Each is a rounded card with icon + label
   - **Pause All** (red ⏸), **Homework** (blue 📖, highlighted if active), **Bedtime** (purple 🌙), **Free Play** (green 🎉)
   - Active mode card: blue background tint

4. **Today's Activity section:**
   - "Today's Activity · Total: 2h 15m screen time" header + bar chart icon
   - Category rows: Education | Entertainment | Social — each with colored `LinearProgressIndicator` + time

5. **Active Schedules section:**
   - "Active Schedules · **View All**" header
   - Schedule rows: icon + name + time range + `Switch`

6. **Tests:**
   - Update `test/screens/child_detail_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Matches `child_detail_mobile_light`

---

### Day 104 — Usage Reports Screen (Donut Chart + 7-Day Bar + Most Used Apps)
**Week 21 Day 5**

**Program goal:** Build the Usage Reports screen from scratch — it was designed but never implemented. Hero stats, donut chart by category, 7-day bar chart trend, "Most Used Apps" list.

**Design reference:** `usage_reports_mobile_light`

**Tasks:**
1. **Create `lib/screens/usage_reports_screen.dart`:**

2. **Hero stats card:**
   - Blue gradient card: "Total Screen Time · **5h 47m** ↗ 12%"
   - "DAILY AVERAGE: 4H 12M" caption

3. **By Category section:**
   - `PieChart` (fl_chart) — donut style, center label "Mainly Social"
   - Legend rows: Social Media 2h 15m | Education 2h 02m | Games 1h 30m

4. **7-Day Trend section:**
   - `BarChart` (fl_chart) — Mon–Sun
   - Peak day highlighted in full blue, others light blue
   - Insight card: "Weekend screen time is **24% higher** than usual. Consider setting a Saturday limit."

5. **Most Used Apps section:**
   - Ranked list: app icon + name + category + time + colored progress bar
   - "View All App Usage" text button

6. **Date range selector** top-right: "This Week 📅" chip

7. **Wire into Reports tab** (ParentShell Day 89)

8. **Tests:**
   - `test/screens/usage_reports_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Charts render on device

---

## 🟡 WEEK 22 — Missing Screens

---

### Day 105 — Blocked Overlay Screen for Child (DNS Block Experience)
**Week 22 Day 1**

**Program goal:** Build the child-facing blocked screen overlay — the full-screen experience a child sees when they try to access a blocked domain. Currently DNS blocking happens but there's no UI for it.

**Design reference:** `blocked_overlay_mobile_light`

**Tasks:**
1. **Create `lib/screens/blocked_overlay_screen.dart`:**
   - White/light background, centered
   - Top: TrustBridge shield icon (large, white, in blue rounded-square)
   - **"This is blocked during {modeName}"** bold heading (24px)
   - Subtitle: "To help you focus on your studies, this app is currently unavailable."
   - **STATUS card:** "STATUS · 1h 34m · until free time begins" + `LinearProgressIndicator`
   - **"📋 Request Access"** full-width blue button → navigates to `ChildRequestScreen`
   - **"I Understand"** outlined button → dismisses overlay

2. **Wire into VPN service** — when DNS returns `0.0.0.0`, the native VPN service sends a local broadcast; Flutter catches it via method channel and shows `BlockedOverlayScreen`

3. **Tests:**
   - `test/screens/blocked_overlay_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Matches `blocked_overlay_mobile_light`

---

### Day 106 — Child Tutorial Onboarding (Illustrated 3-Step Flow)
**Week 22 Day 2**

**Program goal:** Build the child-facing illustrated onboarding tutorial — 3 steps explaining how TrustBridge works from the child's perspective. Currently only parent onboarding exists.

**Design reference:** `child_tutorial_light`

**Tasks:**
1. **Create `lib/screens/child_tutorial_screen.dart`:**
   - `PageView` with 3 pages
   - Each page:
     - Large illustrated card (rounded square, light blue bg + bold icon illustration)
     - Step number badge at top of illustration
     - Bold heading: "1. Ask for Permission" / "2. Wait for Reply" / "3. You're Protected"
     - Subtitle explanation paragraph
   - Dot indicator (animated, step-aware)
   - "Step N of 3: The Basics" caption
   - **"Next →"** full-width blue button (last page: "Let's Go!")
   - **"Skip"** top-right text button

2. **Step content:**
   - Step 1: "Ask for Permission" — "Found a fun new app or game? Just tap the button to ask your parents!"
   - Step 2: "Your Parent Decides" — "Mom or Dad will get a notification and can approve it right away."
   - Step 3: "Stay Safe Together" — "TrustBridge keeps you safe while giving you freedom to explore."

3. **Wire into child first-launch flow** — shown before `ChildStatusScreen` on first open

4. **Tests:**
   - `test/screens/child_tutorial_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Matches `child_tutorial_light`

---

### Day 107 — Family Management Screen
**Week 22 Day 3**

**Program goal:** Build the Family Management screen — subscription status, admin parents list with roles, children list with device status, invite controls.

**Design reference:** `family_management_light`

**Tasks:**
1. **Create `lib/screens/family_management_screen.dart`:**

2. **Subscription card at top:**
   - Shield icon + "Premium Family" bold + "ACTIVE" badge
   - "Renews Oct 24, 2024" subtitle
   - "Manage Billing →" row

3. **"🔐 END-TO-END ENCRYPTED MANAGEMENT"** caption

4. **ADMINS (PARENTS) section:**
   - "2 / 4 Seats" right label
   - Parent rows: avatar + name + email + "OWNER" badge (or edit ⋯)
   - "+ Invite another parent" blue text button

5. **CHILDREN section:**
   - "2 / Unlimited" right label
   - Child rows: avatar + name + device + "Active Now" or "N hours ago"
   - "+ Add child profile" blue text button → navigates to `AddChildScreen`

6. **"Leave Family Group"** red text button at bottom

7. **Wire into Settings** — "Family Management" row in ACCOUNT section

8. **Tests:**
   - `test/screens/family_management_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Matches `family_management_light`

---

### Day 108 — Premium Upgrade Screen (TrustBridge Plus)
**Week 22 Day 4**

**Program goal:** Build the TrustBridge Plus upgrade screen — feature list, yearly/monthly pricing cards, Upgrade Now CTA.

**Design reference:** `premium_upgrade_light`

**Tasks:**
1. **Create `lib/screens/premium_screen.dart`:**

2. **Header:**
   - "✕" close button top-left + "🛡 SAFE & SECURE" badge top-right
   - White card: star-shield icon (blue) + "TrustBridge **Plus**" (blue Plus) + "PREMIUM PLAN" pill

3. **Feature list:**
   - 4 rows with icon + title + description:
     - 👨‍👩‍👧‍👦 Unlimited Children
     - 📊 Advanced Analytics
     - 🔺 Custom Categories
     - 🎧 Priority Support

4. **Pricing cards:**
   - "BEST VALUE" badge
   - **Yearly Plan** card (blue border, selected): "₹{price} / year · Save 40%"
   - **Monthly Plan** card (unbordered): "₹{price} / month"

5. **"Upgrade Now ›"** full-width blue button
   - "RESTORE PURCHASE · TERMS · PRIVACY" footer

6. **Wire into:** SUBSCRIPTION section in Settings (Day 93)

7. **Tests:**
   - `test/screens/premium_screen_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Matches `premium_upgrade_light`

---

### Day 109 — Loading Skeleton Screens for All Data States
**Week 22 Day 5**

**Program goal:** Replace blank loading states with shimmer skeleton placeholders on every screen that loads from Firestore, matching the design's shimmer loading behavior.

**Tasks:**
1. **Create `lib/widgets/skeleton_loaders.dart`:**
   - `SkeletonCard` — animated shimmer rectangle (uses existing `shimmer` package)
   - `SkeletonChildCard` — avatar circle + 3 shimmer lines
   - `SkeletonListTile` — icon circle + 2 shimmer lines
   - `SkeletonChart` — rectangle shimmer for chart areas

2. **Apply to screens:**
   - `dashboard_screen.dart`: show 2× `SkeletonChildCard` while children stream loads
   - `parent_requests_screen.dart`: show 3× `SkeletonListTile` while requests load
   - `usage_reports_screen.dart`: show `SkeletonChart` while data loads
   - `beta_feedback_history_screen.dart`: show skeleton list
   - `child_status_screen.dart`: show skeleton ring card

3. **Shimmer animation config** (from design tokens):
   - Base color: `#E8EDF2`, highlight: `#F5F7FA` (light) / `#1C2128`, `#2D333B` (dark)

4. **Tests:**
   - `test/widgets/skeleton_loaders_test.dart` — renders in loading state

**Validation:**
- `flutter analyze` passes · `flutter test` passes · No blank screens during Firestore loading

---

## 🟢 WEEK 23 — Polish, Dark Mode & Beta Release

---

### Day 110 — Illustrated Empty States
**Week 23 Day 1**

**Program goal:** Replace blank empty states with friendly illustrated empty states with clear CTAs — matching the design language across all list screens.

**Tasks:**
1. **Create `lib/widgets/empty_state.dart`:**
   - `EmptyState({icon, title, subtitle, actionLabel, onAction})`
   - Centered layout: large emoji/icon (64px) + bold title + subtitle + outlined button CTA

2. **Apply to all screens:**
   - **Dashboard (no children):** 👨‍👩‍👧 "Add your first child" + "Get started by adding a child profile." + "Add Child" button
   - **Pending requests (empty):** ✅ "All caught up!" + "No pending requests." (this one is good, keep emoji)
   - **History (empty):** 📋 "No history yet" + "Approved and denied requests will appear here."
   - **Category blocking (all off):** 🛡 "No categories blocked" + "Toggle categories to start filtering."
   - **Schedule (empty):** 📅 "No schedules yet" + "Add a bedtime or school schedule." + "Add Schedule" button
   - **DNS query log (empty):** 🔍 "No queries yet" + "Start VPN to see DNS activity."

3. **Tests:**
   - `test/widgets/empty_state_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · No blank states anywhere

---

### Day 111 — Dark Theme Proper Implementation
**Week 23 Day 2**

**Program goal:** Fix dark theme so it correctly uses dark design tokens — not just system default dark. Many screens look wrong in dark mode because background and card colors weren't set from the design token spec.

**Design reference:** `parent_dashboard_mobile_dark`, `category_blocking_mobile_dark`, `child_home_mobile_dark`

**Tasks:**
1. **Update `lib/theme/app_theme.dart`:**
   - Dark theme `scaffoldBackgroundColor`: `#0D1117`
   - Dark card color: `#161B22`
   - Dark surface: `#21262D`
   - Dark divider: `#30363D`
   - Dark text primary: `#F0F6FC`
   - Dark text secondary: `#8B949E`

2. **Fix specific screens in dark mode:**
   - Dashboard: greeting text, hero card, child cards
   - Settings: section headers, dividers, profile card
   - VPN protection: status cards

3. **Verify `ThemeMode.system`** in `main.dart` switches correctly on Android 14

4. **Tests:**
   - `test/theme/dark_theme_test.dart`

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Dark mode matches design on physical device

---

### Day 112 — Motion & Micro-Animations (Spring Physics)
**Week 23 Day 3**

**Program goal:** Add the spring-physics micro-animations specified in the design token spec — page transitions, chip selection, card tap feedback, approval animation.

**Design reference:** `design_system_tokens_spec` → Motion & Glass Effects: Stiffness 300, Damping 20

**Tasks:**
1. **Spring animation utility** in `lib/utils/spring_animation.dart`:
   - Stiffness: 300, Damping: 20 (from tokens)
   - Helper: `springCurve` using `SpringSimulation`

2. **Apply to key interactions:**
   - Duration chips (child request): scale up on select
   - Quick action cards (child detail): press scale-down feedback
   - Bottom sheet: spring entrance (already modal, tweak curve)
   - Page transitions: `SlideTransition` with spring curve
   - FAB (dashboard add child): scale in with spring

3. **Circular ring animation** (Days 95, 103):
   - Animate progress fill from 0 to value on screen load (600ms, spring curve)

4. **Tests:**
   - Visual test: animations don't crash or throw
   - `flutter test` passes

**Validation:**
- `flutter analyze` passes · `flutter test` passes · Animations at 60fps on device

---

### Day 113 — Full Physical Device QA (Android 14 End-to-End)
**Week 23 Day 4**

**Program goal:** Systematic end-to-end QA on physical Android 14 device covering all critical flows, VPN, onboarding, and request approval. Document any remaining issues.

**Tasks:**
1. **Onboarding flow QA:**
   - Fresh install → onboarding appears ✓
   - Complete → dashboard ✓
   - Skip → dashboard ✓
   - Return to onboarding from Settings ✓

2. **VPN flow QA:**
   - Request VPN permission → system dialog appears ✓
   - Enable protection → VPN connects, DNS queries increment ✓
   - Open blocked site → DNS blocked (0.0.0.0 returned) ✓
   - Blocked overlay screen appears ✓
   - Request access → approval flow ✓
   - Approved → temp exception domain allowed ✓
   - Exception expires → blocking resumes ✓
   - Device restart → VPN auto-restarts ✓

3. **Notification QA:**
   - POST_NOTIFICATIONS granted ✓
   - Child submits request → parent gets push notification ✓
   - Notification tap → opens parent inbox ✓

4. **Theme QA:**
   - Light mode: `#F0F4F8` background ✓
   - Dark mode: `#0D1117` background ✓

5. **Create `docs/QA_CHECKLIST_V1_BETA.md`** with all test results

**Validation:**
- All critical flows pass on physical Android 14 device
- No crashes in Crashlytics

---

### Day 114 — Beta Release v1.0.0-beta.1 + Release Notes
**Week 23 Day 5**

**Program goal:** Build, sign, and distribute TrustBridge Beta 1 via Firebase App Distribution. Update all release docs. Close the 30-day design improvement sprint.

**Tasks:**
1. **Version bump** in `pubspec.yaml`:
   - `version: 1.0.0-beta.1+114`

2. **Release build:**
   ```bash
   flutter build apk --release \
     --target-platform android-arm64 \
     --obfuscate \
     --split-debug-info=build/debug-info
   ```

3. **Upload to Firebase App Distribution:**
   - Group: `beta-testers`
   - Release notes referencing all improvements since alpha

4. **Create `docs/BETA_1_RELEASE_NOTES.md`:**
   - What's new: VPN Android 14 fix, onboarding fix, full UI redesign, 7 new screens, bottom nav
   - Known issues
   - How to report feedback (Beta Feedback screen)

5. **Update `PROGRESS_JOURNAL.md`** for Days 85–114

6. **Update `firestore.rules`** and **deploy:**
   - Verify all new screens' Firestore paths are covered

7. **Final test run:**
   - `flutter test` must pass all tests (target: 300+ tests)
   - `flutter analyze` must pass clean

**Validation:**
- Signed APK uploaded to Firebase App Distribution ✓
- Beta testers can download and install ✓
- No critical crashes in first 24 hours ✓

---

## 📊 Summary — Days 85 to 114

| Category | Days | Count |
|----------|------|-------|
| 🔴 Critical Bug Fixes | 85–87 | 3 days |
| 🎨 Design System Foundation | 88 | 1 day |
| 🧭 Navigation Shell | 89 | 1 day |
| 🟠 Parent UI Redesign | 90–94 | 5 days |
| 🟠 Child UI Redesign | 95–99 | 5 days |
| 🟠 Policy & Reports Redesign | 100–104 | 5 days |
| 🟡 Missing Screens (New Builds) | 105–109 | 5 days |
| 🟢 Polish + Release | 110–114 | 5 days |
| **Total** | **85–114** | **30 days** |

### Screens Touched
| Screen | Day | Type |
|--------|-----|------|
| Onboarding (fix) | 85 | Bug Fix |
| VPN Android 14 (fix) | 86–87 | Bug Fix |
| Design Tokens | 88 | Foundation |
| Bottom Nav Shell | 89 | New |
| Dashboard (redesign) | 90–92 | Redesign |
| Settings (redesign) | 93 | Redesign |
| Security Controls (redesign) | 94 | Redesign |
| Child Home (redesign) | 95 | Redesign |
| Child Request (redesign) | 96 | Redesign |
| Request Sent Success | 97 | New |
| Approval Modal (redesign) | 98 | Redesign |
| Approval Success Animation | 99 | New |
| Add Child (redesign) | 100 | Redesign |
| Category Blocking (redesign) | 101 | Redesign |
| Schedule Editor (redesign) | 102 | Redesign |
| Child Detail (redesign) | 103 | Redesign |
| Usage Reports | 104 | New |
| Blocked Overlay | 105 | New |
| Child Tutorial | 106 | New |
| Family Management | 107 | New |
| Premium Upgrade | 108 | New |
| Skeleton Loaders | 109 | New |
| Empty States | 110 | New |
| Dark Theme (fix) | 111 | Fix |
| Motion / Animations | 112 | Polish |
| QA on Android 14 | 113 | QA |
| Beta v1.0.0-beta.1 | 114 | Release |
