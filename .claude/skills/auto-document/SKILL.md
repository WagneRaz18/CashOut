---
name: auto-document
description: Captures decisions and lessons learned from code changes. Use proactively BEFORE commits to record architectural decisions, bug fixes, and lessons into learnings files. Part of the pre-commit workflow.
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git show:*), Bash(git status:*), Edit, Write
argument-hint: "[scope] (optional - main, last, last N, or commit SHA; default: staged changes)"
user-invocable: true
model: sonnet
---

# Auto-Document Agent

Captures decisions and lessons learned from code changes into the appropriate `.claude/learnings/*.md` file.

## Input Options

- **No input**: Analyze `git diff --staged` (default for pre-commit)
- **main** or branch name: Analyze `git diff <branch>`
- **Commit SHA**: Analyze `git show <sha>`
- **last**: Analyze `git show HEAD`
- **last N**: Analyze last N commits

## Workflow

### 1. Analyze Changes

Run the appropriate git command based on input:
```bash
git diff --staged      # Default (no input)
git diff main          # With "main" input
git show HEAD          # With "last" input
```

### 2. Classify the Change

| Change Type | Target File |
|-------------|-------------|
| SwiftUI view, SwiftData model, Sign in with Apple, iOS platform | `.claude/learnings/ios-swiftui.md` |
| CloudKit sync, CKRecord, CKShare, offline queue, conflict resolution | `.claude/learnings/cloudkit-sync.md` |
| ViewModel, state management, DI, navigation, data layer pattern | `.claude/learnings/architecture.md` |
| Bug fix (any domain) | Appropriate domain file |
| Documentation-only | Skip |
| Test-only (unless new pattern) | Skip |
| Formatting/config | Skip |

### 3. Determine What to Record

**Only record non-obvious lessons.** Ask yourself:

- Would a future Claude session make this same mistake without this entry?
- Is this a gotcha that isn't self-evident from reading the code?
- Did something behave differently than expected?
- Was an architectural decision made that has non-obvious reasoning?

If YES to any → record it. If NO to all → skip.

### 4. Write to Learnings File

Read the target learnings file first, then append under the most appropriate section header.

**Format:** `- **YYYY-MM-DD**: [concise, actionable description]`

**Rules:**
- One line per learning — brief and actionable
- Lead with the symptom or surprise, then the fix/insight
- Include enough context that a future session understands without reading the diff
- Do NOT duplicate entries that already exist — grep first

### 5. Stage Updated Files

```bash
git add .claude/learnings/<modified-file>.md
```

### 6. Output Summary

```
## Documentation Created

### Learnings Recorded
- [ios-swiftui.md] <section>: <one-line summary>
- [cloudkit-sync.md] <section>: <one-line summary>
- [architecture.md] <section>: <one-line summary>

### Skipped (no lesson to record)
- <file>: <reason — formatting only / obvious change / already documented>
```

## Skip Criteria

Do NOT create entries for:
- Only formatting/whitespace changes
- Only test file changes (unless a new testing pattern was discovered)
- Only comment changes
- Reverts of previous commits
- Changes where the lesson is already in the learnings file
- Obvious things that any Swift/iOS developer would know

## Domain → File → Section Quick Reference

| Domain Signal | File | Likely Sections |
|---------------|------|-----------------|
| NavigationStack, TabView, navigation | ios-swiftui.md | SwiftUI Navigation |
| @State, @Observable, @Bindable, observation | ios-swiftui.md | SwiftUI State & Observation |
| scroll perf, lazy containers | ios-swiftui.md | SwiftUI Performance |
| ASAuthorization, Sign in with Apple, credential | ios-swiftui.md | Sign in with Apple |
| VersionedSchema, migration, schema | ios-swiftui.md | SwiftData Migrations |
| relationship, cascade, delete | ios-swiftui.md | SwiftData Relationships |
| ModelContext, ModelActor, Sendable | ios-swiftui.md | SwiftData Threading |
| CKContainer, CKRecordZone, zone | cloudkit-sync.md | Shared Database Setup |
| CKRecord, field, recordType | cloudkit-sync.md | CKRecord Types & Schema |
| CKShare, participant, UICloudSharingController | cloudkit-sync.md | CKShare & Participant Management |
| serverRecordChanged, changeTag, conflict | cloudkit-sync.md | Conflict Resolution |
| CKModifyRecordsOperation, offline, pending, queue | cloudkit-sync.md | Offline Queue & Background Sync |
| CKSubscription, CKNotification, silent push | cloudkit-sync.md | CKSubscription & Real-Time Updates |
| CKServerChangeToken, incremental sync | cloudkit-sync.md | Security & Zone Permissions |
| ViewModel, @State ownership | architecture.md | MVVM with @Observable |
| Task, .task, cancellation, async | architecture.md | Async & Task Lifecycle |
| @Query, repository, aggregate, fetch | architecture.md | Data Layer |
| .environment, init injection, DI | architecture.md | Dependency Injection |
| ViewState, isLoading, error | architecture.md | State Modeling |
| Coordinator, NavigationPath, route | architecture.md | Navigation Coordination |
