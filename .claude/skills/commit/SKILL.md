---
name: commit
description: Commit changes with enforced auto-documentation and compound learning workflow. Use this for ALL commits - it ensures decisions, issues, and learnings are captured before committing.
argument-hint: "[optional commit message or context]"
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Skill
---

# Commit Workflow

1. **Stage** → 2. **Classify** → 3. **Auto-document** → 4. **Compound Learning** → 5. **Commit & Verify**

---

## Step 1: Stage Changes

```bash
git status
git add <specific-files>   # Be specific, avoid -A unless intentional
```

Review what's staged:
```bash
git diff --cached --stat
```

## Step 2: Classify Commit Type

| Prefix | Auto-Document | Compound Learning |
|--------|---------------|-------------------|
| `fix:` | **REQUIRED** | **REQUIRED** |
| `feat:` | **REQUIRED** | **REQUIRED** |
| `refactor:` | **REQUIRED** | **REQUIRED** |
| `docs:` | Skip | Optional |
| `test:` | Skip | Optional |
| `chore:` | Skip | Optional |

Steps 3-4 are **REQUIRED** for `fix:`/`feat:`/`refactor:`. For `docs:`/`test:`/`chore:`, skip to Step 5.

## Step 3: Auto-Documentation

Invoke via **Skill tool**:

```
Skill tool → skill: "auto-document"
```

This analyzes `git diff --staged` and records lessons to the appropriate `.claude/learnings/*.md` file.

**DO NOT SKIP for fix/feat/refactor changes.**

## Step 4: Compound Learning

Evaluate whether this commit produced a learning worth capturing. See [compound-learning-guide.md](compound-learning-guide.md) for detailed questions and examples.

**Quick check:** Did Claude make a correctable mistake? Discover a non-obvious pattern? Hit unexpected API behavior? If YES → add to the matching learnings file.

| Domain | File |
|--------|------|
| SwiftUI, SwiftData, iOS Platform | `.claude/learnings/ios-swiftui.md` |
| CloudKit Sync, Sharing, Offline | `.claude/learnings/cloudkit-sync.md` |
| MVVM, Data Layer, Patterns | `.claude/learnings/architecture.md` |

**Format:** Brief, actionable, max 1 line. Read the file first, append under the correct section header.

```bash
git add .claude/learnings/<file>.md   # Stage if learning added
```

**Do NOT add learnings to CLAUDE.md** — it only has a lookup table pointing to these files.

## Step 5: Commit & Verify

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <description>

<body - what and why>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

Verify:
```bash
git log --oneline -1
git status
```

---

## Commit Message Convention

```
<type>(<scope>): <short description>

<body — what changed and why>
```

**Types:** `fix`, `feat`, `refactor`, `docs`, `test`, `chore`

**Scopes for CashOut:**

| Scope | When |
|-------|------|
| `entry` | Expense entry flow, amount input, quick-log |
| `categories` | Category management, defaults, custom categories |
| `insights` | Daily/weekly/monthly views, spending breakdowns |
| `household` | Household setup, partner pairing, CKShare |
| `sync` | CloudKit sync, CKRecord operations, offline queue |
| `settings` | User preferences, app configuration |
| `data` | SwiftData models, migrations, persistence |
| `offline` | Offline queue, pending operations, NWPathMonitor |
| `ui` | General UI, navigation, theming |
| `arch` | Architecture, DI, coordinators, base patterns |
| `auth` | Sign in with Apple, authentication state |

---

## Output Format

```
COMMIT WORKFLOW COMPLETE

Changes Staged:
   - <list of files>

Commit Type: fix|feat|refactor|docs|test|chore

Documentation:
   - Auto-document: Ran / Skipped (docs/test/chore)

Compound Learning:
   - Learning identified: Yes / No
   - Added to: .claude/learnings/<file>.md / N/A

Committed: "<commit message>"
   SHA: <short-sha>

Remember: Do NOT push. Create PR separately if needed.
```

---

## Rules

1. **NEVER skip auto-documentation** for fix/feat/refactor — invoke via `Skill` tool (`skill: "auto-document"`)
2. **ALWAYS evaluate compound learning** for fix/feat/refactor
3. **NEVER push** — this workflow is commit-only
4. **Stage all auxiliary changes** (learnings files) in the same commit
5. **Be specific with git add** — avoid `git add -A` or `git add .`

## Arguments

- No arguments: Commit all staged changes (determines message from diff)
- `$ARGUMENTS`: Optional commit message hint or additional context
