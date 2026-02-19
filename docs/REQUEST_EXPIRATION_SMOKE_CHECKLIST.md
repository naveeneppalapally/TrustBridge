# Request Expiration Smoke Checklist

## Goal
Verify approved access windows consistently expire across parent UI, child UI,
and VPN enforcement.

## End-to-End Flow
- [ ] Child submits a request (`appOrSite`, duration, optional reason)
- [ ] Parent approves with a timed duration (e.g., 15 min)
- [ ] Child immediately sees approved access in status/updates screens
- [ ] Parent history shows approved request with `Ends in ...`
- [ ] After expiry time passes, child UI shows `Expired ... ago` (without waiting for backend sweep)
- [ ] Parent history shows expired status and no active revoke action
- [ ] Access to the previously approved domain is blocked again

## Manual Early End Flow
- [ ] Parent opens History for an active approved request
- [ ] Parent taps `End Access Now` and confirms
- [ ] Request transitions to `expired`
- [ ] Child UI updates promptly to expired state
- [ ] Access to approved domain is blocked again

## Backend Sweep Verification
- [ ] Cloud Function `expireApprovedAccessRequests` runs on schedule
- [ ] Logs include `totalExpired`, `batchesProcessed`, `durationMs`
- [ ] No failures in function logs for expiry sweep

## Edge Cases
- [ ] `until schedule ends` approvals remain active (no fixed expiry label)
- [ ] Already-expired approvals do not show `End Access Now`
- [ ] Multiple active approvals show independent expiry labels
- [ ] App restart does not revert expired requests back to approved UI state
