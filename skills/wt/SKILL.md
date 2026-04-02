---
name: wt
description: Create a git worktree for parallel Claude Code development. Pass a branch name and it sets up an isolated worktree with its own test database, then switches to working in that directory.
user-invocable: true
arguments: branch-name
---

# Worktree Skill

Create a git worktree and switch to it for isolated parallel development.

## Branch Name Convention

Branch names MUST be prefixed with the TEST_ENV_NUMBER:

```
<TEST_ENV_NUMBER>-<rest-of-branch-name>
```

Examples:
- `11-472852-my-fancy-feature`
- `3-fix-login-bug`
- `7-123456-add-user-search`

The first segment before the first `-` is the TEST_ENV_NUMBER, which is always 1-2 digits (under 100). A 3+ digit leading number would be a ticket ID, not a TEST_ENV_NUMBER. This eliminates the need for a separate registry — the number is encoded directly in the branch name.

## Usage

```
/wt <branch-name>
```

If the branch name already starts with a number prefix, use it as-is. If not, the skill will auto-assign the next available TEST_ENV_NUMBER and prepend it.

## What Happens

1. Creates the git branch if it doesn't exist
2. Creates worktree at `tmp/worktrees/<short-name>`
3. Sets `BUNDLE_GEMFILE` to reuse main repo's gems (no bundle install needed)
4. Runs `bin/rake bootstrap` to set up database
5. Switches Claude Code's working directory to the worktree
6. All further work happens in the worktree until you switch out

**IMPORTANT: Run each step as a separate Bash command. Do NOT chain commands with `&&` or `;`.**

## Steps to Execute

1. **Parse arguments** from `$ARGUMENTS`
   - Extract the branch name (first argument)
   - If no branch name given, list available branches with `git branch -a` and stop

2. **Determine TEST_ENV_NUMBER from the branch name**:
   - If the branch name matches `^[0-9]{1,2}-` (1-2 digit prefix), extract it as NUM
     ```bash
     NUM=$(echo "<branch-name>" | grep -oP '^\d{1,2}(?=-)')
     ```
   - If the branch name does NOT have a 1-2 digit prefix (including 3+ digit prefixes like ticket IDs), auto-assign the lowest available slot starting at 2:
     ```bash
     USED=$(git worktree list --porcelain | grep '^branch' | grep -oP '/(\d{1,2})-' | grep -oP '\d+' | sort -n)
     NUM=2; while echo "$USED" | grep -qx "$NUM"; do NUM=$((NUM + 1)); done
     ```
     Then prepend it to the branch name: `<NUM>-<branch-name>`

3. **Derive short directory name** from the branch:
   - Strip prefixes: `feature/`, `fix/`, `bugfix/`, `hotfix/`, `chore/`
   - Example: `feature/7-foo-bar` → `7-foo-bar`

4. **Save the main repo path** before changing directories:
   ```bash
   MAIN_REPO=$(git rev-parse --show-toplevel)
   ```

5. **Create the branch if it doesn't exist**:
   ```bash
   git show-ref --verify --quiet refs/heads/<branch-name> || git branch <branch-name>
   ```

6. **Create the worktree**:
   ```bash
   mkdir -p tmp/worktrees
   ```
   ```bash
   git worktree add tmp/worktrees/<short-name> <branch-name>
   ```

7. **Change to worktree directory**:
   ```bash
   cd tmp/worktrees/<short-name>
   ```

8. **Copy gitignored config files** (use `cat` not `cp`):
   ```bash
   cat $MAIN_REPO/config/master.key > config/master.key
   ```
   ```bash
   cat $MAIN_REPO/config/database.yml > config/database.yml
   ```

9. **Run bootstrap** to set up the database:
    ```bash
    BUNDLE_GEMFILE=$MAIN_REPO/Gemfile TEST_ENV_NUMBER=$NUM bin/rake bootstrap
    ```

10. **Stay in the worktree directory** - do NOT cd back

11. **Report success**:
    ```
    Now working in: tmp/worktrees/<short-name>
    Branch: <branch-name>
    TEST_ENV_NUMBER: <NUM>

    For all commands, use: BUNDLE_GEMFILE=<main-repo>/Gemfile TEST_ENV_NUMBER=<NUM>
    ```

## Important

- After setup, remain in the worktree directory
- For ALL subsequent commands in this session, prefix with:
  - `BUNDLE_GEMFILE=<main-repo>/Gemfile` - reuse gems from main repo
  - `TEST_ENV_NUMBER=<NUM>` - use isolated test database

## Closing a Worktree

When the user says they're done with a worktree and want to merge/deploy:

1. **CRITICAL: Check for uncommitted changes first**:
   ```bash
   git status
   ```
   - If there are uncommitted changes, **ASK THE USER** if they want to commit them
   - **NEVER force-remove a worktree with uncommitted changes** - this destroys work!
   - If the user wants to commit, create a commit before proceeding

2. **Go back to main repo**:
   ```bash
   cd <main-repo-path>   # e.g., /home/micah/work/axis
   ```

3. **Remove the worktree** (should succeed without --force if changes are committed):
   ```bash
   git worktree remove tmp/worktrees/<name>
   ```
   - If this fails due to uncommitted changes, **STOP and ask the user** - do NOT use --force

4. **Checkout the branch** if main repo is on master:
   ```bash
   if [ "$(git branch --show-current)" = "master" ]; then
     git checkout <branch-name>
   fi
   ```

5. **Report done** - user is now on the branch and ready to merge/deploy

## Listing Worktrees

```bash
git worktree list
```
