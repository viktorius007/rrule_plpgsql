# Edge Cases - Agent 1 Verified Issues

**Source transcript:** `agent-a91fda7.jsonl`
**Issues found by agent:** 2
**Issues verified as real:** 1

---

## Issue 1: SKIP=OMIT inner loop lacks maxdate/UNTIL boundary checks present in SKIP=FORWARD

**Severity:** Medium
**Location:** `src/rrule.sql:2044-2053` (MONTHLY OMIT), `src/rrule.sql:2114-2125` (YEARLY OMIT)
**Description:** The SKIP=OMIT inner loops that advance `current_base` when dtstart day does not exist in the target month only exit on `period_count >= period_limit`. Unlike the SKIP=FORWARD branch (lines 2054-2069, 2126-2150), they do not check `rule.until` or `current > maxdate` before continuing to advance.
**Why this is real:** Source code confirms the asymmetry. The FORWARD branch at lines 2059-2060 contains `EXIT WHEN rule.until IS NOT NULL AND current > rule.until` and `EXIT WHEN current > maxdate`, while the OMIT branch at lines 2044-2053 has no equivalent checks. The outer loop at line 2182 does catch `rule.until` after the inner loop exits, so this is a performance issue rather than a correctness bug -- the OMIT loop may advance `current_base` far beyond maxdate before the outer loop terminates it. The `period_limit` cap prevents infinite looping but does not prevent unnecessary iterations past the time boundary.

---

## Rejected Issues

### Agent Issue 1: BYWEEKNO cross-year week handling lacks multi-year YEARLY loop testing -- FALSE POSITIVE

The agent claimed no multi-year YEARLY+BYWEEKNO test exists. This is incorrect. `tests/test_wkst_support.sql:540` tests `FREQ=YEARLY;BYWEEKNO=53;BYDAY=MO;COUNT=2` spanning 2015 to 2020. `tests/test_consensus_gaps.sql:766` tests `FREQ=YEARLY;BYWEEKNO=1;COUNT=3` spanning 3 years. `tests/test_wkst_support.sql:576` tests `BYWEEKNO=-1;BYDAY=MO;COUNT=2` across multiple years. Additionally, the internal function `byweekno_matches_for_year()` cross-year filtering is tested in `tests/test_consensus_gaps_2.sql:399-440` and `tests/test_internal_functions.sql:934-948`. The year-filtering logic at `src/rrule.sql:1757-1758` is correct and exercised through these multi-year tests.
