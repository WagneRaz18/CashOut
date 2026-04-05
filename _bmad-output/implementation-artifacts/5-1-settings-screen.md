# Story 5.1: Settings Screen

Status: done

## Story

As a user,
I want to access app settings from the feed or insights screen,
So that I can manage categories and household configuration in one place.

## Acceptance Criteria

1. **Given** the Feed navigation bar **When** the gear icon (gearshape) is tapped **Then** the Settings screen opens via NavigationStack push

2. **Given** the Insights navigation bar **When** the gear icon is tapped **Then** the same Settings screen opens

3. **Given** the Settings screen **When** displayed **Then** it uses a standard Form/List with grouped sections: Categories, Household, About

4. **Given** the Household section **When** no partner is connected **Then** it shows the "Invite Partner" button (triggers UICloudSharingController from Epic 4)

5. **Given** the Household section **When** a partner is connected **Then** it shows partner info (name/initials) and sharing status

6. **Given** the About section **When** displayed **Then** it shows app version and a privacy note ("Your data stays on your devices and iCloud. No analytics, no third-party access.")

7. **Given** the Settings screen **When** any setting is changed **Then** the core entry flow on the Add tab is never affected — no settings gate or modify the entry experience

## Tasks / Subtasks

- [x] Task 1: Enhance Categories section with real category data (AC: #3)
  - [x] 1.1 **Add `CategoryRepositoryProtocol` dependency** to `SettingsViewModel`. Inject via init with default `CategoryRepository()`. Declare as `@ObservationIgnored private let` — matching the existing `FeedViewModel` pattern. (`@ObservationIgnored` is technically redundant on `let` but keeps codebase consistency.) [Source: `.claude/learnings/architecture.md` — MVVM with @Observable, line 6,14]
  - [x] 1.2 **Add categories state** to `SettingsViewModel`:
    ```swift
    var categories: [CategoryData] = []
    ```
  - [x] 1.3 **Add `loadCategories()` method** to `SettingsViewModel`:
    ```swift
    func loadCategories() async {
        do {
            let result = try await categoryRepository.fetchCategories()
            guard !Task.isCancelled else { return }
            categories = result
        } catch {
            guard !Task.isCancelled else { return }
            // Categories are seeded at startup — empty state is infrastructure failure
            // Log but don't show error to user (categories still work on entry screen)
            categories = []
        }
    }
    ```
    No `errorMessage` set on failure — category list in Settings is informational. The entry screen has its own category loading. [Source: architecture.md — Error Handling table: Core Data save failure → Assert DEBUG, log release, None visible]
  - [x] 1.4 **Replace placeholder text** in `SettingsView.swift` Categories section. Currently line 10: `Text("6 default categories active")`. Replace with a `ForEach` over `viewModel.categories`:
    ```swift
    Section("Categories") {
        ForEach(viewModel.categories, id: \.id) { category in
            CategoryRowView(category: category)
        }
    }
    ```
    **Read-only for Story 5.1** — no NavigationLink, no tap action. Story 5.2 adds add/edit functionality.
  - [x] 1.5 **Create `CategoryRowView`** in `CashOut/Views/Settings/CategoryRowView.swift`:
    ```swift
    struct CategoryRowView: View {
        let category: CategoryData

        var body: some View {
            HStack(spacing: Spacing.sm) {
                Image(systemName: category.iconName)
                    .foregroundStyle(CategoryColor(from: category.colorName)?.color ?? .gray)
                    .frame(width: 24, height: 24)
                Text(category.name)
                Spacer()
                if category.isDefault {
                    Text("Default")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    ```
    **CRITICAL:** Use `CategoryColor(from:)?.color ?? .gray` enum-based lookup — never raw `Color(colorName)` which silently renders as clear/invisible. [Source: `.claude/learnings/ios-swiftui.md` line 48]
  - [x] 1.6 **Call `loadCategories()` in `.task`** on `SettingsView`. The existing `.task` calls `viewModel.refreshSharingStatus()`. Add category loading:
    ```swift
    .task {
        await viewModel.refreshSharingStatus()
        await viewModel.loadCategories()
    }
    ```
    Both calls are independent — could be parallelized with `async let` but sequential is fine for this volume. `.task` re-fires on every appear (NavigationStack push/pop) — categories list is small, re-fetch is cheap, and ensures custom categories added on partner's device appear immediately via `NSPersistentCloudKitContainer` auto-merge. No loaded-state guard needed — add a code comment explaining this deliberate re-fetch strategy so future devs don't "fix" it.

- [x] Task 2: Verify existing Household section implementation (AC: #4, #5)
  - [x] 2.1 **ALREADY IMPLEMENTED.** `HouseholdSectionView` at `SettingsView.swift:52-78` handles both states: invite button when `!hasPartner`, partner avatar + name + "Connected" when `hasPartner`. `SettingsViewModel.invitePartner()` fetches categories from private store and calls `cloudSharingService.createShare(for:)`. Tests exist at `SettingsViewModelTests.swift`.
  - [x] 2.2 **Verified.** Partner avatar uses warm stone color (`#A89B8A`). Hardcoded at `SettingsView.swift:95` as `Color(red: 0.659, green: 0.608, blue: 0.541)`. Confirmed match. No changes needed.
  - [x] 2.3 **Verified.** `CloudSharingSheet` at `Views/Settings/CloudSharingSheet.swift` correctly wraps `UICloudSharingController` with delegate callbacks for save (line 34), fail (line 26), and stop-sharing (line 38). No changes needed.

- [x] Task 3: Verify existing About section implementation (AC: #6)
  - [x] 3.1 **Verified.** About section at `SettingsView.swift:19-24` shows `Bundle.main.appVersion` via `LabeledContent` and privacy note as `.footnote` secondary text. No changes needed.
  - [x] 3.2 **Verified.** `Bundle+Version.swift` at `Utilities/Extensions/Bundle+Version.swift` returns `CFBundleShortVersionString` with "1.0" fallback. No changes needed.

- [x] Task 4: Verify navigation from Feed and Insights (AC: #1, #2)
  - [x] 4.1 **Verified.** `FeedView.swift:67-71` has `ToolbarItem(placement: .topBarTrailing)` with `NavigationLink(destination: SettingsView())` using `gearshape` icon. `InsightsView.swift:90-93` has identical pattern. No changes needed.
  - [x] 4.2 **Verified.** Feed has own `NavigationStack` at `ContentView.swift:14`, Insights at line 19. Both push onto separate stacks. No changes needed.

- [x] Task 5: Add unit tests for category loading (AC: #3)
  - [x] 5.1 **Updated `makeSUT`** to return 3-element tuple with `MockCategoryRepository`. Updated all existing callers to destructure 3 elements. Init default value on `categoryRepository:` ensures backward compat.
  - [x] 5.2 **Test: loadCategories populates categories array.** `testLoadCategoriesPopulatesCategoriesArray` — 6 defaults → count == 6. PASSED.
  - [x] 5.3 **Test: loadCategories on error sets empty array.** `testLoadCategoriesOnErrorSetsEmptyArrayWithNoErrorMessage` — mock throws → isEmpty && errorMessage == nil. PASSED.
  - [x] 5.4 **Test: loadCategories includes custom categories.** `testLoadCategoriesIncludesCustomCategories` — 6 defaults + 2 custom → count == 8, 2 non-default. PASSED.

- [x] Task 6: Accessibility verification (AC: #3, #7)
  - [x] 6.1 **Verified.** All text uses SwiftUI text styles (`.body`, `.caption`, `.footnote`, `.caption.weight(.semibold)`) — all scale with Dynamic Type. No fixed font sizes found.
  - [x] 6.2 **Verified.** `CategoryRowView` uses `Image(systemName:)` (SF Symbols auto-labeled by VoiceOver) and standard `Text`. Row reads naturally as icon + name.
  - [x] 6.3 **Verified.** `Form` with `Section("Categories")`, `Section("Household")`, `Section("About")` provides automatic VoiceOver section navigation with headers announced as headings.

## Dev Notes

### What's Already Built (from Epic 4)

The Settings screen was scaffolded during Epic 4 (Household Sharing) to house the "Invite Partner" flow. Most of Story 5.1's ACs are already satisfied:

| Component | File | Status |
|-----------|------|--------|
| SettingsView | `Views/Settings/SettingsView.swift` (98 lines) | Exists — Categories section is placeholder |
| SettingsViewModel | `ViewModels/SettingsViewModel.swift` (70 lines) | Exists — needs CategoryRepository |
| CloudSharingSheet | `Views/Settings/CloudSharingSheet.swift` (45 lines) | Complete |
| Feed gear icon | `Views/Feed/FeedView.swift:67-71` | Complete |
| Insights gear icon | `Views/Insights/InsightsView.swift:90-93` | Complete |
| ViewModel tests | `CashOutTests/ViewModels/SettingsViewModelTests.swift` | Exists — needs category tests |

**Primary work:** Replace the Categories section placeholder with a real category list and add the `CategoryRepositoryProtocol` dependency to `SettingsViewModel`.

### Architecture Compliance

- **MVVM boundary:** SettingsViewModel fetches `[CategoryData]` DTOs from `CategoryRepositoryProtocol` — no Core Data types in the View layer. Exception: `invitePartner()` accesses `viewContext` directly for `container.share(objects:)` — accepted MVVM exception documented in `.claude/learnings/architecture.md:11`.
- **@Observable pattern:** SettingsViewModel is `@MainActor @Observable final class`. New `categoryRepository` reference must be `@ObservationIgnored var` (not `let`) since it's a protocol type.
- **DI pattern:** Init injection with defaults: `categoryRepository: CategoryRepositoryProtocol = CategoryRepository()`. Repositories are transient (not singletons). [Source: `.claude/learnings/architecture.md:46`]
- **One View per file:** `CategoryRowView` goes in its own file at `Views/Settings/CategoryRowView.swift`. [Source: architecture.md — "One SwiftUI View per file"]
- **Singleton usage:** No new singletons needed. SettingsViewModel already uses `CloudSharingService.shared` and `PersistenceController.shared`.

### Key Patterns to Follow

- **Color lookup:** Always use `CategoryColor(from: colorName)?.color ?? .gray` — never `Color(colorName)`. Raw Color init silently renders clear. [Source: `.claude/learnings/ios-swiftui.md:48`]
- **Spacing tokens:** Use `Spacing.sm` (8pt), `Spacing.md` (16pt) from `Constants.swift:4-10`. [Source: architecture.md — Spacing Tokens]
- **@ObservationIgnored:** Required on `var` protocol references in `@Observable` classes. Not needed on `let` constants. [Source: `.claude/learnings/architecture.md:6,14`]
- **Task cancellation:** Check `Task.isCancelled` before state mutations after async calls. [Source: `.claude/learnings/architecture.md:24-25`]
- **Test pattern:** `@MainActor` at class level. `makeSUT()` factory. Mock injection via protocol. [Source: `.claude/learnings/architecture.md:23`]
- **No `.toolbarBackground(.visible)`** — obsolete in iOS 26, breaks Liquid Glass. Toolbar is glass and adaptive by default.

### iOS 26 / Liquid Glass Notes

- `Form` with grouped sections gets Liquid Glass styling automatically — no `.glassEffect()` on content.
- Navigation bar chrome (toolbar) gets glass treatment automatically via NavigationStack.
- Do NOT apply `.glassEffect()` to Form rows, section headers, or list content — glass belongs to navigation layer, not content.
- `.toolbarBackground(.visible, for: .navigationBar)` is obsolete in iOS 26 — remove if encountered.

### Project Structure Notes

New files to create:
- `CashOut/Views/Settings/CategoryRowView.swift` — category list row component

Files to modify:
- `CashOut/ViewModels/SettingsViewModel.swift` — add CategoryRepositoryProtocol dependency, categories state, loadCategories()
- `CashOut/Views/Settings/SettingsView.swift` — replace Categories placeholder with ForEach
- `CashOutTests/ViewModels/SettingsViewModelTests.swift` — add category loading tests

No modifications to:
- `Views/Feed/FeedView.swift` — gear icon already wired
- `Views/Insights/InsightsView.swift` — gear icon already wired
- `Services/CloudSharingService.swift` — already complete
- `App/ContentView.swift` — TabView structure unchanged

### Orchestrator Guardian Findings (2026-04-05)

**0 CRITICAL, 5 WARNING, 8 SUGGESTION** — Ready for dev.

Incorporated warnings:
- W1: Use `private let` (not `var`) for `categoryRepository` — matches `FeedViewModel` pattern
- W5: Add `guard !Task.isCancelled` in both success and catch paths of `loadCategories()`

Implementation guidance (from WARNINGs):
- W2: Add code comment in `.task` block explaining deliberate re-fetch strategy for categories
- W3: `CategoryRowView` icon uses fixed 24x24 frame — consider `@ScaledMetric` for accessibility text sizes, or `.imageScale(.large)` if Dynamic Type scaling is desired for icons
- W6: Existing test `makeSUT` works without changes because `categoryRepository:` has a default value in init

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` — Story 5.1 acceptance criteria, lines 833-870]
- [Source: `_bmad-output/planning-artifacts/architecture.md` — MVVM patterns, lines 147-178]
- [Source: `_bmad-output/planning-artifacts/architecture.md` — Category Entity, lines 218-228]
- [Source: `_bmad-output/planning-artifacts/architecture.md` — Project structure, lines 370-389]
- [Source: `_bmad-output/planning-artifacts/architecture.md` — CategoryColor tokens, lines 446-456]
- [Source: `_bmad-output/planning-artifacts/ux-design-specification.md` — Settings Pattern, lines 900-912]
- [Source: `_bmad-output/planning-artifacts/ux-design-specification.md` — Accessibility, lines 936-948]
- [Source: `.claude/learnings/architecture.md` — @ObservationIgnored rule, line 6]
- [Source: `.claude/learnings/ios-swiftui.md` — CategoryColor lookup, line 48]

## Dev Agent Record

### Agent Model Used
Claude Opus 4.6 (1M context)

### Debug Log References
None — clean implementation, no debugging required.

### Completion Notes List
- ✅ Task 1: Replaced Categories placeholder with real category data from CategoryRepositoryProtocol. Created CategoryRowView, added loadCategories() to SettingsViewModel, wired .task in SettingsView.
- ✅ Task 2: Verified Household section — invite button, partner avatar (#A89B8A), CloudSharingSheet delegates all correct.
- ✅ Task 3: Verified About section — version from Bundle.main.appVersion, privacy note as footnote.
- ✅ Task 4: Verified navigation — gear icons in FeedView and InsightsView push to SettingsView via separate NavigationStacks.
- ✅ Task 5: Added 3 category loading tests (populate, error handling, custom categories). Updated makeSUT to 3-element tuple. All 14 SettingsViewModelTests pass.
- ✅ Task 6: Verified accessibility — Dynamic Type text styles, VoiceOver-accessible CategoryRowView with .accessibilityElement(children: .combine), grouped Form sections.
- 🔧 Orchestrator fixes: Added os_log in loadCategories catch, replaced fixed icon frame with .imageScale(.medium), added .accessibilityElement(children: .combine) to CategoryRowView.

### Orchestrator Guardian Report (2026-04-05)
**0 CRITICAL, 6 WARNING, 3 SUGGESTION**
- W1 (ios): CategoryRowView VoiceOver — FIXED: added .accessibilityElement(children: .combine)
- W2 (arch): No os_log in loadCategories catch — FIXED: added os_log(.error)
- W3 (ios): Fixed 24x24 icon frame — FIXED: replaced with .imageScale(.medium)
- W4 (arch): Sequential .task calls — ACCEPTED: story spec acknowledges acceptable for this volume
- W5 (arch): @ObservationIgnored on let — ACCEPTED: follows codebase-wide FeedViewModel pattern for consistency
- W6 (ios): Partner avatar hard-coded RGB — NOT IN SCOPE: pre-existing from Epic 4

### File List
- `CashOut/ViewModels/SettingsViewModel.swift` — MODIFIED (added categoryRepository dependency, categories state, loadCategories() with os_log)
- `CashOut/Views/Settings/SettingsView.swift` — MODIFIED (replaced Categories placeholder with ForEach, added loadCategories() to .task)
- `CashOut/Views/Settings/CategoryRowView.swift` — NEW (category list row with icon, name, Default badge, VoiceOver combined)
- `CashOutTests/ViewModels/SettingsViewModelTests.swift` — MODIFIED (updated makeSUT, added 3 category loading tests)
- `CashOut.xcodeproj/project.pbxproj` — MODIFIED (added CategoryRowView.swift to project)

### Review Findings

- [x] [Review][Patch] `@ObservationIgnored` missing on `persistenceController` — FIXED [`SettingsViewModel.swift:21`]
- [x] [Review][Patch] Test hard-codes category count as literal `6` — FIXED, uses `defaultCategories.count` [`SettingsViewModelTests.swift:172`]
- [x] [Review][Patch] Happy-path test does not assert `mockCategories.fetchCategoriesCalled` — FIXED [`SettingsViewModelTests.swift:171`]
- [x] [Review][Defer] Invalid SF Symbol `iconName` renders zero-size invisible icon with no fallback [`CategoryRowView.swift:8`] — deferred, validation concern for custom categories (Story 5-2)
- [x] [Review][Defer] `ForEach(id: \.id)` with nil Core Data id generates new UUID each fetch — unstable identity [`SettingsView.swift:10`] — deferred, pre-existing (tracked as W1 in Story 1-1)
- [x] [Review][Defer] `makeSUTWithPersistence()` does not inject `MockCategoryRepository` — latent test isolation gap [`SettingsViewModelTests.swift:29-42`] — deferred, pre-existing helper
- [x] [Review][Defer] `CategoryData` lacks `Identifiable` conformance — requires `id: \.id` in every ForEach — deferred, already tracked (W3 in Story 2-1)

## Change Log
- 2026-04-05: Code review complete — 0 CRITICAL, 3 PATCH, 4 DEFER, 8 DISMISSED. All 7 ACs pass.
- 2026-04-05: Story implemented — replaced Categories placeholder with real category data from CategoryRepositoryProtocol, created CategoryRowView, added 3 unit tests. Verified all existing sections (Household, About, Navigation). Addressed 3 orchestrator warnings (VoiceOver, os_log, icon scaling). 189/189 tests pass.
