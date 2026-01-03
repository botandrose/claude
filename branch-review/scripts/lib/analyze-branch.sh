#!/bin/bash

# Analyze a single branch for deletion safety

set -e

BRANCH="$1"

if [ -z "$BRANCH" ]; then
  echo "Usage: branch-review analyze <branch>" >&2
  exit 1
fi

# Verify branch exists
if ! git show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
  # Try as remote branch
  if ! git show-ref --verify --quiet "refs/remotes/$BRANCH" 2>/dev/null; then
    echo "Error: Branch '$BRANCH' not found" >&2
    exit 1
  fi
fi

# Detect main branch
if git show-ref --verify --quiet refs/heads/main; then
  MAIN="main"
elif git show-ref --verify --quiet refs/heads/master; then
  MAIN="master"
else
  MAIN="main"
fi

echo "=== Branch Analysis: $BRANCH ==="
echo ""

# Basic info
echo "--- Basic Info ---"
git log "$BRANCH" -1 --format="Last commit: %h %s (%ar by %an)"
echo ""

# Check if strictly merged
MERGED_BRANCHES=$(git branch --merged "$MAIN" | sed 's/^[* ]*//')
IS_MERGED=false
if echo "$MERGED_BRANCHES" | grep -q "^${BRANCH}$"; then
  IS_MERGED=true
fi

# Unique commits
echo "--- Commits Unique to Branch ---"
UNIQUE_COMMITS=$(git log "$MAIN..$BRANCH" --oneline)
if [ -z "$UNIQUE_COMMITS" ]; then
  echo "(none - branch is strict subset of $MAIN)"
  UNIQUE_COUNT=0
else
  echo "$UNIQUE_COMMITS"
  UNIQUE_COUNT=$(echo "$UNIQUE_COMMITS" | wc -l)
fi
echo ""

# If no unique commits, it's category 1
if [ "$UNIQUE_COUNT" -eq 0 ]; then
  echo "=== VERDICT ==="
  echo "Category: 1 (SAFE TO DELETE)"
  echo "Reason: Branch has no unique commits - strict subset of $MAIN"
  exit 0
fi

# Cherry analysis
echo "--- Cherry Analysis (- = has equivalent in $MAIN, + = unique) ---"
CHERRY_OUTPUT=$(git cherry -v "$MAIN" "$BRANCH")
echo "$CHERRY_OUTPUT"
echo ""

# Count equivalents vs unique
EQUIVALENT_COUNT=$(echo "$CHERRY_OUTPUT" | grep -c "^-" || true)
UNIQUE_CHERRY_COUNT=$(echo "$CHERRY_OUTPUT" | grep -c "^+" || true)

# If all commits have equivalents
if [ "$UNIQUE_CHERRY_COUNT" -eq 0 ]; then
  echo "=== VERDICT ==="
  echo "Category: 1 (SAFE TO DELETE)"
  echo "Reason: All commits have equivalent patches in $MAIN (likely rebased and merged)"
  exit 0
fi

# Search for commit messages in main (only for commits that cherry says are unique)
echo "--- Commit Message Search in $MAIN ---"
MESSAGES_FOUND=0
MESSAGES_TOTAL=0
TIMESTAMPS_MATCH=0
while IFS= read -r line; do
  # Only search for commits marked as unique (+) by cherry
  if ! echo "$line" | grep -q "^+"; then
    continue
  fi

  BRANCH_HASH=$(echo "$line" | sed 's/^+ \([a-f0-9]*\) .*/\1/')
  COMMIT_MSG=$(echo "$line" | sed 's/^+ [a-f0-9]* //')
  MESSAGES_TOTAL=$((MESSAGES_TOTAL + 1))

  # Get branch commit timestamp
  BRANCH_DATE=$(git log -1 --format="%ci" "$BRANCH_HASH" 2>/dev/null | cut -d' ' -f1)

  # Search for this message in main
  FOUND=$(git log "$MAIN" --oneline --grep="$COMMIT_MSG" -1 2>/dev/null || true)
  if [ -n "$FOUND" ]; then
    MAIN_HASH=$(echo "$FOUND" | cut -d' ' -f1)
    MAIN_DATE=$(git log -1 --format="%ci" "$MAIN_HASH" 2>/dev/null | cut -d' ' -f1)

    # Check if main commit is same date or later (indicates rebase)
    # Use string comparison - dates in YYYY-MM-DD format sort correctly
    if [ "$MAIN_DATE" \> "$BRANCH_DATE" ] || [ "$MAIN_DATE" = "$BRANCH_DATE" ]; then
      echo "\"$COMMIT_MSG\""
      echo "  -> FOUND in $MAIN: $FOUND (date: $MAIN_DATE >= $BRANCH_DATE)"
      MESSAGES_FOUND=$((MESSAGES_FOUND + 1))
      TIMESTAMPS_MATCH=$((TIMESTAMPS_MATCH + 1))
    else
      echo "\"$COMMIT_MSG\""
      echo "  -> Found but OLDER: $FOUND (date: $MAIN_DATE < $BRANCH_DATE)"
      echo "  -> This is likely a DIFFERENT commit with same message"
    fi
  else
    echo "\"$COMMIT_MSG\" -> not found in $MAIN"
  fi
done <<< "$CHERRY_OUTPUT"
echo ""

# Diff summary
echo "--- Diff Against $MAIN ---"
DIFF_STAT=$(git diff "$MAIN...$BRANCH" --stat 2>/dev/null | tail -1)
if [ -z "$DIFF_STAT" ] || echo "$DIFF_STAT" | grep -q "0 files changed"; then
  echo "(no differences)"
  NO_DIFF=true
else
  git diff "$MAIN...$BRANCH" --stat | head -20
  NO_DIFF=false
fi
echo ""

# Make verdict
echo "=== VERDICT ==="

# Category 1: No diff or all equivalents
if [ "$NO_DIFF" = true ]; then
  echo "Category: 1 (SAFE TO DELETE)"
  echo "Reason: No actual differences from $MAIN"
  exit 0
fi

# Category 2: Messages found in main with matching/later timestamps (strong rebase signal)
if [ "$TIMESTAMPS_MATCH" -gt 0 ] && [ "$TIMESTAMPS_MATCH" -eq "$MESSAGES_TOTAL" ]; then
  echo "Category: 2 (PROBABLY SAFE TO DELETE)"
  echo "Reason: All $TIMESTAMPS_MATCH commit messages found in $MAIN with same/later dates"
  echo "        This strongly suggests the work was rebased and merged."
  echo "Review: Check if the diff represents incomplete fragments or valuable unique work"
  exit 0
fi

if [ "$TIMESTAMPS_MATCH" -gt 0 ]; then
  echo "Category: 2 (PROBABLY SAFE TO DELETE)"
  echo "Reason: $TIMESTAMPS_MATCH of $MESSAGES_TOTAL commit messages found in $MAIN with matching dates"
  echo "Review: Some work appears rebased/merged; check remaining diff for value"
  exit 0
fi

if [ "$EQUIVALENT_COUNT" -gt 0 ]; then
  echo "Category: 2 (PROBABLY SAFE TO DELETE)"
  echo "Reason: $EQUIVALENT_COUNT of $UNIQUE_COUNT commits have equivalent patches in $MAIN"
  echo "Review: Partial overlap detected; check remaining diff for value"
  exit 0
fi

# Category 3: Unique work
echo "Category: 3 (KEEP - NOT SAFE TO DELETE)"
echo "Reason: Contains $UNIQUE_CHERRY_COUNT unique commits with no equivalents in $MAIN"
echo "The branch appears to contain unmerged work that would be lost if deleted"
