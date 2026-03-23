---
title: "Product Brief Distillate: CashOut"
type: llm-distillate
source: "product-brief-CashOut.md"
created: "2026-03-23"
purpose: "Token-efficient context for downstream PRD creation"
---

# CashOut — Detail Pack for PRD Creation

## Competitive Intelligence

- **Honeydue** — free couples finance app, bank-linked, no fast cash entry, users report buggy syncing and stale development
- **YNAB** — $14.99/mo, zero-based budgeting philosophy, steep learning curve, cash entry buried in complex workflow, "YNAB Together" for couples is an add-on
- **Monarch Money** — $14.99/mo, premium all-in-one dashboard, cash tracking is manual afterthought in complex UI, overkill for cash-only use case
- **Goodbudget** — digital envelope budgeting, manual entry by design, dated UI, household sharing but not couples-first, no real-time sync
- **Splitwise** — expense splitting (who-owes-whom), not a spending tracker, no category breakdowns or budget views
- **Cashew** — clean modern expense tracker, fast manual entry, but single-user only — no couples/shared mode
- **PocketGuard** — automated budget tracker, entirely digital-transaction focused, limited couples support
- **EveryDollar** — Dave Ramsey-affiliated, couples share one login (not individual views), premium required for bank sync ($17.99/mo)
- **No existing app** is purpose-built for the trifecta: cash-specific + couples sharing + speed-first entry

## Market Context

- Personal finance app market ~$25.8B in 2026, projected $167.6B by 2035 (20.57% CAGR)
- ~36% of households use shared budgeting apps — behavior is normalized
- Cash still accounts for 16-18% of in-person US transactions (2025), concentrated in small-dollar purchases
- Over 90% of US consumers still intend to use cash (2025 Federal Reserve data)
- "Cash stuffing" / envelope budgeting trending on TikTok — cultural awareness of deliberate cash usage is growing
- Speed is make-or-break: users want to log a purchase in under 5 seconds or they stop using the app entirely
- Manual entry fatigue is the #1 complaint across all cash tracking apps

## Rejected / Deferred Ideas (with rationale)

- **Cash withdrawal tracking with reconciliation** — user doesn't want it; just wants to see how much was spent, not track against withdrawals. Deferred indefinitely.
- **Budget/goal setting per category** — deferred to v2; contradicts v1 "one thing done well" philosophy
- **Receipt photo capture** — deferred to v2; adds camera permissions, storage complexity, and UI surface area for unclear v1 value
- **Smart reminders / notifications** — deferred to v2; user wants v1 lean
- **Bank account linking** — permanent non-goal, not a deferral. Framed as privacy advantage.
- **Multi-currency support** — out of scope entirely
- **App Store public launch** — v1 is personal use for the user and his wife only

## Requirements Hints

- Entry flow must be completable in under 5 seconds from app open — this is the non-negotiable UX constraint
- Categories must be both predefined (sensible defaults) and customizable (user can add/edit)
- Both partners must see all entries in real-time — shared household is the core data model
- Daily, weekly, and monthly views are all required — user specifically called out all three time horizons
- iOS 26+ only — user specified this explicitly
- The app must be "very quick and intuitive" — speed and intuitiveness are equal priorities
- v1 audience is exactly 2 users (the user and his wife) — no need for onboarding flows, App Store optimization, or scalability concerns in v1

## Technical Context

- Platform: iOS 26+ (SwiftUI likely, given modern iOS target)
- Sharing mechanism: needs real-time sync between two users — CloudKit shared databases or similar
- No custom backend required for v1 (2-user personal use)
- No bank integrations, no Plaid, no financial credential handling
- No multi-currency — single currency only
- Privacy-first: no data leaves device/iCloud boundary

## User Scenarios (beyond exec summary)

- **Primary scenario:** User buys coffee with cash → opens CashOut → taps "Food & Drink" → types "5" → done. Wife sees it immediately on her phone.
- **Insight scenario:** End of week, couple opens the weekly view → sees they spent $120 on eating out (cash) → "oh wow, that's where the money is going" → informed discussion about spending habits
- **Asymmetric adoption risk:** One partner logs diligently, the other forgets → shared view becomes unreliable → trust in data collapses. Invite flow and minimal friction for second partner are critical.

## Open Questions

- Authentication strategy: Sign in with Apple + Face ID for speed? iCloud-based identity?
- Default category set: What are the predefined categories? (e.g., Food & Drink, Transport, Entertainment, Household, Shopping, Other)
- Data model for "household": How are two users paired? Invite flow? What happens on partner removal?
- Offline behavior: What happens when one partner logs while offline? Conflict resolution on sync?
- Edit/delete: Can entries be edited or deleted after creation? By either partner or only the one who logged it?

## Scope Signals Summary

| Feature | Status | Rationale |
|---|---|---|
| Fast expense entry | v1 | Core value prop |
| Predefined + custom categories | v1 | Essential for insights |
| Shared household (real-time) | v1 | Core differentiator |
| Daily/weekly/monthly views | v1 | "aha moment" driver |
| Budget/goal setting | v2 | Scope discipline |
| Receipt photo capture | v2 | Scope discipline |
| Cash withdrawal tracking | v2+ | User doesn't want it in foreseeable scope |
| Smart reminders | v2 | Keep v1 lean |
| Bank linking | Never | Permanent design decision |
| Multi-currency | Never | Out of scope |
| Ads | Never | Non-goal |
