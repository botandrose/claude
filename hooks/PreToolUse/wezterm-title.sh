#!/bin/bash
# Update wezterm title on PreToolUse

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/wezterm-title.sh"

HOOK_DATA=$(cat)
TOOL_NAME=$(echo "$HOOK_DATA" | jq -r '.tool_name // ""' 2>/dev/null)

PANE_JSON=$(get_pane_info)
CURRENT_TITLE=$(get_current_title "$PANE_JSON")
PANE_TTY=$(get_pane_tty "$PANE_JSON")

if [[ "$TOOL_NAME" == "AskUserQuestion" ]]; then
    NEW_TITLE=$(swap_to_waiting "$CURRENT_TITLE")
else
    NEW_TITLE=$(swap_to_working "$CURRENT_TITLE")
fi

set_title "$NEW_TITLE" "$PANE_TTY"
