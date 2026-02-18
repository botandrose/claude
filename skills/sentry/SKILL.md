---
name: sentry
description: Query Sentry for issues, errors, and stacktraces via the API.
user-invocable: true
allowed-tools: Bash(*)
arguments: command [args]
---

# Sentry Skill

Query the Sentry API for issues, errors, and stacktraces.

## Important: Minimize Bash Tool Calls

**Each command below must be executed as a SINGLE Bash tool call.** Combine discovery, API calls, and formatting into one script. Never split discovery and the actual command into separate Bash calls.

## Implied Action

When the user provides an event ID or issue ID — whether via `/sentry <id>` or just pasting an ID in conversation — the implication is **look into it**. Fetch the details and stacktrace immediately, then investigate the cause in the codebase. Do not ask "would you like me to look into this?" — just do it.

## Discovery & Caching

Every script below starts with a discovery preamble that caches org/project info to `/tmp/sentry_config.sh`. This file is sourced on subsequent calls to skip re-discovery.

The discovery preamble (include at the top of every script):

```bash
set -euo pipefail
TOKEN=$(printenv SENTRY_AUTH_TOKEN || true)
if [ -z "$TOKEN" ]; then
  echo "ERROR: SENTRY_AUTH_TOKEN not set. Run: export SENTRY_AUTH_TOKEN=your-token"
  exit 1
fi

# Cached discovery
if [ -f /tmp/sentry_config.sh ]; then
  source /tmp/sentry_config.sh
else
  PROJECT_ID=$(grep -oP 'ingest\.[a-z]+\.sentry\.io/\K[0-9]+' config/initializers/sentry.rb 2>/dev/null || true)
  if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: Could not find Sentry DSN in config/initializers/sentry.rb"
    exit 1
  fi
  curl -s -H "Authorization: Bearer $TOKEN" "https://sentry.io/api/0/projects/" -o /tmp/sentry_projects.json
  ORG_SLUG=$(jq -r ".[] | select(.id == \"$PROJECT_ID\") | .organization.slug" /tmp/sentry_projects.json)
  PROJECT_SLUG=$(jq -r ".[] | select(.id == \"$PROJECT_ID\") | .slug" /tmp/sentry_projects.json)
  if [ -z "$ORG_SLUG" ] || [ "$ORG_SLUG" = "null" ]; then
    echo "ERROR: Could not match project ID $PROJECT_ID to a Sentry project"
    exit 1
  fi
  echo "ORG_SLUG=$ORG_SLUG" > /tmp/sentry_config.sh
  echo "PROJECT_SLUG=$PROJECT_SLUG" >> /tmp/sentry_config.sh
  echo "PROJECT_ID=$PROJECT_ID" >> /tmp/sentry_config.sh
  source /tmp/sentry_config.sh
fi
```

## Argument Auto-Detection

When the user passes a bare argument (not a subcommand like `issues` or `search`), auto-detect the type:

- **Hex string (8+ hex chars)** → event ID (full or partial). Use the event lookup flow.
- **Contains letters and hyphens matching `WORD-ALPHANUM`** (e.g., `RUBY-RAILS-N4`) → short issue ID. Use the issue lookup flow.
- **Pure digits** → numeric issue ID. Use the issue lookup flow.

This means `/sentry 8ab42773` automatically does an event lookup, and `/sentry RUBY-RAILS-N4` automatically does an issue lookup. No need for explicit `issue` or `event` subcommands (though they still work).

## Commands

### `/sentry` or `/sentry issues` — List recent unresolved issues

**Default command when no arguments are given.**

Run as a single script:

```bash
# ... discovery preamble ...

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/$ORG_SLUG/issues/?query=is:unresolved&project=$PROJECT_ID&sort=date&limit=25" \
  -o /tmp/sentry_issues.json

echo "Short ID|Level|Count|Last Seen|Title"
echo "-------|-----|-----|---------|-----"
jq -r '.[] | "\(.shortId)|\(.level)|\(.count)|\(.lastSeen | split("T") | .[0] + " " + (.[1] | split(".")[0]))|\(.title)"' /tmp/sentry_issues.json
```

Present the output as a markdown table.

### `/sentry <issue-id>` or `/sentry issue <issue-id>` — Issue details + latest stacktrace

The `issue-id` can be a numeric issue ID or a short ID like `PROJECT-N4`.

Run as a single script:

```bash
# ... discovery preamble ...

ISSUE_ID="<issue-id>"

# Fetch issue details + latest event in parallel
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/$ORG_SLUG/issues/$ISSUE_ID/" \
  -o /tmp/sentry_issue.json &
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/$ORG_SLUG/issues/$ISSUE_ID/events/latest/?full=true" \
  -o /tmp/sentry_event.json &
wait

echo "=== Issue Details ==="
jq -r '"Title: \(.title)\nCulprit: \(.culprit)\nLevel: \(.level)\nFirst seen: \(.firstSeen)\nLast seen: \(.lastSeen)\nCount: \(.count)\nUsers: \(.userCount)\nStatus: \(.status)\nAssigned: \(.assignedTo.name // "unassigned")\nLink: \(.permalink)"' /tmp/sentry_issue.json

echo ""
echo "=== Stacktrace ==="
jq -r '.entries[] | select(.type == "exception") | .data.values[] | "Exception: \(.type): \(.value)\n", (.stacktrace.frames[] | "  \(.filename):\(.lineNo) in \(.function)")' /tmp/sentry_event.json
```

Display the issue metadata and full stacktrace together.

### `/sentry <event-id>` — Event lookup (full or partial hex ID)

Detected automatically when the argument is a hex string (8+ hex chars). Full event IDs (32+ hex chars) use the direct resolve endpoint; partial IDs paginate through recent project events to find a match.

Run as a single script:

```bash
# ... discovery preamble ...

EVENT_ID="<event-id>"

# Determine if this is a full event ID (32 hex chars) or partial
CLEAN_ID=$(echo "$EVENT_ID" | tr -d '-')
ID_LEN=${#CLEAN_ID}

if [ "$ID_LEN" -ge 32 ]; then
  # Full event ID -- use the direct resolve endpoint
  curl -s -H "Authorization: Bearer $TOKEN" \
    "https://sentry.io/api/0/organizations/$ORG_SLUG/eventids/$EVENT_ID/" \
    -o /tmp/sentry_resolved.json

  FULL_EVENT_ID=$(jq -r '.event.eventID // empty' /tmp/sentry_resolved.json)
  ISSUE_ID=$(jq -r '.groupId // empty' /tmp/sentry_resolved.json)

  if [ -z "$FULL_EVENT_ID" ]; then
    echo "ERROR: Could not resolve event ID '$EVENT_ID'"
    jq '.' /tmp/sentry_resolved.json
    exit 1
  fi
else
  # Partial event ID -- paginate through project events to find a match
  FULL_EVENT_ID=""
  ISSUE_ID=""
  CURSOR=""
  MAX_PAGES=10  # 10 pages x 100 events = 1000 events searched

  for PAGE in $(seq 1 $MAX_PAGES); do
    URL="https://sentry.io/api/0/projects/$ORG_SLUG/$PROJECT_SLUG/events/?per_page=100&full=false"
    if [ -n "$CURSOR" ]; then
      URL="${URL}&cursor=${CURSOR}"
    fi

    RESPONSE=$(curl -sD /tmp/sentry_headers.txt -H "Authorization: Bearer $TOKEN" "$URL")

    # Search for matching event in this page
    MATCH=$(echo "$RESPONSE" | jq -r ".[] | select(.eventID | startswith(\"$EVENT_ID\")) | .eventID + \" \" + .groupID" | head -1)

    if [ -n "$MATCH" ]; then
      FULL_EVENT_ID=$(echo "$MATCH" | cut -d' ' -f1)
      ISSUE_ID=$(echo "$MATCH" | cut -d' ' -f2)
      break
    fi

    # Extract next cursor from Link header
    CURSOR=$(grep -i '^link:' /tmp/sentry_headers.txt | grep -oP 'cursor=\K[^&>]+(?=[^>]*rel="next"[^>]*results="true")' || true)
    if [ -z "$CURSOR" ]; then
      break  # No more pages
    fi
  done

  if [ -z "$FULL_EVENT_ID" ]; then
    echo "ERROR: No event found matching prefix '$EVENT_ID' in the last 1000 events."
    echo "The event may be older. Try providing the full 32-character event ID."
    exit 1
  fi
fi

echo "Resolved event: $FULL_EVENT_ID (issue: $ISSUE_ID)"
echo ""

# Now fetch issue details + the specific event in parallel
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/$ORG_SLUG/issues/$ISSUE_ID/" \
  -o /tmp/sentry_issue.json &
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/$ORG_SLUG/issues/$ISSUE_ID/events/$FULL_EVENT_ID/?full=true" \
  -o /tmp/sentry_event.json &
wait

echo "=== Issue Details ==="
jq -r '"Title: \(.title)\nShort ID: \(.shortId)\nCulprit: \(.culprit)\nLevel: \(.level)\nFirst seen: \(.firstSeen)\nLast seen: \(.lastSeen)\nCount: \(.count)\nUsers: \(.userCount)\nStatus: \(.status)\nAssigned: \(.assignedTo.name // "unassigned")\nLink: \(.permalink)"' /tmp/sentry_issue.json

echo ""
echo "=== Stacktrace (event $FULL_EVENT_ID) ==="
jq -r '.entries[] | select(.type == "exception") | .data.values[] | "Exception: \(.type): \(.value)\n", (.stacktrace.frames[] | "  \(.filename):\(.lineNo) in \(.function)")' /tmp/sentry_event.json
```

### `/sentry search <query>` — Search issues

Search issues using Sentry's query syntax. The query is passed directly to Sentry's search.

Common query syntax:
- `is:unresolved` — only unresolved issues
- `assigned:me` — assigned to the token owner
- `level:error` — only errors
- `message:something` — search by message text
- Free text searches error messages

Run as a single script:

```bash
# ... discovery preamble ...

QUERY="<url_encoded_query>"

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/$ORG_SLUG/issues/?query=$QUERY&sort=date&limit=25" \
  -o /tmp/sentry_search.json

echo "Short ID|Level|Count|Last Seen|Title"
echo "-------|-----|-----|---------|-----"
jq -r '.[] | "\(.shortId)|\(.level)|\(.count)|\(.lastSeen | split("T") | .[0] + " " + (.[1] | split(".")[0]))|\(.title)"' /tmp/sentry_search.json
```

Present the output as a markdown table.

## Output Formatting

- Save all API responses to temp files, then parse with `jq`
- Present tabular data as markdown tables
- For stacktraces, show frames with filename, line number, and function name
- Show exception type and message prominently
- If an API call fails, show the HTTP status code and error message from the response
