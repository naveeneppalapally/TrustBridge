# Quick Start Checklist - Build Your App in 12 Weeks

This is your master checklist. Check off items as you complete them.

---

## 🎯 PRE-DEVELOPMENT (Before Week 1)

### Business Setup
- [ ] Choose company name and app name
- [ ] Register domain (yourapp.com)
- [ ] Create email (support@yourapp.com)
- [ ] Open business bank account (for Razorpay)
- [ ] Register for GST (if revenue >₹20L/year expected)

### Accounts & Tools
- [ ] Google Play Developer account ($25 one-time)
- [ ] Firebase account (free tier)
- [ ] NextDNS account (free for testing)
- [ ] Razorpay merchant account
- [ ] GitHub account for code hosting
- [ ] Postman for API testing

### Development Environment
- [ ] Install Android Studio
- [ ] Install Flutter SDK
- [ ] Install VS Code
- [ ] Set up Android emulator
- [ ] Get a real Android device for testing (minimum Android 7)

---

## WEEK 1: FOUNDATION

### Day 1: Project Setup
- [ ] Create Flutter project
- [ ] Initialize Git repository
- [ ] Create README.md
- [ ] Push to GitHub

### Day 2: Dependencies
- [ ] Add Firebase dependencies
- [ ] Add Provider for state management
- [ ] Add HTTP package
- [ ] Add UI packages (charts, shimmer)
- [ ] Run `flutter pub get`

### Day 3: Firebase Setup
- [ ] Create Firebase project
- [ ] Add Android app to Firebase
- [ ] Download google-services.json
- [ ] Configure build.gradle files
- [ ] Test Firebase initialization

### Day 4: Authentication Service
- [ ] Create AuthService class
- [ ] Implement sendOTP method
- [ ] Implement verifyOTP method
- [ ] Test with real phone number

### Day 5: Login Screen
- [ ] Create LoginScreen UI
- [ ] Add phone input field
- [ ] Add OTP input field
- [ ] Test full login flow

### Week 1 Goal
- [ ] App runs on device
- [ ] User can sign up with phone
- [ ] Firebase authentication works

---

## WEEK 2: BASIC UI & NAVIGATION

### Day 1: Firestore Setup
- [ ] Enable Firestore in Firebase console
- [ ] Set up security rules
- [ ] Create parents collection
- [ ] Test write operation

### Day 2: Data Models
- [ ] Create ChildProfile model
- [ ] Create Policy model
- [ ] Create Schedule model
- [ ] Add toFirestore/fromFirestore methods

### Day 3: Firestore Service
- [ ] Create FirestoreService class
- [ ] Implement addChild method
- [ ] Implement getChildren stream
- [ ] Implement updateChild method

### Day 4: Dashboard Screen
- [ ] Create DashboardScreen
- [ ] Show list of children
- [ ] Handle empty state
- [ ] Add floating action button

### Day 5: Navigation
- [ ] Set up named routes
- [ ] Implement navigation to add child
- [ ] Implement navigation to child detail
- [ ] Test navigation flow

### Week 2 Goal
- [ ] Parent can see dashboard
- [ ] Navigation between screens works
- [ ] Data syncs with Firestore

---

## WEEK 3: CHILD MANAGEMENT

### Day 1: Add Child Screen
- [ ] Create AddChildScreen UI
- [ ] Add nickname input
- [ ] Add age band selector
- [ ] Add save button

### Day 2: Age Band Presets
- [ ] Define preset policies for 6-9
- [ ] Define preset policies for 10-13
- [ ] Define preset policies for 14-17
- [ ] Apply preset on child creation

### Day 3: Child Detail Screen
- [ ] Create ChildDetailScreen
- [ ] Show child info
- [ ] Show current policy
- [ ] Show quick action buttons

### Day 4: Edit Child
- [ ] Add edit button
- [ ] Allow nickname change
- [ ] Allow age band change
- [ ] Update Firestore

### Day 5: Delete Child
- [ ] Add delete button
- [ ] Show confirmation dialog
- [ ] Delete from Firestore
- [ ] Handle related data cleanup

### Week 3 Goal
- [ ] Parent can add children
- [ ] Parent can view child details
- [ ] Parent can edit/delete children

---

## WEEK 4: POLICY MANAGEMENT

### Day 1: Policy Model
- [ ] Create Policy data model
- [ ] Add blocked categories
- [ ] Add blocked domains
- [ ] Add schedules list

### Day 2: Category Blocking UI
- [ ] Create category list
- [ ] Add toggle switches
- [ ] Save to Firestore
- [ ] Show selected categories

### Day 3: Domain Blocking UI
- [ ] Add custom domain input
- [ ] Show blocked domains list
- [ ] Add remove button
- [ ] Validate domain format

### Day 4: Schedule List Screen
- [ ] Show all schedules
- [ ] Add new schedule button
- [ ] Edit schedule button
- [ ] Delete schedule button

### Day 5: Schedule Editor
- [ ] Time picker for start/end
- [ ] Day selector
- [ ] Action selector (block all/categories)
- [ ] Save schedule

### Week 4 Goal
- [ ] Parent can block categories
- [ ] Parent can add custom domains
- [ ] Parent can create schedules

---

## WEEK 5: ANDROID VPN SETUP

### Day 1: AndroidManifest Configuration
- [ ] Add VPN permission
- [ ] Add FOREGROUND_SERVICE permission
- [ ] Declare VpnService
- [ ] Add UsageStats permission

### Day 2: VPN Service (Basic)
- [ ] Create ParentalControlVpnService.kt
- [ ] Implement onStartCommand
- [ ] Create VPN interface
- [ ] Add foreground notification

### Day 3: Flutter Plugin
- [ ] Create VpnPlugin.kt
- [ ] Register in MainActivity
- [ ] Create Flutter MethodChannel
- [ ] Test start/stop VPN

### Day 4: Permission Flow
- [ ] Request VPN permission
- [ ] Handle permission result
- [ ] Show permission denied message
- [ ] Retry permission request

### Day 5: Testing
- [ ] Test VPN starts on device
- [ ] Check persistent notification
- [ ] Verify VPN stays active
- [ ] Test VPN stop

### Week 5 Goal
- [ ] VPN service runs on device
- [ ] VPN permission flow works
- [ ] Persistent notification shows

---

## WEEK 6: DNS FILTERING

### Day 1: Blocklist Database
- [ ] Create SQLite helper
- [ ] Create blocked_domains table
- [ ] Insert top 100 social media domains
- [ ] Create query methods

### Day 2: DNS Resolution
- [ ] Parse DNS query packets
- [ ] Extract domain from query
- [ ] Check against blocklist
- [ ] Return NXDOMAIN if blocked

### Day 3: NextDNS Integration
- [ ] Add NextDNS setup screen
- [ ] Store API key encrypted
- [ ] Configure DNS resolver
- [ ] Test NextDNS forwarding

### Day 4: Category Filtering
- [ ] Map categories to domains
- [ ] Check domain category
- [ ] Apply category blocks
- [ ] Test category blocking

### Day 5: Testing & Optimization
- [ ] Test blocking Facebook
- [ ] Test blocking YouTube
- [ ] Test blocking gaming sites
- [ ] Measure DNS latency

### Week 6 Goal
- [ ] DNS filtering works
- [ ] Social media sites blocked
- [ ] NextDNS integration works
- [ ] Latency <50ms

---

## WEEK 7: SCHEDULES & ENFORCEMENT

### Day 1: AlarmManager Setup
- [ ] Create ScheduleService
- [ ] Register broadcast receiver
- [ ] Set alarms for schedule start
- [ ] Set alarms for schedule end

### Day 2: Schedule Triggers
- [ ] Trigger bedtime schedule
- [ ] Update VPN rules
- [ ] Show notification to child
- [ ] Log schedule activation

### Day 3: Quick Modes
- [ ] Implement Homework Mode
- [ ] Implement Bedtime Mode
- [ ] Implement Free Time Mode
- [ ] Add mode switcher UI

### Day 4: Device Pause
- [ ] Add pause button
- [ ] Block all traffic immediately
- [ ] Set auto-resume timer
- [ ] Show countdown to child

### Day 5: Testing
- [ ] Test bedtime schedule triggers
- [ ] Test school schedule triggers
- [ ] Test quick mode switching
- [ ] Test device pause

### Week 7 Goal
- [ ] Schedules trigger automatically
- [ ] Blocking applies based on schedule
- [ ] Quick modes work
- [ ] Device pause works

---

## WEEK 8: USAGE TRACKING

### Day 1: UsageStatsManager
- [ ] Request Usage Access permission
- [ ] Query app usage stats
- [ ] Calculate daily usage
- [ ] Store in local database

### Day 2: Usage Reports
- [ ] Create UsageReport model
- [ ] Aggregate by category
- [ ] Calculate total time
- [ ] Sync to Firestore

### Day 3: Charts & Visualization
- [ ] Add fl_chart package
- [ ] Create daily usage chart
- [ ] Create category breakdown chart
- [ ] Show weekly trends

### Day 4: Blocked Attempts
- [ ] Log blocked attempts
- [ ] Count by app/site
- [ ] Show top blocked apps
- [ ] Display in report

### Day 5: Report Screen
- [ ] Create ReportScreen UI
- [ ] Show today's stats
- [ ] Show weekly comparison
- [ ] Export report button

### Week 8 Goal
- [ ] App usage tracked
- [ ] Reports show accurate data
- [ ] Charts display correctly
- [ ] Blocked attempts counted

---

## WEEK 9: REQUEST & APPROVE

### Day 1: Request Model & Firestore
- [ ] Create OverrideRequest model
- [ ] Add requests collection
- [ ] Create FirestoreService methods
- [ ] Test write/read requests

### Day 2: Child Request Flow
- [ ] Create RequestScreen UI
- [ ] Add reason text field
- [ ] Add duration picker
- [ ] Submit request to Firestore

### Day 3: Push Notifications
- [ ] Set up FCM in Firebase
- [ ] Send notification on request
- [ ] Handle notification tap
- [ ] Navigate to approval screen

### Day 4: Parent Approval Flow
- [ ] Create ApprovalScreen UI
- [ ] Show request details
- [ ] Add approve button
- [ ] Add deny button

### Day 5: Apply Override
- [ ] Update VPN rules on approval
- [ ] Set expiry timer
- [ ] Notify child of approval
- [ ] Auto-revoke after expiry

### Week 9 Goal
- [ ] Child can submit requests
- [ ] Parent receives notifications
- [ ] Parent can approve/deny
- [ ] Override applies immediately

---

## WEEK 10: CHILD APP

### Day 1: Child Status Screen
- [ ] Create child app variant
- [ ] Show current mode
- [ ] Show time until change
- [ ] Show blocked categories

### Day 2: Blocked Screen Overlay
- [ ] Create overlay UI
- [ ] Detect blocked app launch
- [ ] Show reason for block
- [ ] Add request button

### Day 3: Transparency Log
- [ ] Log all blocks locally
- [ ] Show recent blocks
- [ ] Show schedule changes
- [ ] Show approved overrides

### Day 4: Request from Child App
- [ ] Implement request flow
- [ ] Show pending requests
- [ ] Show request status
- [ ] Notify on approval

### Day 5: Child UX Polish
- [ ] Make UI friendly
- [ ] Add encouraging messages
- [ ] Explain blocks clearly
- [ ] Test with real kids

### Week 10 Goal
- [ ] Child app functional
- [ ] Child sees current status
- [ ] Child can request access
- [ ] UI is respectful & clear

---

## WEEK 11: BYPASS DETECTION

### Day 1: VPN State Monitoring
- [ ] Detect VPN disabled
- [ ] Send alert to parent
- [ ] Show warning to child
- [ ] Auto-restart if possible

### Day 2: Private DNS Detection
- [ ] Check Private DNS setting
- [ ] Detect DNS-over-TLS
- [ ] Alert parent
- [ ] Show fix instructions

### Day 3: Time Manipulation
- [ ] Detect time change
- [ ] Use server time
- [ ] Recalculate schedules
- [ ] Alert parent

### Day 4: Uninstall Detection
- [ ] Make child app device admin
- [ ] Prevent easy uninstall
- [ ] Alert on uninstall attempt
- [ ] Require parent PIN

### Day 5: Bypass Education
- [ ] Document common bypasses
- [ ] Add to parent FAQ
- [ ] Be honest about limits
- [ ] Focus on communication

### Week 11 Goal
- [ ] Bypasses detected
- [ ] Parent notified
- [ ] Child sees warnings
- [ ] Documentation complete

---

## WEEK 12: POLISH & LAUNCH PREP

### Day 1: UI Polish
- [ ] Fix all UI bugs
- [ ] Improve animations
- [ ] Add loading states
- [ ] Add error states

### Day 2: Testing
- [ ] Test on multiple devices
- [ ] Test different Android versions
- [ ] Test poor network
- [ ] Test edge cases

### Day 3: Privacy Policy & Terms
- [ ] Write privacy policy
- [ ] Write terms of service
- [ ] Add grievance contact
- [ ] Publish on website

### Day 4: Play Store Listing
- [ ] Write app description
- [ ] Create screenshots
- [ ] Record promo video
- [ ] Design feature graphic

### Day 5: Submit to Play Store
- [ ] Complete Data Safety form
- [ ] Complete Content Rating
- [ ] Declare VPN usage
- [ ] Submit for review

### Week 12 Goal
- [ ] App polished
- [ ] All bugs fixed
- [ ] Compliance documents ready
- [ ] Submitted to Play Store

---

## POST-LAUNCH

### Week 13: Beta Testing
- [ ] Recruit 10 beta families
- [ ] Collect feedback
- [ ] Fix reported issues
- [ ] Iterate on UX

### Week 14: Marketing
- [ ] Post on social media
- [ ] Write blog post
- [ ] Submit to app directories
- [ ] Reach out to parenting bloggers

### Ongoing
- [ ] Monitor crash reports
- [ ] Respond to reviews
- [ ] Update blocklists
- [ ] Add requested features

---

## KEY MILESTONES

✅ **Milestone 1 (Week 2):** Authentication & basic UI works  
✅ **Milestone 2 (Week 4):** Child management complete  
✅ **Milestone 3 (Week 6):** VPN + DNS filtering works  
✅ **Milestone 4 (Week 8):** Schedules + usage tracking works  
✅ **Milestone 5 (Week 10):** Request-approve + child app works  
✅ **Milestone 6 (Week 12):** App submitted to Play Store  

---

## CRITICAL SUCCESS FACTORS

### Technical Excellence
- VPN must be stable (99%+ uptime)
- DNS latency must be <50ms
- Battery drain must be <5%/day
- No crashes (99.5%+ crash-free rate)

### User Experience
- Setup takes <5 minutes
- Blocking is transparent to child
- Request-approve flow is instant
- Parent dashboard is clear

### Compliance
- Privacy policy accurate
- Data Safety form complete
- VPN declaration done
- DPDP requirements met

### Business Viability
- 50+ beta users by Week 13
- 4+ star rating on Play Store
- <10% churn rate
- Positive word-of-mouth

---

## RESOURCES PROVIDED

1. **PRODUCT_REQUIREMENTS_DOCUMENT.md** - Complete feature specs
2. **IMPLEMENTATION_GUIDE.md** - Code examples & tutorials
3. **nextdns_integration_guide.md** - NextDNS setup
4. **dns_decision_framework.md** - Build vs buy analysis
5. **flutter_models.dart** - Data model templates
6. **ios_screen_time_bridge.swift** - iOS code (for later)
7. **android_vpn_service.kt** - Android VPN code

---

## DAILY ROUTINE (While Building)

### Morning (2-3 hours)
- Pick ONE task from weekly checklist
- Code/build that task
- Commit to Git when working

### Evening (1 hour)
- Test what you built
- Fix bugs
- Update checklist
- Plan tomorrow's task

### Weekly Review (1 hour)
- Review completed tasks
- Test full app flow
- Identify blockers
- Adjust timeline if needed

---

## WHEN YOU GET STUCK

1. **Re-read documentation** - Answer might be there
2. **Test on real device** - Emulator hides issues
3. **Check Firebase console** - Are rules blocking you?
4. **Google the error** - Android errors are well-documented
5. **Ask me** - Come back with specific error messages

---

## SIGNS YOU'RE ON TRACK

✅ Week 2: You can log in on real device  
✅ Week 4: You can add a child profile  
✅ Week 6: VPN starts and notification shows  
✅ Week 8: You can see blocked domains don't load  
✅ Week 10: Schedules trigger at right time  
✅ Week 12: App looks production-ready  

---

## SIGNS YOU'RE OFF TRACK

⚠️ Week 4: Still debugging authentication  
⚠️ Week 6: VPN won't start  
⚠️ Week 8: DNS filtering doesn't work  
⚠️ Week 10: Too many bugs to count  
⚠️ Week 12: Not ready for Play Store  

**If off track:** Simplify scope. Cut non-essential features. Focus on core: Auth + VPN + Blocking.

---

## MINIMUM VIABLE PRODUCT (If You're Behind)

**Must have:**
- Parent sign up/login
- Add 1 child
- Start VPN
- Block social media domains (hardcoded list)
- One schedule (bedtime)
- Basic child status screen

**Can skip for MVP:**
- Multiple children
- NextDNS integration
- Request-approve flow
- Usage reports
- Quick modes

Launch with MVP, add features later.

---

## FINAL CHECKLIST BEFORE LAUNCH

- [ ] App works on 3+ different devices
- [ ] All critical flows tested
- [ ] No crashes in 7-day test
- [ ] Privacy policy published
- [ ] Support email active
- [ ] Play Store listing complete
- [ ] First 10 beta users lined up
- [ ] You're confident in the product

---

**YOU'VE GOT THIS!**

This is a big project but totally doable in 12 weeks as a solo developer.

Stay focused. Ship features. Test constantly. Launch imperfect.

You can iterate after launch. Don't wait for perfect.

---

**Next Steps:**
1. Read PRODUCT_REQUIREMENTS_DOCUMENT.md (understand WHAT to build)
2. Follow IMPLEMENTATION_GUIDE.md (learn HOW to build)
3. Start Week 1 Day 1 checklist
4. Code for 2-3 hours daily
5. Ship in 12 weeks

Good luck! 🚀
