# Testing Issues

Issues identified through critical evaluation of the testing framework. Prioritized by risk and production impact.

**Generated:** 2026-02-07
**Statement Coverage:** 71.62% (911/1272)
**Branch Coverage:** 95.2% (200/210)
**Mutation Score:** 100% (21/21)

---

## Status Legend

| Status | Meaning |
|--------|---------|
| `OPEN` | Not started |
| `IN_PROGRESS` | Work underway |
| `REQUIRES VERIFICATION` | Needs independent verification that the issue doesn't exist |
| `DEFERRED` | Intentionally postponed |

---

## Open

### ISSUE-014: Parser accepts `X*` extension parameters as core RRULE fields

**Status:** REQUIRES VERIFICATION
**Risk:** HIGH
**Coverage Impact:** Validation/parser edge-case gap

`parse_rrule_parts()` uses unanchored extraction patterns (e.g., `COUNT=...`, `FREQ=...`, `BYDAY=...`) that can match inside extension parameter names.

**Confirmed Reproduction:**
- `rrule."count"('FREQ=DAILY;XCOUNT=2', '2025-01-01')` returns `2` (should ignore `XCOUNT`)
- `rrule."count"('XFREQ=DAILY;COUNT=2', '2025-01-01')` returns `2` (should reject missing `FREQ`)
- `rrule."all"('FREQ=DAILY;COUNT=3;XBYDAY=MO', '2025-01-01')` emits Mondays (should ignore `XBYDAY`)

**Root Cause:**
- Regexes in `parse_rrule_parts()` are not consistently anchored to token boundaries `(^|;)`.

**Hardening Strategy:**
- Anchor all extraction and presence checks to `(^|;)PARAM=`.
- Add regression tests for `XCOUNT`, `XFREQ`, `XBYDAY`, and similar extension collisions.

**Files:**
- `src/rrule.sql`
- `tests/test_validation.sql`

**Implementation-Ready Test Spec:**

Add a dedicated section to `tests/test_validation.sql` (or a new `tests/test_extension_params.sql`) covering token-boundary collisions.

Use fixed `dtstart`: `'2025-01-01 00:00:00'::TIMESTAMP`.

Required cases and expected behavior:
- Case 14.1
  - RRULE: `FREQ=DAILY;XCOUNT=2`
  - Call: `rrule."count"(...)`
  - Expect: `1000` (API cap path), not `2`
- Case 14.2
  - RRULE: `XFREQ=DAILY;COUNT=2`
  - Call: `rrule."all"(...)`
  - Expect: rejection with pattern `%FREQ parameter is required%`
- Case 14.3
  - RRULE: `FREQ=DAILY;COUNT=3;XBYDAY=MO`
  - Call: `array_agg` over `rrule."all"(...)`
  - Expect: `{2025-01-01,2025-01-02,2025-01-03}` (daily), not Monday-only
- Case 14.4
  - RRULE: `FREQ=DAILY;COUNT=3;XBYMONTH=2`
  - Expect: same 3 daily January occurrences (XBYMONTH ignored)
- Case 14.5
  - RRULE: `FREQ=DAILY;COUNT=3;XBYSETPOS=1`
  - Expect: same 3 daily occurrences (XBYSETPOS ignored)
- Case 14.6
  - RRULE: `FREQ=DAILY;COUNT=3;XXFREQ=WEEKLY`
  - Expect: no parse effect from `XXFREQ`, still daily results

TIMESTAMPTZ parity cases (minimum):
- Mirror 14.2 and 14.3 using `rrule."all"(TEXT, TIMESTAMPTZ, TEXT)` with explicit timezone `'UTC'`.

Suggested assertion style:
- Reuse `assert_rrule_rejected(...)` for error-pattern checks.
- For acceptance checks, use `array_agg(occurrence::date ORDER BY occurrence)` exact equality.

**Done When:**
- All cases above are present and pass.
- Existing validation suites still pass in `./test.sh --standard`.

**Resolution Notes (2026-02-07):**
- Anchored parser extraction and presence checks to token boundaries in `src/rrule.sql` (`parse_rrule_parts`), including duplicate FREQ detection.
- Added extension-collision regressions in `tests/test_validation.sql` and matrix coverage in `tests/matrix/test_api_boundary_matrix.sql`.
- Local verification passed via `./test.sh --both` and `./lint-tests.sh`.

---

### ISSUE-015: TIMESTAMP `next()` / `most_recent()` default reference time is session-timezone dependent

**Status:** REQUIRES VERIFICATION
**Risk:** MEDIUM
**Coverage Impact:** Default-argument behavior gap

TIMESTAMP wrappers use `NOW()::TIMESTAMP` when `reference_time` is NULL and do not pin timezone at function level.

**Confirmed Reproduction:**
- Same call to `rrule."next"('FREQ=DAILY', probe_ts, NULL)` returned different dates under different session `TimeZone` values (`UTC` vs `America/New_York`).

**Why This Matters:**
- Violates deterministic behavior expectation for the TIMESTAMP API when relying on default `reference_time`.

**Hardening Strategy:**
- Pin timezone in wrappers or compute default reference in UTC (`NOW() AT TIME ZONE 'UTC'`).
- Add explicit tests for NULL `reference_time` under non-UTC session timezone.

**Files:**
- `src/rrule.sql`
- `tests/test_coverage_gaps.sql`
- `tests/matrix/test_api_boundary_matrix.sql`

**Implementation-Ready Test Spec:**

Add deterministic session-timezone variance tests for NULL `reference_time`.

Key strategy:
- Build a dynamic `probe_ts` from New York wall-clock so one session is before the daily occurrence and another is after it.
- Evaluate same function call under two session timezones.

Recommended SQL pattern:
```sql
-- deterministic probe relative to current date, avoids hardcoding a stale date
WITH p AS (
  SELECT ('2025-01-01'::date + ((now() AT TIME ZONE 'America/New_York' + interval '1 hour')::time))::timestamp AS probe_ts
)
SELECT ...
```

Required cases and expected behavior:
- Case 15.1 (`next`)
  - Session A: `SET timezone='UTC'`
  - Session B: `SET timezone='America/New_York'`
  - Call both: `rrule."next"('FREQ=DAILY', probe_ts, NULL)`
  - Current behavior (bug): values differ by one day
  - Post-fix expectation: values are equal across sessions
- Case 15.2 (`most_recent`)
  - Same setup/call pattern with `rrule."most_recent"('FREQ=DAILY', probe_ts, NULL)`
  - Post-fix expectation: equal across sessions
- Case 15.3 (control)
  - Provide explicit `reference_time` and assert equality across session timezone today and after fix.

Add guard assertion:
- When explicit `reference_time` is supplied, no timezone-variance should occur.

**Done When:**
- NULL-path variance test fails on old behavior and passes after fix.
- Explicit-reference control remains passing.

**Resolution Notes (2026-02-07):**
- Updated TIMESTAMP wrappers in `src/rrule.sql`:
  - `rrule."next"` now uses `COALESCE(reference_time, (NOW() AT TIME ZONE 'UTC')::TIMESTAMP)`
  - `rrule."most_recent"` now uses `COALESCE(reference_time, (NOW() AT TIME ZONE 'UTC')::TIMESTAMP)`
- Added deterministic timezone-invariance tests for NULL/default path and explicit-reference controls in:
  - `tests/test_coverage_gaps.sql`
  - `tests/matrix/test_api_boundary_matrix.sql`
- Local verification passed via `./test.sh --both` and `./lint-tests.sh`.

---

### ISSUE-016: Volatility classification mismatch for timezone-sensitive restore helpers

**Status:** REQUIRES VERIFICATION
**Risk:** MEDIUM
**Coverage Impact:** Classification and planner-safety gap

`_restore_monthly_base()` and `_restore_yearly_base()` are marked `IMMUTABLE` but operate on `TIMESTAMPTZ` with `date_trunc`, which depends on timezone context.

**Confirmed Reproduction:**
- Calling `_restore_monthly_base(...)` with identical args produced different UTC-normalized output when session timezone changed.

**Why This Matters:**
- Conflicts with the project volatility policy and can allow unsafe planner assumptions.

**Hardening Strategy:**
- Mark these helpers `STABLE`, or refactor to timezone-invariant inputs.
- Add a focused volatility regression test.

**Files:**
- `src/rrule.sql`
- `tests/test_internal_functions.sql`

**Implementation-Ready Test Spec:**

This issue is primarily classification hardening, but add regression tests to prove timezone sensitivity of helper output.

Required cases:
- Case 16.1 (`_restore_monthly_base`)
  - Same args, two session timezones (`UTC`, `America/New_York`)
  - Compare UTC-normalized outputs via `AT TIME ZONE 'UTC'`
  - Expect different outputs on current implementation (proof of non-immutability)
- Case 16.2 (`_restore_yearly_base`)
  - Same setup as 16.1
  - Expect timezone-sensitive output

Post-fix expectation options:
- If function is relabeled to `STABLE`: tests should document and assert timezone sensitivity remains possible.
- If refactored to timezone-invariant logic: tests should assert identical UTC-normalized outputs across sessions.

Catalog assertion (recommended):
- Query `pg_proc.provolatile` for both helpers and assert expected volatility char:
  - `s` if relabeled STABLE
  - `i` only if implementation made truly timezone-invariant

**Done When:**
- Behavioral test and volatility metadata test both added and passing.

**Resolution Notes (2026-02-07):**
- Changed volatility classification in `src/rrule.sql`:
  - `_restore_monthly_base`: `IMMUTABLE` -> `STABLE`
  - `_restore_yearly_base`: `IMMUTABLE` -> `STABLE`
- Added regression checks in `tests/test_internal_functions.sql` for:
  - timezone-sensitive behavior across session timezones
  - catalog metadata assertion (`pg_proc.provolatile = 's'`)
- Local verification passed via `./test.sh --both` and `./lint.sh`.

---

### ISSUE-017: Missing adversarial tests allowed parser and timezone-default bugs to pass undetected

**Status:** REQUIRES VERIFICATION
**Risk:** MEDIUM
**Coverage Impact:** Test strategy gap

Current tests are strong for RFC-valid rules but miss adversarial and environment-sensitive cases:
- No tests for `X*` extension collisions (`XCOUNT`, `XFREQ`, `XBYDAY`).
- Limited coverage of `reference_time IS NULL` path in TIMESTAMP convenience APIs.
- Most runs occur in UTC, masking session-timezone sensitivity.

**Hardening Strategy:**
- Add negative/edge suites specifically for extension-token collisions.
- Add per-test timezone variance checks for default-time paths.
- Keep deterministic explicit-time tests, but include targeted defaults-path tests.

**Files:**
- `tests/test_validation.sql`
- `tests/test_coverage_gaps.sql`
- `tests/matrix/test_api_boundary_matrix.sql`

**Implementation-Ready Test Expansion Matrix:**

Minimum new edge suites:
- Extension-token collisions:
  - `XCOUNT`, `XFREQ`, `XBYDAY`, `XBYMONTH`, `XBYSETPOS`
- Defaults-path behavior:
  - `next(..., NULL)` and `most_recent(..., NULL)` under at least 2 session timezones
- Control path:
  - explicit reference-time calls under same 2 timezones

Execution targets:
- Must pass under `./test.sh --standard`
- Add at least one matrix-style test row in `tests/matrix/test_api_boundary_matrix.sql` for each new edge category

Acceptance criteria:
- No open parser-collision paths without an explicit regression case
- No defaults-path timezone behavior without explicit test coverage

**Resolution Notes (2026-02-07):**
- Added adversarial extension-token collision tests (`XCOUNT`, `XFREQ`, `XBYDAY`, `XBYMONTH`, `XBYSETPOS`, `XXFREQ`) with TIMESTAMPTZ parity coverage.
- Added defaults-path timezone variance + explicit-reference control coverage for TIMESTAMP convenience APIs.
- Added matrix-style rows covering both edge categories.
- Local verification passed via `./test.sh --both`, `./lint.sh`, and `./lint-tests.sh`.

---

### ISSUE-018: Stale documentation references in code and install messaging

**Status:** OPEN
**Risk:** LOW
**Coverage Impact:** Operational/documentation gap

Several messages reference files that no longer exist:
- `INCLUDING_SUBDAY_OPERATIONS.md` (actual: `docs/SUBDAY_OPERATIONS.md`)
- `MANUAL_MIGRATION.md` (actual: `docs/MIGRATION.md`)

**Why This Matters:**
- Misleads operators during installation and troubleshooting.

**Hardening Strategy:**
- Update references in SQL comments and exception text.
- Add a simple doc-link consistency check in CI.

**Files:**
- `src/rrule.sql`
- `src/install.sql`

**Implementation-Ready Verification Checks:**

Add static check script (or extend existing lint script) to fail CI on broken intra-repo doc references in SQL files.

Minimum checks:
- Reject `INCLUDING_SUBDAY_OPERATIONS.md`
- Reject `MANUAL_MIGRATION.md` if file does not exist
- Confirm referenced canonical paths exist:
  - `docs/SUBDAY_OPERATIONS.md`
  - `docs/MIGRATION.md`

**Done When:**
- SQL comments/messages updated and check script enforced in CI.

---

### ISSUE-019: Contributor documentation drift on iteration multipliers

**Status:** OPEN
**Risk:** LOW
**Coverage Impact:** Design/implementation alignment gap

`CLAUDE.md` multiplier table does not match current `calculate_safe_iteration_limit()` logic.

**Why This Matters:**
- Increases risk of incorrect future edits and review confusion.

**Hardening Strategy:**
- Update `CLAUDE.md` table to match code.
- Optionally generate documentation snippets from source constants.

**Files:**
- `CLAUDE.md`
- `src/rrule.sql`

**Implementation-Ready Verification Checks:**

Add one doc-alignment check in review checklist or CI script:
- Parse `calculate_safe_iteration_limit()` constants and compare against documented multiplier table in `CLAUDE.md`.

Minimum acceptance:
- Table values and rationale match current function branches for:
  - DAILY
  - WEEKLY
  - MONTHLY
  - YEARLY
- Any future change to constants must update docs in same PR.

---

## Deferred

### ISSUE-013: Sub-day frequency coverage

**Status:** DEFERRED
**Risk:** LOW (feature disabled by default)
**Coverage Impact:** ~200 statements

Sub-day frequencies (HOURLY, MINUTELY, SECONDLY) are intentionally disabled by default for security reasons (DoS risk: SECONDLY can generate 31M+ occurrences/year).

The following have low coverage because sub-day code paths aren't exercised in standard tests:
- `hourly_set()`: 56.25%
- `minutely_set()`: 56.25%
- `secondly_set()`: 56.25%
- TZ generator sub-day branches: 0%

**Deferral Reason:**
1. Feature is disabled by default for security
2. Requires `install_with_subday.sql` which has explicit security warnings
3. Testing would require separate test mode with security implications
4. Existing `test_subday_correctness.sql` covers the feature when enabled

**Revisit Condition:** If sub-day frequencies become enabled by default (requires security review).

**Reference:** CLAUDE.md "Security" section, docs/SUBDAY_OPERATIONS.md

---

## Notes

### Running Coverage Analysis

```bash
# Full profiler coverage report
./scripts/profiler-coverage.sh

# Branch coverage analysis
node scripts/verify-branch-coverage.js

# Mutation testing
pnpm test:mutations
```

### Adding New Issues

Use the format:
```markdown
### ISSUE-NNN: Brief description

**Status:** OPEN
**Risk:** CRITICAL | HIGH | MEDIUM | LOW
**Coverage Impact:** N statements/branches

Description of the issue.

**Test Strategy:**
- Specific test approach
- Files to modify

**Files:** `tests/relevant_file.sql`
```
