# Global Claude Code Settings

This file provides default guidance to Claude Code (claude.ai/code) across all projects.

## Default Working Style

**Analysis & Planning Mode**
- Always analyze and plan all changes without making filesystem modifications
- Read any files needed to understand the current state
- Prepare detailed diffs showing all proposed edits
- Document commands to be run without executing them
- Present comprehensive review of all changes before implementation
- Only make actual changes after explicit user approval of the plan

## General Guidelines

- Be concise and direct in communication
- Follow existing code conventions and patterns
- Prefer editing existing files over creating new ones
- Never create documentation files unless explicitly requested
- Use TodoWrite tool for complex multi-step tasks
- Never commit changes unless explicitly asked
- When asked to commit, use single-line commit messages. NEVER add Co-Authored-By attribution
- Never introduce trailing whitespace in a file
- Prefer double quotes for strings unless single quotes are required

## Project Management
Use BARD Tracker MCP server for ticket management. **IMPORTANT** Use it in a read-only fashion, unless explicitly told you otherwise.

### Implementing from a ticket
- **ALWAYS check the ticket's comments for a named branch** (e.g. "Branch **foo**") before writing any code. If one exists, base ALL your work on that remote branch — `git fetch` and create your branch/worktree from `origin/<branch>` (rebasing onto the main branch as needed), NEVER fresh from master.
- A branch named in a ticket almost always contains a collaborator's in-progress work (frontend, mockups, partial implementation, WIP tests). Your job is to build on it, not duplicate it or reinvent the approach. Read their diff first and match their structure, naming, and intent.
- Their WIP may be incomplete or never-run (broken test data, undefined steps, stale assumptions). Finish it faithfully rather than replacing it: fix what's broken, keep what's intended.
- Only branch from the main branch when the ticket names no branch.

## Error Handling

**NEVER silently swallow errors.** Bare `rescue` blocks that return nil or a default value hide bugs and make debugging extremely difficult.

Bad - errors are invisible:
```ruby
rescue
  nil
end
```

Bad - still swallows the error:
```ruby
rescue => e
  Rails.logger.error(e)
  nil
end
```

Good - let it raise:
```ruby
# Just don't rescue at all if there's no meaningful recovery
```

Good - if you must handle it, be specific:
```ruby
rescue ActiveRecord::RecordNotFound
  # Handle this specific, expected case
end
```

**Avoid excessive defensive code.** Trust the system and let errors surface:
- Don't add nil checks unless nil is a legitimate expected value
- Don't wrap code in begin/rescue "just in case"
- Don't add fallbacks for scenarios that shouldn't happen
- If something unexpected happens, an exception is the correct behavior - it tells us there's a bug to fix

## Outside-In Development (BDD)

**ALWAYS develop outside-in, never inside-out.**

When implementing a feature:
1. **Start with user-visible behavior** - What does the user see or experience?
2. **Write a failing acceptance/integration test first** - Cucumber feature, request spec, or system test that exercises the full stack
3. **Watch it fail** - Confirm the test fails for the right reason
4. **Only then** think about implementation details and unit tests
5. **Drive implementation from the outside in** - Let the failing acceptance test guide what lower-level code is needed

This means:
- Do NOT start by editing models, services, or internal classes
- Do NOT write unit tests before the feature has an acceptance test
- Do NOT think about "how to implement" before "what the user should experience"
- The first code change should typically be a test file, not an implementation file

Example workflow:
1. User asks for "expeditions transition to Ready when requirements are met"
2. First question: "How does the user observe this?" (API response? UI change? Background job?)
3. Write a Cucumber feature or request spec that tests that user-visible behavior
4. Run it, watch it fail
5. Now implement the minimum code to make it pass
6. Add unit tests as needed for complex internal logic

## Critical Rule: Failing Tests

**WORK IS NOT DONE UNTIL ALL TESTS PASS**

- We ALWAYS start with a passing test suite
- If ANY test is failing after changes are made, the work is NOT complete
- **TEST FAILURES ARE ALWAYS MY FAULT** - since we start from green, any red is caused by my changes
- NEVER dismiss failures as "pre-existing" or "unrelated" - investigate thoroughly first
- NEVER declare work "ready for deployment" or "complete" with failing tests
- NEVER summarize work as successful if tests are failing
- Keep investigating and fixing until all tests pass
- Only after ALL tests pass can work be considered complete

## CI and Branch Assumptions

**Master/main is always green** - nothing gets merged without passing CI.

When debugging test failures on a branch:
- **DO NOT** try to check "was this test passing before?" by stashing changes or checking out master
- **ASSUME** the test was passing on master - CI enforces this
- Any test failure is caused by changes on the current branch vs master
- Focus investigation on what this branch changed, not on verifying the baseline
- Only in extremely rare circumstances could master be red (CI outage, force push, etc.)

## Testing with Cucumber

When running cucumber tests:
- **NEVER run the full cucumber test suite** - it is extremely slow. Only run specific feature files relevant to the current work (e.g., `bundle exec cucumber features/specific.feature`)
- **NEVER run a cucumber test without piping to an output file** - **ALWAYS** pipe output to a file first, so that you can grep it later. Ensure this file has a unique filename to avoid collisions with other Claude sessions
- After piping to a file, use grep/cat on that file to extract specific information
- This significantly reduces token usage and test execution time
- Use a descriptive filename based on the feature being tested, with a random number for uniqueness across sessions
- **Do NOT use shell variable expansion** (`$RANDOM`, `$F`, etc.) — use literal values to avoid permission prompts
- Example workflow:
  1. Run test: `bundle exec cucumber path/to/test.feature 2>&1 | tee /tmp/cucumber_login_38291.txt`
  2. Analyze: `grep "error" /tmp/cucumber_login_38291.txt`
  3. Get more context: `grep -A 10 -B 5 "specific error" /tmp/cucumber_login_38291.txt`
- **NEVER run multiple Cucumber commands in parallel without separate databases** — all scenarios share the same test database. To run Cucumber features in parallel, prefix each command with a unique `TEST_ENV_NUMBER=N` (e.g., `TEST_ENV_NUMBER=2 bundle exec cucumber ...`). Ensure the corresponding test database exists and is migrated.

## Testing with RSpec

When running the full rspec suite:
- **NEVER run the full rspec suite without piping to an output file** - **ALWAYS** use `tee` to capture output
- After piping to a file, use grep/cat on that file to extract specific information
- Use a descriptive filename based on the work being done, with a random number for uniqueness across sessions
- **Do NOT use shell variable expansion** (`$RANDOM`, `$F`, etc.) — use literal values to avoid permission prompts
- Example workflow:
  1. Run suite: `bundle exec rspec 2>&1 | tee /tmp/rspec_auth_changes_38291.txt`
  2. Analyze: `grep -E "(Failed|Error)" /tmp/rspec_auth_changes_38291.txt`
  3. Get more context: `grep -A 10 -B 5 "specific error" /tmp/rspec_auth_changes_38291.txt`

When editing Cucumber tables:
- **ALWAYS preserve column alignment** - maintain consistent spacing so columns line up
- When changing cell values, adjust spacing to keep the table properly aligned
- Example: if replacing "Early Adopter" (13 chars) with "Standard" (8 chars), add 5 spaces after "Standard"
- Surplus columns in the HTML content are ignored - you can omit columns you don't care about in test expectations

When writing Cucumber scenarios:
- **Prefer existing step definitions** - search `features/step_definitions/` for existing steps before creating new ones
- Many common actions already have step definitions (e.g., clicking links, filling forms, checking content)
- Only create new step definitions when no existing step can accomplish the task
- Reusing steps keeps the test suite consistent and maintainable

## Chop Gem

Chop is a Ruby gem ([botandrose/chop](https://github.com/botandrose/chop)) that enhances Cucumber tables with three methods: `#create!` (entity creation), `#diff!` (compare tables against HTML elements), and `#fill_in!` (form filling). It monkey-patches Cucumber's DataTable class. When writing or modifying Cucumber step definitions that interact with tables, refer to the Chop [README](https://github.com/botandrose/chop/blob/master/README.md) and [CLAUDE.md](https://github.com/botandrose/chop/blob/master/CLAUDE.md) for the full DSL (field transformations, diffing options, regex templates, etc.).

## Git Worktrees

**Detecting worktrees:**
- **ALWAYS check "Additional working directories" in the environment context before starting work**
- **Also check if the CWD itself is a worktree** — if the path contains `tmp/worktrees/`, you ARE in a worktree already
- **Detached HEAD is a worktree signal** — if git status shows `HEAD` instead of a branch name, verify with `git worktree list`
- If a worktree is active, ALL work (file edits, git commands, test runs) must happen there, not in the main repo
- Working in the main repo when a worktree exists stomps on other people's in-progress changes
- **TEST_ENV_NUMBER is encoded in the branch name prefix** — branch names follow the format `<TEST_ENV_NUMBER>-<rest>` (e.g., `11-472852-my-feature`). The prefix is always 1-2 digits (under 100); a 3+ digit prefix is a ticket ID, not a TEST_ENV_NUMBER. Extract it: `git branch --show-current | grep -oP '^\d{1,2}(?=-)'`

**Plans in worktrees:**
- Plans must include the full worktree path and `TEST_ENV_NUMBER`
- Use absolute paths in the plan so the implementing session resolves files correctly

**Closing/removing a git worktree:**
- **NEVER use `--force` to remove a worktree** - this can destroy uncommitted work
- If `git worktree remove` fails due to modified or untracked files, STOP and ask the user what to do
- Before removing, check what files are dirty and report them to the user
- The user will decide whether to commit, stash, or discard the changes

## Code Comments

- Comments are rare and terse. Default to none. A reviewer skimming the code should see mostly code, not prose.
- Only comment the "why" when it is non-obvious from the code (a surprising constraint, a workaround, a gotcha). Never comment "what" or "how" — the code already says that.
- One terse line, not a paragraph. Never write multi-line explanatory blocks, restate the method's behavior, or include usage examples — that belongs in docs, not inline.
- If a comment just narrates the next line, delete it. When in doubt, leave it out.

## Rails Conventions

### Migrations
- Only use ActiveRecord migration commands, raw SQL, and standard Ruby in migrations
- Never reference application models (e.g., `User.find_each`) in migrations - they may not exist or have different schemas when the migration runs
- Use raw SQL queries or direct table manipulation instead

### Path Helpers
- Prefer array-style path building over named path helpers:
  - Use: `[:admin, organization, invoice]`
  - Avoid: `admin_organization_invoice_path(organization, invoice)`
- Use `form` as the block variable name in form builders:
  - Use: `form_with model: @user do |form|`
  - Avoid: `form_with model: @user do |f|`
- Prefer `expose` pattern over instance variables for controller-to-view data:
  - Use: `expose :invoice, :credit_note` with private methods that memoize
  - Avoid: `@invoice = Invoice.find(...)` in controller actions
  - Views should use bare identifiers like `invoice` instead of `@invoice`
  - The `expose` method creates `attr_reader` and `helper_method` for each symbol

## Configuration Precedence

Claude Code loads instructions in the following order of precedence (highest to lowest):
1. `CLAUDE.md` in the project directory
2. `AGENTS.md` in the project directory (if project CLAUDE.md doesn't exist)
3. `~/.claude/CLAUDE.md` (global defaults)

This allows projects to override global settings either with a full CLAUDE.md or with agent-specific guidance via AGENTS.md.
