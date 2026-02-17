# Day 61 - Beta Feedback Workflow

## Goal
Capture actionable reports from alpha testers directly inside the app and route
them into a structured queue for triage.

## In-App Flow
1. Parent opens `Settings -> Beta Feedback`.
2. Parent selects:
   - category
   - severity
   - optional child context
3. Parent enters a short title and detailed description.
4. App stores the report in `supportTickets` using a `[Beta]` subject prefix.

## Data Routing
- Collection: `supportTickets`
- Ownership: `parentId`
- Subject format: `[Beta][Severity] Category: Title`
- Message format:
  - category
  - severity
  - optional child id
  - report details
  - submission source marker

This reuses existing secured rules for `supportTickets`, so no additional
Firestore rule deployment is required for Day 61.

## Triage Recommendation
- `Critical`: fix same day or hotfix
- `High`: fix in next patch build
- `Medium`: queue for weekly stabilization sprint
- `Low`: UX polish backlog

## Operator Checklist
- Review new beta tickets daily.
- Group duplicates by normalized title.
- Reply to testers with workaround in release notes when available.
