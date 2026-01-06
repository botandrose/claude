#!/bin/bash
# Update wezterm title on PermissionRequest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/wezterm-title.sh"

HOOK_DATA=$(cat)

PANE_JSON=$(get_pane_info)
CURRENT_TITLE=$(get_current_title "$PANE_JSON")
PANE_TTY=$(get_pane_tty "$PANE_JSON")

NEW_TITLE=$(swap_to_waiting "$CURRENT_TITLE")

set_title "$NEW_TITLE" "$PANE_TTY"
