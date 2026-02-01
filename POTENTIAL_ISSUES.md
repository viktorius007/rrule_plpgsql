# Potential Issues

Issues identified by single audit agents during production readiness review. These have not reached consensus (2+ independent agents agreeing) but are recorded for future investigation. When an issue is independently reported again, increment its report counter.

## Format

Each issue includes: description, category, severity assessment, agent analysis summary, and number of independent reports.

---

## Issue 1: SKIP=OMIT inner loop missing maxdate/UNTIL boundary check

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Medium-High
**Reports:** 1

The SKIP=OMIT inner loop in MONTHLY/YEARLY branches advances `current_base` by INTERVAL repeatedly but only checks `period_count >= period_limit`. It does NOT check `current_base >= maxdate` or `rule.until`, meaning the loop can advance far beyond the requested date range before exiting. The SKIP=FORWARD branch does check these boundaries.

**Location:** `src/rrule.sql` lines 2044-2053 (MONTHLY), lines 2114-2125 (YEARLY), and equivalent in `src/rrule_subday.sql` and TZ generators.

**Note:** The outer loop catches these conditions immediately after the inner loop exits, so this is primarily a performance issue (wasted iterations) rather than a correctness bug.

---

## Issue 2: UNTIL before dtstart - no early exit optimization

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Medium
**Reports:** 1

When `UNTIL < dtstart`, the generators enter the main loop and execute at least one period before checking the UNTIL condition. Adding an early-exit check (`IF rule.until IS NOT NULL AND rule.until < basedate THEN RETURN; END IF;`) would avoid unnecessary computation.

**Location:** `src/rrule.sql` `rrule_event_instances_range()` and `rrule_event_instances_range_tz()`.

**Note:** This is a performance optimization, not a correctness bug. The generators will correctly return an empty set, just less efficiently.

---

## Issue 3: between() does not enforce 10-year window when user specifies wide range

**Category:** Safety & Security
**Severity Assessment:** Medium
**Reports:** 1

The `between()` function passes user-provided start_date and end_date directly to the internal generator without clamping to a 10-year window. A user can request `between(rrule, dtstart, '2020-01-01', '2070-01-01')` and scan 50 years. The 1000-result cap still applies, but the generator may scan many more periods for sparse rules.

**Location:** `src/rrule.sql` TIMESTAMP `between()` (~line 2344) and TIMESTAMPTZ `between()` (~line 3058).

**Note:** This is by design for `between()` (users explicitly specify their range), but could be a DoS vector for sparse rules. The iteration limit provides some protection.

---

## Issue 4: before() TIMESTAMPTZ uses array accumulation instead of efficient query

**Category:** Safety & Security
**Severity Assessment:** Medium
**Reports:** 1

The TIMESTAMPTZ `before()` function accumulates ALL occurrences in an array with sliding window, while the TIMESTAMP `before()` uses efficient `ORDER BY DESC LIMIT`. For rules with many occurrences before the target date, this causes O(N) memory and array operations.

**Location:** `src/rrule.sql` TIMESTAMPTZ `before()` (~lines 3215-3238).

**Note:** Mitigated by the period_limit in the generator. The TIMESTAMP API version does not have this issue.

---

## Issue 5: ~~Sub-day frequency DoS cap bypassed by large INTERVAL values~~ RESOLVED

**Category:** Safety & Security
**Severity Assessment:** Medium
**Reports:** 1
**Status:** Resolved

The DoS caps for MINUTELY and SECONDLY are now INTERVAL-aware. `calculate_safe_iteration_limit()` accepts an `interval_val` parameter and divides the base cap by the interval value: MINUTELY uses `FLOOR(1440 / interval)` and SECONDLY uses `FLOOR(3600 / interval)`. This ensures the caps represent real time spans (1 day for MINUTELY, 1 hour for SECONDLY) regardless of INTERVAL.

**Fix:** `calculate_safe_iteration_limit()` in `src/rrule.sql`; all 4 callers updated to pass `rule.interval`.

---

## Issue 6: BYSETPOS + TIMESTAMPTZ API has no DST test coverage

**Category:** Dual-Path Consistency
**Severity Assessment:** Medium
**Reports:** 1

All BYSETPOS tests use the TIMESTAMP API. No tests verify BYSETPOS behavior through the TIMESTAMPTZ API during DST transitions (spring forward gaps, fall back overlaps). The architecture is sound (TZ conversion happens at the outermost layer, after BYSETPOS), but this is untested.

**Location:** `tests/test_bysetpos.sql` (all TIMESTAMP), `tests/test_tz_api.sql` (no BYSETPOS).

---

## Issue 7: Variable declaration asymmetry in subday TIMESTAMP generator

**Category:** Dual-Path Consistency
**Severity Assessment:** Low
**Reports:** 1

The subday TIMESTAMP generator declares `rule rrule.rrule_parts;` (no %ROWTYPE) and uses `:=` assignment, while the other 3 generators use `rule rrule.rrule_parts%ROWTYPE;` with `SELECT * INTO`. This works because `rrule_parts` is a TYPE, but the inconsistency creates maintenance confusion.

**Location:** `src/rrule_subday.sql` line 220 (declaration) and line 222 (assignment).

---

## Issue 8: Year boundary BYWEEKNO cross-year handling untested for multi-year rules

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Medium
**Reports:** 1

ISO 8601 Week 1 can start in late December of the previous year. The `rrule_yearly_byweekno_set()` function is tested for single years, but no multi-year YEARLY loop test exists for BYWEEKNO to verify the year-advancement loop handles cross-year weeks correctly.

**Location:** `src/rrule.sql` `rrule_yearly_byweekno_set()` and YEARLY loop.

---

## Issue 9: Stale `current` value in outer loop UNTIL exit check

**Category:** Safety & Security
**Severity Assessment:** Low
**Reports:** 1

If a frequency set function returns zero results for a period, `current` retains its previous value. The outer loop exit condition `EXIT WHEN rule.until IS NOT NULL AND current IS NOT NULL AND current > rule.until` then checks a stale value. This doesn't cause incorrect results (other exit conditions prevent runaway), but wastes iterations when the rule has exceeded UNTIL but the last non-empty period was before UNTIL.

**Location:** `src/rrule.sql` line 2182, `src/rrule_subday.sql` line 463.
