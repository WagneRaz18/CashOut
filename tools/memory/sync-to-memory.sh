#!/bin/bash
# sync-to-memory.sh - Sync staged changes to CashOut memory system
#
# This script can be run:
# 1. Automatically via git pre-commit hook
# 2. Manually: ./tools/memory/sync-to-memory.sh [--manual]
#
# It syncs:
# - Markdown files in docs/ (architecture, ADRs, stories, etc.)
# - Markdown files in _bmad-output/ (BMAD workflow artifacts)
# - All ingested to the semantic memory system for search

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEMORY_VENV="$SCRIPT_DIR/.venv"
MEMORY_PYTHON="$MEMORY_VENV/bin/python"

GIT_ROOT="$(cd "$PROJECT_ROOT" && git rev-parse --show-toplevel)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

MANUAL_MODE=false
QUIET_MODE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --manual)
      MANUAL_MODE=true
      shift
      ;;
    --quiet)
      QUIET_MODE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

log_info() {
  if [ "$QUIET_MODE" = false ]; then
    echo -e "${BLUE}[CashOut Memory Sync]${NC} $1"
  fi
}

log_success() {
  if [ "$QUIET_MODE" = false ]; then
    echo -e "${GREEN}[CashOut Memory Sync]${NC} $1"
  fi
}

log_warning() {
  if [ "$QUIET_MODE" = false ]; then
    echo -e "${YELLOW}[CashOut Memory Sync]${NC} $1"
  fi
}

log_error() {
  echo -e "${RED}[CashOut Memory Sync]${NC} $1"
}

check_memory_initialized() {
  if [ ! -d "$MEMORY_VENV" ]; then
    log_error "Memory system not initialized. Virtual environment not found at: $MEMORY_VENV"
    log_error "Run: cd $PROJECT_ROOT && python3 -m venv tools/memory/.venv"
    log_error "Then: source tools/memory/.venv/bin/activate && pip install pixeltable sentence-transformers tiktoken mistune"
    return 1
  fi

  if [ ! -f "$MEMORY_PYTHON" ]; then
    log_error "Python not found in virtual environment: $MEMORY_PYTHON"
    return 1
  fi

  if ! "$MEMORY_PYTHON" -m tools.memory.schema status > /dev/null 2>&1; then
    log_error "Memory schema not initialized. Run: source tools/memory/.venv/bin/activate && python -m tools.memory.schema init"
    return 1
  fi

  return 0
}

get_category_for_file() {
  local filepath="$1"

  # Handle _bmad-output paths
  if echo "$filepath" | grep -q '_bmad-output'; then
    case "$filepath" in
      *planning-artifacts/prd*) echo "prd" ;;
      *planning-artifacts/architecture*) echo "architecture" ;;
      *planning-artifacts/epics*) echo "stories" ;;
      *planning-artifacts/ux*) echo "ux" ;;
      *planning-artifacts/*) echo "planning" ;;
      *implementation-artifacts/stories/*) echo "stories" ;;
      *implementation-artifacts/retrospectives/*) echo "retrospectives" ;;
      *implementation-artifacts/td-*) echo "technical-debt" ;;
      *implementation-artifacts/*) echo "implementation" ;;
      *test-design*) echo "qa" ;;
      *test-review*) echo "qa" ;;
      *test-automation*) echo "qa" ;;
      *traceability*) echo "qa" ;;
      *automation-summary*) echo "implementation" ;;
      *nfr*) echo "architecture" ;;
      *) echo "bmad" ;;
    esac
    return
  fi

  # Handle docs/ paths
  case "$filepath" in
    *docs/architecture/*) echo "architecture" ;;
    *docs/stories/*) echo "stories" ;;
    *docs/adr/*) echo "adr" ;;
    *docs/technical-debt/*) echo "technical-debt" ;;
    *docs/analysis/*) echo "analysis" ;;
    *docs/qa/*) echo "qa" ;;
    *docs/prd/*) echo "prd" ;;
    *docs/implementation/*) echo "implementation" ;;
    *docs/*) echo "general" ;;
    *) echo "other" ;;
  esac
}

ingest_staged_docs() {
  log_info "Checking for staged documentation changes..."

  local staged_md_files
  if [ "$MANUAL_MODE" = true ]; then
    staged_md_files=$(cd "$GIT_ROOT" && git diff --name-only HEAD 2>/dev/null | grep '\.md$' | grep -E '(docs/|_bmad-output/)' || true)
  else
    staged_md_files=$(cd "$GIT_ROOT" && git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep '\.md$' | grep -E '(docs/|_bmad-output/)' || true)
  fi

  if [ -z "$staged_md_files" ]; then
    log_info "No markdown files to ingest."
    return 0
  fi

  local file_count=0
  local ingested_count=0

  while IFS= read -r file; do
    [ -z "$file" ] && continue

    local full_path="$GIT_ROOT/$file"

    if [ ! -f "$full_path" ]; then
      continue
    fi

    ((file_count++)) || true

    local category
    category=$(get_category_for_file "$file")

    log_info "Ingesting: $file (category: $category)"

    if "$MEMORY_PYTHON" -m tools.memory.ingest file "$full_path" --category "$category" 2>&1 | grep -q "\[+\] Ingested"; then
      ((ingested_count++)) || true
    fi
  done <<< "$staged_md_files"

  if [ $file_count -gt 0 ]; then
    log_success "Processed $file_count doc file(s), ingested $ingested_count new file(s)"
  fi
}

main() {
  cd "$PROJECT_ROOT"

  if [ "$MANUAL_MODE" = true ]; then
    log_info "Running in MANUAL mode (analyzing all changes)"
  else
    log_info "Running in HOOK mode (analyzing staged changes)"
  fi

  if ! check_memory_initialized; then
    log_error "Memory system not ready. Skipping sync."
    exit 0
  fi

  ingest_staged_docs

  if [ "$QUIET_MODE" = false ]; then
    log_success "Memory sync complete!"
  fi
}

main "$@"
