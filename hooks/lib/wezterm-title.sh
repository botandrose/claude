#!/bin/bash
# Shared functions for wezterm title manipulation

get_pane_info() {
    wezterm cli list --format json 2>/dev/null | jq ".[] | select(.pane_id == $WEZTERM_PANE)"
}

get_current_title() {
    echo "$1" | jq -r '.title // ""'
}

get_pane_tty() {
    echo "$1" | jq -r '.tty_name // ""'
}

set_title() {
    local new_title="$1"
    local pane_tty="$2"
    if [[ -n "$pane_tty" && -w "$pane_tty" ]]; then
        printf '\033]0;%s\007' "$new_title" > "$pane_tty" 2>/dev/null
    fi
}

swap_to_working() {
    echo "${1//🔶/✳}"
}

swap_to_waiting() {
    echo "${1//✳/🔶}"
}
