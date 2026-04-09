# iOS, SwiftUI, SwiftData

<!-- One line per learning, brief and actionable -->

## SwiftUI Navigation
- Never wrap TabView inside NavigationStack — each tab must own its own NavigationStack inside itself.
- NavigationPath must be @State on the tab root view, never on a ViewModel.

## SwiftUI Animations
- **2026-04-08**: `PhaseAnimator(phases:trigger:)` fires its full phase sequence on first insertion into the view tree — not only on trigger changes. Wrapping it in `if condition { PhaseAnimator(...) }` and toggling the condition causes a re-insertion auto-cycle every time, producing double overlapping animations on 2nd+ triggers. Keep PhaseAnimator permanently in the tree; use the `.hidden` phase (opacity 0) for invisibility.
- **2026-04-09**: PhaseAnimator first-insertion auto-cycle makes the `.visible` phase briefly appear even before any user interaction. Guard visible-phase opacity on the trigger value: `opacity(phase == .visible && trigger > 0 ? 1 : 0)`. With `@State trigger = 0`, the auto-cycle at insertion stays fully invisible because `trigger == 0` forces opacity 0 in all phases.
- **2026-04-08**: `.contentTransition(.symbolEffect(.replace.downUp))` does NOT animate automatically on `@State`/`@Observable` property changes — it requires `withAnimation { }` wrapping the mutation at the call site. Without it, the symbol swaps instantly with no transition.

## SwiftUI State & Observation
- **2026-04-04**: `@State` on an `@Observable` class does NOT expose `$viewModel` for property bindings. Use `Bindable(viewModel).property` inline or declare `@Bindable private var viewModel` to get `Binding<T>` for modifiers like `.navigationDestination(item:)`.
- **2026-04-06**: `.navigationDestination(item:)` destination closure must produce content unconditionally — `if let` inside produces `EmptyView` (blank screen). Pack all required data into the item type (e.g., `struct CategoryNavDestination: Hashable { let categoryID: UUID; let interval: DateInterval }`), gate in the ViewModel's setter, so the closure always has everything it needs.
- .task re-fires on every tab appear in TabView — guard with loaded-state check (e.g., `guard items.isEmpty else { return }`).
- **2026-04-07**: `@State private var viewModel = FeedViewModel()` evaluates the init expression on EVERY View struct creation (even when @State returns the stored value). Default parameter values like `AuthenticationService()` run their constructors every time. If any default creates side effects (Tasks, notification observers, mutating shared @Observable properties), they leak or trigger infinite re-render loops. Fix: (1) use `.shared` singletons as default params, (2) mark callback-registration arrays as `@ObservationIgnored`, (3) move callback registration to lifecycle methods (`.onAppear`/`.task`) not init.
- Subscribe to NotificationCenter via async sequence in .task {} — auto-cancels on view disappear. Never use addObserver in ViewModels.
- **2026-04-08**: `NavigationLink(destination: SomeView())` eagerly evaluates the destination closure on every parent body evaluation, even inside `NavigationStack`. Replace with `Button { showFlag = true }` + `.navigationDestination(isPresented: $showFlag) { SomeView() }` to defer creation until navigation occurs — eliminates phantom ViewModel allocations from toolbar gear icons.

## SwiftUI Performance
- **2026-04-03**: Empty state in a ScrollView-hosted tab must stay inside the ScrollView (not replace it) — removing ScrollView from the hierarchy breaks `.tabBarMinimizeBehavior(.onScrollDown)`. Use `.containerRelativeFrame(.vertical) { height, _ in height }` on the empty-state container to center it vertically within the scroll area.
- Use List (not ScrollView+VStack) for Feed — provides swipe actions and built-in row recycling. Switch to LazyVStack only if custom row layouts require leaving List.
- **2026-04-03**: Inside `List`, use `Button` + `.buttonStyle(.plain)` for tappable rows with `.swipeActions` — `.contentShape(Rectangle()).onTapGesture` conflicts with swipe gesture recognition (tap intercepts swipe initiation). `Button` integrates cleanly with List's gesture system.
- **2026-04-03**: `.sheet(item:)` must be placed on the outer container (`Group`), not on `List` — when an empty-state branch replaces the List, the sheet modifier disappears from the view hierarchy and can never trigger.
- **2026-04-09**: `.confirmationDialog` has no `item:` overload like `.sheet(item:)`. For optional-driven dialogs, use `Binding(get: { item != nil }, set: { if !$0 { item = nil } })` with the `presenting:` parameter — `presenting:` passes the unwrapped item into the actions closure, avoiding `if let` unwrapping inside button actions.
- .tabBarMinimizeBehavior(.onScrollDown) must be applied on TabView itself, not on tab content. Only triggers on tabs with scrollable content.
- **2026-04-03**: `.tabViewBottomAccessory` with conditional content (`if condition { View }`) may leave empty accessory space when the condition is false — iOS may still reserve height for the slot. If visible dead space appears, use `.opacity(0)` + `.allowsHitTesting(false)` instead of conditional removal to guarantee zero visual footprint.
- **2026-04-06**: However, `.opacity(0)` in `.tabViewBottomAccessory` still reserves the full accessory height as a bottom safe area inset on ALL tabs — this can squeeze content-heavy tabs (e.g., numpad layouts) and cause GeometryReader-based views to overflow. Prefer conditional removal (`if condition { View }`) when the accessory view is large (>44pt) and specific tabs need maximum vertical space. Test for dead space after switching.
- **2026-04-07**: Even conditional removal inside `.tabViewBottomAccessory` still reserves the accessory container's height on iOS 26 — the container slot exists regardless of content. Replace `.tabViewBottomAccessory` with `.overlay(alignment: .bottom)` when accessory should have zero footprint on specific tabs.
- **2026-04-04**: `EmptyView()` inside a `ToolbarItem` can still reserve phantom leading/trailing inset (8-16pt) — UIKit's underlying `UIBarButtonItem` occupies a slot even with zero-size content. Conditionally emit the entire `ToolbarItem` based on state (e.g., `if status == .failure { ToolbarItem { ... } }`) rather than returning `EmptyView()` from the content.
- **2026-03-29**: Never have `LazyVGrid` as the direct child of `GeometryReader` — causes circular layout negotiation. Interpose `VStack(spacing: 0) { LazyVGrid(...) }` inside the GeometryReader closure to break the cycle. Also add `.frame(height:)` in `#Preview` for GeometryReader-based views so previews reflect realistic layout.
- **2026-04-06**: `.buttonStyle(.glass)` adds internal chrome (padding/background) OUTSIDE `.frame(height:)` applied to the label — manual GeometryReader height math can't account for it. For button grids, replace GeometryReader + LazyVGrid with `VStack { ForEach(rows) { HStack { ForEach(row) { Button.frame(maxWidth: .infinity, maxHeight: .infinity) } } } }` — the layout system distributes space including all style decorations with no manual math.
- **2026-04-07**: `maxHeight: .infinity` on buttons in a VStack with Spacers creates layout competition — buttons greedily expand, consuming space intended for Spacers and pushing siblings offscreen. Use `minHeight: <fixed>` for elements with known size in flexible layouts; reserve `maxHeight: .infinity` only when the element should truly fill all remaining space.

## Sign in with Apple
- Email/name data only available on FIRST sign-in — cache to CloudKit UserProfile record immediately.
- Store userIdentifier in Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.
- Register for ASAuthorizationAppleIDProvider.credentialRevokedNotification for mid-session revocation detection.
- Handle .revoked (clear Keychain + cleanup) separately from .notFound (just show sign-in, no cleanup).

## Swift Charts
- **2026-04-04**: `chartAngleSelection(value:)` binding type must exactly match the `PlottableValue` type passed to `SectorMark(angle: .value(..., value))`. If `value` is `Int64`, the binding must be `Binding<Int64?>`. Type mismatch silently prevents selection from firing.
- **2026-04-04**: `.chartAngleSelection` alone uses hold-not-tap gesture (Apple bug). Must pair with `.chartGesture { chart in SpatialTapGesture().onEnded { ... chart.selectAngleValue(at: angle) } }` to enable single-tap selection on donut/pie charts.
- **2026-04-04**: `chartAngleSelection` raw value can exceed the integer sum of all `SectorMark` values due to floating-point rounding in chart geometry. Always fall back to the last slice in `resolveCategory` instead of returning nil — prevents silent tap failures on the last slice's trailing edge.
- **2026-04-04**: `BarMark` with String x-values sorts labels alphabetically by default. Use `.chartXScale(domain: entries.map(\.label))` to enforce array-order (chronological). If ordering still breaks, fall back to index-based x-values with custom `AxisValueLabel`.

## SwiftData Migrations
- N/A — CashOut uses Core Data, not SwiftData (shared CloudKit database not supported in SwiftData).

## SwiftData Relationships
- N/A — CashOut uses Core Data.

## SwiftData Threading
- N/A — CashOut uses Core Data.

## Core Data Testing
- **2026-03-28**: `PersistenceController(inMemory: true)` already disables CloudKit (sets `cloudKitContainerOptions = nil` and URL to `/dev/null`) — no need for a separate plain `NSPersistentContainer` test helper. Reuse the existing controller.
- **2026-03-28**: Asset catalog colorset group folders (e.g., `CategoryColors/`) are NOT part of the `Color(_ name:)` lookup — Xcode resolves by colorset name only. `Color("Sage")` works regardless of folder nesting depth.
- **2026-04-04**: `Color("name")` silently renders as clear/invisible when the name doesn't match an asset catalog entry — no crash, no warning. Always use the `CategoryColor(from:)?.color ?? .gray` enum-based lookup with an explicit fallback instead of raw `Color(colorName)` for data-driven color names.

## Accessibility
- **2026-04-08**: Fixed `font(.system(size: N))` blocks Dynamic Type scaling — use `@ScaledMetric(relativeTo: .largeTitle) private var fontSize: CGFloat = N` to let custom sizes scale with the user's preferred text size. The existing `.minimumScaleFactor(0.5)` handles overflow at larger sizes.
- **2026-04-08**: Decorative large-radius `blur()` circles must be gated on `@Environment(\.accessibilityReduceTransparency)` — omit or replace with solid fill when true. Users who enable Reduce Transparency expect no translucent/blur effects. Scope `.drawingGroup()` to ONLY the blur circles ZStack — never on a parent container.
- **2026-04-08**: `.drawingGroup()` MUST be scoped to leaf decoration layers (blur circles, gradients) — NEVER on a container holding `ScrollView` or `.ultraThinMaterial`. It rasterizes the entire subtree into an offscreen Metal texture: ScrollView content outside initial visible bounds vanishes, and Material effects render invisible because the compositor can't sample pixels behind the flattened texture. This caused categories to disappear from EntryView when `.drawingGroup()` was placed after `.background{}` on the outer VStack.
- **2026-04-05**: `HStack` rows with icon + text + spacer + badge create 4 separate VoiceOver focus stops — noisy and confusing. Add `.accessibilityElement(children: .combine)` to collapse into one element. Prefer `.imageScale(.medium)` over fixed `.frame(width:height:)` on SF Symbols so icons scale with Dynamic Type.
- **2026-04-06**: SF Symbol names (e.g., `"cup.and.saucer.fill"`) are incomprehensible as VoiceOver labels — always map to human-readable strings via a `[String: String]` dictionary. Use `.accessibilityAddTraits(.isSelected)` on picker items so VoiceOver announces selection state.

- **2026-04-06**: NavigationLink wrapping tappable rows for edit navigation should include `.accessibilityHint("Double tap to edit")` — VoiceOver announces the chevron as "button" but does not describe the action. The hint distinguishes editable rows from read-only ones for screen reader users.

## os.log in SwiftUI Views
- **2026-04-08**: `logger.info(...)` returns `Void` — placing it directly inside `@ViewBuilder` closures (`.sheet`, `.navigationDestination`, `.overlay` content) causes "type '()' cannot conform to 'View'". Move logger calls to `.onAppear { }`, button action closures, or `.task { }` instead.
- **2026-04-08**: Always use explicit `privacy:` annotations on `os.log` string interpolations for user data — `\(amount, privacy: .private)` for financial figures, `\(uuid, privacy: .private)` for record identifiers. Swift `Logger` default privacy is type-dependent (`Int` = `.public`, `String` = `.private`) and varies across iOS versions. Explicit annotations prevent log regression.
- **2026-04-08**: Use `\(error.localizedDescription, privacy: .public)` in `.error`/`.fault` log levels — without annotation, error descriptions are redacted as `<private>` in Console.app on-device, making error logs useless for remote debugging.

## iOS Platform Patterns
- **2026-04-06**: Dark-only apps using hardcoded hex color tokens must add `.preferredColorScheme(.dark)` at the app root — without it, system adaptive colors (`Color.secondary`, `.primary`) resolve to light-mode values when the device OS is in light mode, breaking the custom dark palette.
- **2026-04-06**: `SignInWithAppleButton` style must be hardcoded `.white` on dark-surface apps — `colorScheme == .dark ? .white : .black` renders black-on-dark when device is in light mode system-wide, making the button invisible.
- **2026-04-06**: SwiftUI glassmorphism: `.background(tintColor)` must come BEFORE `.background(.ultraThinMaterial)` — material must be the outer (last) background so it blends with content behind it. Reversed order occludes the blur, producing a flat colored rectangle.
- **2026-04-08**: `Material` (`.ultraThinMaterial`) and `Color` are different types — cannot mix in a ternary for `.background()`. Use `@ViewBuilder` closure with `if/else` and `RoundedRectangle.fill()` for each branch: `if isSelected { RoundedRectangle(...).fill(color) } else { RoundedRectangle(...).fill(.ultraThinMaterial) }`.
- For Liquid Glass buttons: use .buttonStyle(.glass) or .buttonStyle(.glassProminent) — never combine with .glassEffect() modifier on the same element.
- .glassEffect() is for non-button views. Button styles auto-apply glass.
- Use view-associated UIImpactFeedbackGenerator(style:view:) for iOS 26+ (correct Taptic Engine routing), not legacy initializer.
- **2026-03-29**: Custom-styled buttons (manual background/border) must use `.buttonStyle(.plain)` explicitly — `.buttonBorderShape(.capsule)` only works with `.bordered`/`.borderedProminent` styles and has no effect on plain `Button`. Without explicit `.buttonStyle(.plain)`, iOS 26 Liquid Glass may override custom visuals.
- **2026-03-29**: Icon-only buttons (e.g., note pencil icon) need `.frame(width: 44, height: 44)` on the label — SF Symbol intrinsic size is ~22pt, below the 44pt accessibility minimum tap target.
- **2026-03-29**: Use `.task(id: selectedID)` not `.onAppear` for `ScrollViewReader.scrollTo()` — synchronous `.onAppear` fires before SwiftUI completes layout, so `scrollTo` silently does nothing. `.task(id:)` defers to next run loop tick AND re-fires on selection change.
- **2026-04-07**: SwiftUI-only apps still need `UILaunchScreen` (empty `<dict/>`) in Info.plist — without it, iOS renders the app in compatibility mode with black letterboxing on devices with Dynamic Island/notch. No launch storyboard needed, just the key.

## Testing Async Notification Handlers
- **2026-03-28**: `Task { }` on `@MainActor` doesn't start until the caller yields. `NotificationCenter.notifications(named:)` only receives notifications posted AFTER `for await` begins iteration. In tests: `await Task.yield()` before posting notifications so observer Tasks register their async sequence listeners first. Without this, tests pass as false positives (asserting on already-default-nil state).

## Swift 6 Strict Concurrency
- `static var` with closure init is not concurrency-safe — use `static let` for singletons/previews.
- CoreData's `NSMergeByPropertyStoreTrumpMergePolicy` triggers "shared mutable state" error in Swift 6 — use `@preconcurrency import CoreData`.
- XCUITest methods (`launch()`, `.staticTexts[]`, `.exists`) are MainActor-isolated in Swift 6 — annotate test methods with `@MainActor`.
- `NSPersistentCloudKitContainerOptionsKey` is NOT a public API — don't try to read CloudKit options from persistent store's options dict. Identify stores by URL instead.
- Core Data `codeGenerationType` absent from `.xcdatamodel` XML defaults to Manual/None when using xcodegen — do NOT add `codeGenerationType="category"` as it causes duplicate symbol errors with manually written +CoreDataProperties files.
- `@preconcurrency import CoreData` should be used on ALL files that reference Core Data types, not just PersistenceController — keeps Swift 6 strict concurrency consistent across model files.
- **2026-04-02**: Adding `@MainActor` to a class that conforms to a nonisolated protocol causes "conformance crosses into main actor-isolated code" error — if the protocol is nonisolated, all conforming types (including mocks) must also be nonisolated.
- **2026-04-02**: `@MainActor` class conforming to `NSFetchedResultsControllerDelegate` requires `@preconcurrency` on the conformance (`@preconcurrency NSFetchedResultsControllerDelegate`) — the delegate protocol's methods are `nonisolated` but `@MainActor` class methods are actor-isolated, causing "conformance crosses into main actor-isolated code" without `@preconcurrency`.
- **2026-04-02**: `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator` initializers are main actor-isolated in iOS 26 SDK — calling them from nonisolated code generates warnings. Previously considered thread-safe. Plan for `@MainActor` annotation on haptic services when all callers are guaranteed main-actor.
- **2026-04-06**: To make a service protocol `@MainActor`, add the annotation to both the protocol AND all conforming types (including test mocks). Cache `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator` as stored properties and call `prepare()` after each use to pre-warm the Taptic Engine for the next event — eliminates ~50ms first-hit latency from per-call instantiation.
