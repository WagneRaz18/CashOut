# Deferred Work

## Deferred from: code review of 1-1-xcode-project-setup-with-core-data-and-cloudkit (2026-03-28)

- **W1: `wrappedID` returns new UUID on every nil access** — `Category+CoreDataProperties.swift:18`, `Expense+CoreDataProperties.swift:19`. No ForEach usage yet; will break Identifiable contract when views consume these entities. Fix before Story 1.5+.
- **W2: `fatalError` on store load failure** — `PersistenceController.swift:66`. No graceful degradation if store fails to load. Replace with error propagation or fallback store.
- **W3: `@unchecked Sendable` on PersistenceController** — `PersistenceController.swift:4`. Acceptable singleton pattern but suppresses compiler concurrency checks. Track and ensure no mutable state is added.
- **W4: `handleAccountChange` observer is a no-op** — `PersistenceController.swift:94-97`. Placeholder; replace with async sequence that reconfigures cloudKitContainerOptions on account change.
- **W5: `purgeOldHistory` runs synchronously on main thread** — `PersistenceController.swift:73`. Uses `performAndWait` on background context during init. Move to async for better startup performance.
- **W6: `wrappedCreatedAt`/`wrappedModifiedAt` return `Date()` on nil** — `Expense+CoreDataProperties.swift:22-28`. Same instability as wrappedID; returns different value each access when nil.
- **D1: Share acceptance falls back to private store when no shared store loaded** — `AppDelegate.swift:32-34`. When offline/no iCloud, `stores.first(where:) ?? stores.last` resolves to the private store. Accepting a share into the private store will silently fail. **Address in Story 4-1** (CloudKit shared zone & partner invitation): add guard that bails if no shared-scoped store is found.
- **W7: Category entity missing timestamps/attribution** — `CashOut.xcdatamodel`. Spec intentionally excludes `createdAt`/`modifiedAt`/`createdByUserID` from Category. Revisit if custom category attribution becomes a requirement.

## Deferred from: code review of 1-2-sign-in-with-apple-authentication (2026-03-28)

- **D2: AC #5 "local user profile data cleared" only clears Keychain items** — `AuthenticationService.swift:92-95`. When `.revoked` detected, `clearKeychain()` + `clearProfileKeychain()` remove Keychain entries, but `PersistenceController.handleAccountChange()` remains a no-op from Story 1.1 (W4). Local Core Data records for the previous user are not cleared. Acceptable for v1 (single-device, two known users) but MUST be addressed in Story 4.x alongside the PersistenceController data reconciliation work.

## Deferred from: code review of 1-3-app-shell-and-tab-navigation (2026-03-28)

- **iPad orientation not locked** — `TARGETED_DEVICE_FAMILY = "1,2"` in project.pbxproj includes iPad, but `Info.plist` only defines `UISupportedInterfaceOrientations` (iPhone key). iPad ignores this and requires `UISupportedInterfaceOrientations~ipad`. App is iPhone-only per product brief — consider changing `TARGETED_DEVICE_FAMILY` to `"1"` to eliminate iPad concerns entirely. Pre-existing from Story 1.1 project setup.
