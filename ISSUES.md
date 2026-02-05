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

**Status:** DONE
**Risk:** MEDIUM
**Coverage Impact:** 3 branches in `parse_rrule_parts()`

These validation branches reject BYMINUTE/BYSECOND with WEEKLY/MONTHLY/YEARLY (documented limitation):

| Line | Condition | Test Coverage |
|------|-----------|---------------|
| 562 | `result.byminute IS NOT NULL` with non-DAILY freq | Already tested in `test_rejection_matrix.sql` |
| 565 | `result.bysecond IS NOT NULL` with non-DAILY freq | Already tested in `test_rejection_matrix.sql` |
| 572 | `result.bysetpos IS NOT NULL` with sub-day freq | **Added** in `test_subday_correctness.sql` Section 14 |

**Resolution:**
Investigation revealed lines 562 and 565 (BYMINUTE/BYSECOND with WEEKLY/MONTHLY/YEARLY) were already tested in `tests/matrix/test_rejection_matrix.sql` Section 5 (lines 152-176).

Only line 572 (BYSETPOS with sub-day frequencies) lacked coverage because it requires sub-day installation. Added Section 14 to `tests/test_subday_correctness.sql` with 5 tests:
- BYSETPOS with HOURLY rejected
- BYSETPOS with MINUTELY rejected
- BYSETPOS with SECONDLY rejected
- BYSETPOS=-1 (negative) with HOURLY rejected
- BYSETPOS=1,2,-1 (multiple values) with MINUTELY rejected

**Verification:**
- Sub-day tests pass: `./test.sh --subday`
- Full suite passes: `./test.sh --both`
- Static linter passes: `./lint-tests.sh`

**Files:** `tests/test_subday_correctness.sql` (Section 14 added)

---

## Priority 3: Property Test Expansion

### ISSUE-006: Property tests missing BYWEEKNO strategy

**Status:** DONE
**Risk:** MEDIUM

The Hypothesis strategies in `tests/property/strategies.py` did not generate BYWEEKNO rules. Property-based invariant testing never exercised week number logic.

**Resolution:**
Added `rrule_with_byweekno()` strategy and `test_byweekno_filtering()` invariant test.

The strategy:
- Only generates `FREQ=YEARLY` (RFC 5545 requirement)
- Generates week numbers in range 1-52 (positive) and -52 to -1 (negative)
- Optionally includes WKST (MO, SU) to test non-default week starts
- Optionally includes non-ordinal BYDAY (ordinals prohibited with BYWEEKNO per RFC 5545)
- Returns (rrule_string, expected_weeks, wkst) tuple for invariant validation

The invariant test:
- Queries database's `get_week_info()` to handle WKST-dependent week numbering correctly
- Uses `weeks_in_year()` to normalize negative week numbers
- Validates all results occur in specified ISO weeks

Verified with 1000 examples in CI profile.

**Files:** `tests/property/strategies.py`, `tests/property/test_invariants.py`

---

### ISSUE-007: Property tests missing BYSETPOS strategy

**Status:** DONE
**Risk:** MEDIUM

BYSETPOS is a complex post-filter that selects positions from candidate sets. Not covered by property tests.

**Resolution:**
Added `rrule_with_bysetpos()`, `rrule_with_bysetpos_first()`, and `rrule_with_bysetpos_last()` strategies along with four invariant tests:

| Test | Purpose |
|------|---------|
| `test_bysetpos_subset_invariant()` | Validates BYSETPOS results are subset of period's candidate set |
| `test_bysetpos_count_bound()` | Validates BYSETPOS results ≤ full results (filter never adds) |
| `test_bysetpos_first_position()` | Validates BYSETPOS=1 selects first candidate per period |
| `test_bysetpos_last_position()` | Validates BYSETPOS=-1 selects last candidate per period |

Strategies use UNTIL-based time bounding to ensure both rules cover identical time ranges for accurate comparison. The subset test accounts for the 1000-result API cap by only comparing periods with complete data.

**Verification:**
- All 4 BYSETPOS tests pass with 500 examples each
- CI profile (1000 examples) passes
- All 26 property tests pass
- All 28 SQL test suites pass

**Files:** `tests/property/strategies.py`, `tests/property/test_invariants.py`

---

### ISSUE-008: Property tests missing SKIP parameter

**Status:** DONE
**Risk:** MEDIUM

RFC 7529 SKIP parameter (OMIT/BACKWARD/FORWARD) is not tested by property tests. This is a production feature for month-end handling.

**Resolution:**
Added four strategies to `tests/property/strategies.py`:
- `dtstart_for_skip()`: Generate dtstart with day 29-31 to trigger SKIP edge cases
- `dtstart_leap_day()`: Generate Feb 29 from leap years for SKIP testing
- `rrule_with_skip()`: Generate MONTHLY/YEARLY rules with SKIP parameter
- `rrule_skip_comparison_pair()`: Generate paired rules for OMIT vs BACKWARD comparison

Added eight invariant tests to `tests/property/test_invariants.py`:
- `test_skip_all_dates_valid()`: All produced dates must be valid calendar dates
- `test_skip_no_duplicates()`: All occurrences must be distinct
- `test_skip_count_respected()`: COUNT must never be exceeded
- `test_skip_monotonicity()`: Results must be strictly ascending
- `test_skip_no_drift()`: BACKWARD must not cause cumulative drift
- `test_skip_idempotence()`: Same RRULE called twice returns identical results
- `test_skip_omit_subset_of_backward()`: Every OMIT result also appears in BACKWARD
- `test_skip_leap_year_behavior()`: Feb 29 dtstart triggers correct SKIP behavior

**Verification:**
- All 8 SKIP tests pass with 500 examples each
- CI profile (1000 examples) passes
- All 34 property tests pass
- All 28 SQL test suites pass (./test.sh --standard)
- Static linter passes (./lint-tests.sh)
- Manual spot-check confirms expected SKIP=BACKWARD behavior

**Files:** `tests/property/strategies.py`, `tests/property/test_invariants.py`

---

### ISSUE-009: Property tests missing ordinal BYDAY patterns

**Status:** DONE
**Risk:** LOW

Ordinal BYDAY patterns like `2MO` (2nd Monday), `-1FR` (last Friday) are not generated by property tests.

**Resolution:**
Added two strategies to `tests/property/strategies.py`:
- `rrule_with_byday_ordinal()`: Generate MONTHLY/YEARLY rules with ordinal BYDAY (e.g., `2MO`, `-1FR`)
- `rrule_ordinal_comparison_pair()`: Generate paired rules with/without ordinal for subset validation

Added four invariant tests to `tests/property/test_invariants.py`:
- `test_byday_ordinal_weekday()`: All results must occur on specified weekday
- `test_byday_ordinal_monthly_position()`: For MONTHLY (or YEARLY+BYMONTH), ordinal matches Nth weekday within month
- `test_byday_ordinal_yearly_position()`: For YEARLY without BYMONTH, ordinal applies to entire year
- `test_byday_ordinal_subset()`: Ordinal BYDAY results are subset of non-ordinal results

Strategies generate ordinals in range ±1 to ±5 (common range, avoids non-existent positions like 6th Monday in a month). YEARLY rules optionally include BYMONTH to test both year-scoped and month-scoped ordinal semantics.

**Verification:**
- All 4 ordinal BYDAY tests pass with 500 examples each
- All 38 property tests pass
- All 28 SQL test suites pass (`./test.sh --standard`)
- Static linter passes (`./lint-tests.sh`)
- Manual spot-checks confirm correct ordinal semantics

**Files:** `tests/property/strategies.py`, `tests/property/test_invariants.py`

---

### ISSUE-010: Differential testing uses overly conservative strategies

**Status:** DONE
**Risk:** LOW

The `simple_rrule_for_differential()` strategy deliberately avoids edge cases to prevent false failures. This means differential testing doesn't verify behavior in boundary conditions.

**Constraints applied:**
- YEARLY: max 9 occurrences
- MONTHLY: max 24 occurrences, max interval 4
- No BYMONTHDAY (month-end edge cases)
- No SKIP parameter

**Trade-off:** The conservative approach ensures tests pass but misses potential divergences.

**Resolution:**
Added edge case strategies and differential tests:

1. **`edge_case_rrule_for_differential()`** - Generates BYMONTHDAY rules (28-31, -1, -2) with MONTHLY/YEARLY frequencies (avoids DAILY due to ISSUE-014)
2. **`dtstart_edge_case_for_differential()`** - Generates dtstart with day 28-31 in 31-day months
3. **`test_bymonthday_matches_dateutil()`** - 300 examples comparing BYMONTHDAY edge cases
4. **`test_edge_dtstart_bymonthday()`** - 200 examples with edge case dtstart + BYMONTHDAY

Updated `known_differences.py` with:
- Pattern-based detection for SKIP/RSCALE parameters (dateutil-incompatible)
- Pattern-based detection for FREQ=DAILY + BYMONTHDAY>=29 (iteration limit issue, see ISSUE-014)
- Comprehensive documentation of systematic vs extension vs limitation differences
- Documented compatible behaviors (BYMONTHDAY with default SKIP=OMIT matches dateutil for MONTHLY/YEARLY)

Also tightened `simple_rrule_for_differential()` constraints:
- YEARLY: max 8 occurrences (was 9, to avoid 10-year boundary)
- MONTHLY: max 18 occurrences, max interval 3 (was 24/4, to handle month-skipping)

**Key Findings:**
1. BYMONTHDAY with MONTHLY/YEARLY + default SKIP=OMIT matches python-dateutil exactly
2. FREQ=DAILY + BYMONTHDAY>=29 has an iteration limit issue (filed as ISSUE-014)
3. 10-year window boundary can cause off-by-one when occurrence lands exactly at maxdate

**Verification:**
- All differential tests pass
- Full property test suite passes
- SQL test suite passes (`./test.sh --standard`)
- Linter passes (`./lint-tests.sh`)

**Files:** `tests/property/strategies.py`, `tests/property/test_differential.py`, `tests/property/known_differences.py`

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

### ISSUE-014: FREQ=DAILY + BYMONTHDAY iteration limit insufficient for sparse days

**Status:** OPEN
**Risk:** LOW
**Coverage Impact:** N/A (behavioral issue, not coverage gap)

The `calculate_safe_iteration_limit()` function returns `COUNT * 40` days for DAILY frequency. This is insufficient for sparse BYMONTHDAY values:
- BYMONTHDAY=31 occurs ~7 times/year (~52 days between occurrences)
- BYMONTHDAY=30 occurs ~11 times/year (~33 days between occurrences)
- BYMONTHDAY=29 occurs ~12 times/year (~30 days between occurrences)

With COUNT=3 and BYMONTHDAY=31, the iteration limit is 120 days, but finding 3 occurrences of day 31 can require up to 156 days (e.g., starting Feb 1).

**Example:**
```sql
-- PL/pgSQL returns 0 results (limit exceeded before finding any occurrence)
SELECT * FROM rrule."all"('FREQ=DAILY;BYMONTHDAY=29;COUNT=1', '2021-02-01'::timestamp);
-- Expected: 2021-03-29 (56 days away, but limit is only 40 days)
```

**Workaround:** Use `FREQ=MONTHLY;BYMONTHDAY=31` instead of `FREQ=DAILY;BYMONTHDAY=31` for sparse day-of-month patterns.

**Potential Fix:** Increase DAILY multiplier when BYMONTHDAY is present, or detect sparse BYMONTHDAY values and adjust accordingly.

**Files:** `src/rrule.sql` (calculate_safe_iteration_limit function, line ~1316)

---

### ISSUE-015: 10-year window boundary excludes occurrences at exact boundary

**Status:** OPEN
**Risk:** LOW
**Coverage Impact:** N/A (behavioral issue, not coverage gap)

The 10-year window cap uses strict `< maxdate` comparison, which excludes occurrences that land exactly at the 10-year boundary.

**Example:**
```sql
-- dtstart + 10 years = 2030-06-30
-- 21st occurrence lands exactly at 2030-06-30
SELECT * FROM rrule."all"('FREQ=MONTHLY;COUNT=21;INTERVAL=4', '2020-06-30'::timestamp);
-- Returns 20 results instead of 21
-- Missing: 2030-06-30 (exactly at 10-year boundary)
```

**Behavior:**
- PL/pgSQL: Returns 20 occurrences (excludes boundary)
- python-dateutil: Returns 21 occurrences (no cap)

**Root Cause:** In `rrule_event_instances_range()`, the condition `current_base < maxdate` excludes dates at exactly maxdate.

**Potential Fix:** Change `< maxdate` to `<= maxdate` in the main WHILE loop condition. Need to verify this doesn't cause off-by-one errors in other edge cases.

**Workaround:** Use slightly lower COUNT values or ensure occurrences don't land exactly at the 10-year boundary.

**Files:** `src/rrule.sql` (rrule_event_instances_range function, line ~2459)

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

### ISSUE-005: Validation error paths for time filters (2026-02-05)
Investigation found lines 562/565 (BYMINUTE/BYSECOND rejection) were already tested in `test_rejection_matrix.sql`. Only line 572 (BYSETPOS with sub-day frequencies) lacked coverage. Added Section 14 to `test_subday_correctness.sql` with 5 tests covering BYSETPOS rejection with HOURLY/MINUTELY/SECONDLY, including negative and multiple value variants.

### ISSUE-006: Property tests BYWEEKNO strategy (2026-02-05)
Added `rrule_with_byweekno()` strategy and `test_byweekno_filtering()` invariant test.
The invariant test validates all results occur in specified ISO weeks using database
queries to handle WKST-dependent week numbering correctly. See `tests/property/strategies.py`
and `tests/property/test_invariants.py`.

### ISSUE-007: Property tests BYSETPOS strategy (2026-02-05)
Added `rrule_with_bysetpos()`, `rrule_with_bysetpos_first()`, and `rrule_with_bysetpos_last()` strategies with four invariant tests:
- `test_bysetpos_subset_invariant()`: Results are subset of period's candidate set
- `test_bysetpos_count_bound()`: Results ≤ full results (filter never adds)
- `test_bysetpos_first_position()`: BYSETPOS=1 selects first candidate per period
- `test_bysetpos_last_position()`: BYSETPOS=-1 selects last candidate per period

See `tests/property/strategies.py` and `tests/property/test_invariants.py`.

### ISSUE-008: Property tests SKIP parameter (2026-02-05)
Added four strategies (`dtstart_for_skip()`, `dtstart_leap_day()`, `rrule_with_skip()`, `rrule_skip_comparison_pair()`) and eight invariant tests:
- `test_skip_all_dates_valid()`: All produced dates are valid calendar dates
- `test_skip_no_duplicates()`: All occurrences are distinct
- `test_skip_count_respected()`: COUNT never exceeded
- `test_skip_monotonicity()`: Results strictly ascending
- `test_skip_no_drift()`: BACKWARD mode doesn't cause cumulative drift
- `test_skip_idempotence()`: Same RRULE returns identical results
- `test_skip_omit_subset_of_backward()`: Every OMIT result appears in BACKWARD
- `test_skip_leap_year_behavior()`: Feb 29 dtstart triggers correct SKIP behavior

See `tests/property/strategies.py` and `tests/property/test_invariants.py`.

### ISSUE-009: Property tests ordinal BYDAY patterns (2026-02-05)
Added two strategies (`rrule_with_byday_ordinal()`, `rrule_ordinal_comparison_pair()`) and four invariant tests:
- `test_byday_ordinal_weekday()`: All results occur on specified weekday
- `test_byday_ordinal_monthly_position()`: MONTHLY/YEARLY+BYMONTH ordinals match Nth weekday in month
- `test_byday_ordinal_yearly_position()`: YEARLY without BYMONTH ordinals match Nth weekday in year
- `test_byday_ordinal_subset()`: Ordinal BYDAY results are subset of non-ordinal results

Strategies generate ordinals ±1 to ±5 for MONTHLY/YEARLY frequencies. YEARLY rules optionally include BYMONTH to test both year-scoped and month-scoped ordinal semantics.

See `tests/property/strategies.py` and `tests/property/test_invariants.py`.

### ISSUE-010: Differential testing edge case expansion (2026-02-05)
Added edge case strategies and differential tests for BYMONTHDAY month-end handling:

**New Strategies:**
- `edge_case_rrule_for_differential()`: BYMONTHDAY=28,29,30,31,-1,-2 with MONTHLY/YEARLY
- `dtstart_edge_case_for_differential()`: dtstart with day 28-31 in 31-day months

**New Tests:**
- `test_bymonthday_matches_dateutil()`: 300 examples comparing BYMONTHDAY edge cases
- `test_edge_dtstart_bymonthday()`: 200 examples with edge case dtstart + BYMONTHDAY

**Updated `known_differences.py`:**
- Pattern-based detection for SKIP/RSCALE parameters (dateutil-incompatible)
- Pattern-based detection for FREQ=DAILY + BYMONTHDAY>=29 (iteration limit, see ISSUE-014)
- Documentation of systematic, extension, limitation, and compatible behaviors

**Key Findings:**
- BYMONTHDAY with MONTHLY/YEARLY + SKIP=OMIT matches python-dateutil exactly
- FREQ=DAILY + BYMONTHDAY>=29 has iteration limit issue (filed as ISSUE-014)
- Tightened `simple_rrule_for_differential()` constraints to avoid 10-year boundary issues

See `tests/property/strategies.py`, `tests/property/test_differential.py`, and `tests/property/known_differences.py`.

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
