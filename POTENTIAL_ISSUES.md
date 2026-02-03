# Potential Issues

Issues identified by audit agents during production readiness review.

## Severity Thresholds

An issue qualifies for fixing when its report count meets the severity threshold:

| Severity | Reports needed |
|----------|---------------|
| Critical | 1             |
| High     | 1             |
| Medium   | 2             |
| Low      | 3             |

## Document Structure

- **Open Issues** — Active issues pending fix or verification
- **Closed Issues** — Resolved issues with resolution type and commit reference
- **Verified Non-Issues** — False positives and design decisions (prevents re-reporting)

## Field Definitions

| Field | Values | Meaning |
|-------|--------|---------|
| **Verified** | Yes / No / Pending | Has the issue been confirmed to exist? |
| **Status** | Pending Fix / Needs Verification / Blocked | Current state |
| **Resolution** | Fixed / Won't Fix / Duplicate / Cannot Reproduce | How the issue was closed |
| **Verdict** | False Positive / Design Decision / Already Tested / Invalid Assumption | Why it's not an issue |

---

# Open Issues

Issues pending fix or verification. Format includes: description, category, severity, reports, verification status, and current status.

---

## Issue 9: npm buildDriverSafeSQL strips all backslash-prefixed lines

**Category:** Integration & Real-World Usage
**Severity:** Medium | **Reports:** 1 | **Verified:** No | **Status:** Needs Verification

The `buildDriverSafeSQL()` function in `index.js` uses `trimmed.startsWith('\\')` to strip lines, removing any line starting with a backslash. While this works for current code (only psql meta-commands like `\ir`, `\set`, `\echo` start with backslash), it's fragile. Future SQL containing escaped string literals at line start (e.g., `E'\\n...'`) would be incorrectly stripped.

**Location:** `index.js` line 39.

**Note:** No current SQL files trigger this. A safer approach would be to explicitly match known meta-commands.

**Fix:** 1 edit in `index.js`
**Complexity:** simple

---

## Issue 44: next()/most_recent() missing NULL rrule_string guard

**Category:** API Contract
**Severity:** Low | **Reports:** 2 | **Verified:** No | **Status:** Needs Verification

TIMESTAMP and TIMESTAMPTZ `next()` and `most_recent()` do not validate NULL `rrule_string` at their own level. They delegate to `after()`/`before()` which do validate, but the error originates from a different function. Before delegation, TIMESTAMPTZ variants compute `substring(rrule_string from 'TZID=...')` on potentially NULL input, which silently returns NULL and wastes work. All other public API functions (all, between, after, before) check NULL rrule at their entry point.

**Location:** `src/rrule.sql:2593-2606` (TIMESTAMP next), `src/rrule.sql:2615-2628` (TIMESTAMP most_recent), `src/rrule.sql:3403-3435` (TIMESTAMPTZ next), `src/rrule.sql:3442-3474` (TIMESTAMPTZ most_recent).

**Fix:** 4 edits in `src/rrule.sql` + append to `tests/test_validation.sql`
**Complexity:** intermediate

---

## Issue 45: YEARLY branch lacks cross-period dedup (prev_period_max_ts) for SKIP=FORWARD

**Category:** Cross-Cutting Concerns
**Severity:** Low | **Reports:** 1 | **Verified:** No | **Status:** Needs Verification

The MONTHLY branch deduplicates SKIP=FORWARD dates pushed into adjacent periods via `prev_period_max_ts` (line 2054), but the YEARLY branch has no equivalent check. With SKIP=FORWARD on FREQ=YEARLY, if dtstart is Feb 29, the FORWARD inner loop emits Mar 1. The next iteration's yearly_set could theoretically also generate Mar 1 for specific INTERVAL values.

**Location:** `src/rrule.sql:2120-2198` (YEARLY branch, all four generators).

**Fix:** 4 edits in `src/rrule.sql`, `src/rrule_subday.sql` + append to `tests/test_skip_support.sql`
**Complexity:** intermediate
**Quadruple:** Yes

---

## Issue 46: daily_set passes max_results when BYSETPOS active

**Category:** Edge Cases & Boundary Conditions
**Severity:** Low | **Reports:** 1 | **Verified:** No | **Status:** Needs Verification

`daily_set` passes `max_results` directly to `rrule_day_time_set` even when `rule.bysetpos IS NOT NULL` (line 1445), which would truncate the candidate set before BYSETPOS position selection. The outer generator mitigates this by passing NULL `max_results` when bysetpos is active, but `daily_set` itself has no guard.

**Location:** `src/rrule.sql:1445` (daily_set function).

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_bysetpos.sql`
**Complexity:** simple

---

## Issue 47: after() passes max_count=1000 but only needs first match

**Category:** Performance
**Severity:** Low | **Reports:** 2 | **Verified:** No | **Status:** Needs Verification

TIMESTAMP `after()` passes `max_count=1000` to the generator even though it uses `LIMIT 1` on the outer query. For dense rules, this is harmless. For sparse rules with heavy filtering (e.g., FREQ=DAILY;BYDAY=MO;BYMONTHDAY=13), up to 1000 occurrences may be generated before the WHERE clause finds the first match.

**Location:** `src/rrule.sql:2456-2468` (TIMESTAMP after function).

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_optimizations.sql`
**Complexity:** simple

---

## Issue 48: overlaps() passes max_count=1000 but only needs existence check

**Category:** Performance
**Severity:** Low | **Reports:** 2 | **Verified:** No | **Status:** Needs Verification

Both TIMESTAMP and TIMESTAMPTZ `overlaps()` pass `max_count=1000` to the generator but use `LIMIT 1` to check for existence. Passing `max_count=1` would reduce the generator's period_limit (calculated as max_count * multiplier) by 1000x, enabling much earlier termination.

**Location:** `src/rrule.sql:2679` (TIMESTAMP overlaps), `src/rrule.sql:3535-3541` (TIMESTAMPTZ overlaps).

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`
**Complexity:** simple

---

## Issue 49: Generators callable with NULL max_count yield INT_MAX period_limit

**Category:** Safety & Security
**Severity:** Low | **Reports:** 1 | **Verified:** No | **Status:** Needs Verification

When `calculate_safe_iteration_limit` returns NULL (both rrule_count and requested_max are NULL), all four generators set `period_limit` to 2147483647 (INT_MAX). This path is unreachable through the public API (all functions pass non-NULL max_count), but the internal functions can be called directly by database users with EXECUTE privilege on the rrule schema.

**Location:** `src/rrule.sql:1988-1990`, `src/rrule.sql:2762-2764`, `src/rrule_subday.sql:234-236`, `src/rrule_subday.sql:530-532`.

**Fix:** 4 edits in `src/rrule.sql`, `src/rrule_subday.sql` + append to `tests/test_coverage_gaps.sql`
**Complexity:** intermediate
**Quadruple:** Yes

---

## Issue 50: rrule_bysetpos_filter NULL path uses per-row cursor FETCH

**Category:** Performance
**Severity:** Low | **Reports:** 1 | **Verified:** No | **Status:** Needs Verification

When `bysetpos IS NULL`, `rrule_bysetpos_filter` (line 1273-1278) fetches every row from the cursor one at a time in a PL/pgSQL LOOP. All set functions route through this cursor+filter path even when no BYSETPOS is specified, adding per-row FETCH overhead for every period's candidate set.

**Location:** `src/rrule.sql:1273-1278` (rrule_bysetpos_filter NULL path).

**Fix:** 4 edits in `src/rrule.sql` (bypass cursor when bysetpos IS NULL in set functions)
**Complexity:** intermediate

---

## Issue 51: yearly_set CROSS JOIN 12 months doesn't short-circuit on max_results

**Category:** Performance
**Severity:** Low | **Reports:** 2 | **Verified:** No | **Status:** Needs Verification

`yearly_set` without BYMONTH/BYWEEKNO/BYYEARDAY but with BYMONTHDAY or BYDAY opens a cursor over `generate_series(1,12) CROSS JOIN LATERAL monthly_set`. Each `monthly_set` call receives the full `max_results` limit independently, so all 12 months always execute even if earlier months already produced enough results.

**Location:** `src/rrule.sql:1891-1901` (yearly_set CROSS JOIN LATERAL branch).

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_optimizations.sql`
**Complexity:** simple

---

## Issue 52: COUNT/INTERVAL negative check uses case-insensitive match but extraction is case-sensitive

**Category:** Input Validation
**Severity:** Low | **Reports:** 1 | **Verified:** No | **Status:** Needs Verification

The negative value checks use `~*` (case-insensitive): `repeatrule ~* 'COUNT=-'` matches `count=-5`. But the extraction regex uses case-sensitive match: `substring(repeatrule from 'COUNT=([0-9]+)')` only matches uppercase. So `count=-5` triggers "COUNT must be a positive integer" even though lowercase `count` would otherwise be silently ignored.

**Location:** `src/rrule.sql:123-126` (COUNT), `src/rrule.sql:129-132` (INTERVAL).

**Fix:** 2 edits in `src/rrule.sql` + append to `tests/test_validation.sql`
**Complexity:** simple

---

## Issue 53: TIMESTAMP before() stale comment about max_count value

**Category:** API Contract
**Severity:** Low | **Reports:** 1 | **Verified:** No | **Status:** Needs Verification

Comment at line 2528-2530 reads "pass 50000000 which is large enough to be uncapped" but the actual code at line 2540 passes 1000000.

**Location:** `src/rrule.sql:2528-2540`.

**Fix:** 1 edit in `src/rrule.sql` (update comment)
**Complexity:** simple

---

## Issue 54: overlaps() 5-param variant may have false positive edge case

**Category:** Integration & Real-World Usage
**Severity:** Low | **Reports:** 1 | **Verified:** No | **Status:** Needs Verification

The 5-param `overlaps()` adjusts mindate by subtracting duration (line 2672) and checks for any occurrence in the expanded range, but does not verify that occurrence + duration actually overlaps the original range. An occurrence starting exactly at adjusted_mindate whose event interval ends exactly at original_mindate could be a false positive.

**Location:** `src/rrule.sql:2670-2682`.

**Fix:** 1 edit in `src/rrule.sql` + append to `tests/test_coverage_gaps.sql`
**Complexity:** simple

---

## Issue 61: WEEKLY + BYMONTH sparsity causes insufficient iteration limit

**Category:** Functional Correctness
**Severity:** Medium | **Reports:** 1 | **Verified:** Yes | **Status:** Pending Fix

`FREQ=WEEKLY;BYMONTH=12;COUNT=5` starting from January returns only 2 results instead of 5. The 10x sparsity multiplier in `calculate_safe_iteration_limit` is insufficient for very sparse rules where only ~5/52 weeks match (December weeks from January start = ~10% match rate).

**Evidence:** Tested 2026-02-03:
```sql
SELECT count(*) FROM rrule."all"('FREQ=WEEKLY;BYMONTH=12;COUNT=5', '2025-01-01'::TIMESTAMP);
-- Returns 2 instead of 5
```

**Location:** `src/rrule.sql` — `calculate_safe_iteration_limit` function and WEEKLY branch multiplier.

**Fix:** Increase WEEKLY multiplier or add BYMONTH-aware adjustment
**Complexity:** intermediate

---

# Closed Issues

Issues that have been resolved. Preserved for historical reference.

---

(No closed issues yet. When an open issue is fixed, move it here with resolution details.)

---

# Verified Non-Issues

Reports that have been analyzed and determined to NOT be issues. Documented here to prevent re-reporting by future audit agents.

---

## [NOT AN ISSUE] TIMESTAMP vs TIMESTAMPTZ API signature incompatibility

**Reported As:** Issue 3 — The TIMESTAMP and TIMESTAMPTZ APIs have different signatures for `after()`, `before()`, `next()`, `most_recent()`, and `between()`. TIMESTAMP returns single values, TIMESTAMPTZ returns SETOF with count parameter.
**Verified:** 2026-02-03
**Verdict:** Design Decision
**Evidence:** The TIMESTAMPTZ API intentionally returns SETOF with a count parameter for flexibility (e.g., "next 5 occurrences"). This is documented behavior, not a bug. Changing it would be a breaking API change.

---

## [NOT AN ISSUE] overlaps() has no TIMESTAMP API variant

**Reported As:** Issue 8 — All other public API functions have both TIMESTAMP and TIMESTAMPTZ overloads, but `overlaps()` only accepts TIMESTAMPTZ.
**Verified:** 2026-02-03
**Verdict:** Design Decision
**Evidence:** This is a feature gap, not a bug. Users have a workaround (cast to TIMESTAMPTZ). Adding a TIMESTAMP variant would be a new feature, not a fix.

---

## [NOT AN ISSUE] TZ generator sub-day error message is unhelpful

**Reported As:** Consensus gap 1.3 — The TZ generator raises generic "Unsupported frequency" for sub-day frequencies, while TIMESTAMP generator provides helpful message.
**Verified:** 2026-02-03
**Verdict:** False Positive
**Evidence:** Tested and found the error message IS detailed:
```
ERROR: Frequency "HOURLY" is not supported in standard installation. Sub-day frequencies
(HOURLY, MINUTELY, SECONDLY) are disabled by default for security. To enable them, use:
psql -d your_database -f src/install_with_subday.sql
```

---

## [NOT AN ISSUE] overlaps() NULL rrule dead code

**Reported As:** Consensus gap 1.4 — TIMESTAMP `overlaps()` has dead code at lines 2617-2619 because NULL rrule check raises exception before single-event fallback.
**Verified:** 2026-02-03
**Verdict:** False Positive (Outdated Line Numbers)
**Evidence:** Line numbers referenced are from an older version. Current code at lines 2979-3025 (TIMESTAMPTZ) and 3778-3845 correctly handles NULL rrule by returning single-event overlap check. No dead code exists.

---

## [NOT AN ISSUE] BYSETPOS + YEARLY + BYMONTH untested

**Reported As:** Consensus gap 2.1 — No test combines BYSETPOS with YEARLY+BYMONTH+BYDAY where the set spans multiple months.
**Verified:** 2026-02-03
**Verdict:** Already Tested
**Evidence:** Tests exist at:
- `test_coverage_gaps.sql:1736` — `FREQ=YEARLY;BYMONTH=1,7;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=4`
- `test_validation.sql:842` — `FREQ=YEARLY;BYMONTH=1,7;BYDAY=MO,FR;BYSETPOS=1,-1;COUNT=4`

---

## [NOT AN ISSUE] YEARLY BYDAY large ordinals untested (20MO, 53MO)

**Reported As:** Consensus gap 2.2 — No test exercises mid-range or boundary ordinals like `BYDAY=20MO` or `BYDAY=53MO`.
**Verified:** 2026-02-03
**Verdict:** Already Tested
**Evidence:** Tests exist at `test_coverage_gaps.sql:6153-6185`:
- Test 31.3: `FREQ=YEARLY;BYDAY=20MO;COUNT=3` (20th Monday of year)
- Test 31.4: `FREQ=YEARLY;BYDAY=53MO` (53rd Monday, sparse years)

---

## [NOT AN ISSUE] inc=TRUE exact boundary untested

**Reported As:** Consensus gap 2.3 — No test verifies that when an occurrence falls exactly on the boundary timestamp, `inc=TRUE` includes it.
**Verified:** 2026-02-03
**Verdict:** Already Tested
**Evidence:** Tests exist at `test_consensus_gaps.sql:786-842` (GROUP 9):
- Test 9.1: `between()` inc=TRUE — occurrence exactly on end_date
- Test 9.2: `between()` inc=TRUE — occurrence exactly on start_date
- Test 9.3: `after()` inc=TRUE — occurrence exactly on after_date

---

## [NOT AN ISSUE] DAILY + BYWEEKNO filter path untested

**Reported As:** Consensus gap 2.5 — The `daily_set` function filters by `byweekno_matches_for_year` but no test covers `FREQ=DAILY;BYWEEKNO=...`.
**Verified:** 2026-02-03
**Verdict:** Invalid Assumption
**Evidence:** `FREQ=DAILY;BYWEEKNO=...` is correctly rejected per RFC 5545 Section 3.3.10: "BYWEEKNO MUST NOT be used when FREQ is not YEARLY". Test exists at `test_validation.sql:202-207`.
