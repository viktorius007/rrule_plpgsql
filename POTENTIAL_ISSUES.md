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

## Issue 11: npm package strips RESET commands but retains SET commands, risking session state leakage

**Category:** Upgrade & Install
**Severity Assessment:** Medium
**Reports:** 3

`buildDriverSafeSQL()` in `index.js` strips `RESET` commands that follow COMMIT, but `SET timezone` and `SET search_path` commands inside the transaction are retained. In connection-pooled environments, these SET commands persist in the session after installation completes, potentially affecting subsequent queries.

**Location:** `index.js:48-50`.

**Fix:** 1 edit in `index.js` + test

---

## Issue 12: SKIP drift prevention may exhaust period_limit prematurely with large INTERVAL

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Medium
**Reports:** 2

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

---

## Issue 14: TIMESTAMP after() passes max_count=2 causing insufficient period_limit for sparse rules

**Category:** Functional Correctness
**Severity Assessment:** High
**Severity Range:** Medium-High from 4 reports
**Reports:** 4

The TIMESTAMP `after()` function passes `max_count=2` to the internal generator. `calculate_safe_iteration_limit('DAILY', NULL, 2)` returns only 80, meaning the generator scans at most 80 daily periods. For sparse rules like `FREQ=DAILY;BYMONTHDAY=31;BYMONTH=1` (matches ~1/365 days), or when after_date is more than ~80 days from dtstart, the generator exhausts period_limit and returns NULL despite valid occurrences existing. Multi-occurrence-per-period rules (e.g., `FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR`) also suffer: the generator may truncate candidates within a period because max_count=2 limits the output. The TIMESTAMPTZ `after()` correctly uses `max_count=1000` and does not have this issue.

**Location:** `src/rrule.sql:2447` (TIMESTAMP `after()` function).

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`

---

## Issue 15: Subday generators use weaker max_results guard, missing bymonthday/bymonth checks

**Category:** Cross-Cutting Concerns
**Severity Assessment:** Medium
**Severity Range:** Low-Medium from 14 reports
**Reports:** 14

The subday generators in `rrule_subday.sql` pass `max_results` to `daily_set`, `monthly_set`, and `yearly_set` when only `rule.bysetpos IS NULL`, omitting the `AND rule.bymonthday IS NULL AND rule.bymonth IS NULL` guards present in the main `rrule.sql` generators. This violates CLAUDE.md rules #9 (quadruple generator maintenance) and #11 (never limit before post-filters). For rules combining sub-day time expansion (BYHOUR/BYMINUTE/BYSECOND) with BYMONTH or BYMONTHDAY, this truncates candidates per-day, producing wrong occurrence selection. Example: `FREQ=DAILY;BYMONTH=1;BYHOUR=9,10,11;COUNT=6` skips 11AM on Jan 1 and includes 9AM on Jan 3 instead of filling Jan 1 and Jan 2 completely.

**Location:** `src/rrule_subday.sql:255` (DAILY), `293` (MONTHLY), `351` (YEARLY) in TIMESTAMP generator; `539` (DAILY), `593` (MONTHLY), `659` (YEARLY) in TZ generator.

**Fix:** 6 edits in `src/rrule_subday.sql` + append to `tests/test_subday_correctness.sql`

---

## Issue 16: Sub-day set functions use naive BYMONTHDAY check that rejects negative values

**Category:** Functional Correctness
**Severity Assessment:** Medium
**Reports:** 2

The sub-day frequency set functions (`hourly_set`, `minutely_set`, `secondly_set`) use `date_part('day', after_ts) = ANY(rule.bymonthday)` for the BYMONTHDAY filter. This only matches positive day-of-month values. Negative BYMONTHDAY values (e.g., `BYMONTHDAY=-1` for last day of month) never match because `date_part('day', ...)` returns 1-31 while the array contains negative integers. The correct approach (used by `daily_set` and other frequency handlers) is to call `rrule.test_bymonthday_rule()` which resolves negative indices relative to month length.

**Location:** `src/rrule_subday.sql:84, 128, 171` (hourly_set, minutely_set, secondly_set).

**Fix:** 3 edits in `src/rrule_subday.sql` + append to `tests/test_subday_correctness.sql`

---

## Issue 17: RSCALE regex only matches uppercase, no parse-failure detection

**Category:** Input Validation
**Severity Assessment:** Medium
**Reports:** 2

The RSCALE regex `RSCALE=([A-Z]+)` only matches uppercase values. If a user passes `RSCALE=hebrew` (lowercase), the regex returns NULL, and there is no parse-failure detection (unlike all other BYxxx parameters which have `IF result.X IS NULL AND repeatrule ~ 'X=' THEN RAISE EXCEPTION` guards). Lowercase RSCALE is silently ignored rather than rejected with a descriptive error. `RSCALE=HEBREW` is properly rejected (matched by regex, fails validation), but `RSCALE=hebrew` bypasses validation entirely.

**Location:** `src/rrule.sql:142` (RSCALE parsing) and `src/rrule.sql:222-256` (parse-failure detection block, RSCALE absent).

**Fix:** 2 edits in `src/rrule.sql` (case-insensitive regex + parse-failure detection) + append to `tests/test_validation.sql`

---

## Issue 18: SKIP=FORWARD with BYMONTHDAY produces cross-period duplicate dates

**Category:** Cross-Cutting Concerns
**Severity Assessment:** Medium
**Reports:** 3

When `rrule_month_bymonthday_set` forwards an invalid date to the first of the next month (e.g., Feb 31 -> Mar 1 with SKIP=FORWARD), and the next period also generates that same date via a different BYMONTHDAY value (e.g., BYMONTHDAY=1), the date is emitted twice. Example: `FREQ=MONTHLY;BYMONTHDAY=1,31;SKIP=FORWARD` — February's set emits Feb 1 and Mar 1 (forwarded from Feb 31); March's set emits Mar 1 and Mar 31. Mar 1 appears twice, inflating occurrence_count and potentially stopping COUNT-limited rules one result early. The `seen_dates` deduplication in `rrule_month_bymonthday_set` only operates within a single month's call, not across periods. Same issue exists in `rrule_yearly_bymonth_set` when FORWARD pushes dates across BYMONTH boundaries.

**Location:** `src/rrule.sql:rrule_month_bymonthday_set` (lines 770-782) and generator MONTHLY branches in all 4 generators.

**Fix:** 4 edits in `src/rrule.sql`, `src/rrule_subday.sql` (add cross-period dedup in MONTHLY/YEARLY branches of all generators) + append to `tests/test_skip_support.sql`

---

## Issue 19: overlaps() false-positive with duration-expanded adjusted_mindate for single events

**Category:** Functional Correctness
**Severity Assessment:** Medium
**Reports:** 1

Both `overlaps()` functions (TIMESTAMP and TIMESTAMPTZ) apply the duration-expanded `adjusted_mindate` to the single-event NULL-rrule check. This causes false-positive overlap detection when the event ends before the query window but the gap is smaller than the event duration. Example: Event [Jan 1, Jan 10] (9-day duration), query range [Jan 11, Jan 20]: `adjusted_mindate = Jan 2` (Jan 11 - 9 days). Check yields `dtstart(Jan 1) < maxdate(Jan 20) AND dtend(Jan 10) >= adjusted_mindate(Jan 2) = TRUE`, but the event does not actually overlap the range.

**Location:** `src/rrule.sql:2655` and `src/rrule.sql:3501`.

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`

---

## Issue 20: installManual.sh does not replace hardcoded rrule. schema-qualified references

**Category:** Upgrade & Install
**Severity Assessment:** High
**Reports:** 2

`installManual.sh` sed replacements only handle `SET search_path` and `nspname = 'rrule'` but miss all 140+ hardcoded `rrule.` schema-qualified references in function bodies (e.g., `rrule.parse_rrule_parts`, `rrule.weekday_to_number`, `rrule."all"`). Functions created in `rrule_update` will call the OLD `rrule` schema at runtime, producing a broken hybrid installation. After dropping the old schema per the migration guide, all functions fail.

**Location:** `src/installManual.sh:49-52`.

**Fix:** 1 edit in `src/installManual.sh` + verification test or manual verification script

---

## Issue 21: npm SQL.core export includes SET search_path without processing

**Category:** Integration & Real-World Usage
**Severity Assessment:** Medium
**Reports:** 3

The `SQL.core` export in `index.js` reads `src/rrule.sql` raw via `fs.readFileSync` without passing through `buildDriverSafeSQL`. This means `SET search_path = rrule, public;` (line 43 of rrule.sql) is included verbatim. When users execute `SQL.core` via any PostgreSQL driver, the session's `search_path` is permanently changed to `rrule, public`, affecting all subsequent queries. In connection-pooled environments, this silently corrupts other requests sharing the same connection. This also breaks the documented custom-schema usage pattern in INSTALLATION.md.

**Location:** `index.js:76`, `src/rrule.sql:43`.

**Fix:** 1 edit in `index.js` (apply stripping or strip SET search_path specifically) + update documentation

---

## Issue 22: npm buildDriverSafeSQL strips BEGIN/COMMIT making install non-atomic

**Category:** Upgrade & Install
**Severity Assessment:** Medium
**Reports:** 2

`buildDriverSafeSQL()` strips `BEGIN;` and `COMMIT;`, making the entire installation run in autocommit mode. The DO block executes `DROP SCHEMA IF EXISTS rrule CASCADE` which commits immediately. If a later CREATE statement fails (syntax error, connection drop), the schema is already dropped with no transaction to roll back, leaving the database in a broken state with no usable rrule schema.

**Location:** `index.js:45-46`.

**Fix:** 1 edit in `index.js` (retain BEGIN/COMMIT or document that callers must wrap in a transaction) + update documentation

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

## Issue 28: TIMESTAMPTZ overlaps() inefficient delegation through between()

**Category:** Performance
**Severity Assessment:** Low
**Reports:** 3

The TIMESTAMPTZ `overlaps()` function delegates to `rrule."between"()` which materializes results before LIMIT 1 takes effect. The TIMESTAMP `overlaps()` calls `rrule_event_instances_range()` directly with LIMIT 1, streaming results efficiently. For rules with many occurrences in the adjusted range, the TIMESTAMPTZ variant is significantly slower.

**Location:** `src/rrule.sql:3504-3507` (TIMESTAMPTZ overlaps) vs `src/rrule.sql:2662` (TIMESTAMP overlaps).

**Fix:** 1 edit in `src/rrule.sql` (use `rrule_event_instances_range_tz` directly with LIMIT 1) + append to `tests/test_tz_api.sql`

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
