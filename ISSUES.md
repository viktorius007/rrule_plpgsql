# Testing Issues

Issues identified through critical evaluation of the testing framework. Prioritized by risk and production impact.

**Generated:** 2026-02-05
**Statement Coverage:** 71.62% (911/1272)
**Branch Coverage:** 95.2% (200/210)
**Mutation Score:** 100% (21/21)

---

## Status Legend

| Status | Meaning |
|--------|---------|
| `OPEN` | Not started |
| `IN_PROGRESS` | Work underway |
| `DONE` | Completed and verified |
| `DEFERRED` | Intentionally postponed |
| `FALSE POSITIVE` | Investigation found no actual issue |

---

## Priority 1: Critical Security/DoS

### ISSUE-001: DoS protection branches untested in `_advance_yearly()`

**Status:** DONE
**Risk:** CRITICAL
**Coverage Impact:** 2 branches

Two critical DoS protection branches have zero test coverage:

```
Line 1598: IF result.omit_count >= p_period_limit  (SKIP=OMIT termination)
Line 1620: IF result.period_count >= p_period_limit (normal termination)
```

These limits prevent infinite loops when processing rules that skip many periods. A bug here could cause production database hangs.

**Resolution:**
Created `tests/security/test_dos_protection_yearly.sql` with:
- Public API tests using impossible dates (Feb 30, Feb 31, Apr 31) that trigger DoS limits
- Direct `_advance_yearly()` function tests with controlled small `period_limit` values
- Tests verifying `omit_count` and `period_count` increment correctly
- Regression tests ensuring normal SKIP behavior still works
- Edge cases with INTERVAL > 1 and UNTIL termination

Also created `tests/security/test_dos_protection_monthly.sql` for `_advance_monthly()`:
- Same pattern using day 32 (never exists in any month)
- Both functions now at 100% coverage

**Verification:**
- All 28 test suites pass (./test.sh --standard), 58 with --both
- Static linter passes (./lint-tests.sh)
- Direct function tests confirm DoS branches execute and terminate correctly
- Profiler confirms 100% coverage on both `_advance_yearly()` and `_advance_monthly()`

**Files:** `tests/security/test_dos_protection_yearly.sql`, `tests/security/test_dos_protection_monthly.sql`

---

### ISSUE-002: `overlaps()` 5-parameter signature was dead code

**Status:** DONE
**Risk:** N/A (resolved)
**Coverage Impact:** 0 statements (removed)

**Root Cause:**
The 5-parameter `overlaps(dtstart, dtend, rrule_string, mindate, maxdate)` function was unreachable dead code. PostgreSQL function resolution always preferred the 6-parameter version (which has `timezone TEXT DEFAULT NULL`). When users called `rrule."overlaps"()` with 5 TIMESTAMPTZ arguments, PostgreSQL matched the 6-parameter overload.

**Resolution:**
Deleted the unreachable 5-parameter function from `src/rrule.sql`. The 6-parameter TIMESTAMPTZ API remains the sole `overlaps()` implementation and is fully tested.

Updated `tests/test_consensus_gaps_2.sql` to call `rrule."overlaps"()` directly instead of using a workaround wrapper that replicated the dead code's logic.

**Verification:**
- All tests pass with `./test.sh --standard`
- Linters pass: `./lint.sh`, `./lint-tests.sh`
- No API breaking changes (all existing calls already routed to 6-parameter version)

**Files:** `src/rrule.sql` (removed lines 3055-3109), `tests/test_consensus_gaps_2.sql`

---

## Priority 2: Coverage Gaps

### ISSUE-003: BYWEEKNO functions have 0% profiler coverage

**Status:** FALSE POSITIVE
**Risk:** N/A (measurement limitation)
**Coverage Impact:** N/A - functions are tested, profiler cannot measure

| Function | Volatility | Statements | Profiler Issue |
|----------|------------|------------|----------------|
| `byweekno_matches()` | IMMUTABLE | 10 | Optimized at plan time |
| `byweekno_matches_for_year()` | STABLE | 8 | Called with constant args |
| `get_week_info()` | STABLE | 15 | OR short-circuit |
| `get_week_number()` | STABLE | 3 | Called from filtered context |

**Root Cause:**
PostgreSQL's query planner evaluates IMMUTABLE functions at plan time when called with constant arguments. The plpgsql_check profiler operates at execution time and never sees these calls. This is a known limitation of coverage measurement for pure functions.

**Evidence Functions ARE Tested:**

*Direct Function Tests (`tests/test_internal_functions.sql`):*
- Section 19: `byweekno_matches()` - positive, negative, multiple values, NULL
- Section 20: `weeks_in_year()` - 52-week and 53-week years
- Section 24: `rrule_yearly_byweekno_set()` - 16 tests for cross-year boundaries

*Functional Tests (`tests/test_wkst_support.sql`):*
- BYWEEKNO with all 7 WKST values (tests 9-12)
- Week 53 handling (2015, 2020, 2026)
- Negative BYWEEKNO=-1 (last week of year)
- Negative BYWEEKNO=-53 (first week of 53-week years)
- Cross-year ISO week boundary (Issue 34 regression)

**Total: 32+ distinct BYWEEKNO tests across 17 test files**

**Why NOT Fix:**
Changing `byweekno_matches()` from IMMUTABLE to STABLE would:
1. Violate DECISIONS.md (function IS deterministic)
2. Degrade query performance for users
3. Only produce a cosmetic improvement to profiler numbers

Adding artificial tests with variable inputs would create maintenance burden for no real coverage improvement since the underlying code paths are already exercised.

**Resolution:** FALSE POSITIVE. The 0% profiler coverage is a measurement limitation, not a testing gap. The functions are comprehensively tested via direct tests and functional tests.

---

### ISSUE-004: TIMESTAMPTZ MONTHLY generator under-tested

**Status:** DONE
**Risk:** HIGH
**Coverage Impact:** 5 branches in `rrule_event_instances_range_tz()`

The TZ generator has 21.13% coverage vs TIMESTAMP generator's 98.61%. Specifically untested:

| Line | Branch | Condition |
|------|--------|-----------|
| 3259 | 12 | `current_base = basedate` (first iteration) |
| 3264 | 13 | `output_limit IS NULL` (1000 cap path) |
| 3275 | 14 | `current >= mindate` (range filtering) |
| 3366 | 28 | Sub-day frequency check |
| 3368 | 29 | Else branch for unsupported freq |

**Resolution:**
Added TEST SUITE 22 to `tests/test_tz_api.sql` with 9 tests targeting MONTHLY TIMESTAMPTZ branches:

| Test | Purpose | Branch Targeted |
|------|---------|-----------------|
| 22.1 | Simple MONTHLY COUNT=4 | Line 3203 TRUE (first iteration) |
| 22.2 | MONTHLY between() with mindate > dtstart | Line 3219 (range filtering) |
| 22.3 | Unbounded MONTHLY hitting 10-year window | Line 3208 (output_limit NULL) |
| 22.4 | MONTHLY after() offset query | TZ API path |
| 22.5 | MONTHLY before() offset query | TZ API path |
| 22.6 | MONTHLY INTERVAL=2 | Line 3203 FALSE (subsequent iterations) |
| 22.7 | MONTHLY with explicit COUNT | Line 3208 (output_limit non-NULL) |
| 22.8 | HOURLY via TZ API raises error | Line 3310 (sub-day check) |
| 22.9 | FREQ=INVALID raises error | Line 3312 (invalid freq) |

Also fixed a pre-existing bug in test `before() with inc=TRUE includes boundary date` which was doing TEXT comparison instead of TIMESTAMPTZ comparison (same instant, different timezone formats). Added second failure check block at end of file to catch tests that were added after the original failure check.

**Verification:**
- All 28 test suites pass (`./test.sh --standard`)
- Linters pass (`./lint-tests.sh`)
- Manual spot-checks confirm expected behavior

**Files:** `tests/test_tz_api.sql`

---

### ISSUE-005: Validation error paths for time filters untested

**Status:** OPEN
**Risk:** MEDIUM
**Coverage Impact:** 3 branches in `parse_rrule_parts()`

These validation branches reject BYMINUTE/BYSECOND with WEEKLY/MONTHLY/YEARLY (documented limitation):

| Line | Condition |
|------|-----------|
| 562 | `result.byminute IS NOT NULL` with non-DAILY freq |
| 565 | `result.bysecond IS NOT NULL` with non-DAILY freq |
| 572 | `result.bysetpos IS NOT NULL` with sub-day freq |

**Test Strategy:**
- Add rejection tests to `tests/matrix/test_rejection_matrix.sql`:
  ```sql
  -- Should reject: BYMINUTE with WEEKLY
  SELECT rrule."all"('FREQ=WEEKLY;BYMINUTE=30;COUNT=5', '2025-01-01'::TIMESTAMP);
  ```

**Files:** `tests/matrix/test_rejection_matrix.sql`

---

## Priority 3: Property Test Expansion

### ISSUE-006: Property tests missing BYWEEKNO strategy

**Status:** OPEN
**Risk:** MEDIUM

The Hypothesis strategies in `tests/property/strategies.py` do not generate BYWEEKNO rules. This means property-based invariant testing never exercises week number logic.

**Test Strategy:**
- Add `rrule_with_byweekno()` strategy
- Ensure it only generates `FREQ=YEARLY` (RFC 5545 requirement)
- Add invariant test verifying results fall in specified week numbers

**Files:** `tests/property/strategies.py`, `tests/property/test_invariants.py`

---

### ISSUE-007: Property tests missing BYSETPOS strategy

**Status:** OPEN
**Risk:** MEDIUM

BYSETPOS is a complex post-filter that selects positions from candidate sets. Not covered by property tests.

**Test Strategy:**
- Add `rrule_with_bysetpos()` strategy
- Test with MONTHLY and YEARLY frequencies
- Verify position selection invariants (e.g., BYSETPOS=1 returns first, BYSETPOS=-1 returns last)

**Files:** `tests/property/strategies.py`, `tests/property/test_invariants.py`

---

### ISSUE-008: Property tests missing SKIP parameter

**Status:** OPEN
**Risk:** MEDIUM

RFC 7529 SKIP parameter (OMIT/BACKWARD/FORWARD) is not tested by property tests. This is a production feature for month-end handling.

**Test Strategy:**
- Add `rrule_with_skip()` strategy generating MONTHLY/YEARLY rules with BYMONTHDAY=29,30,31
- Test SKIP=OMIT (default), SKIP=BACKWARD, SKIP=FORWARD
- Verify month-end dates are handled per specified mode

**Files:** `tests/property/strategies.py`, `tests/property/test_advanced.py`

---

### ISSUE-009: Property tests missing ordinal BYDAY patterns

**Status:** OPEN
**Risk:** LOW

Ordinal BYDAY patterns like `2MO` (2nd Monday), `-1FR` (last Friday) are not generated by property tests.

**Test Strategy:**
- Add ordinal generation to `rrule_with_byday()` strategy
- Only generate ordinals for MONTHLY/YEARLY (RFC 5545 requirement)
- Verify ordinal constraints (result.day matches Nth weekday of month)

**Files:** `tests/property/strategies.py`

---

### ISSUE-010: Differential testing uses overly conservative strategies

**Status:** OPEN
**Risk:** LOW

The `simple_rrule_for_differential()` strategy deliberately avoids edge cases to prevent false failures. This means differential testing doesn't verify behavior in boundary conditions.

**Constraints applied:**
- YEARLY: max 9 occurrences
- MONTHLY: max 24 occurrences, max interval 4
- No BYMONTHDAY (month-end edge cases)
- No SKIP parameter

**Trade-off:** The conservative approach ensures tests pass but misses potential divergences.

**Test Strategy:**
- Create separate `edge_case_rrule_for_differential()` strategy
- Document specific known differences rather than avoiding them
- Run edge case tests with explicit exception handling

**Files:** `tests/property/strategies.py`, `tests/property/known_differences.py`

---

## Priority 4: Edge Case Hardening

### ISSUE-011: Feb 29 handling needs comprehensive testing

**Status:** OPEN
**Risk:** LOW

Leap year Feb 29 with all three SKIP modes needs systematic testing.

**Test Cases Needed:**
- `FREQ=YEARLY;BYMONTHDAY=29;BYMONTH=2;SKIP=OMIT` - skip non-leap years
- `FREQ=YEARLY;BYMONTHDAY=29;BYMONTH=2;SKIP=BACKWARD` - use Feb 28
- `FREQ=YEARLY;BYMONTHDAY=29;BYMONTH=2;SKIP=FORWARD` - use Mar 1
- Same patterns with INTERVAL=4 (every 4 years = every leap year)

**Files:** `tests/test_skip_support.sql`

---

### ISSUE-012: BYWEEKNO with negative week numbers

**Status:** OPEN
**Risk:** LOW

Negative BYWEEKNO values (e.g., -1 = last week of year) may not be tested. RFC 5545 allows negative values for week selection.

**Test Strategy:**
- Test `FREQ=YEARLY;BYWEEKNO=-1` (last week)
- Test `FREQ=YEARLY;BYWEEKNO=-2` (second to last week)
- Verify against ISO 8601 week numbering

**Files:** `tests/test_wkst_support.sql`

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

## Completed

### ISSUE-001: DoS protection branches in `_advance_yearly()` and `_advance_monthly()` (2026-02-05)
Added tests for critical DoS protection branches that prevent infinite loops when SKIP logic encounters impossible dates:
- `_advance_yearly()`: Lines 1598-1600, 1620-1623 (Feb 30 never exists)
- `_advance_monthly()`: Lines 1502-1503, 1524-1526 (day 32 never exists)

Both functions now at 100% coverage. See `tests/security/test_dos_protection_yearly.sql` and `tests/security/test_dos_protection_monthly.sql`.

### ISSUE-002: 5-parameter `overlaps()` dead code removed (2026-02-05)
The 5-parameter `overlaps()` function was unreachable dead code because PostgreSQL function resolution always preferred the 6-parameter overload (with `timezone TEXT DEFAULT NULL`). Removed the dead function and updated tests to call `rrule."overlaps"()` directly. No API changes since all existing calls already routed to the 6-parameter TIMESTAMPTZ version.

### ISSUE-003: BYWEEKNO functions profiler coverage (2026-02-05)
FALSE POSITIVE. The 0% profiler coverage is caused by PostgreSQL's plan-time evaluation of IMMUTABLE functions, not missing tests. Functions are tested via direct tests in `test_internal_functions.sql` (Sections 19, 20, 24) and functional tests in `test_wkst_support.sql`.

### ISSUE-004: TIMESTAMPTZ MONTHLY generator branch coverage (2026-02-05)
Added TEST SUITE 22 to `test_tz_api.sql` with 9 tests covering MONTHLY frequency through the TIMESTAMPTZ API. Tests exercise first iteration, range filtering, output limits, after()/before() API paths, INTERVAL>1, and error handling for sub-day/invalid frequencies. Also fixed a pre-existing bug where test `before() with inc=TRUE includes boundary date` did TEXT comparison instead of TIMESTAMPTZ comparison.

---

## Notes

### Running Coverage Analysis

```bash
# Full profiler coverage report
./scripts/profiler-coverage.sh

# Branch coverage analysis
node scripts/verify-branch-coverage.js

# Mutation testing
npm run test:mutations
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
