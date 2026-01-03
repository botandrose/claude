#!/bin/bash

# List all branches with their deletion category

set -e

INCLUDE_REMOTE=false
if [ "$1" = "--remote" ]; then
  INCLUDE_REMOTE=true
fi

# Detect main branch
if git show-ref --verify --quiet refs/heads/main; then
  MAIN="main"
elif git show-ref --verify --quiet refs/heads/master; then
  MAIN="master"
else
  MAIN="main"
fi

# Get merged branches for quick category 1 detection
MERGED_BRANCHES=$(git branch --merged "$MAIN" | sed 's/^[* ]*//')

# Header
printf "%-50s %-10s %s\n" "BRANCH" "CATEGORY" "REASON"
printf "%-50s %-10s %s\n" "------" "--------" "------"

# Note: This is a quick scan. For accurate 2-MAYBE analysis, use: branch-review analyze <branch>

# Process local branches
for BRANCH in $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v "^${MAIN}$"); do
  # Skip the main branch
  if [ "$BRANCH" = "$MAIN" ]; then
    continue
  fi

  # Quick check: is it merged?
  if echo "$MERGED_BRANCHES" | grep -q "^${BRANCH}$"; then
    # Check if it has any unique commits
    UNIQUE_COUNT=$(git log "$MAIN..$BRANCH" --oneline 2>/dev/null | wc -l)
    if [ "$UNIQUE_COUNT" -eq 0 ]; then
      printf "%-50s %-10s %s\n" "$BRANCH" "1-SAFE" "Strict subset of $MAIN"
      continue
    fi
  fi

  # Cherry check
  CHERRY_OUTPUT=$(git cherry -v "$MAIN" "$BRANCH" 2>/dev/null || echo "")
  if [ -z "$CHERRY_OUTPUT" ]; then
    printf "%-50s %-10s %s\n" "$BRANCH" "1-SAFE" "No unique commits"
    continue
  fi

  EQUIVALENT_COUNT=$(echo "$CHERRY_OUTPUT" | grep -c "^-" || true)
  UNIQUE_COUNT=$(echo "$CHERRY_OUTPUT" | grep -c "^+" || true)
  TOTAL_COUNT=$((EQUIVALENT_COUNT + UNIQUE_COUNT))

  if [ "$UNIQUE_COUNT" -eq 0 ]; then
    printf "%-50s %-10s %s\n" "$BRANCH" "1-SAFE" "All $TOTAL_COUNT commits have equivalents"
    continue
  fi

  # Check for message matches
  MESSAGES_FOUND=0
  while IFS= read -r line; do
    COMMIT_MSG=$(echo "$line" | sed 's/^[+-] [a-f0-9]* //')
    if git log "$MAIN" --oneline --grep="$COMMIT_MSG" -1 &>/dev/null; then
      FOUND=$(git log "$MAIN" --oneline --grep="$COMMIT_MSG" -1 2>/dev/null || true)
      if [ -n "$FOUND" ]; then
        MESSAGES_FOUND=$((MESSAGES_FOUND + 1))
      fi
    fi
  done <<< "$CHERRY_OUTPUT"

  if [ "$MESSAGES_FOUND" -eq "$TOTAL_COUNT" ] && [ "$TOTAL_COUNT" -gt 0 ]; then
    printf "%-50s %-10s %s\n" "$BRANCH" "2-MAYBE" "All messages found in $MAIN (rebased?)"
    continue
  fi

  if [ "$MESSAGES_FOUND" -gt 0 ]; then
    printf "%-50s %-10s %s\n" "$BRANCH" "2-MAYBE" "$MESSAGES_FOUND/$TOTAL_COUNT messages in $MAIN"
    continue
  fi

  if [ "$EQUIVALENT_COUNT" -gt 0 ]; then
    printf "%-50s %-10s %s\n" "$BRANCH" "2-MAYBE" "$EQUIVALENT_COUNT/$TOTAL_COUNT have equivalents"
    continue
  fi

  # Get age for context
  AGE=$(git log "$BRANCH" -1 --format="%ar" 2>/dev/null || echo "unknown")
  printf "%-50s %-10s %s\n" "$BRANCH" "3-KEEP" "$UNIQUE_COUNT unique commits ($AGE)"
done

echo ""
echo "Note: 2-MAYBE branches need deeper analysis. Run: branch-review analyze <branch>"

# Process remote branches if requested
if [ "$INCLUDE_REMOTE" = true ]; then
  echo ""
  echo "=== Remote Branches ==="
  printf "%-50s %-10s %s\n" "BRANCH" "CATEGORY" "REASON"
  printf "%-50s %-10s %s\n" "------" "--------" "------"

  for BRANCH in $(git for-each-ref --format='%(refname:short)' refs/remotes/ | grep -v HEAD | grep -v "/${MAIN}$"); do
    # Quick unique commit check
    UNIQUE_COUNT=$(git log "$MAIN..$BRANCH" --oneline 2>/dev/null | wc -l || echo "0")
    if [ "$UNIQUE_COUNT" -eq 0 ]; then
      printf "%-50s %-10s %s\n" "$BRANCH" "1-SAFE" "Strict subset of $MAIN"
    else
      AGE=$(git log "$BRANCH" -1 --format="%ar" 2>/dev/null || echo "unknown")
      printf "%-50s %-10s %s\n" "$BRANCH" "?-CHECK" "$UNIQUE_COUNT unique commits ($AGE)"
    fi
  done
fi
