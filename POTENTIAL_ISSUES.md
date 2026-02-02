# Potential Issues

Issues identified by audit agents during production readiness review. An issue qualifies for fixing when its report count meets the severity threshold:

| Severity | Reports needed |
|----------|---------------|
| Critical | 1             |
| High     | 1             |
| Medium   | 2             |
| Low      | 3             |

## Format

Each issue includes: description, category, severity assessment, agent analysis summary, and number of independent reports. Resolved issues are removed — the fix commit serves as the permanent record.

---

## Issue 1: between() does not enforce 10-year window when user specifies wide range

**Category:** Safety & Security
**Severity Assessment:** Medium
**Reports:** 2

The `between()` function passes user-provided start_date and end_date directly to the internal generator without clamping to a 10-year window. A user can request `between(rrule, dtstart, '2020-01-01', '2070-01-01')` and scan 50 years. The 1000-result cap still applies, but the generator may scan many more periods for sparse rules.

**Location:** `src/rrule.sql` TIMESTAMP `between()` (~line 2344) and TIMESTAMPTZ `between()` (~line 3058).

**Note:** This is by design for `between()` (users explicitly specify their range), but could be a DoS vector for sparse rules. The iteration limit provides some protection.

---

## Issue 2: before() TIMESTAMPTZ uses array accumulation instead of efficient query

**Category:** Safety & Security
**Severity Assessment:** Medium
**Reports:** 3

The TIMESTAMPTZ `before()` function accumulates ALL occurrences in an array with sliding window, while the TIMESTAMP `before()` uses efficient `ORDER BY DESC LIMIT`. For rules with many occurrences before the target date, this causes O(N) memory and array operations.

**Location:** `src/rrule.sql` TIMESTAMPTZ `before()` (~lines 3215-3238).

**Note:** Mitigated by the period_limit in the generator. The TIMESTAMP API version does not have this issue.

---

## Issue 3: TIMESTAMP vs TIMESTAMPTZ API signature incompatibility for after()/before()/next()/most_recent()

**Category:** Dual-Path Consistency
**Severity Assessment:** High
**Severity Range:** Medium-High from 9 reports
**Reports:** 9

The TIMESTAMP and TIMESTAMPTZ APIs have fundamentally different signatures for `after()`, `before()`, `next()`, and `most_recent()`:
- TIMESTAMP `after(rrule, dtstart, after_date, inc)` returns a single TIMESTAMP
- TIMESTAMPTZ `after(rrule, dtstart, after_date, count, timezone, inc)` returns SETOF TIMESTAMPTZ
- TIMESTAMP `next(rrule, dtstart, reference_time)` — 3rd param is reference_time
- TIMESTAMPTZ `next(rrule, dtstart, timezone, reference_time)` — 3rd param is timezone

This breaks API parity. Users cannot easily switch between APIs. Code using positional arguments like `after(rrule, dt, dt2, true)` means "inclusive boundary" for TIMESTAMP but "return 1 result (true->1)" for TIMESTAMPTZ. Same issue for `next()` and `most_recent()` where the 3rd parameter changes meaning between APIs.

**Location:** `src/rrule.sql` lines 2377-2429 (TIMESTAMP after) vs 3112-3184 (TIMESTAMPTZ after), lines 2552-2565 (TIMESTAMP next) vs 3334-3366 (TIMESTAMPTZ next), and similarly for `before()` and `most_recent()`.

**Note:** This is a design decision, not a runtime bug. The TIMESTAMPTZ versions intentionally return SETOF with a count parameter. Changing this would be a breaking API change.

---

## Issue 4: Inconsistent NULL check in TIMESTAMPTZ generators vs TIMESTAMP generators

**Category:** Dual-Path Consistency
**Severity Assessment:** Medium
**Severity Range:** Low-Medium from 7 reports
**Reports:** 7

The subday TIMESTAMPTZ generator includes `current IS NOT NULL AND` in UNTIL exit conditions, while the standard TIMESTAMPTZ generator and TIMESTAMP generators do not include this guard. While `current` should never be NULL inside a FOR loop iterating over set-returning function results, the inconsistency indicates the four generators diverged from a common template (violating Development Rule #9).

**Location:** `src/rrule.sql` lines 1987, 2006, 2029, 2099 (TIMESTAMP) vs `src/rrule_subday.sql` lines 535, 560, 589, 631, 665, 703, 733, 749, 765 (subday TZ includes guard).

**Fix:** 9 edits in `src/rrule_subday.sql` (remove redundant NULL checks to align with standard generators)

---

## Issue 5: WEEKLY/DAILY frequency passes max_results before post-filters causing missing results

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** High
**Severity Range:** Medium-High from 5 reports
**Reports:** 5

The WEEKLY branch in the generators calls `weekly_set(current_base, rule, ...)` with a max_results limit, then applies BYYEARDAY/BYMONTHDAY/BYMONTH post-filters. This violates Development Rule #11. Confirmed as a correctness bug: `FREQ=WEEKLY;BYDAY=SU,MO,TU,WE,TH,FR,SA;BYMONTH=2;COUNT=3` starting 2025-01-27 returns `[Sun Feb 2, Mon Feb 3, Sun Feb 9]` instead of `[Sat Feb 1, Sun Feb 2, Mon Feb 3]` because `rrule_week_byday_set` exits early (max_results=3) before generating Sat Feb 1. Same pattern exists for the DAILY branch. Additionally, `yearly_set` passes max_results to `monthly_set` in the 12-month scan path, but `monthly_set` may apply BYSETPOS internally, creating the same under-generation issue.

**Location:** `src/rrule.sql` lines 2001-2004 (WEEKLY, all 4 generators), daily_set line ~1430, yearly_set line ~1884.

**Fix:** 6 edits in `src/rrule.sql`, `src/rrule_subday.sql` (pass NULL for max_results when post-filters present in WEEKLY/DAILY branches, and pass NULL to monthly_set in yearly_set when BYSETPOS present) + tests in `tests/test_rrule_functions.sql`

---

## Issue 6: No BYSETPOS + SKIP interaction test coverage

**Category:** Cross-Cutting Concerns
**Severity Assessment:** Medium
**Reports:** 2

No tests verify BYSETPOS behavior when SKIP=FORWARD or SKIP=BACKWARD produce dates that overlap with other BYxxx rules. For example, `FREQ=MONTHLY;BYMONTHDAY=30,31;SKIP=FORWARD;BYSETPOS=1,-1` could produce duplicate forwarded dates that affect BYSETPOS position selection. BYSETPOS position selection depends on input cardinality — if duplicates aren't properly removed before BYSETPOS, position indices will be off.

**Location:** `tests/` (no BYSETPOS + SKIP combination tests).

**Fix:** 0 edits in src + new tests in `tests/test_bysetpos.sql` or `tests/test_skip_support.sql`

---

## Issue 7: NULL date range parameters not validated in between()/after()/before()

**Category:** Input Validation
**Severity Assessment:** Medium
**Reports:** 2

The `between()`, `after()`, and `before()` functions validate NULL for `rrule_string` and `dtstart` but NOT for date range parameters (`start_date`/`end_date`, `after_date`, `before_date`). Passing NULL produces confusing behavior (empty results or PostgreSQL cast errors) without a descriptive error message.

**Location:** `src/rrule.sql` lines 2315-2368 (between TIMESTAMP), 2377-2428 (after TIMESTAMP), 2438-2509 (before TIMESTAMP), and TIMESTAMPTZ equivalents.

**Note:** PostgreSQL handles NULL gracefully (comparisons with NULL return NULL, preventing matches), so results are technically correct (empty set). The gap is user experience, not correctness.

**Fix:** 6 edits in `src/rrule.sql` (add NULL checks for date range params in 6 functions) + tests in `tests/test_validation.sql`

---

## Issue 8: overlaps() has no TIMESTAMP API variant

**Category:** Integration & Real-World Usage
**Severity Assessment:** High
**Reports:** 2

All other public API functions (`all`, `between`, `after`, `before`, `count`, `next`, `most_recent`) have both TIMESTAMP and TIMESTAMPTZ overloads. The `overlaps()` function only accepts TIMESTAMPTZ parameters. Users of the TIMESTAMP API must cast values to use `overlaps()`.

**Location:** `src/rrule.sql` lines 2592-2636.

**Note:** This is a feature gap, not a runtime bug. Users have a workaround (cast to TIMESTAMPTZ).

---

## Issue 9: npm buildDriverSafeSQL strips all backslash-prefixed lines

**Category:** Integration & Real-World Usage
**Severity Assessment:** Medium
**Reports:** 1

The `buildDriverSafeSQL()` function in `index.js` uses `trimmed.startsWith('\\')` to strip lines, removing any line starting with a backslash. While this works for current code (only psql meta-commands like `\ir`, `\set`, `\echo` start with backslash), it's fragile. Future SQL containing escaped string literals at line start (e.g., `E'\\n...'`) would be incorrectly stripped.

**Location:** `index.js` line 39.

**Note:** No current SQL files trigger this. A safer approach would be to explicitly match known meta-commands.

---

## Issue 10: CREATE TYPE rrule_parts not idempotent, breaks direct SQL reload

**Category:** Upgrade & Install
**Severity Assessment:** High
**Reports:** 2

`CREATE TYPE rrule_parts` at `src/rrule.sql:48` has no idempotency guard. PostgreSQL does not support `CREATE OR REPLACE TYPE` for composite types, so reloading `rrule.sql` or using `SQL.core` without first dropping the schema fails with "ERROR: type rrule_parts already exists". The `DOMAIN rrule` at line 2230 uses `IF NOT EXISTS`, creating inconsistent reinstall behavior.

**Location:** `src/rrule.sql:48` (CREATE TYPE) vs `src/rrule.sql:2230` (DOMAIN with IF NOT EXISTS).

**Note:** Mitigated by `install.sql` doing `DROP SCHEMA CASCADE` before loading. Only affects direct `rrule.sql` loading or `SQL.core` usage without schema drop.

**Fix:** 1 edit in `src/rrule.sql` (wrap CREATE TYPE in DO block with existence check) + no test needed

---

## Issue 11: npm package strips RESET commands but retains SET commands, risking session state leakage

**Category:** Upgrade & Install
**Severity Assessment:** Medium
**Reports:** 1

`buildDriverSafeSQL()` in `index.js` strips `RESET` commands that follow COMMIT, but `SET timezone` and `SET search_path` commands inside the transaction are retained. In connection-pooled environments, these SET commands persist in the session after installation completes, potentially affecting subsequent queries.

**Location:** `index.js:48-50`.

**Fix:** 1 edit in `index.js` + test

---

## Issue 12: SKIP drift prevention may exhaust period_limit prematurely with large INTERVAL

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Medium
**Reports:** 1

In MONTHLY/YEARLY generators, the SKIP=OMIT loop increments `period_count` multiple times per interval advancement when months are skipped. For rules like `FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=31;SKIP=OMIT`, each skipped month consumes a period count, potentially exhausting `period_limit` before the requested COUNT is reached.

**Location:** `src/rrule.sql:2058-2069, 2130-2143` (and equivalents in all 4 generators).

**Fix:** 4 edits in `src/rrule.sql`, `src/rrule_subday.sql` + test in `tests/test_skip_support.sql` with INTERVAL=2

---

## Issue 13: BYDAY uses array_remove for empty strings but other BYxxx parameters do not

**Category:** Input Validation
**Severity Assessment:** Low
**Reports:** 1

Only BYDAY parsing uses `array_remove(result, '')` to clean up empty strings from `string_to_array` (handling trailing commas like `BYDAY=MO,TU,`). BYMONTH, BYMONTHDAY, BYYEARDAY, BYWEEKNO, BYSETPOS, BYHOUR, BYMINUTE, BYSECOND do not apply the same cleanup. A trailing comma in these parameters produces an empty string element that causes a cast error or validation failure with a confusing message.

**Location:** `src/rrule.sql:154-162` (BYDAY parsing with array_remove) vs lines 163-246 (other BYxxx parsing without).

**Fix:** 8 edits in `src/rrule.sql` + tests in `tests/test_validation.sql`
