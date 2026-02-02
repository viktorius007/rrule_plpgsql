# Safety & Security - Agent 2 Verified Issues

**Source transcript:** `agent-ad76bc5.jsonl`
**Issues found by agent:** 4
**Issues verified as real:** 1

---

## Issue 1: before() disables warning emission by using 50M output_limit

**Severity:** Medium
**Location:** `src/rrule.sql:2462-2476` (TIMESTAMP API) and `src/rrule.sql:3213-3222` (TIMESTAMPTZ API)
**Description:** The `before()` function passes `max_count=50000000` to the generator, which sets `output_limit` to 50M. The warning at line 2186 only fires when `emitted_count >= output_limit`, so warnings are effectively disabled for `before()`. Rules without COUNT or UNTIL that generate thousands of occurrences before the target date will never trigger the documented warning.
**Why this is real:** Confirmed at line 1953 that `output_limit := max_count`, and at lines 2186-2190 that the warning condition requires `emitted_count >= output_limit`. With output_limit=50M, no practical rule will hit this threshold. The `maxdate` parameter (set from user-provided `before_date` with no 10-year clamping at lines 2460, 3221) bounds iteration count but the warning pathway is genuinely dead. The generator loop at line 1971 (`current_base < maxdate`) prevents truly unbounded iteration, but a user calling `before()` with a date far in the future (e.g., year 9999) combined with a high-frequency rule lacking COUNT/UNTIL could force millions of iterations with no warning emitted. Severity downgraded from Critical to Medium because the `maxdate` constraint does prevent infinite loops, and realistic `before_date` values produce bounded work.

---

## False Positives

**Issue 2 (between() no 10-year window):** FALSE POSITIVE. The `between()` function is designed for user-specified ranges. The 1000 result cap (line 2327) remains enforced, and `period_limit` for DAILY at max_count=1000 is only 40,000 iterations -- well-bounded. The "10-year window" documented in CLAUDE.md applies to `all()`, not `between()`.

**Issue 3 (Sub-day INTERVAL bypass):** FALSE POSITIVE. Sub-day frequencies are disabled by default (line 2173). When enabled, the caps at lines 1221-1222 limit iteration count, and `maxdate` in the generator loop (line 1971) limits time span. Application-level INTERVAL validation is explicitly documented as required in `INCLUDING_SUBDAY_OPERATIONS.md`.

**Issue 4 (TIMESTAMPTZ before() O(N) memory):** FALSE POSITIVE. The sliding window at lines 3236-3238 trims the array to `count` elements, making memory O(count), not O(N). The `count` parameter is user-specified (required, no default), so memory scales with the requested result size, not total occurrences. For the typical before() use case (count=1), memory is O(1).
