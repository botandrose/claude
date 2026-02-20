---
name: flaky
description: Investigate flaky Cucumber tests, diagnose the root cause, and suggest fixes.
user-invocable: true
allowed-tools: Bash(*), Read, Grep, Glob
arguments: feature-path[:line]
---

# Flaky Cucumber Test Investigator

Diagnose why a Cucumber scenario is flaky, identify the root cause, and suggest a fix.

## Usage

```
/flaky features/expeditions.feature:42
/flaky features/orders/checkout.feature:18
```

## Investigation Process

### 1. Parse the Argument

Extract the feature file path and optional line number from `$ARGUMENTS`. If no argument is given, ask the user which scenario to investigate.

### 2. Read the Scenario

Read the feature file. Identify the specific scenario at the given line (or ask the user to clarify if no line was given and the file has multiple scenarios). Also read:
- The `Background` block if present
- Step definitions used by the scenario (search `features/step_definitions/`)
- Any support files referenced (e.g., `features/support/`)

### 3. Run the Scenario Multiple Times

Run the scenario 8 times to observe the failure pattern. **Pipe output to a temp file** with a unique name.

If in a worktree, read `tmp/.test_env` for `TEST_ENV_NUMBER` and `BUNDLE_GEMFILE` and use them for all commands.

```bash
OUTFILE=/tmp/flaky_$(basename <feature> .feature)_$$.txt
for i in $(seq 1 8); do
  echo "=== RUN $i ==="
  bundle exec cucumber <feature>:<line> 2>&1
  echo "EXIT_CODE=$?"
done | tee "$OUTFILE"
```

Then analyze:
```bash
grep "EXIT_CODE=" "$OUTFILE"
```

- If it passes all 8 times, tell the user and offer to run more iterations.
- If it fails consistently, it's not flaky — it's broken. Report that instead.

### 4. Capture the Failure

From the failed runs, extract the error details:

```bash
grep -B 5 -A 20 "FAILED\|Error\|expected\|got:" "$OUTFILE"
```

Note:
- Which step failed
- The error message and exception type
- Actual vs expected values
- The backtrace

### 5. Analyze for Common Flaky Patterns

With the scenario, step definitions, and failure output in hand, check for these root causes:

**Database ordering:**
- Scenarios that assert table row order, but the underlying query has no `ORDER BY`
- Chop `#diff!` comparisons against HTML tables where the source query doesn't guarantee order
- `first` / `last` calls without explicit ordering

**Time-dependent logic:**
- Steps that depend on `Time.now`, `Date.today`, or relative dates
- Scenarios near time boundaries (midnight, month-end, DST)
- Assertions on formatted dates/times that shift between runs

**Capybara / JS async issues:**
- Steps that click or assert before JavaScript has finished rendering
- Missing `has_css?` / `has_content?` waits before assertions
- Animations or transitions that delay element visibility
- `find` calls that race against DOM updates

**Test order dependency:**
- Scenario only fails when run after or before a specific other scenario
- Global state (class variables, module-level memoization) modified by other scenarios

**External / environmental:**
- Network calls to real services
- File system assumptions (temp files, uploads directory)
- Port or TEST_ENV_NUMBER conflicts with parallel test processes

### 6. Investigate the Source Code

Read the application code exercised by the failing step. Trace from the step definition into models, controllers, or queries. Look for:
- Queries without deterministic `ORDER BY`
- Methods using `Time.now` or non-deterministic inputs
- Caching that persists between scenarios
- Side effects on shared state

### 7. Report Findings

Present a clear diagnosis:

1. **Flakiness confirmed**: X passes, Y failures out of N runs
2. **Root cause**: Explain why the scenario fails intermittently, with specific code references (file:line)
3. **Suggested fix**: Provide a concrete code change. Prefer fixing the source code (e.g., adding `ORDER BY` to a query) over papering over the issue in the test.

## Important

- **Don't fix without understanding.** The investigation matters more than the fix.
- **Prefer fixing root causes over symptoms.** If a query has no `ORDER BY` and the test asserts order, fix the query — don't sort in the test.
- **Never run the full Cucumber suite.** Only run the specific scenario being investigated.
