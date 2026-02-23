# TrustBridge Physical Test Instructions (Two Android Phones)

Use this on a different laptop with two real Android phones.

Important:
- Use the same APK on both phones. TrustBridge does not have separate parent/child APKs.
- Parent mode vs child mode is chosen inside the app during setup.

## 1) What You Need

- 2 Android phones with internet
- TrustBridge APK built from this repo
- USB cables (preferred for ADB/logging)
- A test email/password you can use for Firebase login

## 2) Install APK on Both Phones

1. Install the same TrustBridge APK on both phones.
2. Open TrustBridge on both phones.
3. Allow notifications on both phones if prompted.

## 3) Parent Phone Setup

1. On phone A (parent), choose Parent mode.
2. Sign in (email/password).
3. Complete onboarding.
4. Add a child profile (nickname + age band).
5. Open the child profile and generate/show pairing code (6 digits).

Expected:
- Parent dashboard loads.
- Child appears in dashboard/profile.

## 4) Child Phone Setup

1. On phone B (child), choose Child mode.
2. Sign in using the SAME Firebase parent account (same email/password as parent phone).
3. Enter the 6-digit pairing code from parent phone.
4. Grant VPN permission when Android prompts.
5. Grant notification permission.
6. If TrustBridge shows battery optimization guidance:
   - Open Android battery settings
   - Set TrustBridge to `Unrestricted` / `Don't optimize`

Expected:
- Child setup completes.
- Child status screen appears.
- Protection/VPN starts.

## 5) Core Things To Test (Manual Verification)

## A. Real Website Blocking

1. From parent phone, block `reddit.com` (or enable a category that blocks it).
2. On child phone, open Chrome and visit:
   - `https://www.reddit.com`
   - `https://m.reddit.com`
3. Confirm the site does not load (blocked behavior).
4. Unblock it from parent.
5. Retry on child and confirm it loads again.

Expected:
- Block/unblock changes apply within seconds.
- Child should not be able to bypass using Chrome Secure DNS/DoH.

## B. Quick Modes (Homework / Bedtime / Pause)

1. From parent dashboard, trigger:
   - Homework Mode
   - Bedtime Mode
   - Pause Internet / Pause Device
2. Watch child status screen and child browsing behavior.

Expected:
- Child mode label updates quickly.
- Internet blocking behavior changes immediately (or within a few seconds).

## C. Request / Approve / Deny Notifications

1. Make sure something is blocked on child.
2. From child phone, send a Request Access (enter reason + duration).
3. Confirm parent phone receives a push notification.
4. Approve request from parent.
5. Confirm child phone receives approval push notification.
6. Repeat and deny request.
7. Confirm child receives deny push notification.

Expected:
- Push notifications arrive on both devices.
- Approve/deny result is visible to child quickly.

## D. Parent Dashboard Accuracy

1. With child online and browsing blocked sites, watch parent dashboard.
2. Confirm:
   - Child shows online/protected
   - Blocked attempts counter increases while child hits blocked sites

Expected:
- Counter should not stay at a fake placeholder value.

## E. Offline Recovery

1. On child phone, turn on Airplane mode for ~30 seconds.
2. Turn it off and reconnect internet.
3. Retry blocked + allowed sites.

Expected:
- Blocking still works after network returns.
- App should not get stuck.

## F. Delete Child Profile Cleanup (Important)

1. With child paired and protection active, delete the child profile from parent phone.
2. Watch child phone for behavior after deletion.
3. Check whether child returns to setup/unpaired state and protection stops.

Expected:
- Child pairing should be cleared.
- Protection rules should clear/stop.
- Child should not stay permanently blocked after profile deletion.

## G. Reboot Persistence (Device-Specific)

1. Reboot the child phone.
2. Do NOT open TrustBridge yet.
3. Check whether protection/VPN is still active after boot.

Expected:
- On some devices (especially some OEM ROMs), Android may revoke VPN consent after reboot.
- If so, this is a device/OEM behavior and child may need to re-allow VPN.

## 6) Record Results (Simple)

For each test above, write:
- `PASS` / `FAIL` / `PARTIAL`
- What you saw
- Time taken to apply (roughly)

If something fails, capture:
- Screenshot of parent screen
- Screenshot of child screen
- Exact error text (if any)
