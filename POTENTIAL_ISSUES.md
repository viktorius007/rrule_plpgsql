# Potential Issues

Issues identified by audit agents during production readiness review. An issue qualifies for fixing when its report count meets the severity threshold:

| Severity | Reports needed |
|----------|---------------|
| Critical | 1             |
| High     | 1             |
| Medium   | 2             |
| Low      | 3             |

## Format

Each issue includes: description, category, severity assessment, agent analysis summary, and number of independent reports.

---

## Issue 1: SKIP=OMIT inner loop missing maxdate/UNTIL boundary check

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Medium-High
**Reports:** 1
**Status:** Resolved in commit 6c4c39e

The SKIP=OMIT inner loop in MONTHLY/YEARLY branches advances `current_base` by INTERVAL repeatedly but only checks `period_count >= period_limit`. It does NOT check `current_base >= maxdate` or `rule.until`, meaning the loop can advance far beyond the requested date range before exiting. The SKIP=FORWARD branch does check these boundaries.

**Location:** `src/rrule.sql` lines 2044-2053 (MONTHLY), lines 2114-2125 (YEARLY), and equivalent in `src/rrule_subday.sql` and TZ generators.

**Note:** The outer loop catches these conditions immediately after the inner loop exits, so this is primarily a performance issue (wasted iterations) rather than a correctness bug.

---

## Issue 2: UNTIL before dtstart - no early exit optimization

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Medium
**Reports:** 4
**Status:** Resolved in commit 0d1e439

When `UNTIL < dtstart`, the generators enter the main loop and execute at least one period before checking the UNTIL condition. Adding an early-exit check (`IF rule.until IS NOT NULL AND rule.until < basedate THEN RETURN; END IF;`) would avoid unnecessary computation. Affects all 4 generators (TIMESTAMP, TZ, subday TIMESTAMP, subday TZ).

**Location:** `src/rrule.sql` `rrule_event_instances_range()` and `rrule_event_instances_range_tz()`, `src/rrule_subday.sql` equivalents.

**Note:** This is a performance optimization, not a correctness bug. The generators will correctly return an empty set, just less efficiently.

---

## Issue 3: between() does not enforce 10-year window when user specifies wide range

**Category:** Safety & Security
**Severity Assessment:** Medium
**Reports:** 2

The `between()` function passes user-provided start_date and end_date directly to the internal generator without clamping to a 10-year window. A user can request `between(rrule, dtstart, '2020-01-01', '2070-01-01')` and scan 50 years. The 1000-result cap still applies, but the generator may scan many more periods for sparse rules.

**Location:** `src/rrule.sql` TIMESTAMP `between()` (~line 2344) and TIMESTAMPTZ `between()` (~line 3058).

**Note:** This is by design for `between()` (users explicitly specify their range), but could be a DoS vector for sparse rules. The iteration limit provides some protection.

---

## Issue 4: before() TIMESTAMPTZ uses array accumulation instead of efficient query

**Category:** Safety & Security
**Severity Assessment:** Medium
**Reports:** 3

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
**Reports:** 3
**Status:** Resolved in commit dd434bd

All BYSETPOS tests use the TIMESTAMP API. No tests verify BYSETPOS behavior through the TIMESTAMPTZ API during DST transitions (spring forward gaps, fall back overlaps). The architecture is sound (TZ conversion happens at the outermost layer, after BYSETPOS), but this is untested.

**Location:** `tests/test_bysetpos.sql` (all TIMESTAMP), `tests/test_tz_api.sql` (no BYSETPOS).

**Resolution:** Added 3 BYSETPOS+TIMESTAMPTZ DST tests in `tests/test_dual_path_consistency.sql`.

---

## Issue 7: Variable declaration asymmetry in subday TIMESTAMP generator

**Category:** Dual-Path Consistency
**Severity Assessment:** Low
**Reports:** 1
**Status:** RESOLVED (fix/finding-5-subday-type-decl)

The subday TIMESTAMP generator declares `rule rrule.rrule_parts;` (no %ROWTYPE) and uses `:=` assignment, while the other 3 generators use `rule rrule.rrule_parts%ROWTYPE;` with `SELECT * INTO`. This works because `rrule_parts` is a TYPE, but the inconsistency creates maintenance confusion.

**Location:** `src/rrule_subday.sql` line 220 (declaration) and line 222 (assignment).

**Resolution:** Normalized to `rule rrule.rrule_parts%ROWTYPE;` with `SELECT * INTO rule FROM rrule.parse_rrule_parts(...)` to match the other 3 generators.

---

## Issue 8: Year boundary BYWEEKNO cross-year handling untested for multi-year rules

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Medium
**Reports:** 4
**Status:** Resolved in commit dd434bd

ISO 8601 Week 1 can start in late December of the previous year. The `rrule_yearly_byweekno_set()` function is tested for single years, but no multi-year YEARLY loop test exists for BYWEEKNO to verify the year-advancement loop handles cross-year weeks correctly.

**Location:** `src/rrule.sql` `rrule_yearly_byweekno_set()` and YEARLY loop.

**Resolution:** Added 6 multi-year BYWEEKNO tests in `tests/test_dual_path_consistency.sql` covering BYWEEKNO=1 COUNT=5, BYWEEKNO=53 COUNT=3, and INTERVAL=2.

---

## Issue 9: Stale `current` value in outer loop UNTIL exit check

**Category:** Safety & Security
**Severity Assessment:** Low
**Reports:** 4
**Status:** Resolved in commit 0d1e439

If a frequency set function returns zero results for a period, `current` retains its previous value. The outer loop exit condition `EXIT WHEN rule.until IS NOT NULL AND current IS NOT NULL AND current > rule.until` then checks a stale value. This doesn't cause incorrect results (other exit conditions prevent runaway), but wastes iterations when the rule has exceeded UNTIL but the last non-empty period was before UNTIL.

**Location:** `src/rrule.sql` line 2182, `src/rrule_subday.sql` line 463.

**Resolution:** Changed outer loop UNTIL exit to use `current_base` instead of `current` in all 4 generators.

---

## Issue 10: npm SQL.install contains BEGIN/COMMIT that breaks outer transaction control

**Category:** Integration & Real-World Usage
**Severity Assessment:** Critical
**Reports:** 1
**Status:** Resolved in commit 8cef4f6

The npm package exports `SQL.install` and `SQL.installWithSubday` with embedded `BEGIN;` and `COMMIT;` statements from the install scripts. When driver users wrap installation in their own transaction (as documented in INSTALLATION.md), the inner `COMMIT` commits the outer transaction prematurely. If an error occurs after install completes but before the user's intended `COMMIT`, the schema changes are already committed and cannot be rolled back. The `SQL.core` export does not have this issue.

**Location:** `index.js` `buildDriverSafeSQL()` function, `src/install.sql:27,186`, `src/install_with_subday.sql:46,186`.

**Resolution:** `buildDriverSafeSQL()` now strips standalone BEGIN/COMMIT and RESET statements from driver-safe output.

---

## Issue 11: BYMONTH filter missing in YEARLY+BYWEEKNO primary generator path

**Category:** Functional Correctness
**Severity Assessment:** High
**Reports:** 1
**Status:** Resolved in commit 1af5794

The `yearly_set()` function's BYWEEKNO-primary code path (lines 1841-1852) applies WHERE-clause filters for BYYEARDAY, BYMONTHDAY, and BYDAY, but is missing a filter for BYMONTH. When `FREQ=YEARLY;BYWEEKNO=10;BYMONTH=6` is evaluated, `rrule_yearly_byweekno_set()` generates all dates in ISO week 10 (typically March), but the BYMONTH=6 filter is never applied. Per RFC 5545 intersection semantics, this should return 0 results.

**Location:** `src/rrule.sql` `yearly_set()` lines 1841-1852.

**Resolution:** Added `test_bymonth_rule()` filter to BYWEEKNO-primary path and updated max_results NULL propagation. Added 3 tests in `tests/test_coverage_gaps.sql`.

---

## Issue 12: NULL count parameter not validated in TIMESTAMPTZ after() and before()

**Category:** API Contract
**Severity Assessment:** High
**Severity Range:** Medium-High from 3 reports
**Reports:** 3
**Status:** Resolved in commit b52eb30

The TIMESTAMPTZ `after()` and `before()` functions accept a `count` parameter with no DEFAULT value. The validation only checks `count <= 0` but not `count IS NULL`. When NULL is passed:
- `after()`: The exit condition `EXIT WHEN occurrence_count >= count` evaluates to NULL, never triggering. The function returns up to 1000 results instead of raising an error.
- `before()`: The array trimming condition `IF array_length(results, 1) > count` evaluates to NULL, preventing trimming and allowing unbounded memory growth up to the iteration limit.

**Location:** `src/rrule.sql` lines 3148 (after validation), 3181 (after exit), 3231 (before validation), 3269 (before trim).

**Resolution:** Added explicit NULL check raising exception in both functions. Added 2 tests in `tests/test_tz_api.sql`.

---

## Issue 13: TIMESTAMP vs TIMESTAMPTZ API signature incompatibility for after()/before()

**Category:** Dual-Path Consistency
**Severity Assessment:** High
**Severity Range:** Medium-High from 3 reports
**Reports:** 3

The TIMESTAMP and TIMESTAMPTZ APIs have fundamentally different signatures for `after()` and `before()`:
- TIMESTAMP `after(rrule, dtstart, after_date, inc)` returns a single TIMESTAMP
- TIMESTAMPTZ `after(rrule, dtstart, after_date, count, timezone, inc)` returns SETOF TIMESTAMPTZ

This breaks API parity. Users cannot easily switch between APIs. Code using positional arguments like `after(rrule, dt, dt2, true)` means "inclusive boundary" for TIMESTAMP but "return 1 result (true→1)" for TIMESTAMPTZ.

**Location:** `src/rrule.sql` lines 2377-2429 (TIMESTAMP) vs 3112-3184 (TIMESTAMPTZ), and similarly for `before()`.

**Note:** This is a design decision, not a runtime bug. The TIMESTAMPTZ versions intentionally return SETOF with a count parameter. Changing this would be a breaking API change.

---

## Issue 14: No cross-validation tests between TIMESTAMP and TIMESTAMPTZ APIs

**Category:** Dual-Path Consistency
**Severity Assessment:** Medium
**Reports:** 2
**Status:** Resolved in commit dd434bd

No tests verify that the TIMESTAMP API (with `TZID=` in string) produces equivalent results to the TIMESTAMPTZ API (with explicit timezone parameter) for the same rule and timezone. The two paths use completely different generators (`rrule_event_instances_range()` vs `rrule_event_instances_range_tz()`), so divergence is plausible but undetected.

**Location:** `tests/` (no cross-API comparison tests exist).

**Resolution:** Added 8 cross-API parity tests in `tests/test_dual_path_consistency.sql` covering DAILY/WEEKLY/MONTHLY with and without DST transitions.

---

## Issue 15: Inconsistent NULL check in TIMESTAMPTZ generators vs TIMESTAMP generators

**Category:** Dual-Path Consistency
**Severity Assessment:** Medium
**Severity Range:** Low-Medium from 2 reports
**Reports:** 2

The subday TIMESTAMPTZ generator includes `current IS NOT NULL AND` in UNTIL exit conditions, while the standard TIMESTAMPTZ generator and TIMESTAMP generators do not include this guard. While `current` should never be NULL inside a FOR loop iterating over set-returning function results, the inconsistency indicates the four generators diverged from a common template (violating Development Rule #9).

**Location:** `src/rrule.sql` lines 1987, 2006, 2029, 2099 (TIMESTAMP) vs `src/rrule_subday.sql` lines 535, 560, 589 (subday TZ includes guard).

---

## Issue 16: WEEKLY frequency passes max_results before post-filters

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Medium
**Reports:** 1

The WEEKLY branch in the generators calls `weekly_set(current_base, rule, CASE WHEN output_limit IS NULL THEN NULL ELSE GREATEST(output_limit - emitted_count, 0) END)` and then applies BYYEARDAY/BYMONTHDAY/BYMONTH post-filters via `test_byyearday_rule`, `test_bymonthday_rule`, `test_bymonth_rule`. This violates Development Rule #11: "Never limit candidate generation before post-filters." If `weekly_set` generates N candidates hitting its limit, but post-filters reject most, fewer results than requested are returned.

**Location:** `src/rrule.sql` lines 2001-2004 (and equivalents in all 4 generators).

**Note:** Same pattern exists for DAILY branch. The fix would be to pass NULL for max_results when any post-filters are present (matching the yearly_set pattern).

---

## Issue 17: No BYSETPOS + SKIP interaction test coverage

**Category:** Cross-Cutting Concerns
**Severity Assessment:** Medium
**Reports:** 1

No tests verify BYSETPOS behavior when SKIP=FORWARD or SKIP=BACKWARD produce dates that overlap with other BYxxx rules. For example, `FREQ=MONTHLY;BYMONTHDAY=30,31;SKIP=FORWARD;BYSETPOS=1,-1` could produce duplicate forwarded dates that affect BYSETPOS position selection. BYSETPOS position selection depends on input cardinality — if duplicates aren't properly removed before BYSETPOS, position indices will be off.

**Location:** `tests/` (no BYSETPOS + SKIP combination tests).

---

## Issue 18: NULL date range parameters not validated in between()/after()/before()

**Category:** Input Validation
**Severity Assessment:** Medium
**Reports:** 1

The `between()`, `after()`, and `before()` functions validate NULL for `rrule_string` and `dtstart` but NOT for date range parameters (`start_date`/`end_date`, `after_date`, `before_date`). Passing NULL produces confusing behavior (empty results or PostgreSQL cast errors) without a descriptive error message.

**Location:** `src/rrule.sql` lines 2315-2368 (between TIMESTAMP), 2377-2428 (after TIMESTAMP), 2438-2509 (before TIMESTAMP), and TIMESTAMPTZ equivalents.

**Note:** PostgreSQL handles NULL gracefully (comparisons with NULL return NULL, preventing matches), so results are technically correct (empty set). The gap is user experience, not correctness.

---

## Issue 19: overlaps() has no TIMESTAMP API variant

**Category:** Integration & Real-World Usage
**Severity Assessment:** High
**Reports:** 1

All other public API functions (`all`, `between`, `after`, `before`, `count`, `next`, `most_recent`) have both TIMESTAMP and TIMESTAMPTZ overloads. The `overlaps()` function only accepts TIMESTAMPTZ parameters. Users of the TIMESTAMP API must cast values to use `overlaps()`.

**Location:** `src/rrule.sql` lines 2592-2636.

**Note:** This is a feature gap, not a runtime bug. Users have a workaround (cast to TIMESTAMPTZ).

---

## Issue 20: npm buildDriverSafeSQL strips all backslash-prefixed lines

**Category:** Integration & Real-World Usage
**Severity Assessment:** Medium
**Reports:** 1

The `buildDriverSafeSQL()` function in `index.js` uses `trimmed.startsWith('\\')` to strip lines, removing any line starting with a backslash. While this works for current code (only psql meta-commands like `\ir`, `\set`, `\echo` start with backslash), it's fragile. Future SQL containing escaped string literals at line start (e.g., `E'\\n...'`) would be incorrectly stripped.

**Location:** `index.js` line 39.

**Note:** No current SQL files trigger this. A safer approach would be to explicitly match known meta-commands.
