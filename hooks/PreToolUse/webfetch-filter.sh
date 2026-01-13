#!/bin/bash
# Block WebFetch calls with query parameters (URLs containing ?)
# Auto-approve WebFetch calls without query params

HOOK_DATA=$(cat)

# Extract tool name
TOOL_NAME=$(echo "$HOOK_DATA" | jq -r '.tool_name // ""' 2>/dev/null)

# Only check WebFetch calls
[[ "$TOOL_NAME" == "WebFetch" ]] || exit 0

# Extract the URL
FETCH_URL=$(echo "$HOOK_DATA" | jq -r '.tool_input.url // ""' 2>/dev/null)

# Prompt for approval if URL contains query parameters
if [[ "$FETCH_URL" == *"?"* ]]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "URL contains query parameters: $FETCH_URL"
  }
}
EOF
    exit 0
fi

exit 0
