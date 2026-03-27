---
stepsCompleted: ['step-01-validate-prerequisites', 'step-02-design-epics', 'step-03-create-stories', 'step-04-final-validation']
inputDocuments:
  - prd.md
  - architecture.md
  - ux-design-specification.md
---

# CashOut - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for CashOut, decomposing the requirements from the PRD, UX Design, and Architecture into implementable stories.

## Requirements Inventory

### Functional Requirements

FR1: User can create a new expense entry by selecting a category and entering an amount
FR2: User can optionally add a text note to an expense entry
FR3: User can save an expense entry and have it immediately persisted locally
FR4: User can access the entry flow directly on app launch with zero navigation
FR5: User can view a chronological feed of all household expense entries
FR6: User can tap an existing entry to edit its category, amount, or note
FR7: User can delete an existing entry with a confirmation prompt
FR8: User can see which partner logged each entry
FR9: User can select from a set of predefined default categories (Food & Drink, Transport, Entertainment, Household, Shopping, Other)
FR10: User can create custom spending categories
FR11: User can edit existing custom categories
FR12: User can select any category (predefined or custom) with a single tap during entry
FR13: User can view a daily spending breakdown by category
FR14: User can view a weekly spending breakdown by category
FR15: User can view a monthly spending breakdown by category
FR16: User can switch between daily, weekly, and monthly views effortlessly
FR17: User can see total spending per category within any selected time period
FR18: User can see overall total spending within any selected time period
FR19: User can sign in with Apple to authenticate
FR20: Both household members can view all expense entries in a shared feed in real-time
FR21: Both household members can see edits and deletes reflected in real-time
FR22: Second partner can join the shared household by installing the app and signing in — no invite codes or manual configuration
FR23: User can create, edit, and delete entries while offline
FR24: User can view all locally stored entries while offline
FR25: System syncs queued offline changes automatically when connectivity returns
FR26: System resolves sync conflicts using last-write-wins strategy

### NonFunctional Requirements

NFR1: App launch to entry-ready state must be near-instant — no splash screens, no loading spinners
NFR2: Expense entry save must feel immediate — local persistence completes with no perceptible delay
NFR3: Switching between daily/weekly/monthly views must be instant with no loading states
NFR4: Scrolling through the expense feed must be smooth with no frame drops
NFR5: CloudKit sync must operate in the background without blocking any user interaction
NFR6: All data is encrypted at rest (Apple Data Protection) and in transit (CloudKit TLS)
NFR7: No spending data is accessible outside the household's shared CloudKit zone
NFR8: Authentication via Sign in with Apple — no custom credential storage
NFR9: No analytics, telemetry, or third-party SDKs that transmit user data
NFR10: No data leaves the device/iCloud boundary
NFR11: System retains expense data for a rolling 6-month window
NFR12: Data older than 6 months may be archived or purged
NFR13: No data loss during normal sync operations — local-first persistence guarantees durability
NFR14: Deletes and edits must propagate fully to both devices — no orphaned or ghost entries

### Additional Requirements

- Starter template: Xcode SwiftUI App template with Core Data (NOT SwiftData) + CloudKit — must be the first implementation story
- SwiftData cannot be used — must use Core Data + NSPersistentCloudKitContainer for CloudKit shared database support
- Two NSPersistentStoreDescription configurations: private scope + shared scope
- NSPersistentHistoryTrackingKey enabled for remote change detection
- initializeCloudKitSchema() in DEBUG builds for schema deployment
- Zone-level sharing with CKShare (not record-level) — custom CKRecordZone ("HouseholdZone")
- UICloudSharingController wrapped in UIViewControllerRepresentable for partner invitation
- CKShare acceptance handler in CashOutApp.swift via userDidAcceptCloudKitShareWith
- CKSharingSupported Info.plist key must be true
- Remote Notifications background mode required for NSPersistentCloudKitContainer silent push
- NSPersistentCloudKitContainer manages sync internally — no manual CKDatabaseSubscription
- Persistent history purge: periodically purge NSPersistentHistoryTransaction entries older than 7 days
- Expense entity: amount as Int64 cents, hard deletes, createdByUserID from CloudKit userRecordID
- Category entity: id, name, iconName, colorName, isDefault, sortOrder
- Schema migration: versioned .xcdatamodeld with lightweight inferred migration
- Sign in with Apple: cache userIdentifier in Keychain, cache profile to CloudKit UserProfile record, credential state handling (.authorized/.revoked/.notFound/.transferred)
- Mid-session revocation detection via ASAuthorizationAppleIDProvider.credentialRevokedNotification
- iCloud account change detection via CKAccountChanged notification
- MVVM with @Observable ViewModels (not @ObservableObject), @ObservationIgnored on repository/service references
- Repository pattern: ExpenseRepositoryProtocol, CategoryRepositoryProtocol
- NSFetchedResultsController in ExpenseRepository for Feed, remote change notification + re-fetch for Entry/Insights
- Dependency injection via protocol + default parameter (no DI container)
- PersistenceController as only singleton
- HapticService protocol for centralized haptic feedback
- Navigation: 3-tab TabView, each tab owns its own NavigationStack (never wrap TabView in NavigationStack)
- Error handling: invisible sync errors, subtle banners for persistent issues only, no modals
- Liquid Glass API rules: .buttonStyle(.glass/.glassProminent) for buttons, .glassEffect() for non-buttons, never combine both

### UX Design Requirements

UX-DR1: NumpadView — 3x4 grid with .glassEffect(.regular.interactive()) keys, 60pt+ height per key, full-width with 8pt gaps, light haptic per key tap, backspace key
UX-DR2: AmountDisplayView — SF Pro Rounded 48pt medium weight with .monospacedDigit(), "$0.00" default in secondary color, active amount in primary color, centered horizontally
UX-DR3: CategoryPickerView — horizontal ScrollView of chips with category color dot (8pt circle) + label, selected chip with tinted background + colored border, most-recently-used pre-selected
UX-DR4: FeedRowView — leading category icon in colored badge (28x28pt), center with category name + partner name + relative timestamp, trailing amount with .monospacedDigit() + optional note indicator
UX-DR5: FloatingAddButton — 52x52pt circle with .glassEffect(.regular.interactive()), SF Symbol "plus" in accent color, bottom-trailing 16pt from edges above tab bar, hidden on Add tab
UX-DR6: InsightsSummaryView — compact donut (120pt, SectorMark) + total amount + period label + week-over-week comparison text, tap donut slice to filter feed to that category
UX-DR7: Category color system — 6 muted colors with dark/light variants in asset catalog: Sage (Food & Drink), Slate (Transport), Lavender (Entertainment), Amber (Household), Dusty Rose (Shopping), Cool Gray (Other)
UX-DR8: Partner color system — Partner A cool blue (#6B8AAE), Partner B warm stone (#A89B8A), used only for initials circle on feed rows
UX-DR9: Amount-first entry pattern — numpad visible immediately on launch, category defaults to most-recently-used, save is single tap
UX-DR10: Haptic feedback patterns — light impact per numpad key, light impact on category select, success notification on save, success notification on delete, error notification on validation failure
UX-DR11: Swipe actions on feed rows — swipe-left to edit (opens edit sheet), swipe-right to delete with inline single-tap confirmation (not modal dialog)
UX-DR12: Tab structure — 3 tabs: Add (plus icon, default), Feed (list.bullet icon), Insights (chart.pie icon); Settings behind gear icon in Feed/Insights nav bar, not a tab
UX-DR13: iOS 26 Liquid Glass — .tabViewBottomAccessory for FAB, .tabBarMinimizeBehavior(.onScrollDown) on scrollable tabs, .glassEffect() on interactive controls only
UX-DR14: No loading states anywhere — local-first means data always available instantly; no spinners, skeletons, or progress indicators
UX-DR15: Empty states — Feed: "No entries yet" centered secondary text; Insights: "$0.00" headline + empty donut outline + "No entries this [period]"; No illustrations, no CTAs
UX-DR16: VoiceOver support — all interactive elements have accessibility labels; feed rows announce "[Partner] spent [amount] on [category], [time ago]"; chart text summaries via accessibility API; numpad keys announce digit
UX-DR17: Dynamic Type — all text uses SwiftUI text styles that scale; layout adapts without truncation or overlap; numpad keys scale proportionally via GeometryReader
UX-DR18: Color blindness — category colors distinguishable for protanopia/deuteranopia/tritanopia; SF Symbol icons provide redundant encoding; partner attribution uses initials + color (never color alone)
UX-DR19: Portrait-only orientation — no landscape layout support
UX-DR20: Edit flow — same numpad/category UI as entry with pre-filled values; sheet presentation (.presentationDetents([.large])) from feed row tap or swipe-left
UX-DR21: Delete flow — swipe-right on feed row; single tap inline confirmation (not modal dialog); success haptic; row animates out via system List default
UX-DR22: Insights interaction — segmented control (Day/Week/Month) pinned at top; daily bar chart (BarMark) below donut; category breakdown list with colored icons and proportion bars; tap category row or donut slice to filter feed
UX-DR23: Typography — .monospacedDigit() on all monetary amounts for vertical alignment; .rounded design on entry screen amount display only; Dynamic Type fully supported; no custom fonts
UX-DR24: Spacing — 8pt grid base unit; tokens xs:4pt, sm:8pt, md:16pt, lg:24pt, xl:32pt; all interactive elements minimum 44x44pt; numpad keys 60pt+
UX-DR25: App accent color — muted blue-gray (dark: #6B8AAE, light: #4A6D8C) for Save button active state, tab bar selected icon, and interactive elements; defined in asset catalog
UX-DR26: Emotional design — no save confirmation banners/toasts, no celebration animations, no judgment framing (no red/green on amounts), no "you overspent" language, no surveillance indicators ("partner viewed your entry")

### FR Coverage Map

FR1: Epic 1 — Create expense entry (category + amount)
FR2: Epic 1 — Optional text note on entry
FR3: Epic 1 — Immediate local persistence on save
FR4: Epic 1 — Entry flow on launch with zero navigation
FR5: Epic 2 — Chronological feed of household entries
FR6: Epic 2 — Tap entry to edit (category, amount, note)
FR7: Epic 2 — Delete entry with confirmation
FR8: Epic 2 — Partner attribution on each entry
FR9: Epic 1 — Predefined default categories (6)
FR10: Epic 5 — Create custom spending categories
FR11: Epic 5 — Edit existing custom categories
FR12: Epic 1 — Single-tap category selection during entry
FR13: Epic 3 — Daily spending breakdown by category
FR14: Epic 3 — Weekly spending breakdown by category
FR15: Epic 3 — Monthly spending breakdown by category
FR16: Epic 3 — Effortless switching between day/week/month views
FR17: Epic 3 — Total spending per category per period
FR18: Epic 3 — Overall total spending per period
FR19: Epic 1 — Sign in with Apple authentication
FR20: Epic 4 — Shared feed visible to both partners in real-time
FR21: Epic 4 — Edits and deletes reflected in real-time
FR22: Epic 4 — Second partner joins via install + sign in (no invite codes)
FR23: Epic 1 — Offline create, edit, delete (local-first architecture)
FR24: Epic 1 — View all locally stored entries while offline
FR25: Epic 4 — Automatic sync of queued offline changes on reconnect
FR26: Epic 4 — Last-write-wins conflict resolution

## Epic List

### Epic 1: Project Foundation & Solo Cash Entry
User can sign in with Apple and log cash expenses in under 5 seconds using the numpad-first entry flow, with data persisted locally. The app is fully functional for a single user, including offline capability.
**FRs covered:** FR1, FR2, FR3, FR4, FR9, FR12, FR19, FR23, FR24

### Epic 2: Expense Feed & Management
User can review their expense history in a chronological feed, fix mistakes by editing entries, and remove entries with swipe actions. Includes partner attribution and floating add button.
**FRs covered:** FR5, FR6, FR7, FR8

### Epic 3: Spending Insights
User can understand where their cash goes through interactive daily, weekly, and monthly visual breakdowns with donut charts, bar charts, and category proportion lists.
**FRs covered:** FR13, FR14, FR15, FR16, FR17, FR18

### Epic 4: Household Sharing & Real-Time Sync
Both partners share expenses in real-time — second partner installs, signs in, accepts a share link, and immediately sees all household data. Includes conflict resolution and sync management.
**FRs covered:** FR20, FR21, FR22, FR25, FR26

### Epic 5: Category Customization & Settings
User can personalize their spending categories by creating and editing custom categories, and access app settings for household management.
**FRs covered:** FR10, FR11

## Epic 1: Project Foundation & Solo Cash Entry

User can sign in with Apple and log cash expenses in under 5 seconds using the numpad-first entry flow, with data persisted locally. The app is fully functional for a single user, including offline capability.

### Story 1.1: Xcode Project Setup with Core Data & CloudKit

As a developer,
I want a properly configured Xcode project with Core Data, CloudKit, and MVVM folder structure,
So that all subsequent features can be built on a correctly-configured foundation.

**Acceptance Criteria:**

**Given** a new Xcode project
**When** created via File → New → Project → App
**Then** it uses SwiftUI lifecycle with @main entry point, Core Data storage (NOT SwiftData), and CloudKit hosting
**And** deployment target is iOS 26.0

**Given** the project capabilities
**When** configured in Xcode
**Then** CloudKit, Sign in with Apple, and Background Modes (Remote Notifications) are all enabled
**And** an iCloud CloudKit container identifier is configured

**Given** the Core Data model (.xcdatamodeld)
**When** the Expense entity is defined
**Then** it has: id (UUID), amount (Int64), note (String?), categoryID (UUID), createdByUserID (String), createdAt (Date), modifiedAt (Date)

**Given** the Core Data model
**When** the Category entity is defined
**Then** it has: id (UUID), name (String), iconName (String), colorName (String), isDefault (Bool), sortOrder (Int16)

**Given** PersistenceController
**When** initialized
**Then** it creates NSPersistentCloudKitContainer with two NSPersistentStoreDescription configurations (private + shared scopes)
**And** NSPersistentHistoryTrackingKey is enabled on both stores

**Given** a DEBUG build
**When** the app launches
**Then** initializeCloudKitSchema() is called for CloudKit schema deployment

**Given** Info.plist
**When** configured
**Then** CKSharingSupported is true and UIBackgroundModes includes remote-notification

**Given** the AppDelegate adapter
**When** configured via @UIApplicationDelegateAdaptor
**Then** it implements didReceiveRemoteNotification and forwards to PersistenceController.shared.container to enable NSPersistentCloudKitContainer silent push sync

**Given** the project file structure
**When** organized
**Then** MVVM folders exist: App/, Models/, ViewModels/, Views/Entry/, Views/Feed/, Views/Insights/, Views/Settings/, Services/, Repositories/, Utilities/Extensions/

### Story 1.2: Sign in with Apple Authentication

As a user,
I want to sign in with my Apple ID on first launch,
So that my identity is established for CloudKit sync and partner attribution.

**Acceptance Criteria:**

**Given** first app launch with no credentials in Keychain
**When** the app starts
**Then** a Sign in with Apple UI is presented as a blocking gate (cannot proceed without auth)

**Given** Sign in with Apple
**When** the user authenticates successfully
**Then** userIdentifier is cached in Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

**Given** a successful first sign-in
**When** email and name are provided by Apple
**Then** they are cached locally for future CloudKit UserProfile creation

**Given** subsequent app launches with cached credentials
**When** getCredentialState(forUserID:) returns .authorized
**Then** the user proceeds directly to the entry screen with zero delay (NFR1)

**Given** credential state check
**When** getCredentialState returns .revoked
**Then** Keychain is cleared, local user profile data is cleared, and a modal Sign in with Apple screen is presented

**Given** credential state check
**When** getCredentialState returns .notFound or .transferred
**Then** Sign in with Apple screen is presented

**Given** the app is running
**When** ASAuthorizationAppleIDProvider.credentialRevokedNotification fires
**Then** the session is immediately terminated and Sign in with Apple screen is presented

**Given** the app is running
**When** CKAccountChanged notification fires
**Then** cached credentials and tokens are flushed and local data is reconciled

### Story 1.3: App Shell & Tab Navigation

As a user,
I want a 3-tab navigation structure with the entry screen as default,
So that I can access expense entry, feed, and insights with a single tap.

**Acceptance Criteria:**

**Given** app launch after successful authentication
**When** ContentView loads
**Then** a 3-tab TabView is displayed with Add (plus icon), Feed (list.bullet icon), and Insights (chart.pie icon)

**Given** the TabView
**When** the app opens
**Then** the Add tab is selected by default (FR4)

**Given** the TabView
**When** .tabBarMinimizeBehavior(.onScrollDown) is applied
**Then** the tab bar auto-minimizes on scrollable content tabs (Feed, Insights) but not on the Add tab

**Given** the Feed and Insights tabs
**When** rendered
**Then** each owns its own NavigationStack (TabView is never wrapped in NavigationStack)

**Given** the Add tab
**When** rendered
**Then** it does NOT have a NavigationStack (single screen, no push navigation)

**Given** device orientation
**When** the app is running
**Then** only portrait orientation is supported (UX-DR19)

**Given** the Feed tab with no data
**When** displayed
**Then** "No entries yet" appears as centered text in .secondaryLabel (UX-DR15)

**Given** the Insights tab with no data
**When** displayed
**Then** "$0.00" headline with empty donut outline and "No entries this period" is shown (UX-DR15)

### Story 1.4: Design Tokens, Predefined Categories & Repository Layer

As a user,
I want predefined spending categories with consistent visual styling,
So that I can quickly categorize my cash expenses using familiar labels and colors.

**Acceptance Criteria:**

**Given** the category system
**When** the app initializes with an empty database
**Then** 6 predefined categories are seeded: Food & Drink (fork.knife, Sage), Transport (car.fill, Slate), Entertainment (film.fill, Lavender), Household (house.fill, Amber), Shopping (bag.fill, Dusty Rose), Other (ellipsis.circle.fill, Cool Gray)

**Given** category colors
**When** defined in asset catalog
**Then** each has dark and light mode variants: Sage (#7BA08A/#5C8A6E), Slate (#7B8FA8/#5A7490), Lavender (#9B8AB0/#7D6E95), Amber (#B09A7B/#957F60), Dusty Rose (#A8848B/#8E6B73), Cool Gray (#8A8D94/#6E7178)

**Given** the app accent color
**When** defined in asset catalog
**Then** it uses muted blue-gray (dark: #6B8AAE, light: #4A6D8C) (UX-DR25)

**Given** ExpenseRepositoryProtocol
**When** implemented
**Then** it exposes fetchExpenses(for:), saveExpense(_:), updateExpense(_:), and deleteExpense(id:) methods
**And** the implementation receives PersistenceController via init parameter

**Given** CategoryRepositoryProtocol
**When** implemented
**Then** it exposes fetchCategories() and saveCategory(_:) methods
**And** the implementation receives PersistenceController via init parameter

**Given** amount display needs
**When** Int64 cents need formatting
**Then** Int64.displayAmount extension converts using Foundation.FormatStyle currency (never manual "$" concatenation)

**Given** spacing tokens
**When** defined in Constants.swift
**Then** they follow 8pt grid: xs(4pt), sm(8pt), md(16pt), lg(24pt), xl(32pt) (UX-DR24)

**Given** CategoryColor enum
**When** defined
**Then** it maps colorName strings to SwiftUI Color values resolved from the asset catalog

### Story 1.5: Expense Entry Screen with Numpad & Category Picker

As a user,
I want to enter cash expenses using a numpad with category selection,
So that I can log purchases in under 5 seconds with minimal effort.

**Acceptance Criteria:**

**Given** the entry screen (Add tab)
**When** displayed
**Then** NumpadView shows a 3x4 grid of digit keys (1-9, ".", 0, backspace) with .glassEffect(.regular.interactive()) and 60pt+ key height with 8pt gaps (UX-DR1)

**Given** the entry screen
**When** displayed
**Then** AmountDisplayView shows "$0.00" in SF Pro Rounded 48pt medium weight with .monospacedDigit(), centered horizontally, in .secondaryLabel color (UX-DR2)

**Given** a numpad key tap
**When** a digit is pressed
**Then** the amount display updates immediately in primary color and a light haptic fires via HapticService (UX-DR10)

**Given** amount entry
**When** digits are typed
**Then** amounts are stored as Int64 cents (e.g., typing "1250" displays "$12.50")

**Given** the backspace key
**When** tapped
**Then** the last digit is removed from the amount

**Given** CategoryPickerView
**When** displayed above the numpad
**Then** it shows a horizontal ScrollView of category chips with color dot (8pt circle) + label, and the most-recently-used category is pre-selected (UX-DR3, UX-DR9)

**Given** a category chip
**When** tapped
**Then** it becomes selected with tinted background + colored border and a light haptic fires

**Given** the Save button
**When** amount is $0.00
**Then** the button is inactive (grayed, does not respond to taps) — no error message, no haptic (UX-DR26)

**Given** the Save button
**When** amount > $0 and tapped
**Then** the expense is saved to Core Data via ExpenseRepository with amount (Int64 cents), categoryID, createdByUserID, createdAt, modifiedAt, and optional note
**And** a success haptic fires (UINotificationFeedbackGenerator .success)
**And** the screen resets to "$0.00" with the just-used category as the new MRU default
**And** no confirmation banner, toast, or animation is shown (UX-DR26)

**Given** the optional note field
**When** accessed via a small icon or long-press on Save
**Then** the user can add free text to the entry (FR2)

**Given** the device is offline
**When** the user saves an entry
**Then** it persists locally via Core Data and the experience is identical to online (FR23, FR24)

**Given** HapticService
**When** any haptic event is triggered
**Then** all haptics route through HapticServiceProtocol.trigger(_:) and respect UIAccessibility.isReduceMotionEnabled

**Given** ExpenseEntryViewModel
**When** created
**Then** it is @Observable with @MainActor, uses @ObservationIgnored on repository/service references, and does not import SwiftUI

**Given** VoiceOver is enabled
**When** the entry screen is focused
**Then** numpad keys announce their digit, amount display announces "Amount: [value] dollars", category chips announce "[name], selected/not selected" (UX-DR16)

**Given** Dynamic Type scaling
**When** the user increases text size
**Then** all text scales via SwiftUI text styles and numpad keys scale proportionally via GeometryReader (UX-DR17)

## Epic 2: Expense Feed & Management

User can review their expense history in a chronological feed, fix mistakes by editing entries, and remove entries with swipe actions. Includes partner attribution and floating add button.

### Story 2.1: Expense Feed with Partner Attribution

As a user,
I want to see a chronological feed of all expense entries with partner attribution,
So that I can review household spending activity at a glance.

**Acceptance Criteria:**

**Given** the Feed tab
**When** selected
**Then** a reverse-chronological List of all expense entries is displayed (FR5)

**Given** a FeedRowView
**When** rendered
**Then** it shows: leading category icon in colored badge (28x28pt), category name + partner initials circle + relative timestamp (RelativeDateTimeFormatter), and trailing amount with .monospacedDigit() (UX-DR4)

**Given** partner attribution
**When** entries are displayed
**Then** each entry shows an initials circle using the partner color system (Partner A: cool blue #6B8AAE, Partner B: warm stone #A89B8A) (FR8, UX-DR8)

**Given** the feed data source
**When** FeedViewModel is created
**Then** it is @Observable with @MainActor and uses NSFetchedResultsController via ExpenseRepository for animated row insertions/deletions

**Given** the feed
**When** the user scrolls
**Then** scrolling is smooth with no frame drops (NFR4) and the tab bar auto-minimizes via .tabBarMinimizeBehavior(.onScrollDown)

**Given** no entries exist
**When** the Feed tab is shown
**Then** "No entries yet" appears as centered text in .secondaryLabel with no illustrations or CTAs (UX-DR15)

**Given** an entry has a note
**When** displayed in the feed
**Then** an optional note indicator is visible on the row

**Given** VoiceOver is enabled
**When** a feed row is focused
**Then** it announces "[Partner] spent [amount] on [category], [time ago]" (UX-DR16)

### Story 2.2: Floating Add Button

As a user,
I want a floating add button on the Feed and Insights tabs,
So that I can quickly log a new expense without switching to the Add tab.

**Acceptance Criteria:**

**Given** the Feed tab
**When** displayed
**Then** a FloatingAddButton (52x52pt circle with .glassEffect(.regular.interactive()), SF Symbol "plus" in accent color) appears bottom-trailing, 16pt from edges, above the tab bar (UX-DR5)

**Given** the Insights tab
**When** displayed
**Then** the same FloatingAddButton appears in the same position

**Given** the Add tab
**When** displayed
**Then** the FloatingAddButton is hidden (UX-DR5)

**Given** the FloatingAddButton
**When** tapped
**Then** an entry sheet is presented with the same numpad/category UI as the Add tab via .sheet() with .presentationDetents([.large])

**Given** the entry sheet
**When** an expense is saved via the sheet
**Then** the sheet dismisses and the feed or insights view updates to reflect the new entry

**Given** VoiceOver is enabled
**When** the FloatingAddButton is focused
**Then** it announces "Add expense" (UX-DR16)

### Story 2.3: Edit Expense Flow

As a user,
I want to edit an existing expense entry,
So that I can fix mistakes and keep my spending data accurate.

**Acceptance Criteria:**

**Given** a feed row
**When** the user taps it
**Then** an edit sheet opens with the same numpad/category UI pre-filled with the entry's amount, category, and note (FR6, UX-DR20)

**Given** a feed row
**When** the user swipes left
**Then** the edit sheet opens (same behavior as tap) (UX-DR11)

**Given** the edit sheet
**When** the user modifies the amount, category, or note and taps Save
**Then** the entry is updated in Core Data via ExpenseRepository, a success haptic fires, and the sheet dismisses

**Given** the edited entry
**When** saved
**Then** modifiedAt is updated and the feed row reflects the changes immediately via NSFetchedResultsController

**Given** the edit sheet
**When** the user pulls down to dismiss without saving
**Then** changes are abandoned with no "unsaved changes" warning (UX-DR26)

**Given** VoiceOver is enabled
**When** the edit sheet opens
**Then** pre-filled values are announced and all controls are accessible

### Story 2.4: Delete Expense Flow

As a user,
I want to delete an expense entry with a quick confirmation,
So that I can remove duplicates or erroneous entries while preventing accidents.

**Acceptance Criteria:**

**Given** a feed row
**When** the user swipes right
**Then** a destructive delete action appears as an inline swipe action (not a modal dialog) (UX-DR11, UX-DR21)

**Given** the delete swipe action
**When** the user taps the delete button to confirm
**Then** the entry is hard-deleted from Core Data, a success haptic fires, and the row animates out via system List default (FR7)

**Given** the delete swipe action
**When** the user swipes back or does not confirm
**Then** the entry is not deleted and the row returns to its normal state

**Given** a hard delete
**When** executed
**Then** NSPersistentCloudKitContainer handles tombstone propagation automatically via NSPersistentHistoryTracking (NFR14)

**Given** VoiceOver is enabled
**When** swipe actions are available
**Then** edit and delete actions are discoverable via the VoiceOver rotor

## Epic 3: Spending Insights

User can understand where their cash goes through interactive daily, weekly, and monthly visual breakdowns with donut charts, bar charts, and category proportion lists.

### Story 3.1: Insights Screen with Time Period Switching

As a user,
I want to switch between daily, weekly, and monthly spending views,
So that I can analyze my cash spending patterns at different time scales.

**Acceptance Criteria:**

**Given** the Insights tab
**When** selected
**Then** the default view is Weekly (UX-DR22)

**Given** the Insights screen
**When** a segmented control (Day/Week/Month) is pinned at the top
**Then** tapping a segment switches the time period instantly with no loading states (NFR3, UX-DR14)

**Given** InsightsViewModel
**When** created
**Then** it is @Observable with @MainActor, fetches expenses from ExpenseRepository for the current period, and performs in-memory aggregation by categoryID in Swift (group, sum, sort)
**And** does NOT use NSExpression-based aggregate queries

**Given** the Insights screen
**When** .NSPersistentStoreRemoteChange notification is received
**Then** aggregations are recalculated automatically via async sequence subscription in .task

**Given** the headline metric
**When** a period is selected
**Then** it shows the total spending for that period (e.g., "$247.50 This Week") with .monospacedDigit() and .title3 style (FR18, UX-DR23)

**Given** comparison text
**When** data exists for the previous period
**Then** a neutral comparison is shown (e.g., "$12 more than last week") — no judgment framing, no red/green coloring (UX-DR26)

**Given** no entries for the selected period
**When** the Insights screen is shown
**Then** "$0.00" headline with empty donut outline and "No entries this [period]" is displayed (UX-DR15)

**Given** the .task handler
**When** the Insights tab appears
**Then** it guards against redundant re-loads (re-fires on every tab appear in TabView)

### Story 3.2: Category Donut Chart

As a user,
I want a visual donut chart showing my spending proportions by category,
So that I can instantly see where most of my cash is going.

**Acceptance Criteria:**

**Given** the Insights screen
**When** data exists for the selected period
**Then** a compact donut chart (120pt, SectorMark via Swift Charts) displays category proportions using the muted category colors (UX-DR6, UX-DR7)

**Given** the donut chart
**When** a slice is tapped
**Then** the view navigates to a filtered feed showing only entries for that category (UX-DR22)

**Given** chart colors
**When** rendered
**Then** they use the same category colors as feed rows and category picker — consistent everywhere

**Given** the donut chart
**When** rendered in dark mode and light mode
**Then** category colors use their respective mode variants from the asset catalog

**Given** VoiceOver is enabled
**When** the donut chart is focused
**Then** it provides a text summary via accessibility API: "This week total: [amount]. Largest category: [name] at [amount]" (UX-DR16)

**Given** no data for the period
**When** the donut area is rendered
**Then** an empty donut outline is shown (not hidden entirely) (UX-DR15)

### Story 3.3: Daily Bar Chart & Category Breakdown List

As a user,
I want a bar chart showing daily spending patterns and a detailed category breakdown,
So that I can identify spending trends and see per-category totals.

**Acceptance Criteria:**

**Given** the Insights screen below the donut
**When** data exists for the selected period
**Then** a bar chart (BarMark via Swift Charts) shows daily totals for the Day view, daily totals (Mon-Sun) for the Week view, and weekly totals for the Month view (UX-DR22)

**Given** the bar chart
**When** rendered
**Then** the Y-axis adjusts dynamically so the largest value fills the chart — no fixed thresholds, no red budget ceiling lines

**Given** the category breakdown
**When** displayed below the bar chart
**Then** each row shows: category colored icon, category name, amount with .monospacedDigit(), and a proportion bar indicating percentage of total (FR17)

**Given** a category breakdown row
**When** tapped
**Then** the view navigates to a filtered feed showing only entries for that category (same as tapping a donut slice) (UX-DR22)

**Given** the Insights screen
**When** the user scrolls down through charts and breakdown
**Then** the tab bar auto-minimizes via .tabBarMinimizeBehavior(.onScrollDown) (UX-DR13)

**Given** the Insights screen
**When** a filtered feed is showing
**Then** a system back button (from NavigationStack) returns to the full Insights view

**Given** VoiceOver is enabled
**When** the bar chart is focused
**Then** it announces daily/weekly totals as text summaries (UX-DR16)

**Given** VoiceOver is enabled
**When** a category breakdown row is focused
**Then** it announces "[category name], [amount], [percentage] of total"

## Epic 4: Household Sharing & Real-Time Sync

Both partners share expenses in real-time — second partner installs, signs in, accepts a share link, and immediately sees all household data. Includes conflict resolution and sync management.

### Story 4.1: CloudKit Shared Zone & Partner Invitation

As a user,
I want to invite my partner to a shared household via a system share sheet,
So that we can both see each other's cash expenses in real-time.

**Acceptance Criteria:**

**Given** the app's CloudKit configuration
**When** the first user sets up sharing
**Then** a custom CKRecordZone ("HouseholdZone") is created for zone-level sharing (not record-level)

**Given** the Settings screen Household section
**When** the user taps "Invite Partner"
**Then** UICloudSharingController (wrapped in UIViewControllerRepresentable) presents the system share sheet for AirDrop/iMessage

**Given** the share sheet
**When** the user sends a CKShare URL via AirDrop or iMessage
**Then** the partner receives a functional share invitation link (FR22)

**Given** CloudSharingService
**When** created
**Then** it depends on PersistenceController and AuthenticationService

**Given** the HouseholdZone
**When** the app launches fresh
**Then** zone existence is verified (users can delete zones via iOS Settings → iCloud) and recreated if missing

**Given** no partner has been invited
**When** the app is used solo
**Then** all features work fully without sharing — solo mode is never degraded

**Given** the Settings Household section
**When** a partner is already connected
**Then** partner info (name/initials) is displayed instead of the invite button

### Story 4.2: Partner Share Acceptance & Data Sync

As a partner,
I want to accept a share invitation and immediately see all household expenses,
So that I can join the shared household with zero configuration.

**Acceptance Criteria:**

**Given** a CKShare URL
**When** the partner taps it after installing CashOut and signing in with Apple
**Then** CashOutApp.swift handles the acceptance via userDidAcceptCloudKitShareWith and calls container.accept(metadata) (FR22)

**Given** the CKSharingSupported Info.plist key
**When** set to true
**Then** the system correctly routes share acceptance callbacks to the app

**Given** successful share acceptance
**When** the partner's NSPersistentCloudKitContainer connects to the shared database
**Then** all existing entries from the owner appear in the partner's feed immediately (FR20)

**Given** the shared database
**When** either partner creates a new expense
**Then** it appears on the other partner's device within seconds via NSPersistentCloudKitContainer silent push (FR20)

**Given** the shared database
**When** either partner edits an expense
**Then** the edit is reflected on the other device in real-time (FR21)

**Given** the shared database
**When** either partner deletes an expense
**Then** it disappears from both devices with no orphaned records (FR21, NFR14)

**Given** both partners edit the same entry while offline
**When** both devices reconnect
**Then** last-write-wins conflict resolution is applied via CKRecord change tags — the most recent save overwrites (FR26)

### Story 4.3: Real-Time Feed Updates & Sync Management

As a user,
I want my partner's entries to appear in real-time and sync to be managed reliably,
So that our shared feed is always current and no data is lost.

**Acceptance Criteria:**

**Given** .NSPersistentStoreRemoteChange notification
**When** received
**Then** Feed updates via NSFetchedResultsController (animated row insertions) and Insights re-fetches and re-aggregates

**Given** a partner's new entry arriving via sync
**When** displayed in the feed
**Then** the row animates in via NSFetchedResultsController delegate callbacks

**Given** partner entries in the feed
**When** rendered with attribution
**Then** partner initials circles use the partner color system (Partner A: cool blue #6B8AAE, Partner B: warm stone #A89B8A) (UX-DR8)

**Given** offline changes by either partner
**When** connectivity returns
**Then** queued changes sync automatically via NSPersistentCloudKitContainer — no user action required (FR25)

**Given** persistent history
**When** the app launches
**Then** NSPersistentHistoryTransaction entries older than 7 days are purged to prevent unbounded growth

**Given** a hard delete while the partner is offline
**When** the CloudKit tombstone window expires and the partner reconnects with .changeTokenExpired
**Then** NSPersistentCloudKitContainer performs a full re-import from the server; however, orphaned local records that were deleted on the server past the tombstone window may persist locally — this is a known v1 limitation acceptable at 2-user scale (manual reconciliation deferred to post-MVP if observed)

**Given** transient sync errors (network, throttle)
**When** they occur
**Then** NSPersistentCloudKitContainer retries automatically with no user visibility (NFR5)

**Given** persistent sync failure
**When** detected over an extended period
**Then** a small non-intrusive icon appears in the navigation bar — no modals, no red alerts, no banners (UX-DR26)

**Given** iCloud is not signed in
**When** detected on launch
**Then** a subtle banner shows "Sign in to iCloud to sync" (not blocking — local features still work)

**Given** CloudKit quota exceeded
**When** detected
**Then** it is silently ignored for v1 (2-user scale is negligible)

## Epic 5: Category Customization & Settings

User can personalize their spending categories by creating and editing custom categories, and access app settings for household management.

### Story 5.1: Settings Screen

As a user,
I want to access app settings from the feed or insights screen,
So that I can manage categories and household configuration in one place.

**Acceptance Criteria:**

**Given** the Feed navigation bar
**When** the gear icon (gearshape) is tapped
**Then** the Settings screen opens via NavigationStack push

**Given** the Insights navigation bar
**When** the gear icon is tapped
**Then** the same Settings screen opens

**Given** the Settings screen
**When** displayed
**Then** it uses a standard Form/List with grouped sections: Categories, Household, About

**Given** the Household section
**When** no partner is connected
**Then** it shows the "Invite Partner" button (triggers UICloudSharingController from Epic 4)

**Given** the Household section
**When** a partner is connected
**Then** it shows partner info (name/initials) and sharing status

**Given** the About section
**When** displayed
**Then** it shows app version and a privacy note ("Your data stays on your devices and iCloud. No analytics, no third-party access.")

**Given** the Settings screen
**When** any setting is changed
**Then** the core entry flow on the Add tab is never affected — no settings gate or modify the entry experience

### Story 5.2: Custom Category Creation & Editing

As a user,
I want to create and edit custom spending categories,
So that I can track cash spending in categories that match my personal spending patterns.

**Acceptance Criteria:**

**Given** the Categories section in Settings
**When** displayed
**Then** all 6 predefined categories are listed first (with their icons and colors) followed by any custom categories

**Given** predefined categories
**When** displayed in Settings
**Then** they cannot be edited or deleted (isDefault: true is enforced)

**Given** an "Add Category" button
**When** tapped
**Then** a form is presented allowing the user to enter a name, select an SF Symbol icon, and choose a color from a secondary muted palette

**Given** a new custom category
**When** saved via CategoryRepository
**Then** it immediately appears in the CategoryPickerView on the entry screen and is selectable with a single tap (FR10, FR12)

**Given** an existing custom category in the list
**When** tapped in Settings
**Then** an edit form allows changing its name, icon, and color (FR11)

**Given** a custom category edit
**When** saved
**Then** the updated name, icon, and color are reflected everywhere: entry screen picker, feed rows, and insights charts

**Given** custom categories
**When** created or edited
**Then** they sync to the partner's device via the shared CloudKit zone (categories are shared household data)

**Given** VoiceOver is enabled
**When** navigating the category management screen
**Then** all category names, icons, and actions (add, edit) are properly labeled and accessible (UX-DR16)

**Given** the custom category color picker
**When** displayed
**Then** colors are distinguishable from predefined category colors and from each other in both dark and light modes (UX-DR18)
