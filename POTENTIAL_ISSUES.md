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

## Issue 3: TIMESTAMP vs TIMESTAMPTZ API signature incompatibility for after()/before()

**Category:** Dual-Path Consistency
**Severity Assessment:** High
**Severity Range:** Medium-High from 3 reports
**Reports:** 3

The TIMESTAMP and TIMESTAMPTZ APIs have fundamentally different signatures for `after()` and `before()`:
- TIMESTAMP `after(rrule, dtstart, after_date, inc)` returns a single TIMESTAMP
- TIMESTAMPTZ `after(rrule, dtstart, after_date, count, timezone, inc)` returns SETOF TIMESTAMPTZ

This breaks API parity. Users cannot easily switch between APIs. Code using positional arguments like `after(rrule, dt, dt2, true)` means "inclusive boundary" for TIMESTAMP but "return 1 result (true->1)" for TIMESTAMPTZ.

**Location:** `src/rrule.sql` lines 2377-2429 (TIMESTAMP) vs 3112-3184 (TIMESTAMPTZ), and similarly for `before()`.

**Note:** This is a design decision, not a runtime bug. The TIMESTAMPTZ versions intentionally return SETOF with a count parameter. Changing this would be a breaking API change.

---

## Issue 4: Inconsistent NULL check in TIMESTAMPTZ generators vs TIMESTAMP generators

**Category:** Dual-Path Consistency
**Severity Assessment:** Medium
**Severity Range:** Low-Medium from 2 reports
**Reports:** 2

The subday TIMESTAMPTZ generator includes `current IS NOT NULL AND` in UNTIL exit conditions, while the standard TIMESTAMPTZ generator and TIMESTAMP generators do not include this guard. While `current` should never be NULL inside a FOR loop iterating over set-returning function results, the inconsistency indicates the four generators diverged from a common template (violating Development Rule #9).

**Location:** `src/rrule.sql` lines 1987, 2006, 2029, 2099 (TIMESTAMP) vs `src/rrule_subday.sql` lines 535, 560, 589 (subday TZ includes guard).

---

## Issue 5: WEEKLY frequency passes max_results before post-filters

**Category:** Edge Cases & Boundary Conditions
**Severity Assessment:** Medium
**Reports:** 1

The WEEKLY branch in the generators calls `weekly_set(current_base, rule, CASE WHEN output_limit IS NULL THEN NULL ELSE GREATEST(output_limit - emitted_count, 0) END)` and then applies BYYEARDAY/BYMONTHDAY/BYMONTH post-filters via `test_byyearday_rule`, `test_bymonthday_rule`, `test_bymonth_rule`. This violates Development Rule #11: "Never limit candidate generation before post-filters." If `weekly_set` generates N candidates hitting its limit, but post-filters reject most, fewer results than requested are returned.

**Location:** `src/rrule.sql` lines 2001-2004 (and equivalents in all 4 generators).

**Note:** Same pattern exists for DAILY branch. The fix would be to pass NULL for max_results when any post-filters are present (matching the yearly_set pattern).

---

## Issue 6: No BYSETPOS + SKIP interaction test coverage

**Category:** Cross-Cutting Concerns
**Severity Assessment:** Medium
**Reports:** 1

No tests verify BYSETPOS behavior when SKIP=FORWARD or SKIP=BACKWARD produce dates that overlap with other BYxxx rules. For example, `FREQ=MONTHLY;BYMONTHDAY=30,31;SKIP=FORWARD;BYSETPOS=1,-1` could produce duplicate forwarded dates that affect BYSETPOS position selection. BYSETPOS position selection depends on input cardinality — if duplicates aren't properly removed before BYSETPOS, position indices will be off.

**Location:** `tests/` (no BYSETPOS + SKIP combination tests).

---

## Issue 7: NULL date range parameters not validated in between()/after()/before()

**Category:** Input Validation
**Severity Assessment:** Medium
**Reports:** 1

The `between()`, `after()`, and `before()` functions validate NULL for `rrule_string` and `dtstart` but NOT for date range parameters (`start_date`/`end_date`, `after_date`, `before_date`). Passing NULL produces confusing behavior (empty results or PostgreSQL cast errors) without a descriptive error message.

**Location:** `src/rrule.sql` lines 2315-2368 (between TIMESTAMP), 2377-2428 (after TIMESTAMP), 2438-2509 (before TIMESTAMP), and TIMESTAMPTZ equivalents.

**Note:** PostgreSQL handles NULL gracefully (comparisons with NULL return NULL, preventing matches), so results are technically correct (empty set). The gap is user experience, not correctness.

---

## Issue 8: overlaps() has no TIMESTAMP API variant

**Category:** Integration & Real-World Usage
**Severity Assessment:** High
**Reports:** 1

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
