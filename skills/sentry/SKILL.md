---
name: sentry
description: Query Sentry for issues, errors, and stacktraces via the API.
user-invocable: true
allowed-tools: Bash(*)
arguments: command [args]
---

# Sentry Skill

Query the Sentry API for issues, errors, and stacktraces.

## Authentication

**IMPORTANT:** The `$SENTRY_AUTH_TOKEN` shell variable may not expand correctly in all environments. Always read the token using `printenv`:

```bash
TOKEN=$(printenv SENTRY_AUTH_TOKEN)
```

Then use `$TOKEN` in all curl commands:

```bash
curl -s -H "Authorization: Bearer $TOKEN" <url>
```

If the token is empty (test with `test -z "$(printenv SENTRY_AUTH_TOKEN)"`), stop and tell the user to set it:
```
export SENTRY_AUTH_TOKEN="your-token-here"
```

## Org & Project Discovery

Before running any command, resolve the org slug, project slug, and project numeric ID.

**Use a single API call** to discover everything: `GET /api/0/projects/` returns all accessible projects with embedded organization info.

```bash
TOKEN=$(printenv SENTRY_AUTH_TOKEN)
curl -s -H "Authorization: Bearer $TOKEN" "https://sentry.io/api/0/projects/" -o /tmp/sentry_projects.json
```

Each project in the response contains:
- `.id` — project numeric ID
- `.slug` — project slug
- `.organization.id` — org numeric ID
- `.organization.slug` — org slug

### Matching to the current project

Check for a Sentry DSN in `config/initializers/sentry.rb`. The DSN format is:

```
https://<key>@o<org_id>.ingest.us.sentry.io/<project_id>
```

Parse out:
- **org numeric ID**: the number after `o` in the hostname (e.g., `o4506` → `4506`)
- **project numeric ID**: the path segment after the host (e.g., `/4507` → `4507`)

```bash
grep -oP 'https://[^@]+@o\K[0-9]+' config/initializers/sentry.rb
grep -oP 'ingest\.[a-z]+\.sentry\.io/\K[0-9]+' config/initializers/sentry.rb
```

Then match the project numeric ID from the DSN against `.id` in the projects response to get the project slug and org slug.

### Fallback

If `config/initializers/sentry.rb` doesn't exist or contains no DSN:
- If there's only one project, use it automatically
- If multiple projects, list them and ask the user to specify

**Cache the resolved org_slug, project_slug, and project_id for subsequent commands within the session.**

## Commands

### `/sentry` or `/sentry issues [project-slug]` — List recent unresolved issues

List the 25 most recent unresolved issues. **This is the default command when no arguments are given.** If `project-slug` is provided, filter to that project. If omitted, use the default project discovered above.

1. Use the project numeric ID (already resolved during discovery, or look it up from `/tmp/sentry_projects.json`)

2. Fetch issues and save to a temp file (responses can be large):

```bash
TOKEN=$(printenv SENTRY_AUTH_TOKEN)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/{org_slug}/issues/?query=is:unresolved&project={project_id}&sort=date&limit=25" \
  -o /tmp/sentry_issues.json
```

3. Format output as a readable table:

```bash
jq -r '.[] | "\(.shortId)\t\(.level)\t\(.count)\t\(.lastSeen)\t\(.title)"' /tmp/sentry_issues.json
```

Display columns: Short ID, Level, Count, Last Seen, Title.

### `/sentry issue <issue-id>` — Issue details + latest stacktrace

The `issue-id` can be either:
- A numeric issue ID
- A short ID like `PROJECT-123`

1. Fetch issue details:

```bash
TOKEN=$(printenv SENTRY_AUTH_TOKEN)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/{org_slug}/issues/{issue_id}/" \
  -o /tmp/sentry_issue.json
```

Display: title, culprit, level, first seen, last seen, count, user count, status, assigned to, link.

2. Fetch the latest event with full stacktrace:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/{org_slug}/issues/{issue_id}/events/latest/?full=true" \
  -o /tmp/sentry_event.json
```

3. Extract and format the stacktrace from the event:

The stacktrace lives in the event's `entries` array. Look for entries with `type: "exception"`. Each exception entry has `data.values[]` containing exceptions with `type`, `value`, and `stacktrace.frames[]`.

Extract with:
```bash
jq -r '.entries[] | select(.type == "exception") | .data.values[] | "Exception: \(.type): \(.value)\n", (.stacktrace.frames[] | "  \(.filename):\(.lineNo) in \(.function)")' /tmp/sentry_event.json
```

Show the full exception chain with the most recent exception last. Include the exception type and message.

### `/sentry search <query>` — Search issues

Search issues using Sentry's query syntax.

```bash
TOKEN=$(printenv SENTRY_AUTH_TOKEN)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/{org_slug}/issues/?query={url_encoded_query}&sort=date&limit=25" \
  -o /tmp/sentry_search.json
```

The query is passed directly to Sentry's search. Common query syntax:
- `is:unresolved` — only unresolved issues
- `assigned:me` — assigned to the token owner
- `level:error` — only errors
- `message:something` — search by message text
- Free text searches error messages

Format the results the same as `/sentry issues`.

## Output Formatting

- Save all API responses to temp files first, then parse with `jq` (avoids issues with large responses in pipes)
- Present data in readable, aligned columns suitable for terminal output
- For stacktraces, format frames clearly with filename, line number, function name, and context
- Show exception type and message prominently
- If an API call fails, show the HTTP status code and error message from the response
