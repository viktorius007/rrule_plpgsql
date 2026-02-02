# Safety & Security - Agent 1 Verified Issues

**Source transcript:** `agent-a1bd3e3.jsonl`
**Issues found by agent:** 4
**Issues verified as real:** 3

---

## Issue 1: No upper bound validation on INTERVAL parameter

**Severity:** Medium
**Location:** `src/rrule.sql:265-267`
**Description:** The INTERVAL parameter is validated to be >= 1 but has no upper bound. Values like `INTERVAL=2147483647` are passed directly to `make_interval(years => rule.interval)`, which can cause PostgreSQL timestamp overflow errors or scan astronomical time ranges per iteration.
**Why this is real:** Source code at line 265-267 confirms only `IF result.interval IS NULL OR result.interval < 1 THEN` is checked. No upper bound exists anywhere in `parse_rrule_parts()`. The value flows unchecked into `make_interval()` calls at lines 1989, 2013, 2031, and 2099.

---

## Issue 2: Sub-day frequency DoS caps bypassed by large INTERVAL values

**Severity:** Medium
**Location:** `src/rrule.sql:1221-1222`
**Description:** The MINUTELY cap (1440 iterations) and SECONDLY cap (3600 iterations) in `calculate_safe_iteration_limit()` are iteration-count-based, not time-span-based. `FREQ=SECONDLY;INTERVAL=86400` scans 3600 * 86400 seconds = ~100 days, far exceeding the intended 1-hour cap.
**Why this is real:** Source code at lines 1221-1222 confirms `LEAST(effective_max, 1440)` and `LEAST(effective_max, 3600)` with no consideration of INTERVAL magnitude. Already independently documented in POTENTIAL_ISSUES.md Issue 5.

---

## Issue 3: SKIP=OMIT inner loop missing maxdate/UNTIL boundary checks

**Severity:** Medium
**Location:** `src/rrule.sql:2044-2053` (MONTHLY), `src/rrule.sql:2114-2125` (YEARLY), and equivalents in `src/rrule_subday.sql`
**Description:** The SKIP=OMIT inner loops advance `current_base` repeatedly but only exit on `period_count >= period_limit`. Unlike the SKIP=FORWARD branches (which check `rule.until` and `maxdate` on each iteration), OMIT can advance far beyond the requested range before exiting.
**Why this is real:** Source code at lines 2044-2053 confirms the only exit condition is `EXIT WHEN period_count >= period_limit`. Compare SKIP=FORWARD at lines 2059-2060 which includes `EXIT WHEN rule.until IS NOT NULL AND current > rule.until` and `EXIT WHEN current > maxdate`. Already independently documented in POTENTIAL_ISSUES.md Issue 1.

---

**Note on excluded issue:** The agent's Issue 3 (no test coverage for warning emission) was excluded. While the observation is factually correct (the test at `tests/test_coverage_gaps.sql:2438-2453` only verifies count, not warning emission), this is a test completeness gap rather than a safety/security issue in the production code. The warning logic at `src/rrule.sql:2189` is straightforward and correct. The test file itself documents this limitation with an explanatory comment.
