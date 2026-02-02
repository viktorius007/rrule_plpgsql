# Edge Cases - Agent 3 Verified Issues

**Source transcript:** `agent-a157f1e.jsonl`
**Issues found by agent:** 2
**Issues verified as real:** 2

---

## Issue 1: SKIP=OMIT inner loop lacks maxdate/UNTIL early-exit checks

**Severity:** Medium
**Location:** `src/rrule.sql:2044-2053` (MONTHLY), `src/rrule.sql:2114-2125` (YEARLY)
**Description:** The SKIP=OMIT inner loop advances `current_base` by INTERVAL when the target day does not exist in the current month/year, but only exits on `period_count >= period_limit`. It does not check `current_base > maxdate` or `rule.until`, unlike the SKIP=FORWARD branch which checks both (lines 2059-2060 and 2131-2132). This can cause unnecessary iterations before the outer loop (line 1971) catches the boundary.
**Why this is real:** Confirmed in source: the OMIT branch at line 2053 has only `EXIT WHEN period_count >= period_limit;` while the FORWARD branch at lines 2059-2060 has `EXIT WHEN rule.until IS NOT NULL AND current > rule.until;` and `EXIT WHEN current > maxdate;`. The outer WHILE loop at line 1971 does check `current_base < maxdate`, preventing incorrect results, so this is a performance issue only. Already documented in POTENTIAL_ISSUES.md Issue 1.

---

## Issue 2: between() does not validate start_date <= end_date

**Severity:** Medium
**Location:** `src/rrule.sql:2303-2356` (TIMESTAMP API), `src/rrule.sql:3012-3064` (TIMESTAMPTZ API)
**Description:** The `between()` function accepts `start_date` and `end_date` without validating that `start_date <= end_date`. When called with a backwards range, the generator still runs but the WHERE clause (lines 2351-2353) can never match, silently returning an empty result set with no error or warning.
**Why this is real:** Confirmed in source: lines 2317-2338 validate NULL rrule_string and NULL dtstart but perform no comparison between start_date and end_date. The TIMESTAMPTZ overload at lines 3027-3052 similarly lacks this validation. The codebase validates other invalid inputs (FREQ required, COUNT/UNTIL mutual exclusivity) but not this case. No test coverage exists for backwards ranges.
