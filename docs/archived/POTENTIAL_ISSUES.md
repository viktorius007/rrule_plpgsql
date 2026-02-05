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
- **Verified Non-Issues** — False positives and design decisions (prevents re-reporting)

## Field Definitions

| Field | Values | Meaning |
|-------|--------|---------|
| **Verified** | Yes / No / Pending | Has the issue been confirmed to exist? |
| **Status** | Pending Fix / Needs Verification / Blocked | Current state |
| **Verdict** | False Positive / Design Decision / Already Tested / Invalid Assumption | Why it's not an issue |

---

# Open Issues

Issues pending fix or verification. Format includes: description, category, severity, reports, verification status, and current status.

---

(No open issues)

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

---

## [NOT AN ISSUE] next()/most_recent() missing NULL rrule_string guard

**Reported As:** Issue 44 — TIMESTAMP and TIMESTAMPTZ `next()` and `most_recent()` do not validate NULL `rrule_string` at their own level.
**Verified:** 2026-02-03
**Verdict:** Design Decision
**Evidence:** NULL rrule IS caught via delegation to `after()`/`before()`. Error is raised with helpful message ("FREQ parameter is required"). The slightly longer error context (showing delegation path) doesn't affect user experience. All API functions consistently reject NULL rrule.

---

## [NOT AN ISSUE] YEARLY SKIP=FORWARD may produce duplicate dates

**Reported As:** Issue 45 — The YEARLY branch lacks cross-period dedup (prev_period_max_ts) for SKIP=FORWARD, potentially generating duplicate Mar 1 dates.
**Verified:** 2026-02-03
**Verdict:** False Positive
**Evidence:** Tested `FREQ=YEARLY;BYMONTHDAY=29;BYMONTH=2;SKIP=FORWARD;COUNT=10` from 2024-02-29. Results are unique: 2024-02-29, 2025-03-01, 2026-03-01, ... No duplicates observed across multiple test cases.

---

## [NOT AN ISSUE] daily_set passes max_results when BYSETPOS active

**Reported As:** Issue 46 — `daily_set` passes `max_results` to inner functions even when BYSETPOS is active, potentially truncating candidate set.
**Verified:** 2026-02-03
**Verdict:** False Positive
**Evidence:** The outer generator passes NULL max_results when bysetpos is active, which `daily_set` respects. Tested `FREQ=DAILY;BYHOUR=9,17;BYSETPOS=1,-1;COUNT=10` — correctly returns 10 results with proper BYSETPOS selection.

---

## [NOT AN ISSUE] after()/overlaps() pass max_count=1000 inefficiently

**Reported As:** Issues 47 & 48 — `after()` and `overlaps()` pass max_count=1000 but only need first match, wasting generator iterations.
**Verified:** 2026-02-03
**Verdict:** Design Decision
**Evidence:** The max_count parameter affects period_limit calculation in the generator. For sparse rules (e.g., `FREQ=DAILY;BYMONTHDAY=31`), max_count=1 would set period_limit too low, causing the generator to stop before finding any match. Code comment at line 2775 explains: "max_count=1000: sparse rules may need many periods before finding occurrence".

---

## [NOT AN ISSUE] overlaps() reports false positive when event ends exactly at mindate

**Reported As:** Issue 54 — The 5-param `overlaps()` may report false positive when event ends exactly at adjusted_mindate.
**Verified:** 2026-02-03
**Verdict:** Design Decision
**Evidence:** The semantics are "touching = overlapping". Single-event check uses `(dtstart + duration) >= mindate`, meaning event ending at mindate counts as overlap. Recurring event check is consistent with this. Tested: event 10:00-11:00 with range [11:00, 12:00] returns TRUE (touching); range [11:01, 12:00] returns FALSE (not touching). Behavior is intentional and documented.
