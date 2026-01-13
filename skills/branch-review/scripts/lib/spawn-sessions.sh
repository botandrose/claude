#!/bin/bash

# Spawn Claude Code sessions in new wezterm tabs for each branch
# Each tab runs: claude "/wt <branch>"

set -e

# Get the git repo root directory
get_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# Spawn a new wezterm tab with claude /wt <branch>
spawn_tab() {
  local branch="$1"
  local repo_root="$2"
  wezterm cli spawn --cwd "$repo_root" -- bash -c "claude '/wt $branch'; exec bash"
}

# Main
main() {
  if [[ "$1" == "--help" || "$1" == "-h" || $# -eq 0 ]]; then
    echo "Usage: branch-review spawn <branch1> [branch2] ..."
    echo ""
    echo "Opens new wezterm tabs with Claude Code sessions for each branch."
    echo "Each tab runs: claude \"/wt <branch>\""
    echo ""
    echo "Example:"
    echo "  branch-review spawn feature-a feature-b feature-c"
    exit 0
  fi

  local branches=("$@")

  local repo_root
  repo_root=$(get_repo_root)
  if [[ -z "$repo_root" ]]; then
    echo "Error: Not in a git repository" >&2
    exit 1
  fi

  echo "Spawning ${#branches[@]} Claude Code sessions..."

  for branch in "${branches[@]}"; do
    echo "  → $branch"
    spawn_tab "$branch" "$repo_root"
    sleep 0.3
  done

  echo "Done!"
}

main "$@"
