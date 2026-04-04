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

## Deferred from: story creation of 1-4-design-tokens-predefined-categories-and-repository-layer (2026-03-28)

- **W8: Category sync race condition on partner device** — When device B launches before CloudKit sync delivers device A's seeded categories, the zero-count idempotency guard in `seedDefaultCategoriesIfNeeded()` passes and device B seeds its own 6 categories with different UUIDs. For Epic 1 (solo mode) this is harmless — both devices have identical defaults with matching names/colorNames. **Address in Story 4.x**: either (a) use stable string keys (e.g., `colorName`) for cross-device category matching instead of UUID FK, or (b) implement sync-aware seeding that observes `.NSPersistentStoreRemoteChange` before running the zero-count guard.
- **W9: Private vs shared store entity routing (also flagged in code review)** — `.xcdatamodel` has no named configurations, so all entities (Category, Expense) route to the private store (first `NSPersistentStoreDescription` in the array). For Epic 1 (solo mode) this is correct. **Address in Story 4.1**: add named configurations to `.xcdatamodel` — a "Shared" configuration containing Category and Expense, assigned to the shared `NSPersistentStoreDescription` via its `configuration` property. Must be done before implementing household sharing.

## Deferred from: code review of 1-4-design-tokens-predefined-categories-and-repository-layer (2026-03-28)

- **F6: `wrappedID` generates new UUID on nil — identity instability** — `Category+CoreDataProperties.swift:18`, `Expense+CoreDataProperties.swift:18`. Pre-existing issue (W1). Re-confirmed by adversarial and edge-case review layers.
- **F7: `seedDefaultCategoriesIfNeeded` race condition (W8 re-confirmed)** — Check-then-act in `CategoryRepository.swift:48-67` not atomic w.r.t. CloudKit background merges. Deferred to Story 4.x.
- **F8: `CategoryColor.init?(from:)` / `wrappedColorName` mismatch** — `wrappedColorName` returns `"gray"` when nil, but `CategoryColor` has no `gray` case — returns nil. Pre-existing in CoreDataProperties wrappers.
- **F9: Hard delete tombstone propagation window** — `ExpenseRepository.swift` uses `context.delete()` (hard delete). Tombstone window expiry can leave orphaned records on offline partner. Acceptable for Epic 1 solo mode.
- **F10: Entity store routing undefined (W9 re-confirmed)** — No named configurations in `.xcdatamodel`. Deferred to Story 4.1.

## Deferred from: code review of 1-5-numpad-and-amount-display (2026-03-29)

- **D1: Negative `amountInCents` not guarded** — `ExpenseEntryViewModel.swift:9`. `amountInCents` is `var` (required by @Observable). No UI path produces negative values, but `appendDigit` on negative values makes them more negative and `isAmountZero` returns `false`. Validate at persistence boundary in Story 1.6.
- **D2: `appendDigit` accepts multi-character strings** — `ExpenseEntryViewModel.swift:22`. `Int64("10")` succeeds, appending 10 instead of a single digit. Only called from hardcoded NumpadKey enum; no realistic UI path. Guard at caller boundary if accessibility/paste handling added.
- **D3: Locale-dependent test assertions fragile for Thai digit rendering** — `Int64CurrencyTests.swift`. Tests use `contains("12.50")` etc. Explicit `th_TH` locale should produce Western Arabic digits consistently, but Thai digit substitution (`๐-๙`) could occur on certain system locale + OS version combinations. Monitor on future OS updates.
- **D4: Stale UX spec references** — `ux-design-specification.md` still references `.glassEffect()`, `.monospacedDigit()`, and `"$"` USD symbol. Story spec captured corrections via UX-DR1 and UX-DR2 notes. Update UX spec document separately.
- **D5: InsightsView calls `.displayAmount` directly in View body** — `InsightsView.swift:6`. `Int64(0).displayAmount` in View body bypasses ViewModel boundary. Acceptable for current placeholder; architect properly when InsightsViewModel is built.

## Deferred from: code review of 1-7-entry-screen-haptics-accessibility-and-dynamic-type (2026-04-02)

- **D1: Category chip double "selected" VoiceOver announcement** — `CategoryPickerView.swift:65-66`. `.accessibilityLabel("Food, selected")` + `.accessibilityAddTraits(.isSelected)` may produce double announcement. Per-spec intentional. Verify on physical device.
- **D2: AmountDisplayView VoiceOver pronunciation of ฿ symbol** — `AmountDisplayView.swift:13`. `"Amount: \(amount.displayAmount)"` includes ฿ symbol; VoiceOver pronunciation varies by system language. Verify on physical device.
- **D3: makeSUT 6-tuple positional fragility** — `ExpenseEntryViewModelTests.swift:132`. Pre-existing pattern; adding each new dependency extends the tuple. Consider named struct if 7th dependency added.
- **D4: HapticService creates new generator per call — no prepare()** — `HapticService.swift:19-23`. Apple recommends reusing generators and calling `prepare()`. Architecture decision per spec; future optimization candidate.
- **D5: HapticService @MainActor tension with iOS 26 SDK** — `HapticService.swift:15`. Protocol is nonisolated but UIKit generators are @MainActor in iOS 26. Known, documented in learnings. Broader protocol redesign needed.
- **D6: SaveButton/note button accessibilityHints** — `SaveButtonView.swift:19,30`. No `.accessibilityHint` on either button. Nice-to-have for VoiceOver users.

## Deferred from: code review of 2-2-floating-add-button (2026-04-03)

- **D1: Silent save error in non-DEBUG builds** — `EntryView.swift:38-41`. `catch` block only prints in `#if DEBUG`; release builds show no user feedback on save failure. Pre-existing from Story 1-6. Needs UX design for error surface.
- **D2: Tab 0 EntryView not wrapped in NavigationStack** — `ContentView.swift:9-11`. Feed and Insights tabs each wrap in NavigationStack, but Add tab does not. Pre-existing since Story 1-5; intentional leaf screen. Revisit if EntryView needs navigation destinations.
- **D3: `.buttonBorderShape(.circle)` may be no-op with `.glassProminent`** — `FloatingAddButton.swift:15`. Learnings record that `.buttonBorderShape` only takes effect with `.bordered`/`.borderedProminent`. May be a no-op with glass styles. Needs on-device verification; `.clipShape(.circle)` is the documented fallback if needed.

## Deferred from: code review of 2-1-expense-feed-with-partner-attribution (2026-04-02)

- **W1: `FeedView` does not display `viewModel.errorMessage`** — `FeedView.swift`. ViewModel exposes `errorMessage` set when category fetch fails, but the view never reads or displays it. Needs UX design decision for error states.
- **W2: `wrappedID` returns `id ?? UUID()` — unstable identity if `id` is nil** — `Expense+CoreDataProperties.swift:19`. Pre-existing (re-confirmed from W1 in Story 1.1). Each access generates a different UUID, breaking ForEach identity.
- **W3: `ExpenseData`/`CategoryData` lack `Equatable`** — Pre-existing models. Without Equatable, SwiftUI cannot optimize row diffing in List. Consider adding conformance when edit/delete flows are built (Story 2.3+).
- **W4: Brief "Unknown" category flash on initial load** — `FeedView.swift`, `FeedViewModel.swift`. FRC fires expenses before async category fetch completes, briefly showing "Unknown" for all rows. UX polish candidate.
- **W5: Tests use `Task.sleep(50ms)` for async synchronization** — `FeedViewModelTests.swift:91`. Fragile on CI. Existing project-wide pattern; consider mock-driven expectation fulfillment if flakiness appears.

## Deferred from: code review of 2-3-edit-expense-flow (2026-04-03)

- **D1: Save failure silent in RELEASE — no error UI** — `EditExpenseSheet.swift:48`. Catch block only prints in `#if DEBUG`; release builds show no user feedback on save failure. Same pre-existing pattern as `EntryView` (D1 from Story 2-2).
- **D2: Haptic fires for rejected digit at cap boundary** — `EditExpenseViewModel.swift:60`. `hapticService.trigger(.numpadKey)` fires before `guard amountInCents < maxBeforeAppend`. User feels haptic but digit is ignored. Same in `ExpenseEntryViewModel`.
- **D3: Whitespace-only noteText persisted as non-nil** — `EditExpenseViewModel.swift:113`. `noteText.isEmpty` doesn't catch `"   "`. Should use `trimmingCharacters(in: .whitespaces).isEmpty`. Same in `ExpenseEntryViewModel`.
- **D4: loadCategories error silently swallowed** — `EditExpenseViewModel.swift:90`. Catch block is empty with a comment. Should log via `os_log(.error)`. Same pattern in `ExpenseEntryViewModel`.
- **D5: appendDecimalPoint fires haptic for a no-op** — `EditExpenseViewModel.swift:80`. Decimal point is no-op in satang model, but haptic still fires. Pre-existing in `ExpenseEntryViewModel`.

## Deferred from: code review of 2-4-delete-expense-flow (2026-04-03)

- **F2: Race condition — edit sheet open while expense deleted re-creates expense on save** — `FeedView.swift` + `EditExpenseViewModel.swift`. If edit sheet is open and the expense is deleted (by partner sync or swipe), `saveExpense()` calls `ExpenseRepository.saveExpense()` which re-creates the managed object if not found. Pre-existing from Story 2-3.
- **F3: `context.save()` failure after `context.delete()` leaves dirty Core Data context** — `ExpenseRepository.swift:142-144`. No `context.rollback()` on save failure. Pending deletion commits on next successful save from any operation. Pre-existing.
- **F4: `.onAppear` instead of `.task` for FeedView lifecycle** — `FeedView.swift:56-58`. `.task {}` is preferred for async lifecycle work and auto-cancels on disappear. `isObserving` guard prevents double-invocation, so current code is safe. Pre-existing from Story 2-1.

## Deferred from: code review of 3-2-category-donut-chart (2026-04-04)

## Deferred from: code review of 3-3-daily-bar-chart-and-category-breakdown-list (2026-04-04)

- **D1: `DateInterval()` fallback passes Jan 1 2001 to FilteredFeedView** — `InsightsView.swift:73`. `viewModel.currentPeriodInterval ?? DateInterval()` falls back to a zero-duration interval at Jan 1, 2001. Navigation can't trigger before loadData in practice (selectedCategoryID starts nil), but a guard disabling navigation when interval is nil would be cleaner. Pre-existing from story 3-2.

## Deferred from: code review of 3-2-category-donut-chart (2026-04-04)

## Deferred from: code review of 4-1-cloudkit-shared-zone-and-partner-invitation (2026-04-04)

- **W1: AppDelegate:34 uses `print()` for share acceptance error** — `AppDelegate.swift:34`. Pre-existing logging inconsistency. Should use `os_log(.error)` for production trace.
- **W2: PersistenceController uses `fatalError` on store load failure** — `PersistenceController.swift:77`. No graceful degradation if shared store fails to load. Replace with error propagation or fallback to solo mode for shared store.
- **W3: `sharedPersistentStore` nil when iCloud unavailable — silent share rejection** — `AppDelegate.swift:28`. When iCloud is unavailable at launch, shared store is never created. Partner acceptance silently fails until app restart. Needs `handleAccountChange()` implementation.
- **W4: Multiple SettingsView instances from tab navigation — no shared state** — `FeedView.swift:58`, `InsightsView.swift:81`. Each tab creates independent SettingsView/SettingsViewModel/CloudSharingService. State not shared across navigations. Consider singleton CloudSharingService or environment injection.

## Deferred from: code review of 4-2-partner-share-acceptance-and-data-sync (2026-04-04)

- **D1: PersistenceController stores may not be loaded on cold launch** — `ContentView.swift:40`. `checkSharingStatus()` runs at app launch but persistent stores load asynchronously. Both `privatePersistentStore` and `sharedPersistentStore` may be nil, causing the method to fall through to solo mode. Pre-existing from Epic 1 PersistenceController design.
- **D2: ContentView MVVM boundary violation** — `ContentView.swift:40-47`. View directly calls `CloudSharingService.shared` instead of routing through a ViewModel. Spec-directed pragmatic choice. Consider app-scoped ViewModel for startup checks.
- **D3: `createShare` reuses stale `currentShare`** — `CloudSharingService.swift:58`. No staleness or server-side validity check before returning cached share to UICloudSharingController. Pre-existing from story 4-1.
- **D4: `SettingsViewModel.handleShareDismiss` fire-and-forget Task** — `SettingsViewModel.swift:67`. Task not stored or cancelled. Pre-existing from story 4-1.
- **D5: `invitePartner` race with async category seeding** — `SettingsViewModel.swift:35`. Share created from categories; if seeding hasn't completed on new install, invite fails with "No categories found". Pre-existing from story 4-1.
- **D6: Cold-launch share acceptance timing** — `AppDelegate.swift:29` / `ContentView.swift:40`. When app launches via share URL, `checkSharingStatus()` may fire before `acceptShareInvitations` completes. Notification listener will catch the store change eventually.

## Deferred from: code review of 4-3-real-time-feed-updates-and-sync-management (2026-04-04)

- **D1: InsightsView dual `.task` race on startup** — `InsightsView.swift:96-101`. Two `.task` modifiers run concurrently: `.task(id:)` calls `loadData()` while `.task` calls `subscribeToRemoteChanges()` which immediately fires `invalidateAndReload()`. Both can pass the `loadedPeriod` guard simultaneously on first tab open. Pre-existing from story 3-1.
- **D2: `@ObservationIgnored` on `let` constants in FeedViewModel** — `FeedViewModel.swift:21-25, 32-33`. Three `let` properties (`categoryRepository`, `authService`, `hapticService`) carry redundant `@ObservationIgnored`. `let` constants are never tracked by `@Observable`. Pre-existing.
- **D3: Buddhist calendar force-unwrap crash in InsightsViewModel** — `InsightsViewModel.swift:294, 299-300`. `Calendar.current.dateInterval(of:for:)!` and `Calendar.current.date(byAdding:)!` can return nil on Buddhist calendar (default on Thai devices). Pin to `Calendar(identifier: .gregorian)`. Pre-existing from story 3-1.
- **D4: ContentView remote-change guard misses share-revoked** — `ContentView.swift:45`. `guard !CloudSharingService.shared.isShared` skips all `checkSharingStatus()` refreshes once shared. If partner revokes share, `isShared` remains stale. Pre-existing from story 4-2.
- **D5: Test sleep-polling pattern fragile** — `FeedViewModelTests.swift:99-104`. Uses `Task.sleep(50ms)` + `XCTestExpectation` for async synchronization. Fragile on slow CI. Pre-existing from story 2-1.

## Deferred from: code review of 3-2-category-donut-chart (2026-04-04)

- **D1: Default `AuthenticationService()` in ViewModel init** — All ViewModels (FeedViewModel, ExpenseEntryViewModel, InsightsViewModel) use `authService: AuthenticationServiceProtocol = AuthenticationService()` as default parameter. The learnings entry warns against creating instances in Views; the ViewModel default parameter is the established DI convention. If the shared instance pattern changes, all ViewModels need updating.
- **D2: Duplicate `categoryName` values break `chartForegroundStyleScale` domain** — `InsightsSummaryView.swift:51-53`. If two categories share the same `name` (possible with custom categories in Epic 5), chart colors may map incorrectly and slices could visually merge. Enforce unique names at category creation time (Story 5-2).
- **D3: "This day total:" awkward VoiceOver phrasing** — `InsightsViewModel.chartAccessibilityLabel` uses `selectedPeriod.emptyStateLabel` which returns "day" for `.daily`. "Today's total:" would be more natural. Pre-existing label from Story 3-1.
