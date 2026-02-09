#!/bin/bash

# Branch Review CLI - Analyze branches for safe deletion
# Main entry point for branch-review commands

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect main branch name
detect_main_branch() {
  if git show-ref --verify --quiet refs/heads/main; then
    echo "main"
  elif git show-ref --verify --quiet refs/heads/master; then
    echo "master"
  else
    echo "main"  # fallback
  fi
}

MAIN_BRANCH=$(detect_main_branch)

# Display help
show_help() {
  cat << EOF
Branch Review - Analyze git branches for safe deletion

Usage:
  branch-review analyze <branch>    Analyze a specific branch
  branch-review list                List all branches with categories
  branch-review safe                Show branches safe to delete

Commands:

  analyze <branch>
    Perform detailed analysis of a branch to determine deletion safety.
    Returns category (1=safe, 2=probably safe, 3=keep) with reasoning.

  list
    List all branches (local and remote) with their deletion category.
    Runs git fetch first to ensure remote branches are up to date.

  safe
    Quick list of branches that are definitely safe to delete (category 1).

  spawn <branch1> [branch2] ...
    Open new wezterm tabs with Claude Code sessions for each branch.
    Each tab runs: claude "/wt <branch>"

Categories:
  1 - Safe to delete: Branch is subset of $MAIN_BRANCH or was rebased/merged
  2 - Probably safe: Work appears to have been merged via different commits
  3 - Keep: Contains unique, unmerged work

Examples:
  branch-review analyze feature-x
  branch-review list
  branch-review safe

EOF
}

# Main dispatch
COMMAND="${1:-help}"
case "$COMMAND" in
  analyze)
    shift
    "$SCRIPT_DIR/lib/analyze-branch.sh" "$@"
    ;;
  list)
    shift
    "$SCRIPT_DIR/lib/list-branches.sh" "$@"
    ;;
  safe)
    shift
    "$SCRIPT_DIR/lib/safe-branches.sh" "$@"
    ;;
  spawn)
    shift
    "$SCRIPT_DIR/lib/spawn-sessions.sh" "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Run 'branch-review help' for usage information" >&2
    exit 1
    ;;
esac
