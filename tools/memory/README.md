# CashOut Memory System

Persistent semantic memory for Claude Code sessions using Pixeltable.

## Quick Start

### Search Documentation

```bash
# Via MCP (in Claude Code - automatic)
Claude calls: search_docs("CloudKit sync")

# Via CLI
source .venv/bin/activate
python -m tools.memory.query docs "CloudKit sync" --limit 5
```

### Record Knowledge

```bash
# Via MCP (in Claude Code)
Claude calls: add_decision(title="...", decision="...", rationale="...")

# Via CLI
source .venv/bin/activate
python
>>> from tools.memory.ingest import add_decision, add_issue
>>> add_decision(title="...", decision="...", rationale="...", category="architecture")
```

### Auto-Sync with Git

```bash
# Install the pre-commit hook
./install-hook.sh

# Now commits auto-ingest new/modified docs!
echo "# New Feature" > ../../docs/new-feature.md
git add ../../docs/new-feature.md
git commit -m "docs: add new feature"
# Hook automatically ingests the doc
```

## Files

| File | Purpose |
|------|---------|
| `mcp_server.py` | FastMCP server for Claude Code integration |
| `schema.py` | Pixeltable database schema |
| `ingest.py` | Document/decision/issue ingestion |
| `query.py` | CLI search interface |
| `sync-to-memory.sh` | Git integration sync script |
| `install-hook.sh` | Pre-commit hook installer |
| `.venv/` | Python virtual environment |

## Common Tasks

### Check Status

```bash
source .venv/bin/activate
python -m tools.memory.schema status
```

### Ingest New Docs

```bash
source .venv/bin/activate
python -m tools.memory.ingest file ../../docs/new-doc.md --category architecture
```

### Manual Sync (without committing)

```bash
./sync-to-memory.sh --manual
```

### Search Examples

```bash
source .venv/bin/activate

# Search docs
python -m tools.memory.query docs "expense entry flow"

# Search past issues
python -m tools.memory.query issues "sync conflict"

# Search decisions
python -m tools.memory.query decisions "CloudKit sharing"

# Search everything
python -m tools.memory.query all "SwiftData persistence"
```

## MCP Tools (Claude Code)

When connected via `.mcp.json`:

- `search_docs(query, limit)` - Search documentation
- `search_issues(query, limit)` - Find past bug fixes
- `search_decisions(query, limit)` - Find architectural decisions
- `search_all(query, limit)` - Search all sources
- `add_decision(...)` - Record a decision
- `add_issue(...)` - Record a bug fix
- `memory_status()` - Check system status

## Installation

```bash
# 1. Create venv
python3 -m venv .venv

# 2. Install dependencies
source .venv/bin/activate
pip install pixeltable sentence-transformers tiktoken mistune "mcp[cli]"

# 3. Initialize schema
cd ../..  # project root
python -m tools.memory.schema init

# 4. Ingest docs (if any exist)
python -m tools.memory.ingest dir docs/ --category general

# 5. Install git hook (optional)
cd tools/memory
./install-hook.sh
```
