# TrustBridge Alpha 1 — Release Notes
**Version:** 1.0.0-alpha.1 (Build 60)  
**Date:** February 17, 2026  
**Platform:** Android 7.0+ (API 24+)

---

## What's in Alpha 1

### ✅ Working Features

**For Parents:**
- Phone OTP login (with email fallback)
- Add/edit/delete child profiles with age-band presets (6-9, 10-13, 14-17)
- Category blocking (social networks, gaming, streaming, adult content, etc.)
- Custom domain blocking
- Schedule-based rules (bedtime, homework, school, custom)
- Quick modes (one-tap focus/lockdown)
- Access request inbox (approve/deny with optional reply)
- Push notifications when child sends a request
- VPN protection screen with live telemetry
- DNS analytics dashboard
- NextDNS integration (optional)
- PIN lock for parent settings

**For Children (on parent's device):**
- Child status screen (current mode, what's paused)
- Request access flow (app/site + duration + reason)
- Real-time request status updates

**Infrastructure:**
- On-device VPN DNS filtering (no cloud logging)
- Policy changes sync to VPN automatically
- Boot recovery (VPN restores after reboot)
- NextDNS fallback health handling

---

## ⚠️ Known Alpha Limitations

1. **Android only** — iOS support coming in v1.1
2. **Single-device per child** — multi-device in v2
3. **No child-specific Firebase accounts** — child uses parent's login on their device
4. **VPN requires physical device** — emulators not supported
5. **NextDNS is optional** — local VPN filtering works without it

---

## 🐛 Known Issues

- Profile run not yet captured (no Android device detected during Day 59/60 automation run)
- Biometric unlock requires Android 6.0+ (API 23)

---

## 📋 What Alpha Testers Should Test

### Critical paths (must work)
1. Install -> Onboarding -> Add child -> Enable VPN
2. Block "Social Networks" -> verify Instagram/Facebook blocked on device
3. Child sends request -> parent gets notification -> approves -> child sees approval
4. Schedule created -> VPN enforces during schedule window
5. App locked with PIN -> child cannot access parent settings

### Please report
- Any screen that crashes
- Any VPN permission issues
- Notification delivery failures
- Incorrect blocking (sites blocked that shouldn't be, or vice versa)
- Battery drain that seems excessive

---

## 🔒 Privacy Reminder

TrustBridge does NOT collect:
- Browsing history
- DNS query logs
- Location data
- Screen content

All filtering happens on your device.

---

**Contact:** [your-email] or GitHub issues  
**Next release:** Beta (targeting Day 75)
