---
name: wt
description: Create a git worktree for parallel Claude Code development. Pass a branch name and it sets up an isolated worktree with its own test database, then switches to working in that directory.
user-invocable: true
arguments: branch-name
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/wt.sh *)
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

## Basing on an existing remote branch (ticket branches)

When implementing off a ticket, FIRST check the ticket's comments for a named branch
(e.g. "Branch **foo**"). If one exists, pass that exact name to `/wt`. A teammate has
usually pushed in-progress work there (frontend, mockups, partial implementation) that
you must build on, NOT duplicate or start fresh from master.

`wt.sh create` enforces this automatically: if a remote branch matches the requested
name, it bases the new worktree on `origin/<name>` instead of the current HEAD (look for
the `Basing on origin/<name>` line in its output). After creation, rebase onto the main
branch as needed. Only fall back to branching from master when the ticket names no branch.

## What Happens

1. Creates the git branch if it doesn't exist (based on `origin/<name>` when it exists)
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

2. **Create the worktree** using the CLI script. It handles TEST_ENV_NUMBER assignment, branch creation, and worktree creation atomically:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/wt.sh create <branch-name>
   ```
   The script outputs `WORKTREE_DIR=...`, `BRANCH=...`, and `TEST_ENV_NUMBER=...`. Use these values for subsequent steps.

3. **Save the main repo path** before changing directories:
   ```bash
   MAIN_REPO=$(git rev-parse --show-toplevel)
   ```

4. **Change to worktree directory**:
   ```bash
   cd <WORKTREE_DIR>
   ```

5. **Copy gitignored config files** (use `cat` not `cp`):
   ```bash
   cat <MAIN_REPO>/config/master.key > config/master.key
   ```
   ```bash
   cat <MAIN_REPO>/config/database.yml > config/database.yml
   ```

6. **Run bootstrap** to set up the database:
    ```bash
    BUNDLE_GEMFILE=<MAIN_REPO>/Gemfile TEST_ENV_NUMBER=<TEST_ENV_NUMBER> bin/rake bootstrap
    ```

7. **Stay in the worktree directory** - do NOT cd back

8. **Report success**:
    ```
    Now working in: <WORKTREE_DIR>
    Branch: <BRANCH>
    TEST_ENV_NUMBER: <TEST_ENV_NUMBER>

    For all commands, use: BUNDLE_GEMFILE=<MAIN_REPO>/Gemfile TEST_ENV_NUMBER=<TEST_ENV_NUMBER>
    ```

## Important

- After setup, remain in the worktree directory
- For ALL subsequent commands in this session, prefix with:
  - `BUNDLE_GEMFILE=<main-repo>/Gemfile` - reuse gems from main repo
  - `TEST_ENV_NUMBER=<NUM>` - use isolated test database

## Finishing a Worktree

When the user says they're done with a worktree and want to finish it:

1. **Commit if needed**:
   ```bash
   git status
   ```
   - If there are uncommitted changes, create a commit summarizing the work done
   - If the working tree is clean, skip to step 2

2. **Run the finish command** (must be run from inside the worktree):
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/wt.sh finish; cd <MAIN_REPO>
   ```
   The `cd` must be chained in the same Bash call — the worktree directory is deleted by the script.
   Use the main repo path saved during worktree creation.

   This will:
   - Abort if there are uncommitted changes
   - Rebase the branch onto main repo's HEAD
   - Remove the worktree
   - If main repo was on master/main: checkout the branch
   - If main repo was on another branch: merge the worktree branch into it and delete the worktree branch

3. **Report done** - user is now on the branch and ready to continue

## Abandoning a Worktree

When the user wants to discard a worktree and its branch entirely:

```bash
${CLAUDE_SKILL_DIR}/scripts/wt.sh abandon; cd <MAIN_REPO>
```

The `cd` must be chained in the same Bash call — the worktree directory is deleted by the script.
Use the main repo path saved during worktree creation.

This will:
- Commit any uncommitted changes (so the worktree can be cleanly removed)
- Remove the worktree
- Force-delete the local branch
- Delete the remote branch if it exists

## Listing Worktrees

```bash
${CLAUDE_SKILL_DIR}/scripts/wt.sh list
```
