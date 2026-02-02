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

## Issue 13: BYDAY uses array_remove for empty strings but other BYxxx parameters do not

**Category:** Input Validation
**Severity Assessment:** Low
**Reports:** 1

Only BYDAY parsing uses `array_remove(result, '')` to clean up empty strings from `string_to_array` (handling trailing commas like `BYDAY=MO,TU,`). BYMONTH, BYMONTHDAY, BYYEARDAY, BYWEEKNO, BYSETPOS, BYHOUR, BYMINUTE, BYSECOND do not apply the same cleanup. A trailing comma in these parameters produces an empty string element that causes a cast error or validation failure with a confusing message.

**Location:** `src/rrule.sql:154-162` (BYDAY parsing with array_remove) vs lines 163-246 (other BYxxx parsing without).

**Fix:** 8 edits in `src/rrule.sql` + tests in `tests/test_validation.sql`

---

## Issue 19: overlaps() false-positive with duration-expanded adjusted_mindate for single events

**Category:** Functional Correctness
**Severity Assessment:** Medium
**Reports:** 1

Both `overlaps()` functions (TIMESTAMP and TIMESTAMPTZ) apply the duration-expanded `adjusted_mindate` to the single-event NULL-rrule check. This causes false-positive overlap detection when the event ends before the query window but the gap is smaller than the event duration. Example: Event [Jan 1, Jan 10] (9-day duration), query range [Jan 11, Jan 20]: `adjusted_mindate = Jan 2` (Jan 11 - 9 days). Check yields `dtstart(Jan 1) < maxdate(Jan 20) AND dtend(Jan 10) >= adjusted_mindate(Jan 2) = TRUE`, but the event does not actually overlap the range.

**Location:** `src/rrule.sql:2655` and `src/rrule.sql:3501`.

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`

---

## Issue 23: installManual.sh does not handle rrule_subday.sql

**Category:** Upgrade & Install
**Severity Assessment:** Medium
**Reports:** 1

The manual migration script only pipes `rrule.sql` through sed and psql. There is no handling of `rrule_subday.sql`. Users who had `install_with_subday.sql` installed and follow the manual migration path silently lose sub-day frequency support.

**Location:** `src/installManual.sh:48-52`.

**Fix:** 1 edit in `src/installManual.sh` + update MANUAL_MIGRATION.md

---

## Issue 24: monthly_set BYWEEKNO filter does not normalize negative week numbers

**Category:** Cross-Cutting Concerns
**Severity Assessment:** Medium
**Reports:** 1

`monthly_set` line 1546 compares `get_week_number()` (returns positive 1-53) directly against `rule.byweekno` using `= ANY()`, but `rule.byweekno` can contain negative values (e.g., BYWEEKNO=-1 for last week of year). `daily_set` (line 1420) and `weekly_set` (line 1484) both use `byweekno_matches()` / `byweekno_matches_for_year()` which normalize negatives. `FREQ=MONTHLY;BYWEEKNO=-1` silently returns no results.

**Location:** `src/rrule.sql:1544-1548` (monthly_set function).

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_wkst_support.sql`

---

## Issue 25: after() maxdate anchored to dtstart+10y instead of after_date+10y

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Medium
**Reports:** 1

Both TIMESTAMP and TIMESTAMPTZ `after()` cap the generator maxdate at `dtstart + 10 years`, not `after_date + 10 years`. For rules with COUNT > 10 (e.g., `FREQ=YEARLY;COUNT=20`), calling `after(rule, dtstart, after_date)` where after_date is more than 10 years from dtstart silently returns NULL instead of the correct occurrence.

**Location:** `src/rrule.sql:2438` (TIMESTAMP after), `src/rrule.sql:3209` (TIMESTAMPTZ after).

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`

---

## Issue 26: Subday TZ generator ELSE branch provides generic error message

**Category:** Dual-Path Consistency
**Severity Assessment:** Low
**Reports:** 2

The subday TZ generator (line 778) says only `'Unsupported frequency: %'` without enumerating valid frequencies, while the other three generators provide frequency-specific guidance (valid values list or sub-day install hint).

**Location:** `src/rrule_subday.sql:778`.

**Fix:** 1 edit in `src/rrule_subday.sql`

---

## Issue 27: SKIP regex is case-sensitive, lowercase values rejected instead of accepted

**Category:** Input Validation
**Severity Assessment:** Low
**Reports:** 1

The SKIP regex `SKIP=(OMIT|BACKWARD|FORWARD)` is case-sensitive. `SKIP=backward` fails the regex, defaults to 'OMIT', then the parse-failure check detects the mismatch and raises "Invalid SKIP value". This is an explicit rejection (not silent corruption), but RFC 7529 does not specify case sensitivity for SKIP values.

**Location:** `src/rrule.sql:145`.

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_validation.sql`

---

## Issue 29: SKIP=FORWARD drift loop does not increment period_count

**Category:** Safety & Security
**Severity Assessment:** Low
**Reports:** 1

In MONTHLY/YEARLY generators, the SKIP=FORWARD path advances the date without incrementing `period_count`, while SKIP=OMIT does increment it. This weakens DoS protection for FORWARD rules, allowing more iterations than `period_limit` intends.

**Location:** `src/rrule.sql:2080-2101` (MONTHLY FORWARD), `src/rrule.sql:2154-2178` (YEARLY FORWARD), and equivalents in all 4 generators.

**Fix:** 8 edits in `src/rrule.sql`, `src/rrule_subday.sql` + append to `tests/test_skip_support.sql`

---

## Issue 30: Error message references psql-specific install path for npm users

**Category:** Upgrade & Install
**Severity Assessment:** Low
**Reports:** 1

The RAISE EXCEPTION message for sub-day frequencies says "use: psql -d your_database -f src/install_with_subday.sql" which is inaccessible to npm users. Should mention `SQL.installWithSubday` as an alternative.

**Location:** `src/rrule.sql:2960`.

**Fix:** 1 edit in `src/rrule.sql`

---

## Issue 31: before() max_count=50M allows excessive iteration budget

**Category:** Safety & Security
**Severity Assessment:** Low
**Reports:** 1

The TIMESTAMP `before()` function passes `max_count=50000000` to the generator, resulting in `calculate_safe_iteration_limit` returning up to 2 billion for DAILY frequency. While the maxdate bound prevents unbounded scanning, a far-future before_date with an unbounded DAILY rule could generate significant CPU load.

**Location:** `src/rrule.sql:2525` (TIMESTAMP before), `src/rrule.sql:3311` (TIMESTAMPTZ before).

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`
