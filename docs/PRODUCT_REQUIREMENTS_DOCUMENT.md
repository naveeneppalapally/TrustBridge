# Parental Controls App - Complete Product Requirements Document

**Version:** 1.0  
**Target Platform:** Android (MVP)  
**Target Market:** India + Global  
**Developer:** Solo  
**Timeline:** 12 weeks to MVP

---

## 1. PRODUCT OVERVIEW

### 1.1 Product Vision
A privacy-first parental controls app that helps Indian families manage screen time and block distracting content WITHOUT spyware features like message reading or location tracking.

### 1.2 Core Value Proposition
"Set schedules and block distracting apps/websites using Android VPN + DNS filtering—without invading your child's privacy."

### 1.3 Target Users

**Primary Users (Parents):**
- Age: 30-45
- Tech comfort: Moderate (can use WhatsApp, banking apps)
- Children age: 6-17
- Income: Middle class (₹50K+ monthly household)
- Concerns: Too much YouTube/gaming, social media addiction
- Location: Tier 1 & 2 cities in India initially

**Secondary Users (Children):**
- Age: 6-17
- Tech savvy: High (knows how to find workarounds)
- Expectation: Fair rules, transparency
- Pain point: Parents who snoop vs parents who set boundaries

### 1.4 Success Metrics

**Phase 1 (Months 1-3):**
- 100 beta users
- 4+ star rating on Play Store
- 50%+ daily active usage
- <5% uninstall rate

**Phase 2 (Months 4-12):**
- 1,000 paying users
- ₹3L+ monthly revenue
- <10% churn rate
- Positive word-of-mouth (NPS >30)

---

## 2. FEATURE SPECIFICATIONS

### 2.1 MVP Features (Must Have)

#### Feature 1: User Authentication
**Parent Flow:**
- Sign up with phone number (OTP via Firebase Auth)
- Create parent profile (name, email optional)
- Set up 4-digit PIN for quick access

**Child Flow:**
- Parent creates child profile (nickname, age band)
- Child doesn't need separate login
- Child device identified by device ID

**Technical:**
- Firebase Authentication for parent
- Device UUID for child identification
- Encrypted SharedPreferences for local storage

---

#### Feature 2: Child Profile Management
**Parent Can:**
- Add up to 3 children (MVP limit)
- Set age band: 6-9, 10-13, 14-17
- Assign nickname (not full name for privacy)
- Link devices to child profile
- Delete child profile

**Child Profile Contains:**
- Nickname
- Age band
- Active policy
- Linked devices
- Usage statistics

**Pre-set Policies by Age:**
```
Age 6-9 (Strict):
- Bedtime: 8 PM - 7 AM
- School: 9 AM - 3 PM (Mon-Fri)
- Blocked: Social media, dating, gambling, weapons
- SafeSearch: ON
- YouTube Restricted: ON

Age 10-13 (Moderate):
- Bedtime: 9:30 PM - 7 AM
- School: 9 AM - 3 PM (Mon-Fri)
- Blocked: Dating, gambling, weapons
- SafeSearch: ON
- YouTube Restricted: ON

Age 14-17 (Light):
- Bedtime: 11 PM - 7 AM
- School: None (trust-based)
- Blocked: Gambling, weapons
- SafeSearch: OFF
- YouTube Restricted: OFF
```

---

#### Feature 3: Schedule Management
**Types of Schedules:**

**A. Bedtime Schedule**
- Time range: e.g., 9:00 PM - 7:00 AM
- Days: Every day or custom days
- Action: Block all apps/websites except:
  - Phone calls
  - Messages (SMS)
  - Emergency services
- Override: Parent can approve emergency exceptions

**B. School Schedule**
- Time range: e.g., 9:00 AM - 3:00 PM
- Days: Monday-Friday
- Action: Block distracting categories:
  - Social media
  - Games
  - Video streaming
  - Shopping
- Allow: Educational apps/websites (parent defined)

**C. Homework Schedule**
- Time range: Parent sets (e.g., 4 PM - 6 PM)
- Days: Custom
- Action: Block entertainment, allow educational

**D. Device Pause**
- Instant: Parent can pause device immediately
- Duration: 15 min, 30 min, 1 hour, custom
- Action: Block everything except calls/messages

**Technical Implementation:**
- Store schedules in Firestore
- Local copy in SQLite for offline
- AlarmManager for schedule triggers
- VPN rules updated based on active schedule

---

#### Feature 4: Category Blocking
**Built-in Categories:**
1. Social Media (Facebook, Instagram, TikTok, Snapchat)
2. Video Streaming (YouTube, Netflix, Prime Video)
3. Games (Play Store games section, gaming websites)
4. Dating (Tinder, Bumble, etc.)
5. Gambling (betting sites, online casinos)
6. Adult Content (pornography sites)
7. Weapons (weapon sales, violent content)
8. Drugs (drug-related content)

**Parent Can:**
- Toggle categories ON/OFF
- See example sites in each category
- Add custom domains to block
- Add exception domains (always allow)

**Technical Implementation:**
- Local blocklist database (SQLite)
- Hardcoded top 100 sites per category
- NextDNS for comprehensive blocking
- VPN intercepts DNS queries
- Blocked domains return NXDOMAIN

---

#### Feature 5: Quick Modes
**One-tap mode switching:**

**Homework Mode:**
- Blocks: Social media, games, streaming
- Allows: Educational sites, communication
- Status: Shown on child device

**Bedtime Mode:**
- Blocks: Everything except calls/SMS
- Duration: Until scheduled wake time
- Override: Parent approval only

**Free Time Mode:**
- Blocks: Only dangerous content (adult, gambling)
- Allows: Everything else
- Use case: Weekends, holidays

**Technical:**
- Quick mode = temporary policy override
- Persists until parent changes
- Syncs across all child's devices

---

#### Feature 6: Request & Approve System
**Child Can Request:**
- Unblock specific app (e.g., "I need Instagram for school project")
- Extra time (e.g., "15 more minutes of gaming")
- Unblock website (e.g., "YouTube video for homework")

**Request Contains:**
- What: App/website/extra time
- How long: 15 min, 30 min, 1 hour, until schedule ends
- Reason: Text field (optional)
- Timestamp

**Parent Receives:**
- Push notification
- In-app notification badge
- Details of request

**Parent Can:**
- Approve (with time limit)
- Deny (with optional message)
- Approve with conditions

**Technical:**
- Request stored in Firestore
- FCM push notification to parent
- Real-time sync of approval
- Child app shows approval status

---

#### Feature 7: VPN-Based DNS Filtering
**How It Works:**
1. Child device runs VPN service (always-on)
2. All DNS queries intercepted
3. Blocked domains return NXDOMAIN
4. Allowed domains forwarded to NextDNS
5. VPN stays active even after reboot

**VPN Service Features:**
- Persistent notification (Android requirement)
- Low battery impact (<5% drain)
- Works on WiFi + mobile data
- Automatic reconnection
- Bypass detection

**Technical:**
- Android VpnService implementation
- Local DNS resolution for blocked domains
- Upstream: NextDNS resolver
- Blocklist updated daily
- Status monitoring service

---

#### Feature 8: Basic Usage Reports
**Parent Sees:**
- Daily total screen time per child
- Time by category (social media, games, etc.)
- Number of blocked attempts
- Top blocked apps/sites
- Weekly comparison

**NOT Included (Privacy):**
- Exact URLs visited
- Message content
- Screenshots
- Keystrokes
- Location

**Technical:**
- UsageStatsManager for app time
- VPN logs blocked attempts only
- Aggregate daily, store weekly
- 30-day retention limit

---

#### Feature 9: Child App Transparency
**Child Device Shows:**
- Current active mode (Homework, Bedtime, Free)
- Time until next schedule change
- What's currently blocked (categories)
- Why it's blocked (schedule reason)
- Request button (always visible)
- Recent approvals/denials

**Design Principle:**
- NO HIDING the app
- Child knows they're being monitored
- Respectful UI, not punitive
- Educational tone

---

#### Feature 10: Bypass Detection
**Detects:**
- VPN disabled by user
- Private DNS changed (DNS-over-TLS)
- Date/time manipulation
- App uninstalled
- Device admin removed

**When Detected:**
- Parent gets immediate notification
- Child sees warning banner
- Grace period: 5 minutes to fix
- After grace: Parent notified again

**Cannot Prevent (Be Honest):**
- Child using another device
- Child using school/friend's WiFi without VPN
- Child factory resetting device
- Child using DoH in browser

---

### 2.2 Post-MVP Features (Phase 2)

#### Feature 11: App Time Limits
- Set daily limit per app (e.g., Instagram 1 hour/day)
- Warning at 80% usage
- App blocked when limit reached
- Child can request more time

#### Feature 12: Website Allowlist
- Parent adds educational sites always allowed
- Useful during Homework mode
- Khan Academy, NCERT, etc.

#### Feature 13: Family Link Integration
- Import child profiles from Family Link
- Sync some settings
- Avoid redundant setup

#### Feature 14: Multiple Parent Accounts
- Co-parent access
- Same household, different logins
- Sync policies across parents

#### Feature 15: Advanced Reports
- Weekly email summary
- Export data as CSV
- Trend analysis (improving/worsening)

---

## 3. USER FLOWS

### 3.1 Parent Onboarding Flow

```
1. Download app from Play Store
   ↓
2. See welcome screen
   "Protect your child's screen time—without spying"
   ↓
3. Sign up with phone number
   Enter: +91-XXXXXXXXXX
   ↓
4. Verify OTP
   Enter: 6-digit code
   ↓
5. Create parent profile
   Name: [text]
   Email: [optional]
   ↓
6. Set quick access PIN
   4-digit PIN for fast unlocking
   ↓
7. Dashboard (empty state)
   "Add your first child"
   [+ Add Child button]
```

### 3.2 Adding First Child Flow

```
1. Tap "Add Child"
   ↓
2. Child details
   Nickname: [e.g., "Aarav"]
   Age band: [6-9 / 10-13 / 14-17]
   ↓
3. Choose starting policy
   - Recommended (based on age)
   - Custom
   ↓
4. Review pre-set schedules
   Bedtime: 9 PM - 7 AM
   School: 9 AM - 3 PM (Mon-Fri)
   [Edit] [Confirm]
   ↓
5. Review blocked categories
   ☑ Social Media
   ☑ Games
   ☑ Dating
   [Next]
   ↓
6. Install on child device
   Two options shown:
   
   A. QR Code Setup:
      - Show QR code
      - Scan from child device
      - Auto-installs child app
   
   B. Manual Setup:
      - Download child app separately
      - Enter pairing code: XXXX-XXXX
   ↓
7. Child device setup (see separate flow)
   ↓
8. Success screen
   "Aarav's device is protected!"
   [View Dashboard]
```

### 3.3 Child Device Setup Flow

```
1. Install "ParentalShield - Child" app
   From Play Store or via parent QR
   ↓
2. Welcome screen (child-facing)
   "Your parent has set up screen time rules"
   [Continue]
   ↓
3. Enter pairing code
   Code from parent device: XXXX-XXXX
   ↓
4. Grant permissions (step-by-step):
   
   Step 1: VPN Permission
   "Allow VPN to filter websites"
   [Allow] → System VPN dialog
   
   Step 2: Usage Stats
   "Track app usage for reports"
   [Allow] → Opens Settings
   
   Step 3: Notification Access (optional)
   "Show you what's blocked"
   [Allow] or [Skip]
   
   Step 4: Device Admin (recommended)
   "Prevent accidental uninstall"
   [Enable] or [Skip]
   ↓
5. Setup complete
   Shows current policy:
   "Homework Mode is active until 6 PM"
   [View Details]
   ↓
6. Main child dashboard visible
```

### 3.4 Daily Parent Usage Flow

```
1. Open parent app
   ↓
2. Dashboard shows:
   - List of children (cards)
   - Quick status for each
   
   Example card:
   ┌─────────────────────────┐
   │ 👦 Aarav (12)           │
   │ Status: ✅ Protected    │
   │ Mode: School            │
   │ Screen time: 2h 15m     │
   │ Blocked: 8 attempts     │
   └─────────────────────────┘
   
   ↓
3. Tap child card to see details:
   - Current schedule
   - Usage today
   - Recent blocks
   - Pending requests (badge)
   
   ↓
4. Common actions:
   - [Pause Device] → Instant block
   - [Change Mode] → Quick mode picker
   - [Edit Schedule] → Schedule editor
   - [View Reports] → Usage reports
```

### 3.5 Request-Approve Flow

**Child Side:**
```
1. Child tries to open Instagram (blocked)
   ↓
2. Blocked screen appears:
   "Instagram is blocked during Homework Mode"
   [Request Access] [Back]
   ↓
3. Child taps "Request Access"
   ↓
4. Request form:
   "Why do you need Instagram?"
   [Text field: "School project on social media"]
   "How long?"
   [15 min] [30 min] [1 hour] [Until 6 PM]
   [Send Request]
   ↓
5. Confirmation:
   "Request sent to Mom"
   "You'll be notified when she responds"
   [OK]
```

**Parent Side:**
```
1. Parent receives push notification:
   "Aarav wants to use Instagram"
   ↓
2. Parent opens app (or taps notification)
   ↓
3. Request details shown:
   ┌─────────────────────────────┐
   │ 👦 Aarav requests:          │
   │ App: Instagram              │
   │ Duration: 30 minutes        │
   │ Reason: "School project on  │
   │ social media"               │
   │                             │
   │ [Approve] [Deny] [Message]  │
   └─────────────────────────────┘
   ↓
4. Parent taps "Approve"
   ↓
5. Confirmation:
   "Instagram unlocked for 30 minutes"
   Child device updates instantly
   ↓
6. Child gets notification:
   "Your request was approved!
   Instagram unlocked until 4:45 PM"
```

### 3.6 Schedule Edit Flow

```
1. Parent taps "Edit Schedule"
   ↓
2. Schedule list shown:
   - Bedtime: 9 PM - 7 AM (Every day)
   - School: 9 AM - 3 PM (Mon-Fri)
   - Homework: 4 PM - 6 PM (Mon-Fri)
   [+ Add Schedule]
   ↓
3. Tap existing schedule to edit
   ↓
4. Schedule editor:
   Name: [Bedtime]
   Start: [9:00 PM] ⏰
   End: [7:00 AM] ⏰
   Repeat: [☑ Every day]
   
   OR
   
   Days: ☑Mon ☑Tue ☑Wed ☑Thu ☑Fri ☐Sat ☐Sun
   
   Block: [All apps & websites]
   Exceptions: [+ Add exception]
   
   [Save] [Delete]
   ↓
5. Save confirmation
   "Schedule updated for Aarav"
   ↓
6. Syncs to child device immediately
```

---

## 4. SCREENS & UI MOCKUPS

### 4.1 Parent App Screens

#### Screen 1: Login/Signup
```
┌────────────────────────┐
│   ParentalShield       │
│   🛡️                   │
│                        │
│   Screen time made     │
│   simple & private     │
│                        │
│ ┌────────────────────┐ │
│ │ +91-XXXXXXXXXX     │ │
│ └────────────────────┘ │
│                        │
│   [Get OTP]            │
│                        │
│   By signing up, you   │
│   agree to our Terms   │
└────────────────────────┘
```

#### Screen 2: Dashboard (with children)
```
┌────────────────────────┐
│ ← ParentalShield   ⚙️  │
│                        │
│ Your Children          │
│                        │
│ ┌────────────────────┐ │
│ │ 👦 Aarav (12)      │ │
│ │ ✅ Protected       │ │
│ │ 🕐 School Mode     │ │
│ │ 📊 2h 15m today    │ │
│ │ 🚫 8 blocks        │ │
│ │ [Pause Device]     │ │
│ └────────────────────┘ │
│                        │
│ ┌────────────────────┐ │
│ │ 👧 Priya (15)      │ │
│ │ ✅ Protected       │ │
│ │ 🕐 Free Time       │ │
│ │ 📊 4h 32m today    │ │
│ │ 🚫 2 blocks        │ │
│ │ [Pause Device]     │ │
│ └────────────────────┘ │
│                        │
│ [+ Add Child]          │
│                        │
│ ≡ Menu                 │
└────────────────────────┘
```

#### Screen 3: Child Detail
```
┌────────────────────────┐
│ ← Aarav (12)       ⋮   │
│                        │
│ Status: ✅ Protected   │
│ Current: School Mode   │
│ Until: 3:00 PM         │
│                        │
│ ┌────────────────────┐ │
│ │ Quick Actions      │ │
│ │ [Pause Now]        │ │
│ │ [Change Mode]      │ │
│ │ [Edit Schedule]    │ │
│ └────────────────────┘ │
│                        │
│ Today's Activity       │
│ ┌────────────────────┐ │
│ │ 📱 Screen time     │ │
│ │    2h 15m          │ │
│ │                    │ │
│ │ 🚫 Blocks          │ │
│ │    8 attempts      │ │
│ │    (Instagram: 5,  │ │
│ │     YouTube: 3)    │ │
│ └────────────────────┘ │
│                        │
│ Pending Requests  [1]  │
│ ┌────────────────────┐ │
│ │ Instagram access   │ │
│ │ "School project"   │ │
│ │ 5 min ago          │ │
│ │ [Review]           │ │
│ └────────────────────┘ │
│                        │
│ [View Full Report]     │
└────────────────────────┘
```

#### Screen 4: Schedule Editor
```
┌────────────────────────┐
│ ← Bedtime Schedule     │
│                        │
│ Time                   │
│ ┌────────────────────┐ │
│ │ Start:  9:00 PM ⏰ │ │
│ │ End:    7:00 AM ⏰ │ │
│ └────────────────────┘ │
│                        │
│ Repeat                 │
│ ☑Mon ☑Tue ☑Wed ☑Thu    │
│ ☑Fri ☑Sat ☑Sun         │
│                        │
│ Action                 │
│ ┌────────────────────┐ │
│ │ ⦿ Block all apps   │ │
│ │ ○ Block categories │ │
│ │ ○ Custom           │ │
│ └────────────────────┘ │
│                        │
│ Exceptions (optional)  │
│ ┌────────────────────┐ │
│ │ ✓ Phone calls      │ │
│ │ ✓ Messages (SMS)   │ │
│ │ + Add app          │ │
│ └────────────────────┘ │
│                        │
│ [Save]  [Delete]       │
└────────────────────────┘
```

### 4.2 Child App Screens

#### Screen 1: Status Screen
```
┌────────────────────────┐
│   ParentalShield       │
│   (Child Mode)         │
│                        │
│ ┌────────────────────┐ │
│ │ 🕐 School Mode     │ │
│ │    Active          │ │
│ │                    │ │
│ │ Until 3:00 PM      │ │
│ │ (2h 15m left)      │ │
│ └────────────────────┘ │
│                        │
│ What's blocked:        │
│ • Social Media         │
│ • Games                │
│ • Video Streaming      │
│                        │
│ Today's usage:         │
│ 📱 2h 15m              │
│                        │
│ ┌────────────────────┐ │
│ │ Need more time?    │ │
│ │ [Request Access]   │ │
│ └────────────────────┘ │
│                        │
│ Recent Activity        │
│ • Instagram blocked    │
│   (5 min ago)          │
│ • YouTube blocked      │
│   (12 min ago)         │
│                        │
│ [View Details]         │
└────────────────────────┘
```

#### Screen 2: Blocked Screen (overlay)
```
┌────────────────────────┐
│   🚫                   │
│                        │
│   Instagram            │
│   is blocked           │
│                        │
│   Reason:              │
│   School Mode active   │
│   until 3:00 PM        │
│                        │
│ ┌────────────────────┐ │
│ │ [Request Access]   │ │
│ └────────────────────┘ │
│                        │
│ [Back to Home]         │
└────────────────────────┘
```

#### Screen 3: Request Form
```
┌────────────────────────┐
│ ← Request Access       │
│                        │
│ App: Instagram         │
│                        │
│ Why do you need it?    │
│ ┌────────────────────┐ │
│ │ School project on  │ │
│ │ social media       │ │
│ │                    │ │
│ └────────────────────┘ │
│                        │
│ How long?              │
│ ┌────────────────────┐ │
│ │ ○ 15 minutes       │ │
│ │ ⦿ 30 minutes       │ │
│ │ ○ 1 hour           │ │
│ │ ○ Until 6 PM       │ │
│ └────────────────────┘ │
│                        │
│ Note: Your parent will │
│ be notified instantly  │
│                        │
│ [Send Request]         │
└────────────────────────┘
```

---

## 5. DATA MODELS

### 5.1 Firestore Collections

```javascript
// Collection: parents
{
  "parentId": "uuid",
  "phone": "+91XXXXXXXXXX",
  "name": "Rajesh Kumar",
  "email": "rajesh@example.com",
  "pin": "hashed_pin",
  "createdAt": timestamp,
  "subscription": {
    "tier": "premium",
    "validUntil": timestamp
  }
}

// Collection: children
{
  "childId": "uuid",
  "parentId": "parent_uuid",
  "nickname": "Aarav",
  "ageBand": "10-13",
  "devices": ["device_uuid_1", "device_uuid_2"],
  "currentPolicy": "policy_uuid",
  "createdAt": timestamp
}

// Collection: devices
{
  "deviceId": "uuid",
  "childId": "child_uuid",
  "deviceName": "Samsung Galaxy M32",
  "androidVersion": "12",
  "lastSeen": timestamp,
  "isActive": true,
  "capabilities": {
    "hasVpnPermission": true,
    "hasUsageAccess": true,
    "hasDeviceAdmin": false
  }
}

// Collection: policies
{
  "policyId": "uuid",
  "childId": "child_uuid",
  "schedules": [
    {
      "scheduleId": "uuid",
      "name": "Bedtime",
      "type": "bedtime",
      "startTime": "21:00",
      "endTime": "07:00",
      "days": ["mon", "tue", "wed", "thu", "fri", "sat", "sun"],
      "action": "blockAll",
      "exceptions": ["com.android.phone", "com.android.messaging"]
    }
  ],
  "blockedCategories": ["social", "games", "streaming"],
  "blockedDomains": ["example.com"],
  "allowedDomains": ["khanacademy.org"],
  "safeSearchEnabled": true,
  "youtubeRestrictedMode": true,
  "updatedAt": timestamp
}

// Collection: overrideRequests
{
  "requestId": "uuid",
  "childId": "child_uuid",
  "deviceId": "device_uuid",
  "targetType": "app", // or "domain" or "extraTime"
  "targetIdentifier": "com.instagram.android",
  "durationMinutes": 30,
  "reason": "School project on social media",
  "status": "pending", // or "approved" or "denied"
  "requestedAt": timestamp,
  "respondedAt": null,
  "parentResponse": null
}

// Collection: usageReports
{
  "reportId": "uuid",
  "childId": "child_uuid",
  "date": "2025-02-14",
  "totalMinutes": 135, // 2h 15m
  "byCategory": {
    "education": 45,
    "social": 60,
    "games": 30
  },
  "byApp": {
    "com.instagram.android": 60,
    "com.supercell.clashofclans": 30,
    "org.khanacademy.android": 45
  },
  "blockedAttempts": 8,
  "topBlockedApps": {
    "com.instagram.android": 5,
    "com.youtube.android": 3
  }
}
```

### 5.2 Local SQLite Schema (Android)

```sql
-- Table: blocked_domains
CREATE TABLE blocked_domains (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    domain TEXT NOT NULL UNIQUE,
    category TEXT,
    added_at INTEGER
);

-- Table: allowed_domains
CREATE TABLE allowed_domains (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    domain TEXT NOT NULL UNIQUE,
    added_at INTEGER
);

-- Table: schedules
CREATE TABLE schedules (
    id TEXT PRIMARY KEY,
    name TEXT,
    type TEXT,
    start_time TEXT,
    end_time TEXT,
    days TEXT, -- JSON array
    action TEXT,
    exceptions TEXT, -- JSON array
    enabled INTEGER DEFAULT 1
);

-- Table: policy_cache
CREATE TABLE policy_cache (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at INTEGER
);

-- Table: usage_logs
CREATE TABLE usage_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    package_name TEXT,
    duration_minutes INTEGER,
    date TEXT,
    synced INTEGER DEFAULT 0
);

-- Table: blocked_attempts
CREATE TABLE blocked_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    target TEXT,
    type TEXT,
    timestamp INTEGER,
    synced INTEGER DEFAULT 0
);
```

---

## 6. TECHNICAL ARCHITECTURE

### 6.1 Android App Structure

```
parental_controls_app/
├── android/
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── kotlin/com/yourapp/
│   │   │   │   ├── ParentalControlVpnService.kt
│   │   │   │   ├── ScheduleService.kt
│   │   │   │   ├── UsageStatsService.kt
│   │   │   │   ├── BypassDetectionService.kt
│   │   │   │   └── FlutterPlugin.kt
│   │   │   ├── AndroidManifest.xml
│   │   │   └── res/
│   └── build.gradle
├── lib/
│   ├── main.dart
│   ├── models/
│   │   ├── child_profile.dart
│   │   ├── policy.dart
│   │   ├── schedule.dart
│   │   └── override_request.dart
│   ├── services/
│   │   ├── auth_service.dart
│   │   ├── firestore_service.dart
│   │   ├── vpn_service.dart
│   │   ├── nextdns_service.dart
│   │   └── notification_service.dart
│   ├── screens/
│   │   ├── parent/
│   │   │   ├── login_screen.dart
│   │   │   ├── dashboard_screen.dart
│   │   │   ├── child_detail_screen.dart
│   │   │   ├── schedule_editor_screen.dart
│   │   │   └── approval_screen.dart
│   │   └── child/
│   │       ├── status_screen.dart
│   │       ├── request_screen.dart
│   │       └── blocked_screen.dart
│   ├── widgets/
│   │   ├── child_card.dart
│   │   ├── schedule_card.dart
│   │   └── usage_chart.dart
│   └── utils/
│       ├── constants.dart
│       ├── helpers.dart
│       └── validators.dart
├── pubspec.yaml
└── README.md
```

### 6.2 Technology Stack

**Frontend:**
- Flutter 3.16+
- Dart 3.2+
- Provider (state management)
- http (API calls)

**Backend:**
- Firebase Authentication
- Cloud Firestore
- Firebase Cloud Messaging
- Firebase Cloud Functions (optional for cron jobs)

**Android Native:**
- Kotlin
- VpnService API
- UsageStatsManager
- AlarmManager
- ForegroundService

**Third-party Services:**
- NextDNS (DNS filtering)
- Razorpay (Indian payments)

**Development Tools:**
- Android Studio
- VS Code
- Git/GitHub
- Postman (API testing)

---

## 7. IMPLEMENTATION ROADMAP

### Week 1-2: Foundation
- [ ] Create Flutter project
- [ ] Set up Firebase project
- [ ] Implement authentication (phone OTP)
- [ ] Create data models
- [ ] Set up Firestore security rules
- [ ] Build basic parent dashboard UI

### Week 3-4: Child Management
- [ ] Add child profile creation
- [ ] Implement age-based presets
- [ ] Build schedule management UI
- [ ] Create category blocking UI
- [ ] Device pairing flow

### Week 5-6: Android VPN Service
- [ ] Implement VpnService
- [ ] Create DNS filtering logic
- [ ] Integrate local blocklist
- [ ] Add NextDNS forwarding
- [ ] Test DNS blocking

### Week 7-8: Schedules & Enforcement
- [ ] Implement schedule triggers
- [ ] Create AlarmManager integration
- [ ] Build UsageStatsManager wrapper
- [ ] Add quick modes
- [ ] Test schedule enforcement

### Week 9: Request-Approve Flow
- [ ] Build request submission
- [ ] Implement FCM notifications
- [ ] Create approval UI
- [ ] Add real-time sync
- [ ] Test approval flow

### Week 10: Child App & Reports
- [ ] Build child status screen
- [ ] Create blocked screen overlay
- [ ] Implement usage reports
- [ ] Add charts/visualizations
- [ ] Test child experience

### Week 11: Testing & Polish
- [ ] Bypass detection testing
- [ ] Battery impact testing
- [ ] Network performance testing
- [ ] UI/UX improvements
- [ ] Bug fixes

### Week 12: Launch Prep
- [ ] Create Play Store listing
- [ ] Record promo video
- [ ] Write privacy policy
- [ ] Complete Data Safety form
- [ ] Submit for review
- [ ] Beta testing with 10 families

---

## 8. COMPLIANCE REQUIREMENTS

### 8.1 Google Play Policies

**VpnService Declaration:**
1. Go to Play Console → App Content → VPN Service
2. Declare VPN usage
3. Explain: "Parental control DNS filtering"
4. Provide privacy policy link

**Data Safety Form:**
```
Data collected:
- Phone number (for authentication)
- Device identifiers (for device management)
- App usage data (for reports)

Data shared:
- None

Security practices:
- Data encrypted in transit
- Data encrypted at rest
- User can request deletion
```

**Families Policy (if targeting children):**
- Don't transmit AAID/IMEI from child device
- No ads targeting children
- No behavioral profiling of children

### 8.2 India DPDP Act

**Requirements:**
- Verifiable parental consent (phone OTP counts)
- No tracking/behavioral monitoring of children
- No targeted advertising to children
- Data retention limits (30 days for logs)
- Grievance officer contact info
- Privacy policy in English + Hindi

**Implementation:**
- Store child age band, not DOB
- Aggregate usage data only
- No URL-level tracking by default
- Clear opt-in for detailed logs
- Data deletion within 30 days of request

### 8.3 Privacy Policy Sections

**Required sections:**
1. What data we collect
2. Why we collect it
3. How we use it
4. Who we share with (none)
5. How long we keep it
6. Child data protections
7. Parent rights
8. Contact information
9. Grievance redressal
10. Changes to policy

---

## 9. TESTING PLAN

### 9.1 Functional Testing

**Authentication:**
- [ ] Phone OTP login works
- [ ] Invalid OTP rejected
- [ ] PIN lock/unlock works
- [ ] Logout works

**Child Management:**
- [ ] Add child
- [ ] Edit child
- [ ] Delete child
- [ ] Age-based presets apply correctly

**Schedules:**
- [ ] Bedtime schedule triggers on time
- [ ] School schedule triggers on time
- [ ] Schedule ends correctly
- [ ] Overlapping schedules handled
- [ ] Timezone changes handled

**Blocking:**
- [ ] Social media blocked
- [ ] Games blocked
- [ ] Allowed domains work
- [ ] Blocked domains work
- [ ] NextDNS integration works

**Request-Approve:**
- [ ] Child can submit request
- [ ] Parent receives notification
- [ ] Approve works instantly
- [ ] Deny works instantly
- [ ] Expired requests cleaned up

**Reports:**
- [ ] App usage tracked correctly
- [ ] Category aggregation correct
- [ ] Blocked attempts counted
- [ ] Charts render correctly

### 9.2 Performance Testing

**Battery:**
- [ ] VPN service uses <5% battery/day
- [ ] No battery drain during idle
- [ ] Doze mode compatibility

**Network:**
- [ ] DNS latency <50ms
- [ ] No slowdown on WiFi
- [ ] No slowdown on mobile data
- [ ] Works on slow 3G

**Memory:**
- [ ] VPN service uses <50MB RAM
- [ ] No memory leaks
- [ ] Stable over 7 days

### 9.3 Security Testing

**Bypass Attempts:**
- [ ] VPN disable detected
- [ ] Private DNS change detected
- [ ] Date/time change detected
- [ ] App uninstall attempted detected
- [ ] Factory reset warning works

**Data Security:**
- [ ] Firebase auth secure
- [ ] Firestore rules prevent unauthorized access
- [ ] Local data encrypted
- [ ] No PII in logs

### 9.4 User Acceptance Testing

**Parent Feedback:**
- [ ] Easy to set up?
- [ ] Intuitive UI?
- [ ] Approval flow clear?
- [ ] Reports useful?
- [ ] Would recommend?

**Child Feedback:**
- [ ] Feels fair?
- [ ] Understands why blocked?
- [ ] Request process clear?
- [ ] UI respectful?
- [ ] Any frustrations?

---

## 10. LAUNCH CHECKLIST

### Pre-Launch

**Play Store Assets:**
- [ ] App icon (512x512 PNG)
- [ ] Feature graphic (1024x500 PNG)
- [ ] Screenshots (5+ for phone, 3+ for tablet)
- [ ] Promo video (30-120 seconds)
- [ ] App description (4000 chars max)
- [ ] Short description (80 chars max)

**Compliance:**
- [ ] Privacy policy published (URL)
- [ ] Terms of service published (URL)
- [ ] Data Safety form completed
- [ ] VpnService declaration done
- [ ] Content rating questionnaire

**Technical:**
- [ ] App signed with release key
- [ ] ProGuard enabled
- [ ] Crashlytics integrated
- [ ] Analytics integrated (privacy-conscious)
- [ ] App bundle optimized

**Testing:**
- [ ] Internal testing (you + friends)
- [ ] Closed alpha (10 families)
- [ ] Open beta (50 families)
- [ ] All critical bugs fixed

### Launch Day

**Play Store:**
- [ ] Submit for production review
- [ ] Set pricing (₹299/month)
- [ ] Enable in-app subscriptions
- [ ] Set target countries (India, US, UK)

**Marketing:**
- [ ] Post on social media
- [ ] Email early testers
- [ ] Submit to tech blogs
- [ ] Post on Reddit r/androidapps
- [ ] Post on IndieHackers

**Support:**
- [ ] Support email active
- [ ] WhatsApp Business number
- [ ] FAQ page live
- [ ] Monitor reviews

### Post-Launch (Week 1)

**Monitor:**
- [ ] Crash-free rate >99%
- [ ] ANR rate <0.1%
- [ ] 1-day retention >50%
- [ ] 7-day retention >30%

**Respond:**
- [ ] Reply to all reviews (24 hours)
- [ ] Fix critical bugs (48 hours)
- [ ] Update FAQ based on questions
- [ ] Collect feature requests

---

## 11. MONETIZATION STRATEGY

### 11.1 Pricing Tiers

**Free Tier (Discovery):**
- 1 child
- 1 device
- Basic schedules (bedtime only)
- Basic category blocking (top 3)
- 7-day trial of Premium

**Premium Tier (₹299/month or ₹2,999/year):**
- Up to 3 children
- Unlimited devices
- All schedules
- All categories
- Request-approve flow
- Basic reports

**Family Tier (₹499/month or ₹4,999/year):**
- Up to 5 children
- Unlimited devices
- All Premium features
- NextDNS managed integration
- Detailed reports
- Priority support

### 11.2 Revenue Projections

**Conservative (Year 1):**
```
Month 1-3: 50 users @ ₹299 = ₹14,950/month
Month 4-6: 200 users @ ₹299 = ₹59,800/month
Month 7-9: 500 users @ ₹299 = ₹1,49,500/month
Month 10-12: 1000 users @ ₹299 = ₹2,99,000/month

Year 1 total: ₹10-15 lakhs
```

**Optimistic (Year 1):**
```
Month 1-3: 100 users
Month 4-6: 500 users
Month 7-9: 1500 users
Month 10-12: 3000 users

Average ₹350/month (mix of tiers)

Year 1 total: ₹35-40 lakhs
```

### 11.3 Payment Integration

**For India:**
- Razorpay (UPI, cards, wallets)
- Subscription auto-renewal
- GST handling (18%)

**For Global:**
- Google Play Billing
- Stripe (backup)
- Currency conversion

---

## 12. SUPPORT & MAINTENANCE

### 12.1 Support Channels

**Primary:**
- In-app "Help & Support"
- Email: support@parentalshield.com
- WhatsApp Business: +91-XXXXXXXXXX

**Secondary:**
- FAQ page on website
- Video tutorials on YouTube
- Community forum (later)

**Response SLA:**
- Critical bugs: 24 hours
- General questions: 48 hours
- Feature requests: 7 days

### 12.2 Maintenance Tasks

**Daily:**
- Monitor crash reports
- Check Play Store reviews
- Respond to support emails

**Weekly:**
- Update blocklists
- Review analytics
- Plan improvements

**Monthly:**
- Security updates
- Performance optimization
- Feature updates

**Quarterly:**
- Policy compliance review
- Legal review
- Major feature releases

---

## APPENDIX: GLOSSARY

**VPN (Virtual Private Network):** Technology that routes device traffic through your app, enabling DNS filtering.

**DNS (Domain Name System):** Translates domain names (google.com) to IP addresses. Blocking DNS = blocking website.

**NextDNS:** Third-party DNS service with built-in filtering and parental controls.

**Firebase:** Google's backend platform (database, auth, notifications).

**Firestore:** Firebase's NoSQL database.

**FCM (Firebase Cloud Messaging):** Push notification service.

**UsageStats:** Android API to track app usage time.

**DPDP:** Digital Personal Data Protection Act (India's privacy law).

**COPPA:** Children's Online Privacy Protection Act (US law).

**OTP:** One-Time Password (for phone verification).

**AAB:** Android App Bundle (Play Store upload format).

---

**END OF DOCUMENT**

This is your complete blueprint. Follow it step-by-step and you'll have a working app in 12 weeks.

Next: Read "IMPLEMENTATION_GUIDE.md" for code examples and tutorials.
