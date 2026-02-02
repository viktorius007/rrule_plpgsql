# Safety & Security - Agent 3 Verified Issues

**Source transcript:** `agent-aae12f0.jsonl`
**Issues found by agent:** 5
**Issues verified as real:** 5

---

## Issue 1: SKIP=OMIT inner loop lacks maxdate/UNTIL boundary checks

**Severity:** High
**Location:** `src/rrule.sql:2044-2053, 2114-2125, 2787-2794, 2854-2862` and `src/rrule_subday.sql:308-315, 367-376, 604-611, 671-679`
**Description:** The SKIP=OMIT inner loops in all four generators (MONTHLY and YEARLY branches) only exit on `period_count >= period_limit`. They do not check `current_base >= maxdate` or `rule.until`, unlike the SKIP=FORWARD branches which check both.
**Why this is real:** Source code at all 8 locations confirms the only exit condition is `EXIT WHEN period_count >= period_limit`. The FORWARD branches at the same nesting level (e.g., lines 2059-2060) explicitly check `EXIT WHEN rule.until IS NOT NULL AND current > rule.until` and `EXIT WHEN current > maxdate`. OMIT branches lack both checks, allowing wasted iterations past the intended time boundary.

---

## Issue 2: Sub-day DoS protection caps are iteration-count-based, not time-span-based

**Severity:** Medium
**Location:** `src/rrule.sql:1221-1222`
**Description:** The MINUTELY cap (1440 iterations) and SECONDLY cap (3600 iterations) limit iteration count, not elapsed time. With a large INTERVAL value (e.g., `INTERVAL=86400` for SECONDLY), each iteration covers 1 day, so 3600 iterations scan approximately 10 years rather than the documented "max 1 hour."
**Why this is real:** Lines 1221-1222 show `LEAST(effective_max, 1440)` and `LEAST(effective_max, 3600)` with no consideration of the INTERVAL value. The code comments claim "max 1 day" and "max 1 hour" but these claims only hold when INTERVAL=1.

---

## Issue 3: between() does not enforce 10-year window clamp

**Severity:** Medium
**Location:** `src/rrule.sql:2342-2350`
**Description:** The `between()` function passes user-provided `end_utc` directly to `rrule_event_instances_range()` without clamping to a maximum window. A caller can specify a 50-year range, forcing the generator to scan decades of calendar dates with a sparse rule.
**Why this is real:** Lines 2342-2350 show `end_utc + CASE WHEN inc THEN INTERVAL '1 day' ELSE INTERVAL '0' END` passed as the maxdate parameter with no upper bound. The `all()` function (by contrast) applies `dtstart + INTERVAL '10 years'` as the window. The 1000-result cap and period_limit still provide protection, but CPU cost can be significant for sparse rules over wide ranges.

---

## Issue 4: No early exit when UNTIL precedes dtstart

**Severity:** Medium
**Location:** `src/rrule.sql:1952-2183` (TIMESTAMP generator main loop), `src/rrule.sql:2693-2930` (TZ generator), and equivalent in `src/rrule_subday.sql`
**Description:** When `UNTIL < dtstart`, the generators enter the main WHILE loop and execute at least one full period iteration before detecting the condition. An early-exit check before the loop would avoid unnecessary computation.
**Why this is real:** There is no pre-loop guard comparing `rule.until` against `basedate` in any of the four generators. The UNTIL check only occurs inside the inner frequency FOR loops (e.g., line 2089: `EXIT WHEN rule.until IS NOT NULL AND current > rule.until`), which means the frequency set function must first be called and produce at least one candidate.

---

## Issue 5: Stale current variable in outer loop UNTIL exit check

**Severity:** Low
**Location:** `src/rrule.sql:2182`, `src/rrule_subday.sql:463`, and equivalent TZ generators
**Description:** The outer WHILE loop's UNTIL exit check (`EXIT WHEN rule.until IS NOT NULL AND current IS NOT NULL AND current > rule.until`) uses the `current` variable, which retains its value from the last period that produced results. If intervening periods produce zero results (sparse rule), the check compares against a stale value.
**Why this is real:** Line 2182 confirms the check uses `current` rather than `current_base`. The variable `current` is only updated inside the inner FOR loops when the frequency set returns rows. If a period's set is empty, `current` is unchanged. Other exit conditions (maxdate on `current_base`, period_limit) prevent runaway, so the impact is limited to unnecessary extra iterations.
