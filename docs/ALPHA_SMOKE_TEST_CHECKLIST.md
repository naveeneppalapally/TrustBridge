# Alpha Smoke Test Checklist

## Auth
- [ ] Fresh install -> onboarding shown
- [ ] Phone OTP login works
- [ ] Returning user -> skips onboarding -> dashboard
- [ ] Logout -> login -> back to dashboard

## Child management
- [ ] Add child (all 3 age bands)
- [ ] Edit child nickname
- [ ] Delete child

## Policy
- [ ] Block "Social Networks" category
- [ ] Add custom domain (e.g., `reddit.com`)
- [ ] Create homework schedule (e.g., 3pm-6pm weekdays)
- [ ] Apply Quick Mode: Focus

## VPN (requires device)
- [ ] Enable protection -> VPN icon appears in status bar
- [ ] Notification: "TrustBridge Protection Active"
- [ ] Open blocked site -> does not load
- [ ] Open allowed site -> loads normally
- [ ] Change policy -> VPN syncs automatically
- [ ] Reboot device -> VPN restores
- [ ] Disable protection -> sites load normally

## Request flow
- [ ] Child status screen shows current mode
- [ ] Child sends request (Instagram, 30 min, with reason)
- [ ] Parent receives notification
- [ ] Parent approves with reply
- [ ] Child sees "Approved" status + parent reply

## Security
- [ ] Enable PIN
- [ ] Try accessing Parent Settings -> PIN required
- [ ] Enter wrong PIN -> error shown
- [ ] Enter correct PIN -> access granted
- [ ] Within 60s -> no re-prompt
- [ ] Disable PIN (requires current PIN)

## Analytics
- [ ] Protection Analytics screen loads
- [ ] Shows blocked count (after some browsing)
- [ ] Per-child policy summary shows

## Onboarding re-entry
- [ ] Settings -> Setup Guide -> onboarding reopens
