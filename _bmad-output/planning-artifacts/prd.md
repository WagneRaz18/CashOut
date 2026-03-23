---
stepsCompleted: ['step-01-init', 'step-02-discovery', 'step-02b-vision', 'step-02c-executive-summary', 'step-03-success', 'step-04-journeys', 'step-05-domain-skipped', 'step-06-innovation-skipped', 'step-07-project-type', 'step-08-scoping', 'step-09-functional', 'step-10-nonfunctional', 'step-11-polish', 'step-12-complete']
inputDocuments:
  - product-brief-CashOut.md
  - product-brief-CashOut-distillate.md
documentCounts:
  briefs: 2
  research: 0
  brainstorming: 0
  projectDocs: 0
workflowType: 'prd'
classification:
  projectType: mobile_app_ios
  domain: fintech_personal_finance
  complexity: low
  projectContext: greenfield
---

# Product Requirements Document - CashOut

**Author:** Boss
**Date:** 2026-03-23

## Executive Summary

CashOut is an iOS app that makes cash spending visible between partners — instantly. Built for couples who use cash regularly and can't account for where it goes, CashOut replaces the "where did the money go?" conversation with shared, real-time spending data. The core experience is a 3-tap expense entry flow completable in under 5 seconds: open, tap a category, enter the amount, done. Both partners see every entry immediately. Daily, weekly, and monthly breakdowns by category surface spending patterns that were previously invisible.

v1 is a personal-use app for two users (the builder and his wife). There is no App Store launch, no onboarding flow, no scalability concern. The audience is exactly two people solving a real, felt problem: they spend a lot of cash and don't know on what.

### What Makes This Special

No existing app combines cash-specific design, couples-first shared visibility, and speed-obsessed entry into a single purpose-built tool. General budgeting apps (YNAB, Monarch) treat cash as an afterthought buried behind complex workflows. Couples finance apps (Honeydue) focus on bank-linked transactions. Single-user trackers (Cashew) lack shared visibility. CashOut's narrowness is the moat — it does one thing better than all of them by refusing to do anything else.

Speed is the product thesis. Manual entry fatigue kills every cash tracking app. If logging a purchase takes more than 5 seconds, the habit dies, the data becomes unreliable, and the tool becomes worthless. CashOut treats the 5-second constraint as a hard design principle, not an aspiration.

Privacy is a design decision, not a limitation. CashOut never asks for bank credentials. No Plaid integration, no financial data sharing, no breach surface area. Data stays within the device/iCloud boundary.

## Project Classification

- **Type:** Native iOS mobile app (iOS 26+, SwiftUI, CloudKit)
- **Domain:** Personal finance / expense tracking (unregulated scope — no bank linking, no payment processing, no financial credentials)
- **Complexity:** Low — deliberately sidesteps all regulated fintech concerns
- **Context:** Greenfield — new product, no existing codebase

## Success Criteria

### User Success

- Both partners log at least one cash purchase per day, sustaining the habit beyond the typical 2-week drop-off point for manual tracking apps
- Entry flow feels effortless — neither partner experiences friction that makes them consider skipping a purchase
- Weekly and monthly views reveal spending patterns that were previously invisible, producing genuine "I didn't realize we spent that much on X" moments
- Cash conversations between partners shift from "where did the money go?" to specific, informed, data-driven discussions

### Business Success

- **Problem solved:** The couple can answer "where did our cash go this week?" with specific, category-level data — the original pain point is resolved
- **Sustained personal use:** Both users are still actively logging after 30 days — the app has become part of the daily routine, not another abandoned tool
- **Worth the build:** The app delivers enough value that the builder would build it again knowing the effort involved

### Technical Success

- Expense entry flow is as fast as possible — speed is a priority but not a hard numeric gate
- Real-time sync between both users via CloudKit — entries appear on the partner's device within seconds
- App launches instantly and is responsive — no loading screens, no spinners for core entry flow
- Data integrity — no lost entries, no sync conflicts that silently drop data

### Measurable Outcomes

| Metric | Target | Measurement |
|---|---|---|
| Daily logging | At least 1 entry per user per day | App usage data |
| Daily habit retention | Both users logging at 30 days | App usage data |
| Sync latency | Entries visible to partner within seconds | Observable in testing |
| Data accuracy | Zero lost or duplicated entries | Spot-check against remembered purchases |
| Spending visibility | Can answer "where did cash go this week?" with specific data | Weekly review |

## Product Scope

### MVP Strategy & Philosophy

**MVP Approach:** Problem-solving MVP — deliver the minimum feature set that makes cash spending visible between two partners. The product either solves "we don't know where our cash goes" or it doesn't. There's no partial credit.

**Resource Requirements:** Solo developer. No team dependencies, no coordination overhead. Ship when it's ready, iterate based on real usage by both partners.

### MVP Feature Set (Phase 1)

**Core User Journeys Supported:**
- Quick Log (primary value delivery)
- Fix-Up (error recovery — essential for data trust)
- Insights (the payoff that sustains the habit)
- Partner Onboarding (without this, it's a single-user app)

**Must-Have Capabilities:**
- Ultra-fast expense entry: category + amount + optional note
- Predefined spending categories with sensible defaults (Food & Drink, Transport, Entertainment, Household, Shopping, Other)
- Custom categories (add/edit)
- Shared household via CloudKit — both partners see all entries in real-time
- Daily, weekly, and monthly spending views with category breakdowns
- Edit and delete entries with real-time sync
- Sign in with Apple
- Local-first persistence with offline queue and background sync
- Last-write-wins conflict resolution
- iOS 26+, SwiftUI

### Post-MVP Features

**Phase 2 (Growth):**
- Widgets for quick entry without opening the app
- Budget/goal setting per category
- Receipt photo capture
- Smart reminders to log spending
- Category spending trends over time (month-over-month)

**Phase 3 (Expansion):**
- Siri/Shortcuts integration for voice-based entry
- Cash withdrawal tracking with reconciliation (if ever desired)

### Permanent Non-Goals

- Bank account linking — privacy by design, not a deferral
- Multi-currency support
- App Store public launch (v1)
- Ads — never
- Becoming a full budgeting suite — never

### Risk Mitigation Strategy

**Technical Risks:**
- **CloudKit shared database pairing** is the primary technical unknown. This is the riskiest piece of the build — getting two users connected to a shared CloudKit zone without a custom backend. Mitigation: prototype the CloudKit sharing flow first, before building any UI. If the pairing mechanism doesn't work smoothly, the entire product premise is at risk. This should be the first spike.
- **Offline sync edge cases** — last-write-wins is simple but could produce surprising results if both partners edit simultaneously. Mitigation: acceptable for 2 users with low collision probability. Monitor in real usage.

**Market Risks:**
- None in the traditional sense — v1 audience is the builder and his wife. The only validation needed is: do they use it?

**Resource Risks:**
- Solo developer means no parallelism. Mitigation: the scope is deliberately small. No backend, no App Store review, no multi-platform. Apple platform services (CloudKit, Sign in with Apple) handle the infrastructure.

## User Journeys

### Journey 1: The Quick Log (Core Experience — Happy Path)

**Sarah** just paid $12 cash for lunch at the taco truck. She's standing on the sidewalk, phone in hand, about to put it back in her pocket.

She opens CashOut. The entry screen is right there — no navigation needed. She taps "Food & Drink," types "12," and hits save. Done. She's already walking back to the office. Three seconds, maybe four.

Twenty minutes later, her partner opens CashOut to log his own parking meter. He sees Sarah's taco lunch in the feed. No surprise, no conversation needed — it's just there. Visible. Accounted for.

**What this reveals:** The app must open directly to entry (or one tap away). Category selection must be a single tap. Amount entry must be minimal keystrokes. Save must be instant. The feed must update in real-time on both devices.

### Journey 2: The Fix-Up (Edit/Delete — Error Recovery)

**Mark** just logged $50 for groceries. Except it was $15 — he fat-fingered it. He sees the entry in the feed, taps it, changes the amount to $15, saves. The corrected amount syncs to Sarah's phone immediately.

Later, Sarah notices a duplicate entry from yesterday — she accidentally logged the same coffee twice. She taps the entry, deletes it, confirms. Gone from both devices.

**What this reveals:** Entries must be tappable from the feed to edit. Edit flow should mirror the entry flow (same speed, same simplicity). Delete requires a confirmation to prevent accidents. Edits and deletes must sync in real-time just like new entries.

### Journey 3: The "Where Did It Go?" Moment (Insights — The Payoff)

It's a random Wednesday evening. Sarah is curious — it feels like they've been spending a lot of cash lately. She opens CashOut and swipes to the weekly view. The category breakdown shows $85 on Food & Drink, $40 on Entertainment, $25 on Transport. She taps into monthly view — Food & Drink is $340 this month. "Hey, did you know we've spent $340 on food with cash this month?" The conversation that follows is specific, informed, and productive — not the old vague "where did all the money go?"

**What this reveals:** Switching between daily/weekly/monthly views must be effortless (swipe or tab). Category breakdowns must be scannable at a glance — totals per category, visually clear. The data must tell a story without requiring the user to do math.

### Journey 4: The Second Partner Onboarding

Mark has built CashOut and is using it. Now his wife Sarah needs to be on it too. She installs the app, signs in with Apple, and is immediately connected to the shared household. She sees Mark's entries from today already in the feed. She logs her first purchase. Mark sees it on his phone seconds later. No invite codes, no account setup, no configuration — it just works.

**What this reveals:** The pairing/household setup must be as frictionless as possible. iCloud/CloudKit shared database handles the connection. The second user's experience must be instant — install, sign in, start using. No onboarding screens, no tutorials.

### Journey Requirements Summary

| Journey | Key Capabilities Required |
|---|---|
| Quick Log | Instant app-to-entry flow, single-tap categories, minimal-keystroke amount, real-time sync |
| Fix-Up | Tap-to-edit from feed, edit mirrors entry flow, delete with confirmation, synced edits/deletes |
| Insights | Daily/weekly/monthly views, category breakdowns, scannable totals, effortless view switching |
| Partner Onboarding | Sign in with Apple, automatic household connection via CloudKit, zero-config pairing |

## Mobile App Specific Requirements

### Project-Type Overview

CashOut is a native iOS app targeting iOS 26+ built with SwiftUI. It is a single-platform, 2-user personal app with no App Store distribution in v1. The technical surface is deliberately minimal: CloudKit for real-time sync, Sign in with Apple for authentication, and local persistence for offline support.

### Technical Architecture Considerations

- **Platform:** Native iOS 26+, SwiftUI
- **Sync:** CloudKit shared database for real-time household data sharing
- **Auth:** Sign in with Apple — no custom auth backend
- **Storage:** Local persistence (SwiftData or Core Data) with CloudKit sync
- **No custom backend:** All infrastructure runs on Apple's platform services (iCloud, CloudKit)

### Platform Requirements

- iOS 26+ minimum deployment target
- SwiftUI for all UI
- No Android, no web, no cross-platform
- No App Store submission for v1 — distributed via TestFlight or direct install

### Device Permissions

- iCloud/CloudKit access (required for sync)
- Sign in with Apple (required for auth)
- No camera, location, microphone, contacts, or other device permissions needed in v1

### Offline Mode

- All expense entries are persisted locally first, then synced to CloudKit
- If the device is offline, entries queue locally and sync automatically when connectivity returns
- Conflict resolution: last-write-wins, thread-safe — if both partners edit the same entry while offline, the most recent save overwrites the earlier one
- The app must be fully functional for entry and viewing local data while offline

### Push Strategy

- No push notifications in v1
- Deferred to v2 (smart reminders to log spending)

### Store Compliance

- Not applicable for v1 — personal use only, no App Store launch
- Future consideration if the app is ever published

### Implementation Considerations

- Entry flow must be the default screen on app launch — zero navigation to start logging
- SwiftUI animations and transitions should feel instant — no perceptible lag
- CloudKit subscription for real-time push sync to partner's device (CKSubscription)
- Local-first architecture ensures speed: write locally, sync in background

## Functional Requirements

### Expense Entry

- FR1: User can create a new expense entry by selecting a category and entering an amount
- FR2: User can optionally add a text note to an expense entry
- FR3: User can save an expense entry and have it immediately persisted locally
- FR4: User can access the entry flow directly on app launch with zero navigation

### Expense Management

- FR5: User can view a chronological feed of all household expense entries
- FR6: User can tap an existing entry to edit its category, amount, or note
- FR7: User can delete an existing entry with a confirmation prompt
- FR8: User can see which partner logged each entry

### Spending Categories

- FR9: User can select from a set of predefined default categories (Food & Drink, Transport, Entertainment, Household, Shopping, Other)
- FR10: User can create custom spending categories
- FR11: User can edit existing custom categories
- FR12: User can select any category (predefined or custom) with a single tap during entry

### Spending Insights

- FR13: User can view a daily spending breakdown by category
- FR14: User can view a weekly spending breakdown by category
- FR15: User can view a monthly spending breakdown by category
- FR16: User can switch between daily, weekly, and monthly views effortlessly
- FR17: User can see total spending per category within any selected time period
- FR18: User can see overall total spending within any selected time period

### Household & Sharing

- FR19: User can sign in with Apple to authenticate
- FR20: Both household members can view all expense entries in a shared feed in real-time
- FR21: Both household members can see edits and deletes reflected in real-time
- FR22: Second partner can join the shared household by installing the app and signing in — no invite codes or manual configuration

### Offline & Sync

- FR23: User can create, edit, and delete entries while offline
- FR24: User can view all locally stored entries while offline
- FR25: System syncs queued offline changes automatically when connectivity returns
- FR26: System resolves sync conflicts using last-write-wins strategy

## Non-Functional Requirements

### Performance

- App launch to entry-ready state must be near-instant — no splash screens, no loading spinners
- Expense entry save must feel immediate — local persistence completes with no perceptible delay
- Switching between daily/weekly/monthly views must be instant with no loading states
- Scrolling through the expense feed must be smooth with no frame drops
- CloudKit sync must operate in the background without blocking any user interaction

### Security & Privacy

- All data is encrypted at rest (Apple Data Protection) and in transit (CloudKit TLS)
- No spending data is accessible outside the household's shared CloudKit zone
- Authentication via Sign in with Apple — no custom credential storage
- No analytics, telemetry, or third-party SDKs that transmit user data
- No data leaves the device/iCloud boundary

### Data Management

- System retains expense data for a rolling 6-month window
- Data older than 6 months may be archived or purged
- No data loss during normal sync operations — local-first persistence guarantees durability
- Deletes and edits must propagate fully to both devices — no orphaned or ghost entries
