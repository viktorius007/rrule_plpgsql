# Testing Standards

Prescriptive rules for writing and maintaining tests in rrule_plpgsql. These rules were established after a third-party test quality review and codify the patterns already followed by the majority of the test suite.

---

## Verified Issue Directives

### Rule 1: Always use ROLLBACK, never COMMIT

**Do:** End every test file with `ROLLBACK;`
**Don't:** Use `COMMIT;` — this persists non-temp functions and pollutes the rrule schema

All test files wrap their work in a `BEGIN;` ... `ROLLBACK;` transaction. This ensures that temporary test functions, helper tables, and any schema modifications are automatically cleaned up. Using `COMMIT` instead would leave test artifacts (e.g., `CREATE OR REPLACE FUNCTION` calls) permanently installed in the rrule schema.

### Rule 2: Use fixed reference timestamps, not NOW()

**Do:** Use fixed reference timestamps for all test inputs and assertions
**Don't:** Use `NOW()` anywhere in test files

NOW()-based assertions create race conditions and time-dependent failures. They also weaken assertions — checking "is in the future" can never detect wrong-date regressions. NOW()-based *inputs* make tests non-reproducible, since different dates produce different results.

The `next()` and `most_recent()` functions accept an optional `reference_time` parameter (defaults to `NOW()` when NULL). Tests should always provide a fixed value:

```sql
-- GOOD: deterministic, asserts exact value
SELECT rrule."next"(
    'FREQ=WEEKLY;TZID=Europe/London',
    '2020-01-01 10:00:00+00'::TIMESTAMPTZ,
    NULL,                                    -- timezone
    '2025-06-15 12:00:00+00'::TIMESTAMPTZ    -- reference_time
) INTO result;
assert_equal('next()', 'Returns correct date', result::TEXT, '2025-06-18 09:00:00+00');

-- BAD: non-deterministic, weak assertion
SELECT rrule."next"(...) INTO result;
assert_equal('next()', 'Is future', CASE WHEN result > NOW() THEN 'future' ELSE 'past' END, 'future');
```

If testing real-world query patterns (e.g., "subscriptions due in next 7 days"), use a hardcoded date that exercises the same code paths:

```sql
-- GOOD: fixed date exercises the same pattern
WHERE next_billing_date <= '2025-02-05 12:00:00+00'::TIMESTAMPTZ + INTERVAL '7 days'

-- BAD: non-deterministic
WHERE next_billing_date <= NOW() + INTERVAL '7 days'
```

### Rule 3: Assert exact values, never always-true conditions

**Do:** `COUNT(*) = 3` or compare full date arrays
**Don't:** `COUNT(*) >= 0` (always true for non-negative counts), `COUNT(*) > 0` (existence only), or `>= N` when the exact count is knowable

Always-true conditions can never detect regressions. Existence-only checks (`> 0`) miss cases where the wrong number of results is returned. If you cannot predict the exact count, your test inputs are non-deterministic — fix the inputs, not the assertion.

```sql
-- GOOD: exact count
SELECT COUNT(*) = 1 FROM rrule.daily_set(...)

-- BAD: always true (COUNT is never negative)
SELECT COUNT(*) >= 0 FROM rrule.daily_set(...)

-- BAD: only checks existence
SELECT COUNT(*) > 0 FROM rrule.daily_set(...)
```

### Rule 4: Verify dates, not just counts

**Do:** Compare against expected TIMESTAMP arrays for correctness tests
**Don't:** Only check count when actual date values matter

Wrong dates with the correct count is an undetected regression. When a test is verifying that a specific RRULE produces correct dates, assert the full array:

```sql
-- GOOD: verifies actual dates
expected := ARRAY[
    '2025-01-06 00:00:00'::TIMESTAMP,
    '2025-02-03 00:00:00'::TIMESTAMP,
    '2025-03-03 00:00:00'::TIMESTAMP
];
SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO;BYSETPOS=1;COUNT=3', '2025-01-01'::TIMESTAMP) AS t(occurrence);
IF actual = expected THEN ...

-- BAD: count only
SELECT COUNT(*) INTO result_count FROM rrule."all"(...);
IF result_count = 3 THEN ...  -- dates could all be wrong
```

### Rule 5: Do not declare unused function parameters

**Do:** Remove dead parameters immediately
**Don't:** Keep aspirational parameters "for future use"

Unused parameters mislead readers into thinking functionality is being tested that isn't. If a parameter was planned but never implemented, delete it.

### Rule 6: Use TEMP tables for test data

**Do:** `CREATE TEMP TABLE` for all test artifacts
**Don't:** Create permanent tables or functions outside transactions

All test files in this project run inside `BEGIN; ... ROLLBACK;` transactions. Use `CREATE TEMP TABLE` for data and `CREATE OR REPLACE FUNCTION` within the transaction for helper functions. Both are automatically cleaned up on ROLLBACK.

### Rule 7: Always use ORDER BY in array_agg

**Do:** `array_agg(occurrence ORDER BY occurrence)`
**Don't:** `array_agg(occurrence)` without ORDER BY

The SQL standard does not guarantee the order of aggregate inputs from set-returning functions. While PostgreSQL preserves SRF output order in practice, explicit ORDER BY is the standards-compliant approach and prevents silent regressions if internal implementation changes.

```sql
-- GOOD: explicit order guarantee
SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
FROM rrule."all"('FREQ=DAILY;COUNT=3', '2025-01-01'::TIMESTAMP) AS occurrence;

-- BAD: relies on implicit ordering
SELECT array_agg(occurrence) INTO actual
FROM rrule."all"('FREQ=DAILY;COUNT=3', '2025-01-01'::TIMESTAMP) AS occurrence;
```

### Rule 8: Test boundary and invalid inputs for all API functions

**Do:** Test inverted ranges (start > end), zero values (COUNT=0), and edge cases for every public API function
**Don't:** Assume callers will provide valid inputs — define and test behavior for all degenerate cases

```sql
-- GOOD: tests inverted range behavior
SELECT COUNT(*) FROM rrule."between"(
    'FREQ=DAILY;COUNT=10', '2025-01-01'::TIMESTAMP,
    '2025-01-10'::TIMESTAMP,  -- start (later)
    '2025-01-03'::TIMESTAMP   -- end (earlier)
);  -- Should return 0

-- GOOD: tests invalid COUNT
SELECT rrule."all"('FREQ=DAILY;COUNT=0', '2025-01-01'::TIMESTAMP);
-- Should raise: COUNT must be a positive integer
```

### Rule 9: Test DST gap and ambiguous times

**Do:** Include at least one test per timezone API function using a spring-forward gap time (e.g., 2:30 AM on March 9, 2025 for America/New_York) and one fall-back ambiguous time (e.g., 1:30 AM on November 2, 2025)
**Don't:** Only test "safe" wall-clock times like 10:00 AM that avoid DST transitions

Gap times (times that don't exist due to spring-forward) and ambiguous times (times that occur twice due to fall-back) are where timezone handling is most likely to have bugs.

### Rule 10: Test deduplication for overlapping BYxxx rules

**Do:** Include at least one test where multiple BYxxx parameters produce the same date (e.g., `BYDAY=MO` + `BYMONTHDAY=6` when the 6th is a Monday)
**Don't:** Only test deduplication through SKIP parameter cases

```sql
-- GOOD: verifies no duplicate dates when BYDAY and BYMONTHDAY overlap
SELECT (COUNT(*) = COUNT(DISTINCT occurrence))::TEXT FROM rrule."all"(
    'FREQ=MONTHLY;BYDAY=MO;BYMONTHDAY=6;COUNT=12',
    '2025-01-01 10:00:00'::TIMESTAMP
) AS occurrence;
```

---

## Incorrectly-Claimed Issues (Clarifications)

The following issues were raised in a third-party review but are not actual problems. They are documented here to prevent future re-investigation.

### Clarification B: SQLERRM validation is appropriate for this codebase

All `RAISE EXCEPTION` calls in rrule.sql use the default form (no explicit SQLSTATE). PostgreSQL assigns SQLSTATE `P0001` (raise_exception) to all such calls — every error has an identical SQLSTATE. Checking SQLSTATE would add zero discriminating value.

The distinctive error message patterns (e.g., `'%FREQ parameter is required%'`) are the only meaningful differentiator between different validation errors.

Source: PostgreSQL documentation: "If no condition name nor SQLSTATE is specified in a RAISE EXCEPTION command, the default is to use raise_exception (P0001)."

### Clarification C: DST edge cases are extensively tested

40+ DST tests exist across `test_tz_api.sql` and `test_tzid_support.sql`, covering:
- Spring-forward (March 9, 2025) — wall-clock time preservation
- Fall-back (November 2, 2025) — wall-clock time preservation
- Gap times (2:30 AM during spring-forward) and ambiguous times (1:30 AM during fall-back)
- Multiple timezones (America/New_York, Europe/London, Asia/Tokyo, Australia/Sydney)
- Southern Hemisphere DST transitions

### Clarification D: overlaps() edge cases are well-covered

20+ scenarios exist across `test_coverage_gaps.sql` (16 tests, including inverted dtend/dtstart) and `test_tz_api.sql` (6 timezone scenarios), covering:
- Exact boundary conditions (inclusive/exclusive)
- NULL RRULE handling
- Zero-duration events
- Inverted event intervals (dtend < dtstart)
- All frequency variations (DAILY, WEEKLY, MONTHLY, YEARLY)
- Cross-timezone conflict detection

### Clarification E: COUNT+UNTIL mutual exclusion is correct per RFC 5545

RFC 5545 Section 3.3.10: "The UNTIL or COUNT rule parts are OPTIONAL, but they MUST NOT occur in the same 'recur'." (MUST NOT per RFC 2119 = absolute prohibition.) Testing behavioral interaction of COUNT+UNTIL is not meaningful — the combination is invalid and correctly rejected.

### Clarification F: Empty-result rules (BYMONTHDAY=31 for February) are tested

17+ tests across `test_skip_support.sql`, `test_rfc_compliance.sql`, and `test_rrule_functions.sql` cover BYMONTHDAY=31 with all three SKIP modes (OMIT, BACKWARD, FORWARD). This is one of the most thoroughly tested edge cases in the suite.

### Clarification G: UNTIL before DTSTART is tested

`test_coverage_gaps.sql` Test 4.2 covers this scenario ("Returns NULL when UNTIL in past"), verifying that an UNTIL date before the reference time produces no future occurrences.

---

## See Also

- [DEVELOPMENT.md](DEVELOPMENT.md) — Development setup and contribution guidelines
- [DECISIONS.md](DECISIONS.md) — Architecture and design decision records
