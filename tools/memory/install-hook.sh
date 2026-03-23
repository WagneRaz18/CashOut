#!/bin/bash
# Install pre-commit hook for CashOut memory system
#
# This script installs the git pre-commit hook that automatically
# syncs documentation changes to the memory system.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

GIT_DIR="$(cd "$PROJECT_ROOT" && git rev-parse --git-dir)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}CashOut Memory System - Hook Installer${NC}"
echo ""

HOOK_FILE="$GIT_DIR/hooks/pre-commit"

if [ -f "$HOOK_FILE" ]; then
  echo -e "${YELLOW}Warning: A pre-commit hook already exists.${NC}"
  echo ""
  cat "$HOOK_FILE"
  echo ""
  read -p "Overwrite existing hook? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 1
  fi
fi

mkdir -p "$(dirname "$HOOK_FILE")"

cat > "$HOOK_FILE" << 'HOOK_EOF'
#!/bin/bash
# Git pre-commit hook for CashOut project
# Automatically syncs relevant changes to the memory system

REPO_ROOT="$(git rev-parse --show-toplevel)"

SYNC_SCRIPT="$REPO_ROOT/tools/memory/sync-to-memory.sh"

if [ ! -f "$SYNC_SCRIPT" ]; then
  exit 0
fi

"$SYNC_SCRIPT" --quiet || true

exit 0
HOOK_EOF

chmod +x "$HOOK_FILE"

echo -e "${GREEN}Pre-commit hook installed successfully!${NC}"
echo ""
echo "Location: $HOOK_FILE"
echo ""
echo "The hook will:"
echo "  - Automatically ingest new/modified .md files in docs/ and _bmad-output/"
echo "  - Categorize them based on directory structure"
echo "  - Run silently during commits"
echo ""
echo -e "${BLUE}To manually sync (without committing):${NC}"
echo "  ./tools/memory/sync-to-memory.sh --manual"
echo ""
echo -e "${GREEN}Done!${NC}"
