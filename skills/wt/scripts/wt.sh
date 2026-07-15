#!/bin/bash

# Worktree CLI - create and manage git worktrees with TEST_ENV_NUMBER encoding
#
# Branch name convention: <TEST_ENV_NUMBER>-<rest>
# TEST_ENV_NUMBER is always 1-2 digits. 3+ digit prefixes are ticket IDs.

set -e

# Use --git-common-dir to always resolve to the main repo, even from a worktree
MAIN_REPO=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")

# .claude/worktrees is the only root Claude Code enters without a permission-root
# relocation prompt. Legacy tmp/worktrees stays readable until existing ones drain.
WORKTREES_ROOT="$MAIN_REPO/.claude/worktrees"
LEGACY_WORKTREES_ROOT="$MAIN_REPO/tmp/worktrees"

in_worktrees_root() {
  case "$1" in
    "$WORKTREES_ROOT"/*|"$LEGACY_WORKTREES_ROOT"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Extract TEST_ENV_NUMBER from a branch name (1-2 digit prefix before first dash)
parse_env_number() {
  echo "$1" | grep -oP '^\d{1,2}(?=-)' || true
}

# List TEST_ENV_NUMBERs currently in use by worktrees
used_env_numbers() {
  git worktree list --porcelain \
    | grep '^branch' \
    | sed -E 's#^branch refs/heads/##' \
    | { grep -oP '^\d{1,2}(?=-)' || true; } \
    | sort -n
}

# Find the lowest available TEST_ENV_NUMBER starting at 2
next_env_number() {
  local used
  used=$(used_env_numbers)
  local num=2
  while echo "$used" | grep -qx "$num"; do
    num=$((num + 1))
  done
  echo "$num"
}

# Derive a slash-free directory name from a branch name. Strips a known type
# segment (feature/, fix/, etc.) even when it follows the TEST_ENV_NUMBER
# prefix, then flattens any remaining slashes so worktrees never nest.
short_name() {
  echo "$1" \
    | sed -E 's#^([0-9]{1,2}-)?(feature|fix|bugfix|hotfix|chore)/#\1#' \
    | tr '/' '-'
}

# Remove the worktree's parent dir if a slashed branch nested it and it is now
# empty. Never touches a worktrees root itself.
remove_empty_worktree_parent() {
  local parent
  parent=$(dirname "$1")
  if [ "$parent" != "$WORKTREES_ROOT" ] && [ "$parent" != "$LEGACY_WORKTREES_ROOT" ]; then
    rmdir "$parent" 2>/dev/null || true
  fi
}

cmd_create() {
  local branch="$1"
  if [ -z "$branch" ]; then
    echo "Usage: wt create <branch-name>" >&2
    exit 1
  fi

  local requested="$branch"

  local num
  num=$(parse_env_number "$branch")

  if [ -z "$num" ]; then
    num=$(next_env_number)
    branch="${num}-${branch}"
  fi

  local dir
  dir=$(short_name "$branch")

  # If a remote branch matches the requested name (e.g. a collaborator's WIP
  # branch named in the ticket), base the worktree on it instead of HEAD so we
  # build on their work rather than starting fresh from master.
  local base=""
  if git ls-remote --exit-code --heads origin "$requested" >/dev/null 2>&1; then
    git fetch --quiet origin "$requested"
    base="FETCH_HEAD"
    echo "Basing on origin/$requested (matched remote branch)" >&2
  fi

  git show-ref --verify --quiet "refs/heads/$branch" || git branch "$branch" "${base:-HEAD}"
  mkdir -p "$WORKTREES_ROOT"
  git worktree add "$WORKTREES_ROOT/$dir" "$branch"

  echo "WORKTREE_DIR=$WORKTREES_ROOT/$dir"
  echo "BRANCH=$branch"
  echo "TEST_ENV_NUMBER=$num"
}

cmd_env() {
  local branch="$1"
  if [ -z "$branch" ]; then
    branch=$(git branch --show-current)
  fi
  local num
  num=$(parse_env_number "$branch")
  if [ -z "$num" ]; then
    echo "No TEST_ENV_NUMBER found in branch name: $branch" >&2
    exit 1
  fi
  echo "$num"
}

cmd_list() {
  echo "WORKTREE  BRANCH  TEST_ENV_NUMBER"
  git worktree list --porcelain | awk '
    /^worktree / { wt = $2 }
    /^branch /   {
      branch = $2
      sub(/^refs\/heads\//, "", branch)
      match(branch, /^[0-9]{1,2}-/)
      if (RSTART) {
        num = substr(branch, RSTART, RLENGTH - 1)
      } else {
        num = "-"
      }
      print wt "  " branch "  " num
    }
  '
}

cmd_finish() {
  local worktree_dir
  worktree_dir=$(pwd)

  # Verify we're in a worktree
  if ! in_worktrees_root "$worktree_dir"; then
    echo "Error: not inside a worktree (expected path under $WORKTREES_ROOT)" >&2
    exit 1
  fi

  # Abort if there are uncommitted changes
  if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "Error: worktree has uncommitted changes. Commit or stash them first." >&2
    git status --short >&2
    exit 1
  fi

  local branch
  branch=$(git branch --show-current)

  # Get main repo HEAD branch
  local main_branch
  main_branch=$(git -C "$MAIN_REPO" branch --show-current)

  # Rebase onto main repo's HEAD
  git rebase "$main_branch"

  # Go back to main repo and remove worktree by its absolute path (so slashed
  # branch names that nest the worktree dir are handled correctly)
  cd "$MAIN_REPO"
  git worktree remove "$worktree_dir"
  remove_empty_worktree_parent "$worktree_dir"

  if [ "$main_branch" = "master" ] || [ "$main_branch" = "main" ]; then
    # Main repo is on master/main — just checkout the branch
    git checkout "$branch"
    echo "Checked out $branch (rebased onto $main_branch)"
  else
    # Main repo is on another branch — merge and delete
    git merge "$branch"
    git branch -d "$branch"
    echo "Merged $branch into $main_branch and deleted $branch"
  fi
  echo "MAIN_REPO=$MAIN_REPO"
}

cmd_abandon() {
  local worktree_dir
  worktree_dir=$(pwd)

  # Verify we're in a worktree
  if ! in_worktrees_root "$worktree_dir"; then
    echo "Error: not inside a worktree (expected path under $WORKTREES_ROOT)" >&2
    exit 1
  fi

  local branch
  branch=$(git branch --show-current)

  # Commit any uncommitted changes so worktree removal succeeds
  if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    git add -A
    git commit -m "WIP: abandoning worktree"
  fi

  # Go back to main repo and remove worktree by its absolute path (so slashed
  # branch names that nest the worktree dir are handled correctly)
  cd "$MAIN_REPO"
  git worktree remove "$worktree_dir"
  remove_empty_worktree_parent "$worktree_dir"

  # Delete the branch locally
  git branch -D "$branch"

  # Delete remote branch if it exists
  if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    git push origin --delete "$branch"
    echo "Abandoned $branch (deleted local and remote)"
  else
    echo "Abandoned $branch (deleted local, no remote branch found)"
  fi
  echo "MAIN_REPO=$MAIN_REPO"
}

case "${1:-}" in
  create)  cmd_create "$2" ;;
  finish)   cmd_finish ;;
  abandon) cmd_abandon ;;
  env)     cmd_env "$2" ;;
  list)    cmd_list ;;
  *)
    echo "Usage: wt <command>" >&2
    echo "Commands:" >&2
    echo "  create <branch>   Create worktree (auto-assigns TEST_ENV_NUMBER if missing)" >&2
    echo "  finish            Finish current worktree (rebase, remove, merge/checkout)" >&2
    echo "  abandon           Abandon current worktree (commit, remove, delete branch)" >&2
    echo "  env [branch]      Print TEST_ENV_NUMBER from branch name (default: current)" >&2
    echo "  list              List worktrees with TEST_ENV_NUMBERs" >&2
    exit 1
    ;;
esac
