# Dual-Path Consistency - Agent 1 Verified Issues

**Source transcript:** `agent-ab3f184.jsonl`
**Issues found by agent:** 4
**Issues verified as real:** 2

---

## Issue 1: TIMESTAMP and TIMESTAMPTZ after()/before() have incompatible signatures and return types

**Severity:** Medium
**Location:** `src/rrule.sql:2365-2417` (TIMESTAMP after), `src/rrule.sql:3085-3157` (TIMESTAMPTZ after), `src/rrule.sql:2426-2488` (TIMESTAMP before), `src/rrule.sql:3164-3248` (TIMESTAMPTZ before)
**Description:** The TIMESTAMP `after()` and `before()` functions return a single scalar value (`RETURNS TIMESTAMP`), while the TIMESTAMPTZ versions return a set (`RETURNS SETOF TIMESTAMPTZ`) and accept an additional `count INT` parameter. Code written against one API cannot be ported to the other without rewriting the call site.
**Why this is real:** Verified in source: TIMESTAMP `after()` at line 2371 declares `RETURNS TIMESTAMP`, while TIMESTAMPTZ `after()` at line 3092 declares `RETURNS SETOF TIMESTAMPTZ` with a `count INT` parameter at line 3089. Same pattern confirmed for `before()`. This is likely an intentional design choice (TIMESTAMP API matches python-dateutil, TIMESTAMPTZ API is PostgreSQL-native), but it means the two APIs do not have equivalent contracts, which contradicts the dual-path consistency principle in TESTING_FRAMEWORK.md Category 8.

---

## Issue 2: No explicit dual-path parity tests comparing TIMESTAMP and TIMESTAMPTZ API output

**Severity:** Medium
**Location:** `tests/` directory (all test files)
**Description:** No test compares the output of the TIMESTAMP API against the TIMESTAMPTZ API for the same rule to verify they produce equivalent wall-clock results. Existing TZ parity tests (in `test_consensus_gaps.sql` and `test_tz_api.sql`) verify TIMESTAMPTZ behavior independently against hardcoded expected values, but never directly compare the two paths.
**Why this is real:** Searched all test files for patterns like `EXCEPT`, `dual-path`, `TIMESTAMP vs TIMESTAMPTZ`, and direct comparison queries. Found TZ SKIP parity tests in `test_consensus_gaps.sql` and `test_tz_api.sql`, but these verify TIMESTAMPTZ results independently -- none execute both APIs on the same input and assert result equivalence. TESTING_FRAMEWORK.md Category 8 explicitly requires: "TIMESTAMP vs TIMESTAMPTZ API: Same rule produces equivalent results through both paths."

---

## Rejected Issues (False Positives)

### Agent Issue #2: UNTIL Exit Condition NULL Check Inconsistency
**Reason:** The inner FOR loops iterate over query results, so `current` is guaranteed non-NULL within the loop body. The outer WHILE loop NULL check on `current` is defensive programming for the case where the inner loop returned zero rows and `current` was never assigned. The inconsistency is correct behavior, not a bug.

### Agent Issue #3: SKIP Drift Prevention Casting Differences Between TIMESTAMP and TZ Generators
**Reason:** The TZ generator operates on TIMESTAMP values internally but must compare against TIMESTAMPTZ `rule.until`. The `::TIMESTAMP` cast on assignment and `::TIMESTAMPTZ` cast on comparison are necessary type conversions for correctness. The extra `current IS NOT NULL` check follows the same defensive pattern as the outer loop. These differences are required by the different type contexts, not divergent logic.
