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

## Issue 23: installManual.sh does not handle rrule_subday.sql

**Category:** Upgrade & Install
**Severity Assessment:** Medium
**Reports:** 1

The manual migration script only pipes `rrule.sql` through sed and psql. There is no handling of `rrule_subday.sql`. Users who had `install_with_subday.sql` installed and follow the manual migration path silently lose sub-day frequency support.

**Location:** `src/installManual.sh:48-52`.

**Note:** One analysis agent reported this may be resolved in the current code. Needs verification.

**Fix:** 1 edit in `src/installManual.sh` + update MANUAL_MIGRATION.md
**Complexity:** simple

---

## Issue 44: next()/most_recent() missing NULL rrule_string guard

**Category:** API Contract
**Severity Assessment:** Low
**Reports:** 2

TIMESTAMP and TIMESTAMPTZ `next()` and `most_recent()` do not validate NULL `rrule_string` at their own level. They delegate to `after()`/`before()` which do validate, but the error originates from a different function. Before delegation, TIMESTAMPTZ variants compute `substring(rrule_string from 'TZID=...')` on potentially NULL input, which silently returns NULL and wastes work. All other public API functions (all, between, after, before) check NULL rrule at their entry point.

**Location:** `src/rrule.sql:2593-2606` (TIMESTAMP next), `src/rrule.sql:2615-2628` (TIMESTAMP most_recent), `src/rrule.sql:3403-3435` (TIMESTAMPTZ next), `src/rrule.sql:3442-3474` (TIMESTAMPTZ most_recent).

**Fix:** 4 edits in `src/rrule.sql` + append to `tests/test_validation.sql`
**Complexity:** intermediate

---

## Issue 45: YEARLY branch lacks cross-period dedup (prev_period_max_ts) for SKIP=FORWARD

**Category:** Cross-Cutting Concerns
**Severity Assessment:** Low
**Reports:** 1

The MONTHLY branch deduplicates SKIP=FORWARD dates pushed into adjacent periods via `prev_period_max_ts` (line 2054), but the YEARLY branch has no equivalent check. With SKIP=FORWARD on FREQ=YEARLY, if dtstart is Feb 29, the FORWARD inner loop emits Mar 1. The next iteration's yearly_set could theoretically also generate Mar 1 for specific INTERVAL values.

**Location:** `src/rrule.sql:2120-2198` (YEARLY branch, all four generators).

**Fix:** 4 edits in `src/rrule.sql`, `src/rrule_subday.sql` + append to `tests/test_skip_support.sql`
**Complexity:** intermediate
**Quadruple:** Yes

---

## Issue 46: daily_set passes max_results when BYSETPOS active

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Low
**Reports:** 1

`daily_set` passes `max_results` directly to `rrule_day_time_set` even when `rule.bysetpos IS NOT NULL` (line 1445), which would truncate the candidate set before BYSETPOS position selection. The outer generator mitigates this by passing NULL `max_results` when bysetpos is active, but `daily_set` itself has no guard.

**Location:** `src/rrule.sql:1445` (daily_set function).

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_bysetpos.sql`
**Complexity:** simple

---

## Issue 47: after() passes max_count=1000 but only needs first match

**Category:** Performance
**Severity Assessment:** Low
**Reports:** 2

TIMESTAMP `after()` passes `max_count=1000` to the generator even though it uses `LIMIT 1` on the outer query. For dense rules, this is harmless. For sparse rules with heavy filtering (e.g., FREQ=DAILY;BYDAY=MO;BYMONTHDAY=13), up to 1000 occurrences may be generated before the WHERE clause finds the first match.

**Location:** `src/rrule.sql:2456-2468` (TIMESTAMP after function).

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_optimizations.sql`
**Complexity:** simple

---

## Issue 48: overlaps() passes max_count=1000 but only needs existence check

**Category:** Performance
**Severity Assessment:** Low
**Reports:** 2

Both TIMESTAMP and TIMESTAMPTZ `overlaps()` pass `max_count=1000` to the generator but use `LIMIT 1` to check for existence. Passing `max_count=1` would reduce the generator's period_limit (calculated as max_count * multiplier) by 1000x, enabling much earlier termination.

**Location:** `src/rrule.sql:2679` (TIMESTAMP overlaps), `src/rrule.sql:3535-3541` (TIMESTAMPTZ overlaps).

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`
**Complexity:** simple

---

## Issue 49: Generators callable with NULL max_count yield INT_MAX period_limit

**Category:** Safety & Security
**Severity Assessment:** Low
**Reports:** 1

When `calculate_safe_iteration_limit` returns NULL (both rrule_count and requested_max are NULL), all four generators set `period_limit` to 2147483647 (INT_MAX). This path is unreachable through the public API (all functions pass non-NULL max_count), but the internal functions can be called directly by database users with EXECUTE privilege on the rrule schema.

**Location:** `src/rrule.sql:1988-1990`, `src/rrule.sql:2762-2764`, `src/rrule_subday.sql:234-236`, `src/rrule_subday.sql:530-532`.

**Fix:** 4 edits in `src/rrule.sql`, `src/rrule_subday.sql` + append to `tests/test_coverage_gaps.sql`
**Complexity:** intermediate
**Quadruple:** Yes

---

## Issue 50: rrule_bysetpos_filter NULL path uses per-row cursor FETCH

**Category:** Performance
**Severity Assessment:** Low
**Reports:** 1

When `bysetpos IS NULL`, `rrule_bysetpos_filter` (line 1273-1278) fetches every row from the cursor one at a time in a PL/pgSQL LOOP. All set functions route through this cursor+filter path even when no BYSETPOS is specified, adding per-row FETCH overhead for every period's candidate set.

**Location:** `src/rrule.sql:1273-1278` (rrule_bysetpos_filter NULL path).

**Fix:** 4 edits in `src/rrule.sql` (bypass cursor when bysetpos IS NULL in set functions)
**Complexity:** intermediate

---

## Issue 51: yearly_set CROSS JOIN 12 months doesn't short-circuit on max_results

**Category:** Performance
**Severity Assessment:** Low
**Reports:** 2

`yearly_set` without BYMONTH/BYWEEKNO/BYYEARDAY but with BYMONTHDAY or BYDAY opens a cursor over `generate_series(1,12) CROSS JOIN LATERAL monthly_set`. Each `monthly_set` call receives the full `max_results` limit independently, so all 12 months always execute even if earlier months already produced enough results.

**Location:** `src/rrule.sql:1891-1901` (yearly_set CROSS JOIN LATERAL branch).

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_optimizations.sql`
**Complexity:** simple

---

## Issue 52: COUNT/INTERVAL negative check uses case-insensitive match but extraction is case-sensitive

**Category:** Input Validation
**Severity Assessment:** Low
**Reports:** 1

The negative value checks use `~*` (case-insensitive): `repeatrule ~* 'COUNT=-'` matches `count=-5`. But the extraction regex uses case-sensitive match: `substring(repeatrule from 'COUNT=([0-9]+)')` only matches uppercase. So `count=-5` triggers "COUNT must be a positive integer" even though lowercase `count` would otherwise be silently ignored.

**Location:** `src/rrule.sql:123-126` (COUNT), `src/rrule.sql:129-132` (INTERVAL).

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_validation.sql`
**Complexity:** simple

---

## Issue 53: TIMESTAMP before() stale comment about max_count value

**Category:** API Contract
**Severity Assessment:** Low
**Reports:** 1

Comment at line 2528-2530 reads "pass 50000000 which is large enough to be uncapped" but the actual code at line 2540 passes 1000000.

**Location:** `src/rrule.sql:2528-2540`.

**Fix:** 1 edit in `src/rrule.sql` (update comment)
**Complexity:** simple

---

## Issue 54: overlaps() 5-param variant may have false positive edge case

**Category:** Integration & Real-World Usage
**Severity Assessment:** Low
**Reports:** 1

The 5-param `overlaps()` adjusts mindate by subtracting duration (line 2672) and checks for any occurrence in the expanded range, but does not verify that occurrence + duration actually overlaps the original range. An occurrence starting exactly at adjusted_mindate whose event interval ends exactly at original_mindate could be a false positive.

**Location:** `src/rrule.sql:2670-2682`.

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`
**Complexity:** simple

---

## Issue 55: installManual.sh sed pattern overly broad, corrupts string literals

**Category:** Upgrade & Install
**Severity Assessment:** Low
**Reports:** 1

`installManual.sh` uses `s/rrule\./rrule_update./g` where the dot in the regex is unescaped, matching any character. This corrupts RAISE WARNING messages containing `rrule:` (e.g., 'rrule: result set truncated' becomes 'rrule_update result set truncated').

**Location:** `src/installManual.sh:52` and `src/installManual.sh:60`.

**Fix:** 2 edits in `src/installManual.sh`
**Complexity:** simple

---

## Issue 56: installManual.sh DROP SCHEMA rrule_update missing CASCADE

**Category:** Upgrade & Install
**Severity Assessment:** Medium
**Reports:** 1

`DROP SCHEMA IF EXISTS rrule_update` at line 43 lacks CASCADE. A previous failed migration attempt that left functions/types in rrule_update will cause this DROP to fail, blocking retries.

**Location:** `src/installManual.sh:43`.

**Fix:** 1 edit in `src/installManual.sh`
**Complexity:** simple

---

## Issue 57: installManual.sh missing ON_ERROR_STOP for psql

**Category:** Upgrade & Install
**Severity Assessment:** Medium
**Reports:** 1

The `sed | psql` pipes on lines 53 and 61 do not include `-v ON_ERROR_STOP=on`. If any CREATE FUNCTION statement fails (e.g., syntax error from bad sed substitution), psql continues executing subsequent statements, producing a partially installed rrule_update schema with missing functions and no error exit code.

**Location:** `src/installManual.sh:53` and `src/installManual.sh:61`.

**Fix:** 2 edits in `src/installManual.sh`
**Complexity:** simple

---

## Issue 58: installManual.sh missing pipefail

**Category:** Upgrade & Install
**Severity Assessment:** Low
**Reports:** 1

Without `set -o pipefail`, if sed fails (e.g., source file not found), the pipe exit code reflects only psql (which succeeds on empty input), leaving an empty rrule_update schema with no functions and exit code 0.

**Location:** `src/installManual.sh:17`.

**Fix:** 1 edit in `src/installManual.sh`
**Complexity:** simple

---

## Issue 59: install_with_subday.sql error message missing remediation steps

**Category:** Upgrade & Install
**Severity Assessment:** Low
**Reports:** 1

`install_with_subday.sql` dependency-check error (lines 117-134) only includes "See the complete migration guide" without the step-by-step remediation bullets present in `install.sql` (lines 108-114). Users hitting the dependency error via install_with_subday.sql get less guidance.

**Location:** `src/install_with_subday.sql:117-134`.

**Fix:** 1 edit in `src/install_with_subday.sql`
**Complexity:** simple

---

## Issue 60: MANUAL_MIGRATION.md test example uses NOW()

**Category:** Upgrade & Install
**Severity Assessment:** Low
**Reports:** 1

The verification query in MANUAL_MIGRATION.md Step 4 uses `NOW()::TIMESTAMP` as dtstart, producing non-deterministic results that vary depending on when the migration is run.

**Location:** `MANUAL_MIGRATION.md:153`.

**Fix:** 1 edit in `MANUAL_MIGRATION.md`
**Complexity:** simple
