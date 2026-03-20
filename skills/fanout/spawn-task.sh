#!/bin/bash
REPO_ROOT="$1"
BRANCH="$2"
PROMPT_FILE="$3"
PROMPT=$(<"$PROMPT_FILE")
rm -f "$PROMPT_FILE"
cd "$REPO_ROOT"
unset CLAUDECODE
claude "$PROMPT"
exec bash
