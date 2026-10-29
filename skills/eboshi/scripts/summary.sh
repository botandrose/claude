#!/bin/bash
# Usage: summary.sh [project-slug]

set -euo pipefail

API="https://bardtracker.com/api/v1"
AUTH="Authorization: Bearer ${BARD_TRACKER_API_TOKEN:?BARD_TRACKER_API_TOKEN not set}"

# Resolve through worktrees to the main repo's directory name.
if COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  DEFAULT_SLUG=$(basename "$(dirname "$COMMON_DIR")")
else
  DEFAULT_SLUG=$(basename "$PWD")
fi
SLUG="${1:-$DEFAULT_SLUG}"

PROJECT_ID=$(curl -sf -H "$AUTH" "$API/projects" | jq -r --arg slug "$SLUG" '.[] | select(.slug == $slug) | .id')
if [ -z "$PROJECT_ID" ]; then
  echo "Error: no BARD Tracker project with slug '$SLUG'" >&2
  exit 1
fi

ME_ID=$(curl -sf -H "$AUTH" "$API/me" | jq -r ".id")

# The API's date predicates are UTC, so over-fetch and cut at local midnight.
SINCE=$(date -u -d "@$(date -d 'today 00:00' +%s)" +%Y-%m-%dT%H:%M:%SZ)
FETCH_AFTER=$(date -d "2 days ago" +%F)

curl -sf -G -H "$AUTH" "$API/projects/$PROJECT_ID/tickets" \
  --data-urlencode "filter=owner:$ME_ID updated:>$FETCH_AFTER" \
  --data-urlencode "limit=500" |
  jq -r --arg since "$SINCE" '
    .[]
    | select(.ticket_type != "Release")
    | select((.updated_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) >= ($since | fromdateiso8601))
    | "\(.ticket_type): \(.name)"
  '
