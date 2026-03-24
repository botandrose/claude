---
name: wt
description: Create a git worktree for parallel Claude Code development. Pass a branch name and it sets up an isolated worktree with its own test database, then switches to working in that directory.
user-invocable: true
arguments: branch-name --test-env
---

# Worktree Skill

Create a git worktree and switch to it for isolated parallel development.

## Usage

```
/wt <branch-name>
/wt <branch-name> --test-env 3
```

## Arguments

- **branch-name** — Required. The git branch to use. Created automatically if it doesn't exist.
- **--test-env N** — Optional. Explicit TEST_ENV_NUMBER to use. If omitted, auto-calculated from existing worktree count. Use this when spawning multiple worktrees concurrently to avoid collisions.

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
   - Extract the branch name (first argument that doesn't start with `--`)
   - Extract `--test-env N` value if provided
   - If no branch name given, list available branches with `git branch -a` and stop

2. **Derive short directory name** from the branch:
   - Strip prefixes: `feature/`, `fix/`, `bugfix/`, `hotfix/`, `chore/`
   - Example: `feature/foo-bar` → `foo-bar`

3. **Save the main repo path** before changing directories:
   ```bash
   MAIN_REPO=$(git rev-parse --show-toplevel)
   ```

4. **Create the branch if it doesn't exist**:
   ```bash
   git show-ref --verify --quiet refs/heads/<branch-name> || git branch <branch-name>
   ```

5. **Calculate TEST_ENV_NUMBER** (skip if `--test-env` was provided):
   ```bash
   NUM=$(($(ls -d tmp/worktrees/*/ 2>/dev/null | wc -l) + 1))
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

9. **Save environment variables** for reference:
   ```bash
   mkdir -p tmp
   ```
   ```bash
   cat > tmp/.test_env << 'EOF'
   export TEST_ENV_NUMBER=<NUM>
   export BUNDLE_GEMFILE=<MAIN_REPO>/Gemfile
   EOF
   ```

10. **Run bootstrap** to set up the database:
    ```bash
    BUNDLE_GEMFILE=$MAIN_REPO/Gemfile TEST_ENV_NUMBER=$NUM bin/rake bootstrap
    ```

11. **Stay in the worktree directory** - do NOT cd back

12. **Report success**:
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

2. **Read `tmp/.test_env`** to get the TEST_ENV_NUMBER:
   ```bash
   cat tmp/.test_env
   ```

3. **Go back to main repo**:
   ```bash
   cd <main-repo-path>   # e.g., /home/micah/work/axis
   ```

4. **Remove the worktree** (should succeed without --force if changes are committed):
   ```bash
   git worktree remove tmp/worktrees/<name>
   ```
   - If this fails due to uncommitted changes, **STOP and ask the user** - do NOT use --force

5. **Checkout the branch** if main repo is on master:
   ```bash
   if [ "$(git branch --show-current)" = "master" ]; then
     git checkout <branch-name>
   fi
   ```

6. **Report done** - user is now on the branch and ready to merge/deploy

## Listing Worktrees

```bash
git worktree list
```
