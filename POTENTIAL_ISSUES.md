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
**Reports:** 6

The `between()` function passes user-provided start_date and end_date directly to the internal generator without clamping to a 10-year window. A user can request `between(rrule, dtstart, '2020-01-01', '2070-01-01')` and scan 50 years. The 1000-result cap still applies, but the generator may scan many more periods for sparse rules.

**Location:** `src/rrule.sql` TIMESTAMP `between()` (~line 2387) and TIMESTAMPTZ `between()` (~line 3142).

**Note:** This is by design for `between()` (users explicitly specify their range), but could be a DoS vector for sparse rules. The iteration limit provides some protection.

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`
**Complexity:** simple

---

## Issue 2: before() TIMESTAMPTZ uses array accumulation instead of efficient query

**Category:** Safety & Security
**Severity Assessment:** Medium
**Reports:** 6

The TIMESTAMPTZ `before()` function accumulates ALL occurrences in an array with sliding window, while the TIMESTAMP `before()` uses efficient `ORDER BY DESC LIMIT`. For rules with many occurrences before the target date, this causes O(N) memory and array operations.

**Location:** `src/rrule.sql` TIMESTAMPTZ `before()` (~lines 3317-3341).

**Note:** Mitigated by the period_limit in the generator. The TIMESTAMP API version does not have this issue.

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_tz_api.sql`
**Complexity:** intermediate

---

## Issue 3: TIMESTAMP vs TIMESTAMPTZ API signature incompatibility for after()/before()/next()/most_recent()/between()

**Category:** Dual-Path Consistency
**Severity Assessment:** High
**Severity Range:** Medium-High from 10 reports
**Reports:** 10

The TIMESTAMP and TIMESTAMPTZ APIs have fundamentally different signatures for `after()`, `before()`, `next()`, `most_recent()`, and `between()`:
- TIMESTAMP `after(rrule, dtstart, after_date, inc)` returns a single TIMESTAMP
- TIMESTAMPTZ `after(rrule, dtstart, after_date, count, timezone, inc)` returns SETOF TIMESTAMPTZ
- TIMESTAMP `next(rrule, dtstart, reference_time)` — 3rd param is reference_time
- TIMESTAMPTZ `next(rrule, dtstart, timezone, reference_time)` — 3rd param is timezone
- TIMESTAMP `between(rrule, dtstart, start, end, inc)` — 5th param is inc
- TIMESTAMPTZ `between(rrule, dtstart, start, end, timezone, inc)` — 5th param is timezone

This breaks API parity. Users cannot easily switch between APIs. Code using positional arguments like `after(rrule, dt, dt2, true)` means "inclusive boundary" for TIMESTAMP but "return 1 result (true->1)" for TIMESTAMPTZ.

**Location:** `src/rrule.sql` lines 2377-2429 (TIMESTAMP after) vs 3112-3184 (TIMESTAMPTZ after), and similarly for `before()`, `next()`, `most_recent()`, `between()`.

**Note:** This is a design decision, not a runtime bug. The TIMESTAMPTZ versions intentionally return SETOF with a count parameter. Changing this would be a breaking API change.

**Fix:** N/A (design decision)
**Complexity:** N/A

---

## Issue 8: overlaps() has no TIMESTAMP API variant

**Category:** Integration & Real-World Usage
**Severity Assessment:** High
**Reports:** 2

All other public API functions (`all`, `between`, `after`, `before`, `count`, `next`, `most_recent`) have both TIMESTAMP and TIMESTAMPTZ overloads. The `overlaps()` function only accepts TIMESTAMPTZ parameters. Users of the TIMESTAMP API must cast values to use `overlaps()`.

**Location:** `src/rrule.sql` lines 2592-2636.

**Note:** This is a feature gap, not a runtime bug. Users have a workaround (cast to TIMESTAMPTZ).

**Fix:** N/A (feature gap)
**Complexity:** N/A

---

## Issue 9: npm buildDriverSafeSQL strips all backslash-prefixed lines

**Category:** Integration & Real-World Usage
**Severity Assessment:** Medium
**Reports:** 1

The `buildDriverSafeSQL()` function in `index.js` uses `trimmed.startsWith('\\')` to strip lines, removing any line starting with a backslash. While this works for current code (only psql meta-commands like `\ir`, `\set`, `\echo` start with backslash), it's fragile. Future SQL containing escaped string literals at line start (e.g., `E'\\n...'`) would be incorrectly stripped.

**Location:** `index.js` line 39.

**Note:** No current SQL files trigger this. A safer approach would be to explicitly match known meta-commands.

**Fix:** 1 edit in `index.js`
**Complexity:** simple

---

## Issue 13: BYDAY uses array_remove for empty strings but other BYxxx parameters do not

**Category:** Input Validation
**Severity Assessment:** Low
**Reports:** 1

Only BYDAY parsing uses `array_remove(result, '')` to clean up empty strings from `string_to_array` (handling trailing commas like `BYDAY=MO,TU,`). BYMONTH, BYMONTHDAY, BYYEARDAY, BYWEEKNO, BYSETPOS, BYHOUR, BYMINUTE, BYSECOND do not apply the same cleanup. A trailing comma in these parameters produces an empty string element that causes a cast error or validation failure with a confusing message.

**Location:** `src/rrule.sql:154-162` (BYDAY parsing with array_remove) vs lines 163-246 (other BYxxx parsing without).

**Fix:** 8 edits in `src/rrule.sql` + tests in `tests/test_validation.sql`
**Complexity:** intermediate

---

## Issue 19: overlaps() false-positive with duration-expanded adjusted_mindate for single events

**Category:** Functional Correctness
**Severity Assessment:** Medium
**Reports:** 9

Both `overlaps()` functions (TIMESTAMP and TIMESTAMPTZ) apply the duration-expanded `adjusted_mindate` to the single-event NULL-rrule check. This causes false-positive overlap detection when the event ends before the query window but the gap is smaller than the event duration. Example: Event [Jan 1, Jan 10] (9-day duration), query range [Jan 11, Jan 20]: `adjusted_mindate = Jan 2` (Jan 11 - 9 days). Check yields `dtstart(Jan 1) < maxdate(Jan 20) AND dtend(Jan 10) >= adjusted_mindate(Jan 2) = TRUE`, but the event does not actually overlap the range.

**Location:** `src/rrule.sql:2664` and `src/rrule.sql:3514`.

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`
**Complexity:** simple

---

## Issue 23: installManual.sh does not handle rrule_subday.sql

**Category:** Upgrade & Install
**Severity Assessment:** Medium
**Reports:** 1

The manual migration script only pipes `rrule.sql` through sed and psql. There is no handling of `rrule_subday.sql`. Users who had `install_with_subday.sql` installed and follow the manual migration path silently lose sub-day frequency support.

**Location:** `src/installManual.sh:48-52`.

**Fix:** 1 edit in `src/installManual.sh` + update MANUAL_MIGRATION.md
**Complexity:** simple

---

## Issue 24: monthly_set BYWEEKNO filter does not normalize negative week numbers

**Category:** Cross-Cutting Concerns
**Severity Assessment:** Medium
**Severity Range:** Low-Medium from 9 reports
**Reports:** 9

`monthly_set` line 1551 compares `get_week_number()` (returns positive 1-53) directly against `rule.byweekno` using `= ANY()`, but `rule.byweekno` can contain negative values (e.g., BYWEEKNO=-1 for last week of year). `daily_set` (line 1420) and `weekly_set` (line 1484) both use `byweekno_matches()` / `byweekno_matches_for_year()` which normalize negatives.

**Location:** `src/rrule.sql:1549-1553` (monthly_set function).

**Note:** Multiple agents confirmed this code is unreachable: `parse_rrule_parts` (line 295) rejects BYWEEKNO with any FREQ other than YEARLY, and `yearly_set` nullifies `rr.byweekno` (lines 1604, 1826) before delegating to `monthly_set`. This is dead code — the bug cannot be triggered through any public API path. Fixing is defensive cleanup only.

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_wkst_support.sql`
**Complexity:** simple

---

## Issue 25: after() maxdate anchored to dtstart+10y instead of after_date+10y

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Medium
**Reports:** 9

Both TIMESTAMP and TIMESTAMPTZ `after()` cap the generator maxdate at `dtstart + 10 years`, not `GREATEST(dtstart, after_date) + 10 years`. For rules with COUNT > 10 (e.g., `FREQ=YEARLY;COUNT=20`), calling `after(rule, dtstart, after_date)` where after_date is more than 10 years from dtstart silently returns NULL instead of the correct occurrence.

**Location:** `src/rrule.sql:2447` (TIMESTAMP after), `src/rrule.sql:3222` (TIMESTAMPTZ after).

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`
**Complexity:** simple

---

## Issue 26: Subday TZ generator ELSE branch provides generic error message

**Category:** Dual-Path Consistency
**Severity Assessment:** Low
**Reports:** 5

The subday TZ generator (line 785) says only `'Unsupported frequency: %'` without enumerating valid frequencies, while the other three generators provide frequency-specific guidance (valid values list or sub-day install hint).

**Location:** `src/rrule_subday.sql:785`.

**Fix:** 1 edit in `src/rrule_subday.sql`
**Complexity:** simple

---

## Issue 27: SKIP regex is case-sensitive, lowercase values rejected instead of accepted

**Category:** Input Validation
**Severity Assessment:** Low
**Reports:** 2

The SKIP regex `SKIP=(OMIT|BACKWARD|FORWARD)` is case-sensitive. `SKIP=backward` fails the regex, defaults to 'OMIT', then the parse-failure check detects the mismatch and raises "Invalid SKIP value". This is an explicit rejection (not silent corruption), but RFC 7529 does not specify case sensitivity for SKIP values. RSCALE (line 142) uses `UPPER()` for case-insensitive parsing while SKIP does not, creating inconsistency.

**Location:** `src/rrule.sql:145`.

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_validation.sql`
**Complexity:** simple

---

## Issue 29: SKIP=FORWARD drift loop does not increment period_count

**Category:** Safety & Security
**Severity Assessment:** Low
**Reports:** 7

In MONTHLY/YEARLY generators, the SKIP=FORWARD path advances the date and emits occurrences without incrementing `period_count`, while the outer loop checks `period_count < period_limit`. This weakens DoS protection for FORWARD rules, allowing more iterations than `period_limit` intends. The maxdate/UNTIL checks prevent infinite loops but the iteration budget is bypassed.

**Location:** `src/rrule.sql:2089-2110` (MONTHLY FORWARD), `src/rrule.sql:2163-2187` (YEARLY FORWARD), and equivalents in all 4 generators.

**Fix:** 8 edits in `src/rrule.sql`, `src/rrule_subday.sql` + append to `tests/test_skip_support.sql`
**Complexity:** complex

---

## Issue 30: Error message references psql-specific install path for npm users

**Category:** Upgrade & Install
**Severity Assessment:** Low
**Reports:** 3

The RAISE EXCEPTION message for sub-day frequencies says "use: psql -d your_database -f src/install_with_subday.sql" which is inaccessible to npm users. Should mention `SQL.installWithSubday` as an alternative.

**Location:** `src/rrule.sql:2211` and `src/rrule.sql:2973`.

**Fix:** 2 edits in `src/rrule.sql`
**Complexity:** simple

---

## Issue 31: before() max_count=50M allows excessive iteration budget

**Category:** Safety & Security
**Severity Assessment:** Low
**Reports:** 5

The TIMESTAMP `before()` function passes `max_count=50000000` to the generator, resulting in `calculate_safe_iteration_limit` returning up to 2 billion for DAILY frequency. While the maxdate bound prevents unbounded scanning, a far-future before_date with an unbounded DAILY rule could generate significant CPU load.

**Location:** `src/rrule.sql:2525` (TIMESTAMP before), `src/rrule.sql:3324` (TIMESTAMPTZ before).

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`
**Complexity:** simple

---

## Issue 32: Subday TZ generator missing prev_period_max_ts variable declaration

**Category:** Cross-Cutting Concerns
**Severity Assessment:** Critical
**Severity Range:** High-Critical from 8 reports
**Reports:** 8

The subday TZ generator (`rrule_event_instances_range_tz` in `rrule_subday.sql`) references `prev_period_max_ts` at lines 606 and 614 in the MONTHLY branch for cross-period SKIP=FORWARD deduplication, but the variable is not declared in the DECLARE block (lines 501-512). The other three generators all declare this variable (rrule.sql:1972, rrule.sql:2737, rrule_subday.sql:220). This causes a PL/pgSQL error when the function is created or first invoked, breaking the MONTHLY frequency path through the TIMESTAMPTZ API when subday frequencies are installed. The CI linter (`lint.sh`) does not catch this because it only installs `install.sql`, not `install_with_subday.sql`.

**Location:** `src/rrule_subday.sql:501-512` (DECLARE block missing `prev_period_max_ts`), referenced at lines 606 and 614.

**Fix:** 1 edit in `src/rrule_subday.sql` (add `prev_period_max_ts TIMESTAMP := NULL;` to DECLARE block) + append to `tests/test_subday_correctness.sql`
**Complexity:** simple

---

## Issue 33: npm stripSessionState strips SET search_path required for schema-qualified installation

**Category:** Integration & Real-World Usage
**Severity Assessment:** Critical
**Reports:** 4

`SQL.install`, `SQL.installWithSubday`, and `SQL.core` all strip the file-level `SET search_path = rrule, public;` from `rrule.sql` (and `rrule_subday.sql`) via the `stripSessionState` function. This causes all unqualified `CREATE FUNCTION` statements (~25+ functions including `parse_rrule_parts`, `daily_set`, `weekly_set`, `monthly_set`, `yearly_set`, and all TIMESTAMP API functions) to be created in the caller's default schema (typically `public`) instead of the `rrule` schema. Internal calls use `rrule.` qualification (e.g., `rrule.parse_rrule_parts()`), so every function call fails at runtime with "function does not exist". No npm integration tests exist to catch this.

**Location:** `index.js:31` (`stripSessionState` regex `/^SET\s+(timezone|search_path)\s*/i`) and `index.js:66` (applied to inlined files).

**Fix:** 1 edit in `index.js` (exclude `search_path` from stripping or selectively preserve it) + new npm integration test + update `index.d.ts` and `INSTALLATION.md` for `SQL.core` documentation
**Complexity:** intermediate

---

## Issue 34: rrule_yearly_byweekno_set filters by calendar year, excludes cross-boundary ISO weeks

**Category:** Functional Correctness
**Severity Assessment:** Medium
**Reports:** 1

`rrule_yearly_byweekno_set` filters occurrences by calendar year (`date_part('year', occurrence) = date_part('year', after_ts)`) at lines 1781 and 1790, but ISO weeks at year boundaries can span two calendar years. BYDAY occurrences that fall in the adjacent calendar year (e.g., BYWEEKNO=1 with BYDAY=MO when ISO week 1 starts in December of the prior year) are incorrectly excluded.

**Location:** `src/rrule.sql:1781` and `src/rrule.sql:1790`.

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_wkst_support.sql`
**Complexity:** simple

---

## Issue 35: Duplicate BYxxx parameters silently ignored

**Category:** Input Validation
**Severity Assessment:** Medium
**Reports:** 1

Duplicate BYxxx parameters (e.g., `BYMONTH=1;BYMONTH=6`) are silently ignored. PostgreSQL `substring()` returns only the first regex match, so the second occurrence is discarded without warning. RFC 5545 Section 3.3.10 states "Each rule part MUST only be specified once." Only duplicate FREQ is detected (line 118); no equivalent check exists for COUNT, UNTIL, INTERVAL, WKST, TZID, RSCALE, SKIP, or any BYxxx parameter.

**Location:** `src/rrule.sql:169-197` (parse_rrule_parts, BYxxx parsing block).

**Fix:** 12 edits in `src/rrule.sql` + tests in `tests/test_validation.sql`
**Complexity:** intermediate

---

## Issue 36: SKIP=OMIT inner loops do not increment period_count

**Category:** Safety & Security
**Severity Assessment:** Low
**Reports:** 2

In MONTHLY/YEARLY generators, the SKIP=OMIT drift prevention inner loop advances `current_base` by `rule.interval` without incrementing `period_count` (by design, per code comments: "skipped months should not count against the iteration budget"). However, for pathological rules (e.g., dtstart=Feb 29, FREQ=YEARLY;INTERVAL=1;SKIP=OMIT skips 3 out of every 4 years), the effective scan window is ~4x the intended period_limit because only 1 in 4 years reaches the outer loop's period_count increment.

**Location:** `src/rrule.sql:2077-2088` (MONTHLY OMIT), `src/rrule.sql:2149-2162` (YEARLY OMIT), and equivalents in all 4 generators.

**Fix:** 8 edits in `src/rrule.sql`, `src/rrule_subday.sql` + append to `tests/test_skip_support.sql`
**Complexity:** complex

---

## Issue 37: COUNT/INTERVAL/BYxxx INT overflow gives generic PostgreSQL error

**Category:** Input Validation
**Severity Assessment:** Low
**Reports:** 1

Values exceeding INT range for COUNT (e.g., `COUNT=99999999999`), INTERVAL, BYYEARDAY, BYWEEKNO, or BYMONTHDAY cause unhandled `::INT` cast errors with generic PostgreSQL messages ("integer out of range") instead of descriptive RRULE-specific errors. The UNTIL parameter has an EXCEPTION handler (lines 105-112) demonstrating the correct pattern, but other integer casts are unprotected.

**Location:** `src/rrule.sql:126` (COUNT), `src/rrule.sql:132` (INTERVAL), `src/rrule.sql:173-175` (BYYEARDAY, BYWEEKNO, BYMONTHDAY).

**Fix:** 5 edits in `src/rrule.sql` + append to `tests/test_validation.sql`
**Complexity:** intermediate

---

## Issue 38: TIMESTAMP count() returns 0 for NULL rrule instead of raising error

**Category:** API Contract
**Severity Assessment:** Low
**Reports:** 1

TIMESTAMP `count()` silently returns 0 for NULL `rrule_string` instead of raising an error, because it delegates to TIMESTAMP `all()` which is declared STRICT (returns zero rows for NULL input). All other TIMESTAMP API functions explicitly raise "FREQ parameter is required" for NULL rrule. The TIMESTAMPTZ `count()` correctly raises an error via its `all()` which has an explicit NULL check.

**Location:** `src/rrule.sql:2561-2578` (TIMESTAMP count function).

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_validation.sql`
**Complexity:** simple

---

## Issue 39: TIMESTAMP before() COUNT(*) OVER() forces full result materialization

**Category:** Performance
**Severity Assessment:** Low
**Reports:** 1

TIMESTAMP `before()` uses `COUNT(*) OVER()` window function in the subquery (line 2528), which forces PostgreSQL to materialize the entire result set from the generator before any `ORDER BY DESC LIMIT 1` processing. All occurrences are accumulated in memory even though only the last one is needed. The window function is used only for the `scan_count` warning.

**Location:** `src/rrule.sql:2525-2542` (TIMESTAMP before function).

**Fix:** 1 edit in `src/rrule.sql`
**Complexity:** simple

---

## Issue 40: SKIP=FORWARD with BYMONTH can produce duplicate dates across adjacent months

**Category:** Cross-Cutting Concerns
**Severity Assessment:** Low
**Reports:** 2

`rrule_yearly_bymonth_set` with SKIP=FORWARD can produce duplicate dates when BYMONTHDAY overflow from one BYMONTH month forwards into the next BYMONTH month. Example: `FREQ=YEARLY;BYMONTH=4,5;BYMONTHDAY=31,1;SKIP=FORWARD` generates May 1 twice — once from April's FORWARD of BYMONTHDAY=31 (April has 30 days) and once from May's BYMONTHDAY=1. The yearly_set cursor (line 1847) lacks DISTINCT, and `rrule_bysetpos_filter` does not deduplicate when `bysetpos IS NULL`.

**Location:** `src/rrule.sql:1844-1854` (yearly_set BYMONTH cursor), `src/rrule.sql:1273-1278` (bysetpos_filter null path).

**Fix:** 1 edit in `src/rrule.sql` (add DISTINCT to cursor) + append to `tests/test_skip_support.sql`
**Complexity:** simple

---

## Issue 41: monthly_set INTERSECT passes max_results to inner generators before post-filter

**Category:** Performance
**Severity Assessment:** Low
**Reports:** 1

`monthly_set` passes `max_results` to both `rrule_month_byday_set` and `rrule_month_bymonthday_set` in the BYDAY+BYMONTHDAY INTERSECT path (line 1566-1568). This limits candidate generation before the INTERSECT post-filter, violating CLAUDE.md rule 11. Practical impact is limited since months have at most 31 days.

**Location:** `src/rrule.sql:1565-1568` (monthly_set INTERSECT branch).

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_bysetpos.sql`
**Complexity:** simple

---

## Issue 42: MANUAL_MIGRATION.md DROP SCHEMA missing CASCADE

**Category:** Upgrade & Install
**Severity Assessment:** Medium
**Reports:** 1

MANUAL_MIGRATION.md Step 5 instructs `DROP SCHEMA rrule;` without CASCADE, which will always fail because the old rrule schema still contains all its own functions (~40 functions, types, domains). The comment "No CASCADE needed" is incorrect.

**Location:** `MANUAL_MIGRATION.md:172` and `MANUAL_MIGRATION.md:265`.

**Fix:** 2 edits in `MANUAL_MIGRATION.md`
**Complexity:** simple

---

## Issue 43: lint.sh does not lint subday installation

**Category:** Upgrade & Install
**Severity Assessment:** Medium
**Reports:** 2

`lint.sh` only installs `install.sql` (line 106) and never installs `install_with_subday.sql`. Functions defined in `rrule_subday.sql` (including overridden generators) are never checked by `plpgsql_check`, allowing bugs like the missing `prev_period_max_ts` declaration (Issue 32) to go undetected. CI only validates standard-install functions.

**Location:** `lint.sh:106`.

**Fix:** 1 edit in `lint.sh` (add second lint pass with `install_with_subday.sql`)
**Complexity:** simple
