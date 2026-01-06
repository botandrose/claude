#!/bin/bash

# Wrapper script that dispatches to the actual branch-review implementation
# This allows the skill to be invoked from the skill root directory

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SKILL_DIR/scripts/branch-review.sh" "$@"
