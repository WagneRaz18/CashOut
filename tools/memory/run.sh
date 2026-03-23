#!/bin/bash
# Wrapper script to run memory tools with the virtual environment
# Usage: ./tools/memory/run.sh <module> <args...>
# Examples:
#   ./tools/memory/run.sh schema init
#   ./tools/memory/run.sh ingest dir docs/ --category architecture
#   ./tools/memory/run.sh query docs "CloudKit sync"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Run the specified module
MODULE="$1"
shift

python -m "tools.memory.$MODULE" "$@"
