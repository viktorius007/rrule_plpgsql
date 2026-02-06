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
| `REQUIRES VERIFICATION` | Needs independent verification that the issue doesn't exist |
| `DEFERRED` | Intentionally postponed |

---

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

### ISSUE-003: BYWEEKNO functions profiler coverage (2026-02-06)
**VERIFIED AS TESTING GAP - FIXED.** The original hypothesis (plan-time optimization of IMMUTABLE functions) was **incorrect**.

**Actual Root Cause:** The profiler script's test workload was missing the `BYMONTH+BYWEEKNO` code path. The BYWEEKNO functions have two usage patterns:
1. **Primary generator** (`rrule_yearly_byweekno_set`): When only BYWEEKNO is present, the set function iterates through `rule.byweekno` directly without calling `byweekno_matches()`.
2. **Filter path** (`yearly_set` → WHERE clause): When `BYMONTH+BYWEEKNO` is present, `byweekno_matches_for_year()` is called as a WHERE filter, which then calls `byweekno_matches()`.

**Verification Experiment:**
```sql
-- Pure BYWEEKNO (profiler shows 0% for byweekno_matches)
PERFORM rrule."all"('FREQ=YEARLY;BYWEEKNO=1;COUNT=5', '2025-01-06'::TIMESTAMP);

-- BYMONTH+BYWEEKNO (profiler shows executions for all BYWEEKNO functions)
PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=1;BYWEEKNO=1;COUNT=5', '2025-01-06'::TIMESTAMP);
```

**Fix Applied:** Added `BYMONTH+BYWEEKNO` test cases to `scripts/profiler-coverage.sh` Section 7 to exercise the filter path. Coverage now shows:
- `byweekno_matches()`: 22+ executions
- `byweekno_matches_for_year()`: 22+ executions
- `get_week_info()`: 22+ executions

**Disproving the IMMUTABLE Hypothesis:** Direct SELECT calls to `byweekno_matches()` with constants DO show profiler coverage, proving PostgreSQL does NOT optimize IMMUTABLE PL/pgSQL functions at plan time (unlike SQL functions).

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
- Documentation of systematic, extension, limitation, and compatible behaviors

**Key Findings:**
- BYMONTHDAY with MONTHLY/YEARLY + SKIP=OMIT matches python-dateutil exactly
- ~~FREQ=DAILY + BYMONTHDAY>=29 had iteration limit issue~~ (fixed in ISSUE-014)
- Tightened `simple_rrule_for_differential()` constraints to avoid 10-year boundary issues

See `tests/property/strategies.py`, `tests/property/test_differential.py`, and `tests/property/known_differences.py`.

### ISSUE-011: Feb 29 handling comprehensive testing (2026-02-05)
Added TEST GROUP 13 to `tests/test_skip_support.sql` with 5 tests for MONTHLY frequency starting Feb 29:
- MONTHLY SKIP=BACKWARD from Feb 29 2024 (COUNT=13, hits Feb 2025 → Feb 28)
- MONTHLY SKIP=FORWARD from Feb 29 2024 (COUNT=13, hits Feb 2025 → Mar 1)
- MONTHLY SKIP=OMIT from Feb 29 2024 (COUNT=12, skips Feb 2025)
- MONTHLY INTERVAL=2 SKIP=BACKWARD from Feb 29
- YEARLY SKIP=FORWARD UNTIL exactly on day before forwarded date

The existing YEARLY + Feb 29 tests (16+ tests) were already comprehensive.

### ISSUE-012: Negative BYWEEKNO systematic testing (2026-02-05)
Added TEST GROUP 11 to `tests/test_wkst_support.sql` with 7 tests:
- BYWEEKNO=-2 (second-to-last week)
- BYWEEKNO=-26 (middle from end)
- BYWEEKNO=-52 (first or second week depending on year)
- BYWEEKNO=-1,-52 (last and near-first together)
- YEARLY;INTERVAL=2;BYWEEKNO=-1 (last week every 2 years)
- BYWEEKNO=-1 across 52/53 week year types
- Mixed positive and negative BYWEEKNO=1,-1

Also updated property test strategies to include negative BYWEEKNO values (-52 to -1).

### ISSUE-014: DAILY + BYMONTHDAY iteration limit fix (2026-02-05)
Increased DAILY multiplier in `calculate_safe_iteration_limit()` from 40 to 62 to handle worst-case BYMONTHDAY=31 gaps (Feb 1 → Mar 31 = 58 days). Added regression tests in `tests/test_iteration_limits.sql` and removed workaround from `known_differences.py`.

### ISSUE-015: 10-year boundary inclusion fix (2026-02-05)
Changed `current_base < maxdate` to `current_base <= maxdate` in all 4 generator WHILE loops to include occurrences that land exactly at the 10-year boundary. Added regression tests in `tests/test_iteration_limits.sql`.

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
