#!/bin/bash

# List branches that are definitely safe to delete (category 1)

set -e

# Detect main branch
if git show-ref --verify --quiet refs/heads/main; then
  MAIN="main"
elif git show-ref --verify --quiet refs/heads/master; then
  MAIN="master"
else
  MAIN="main"
fi

echo "Branches safe to delete (category 1):"
echo ""

SAFE_COUNT=0

for BRANCH in $(git branch --merged "$MAIN" | sed 's/^[* ]*//'); do
  # Skip main branch
  if [ "$BRANCH" = "$MAIN" ]; then
    continue
  fi

  # Verify no unique commits
  UNIQUE_COUNT=$(git log "$MAIN..$BRANCH" --oneline 2>/dev/null | wc -l)
  if [ "$UNIQUE_COUNT" -eq 0 ]; then
    echo "  $BRANCH"
    SAFE_COUNT=$((SAFE_COUNT + 1))
  fi
done

# Also check branches where all commits have cherry equivalents
for BRANCH in $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v "^${MAIN}$"); do
  # Skip if already in merged list
  if git branch --merged "$MAIN" | sed 's/^[* ]*//' | grep -q "^${BRANCH}$"; then
    continue
  fi

  # Cherry check
  CHERRY_OUTPUT=$(git cherry -v "$MAIN" "$BRANCH" 2>/dev/null || echo "")
  if [ -z "$CHERRY_OUTPUT" ]; then
    continue
  fi

  UNIQUE_COUNT=$(echo "$CHERRY_OUTPUT" | grep -c "^+" || true)
  if [ "$UNIQUE_COUNT" -eq 0 ]; then
    echo "  $BRANCH (all commits rebased)"
    SAFE_COUNT=$((SAFE_COUNT + 1))
  fi
done

echo ""
if [ "$SAFE_COUNT" -eq 0 ]; then
  echo "No branches are definitely safe to delete."
else
  echo "Total: $SAFE_COUNT branch(es) safe to delete"
  echo ""
  echo "To delete these branches:"
  echo "  git branch -d <branch-name>"
fi
