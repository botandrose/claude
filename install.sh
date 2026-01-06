#!/bin/bash
# Install skills and hooks into ~/.claude/
# Run this after adding new skills to the repo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Installing from $SCRIPT_DIR"

# Ensure ~/.claude/skills exists
mkdir -p "$CLAUDE_DIR/skills"

# Symlink hooks directory
if [[ -L "$CLAUDE_DIR/hooks" ]]; then
    rm "$CLAUDE_DIR/hooks"
elif [[ -d "$CLAUDE_DIR/hooks" ]]; then
    echo "Error: $CLAUDE_DIR/hooks is a directory, not a symlink. Please remove it first."
    exit 1
fi
ln -s "$SCRIPT_DIR/hooks" "$CLAUDE_DIR/hooks"
echo "Linked: ~/.claude/hooks -> $SCRIPT_DIR/hooks"

# Symlink each skill
for skill_dir in "$SCRIPT_DIR/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill_name=$(basename "$skill_dir")
    target="$CLAUDE_DIR/skills/$skill_name"

    if [[ -L "$target" ]]; then
        rm "$target"
    elif [[ -e "$target" ]]; then
        echo "Warning: $target exists and is not a symlink, skipping"
        continue
    fi

    ln -s "$skill_dir" "$target"
    echo "Linked: ~/.claude/skills/$skill_name -> $skill_dir"
done

# Update settings.json to point to the new dispatcher
SETTINGS="$CLAUDE_DIR/settings.json"
if [[ -f "$SETTINGS" ]]; then
    # Check if still pointing to old dispatcher
    if grep -q "hook-dispatcher.sh" "$SETTINGS"; then
        sed -i 's|/home/micah/.claude/hook-dispatcher.sh|/home/micah/.claude/hooks/dispatcher.sh|g' "$SETTINGS"
        echo "Updated settings.json to use new dispatcher"
    fi
fi

echo ""
echo "Done! You may need to restart Claude Code for hook changes to take effect."
