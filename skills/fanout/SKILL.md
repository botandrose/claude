---
name: fanout
description: Spawn parallel Claude Code instances in worktrees, one per markdown task file in a directory.
user-invocable: true
allowed-tools: Bash(*), Read, Glob
arguments: directory
---

# Fan Out Skill

Spawn parallel Claude Code instances, each in its own worktree, from a directory of markdown task files.

## Usage

```
/fanout path/to/tasks/
/fanout path/to/tasks/ "run the tests after each change"
```

## Steps to Execute

1. **Parse arguments** from `$ARGUMENTS`:
   - First argument: directory path (required)
   - Everything after: additional instructions to append to each task (optional)
   - If no directory provided, print usage and stop

2. **Find task files** using Glob for `*.md` in the directory

3. **For each markdown file**:

   a. **Derive branch name** from filename:
      - Strip the `.md` extension
      - Example: `add-authentication.md` → `add-authentication`

   b. **Read the file contents**

   c. **Write a temp prompt file** using Bash (NOT the Write tool — the Write tool doesn't do shell expansion):
      ```bash
      cat > /tmp/fanout_<branch>.md << 'PROMPT_EOF'
      Set up a worktree for this task by running: /wt <branch>

      Once the worktree is ready, implement the following task:

      <file contents>

      <additional instructions, if provided>

      Remember: ALWAYS pipe cucumber output through `tee` to a temp file. Never discard output with `tail` or `head` — capture everything so you can grep it later without re-running slow tests.
      PROMPT_EOF
      ```

   d. **Spawn a wezterm tab**:
      ```bash
      chmod +x ${CLAUDE_SKILL_DIR}/spawn-task.sh
      wezterm cli spawn --cwd "$REPO_ROOT" -- ${CLAUDE_SKILL_DIR}/spawn-task.sh "$REPO_ROOT" "<branch>" "/tmp/fanout_<branch>.md"
      ```
      - Sleep 0.5s between spawns to avoid overwhelming wezterm

4. **Report summary**:
   ```
   Spawned N tasks:
     → <branch-1> (filename1.md)
     → <branch-2> (filename2.md)
   ```

## Important

- Each spawned Claude instance stays interactive after completing the task
- The prompt does NOT start with `/wt` directly — it gives Claude full context so `/wt` is invoked as a tool, not parsed as the only skill invocation
- Use Bash (not the Write tool) to create temp prompt files, since Write doesn't do shell expansion
