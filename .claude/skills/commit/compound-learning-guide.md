# Compound Learning Guide

> *"Every mistake becomes a rule. The file gets smarter over time."*

## Questions to Ask

| Question | If YES → Add Learning |
|----------|----------------------|
| Did Claude make a mistake that needed correction? | Pattern to avoid |
| Did you discover a non-obvious pattern? | Pattern to follow |
| Is there a project-specific convention? | Convention rule |
| Did a library/API behave unexpectedly? | Gotcha warning |
| Would future-you want to know this? | General learning |

## File Routing

| Domain | File |
|--------|------|
| SwiftUI, SwiftData, iOS Platform | `.claude/learnings/ios-swiftui.md` |
| CloudKit Sync, Sharing, Offline | `.claude/learnings/cloudkit-sync.md` |
| MVVM, Data Layer, Patterns | `.claude/learnings/architecture.md` |

## How to Add

1. Pick the right file based on domain
2. Read the file to find the matching section header
3. Append the learning under the correct section using the Edit tool
4. Stage: `git add .claude/learnings/<file>.md`

**Do NOT add learnings to CLAUDE.md** — it only has a lookup table.

## Format

**Good** — brief, actionable, max 1 line:
```markdown
- **2026-03-23**: CKRecord in default zone can't be shared — always use custom CKRecordZone for household data
- **2026-03-23**: CKError.serverRecordChanged returns server record in userInfo — must re-fetch, apply changes to server copy, retry
- **2026-03-23**: @State var vm in child view creates duplicate ViewModel — children use let or @Bindable
```

**Bad** — too vague, no actionable takeaway:
```markdown
- Fixed a bug
- Updated the code
- Made it work
```

## Examples by Commit Type

### For `fix:` commits
Ask: "What caused this bug? What should Claude avoid next time?"

- `fix(sync): conflict resolution fails` → "CKError.serverRecordChanged requires extracting server record from userInfo, applying local changes to it, then retrying — retrying with original record creates infinite loop"
- `fix(auth): credential check crashes` → "ASAuthorizationAppleIDProvider.credentialState(forUserID:) throws on network failure — wrap in do/catch, proceed with cached state"

### For `feat:` commits
Ask: "What pattern emerged? What's the right way to do this?"

- `feat(household): partner pairing` → "Zone-based sharing (CKShare(recordZoneID:)) is correct for 'share everything' — hierarchical sharing requires one CKShare per root record"
- `feat(entry): quick-log flow` → "Minimum entry is category + amount; note is optional. Persist locally before CloudKit sync to maintain <5s entry speed"

### For `refactor:` commits
Ask: "Why was the old way wrong? What's better now?"

- `refactor(arch): extract sync service` → "CloudKit operations abstracted behind protocol for testability — CKContainer is not mockable directly"
- `refactor(data): dynamic queries` → "@Query only works in views, not ViewModels — use subview pattern for dynamic filters"

## Report Format

If learning identified:
```
Compound Learning:
   - Learning identified: Yes
   - Added to: .claude/learnings/<file>.md
   - File staged: Yes
```

If no learning (routine change):
```
Compound Learning:
   - Learning identified: No (routine change)
```
