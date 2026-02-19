# TrustBridge Security Checklist (Pre-Alpha)

## Firestore Rules
- [x] Unauthenticated reads denied everywhere
- [x] Cross-user reads denied (parent data is owner-only)
- [x] `children` collection is parent-owned via `parentId == auth.uid`
- [x] `access_requests` create requires parent auth and `status == pending`
- [x] `access_requests` update restricted to parent and `pending -> approved/denied`
- [x] `access_requests` supports parent-only `approved -> expired` for early revocation
- [x] `notification_queue` is client write-only and client read denied
- [x] Catch-all deny enabled for all non-whitelisted paths

## Field Validation
- [x] `children.nickname` string, 1-30 chars
- [x] `children.ageBand` restricted to `6-9`, `10-13`, `14-17`
- [x] `access_requests.appOrSite` string, 1-100 chars
- [x] `access_requests.childNickname` string, 1-30 chars
- [x] `access_requests.reason` optional string, <= 200 chars
- [x] `notification_queue.title` string, 1-100 chars
- [x] `notification_queue.body` string, 1-300 chars
- [x] `notification_queue.route` string, 1-100 chars
- [x] `supportTickets.subject` and `supportTickets.message` validated

## App-Level Security
- [x] PIN lock on Parent Settings access
- [x] PIN lock on VPN Protection access
- [x] PIN lock on Policy management access
- [x] Secure PIN storage via `flutter_secure_storage`
- [x] 60-second grace period to avoid repeated prompts
- [x] Biometric unlock fallback (when available)

## Authentication
- [x] Phone OTP primary auth
- [x] Email fallback auth
- [x] Session persists and auth state gates app entry
- [x] Sign-out clears active session state

## VPN / DNS
- [x] Filtering rules persisted locally in SQLite
- [x] VPN boot recovery path implemented
- [x] DNS logs respect privacy mode and can be cleared
- [x] No raw browsing history uploaded to TrustBridge servers
- [x] Temporary exception removal syncs after approval expiry and manual revoke

## Notifications
- [x] FCM token persisted per parent profile
- [x] Notification queue processed by Cloud Functions
- [x] Client cannot read notification queue payloads

## Pending (Post-Alpha)
- [ ] Per-child Firebase Auth identities (separate from parent account)
- [ ] TLS certificate pinning for outbound APIs
- [ ] Release build obfuscation and hardening pass
- [ ] Play Store security review and policy checklist
- [ ] Optional parent account MFA (2FA)
