---
name: eboshi
description: Eboshi time-tracking helpers. `summary` lists the BARD Tracker tickets I worked on today in the current project, one `<type>: <title>` per line, ready to paste into a time entry.
user-invocable: true
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/summary.sh *) Bash(${CLAUDE_SKILL_DIR}/scripts/summary.sh)
arguments: command [project]
---

# Eboshi Skill

## `/eboshi summary [project-slug]`

Run, as a single Bash call:

```bash
${CLAUDE_SKILL_DIR}/scripts/summary.sh [project-slug]
```

The project defaults to the current repo's directory name (resolved through worktrees). The script lists tickets owned by me whose last update falls on today in local time, excluding Releases.

**Reply with the script's stdout verbatim inside a plain fenced code block, and nothing else** — no preamble, no bullets, no ticket IDs, no commentary afterwards. The user copies it straight into a time tracker.

If the script prints nothing, reply only: `No tickets worked on today.`

If it errors, show the error.

## Any other command

Reply that the only command is `summary`.
