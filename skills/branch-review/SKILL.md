---
name: branch-review
description: Analyze git branches to determine if they can be safely deleted. Categorizes branches as safe to delete (merged/subset), probably safe (superseded by rebased work), or keep (active unmerged work).
user-invocable: true
allowed-tools: Bash(*)
---

# Branch Review Skill

Use this skill to analyze git branches and make informed decisions about whether they can be safely deleted.

## What This Skill Does

This skill analyzes git branches and categorizes them into three deletion safety levels:

1. **Safe to delete** - Branch is a strict subset of the main branch (all commits exist in main, or would after rebasing)
2. **Probably safe to delete** - Branch contains earlier iterations of work that was eventually rebased and merged differently
3. **Keep** - Branch contains active, unmerged work that would be lost if deleted

## When to Use This Skill

Invoke this skill when the user asks to:
- Review branches for cleanup: "which branches can I delete?", "review my branches"
- Analyze a specific branch: "can I delete the feature-x branch?", "is this branch safe to delete?"
- Clean up old branches: "help me clean up stale branches"

## How to Use This Skill

### Analyze a Single Branch

```bash
branch-review.sh analyze <branch-name>
```

**Returns:** Detailed analysis including:
- Branch age and last commit info
- Commits unique to the branch
- Commit message matches in main branch
- `git cherry` analysis for rebased equivalents
- Diff summary against main
- Category recommendation (1/2/3) with reasoning

### List All Branches with Categories

```bash
branch-review.sh list
```

**Returns:** Table of all branches (local and remote) with their category and a brief reason

### Show Safe-to-Delete Branches

```bash
branch-review.sh safe
```

**Returns:** List of branches that are definitely safe to delete (category 1)

## Category Definitions

### Category 1: Safe to Delete

A branch is safe to delete when:
- `git branch --merged main` includes the branch
- `git log main..branch` returns no commits (strict subset)
- All commits show `-` prefix in `git cherry -v main branch` (all have equivalents)

### Category 2: Probably Safe to Delete

A branch is probably safe to delete when:
- One or more commit messages from the branch exist in main at the same or later timestamp
- This indicates the work was rebased and merged, making this branch the "old version"
- A rebase would result in mostly empty commits (changes already in main)
- The remaining diff represents incomplete fragments rather than coherent new work

### Category 3: Keep (Not Safe to Delete)

A branch should be kept when:
- Commits are unique with no equivalents in main
- Commit messages don't appear in main's history
- The diff against main represents coherent, valuable work
- Recent activity suggests ongoing development

## Detection Methods

The skill uses these git commands for analysis:

```bash
# Check if branch is merged
git branch --merged main

# Find unique commits on branch
git log main..branch --oneline

# Check for rebased equivalents (- = has equivalent, + = unique)
git cherry -v main branch

# Search for matching commit messages
git log main --grep="commit message" --after="date"

# View unique changes
git diff main...branch --stat
```

## Example Output

```
=== Branch Analysis: feature-login ===

Last commit: abc1234 Add login form (3 weeks ago)

Unique commits (not in main):
  abc1234 Add login form
  def5678 Add authentication service

Commit message search in main:
  "Add login form" -> Found: xyz9999 (2 weeks ago)
  "Add authentication service" -> Found: xyz8888 (2 weeks ago)

git cherry analysis:
  - abc1234 Add login form
  - def5678 Add authentication service

Diff against main: 0 files changed

CATEGORY: 1 (Safe to delete)
REASON: All commits have equivalents in main. Branch was rebased and merged.
```

## Environment Requirements

- Must be run from within a git repository
- Assumes main branch is named `main` or `master` (auto-detected)
- Always analyzes both local and remote branches (runs `git fetch` first)
