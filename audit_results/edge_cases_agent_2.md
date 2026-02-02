# Edge Cases - Agent 2 Verified Issues

**Source transcript:** `agent-afdd2db.jsonl`
**Issues found by agent:** 7
**Issues verified as real:** 3

---

## Issue 1: No upper bound validation for INTERVAL parameter - potential make_interval overflow

**Severity:** Medium
**Location:** `src/rrule.sql:122, 265-267, 2099`
**Description:** The INTERVAL parameter is parsed as an unconstrained positive integer with no maximum. Extremely large values (e.g., `INTERVAL=2147483647` with `FREQ=YEARLY`) cause `make_interval(years => rule.interval)` at line 2099 to produce a timestamp that exceeds PostgreSQL's maximum timestamp range (~year 294276), resulting in an unhandled PostgreSQL "timestamp out of range" error.
**Why this is real:** Line 122 parses any `[0-9]+` value into an INT. Line 265 only validates `>= 1`. Line 2099 passes `rule.interval` directly to `make_interval(years => ...)` with no overflow guard. PostgreSQL will raise a runtime error rather than the application providing a descriptive validation message.

---

## Issue 2: SKIP=OMIT inner loop lacks maxdate/UNTIL boundary check

**Severity:** Medium-High
**Location:** `src/rrule.sql:2044-2053` (MONTHLY), `src/rrule.sql:2114-2125` (YEARLY)
**Description:** The SKIP=OMIT inner loops advance `current_base` repeatedly when dtstart's day does not exist in a month, but only check `period_count >= period_limit`. They do not check `current_base >= maxdate` or `rule.until`, unlike the SKIP=FORWARD branch which checks both at lines 2059-2060 and 2131-2132.
**Why this is real:** Confirmed by reading the OMIT branch at lines 2044-2053: only `EXIT WHEN period_count >= period_limit` is present. The FORWARD branch at lines 2059-2060 has `EXIT WHEN rule.until IS NOT NULL AND current > rule.until` and `EXIT WHEN current > maxdate`. The outer loop at line 1971 catches these conditions after the inner loop exits, making this a performance issue rather than a correctness bug. Already tracked in POTENTIAL_ISSUES.md Issue #1.

---

## Issue 3: Stale `current` value in outer loop UNTIL exit check wastes iterations

**Severity:** Medium
**Location:** `src/rrule.sql:2182`
**Description:** When a frequency set function returns zero results for a period (e.g., `BYMONTHDAY=30` in February), `current` retains its value from the previous non-empty period. The outer loop exit condition at line 2182 (`EXIT WHEN rule.until IS NOT NULL AND current IS NOT NULL AND current > rule.until`) checks this stale value, failing to trigger early exit when the rule has already passed UNTIL.
**Why this is real:** Confirmed by reading lines 2085-2097: `current` is only updated inside the `FOR current IN SELECT ...` loop, which iterates zero times when the set function returns no results. Line 2182 then checks the old value. The `current_base < maxdate` check at line 1971 and `period_count < period_limit` provide eventual termination, but unnecessary periods are scanned. Already tracked in POTENTIAL_ISSUES.md Issue #9.

---

## Rejected Issues (False Positives)

**Issue 1 (BYMONTHDAY negative index validation):** FALSE POSITIVE. The behavior of silently skipping `BYMONTHDAY=-31` in February (28 days) is correct RFC 5545 behavior. The validation correctly rejects values outside the +-31 range at line 398, and the runtime skip at line 704 correctly handles months that are too short. The agent's claim about `-100` passing parsing is wrong -- it would be caught by validation. The agent itself acknowledges this is "technically RFC-compliant."

**Issue 3 (BYWEEKNO cross-year filtering):** FALSE POSITIVE for practical purposes. The year filter at line 1758 is intentional design -- `rrule_yearly_byweekno_set()` generates dates for a specific calendar year. In the YEARLY main loop, the prior year's iteration generates that year's Week 1 dates (including any December dates). The edge case where dtstart falls on Jan 1 and Week 1 extends into the prior December is handled by the prior year's pass. Already tracked in POTENTIAL_ISSUES.md Issue #8 as a test coverage gap rather than a code defect.

**Issue 6 (YEARLY+BYMONTHDAY=31+INTERVAL>1 test gap):** NOT A CODE ISSUE. This is a test coverage suggestion, not a defect in the implementation. The agent identified no actual bug in the code logic.

**Issue 7 (DST gap time advancement):** FALSE POSITIVE. The agent explicitly states "This is a PostgreSQL/SQL standard behavior limitation, not a bug in rrule_plpgsql." The behavior is documented and tested at `tests/test_tz_api.sql:1334-1380`.
