# Story 1.3: App Shell & Tab Navigation

Status: review

## Story

As a user,
I want a 3-tab navigation structure with the entry screen as default,
so that I can access expense entry, feed, and insights with a single tap.

## Acceptance Criteria

1. **Given** app launch after successful authentication **When** ContentView loads **Then** a 3-tab TabView is displayed with Add (plus icon), Feed (list.bullet icon), and Insights (chart.pie icon)

2. **Given** the TabView **When** the app opens **Then** the Add tab is selected by default (FR4)

3. **Given** the TabView **When** .tabBarMinimizeBehavior(.onScrollDown) is applied **Then** the tab bar auto-minimizes on scrollable content tabs (Feed, Insights) but not on the Add tab

4. **Given** the Feed and Insights tabs **When** rendered **Then** each owns its own NavigationStack (TabView is never wrapped in NavigationStack)

5. **Given** the Add tab **When** rendered **Then** it does NOT have a NavigationStack (single screen, no push navigation)

6. **Given** device orientation **When** the app is running **Then** only portrait orientation is supported (UX-DR19)

7. **Given** the Feed tab with no data **When** displayed **Then** "No entries yet" appears as centered text in .secondaryLabel (UX-DR15)

8. **Given** the Insights tab with no data **When** displayed **Then** "$0.00" headline with empty donut outline and "No entries this period" is shown (UX-DR15)

## Tasks / Subtasks

- [x] Task 1: Modify ContentView to implement TabView (AC: #1, #2, #3, #4, #5)
  - [x] 1.1 Replace the placeholder `Text("CashOut")` in `App/ContentView.swift` with a `TabView(selection: $selectedTab)` using the iOS 26 `Tab` struct API (NOT `.tabItem`)
  - [x] 1.2 Add `@State private var selectedTab = 0` to ContentView for tab selection tracking
  - [x] 1.3 Add 3 tabs: `Tab("Add", systemImage: "plus", value: 0)`, `Tab("Feed", systemImage: "list.bullet", value: 1)`, `Tab("Insights", systemImage: "chart.pie", value: 2)`
  - [x] 1.4 Apply `.tabBarMinimizeBehavior(.onScrollDown)` on the `TabView` itself — NOT on individual tab content
  - [x] 1.5 `EntryView()` placed directly inside the Add tab — NO `NavigationStack` wrapping
  - [x] 1.6 `FeedView()` wrapped in `NavigationStack { }` inside the Feed tab
  - [x] 1.7 `InsightsView()` wrapped in `NavigationStack { }` inside the Insights tab
  - [x] 1.8 ContentView must NOT have a `NavigationStack` wrapping the `TabView` — each tab manages its own navigation

- [x] Task 2: Create EntryView placeholder (AC: #5)
  - [x] 2.1 Create `Views/Entry/EntryView.swift` — a minimal placeholder View
  - [x] 2.2 Show `Text("Entry")` centered (or just a `Color.clear` background). This view will be replaced by the numpad/amount display in Story 1.5. Do NOT add NavigationStack here.
  - [x] 2.3 No ViewModel needed for this placeholder — ViewModels come in Stories 1.5/1.6

- [x] Task 3: Create FeedView with empty state (AC: #7)
  - [x] 3.1 Create `Views/Feed/FeedView.swift`
  - [x] 3.2 Show centered `Text("No entries yet")` styled with `.foregroundStyle(.secondary)` and `.font(.body)` (UX-DR15). Do NOT use `ContentUnavailableView` — it includes an icon/image that violates the "minimal text only, no illustrations" UX rule.
  - [x] 3.3 The empty state is the ONLY content for now — the List/feed implementation comes in Story 2.1
  - [x] 3.4 Do NOT add a NavigationStack inside FeedView — it's already wrapped by ContentView's Tab
  - [x] 3.5 Add `.navigationTitle("Feed")` on the outermost view body — NavigationStack in ContentView picks this up. Ensure `.navigationTitle` stays on the root content when List is added in Story 2.1.
  - [x] 3.6 No ViewModel needed for this placeholder

- [x] Task 4: Create InsightsView with empty state (AC: #8)
  - [x] 4.1 Create `Views/Insights/InsightsView.swift`
  - [x] 4.2 Show empty state: "$0.00" as headline text with `.monospacedDigit()` + `.font(.title)` and "No entries this period" below in `.secondary` color (UX-DR15)
  - [x] 4.3 Do NOT add a NavigationStack inside InsightsView — it's already wrapped by ContentView's Tab
  - [x] 4.4 Add `.navigationTitle("Insights")` on the outermost view body — same pattern as FeedView. Keep at root level for NavigationStack to pick up.
  - [x] 4.5 No ViewModel needed for this placeholder
  - [x] 4.6 NOTE: UX-DR15 specifies "empty donut outline" — defer the actual donut to Story 3.2 (requires Swift Charts). For this story, the text-only empty state is sufficient.

- [x] Task 5: Lock to portrait orientation (AC: #6)
  - [x] 5.1 In Xcode project build settings, add `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait` (since `GENERATE_INFOPLIST_FILE = YES` is set, use build settings not Info.plist directly). Alternatively, add `UISupportedInterfaceOrientations` key to `CashOut/Info.plist` containing only `UIInterfaceOrientationPortrait`.
  - [x] 5.2 Verify that no `UIInterfaceOrientationLandscapeLeft`, `UIInterfaceOrientationLandscapeRight`, or `UIInterfaceOrientationPortraitUpsideDown` values are present
  - [x] 5.3 CONFIRMED: Orientation is NOT yet configured — `project.pbxproj` has no `INFOPLIST_KEY_UISupportedInterfaceOrientations` build setting and Info.plist has no `UISupportedInterfaceOrientations` key. This is REQUIRED work, not optional.
  - [x] 5.4 NOTE: `TARGETED_DEVICE_FAMILY` is currently `"1,2"` (iPhone + iPad). The app is iPhone-only per product brief. Consider changing to `"1"` (iPhone only) to avoid iPad orientation complications — but this can be addressed separately.

- [x] Task 6: Build verification (all ACs)
  - [x] 6.1 Clean build succeeds with zero errors and zero warnings
  - [x] 6.2 All existing tests still pass (no regressions — 17 tests from Stories 1.1 + 1.2)
  - [x] 6.3 App launches in Simulator → shows Sign in with Apple screen → after auth (or with previously cached credentials), shows TabView with Add tab selected
  - [x] 6.4 Tapping Feed tab shows "No entries yet" centered text
  - [x] 6.5 Tapping Insights tab shows "$0.00" and "No entries this period"
  - [x] 6.6 Tapping Add tab shows the EntryView placeholder
  - [x] 6.7 Tab bar is visible at bottom with all 3 icons and labels
  - [x] 6.8 Portrait lock works — rotating the Simulator does not change orientation

## Dev Notes

### Architecture Constraints (MUST follow)

- **Tab API**: Use iOS 26 `Tab` struct, NOT `.tabItem`. The architecture specifies `Tab("Add", systemImage: "plus", value: 0)` syntax. [Source: architecture.md#Navigation Pattern]
- **NavigationStack ownership**: Each tab (Feed, Insights) owns its own `NavigationStack` INSIDE the Tab body. `TabView` is NEVER wrapped in `NavigationStack`. Add tab has NO NavigationStack. [Source: architecture.md#Navigation Pattern, .claude/learnings/ios-swiftui.md]
- **`.tabBarMinimizeBehavior(.onScrollDown)`**: Applied on `TabView` itself, NOT on individual tab content views. Only triggers on tabs with scrollable content (Feed, Insights). Entry tab (numpad, no scroll) won't trigger minimize. [Source: .claude/learnings/ios-swiftui.md#SwiftUI Performance]
- **Tab selection**: `@State private var selectedTab = 0` on ContentView. Simple state — no Coordinator pattern needed for 3 tabs + sheets. [Source: .claude/learnings/architecture.md#Navigation Coordination]
- **No business logic in Views**: Views are thin — display state, forward actions. Even empty states are just declarative SwiftUI. [Source: architecture.md#SwiftUI View Pattern]
- **No ViewModels in this story**: Story 1.3 is navigation skeleton only. ExpenseEntryViewModel, FeedViewModel, InsightsViewModel come in their respective stories (1.5, 2.1, 3.1). Do NOT create ViewModels prematurely.
- **`.task` re-fires on tab appear**: This is a known TabView behavior. Not relevant for this story (no async work in placeholders), but all future ViewModels loaded via `.task` in these tabs MUST guard against redundant re-loads. [Source: .claude/learnings/ios-swiftui.md#SwiftUI State & Observation]

### Exact Code Pattern from Architecture

ContentView should follow this exact structure [Source: architecture.md:649-671]:

```swift
struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Add", systemImage: "plus", value: 0) {
                EntryView()  // No NavigationStack — single screen
            }
            Tab("Feed", systemImage: "list.bullet", value: 1) {
                NavigationStack {
                    FeedView()
                }
            }
            Tab("Insights", systemImage: "chart.pie", value: 2) {
                NavigationStack {
                    InsightsView()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
```

### Interaction with Existing Code

- **CashOutApp.swift** — Shows `ContentView()` when `authViewModel.isAuthenticated == true`. No changes needed to CashOutApp.swift in this story. ContentView is already rendered conditionally.
- **ContentView.swift** (`CashOut/App/ContentView.swift`) — Currently contains only `Text("CashOut")`. Replace the entire body with the TabView structure above.
- **AppDelegate.swift** — No changes needed.
- **AuthenticationViewModel** — No changes needed. Contains guard against `.task` re-firing (`hasCheckedAuth`) which will protect against TabView re-appearing behavior.
- **Views/Auth/SignInView.swift** — No changes needed.
- **Views/Entry/, Views/Feed/, Views/Insights/** — Empty directories exist from Story 1.1 project setup. Place new view files here.

### Empty State UX Requirements

- **Feed empty state**: "No entries yet" — centered, `.secondary` foreground, `.body` font. No illustrations, no CTAs, no "tap + to add" hints. [Source: ux-design-specification.md, UX-DR15]
- **Insights empty state**: "$0.00" headline + "No entries this period" subtitle. No empty donut outline in this story (deferred to Story 3.2 when Swift Charts are implemented). [Source: ux-design-specification.md, UX-DR15]
- **Entry placeholder**: Minimal — will be fully replaced by numpad in Story 1.5. A simple Text or Color.clear is fine.
- **No loading states**: Local-first means data is always available instantly. No spinners, no skeletons, no progress indicators anywhere. [Source: ux-design-specification.md, UX-DR14]

### Portrait Orientation Lock

- Xcode project target → General → Deployment Info → Device Orientation: check only "Portrait"
- In Info.plist: `UISupportedInterfaceOrientations` should contain only `UIInterfaceOrientationPortrait`
- This may already be set from Story 1.1 project creation — verify before modifying

### What This Story Does NOT Include

- No numpad or amount display (Story 1.5)
- No category picker (Story 1.6)
- No expense persistence (Story 1.6)
- No feed list or data (Story 2.1)
- No floating add button / FAB (Story 2.2)
- No insights charts (Story 3.1, 3.2, 3.3)
- No settings screen or gear icon in nav bar (Story 5.1)
- No ViewModels (respective stories)
- No `.tabViewBottomAccessory` for FAB (Story 2.2)
- No `navigationTransition(.zoom())` morphing transitions (Story 2.2)

### Deferred Work Awareness (from Stories 1.1 + 1.2)

- **W1**: `wrappedID` returns new UUID on nil — no impact on this story (no ForEach usage)
- **W6**: `wrappedCreatedAt`/`wrappedModifiedAt` return `Date()` on nil — no impact
- **D1**: Share acceptance falls back to private store — no impact (Story 4.1 concern)
- **D2**: Credential revocation doesn't clear Core Data — no impact (Story 4.x concern)

### File Structure (exact paths)

**New files:**
```
CashOut/Views/Entry/EntryView.swift       # Add tab placeholder
CashOut/Views/Feed/FeedView.swift         # Feed tab with empty state
CashOut/Views/Insights/InsightsView.swift # Insights tab with empty state
```

**Modified files:**
```
CashOut/App/ContentView.swift             # Replace placeholder with TabView
CashOut.xcodeproj/project.pbxproj         # New files added to target
```

**No test files**: This story is purely structural (view layer) with no business logic. No ViewModel unit tests. Verification is build + visual inspection in Simulator. If the project has UI test infrastructure, a basic UI test for tab presence is optional.

### #Preview Blocks

- Add a simple `#Preview` block to each new view (EntryView, FeedView, InsightsView)
- Update ContentView's existing `#Preview` block to reflect the new TabView structure — the current preview injects `.environment(\.managedObjectContext, ...)` which should still be applied since future child views will need it
- Placeholder views have no Core Data dependency, so their previews need no environment injection

### Naming Conventions (from Story 1.1 + 1.2)

- Types: PascalCase — `EntryView`, `FeedView`, `InsightsView`
- Files: PascalCase matching type — `EntryView.swift`
- Properties: camelCase — `selectedTab`
- One SwiftUI View per file — no multi-view files [Source: architecture.md#Structure Patterns]

### Liquid Glass (iOS 26)

- Tab bar gets Liquid Glass appearance automatically when compiled against iOS 26 SDK — no manual `.glassEffect()` needed on the tab bar itself
- NavigationStack title bars also get automatic glass treatment
- Do NOT add `.glassEffect()` to the tab bar or navigation bars [Source: .claude/learnings/ios-swiftui.md#iOS Platform Patterns]

### Previous Story Intelligence (from Story 1.2)

- **Pattern established**: `@Observable` + `@MainActor` ViewModels with `@ObservationIgnored` on injected references
- **Auth gate working**: CashOutApp shows ContentView only when authenticated — TabView will only appear for authenticated users
- **`.task` guard pattern**: AuthenticationViewModel uses `guard !hasCheckedAuth` to prevent re-firing — all future ViewModels in TabView tabs should use similar guards
- **Test pattern**: `@MainActor` on test methods, `@preconcurrency import` where needed
- **Dual sign-in paths**: `performSignIn()` for programmatic, `completeSignIn()` for button — not relevant to this story but awareness for future integration
- **Session invalidation callback**: `onSessionInvalidated` pattern on AuthenticationServiceProtocol for propagating service events to ViewModel — may need similar patterns in future ViewModels

### Project Structure Notes

- Aligns with MVVM folder structure: Views in Views/{Feature}/ subdirectories
- No new folders needed — Views/Entry/, Views/Feed/, Views/Insights/ all exist from Story 1.1
- No ViewModels created — flat ViewModels/ folder remains with only AuthenticationViewModel.swift
- ContentView stays in App/ folder (it's the root composition view, not a feature view)

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Navigation Pattern] — TabView structure, NavigationStack ownership, Tab API
- [Source: _bmad-output/planning-artifacts/architecture.md#Communication Patterns] — ViewModel pattern, @State for ViewModels
- [Source: _bmad-output/planning-artifacts/architecture.md#Structure Patterns] — File organization, one View per file
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.3] — Acceptance criteria, BDD scenarios
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#UX-DR12] — Tab structure: 3 tabs, settings behind gear icon
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#UX-DR13] — iOS 26 Liquid Glass, .tabBarMinimizeBehavior
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#UX-DR14] — No loading states
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#UX-DR15] — Empty states specification
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#UX-DR19] — Portrait-only
- [Source: .claude/learnings/ios-swiftui.md] — TabView behavior, NavigationStack patterns, .task guard
- [Source: .claude/learnings/architecture.md] — Navigation coordination, MVVM patterns
- [Source: _bmad-output/implementation-artifacts/1-2-sign-in-with-apple-authentication.md] — Previous story patterns, auth gate wiring

### Guardian Validation Summary (pre-implementation)

**iOS/SwiftUI Guardian:**
- PASS: Tab API usage (iOS 26 `Tab` struct, not `.tabItem`)
- PASS: NavigationStack ownership (per-tab, TabView never wrapped)
- PASS: `.tabBarMinimizeBehavior(.onScrollDown)` placement on TabView
- PASS: Liquid Glass automatic treatment
- PASS: `.task` re-fire awareness documented
- WARNING (FIXED): Portrait orientation confirmed NOT configured — Task 5 updated with explicit instructions
- WARNING (FIXED): `ContentUnavailableView` could include icon — Task 3.2 updated to use plain `Text` only
- SUGGESTION (NOTED): `TARGETED_DEVICE_FAMILY` includes iPad — noted in Task 5.4 for future consideration

**Architecture Guardian:**
- PASS: No premature ViewModels
- PASS: Navigation coordination with `@State` on ContentView
- PASS: File structure placement in Views/{Feature}/
- PASS: ContentView composition matches architecture pattern exactly
- PASS: One View per file rule
- PASS: No business logic in Views
- WARNING (FIXED): `.navigationTitle` placement guidance — Tasks 3.5, 4.4 updated with root-level note
- SUGGESTION (FIXED): `#Preview` blocks needed — added to Dev Notes

**CloudKit Sync Guardian:**
- PASS: No CloudKit concerns — purely UI/navigation story

**Verdict: READY FOR IMPLEMENTATION** — 0 critical, 3 warnings (all addressed), 2 suggestions (all addressed)

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Build initially failed because new .swift files were not registered in project.pbxproj — added PBXFileReference, PBXBuildFile, PBXGroup entries and PBXSourcesBuildPhase entries for all 3 new views
- iPhone 16 Pro simulator not available — switched to iPhone 17 Pro

### Completion Notes List

- Implemented 3-tab TabView in ContentView using iOS 26 `Tab` struct API with `@State private var selectedTab = 0` defaulting to Add tab
- Created EntryView as minimal `Color.clear` placeholder (will be replaced by numpad in Story 1.5)
- Created FeedView with centered "No entries yet" text in `.secondary` style, plus `.navigationTitle("Feed")`
- Created InsightsView with "$0.00" `.monospacedDigit()` headline and "No entries this period" subtitle, plus `.navigationTitle("Insights")`
- NavigationStack wraps Feed and Insights tabs individually inside ContentView; Add tab has no NavigationStack
- `.tabBarMinimizeBehavior(.onScrollDown)` applied on TabView itself
- Portrait orientation locked via `UISupportedInterfaceOrientations` in Info.plist (portrait only)
- No landscape or upside-down orientation values present
- `#Preview` blocks added to all 3 new views; ContentView preview updated with TabView structure
- No ViewModels created (per story spec — deferred to respective feature stories)
- Build succeeded with zero errors, zero warnings
- All 17 existing tests pass (zero regressions)

### File List

**New files:**
- `CashOut/Views/Entry/EntryView.swift`
- `CashOut/Views/Feed/FeedView.swift`
- `CashOut/Views/Insights/InsightsView.swift`

**Modified files:**
- `CashOut/App/ContentView.swift` — replaced `Text("CashOut")` with TabView structure
- `CashOut/Info.plist` — added `UISupportedInterfaceOrientations` (portrait only)
- `CashOut.xcodeproj/project.pbxproj` — registered 3 new files and groups

### Change Log

- 2026-03-28: Implemented app shell with 3-tab navigation (Add/Feed/Insights), empty state views, and portrait orientation lock. All ACs satisfied, all tasks complete, zero regressions.
