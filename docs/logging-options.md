# Remote Logging Options for CashOut

Researched 2026-04-08. CashOut is a 2-person TestFlight-only iOS app with CloudKit sync and no custom backend.

## CloudKit Has No Logging

CloudKit is purely sync/storage. No crash reporting, log collection, or analytics.

## Apple Built-ins (No SDK Required)

| Tool | What It Gives You | Limitation |
|------|-------------------|------------|
| **Xcode Organizer** (Window > Organizer > Crashes) | Symbolicated crash reports from TestFlight testers, auto-aggregated | Batched, not real-time. Crash signatures only, no session timeline |
| **`os.Logger`** | Structured local logs visible in Console.app when USB-connected | Logs stay on-device. Useless for partner's device |
| **MetricKit** | Crash diagnostics + performance metrics delivered to app on next launch | Must forward data somewhere. Delivery unreliable on TestFlight |

## Option 1: CloudKit as Log Store (Recommended - Zero New Dependencies)

Write log records to the **private** CloudKit database. View them in [CloudKit Dashboard](https://icloud.developer.apple.com/) > Records.

- Create a `LogEntry` record type: `timestamp`, `level`, `message`, `context`
- Write a thin `RemoteLogger` that batches and saves `CKRecord`s
- No new SDK, no new account, no new dependency
- Already have CloudKit infrastructure

## Option 2: OSLog + In-App "Share Logs" Button

Use `os.Logger` everywhere, add a button that exports the log archive via Messages/AirDrop.

```swift
let store = try OSLogStore(scope: .currentProcessIdentifier)
let entries = try store.getEntries(at: store.position(date: Date().addingTimeInterval(-3600)))
```

- Zero dependencies, fully Apple-native
- Partner taps "Share Logs" and sends the file
- Downside: requires manual action from the user

## Option 3: TelemetryDeck (Lightest Remote Option)

One SPM package, one init line, `.signal("sync.failed", parameters: ["reason": "..."])`.

- 100K signals/month free (may be reduced for new signups post-Winter 2025)
- Privacy-first, EU-hosted, GDPR-compliant
- Not a "logger" per se — carries structured events with metadata
- No crash capture or stack traces

## Decision

**Chosen: Option 1 — CloudKit as log store.** No new dependencies, uses existing infrastructure, logs visible remotely via CloudKit Dashboard.
