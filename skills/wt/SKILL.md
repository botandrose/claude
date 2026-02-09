---
name: wt
description: Create a git worktree for parallel Claude Code development. Pass a branch name and it sets up an isolated worktree with its own test database, then switches to working in that directory.
user-invocable: true
arguments: branch-name
---

# Worktree Skill

Create a git worktree and switch to it for isolated parallel development.

## Usage

```
/wt <branch-name>
```

## What Happens

1. Creates worktree at `tmp/worktrees/<short-name>`
2. Sets `BUNDLE_GEMFILE` to reuse main repo's gems (no bundle install needed)
3. Runs `bin/setup` to bootstrap database
4. Switches Claude Code's working directory to the worktree
5. All further work happens in the worktree until you switch out

## Steps to Execute

1. **Parse the branch name** from `$ARGUMENTS`
   - If empty, list available branches with `git branch -a` and stop

2. **Derive short directory name** from the branch:
   - Strip prefixes: `feature/`, `fix/`, `bugfix/`, `hotfix/`
   - Example: `feature/foo-bar` → `foo-bar`

3. **Save the main repo path** before changing directories:
   ```bash
   MAIN_REPO=$(git rev-parse --show-toplevel)
   ```

4. **Calculate TEST_ENV_NUMBER**:
   ```bash
   NUM=$(($(ls -d tmp/worktrees/*/ 2>/dev/null | wc -l) + 1))
   ```

5. **Create the worktree**:
   ```bash
   mkdir -p tmp/worktrees
   git worktree add tmp/worktrees/<short-name> <branch-name>
   ```

6. **Change to worktree directory**:
   ```bash
   cd tmp/worktrees/<short-name>
   ```

7. **Copy gitignored config files**:
   ```bash
   cp $MAIN_REPO/config/master.key config/master.key
   cp $MAIN_REPO/config/database.yml config/database.yml
   ```

8. **Save environment variables** for reference:
   ```bash
   mkdir -p tmp
   cat > tmp/.test_env << 'EOF'
   export TEST_ENV_NUMBER=<NUM>
   export BUNDLE_GEMFILE=<MAIN_REPO>/Gemfile
   EOF
   ```

9. **Run bin/setup** to bootstrap:
   ```bash
   BUNDLE_GEMFILE=$MAIN_REPO/Gemfile TEST_ENV_NUMBER=$NUM bin/setup
   ```

9. **Stay in the worktree directory** - do NOT cd back

10. **Report success**:
    ```
    Now working in: tmp/worktrees/<short-name>
    Branch: <branch-name>
    Test database: axis_test<NUM>

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
