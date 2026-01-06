#!/bin/bash
# Generic dispatcher for Claude Code hooks
# Runs all *.sh scripts in hooks/<HookName>/ directory

HOOK_NAME="${1:-unknown}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$SCRIPT_DIR/$HOOK_NAME"

# Read hook data from stdin
HOOK_DATA=$(cat)

# Exit silently if no directory for this hook
[[ -d "$HOOK_DIR" ]] || exit 0

# Run all .sh files in the hook directory
for script in "$HOOK_DIR"/*.sh; do
    [[ -x "$script" ]] || continue
    echo "$HOOK_DATA" | "$script" "$HOOK_NAME"
done
