# Dual-Path Consistency - Agent 2 Verified Issues

**Source transcript:** `agent-a75541c.jsonl`
**Issues found by agent:** 2
**Issues verified as real:** 2

---

## Issue 1: Missing NULL check on `current` in SKIP=FORWARD UNTIL comparisons

**Severity:** Medium
**Location:** `src/rrule.sql:2059,2131,2798,2868` and `src/rrule_subday.sql:319,381`
**Description:** Six SKIP=FORWARD branches check `EXIT WHEN rule.until IS NOT NULL AND current > rule.until` without first checking `current IS NOT NULL`. The subday TZ generator at lines 615 and 685 correctly includes `current IS NOT NULL AND`, but the other six locations do not.
**Why this is real:** Verified that the outer loop EXIT conditions (rrule.sql:2182, 2904; rrule_subday.sql:463, 765) all include `current IS NOT NULL AND` before the UNTIL comparison, confirming the project's own convention. The six SKIP=FORWARD locations deviate from this convention. While `current` is unlikely to be NULL in practice (it is assigned from `date_trunc` immediately before), this violates Development Rule #9 (quadruple generator synchronization) and Rule #5 (proper NULL handling).

---

## Issue 2: Inconsistent type declaration and assignment for `rule` variable in subday TIMESTAMP generator

**Severity:** Medium
**Location:** `src/rrule_subday.sql:220,222`
**Description:** The subday TIMESTAMP generator declares `rule rrule.rrule_parts;` and assigns via `rule := rrule.parse_rrule_parts(...)`, while all three other generators use `rule rrule.rrule_parts%ROWTYPE;` with `SELECT * INTO rule FROM ...`.
**Why this is real:** Verified all four declarations: rrule.sql:1948 uses `%ROWTYPE` + `SELECT INTO`, rrule.sql:2673 uses `%ROWTYPE` + `SELECT INTO`, rrule_subday.sql:499 uses `%ROWTYPE` + `SELECT INTO`, but rrule_subday.sql:220 uses bare type + direct assignment. Both forms are functionally equivalent in PostgreSQL, but this is a genuine inconsistency that violates Development Rule #9 requiring all four generators to share identical structure.
