# Dual-Path Consistency - Agent 3 Verified Issues

**Source transcript:** `agent-a0a99f8.jsonl`
**Issues found by agent:** 4
**Issues verified as real:** 1

---

## Issue 1: Inconsistent NULL guard on inner-loop UNTIL checks between Generator 4 and Generators 1-3

**Severity:** Medium
**Location:** `src/rrule.sql:2712,2738,2768,2798,2832,2868` (Generator 2 missing guards) vs `src/rrule_subday.sql:531,556,585,615,649,685` (Generator 4 has guards)
**Description:** Generator 4 (subday TZ in rrule_subday.sql) includes `current IS NOT NULL AND` in all inner-loop and SKIP=FORWARD UNTIL checks, but the other three generators (including Generator 2, the standard TZ generator in rrule.sql) do not. This violates the quadruple-generator synchronization rule (CLAUDE.md Rule #9) -- the four generators should have identical loop structure.
**Why this is real:** Source code confirms Generator 4 at lines 531, 556, 585, 615, 649, 685 of rrule_subday.sql uses the pattern `EXIT WHEN rule.until IS NOT NULL AND current IS NOT NULL AND current::TIMESTAMPTZ > rule.until;`, while Generator 2 at lines 2712, 2738, 2768, 2798, 2832, 2868 of rrule.sql uses `EXIT WHEN rule.until IS NOT NULL AND current::TIMESTAMPTZ > rule.until;` without the NULL guard. Generators 1 and 3 (TIMESTAMP variants) similarly lack the guard. The inconsistency is genuine.

**Severity downgrade note:** The agent rated this CRITICAL, but verification shows the practical impact is negligible. These EXIT statements are inside `FOR current IN SELECT ... LOOP` blocks where `current` is assigned by the loop iterator and cannot be NULL (empty result sets skip the loop body entirely). In the SKIP=FORWARD paths, `current` is explicitly assigned a computed expression that cannot produce NULL. The outer loop termination (lines 2182 and 2904 in rrule.sql) already correctly includes `current IS NOT NULL` in all 4 generators, which is the one location where `current` can genuinely be NULL (when a period produces zero candidates). The missing guards are defensive-only and cannot be triggered in practice, making this a code consistency issue rather than a functional bug.

---

**Agent issues determined to be false positives or overstated:**

- **Agent Issue #2 (DAILY/WEEKLY NULL checks):** This is the same issue as #1, not a separate bug. The agent split one inconsistency across two "CRITICAL" issues. Consolidated into Issue 1 above.
- **Agent Issue #3 (Outer loop termination):** The agent acknowledged all 4 generators already have `current IS NOT NULL` in the outer loop. This is not an issue -- it is a positive finding confirming correct behavior. The agent's claim that "inner loops must also have it for outer protection to work" is incorrect; the outer NULL check works independently because when a FOR loop produces zero iterations, the outer loop's `current IS NOT NULL` guard correctly prevents comparison of the stale/NULL value.
- **Agent Issue #4 (Test coverage gap):** This is a suggestion for improvement, not a bug. The agent correctly identified that no test specifically targets the zero-candidate + UNTIL + TZ path, but since the underlying code issue (Issues #1-2) has no practical impact, the absence of such a test is not a deficiency.
