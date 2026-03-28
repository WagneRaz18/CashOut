# Story 1.2: Sign in with Apple Authentication

Status: done

Readiness Review: 2026-03-28 — PASSED (0 critical, 0 major, 3 minor monitoring items)
Readiness Report: `_bmad-output/planning-artifacts/implementation-readiness-report-2026-03-28.md`

## Story

As a user,
I want to sign in with my Apple ID on first launch,
so that my identity is established for CloudKit sync and partner attribution.

## Acceptance Criteria

1. **Given** first app launch with no credentials in Keychain **When** the app starts **Then** a Sign in with Apple UI is presented as a blocking gate (cannot proceed without auth)

2. **Given** Sign in with Apple **When** the user authenticates successfully **Then** userIdentifier is cached in Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

3. **Given** a successful first sign-in **When** email and name are provided by Apple **Then** they are cached in Keychain (separate item from userIdentifier, using kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) for future CloudKit UserProfile creation (Story 4.x)

4. **Given** subsequent app launches with cached credentials **When** getCredentialState(forUserID:) returns .authorized **Then** the user proceeds directly to the entry screen with zero delay (NFR1)

5. **Given** credential state check **When** getCredentialState returns .revoked **Then** Keychain is cleared, local user profile data is cleared, and a modal Sign in with Apple screen is presented

6. **Given** credential state check **When** getCredentialState returns .notFound or .transferred **Then** Sign in with Apple screen is presented (no Keychain clearance — fresh install or different device)

7. **Given** the app is running **When** ASAuthorizationAppleIDProvider.credentialRevokedNotification fires **Then** the session is immediately terminated and Sign in with Apple screen is presented

8. **Given** the app is running **When** CKAccountChanged notification fires **Then** cached credentials and tokens are flushed and local data is reconciled

## Tasks / Subtasks

- [x] Task 1: Create AuthenticationService (AC: #2, #3, #4, #5, #6)
  - [x] 1.1 Create `Services/AuthenticationService.swift` — `@Observable`, `@MainActor`
  - [x] 1.2 Define `AuthenticationServiceProtocol` in the same file (or separate `AuthenticationServiceProtocol.swift` if preferred) with methods: `checkCredentialState() async`, `signIn() async throws`, `signOut()`, and property `var currentUserID: String? { get }`. NOTE: Do NOT put `isAuthenticated` on the protocol — `@Observable` tracking does not propagate through protocol-typed references. The ViewModel owns its own `isAuthenticated` state and updates it after calling service methods.
  - [x] 1.3 Implement Keychain helper methods (private): `saveToKeychain(userIdentifier:)`, `loadFromKeychain() -> String?`, `clearKeychain()`, `saveProfileToKeychain(name:email:)`, `loadProfileFromKeychain() -> (name: String?, email: String?)?`, `clearProfileKeychain()` — use raw Security framework calls (`SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete`, `SecItemUpdate`) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. IMPORTANT: `saveToKeychain` must handle `errSecDuplicateItem` by falling back to `SecItemUpdate` — this occurs on re-auth after credential revocation (AC #5 flow)
  - [x] 1.4 Implement `checkCredentialState() async` — load userIdentifier from Keychain, call `ASAuthorizationAppleIDProvider().credentialState(forUserID:)` (async version), handle `.authorized` / `.revoked` / `.notFound` / `.transferred`
  - [x] 1.5 Implement `signIn() async throws` — create `ASAuthorizationAppleIDRequest` via `ASAuthorizationController`, use continuation-based async wrapper for the delegate callback, extract `userIdentifier`, `fullName`, `email` from `ASAuthorizationAppleIDCredential`
  - [x] 1.6 On first successful sign-in: save `userIdentifier` to Keychain, cache `fullName` and `email` to Keychain via `saveProfileToKeychain` (these are PII — do NOT use UserDefaults; these are only available on first sign-in — if missed, they are gone forever)
  - [x] 1.7 Implement `signOut()` — clear all Keychain items (userIdentifier + profile), set internal state to unauthenticated. Cancel notification observer Tasks.
  - [x] 1.8 Store `currentUserID` (the `userIdentifier` string) as a readable property on the service — this will be used by repositories for `createdByUserID` partner attribution in later stories
  - [x] 1.9 Register for `ASAuthorizationAppleIDProvider.credentialRevokedNotification` using `NotificationCenter.notifications(named:)` async sequence in a `Task` started on init. Store the `Task` handle in `@ObservationIgnored private var revocationTask: Task<Void, Never>?` for cancellation in `signOut()`/`deinit`. When fired, call `signOut()` (AC: #7)
  - [x] 1.10 Register for `.CKAccountChanged` notification using same async sequence pattern. Store in `@ObservationIgnored private var accountChangeTask: Task<Void, Never>?`. When fired: clear Keychain credentials + profile, set unauthenticated (AC: #8). NOTE: PersistenceController already observes CKAccountChanged for persistence-side handling (`PersistenceController.swift:80-86`); AuthenticationService handles auth side independently. WARNING: The two observers have no ordering guarantee — document this as a known coordination hazard for Story 4.x when PersistenceController.handleAccountChange() gets a real implementation
  - [x] 1.11 Mark ALL Task handles, notification subscriptions, and service/repository references with `@ObservationIgnored` — this includes `revocationTask`, `accountChangeTask`, and any stored continuation

- [x] Task 2: Create AuthenticationViewModel (AC: #1, #4, #5, #6)
  - [x] 2.1 Create `ViewModels/AuthenticationViewModel.swift` — `@MainActor`, `@Observable`
  - [x] 2.2 Stored properties: `isAuthenticated: Bool = false`, `isCheckingCredentials: Bool = true`. Computed property: `var showSignIn: Bool { !isAuthenticated && !isCheckingCredentials }` — do NOT store `showSignIn` as a separate Bool (redundant state causes sync bugs). The ViewModel owns `isAuthenticated` — the service does NOT expose this as an observable property (see Task 1.2 note about protocol observability)
  - [x] 2.3 Inject `AuthenticationServiceProtocol` via init with default parameter: `init(authService: AuthenticationServiceProtocol = AuthenticationService())` — both types are `@MainActor` so this default construction is safe
  - [x] 2.4 Mark `authService` as `@ObservationIgnored`
  - [x] 2.5 Implement `checkAuth() async` — set `isCheckingCredentials = true`, delegate to service's `checkCredentialState()`, set `isAuthenticated` based on result, set `isCheckingCredentials = false`. Add `guard !hasCheckedAuth else { return }` at top to prevent re-firing (`.task` in TabView re-fires on appear)
  - [x] 2.6 Implement `performSignIn() async` — delegates to service's `signIn()`, updates state on success/failure
  - [x] 2.7 Do NOT import SwiftUI in this file — ViewModels must not depend on UI framework

- [x] Task 3: Create SignInView (AC: #1)
  - [x] 3.1 Create `Views/Auth/SignInView.swift` — the blocking sign-in screen
  - [x] 3.2 Use `SignInWithAppleButton(.signIn)` from `AuthenticationServices` framework — Apple's official SwiftUI component. `onCompletion` extracts credential and calls ViewModel's `completeSignIn()` which delegates to service's `saveCredentials()`.
  - [x] 3.3 Style: `.signInWithAppleButtonStyle(.white)` in dark mode, `.black` in light mode via `@Environment(\.colorScheme)`
  - [x] 3.4 Minimal UI: centered Sign in with Apple button, app name/logo above, brief explanation text "Sign in to sync expenses with your partner" below in `.secondary` color
  - [x] 3.5 No onboarding screens, no carousel, no tutorials — the sign-in IS the onboarding (UX spec: "The entry screen IS the onboarding")
  - [x] 3.6 On cancel: explain why sign-in is required ("CloudKit requires authentication to sync your data") — remain on sign-in screen, do not dismiss
  - [x] 3.7 VoiceOver accessibility: accessibility label added to explanation text

- [x] Task 4: Wire authentication gate into app root (AC: #1, #4)
  - [x] 4.1 Modify `App/CashOutApp.swift` — add `@State private var authViewModel = AuthenticationViewModel()`
  - [x] 4.2 In the `WindowGroup` body: show nothing (empty `Color.clear` or similar) while `authViewModel.isCheckingCredentials == true` to prevent flash of sign-in screen. Show `ContentView` when `authViewModel.isAuthenticated`. Show `SignInView` when `authViewModel.showSignIn` (i.e., `!isAuthenticated && !isCheckingCredentials`). Apply `.environment(\.managedObjectContext, ...)` to BOTH branches (ContentView needs it; SignInView doesn't but keeps the modifier placement consistent for future stories)
  - [x] 4.3 Add `.task { await authViewModel.checkAuth() }` on the root view to trigger credential check on launch
  - [x] 4.4 ContentView shown directly without currentUserID parameter for now (ContentView is still a placeholder). Will be wired in Story 1.3 when ContentView gets actual content. ViewModels are never injected via environment per architecture rules.
  - [x] 4.5 Ensure the auth check is near-instant — `getCredentialState` is a local Keychain + Apple ID cache check, not a network call. No loading spinner. If cached credentials are valid, ContentView appears immediately (NFR1: "near-instant launch to entry-ready state")

- [x] Task 5: Handle ASAuthorizationController delegate pattern (AC: #2, #3)
  - [x] 5.1 Implement the `ASAuthorizationController` delegate flow within `AuthenticationService` — use a continuation-based wrapper (`withCheckedThrowingContinuation`) to bridge the delegate callback to async/await
  - [x] 5.2 The delegate requires a presentation anchor (`ASAuthorizationControllerPresentationContextProviding`) — provide the key window via `UIApplication.shared.connectedScenes` → `UIWindowScene` → `keyWindow`. Uses `nonisolated` + `MainActor.assumeIsolated` for Swift 6 strict concurrency. NOTE: This is a UIKit dependency in the service layer — accepted as a known limitation for Sign in with Apple bridging. Unit tests use the mock protocol and bypass this entirely
  - [x] 5.3 Handle the `ASAuthorizationAppleIDCredential` response: extract `user` (the userIdentifier), `fullName` (PersonNameComponents?), `email` (String?) — `fullName` and `email` are ONLY non-nil on the very first sign-in
  - [x] 5.4 Also handle `ASPasswordCredential` case (iCloud Keychain password autofill) — for this app, ignore it or treat as unsupported since we only want Apple ID sign-in

- [x] Task 6: Unit tests (all ACs)
  - [x] 6.1 Create `CashOutTests/Services/AuthenticationServiceTests.swift`
  - [x] 6.2 Create `CashOutTests/Services/MockAuthenticationService.swift` — mock implementing `AuthenticationServiceProtocol`, records method calls, returns configurable results
  - [x] 6.3 Test: `checkCredentialState` with no Keychain entry → `isAuthenticated = false`
  - [x] 6.4 Test: `checkCredentialState` with valid cached credential → tested via ViewModel mock (real credential requires Apple ID device)
  - [x] 6.5 Test: `signOut` clears Keychain and sets `isAuthenticated = false`
  - [x] 6.6 Test: ViewModel `checkAuth` delegates to service correctly
  - [x] 6.7 Test: ViewModel `performSignIn` updates `isAuthenticated` on success
  - [x] 6.8 Test: ViewModel `performSignIn` preserves `isAuthenticated = false` on failure
  - [x] 6.9 NOTE: Testing actual Sign in with Apple flow requires a real device and user interaction — mock the service protocol for unit tests. The delegate-based sign-in flow is tested via integration/UI tests only.
  - [x] 6.10 Annotate test methods with `@MainActor` because `AuthenticationService` and `AuthenticationViewModel` are `@MainActor`-isolated — Swift 6 requires test methods to match actor isolation of the types they test. Mark `MockAuthenticationService` as `@MainActor` as well.
  - [x] 6.11 Test: `CKAccountChanged` notification fires → `isAuthenticated` set to false, Keychain cleared, profile Keychain cleared

- [x] Task 7: Build verification
  - [x] 7.1 Clean build succeeds with zero errors and zero warnings
  - [x] 7.2 All existing tests still pass (no regressions from Story 1.1) — CashOutTests.testPersistenceControllerPreviewInitializes passed
  - [x] 7.3 New unit tests pass — 12 new tests, all passed (3 service + 9 ViewModel)
  - [x] 7.4 App launches in Simulator — shows Sign in with Apple screen (Simulator cannot complete actual sign-in; verify the screen appears)
  - [x] 7.5 Resolve all Swift 6 strict concurrency warnings — zero warnings in build

## Dev Notes

### Architecture Constraints (MUST follow)

- **@Observable, NOT @ObservableObject** — AuthenticationViewModel and AuthenticationService must use `@Observable` macro. No `ObservableObject`, no `@Published`. [Source: architecture.md#State Management]
- **@MainActor on ViewModels and Services** — Both `AuthenticationViewModel` and `AuthenticationService` must be `@MainActor`-isolated. [Source: architecture.md#Communication Patterns]
- **@ObservationIgnored on ALL injected references** — service references in ViewModel, notification observers in service. This prevents spurious view refreshes. [Source: .claude/learnings/architecture.md]
- **ViewModels must NOT import SwiftUI** — `AuthenticationViewModel` imports Foundation only. [Source: .claude/learnings/architecture.md]
- **Protocol + default parameter DI** — `AuthenticationServiceProtocol` with `init(authService: AuthenticationServiceProtocol = AuthenticationService())`. No DI container. [Source: architecture.md#Dependency Injection Pattern]
- **PersistenceController is the ONLY singleton** — AuthenticationService is transient, created per-ViewModel or held at app root. [Source: architecture.md#Service Boundaries]
- **Notification subscriptions via async sequences** — Use `NotificationCenter.notifications(named:)` inside a `Task`, NOT `addObserver`. Store `Task` handles as `@ObservationIgnored` properties and cancel them on teardown. For services (no `.task {}` modifier available), this is acceptable if the service is app-root-scoped — but Task handles MUST be stored for explicit cancellation. [Source: .claude/learnings/ios-swiftui.md, .claude/learnings/architecture.md]
- **Independent state properties, NOT combined enum** — Use `isAuthenticated: Bool` + `errorMessage: String?`, never `enum AuthState { case loading, authenticated, unauthenticated }`. [Source: architecture.md#ViewModel State Properties Pattern]

### Sign in with Apple Critical Details

- **Email/name ONLY on first sign-in** — Apple provides `fullName` and `email` only the very first time the user authorizes. On all subsequent calls, these return nil. Cache them immediately to Keychain on first auth (NOT UserDefaults — this is PII). They will be written to a CloudKit UserProfile record in a future story (Epic 4). [Source: architecture.md#Authentication & Security]
- **Keychain access class** — `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — survives reboots (available after first device unlock), does NOT sync via iCloud Keychain (correct behavior: `userIdentifier` is per-app-per-iCloud-account, same on all user's devices anyway). [Source: epics.md#Story 1.2]
- **Credential state differences**:
  - `.revoked` → MUST clear Keychain + clear local profile data + present sign-in (user explicitly revoked in Settings > Apple ID)
  - `.notFound` → present sign-in WITHOUT clearing Keychain (may be fresh install, Keychain has nothing to clear)
  - `.transferred` → treat as `.notFound` (enterprise account migration edge case) [Source: architecture.md#Authentication & Security]
- **ASAuthorizationController delegate** — requires `ASAuthorizationControllerPresentationContextProviding` to supply a presentation anchor (UIWindow). Use `UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow` to get it. This UIKit dependency in the service layer is accepted — unit tests mock the protocol, bypassing this.
- **Continuation pattern** — Bridge the delegate callback to async/await using `withCheckedThrowingContinuation`. Store the continuation as `@ObservationIgnored`, fulfill in `didCompleteWithAuthorization`, reject in `didCompleteWithError`.
- **Keychain duplicate handling** — `SecItemAdd` returns `errSecDuplicateItem` on the second sign-in (after revoke + re-auth). Always implement a save-or-update pattern: try `SecItemAdd`, if `errSecDuplicateItem`, fall back to `SecItemUpdate`. This applies to both the userIdentifier and profile items.

### Interaction with Existing Code

- **PersistenceController.handleAccountChange()** — Already exists at `PersistenceController.swift:99-102` as a no-op placeholder for CKAccountChanged. AuthenticationService adds its OWN independent CKAccountChanged observer for auth-side handling. Both observers coexist — they handle different concerns (persistence vs. authentication). **DATA PRIVACY HAZARD**: The PersistenceController no-op means a CKAccountChanged event will clear auth credentials but NOT reset Core Data stores. The previous user's local data will remain accessible in the stores. This is acceptable for v1 (single-device, two known users) but MUST be addressed before Story 4.x. The two observers also have no ordering guarantee — document as a known coordination hazard.
- **CashOutApp.swift** — Currently shows `ContentView` unconditionally. Must be modified to conditionally gate on auth state. Keep the existing `.environment(\.managedObjectContext)` injection.
- **ContentView.swift** — Remains a placeholder ("CashOut" text). No changes needed in this story.
- **AppDelegate.swift** — No changes needed. Sign in with Apple does not require AppDelegate modifications.
- **Views/Auth/ folder** — Already exists as empty placeholder from Story 1.1. Place `SignInView.swift` here.

### File Structure (exact paths)

**New files:**
```
CashOut/Services/AuthenticationService.swift          # Service + protocol
CashOut/ViewModels/AuthenticationViewModel.swift      # ViewModel
CashOut/Views/Auth/SignInView.swift                   # Sign-in UI
CashOutTests/Services/MockAuthenticationService.swift # Test mock
CashOutTests/Services/AuthenticationServiceTests.swift # Unit tests
```

**Modified files:**
```
CashOut/App/CashOutApp.swift                          # Add auth gate
```

### Naming Conventions (from Story 1.1)

- Types: PascalCase — `AuthenticationService`, `AuthenticationViewModel`, `SignInView`
- Files: PascalCase matching type — `AuthenticationService.swift`
- Properties: camelCase — `isAuthenticated`, `currentUserID`, `userIdentifier`
- Boolean properties: is/has/should prefix — `isAuthenticated`, `isCheckingCredentials`
- Protocols: suffix with `Protocol` — `AuthenticationServiceProtocol`

### What This Story Does NOT Include

- No CloudKit UserProfile record creation (deferred to Epic 4 — household sharing)
- No Tab navigation or ContentView changes beyond auth gating (Story 1.3)
- No UI beyond the sign-in screen — no settings, no profile view
- No partner-related auth logic (Story 4.x)
- No iCloud availability check for auth (Sign in with Apple works independent of iCloud sign-in state). NOTE: If user authenticates via Apple ID but has iCloud disabled, the app will be authenticated but sync-disabled (PersistenceController sets `cloudKitContainerOptions = nil` when `ubiquityIdentityToken` is nil). This divergence between auth state and sync state is deferred to Story 4.x.
- No implementation of `PersistenceController.handleAccountChange()` — the no-op placeholder from Story 1.1 remains. AuthenticationService handles only the auth side of CKAccountChanged.

### Deferred Work from Story 1.1 (awareness only)

- W1: `wrappedID` returns new UUID on nil — no impact on this story
- W2: `fatalError` on store load — no impact on this story
- W4: `handleAccountChange` no-op in PersistenceController — AuthenticationService handles auth side independently; PersistenceController placeholder remains for future persistence-side logic
- D1: Share acceptance falls back to private store — no impact (Story 4.1 concern)

### Testing Strategy

- **Unit tests** — Mock `AuthenticationServiceProtocol` to test ViewModel logic without Apple ID infrastructure
- **Keychain tests** — Test save/load/clear with the real Keychain in test target (Keychain works in simulator)
- **Cannot test actual Apple sign-in in unit tests** — `ASAuthorizationController` requires user interaction and entitlements. Verify the delegate wiring manually or via UI tests on a real device.
- **Swift 6 concurrency** — Use `@MainActor` on test methods, `@preconcurrency import` where needed (consistent with Story 1.1 patterns)

### UX Requirements

- **No onboarding** — Sign in screen is minimal: Apple button + brief explanation. No carousel, no tutorial, no feature tour. [Source: ux-design-specification.md#Journey 5]
- **No loading spinners** — Credential check is near-instant (local cache). If cached → straight to ContentView. No intermediate state visible. [Source: ux-design-specification.md#Loading States]
- **Cancel handling** — If user cancels sign-in, stay on sign-in screen with explanation text. Do not dismiss or crash. [Source: ux-design-specification.md#Journey 5]
- **Accessibility** — `SignInWithAppleButton` is auto-accessible. Add accessibility labels to any custom text. [Source: ux-design-specification.md#Accessibility]
- **No over-authentication** — Face ID unlocks the device; Sign in with Apple is one tap with Face ID. No additional PIN/OTP layers. [Source: ux-design-specification.md#Anti-Patterns]

### Project Structure Notes

- Aligns with MVVM folder structure from Story 1.1: Service in Services/, ViewModel in ViewModels/, View in Views/Auth/
- No new folders needed — all target directories exist
- Mock goes in test target (CashOutTests/Services/)

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Authentication & Security] — Full auth flow spec, credential states, Keychain pattern
- [Source: _bmad-output/planning-artifacts/architecture.md#State Management] — @Observable, ViewModels via @State
- [Source: _bmad-output/planning-artifacts/architecture.md#Communication Patterns] — ViewModel pattern, @ObservationIgnored
- [Source: _bmad-output/planning-artifacts/architecture.md#Dependency Injection Pattern] — Protocol + default parameter
- [Source: _bmad-output/planning-artifacts/architecture.md#Service Boundaries] — AuthenticationService owns Sign in with Apple + Keychain
- [Source: _bmad-output/planning-artifacts/architecture.md#Complete Project Directory Structure] — File locations
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.2] — Acceptance criteria, BDD scenarios
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Journey 5] — First launch flow, no onboarding
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Anti-Patterns] — No over-authentication
- [Source: _bmad-output/planning-artifacts/prd.md#Security & Privacy] — No custom credential storage
- [Source: .claude/learnings/ios-swiftui.md#Sign in with Apple] — Platform-specific learnings
- [Source: .claude/learnings/architecture.md] — MVVM and DI patterns
- [Source: _bmad-output/implementation-artifacts/1-1-xcode-project-setup-with-core-data-and-cloudkit.md] — Previous story patterns and review findings

### Guardian Validation Summary (pre-implementation)

**iOS/SwiftUI Guardian:**
- CRITICAL (FIXED): PII stored in UserDefaults → moved to Keychain
- CRITICAL (FIXED): Unmanaged Task lifetime for notification observers → stored Task handles with cancellation
- CRITICAL (FIXED): UIApplication.shared @MainActor safety → annotated delegate method
- WARNING (FIXED): Flash of SignInView on launch → isCheckingCredentials gate added to Task 4.2
- WARNING (FIXED): "published property" terminology → clarified protocol property semantics
- WARNING (FIXED): Task 6.10 reasoning → corrected to reference @MainActor types, not viewContext
- WARNING (NOTED): ASAuthorizationController in Service layer → accepted as UIKit bridging limitation, documented

**CloudKit Sync Guardian:**
- CRITICAL (NOTED): PersistenceController.handleAccountChange() is no-op → documented as data-privacy hazard, deferred to Story 4.x
- CRITICAL (FIXED): "reconcile" undefined in AC #8 → explicit actions defined in Task 1.10
- WARNING (NOTED): Two CKAccountChanged observers without ordering → documented as coordination hazard
- WARNING (NOTED): ubiquityIdentityToken not stored for change detection → Story 1.1 gap, out of scope
- WARNING (FIXED): No CKAccountChanged test case → added Test 6.11
- WARNING (FIXED): iCloud availability divergence → documented in "Does NOT Include"

**Architecture Guardian:**
- CRITICAL (FIXED): Task started in init without cancellation handles → stored Task handles
- CRITICAL (FIXED): Task 4.4 .environment() option for ViewModel → restricted to init parameter only
- CRITICAL (FIXED): Protocol isAuthenticated observability gap → ViewModel owns state, service uses method returns
- WARNING (FIXED): showSignIn redundant stored state → made computed property
- WARNING (FIXED): Task handles need @ObservationIgnored → explicitly listed
- WARNING (NOTED): UIKit dependency testability → documented as accepted limitation
- WARNING (FIXED): .environment placement on both branches → documented in Task 4.2
- WARNING (FIXED): Keychain errSecDuplicateItem → save-or-update pattern required

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Build error: `nonisolated` + `@MainActor` conflict on `presentationAnchor(for:)` — resolved by removing `@MainActor` (service is already `@MainActor` isolated, `nonisolated` is required for protocol conformance)
- Build warning: `UIWindow()` init deprecated in iOS 26 — resolved by using `UIWindow(windowScene:)` with force-unwrap (always available in running app)
- Test build error: `private(set)` on mock properties prevented test reset — resolved by making mock tracking properties settable

### Completion Notes List

- **AuthenticationService**: @Observable, @MainActor service with dual sign-in paths: (1) ASAuthorizationController delegate + continuation for programmatic use, (2) `saveCredentials()` for SignInWithAppleButton flow. Keychain save-or-update for userIdentifier and profile (name/email). Notification observers for credential revocation and CKAccountChanged with stored Task handles + restart-after-signout.
- **AuthenticationViewModel**: @Observable, @MainActor ViewModel with isAuthenticated/isCheckingCredentials state, computed showSignIn, guard against re-firing checkAuth. Task cancellation checks after all `await` boundaries. Dual sign-in paths: `performSignIn()` for programmatic, `completeSignIn()`/`failSignIn()` for button.
- **SignInView**: Uses Apple's official `SignInWithAppleButton`, extracts credential in `onCompletion`, delegates to ViewModel. Minimal UI per UX spec.
- **CashOutApp auth gate**: Conditional rendering with Color.clear during credential check, ContentView when authenticated, SignInView when not. Near-instant transition.
- **Deviation from Task 4.4**: ContentView not parameterized with currentUserID yet — it's still a placeholder from Story 1.1. Will be wired when ContentView gets real content in Story 1.3.
- **Guardian review fixes**: (1) Switched to SignInWithAppleButton per iOS guardian, (2) Added Task cancellation checks per architecture guardian, (3) Added observer restart after signOut per architecture guardian, (4) Documented loadFromKeychain internal access for @testable
- **16 unit tests**: 3 AuthenticationService (Keychain + notification), 12 AuthenticationViewModel (state management + delegation + button flow), 1 existing PersistenceController (no regression)
- **Known deferred items** (CloudKit guardian, documented in story spec): PersistenceController.handleAccountChange() no-op, two CKAccountChanged observers uncoordinated — both deferred to Story 4.x

### Review Findings

- [x] [Review][Decision] **ViewModel `isAuthenticated` not updated on mid-session revocation/CKAccountChanged** — Fixed: added `onSessionInvalidated` callback to `AuthenticationServiceProtocol`. Service calls it from both notification handlers. ViewModel wires it in `init` to reset `isAuthenticated`. Tests added for callback propagation (service) and ViewModel state reset.

- [x] [Review][Patch] Concurrent `signIn()` calls overwrite `signInContinuation` — Fixed: added guard checking `signInContinuation != nil`, throws if sign-in already in progress
- [x] [Review][Patch] Missing `import CloudKit` — Fixed: added explicit `import CloudKit` to AuthenticationService.swift
- [x] [Review][Patch] Non-Apple-ID credential silently ignored in `SignInView.onCompletion` — Fixed: added else branch calling `viewModel.failSignIn(cancelled: false, message: "Unsupported credential type")`
- [x] [Review][Patch] No test for `credentialRevokedNotification` handler — Fixed: added `testCredentialRevokedNotificationClearsState` and `testCredentialRevokedCallsSessionInvalidated`. Also improved existing notification tests to seed non-nil state and yield before posting to avoid false positives.

- [x] [Review][Defer] AC #5 "local user profile data cleared" only clears Keychain items — `PersistenceController.handleAccountChange()` is no-op [AuthenticationService.swift:92-95] — deferred, PersistenceController data cleanup deferred to Story 4.x

### File List

**New files:**
- `CashOut/Services/AuthenticationService.swift` — Service + protocol + Keychain helpers + delegate
- `CashOut/ViewModels/AuthenticationViewModel.swift` — ViewModel
- `CashOut/Views/Auth/SignInView.swift` — Sign-in UI
- `CashOutTests/Services/MockAuthenticationService.swift` — Test mock
- `CashOutTests/Services/AuthenticationServiceTests.swift` — Service unit tests
- `CashOutTests/ViewModels/AuthenticationViewModelTests.swift` — ViewModel unit tests

**Modified files:**
- `CashOut/App/CashOutApp.swift` — Auth gate added
- `CashOut.xcodeproj/project.pbxproj` — New files added to targets
