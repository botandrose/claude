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
MERGED_BRANCHES=$(git branch --merged "$MAIN" 2>/dev/null | sed 's/^[* ]*//')

# Function to analyze a single branch and print its category
analyze_branch() {
  local BRANCH="$1"
  local BRANCH_TYPE="$2"  # "local" or "remote"

  # Quick check: is it merged? (local branches only)
  if [ "$BRANCH_TYPE" = "local" ] && echo "$MERGED_BRANCHES" | grep -q "^${BRANCH}$"; then
    UNIQUE_COUNT=$(git log "$MAIN..$BRANCH" --oneline 2>/dev/null | wc -l)
    if [ "$UNIQUE_COUNT" -eq 0 ]; then
      printf "%-55s %-10s %s\n" "$BRANCH" "1-SAFE" "Strict subset of $MAIN"
      return
    fi
  fi

  # Cherry check
  CHERRY_OUTPUT=$(git cherry -v "$MAIN" "$BRANCH" 2>/dev/null || echo "")
  if [ -z "$CHERRY_OUTPUT" ]; then
    printf "%-55s %-10s %s\n" "$BRANCH" "1-SAFE" "No unique commits"
    return
  fi

  EQUIVALENT_COUNT=$(echo "$CHERRY_OUTPUT" | grep -c "^-" || true)
  UNIQUE_COUNT=$(echo "$CHERRY_OUTPUT" | grep -c "^+" || true)
  TOTAL_COUNT=$((EQUIVALENT_COUNT + UNIQUE_COUNT))

  if [ "$UNIQUE_COUNT" -eq 0 ]; then
    printf "%-55s %-10s %s\n" "$BRANCH" "1-SAFE" "All $TOTAL_COUNT commits have equivalents"
    return
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
    printf "%-55s %-10s %s\n" "$BRANCH" "2-MAYBE" "All messages found in $MAIN (rebased?)"
    return
  fi

  if [ "$MESSAGES_FOUND" -gt 0 ]; then
    printf "%-55s %-10s %s\n" "$BRANCH" "2-MAYBE" "$MESSAGES_FOUND/$TOTAL_COUNT messages in $MAIN"
    return
  fi

  if [ "$EQUIVALENT_COUNT" -gt 0 ]; then
    printf "%-55s %-10s %s\n" "$BRANCH" "2-MAYBE" "$EQUIVALENT_COUNT/$TOTAL_COUNT have equivalents"
    return
  fi

  # Check new file coverage - do files introduced by branch exist in main?
  MERGE_BASE=$(git merge-base "$MAIN" "$BRANCH" 2>/dev/null || echo "")
  if [ -n "$MERGE_BASE" ]; then
    NEW_FILES=$(git diff --name-only --diff-filter=A "$MERGE_BASE..$BRANCH" 2>/dev/null)
    NEW_FILES_COUNT=0
    NEW_FILES_IN_MAIN=0

    if [ -n "$NEW_FILES" ]; then
      while IFS= read -r file; do
        [ -z "$file" ] && continue
        NEW_FILES_COUNT=$((NEW_FILES_COUNT + 1))
        if git show "$MAIN":"$file" &>/dev/null; then
          NEW_FILES_IN_MAIN=$((NEW_FILES_IN_MAIN + 1))
        fi
      done <<< "$NEW_FILES"
    fi

    if [ "$NEW_FILES_COUNT" -gt 0 ]; then
      FILE_COVERAGE=$((NEW_FILES_IN_MAIN * 100 / NEW_FILES_COUNT))
      if [ "$FILE_COVERAGE" -ge 50 ]; then
        printf "%-55s %-10s %s\n" "$BRANCH" "2-MAYBE" "$FILE_COVERAGE% new files in $MAIN"
        return
      fi
    fi
  fi

  # Get age for context
  AGE=$(git log "$BRANCH" -1 --format="%ar" 2>/dev/null || echo "unknown")
  printf "%-55s %-10s %s\n" "$BRANCH" "3-KEEP" "$UNIQUE_COUNT unique commits ($AGE)"
}

# Header
echo "=== Local Branches ==="
printf "%-55s %-10s %s\n" "BRANCH" "CATEGORY" "REASON"
printf "%-55s %-10s %s\n" "------" "--------" "------"

# Process local branches
for BRANCH in $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v "^${MAIN}$"); do
  if [ "$BRANCH" = "$MAIN" ]; then
    continue
  fi
  analyze_branch "$BRANCH" "local"
done

# Always process remote branches now
echo ""
echo "=== Remote Branches ==="
printf "%-55s %-10s %s\n" "BRANCH" "CATEGORY" "REASON"
printf "%-55s %-10s %s\n" "------" "--------" "------"

for BRANCH in $(git for-each-ref --format='%(refname:short)' refs/remotes/ | grep -v HEAD | grep -v "/HEAD$" | grep -v "/${MAIN}$" | grep -v "/master$"); do
  analyze_branch "$BRANCH" "remote"
done

echo ""
echo "Notes:"
echo "  - When deleting branches, remove both local AND remote:"
echo "      git branch -d <branch>                  # delete local"
echo "      git push origin --delete <branch>       # delete remote"
echo "  - 2-MAYBE branches need deeper analysis: branch-review analyze <branch>"
