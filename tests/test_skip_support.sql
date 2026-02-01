/**
 * RFC 7529 SKIP Parameter Tests
 *
 * Tests the SKIP parameter for handling invalid dates in BYMONTHDAY:
 * - SKIP=OMIT (default): Skip invalid dates entirely
 * - SKIP=BACKWARD: Use last valid day of month
 * - SKIP=FORWARD: Use first day of next month
 *
 * Usage:
 *   psql -d your_database -f tests/test_skip_support.sql
 *
 * Expected output: All tests pass
 */

\set ON_ERROR_STOP on
\set ECHO all

-- Test database setup
-- Ensure we're testing in UTC timezone for consistency
SET timezone = 'UTC';

-- Install RRULE functions (allow override via -v rrule_install=...)
\if :{?rrule_install}
\i :rrule_install
\else
DROP SCHEMA IF EXISTS rrule CASCADE;
CREATE SCHEMA IF NOT EXISTS rrule;
\i src/rrule.sql
\endif

-- Ensure tests do not rely on search_path
SET search_path = public;

BEGIN;

\i tests/helpers.sql

-- Test results tracking
CREATE TEMP TABLE skip_test_results (
    test_number SERIAL PRIMARY KEY,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 1: SKIP=OMIT (Default RFC 7529 behavior)'
\echo '==================================================================='

-- Test 1: SKIP=OMIT on Feb 31 (explicit)
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=OMIT on Feb 31 (explicit)',
    assert_occurrences_equal(
        'SKIP=OMIT explicit',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=OMIT;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 2: SKIP=OMIT on Feb 31 (default, no SKIP parameter)
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=OMIT on Feb 31 (default)',
    assert_occurrences_equal(
        'SKIP=OMIT default',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 3: SKIP=OMIT on Feb 30
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=OMIT on Feb 30',
    assert_occurrences_equal(
        'SKIP=OMIT on day 30',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,
            '2025-03-30 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP,
            '2025-05-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=30;SKIP=OMIT;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 2: SKIP=BACKWARD (Use last valid day)'
\echo '==================================================================='

-- Test 4: SKIP=BACKWARD on Feb 31
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=BACKWARD on Feb 31',
    assert_occurrences_equal(
        'SKIP=BACKWARD on day 31',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 5: SKIP=BACKWARD on Feb 30
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=BACKWARD on Feb 30',
    assert_occurrences_equal(
        'SKIP=BACKWARD on day 30',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-30 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=30;SKIP=BACKWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 6: SKIP=BACKWARD with leap year
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=BACKWARD with leap year',
    assert_occurrences_equal(
        'SKIP=BACKWARD leap year',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2026-02-28 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;SKIP=BACKWARD;COUNT=3',
            '2024-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 3: SKIP=FORWARD (Use first of next month)'
\echo '==================================================================='

-- Test 7: SKIP=FORWARD on Feb 31
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=FORWARD on Feb 31',
    assert_occurrences_equal(
        'SKIP=FORWARD on day 31',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 8: SKIP=FORWARD on Feb 30
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=FORWARD on Feb 30',
    assert_occurrences_equal(
        'SKIP=FORWARD on day 30',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2025-03-30 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=30;SKIP=FORWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 4: Multiple BYMONTHDAY values with SKIP'
\echo '==================================================================='

-- Test 9: Multiple days with SKIP=BACKWARD (deduplication test)
INSERT INTO skip_test_results (test_name, status)
VALUES ('Multiple BYMONTHDAY with SKIP=BACKWARD',
    assert_occurrences_equal(
        'Multiple days BACKWARD',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-30 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=30,31;SKIP=BACKWARD;COUNT=5',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 10: Multiple days with SKIP=OMIT
INSERT INTO skip_test_results (test_name, status)
VALUES ('Multiple BYMONTHDAY with SKIP=OMIT',
    assert_occurrences_equal(
        'Multiple days OMIT',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-30 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=30,31;SKIP=OMIT;COUNT=5',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 5: SKIP with negative BYMONTHDAY (always valid)'
\echo '==================================================================='

-- Test 11: Negative BYMONTHDAY unaffected by SKIP
INSERT INTO skip_test_results (test_name, status)
VALUES ('Negative BYMONTHDAY ignores SKIP',
    assert_occurrences_equal(
        'Negative BYMONTHDAY',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-1;SKIP=FORWARD;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 6: SKIP with YEARLY frequency'
\echo '==================================================================='

-- Test 12: YEARLY with SKIP=BACKWARD
INSERT INTO skip_test_results (test_name, status)
VALUES ('YEARLY;BYMONTH=2;BYMONTHDAY=31;SKIP=BACKWARD',
    assert_occurrences_equal(
        'YEARLY SKIP=BACKWARD',
        ARRAY[
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2026-02-28 10:00:00'::TIMESTAMP,
            '2027-02-28 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 13: YEARLY with SKIP=OMIT (skips entire year)
INSERT INTO skip_test_results (test_name, status)
VALUES ('YEARLY;BYMONTH=2;BYMONTHDAY=31;SKIP=OMIT',
    assert_occurrences_equal(
        'YEARLY SKIP=OMIT',
        ARRAY[]::TIMESTAMP[],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=31;SKIP=OMIT;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 7: Time preservation with SKIP'
\echo '==================================================================='

-- Test 14: SKIP preserves time component
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP preserves time component',
    assert_occurrences_equal(
        'Time preservation',
        ARRAY[
            '2025-01-31 14:30:00'::TIMESTAMP,
            '2025-02-28 14:30:00'::TIMESTAMP,
            '2025-03-31 14:30:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=3',
            '2025-01-01 14:30:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 8: SKIP drift prevention (implicit SKIP without BYMONTHDAY)'
\echo '==================================================================='

-- Test 15: MONTHLY SKIP=BACKWARD drift prevention (Jan 31 start, no BYMONTHDAY)
-- Without drift fix: Jan 31, Feb 28, Mar 28, Apr 28, May 28, Jun 28 (drifts to 28)
-- With drift fix:    Jan 31, Feb 28, Mar 31, Apr 30, May 31, Jun 30 (restores to 31 when possible)
INSERT INTO skip_test_results (test_name, status)
VALUES ('MONTHLY SKIP=BACKWARD drift prevention (Jan 31)',
    assert_occurrences_equal(
        'MONTHLY BACKWARD drift',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-06-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;SKIP=BACKWARD;COUNT=6',
            '2025-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 16: YEARLY SKIP=BACKWARD drift prevention (Feb 29 leap year start)
-- Without drift fix: 2024-02-29, 2025-02-28, 2026-02-28, 2027-02-28, 2028-02-28 (drifts)
-- With drift fix:    2024-02-29, 2025-02-28, 2026-02-28, 2027-02-28, 2028-02-29 (restores on leap year)
INSERT INTO skip_test_results (test_name, status)
VALUES ('YEARLY SKIP=BACKWARD drift prevention (Feb 29)',
    assert_occurrences_equal(
        'YEARLY BACKWARD drift',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2026-02-28 10:00:00'::TIMESTAMP,
            '2027-02-28 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;SKIP=BACKWARD;COUNT=5',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 17: MONTHLY SKIP=OMIT drift prevention (Jan 31 start, no BYMONTHDAY)
-- Months without day 31 should be skipped entirely
INSERT INTO skip_test_results (test_name, status)
VALUES ('MONTHLY SKIP=OMIT drift prevention (Jan 31)',
    assert_occurrences_equal(
        'MONTHLY OMIT drift',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;SKIP=OMIT;COUNT=4',
            '2025-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 18: MONTHLY SKIP=FORWARD drift prevention (Jan 31 start, no BYMONTHDAY)
-- Each month attempts dtstart_day (31). When it doesn't exist (Feb, Apr, Jun),
-- SKIP=FORWARD advances to the 1st of the following month. Months that CAN hold
-- day 31 (Mar, May, Jul) restore to the 31st — no cumulative drift.
INSERT INTO skip_test_results (test_name, status)
VALUES ('MONTHLY SKIP=FORWARD drift prevention (Jan 31)',
    assert_occurrences_equal(
        'MONTHLY FORWARD drift',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;SKIP=FORWARD;COUNT=4',
            '2025-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 19: YEARLY SKIP=FORWARD drift prevention (Feb 29 leap year start)
-- Each year re-attempts Feb 29. Non-leap years forward to Mar 1.
-- Leap years (2028) restore to Feb 29 — no cumulative drift.
INSERT INTO skip_test_results (test_name, status)
VALUES ('YEARLY SKIP=FORWARD drift prevention (Feb 29)',
    assert_occurrences_equal(
        'YEARLY FORWARD drift',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2026-03-01 10:00:00'::TIMESTAMP,
            '2027-03-01 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;SKIP=FORWARD;COUNT=5',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 9: SKIP + INTERVAL > 1'
\echo '==================================================================='

-- Test 20: BACKWARD every 2 months from day 31
-- Months with 31 days keep it; months without (Sep=30, Nov=30) get BACKWARD adjustment
INSERT INTO skip_test_results (test_name, status)
VALUES ('MONTHLY INTERVAL=2 SKIP=BACKWARD from day 31',
    assert_occurrences_equal(
        'MONTHLY INTERVAL=2 BACKWARD',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP,
            '2025-09-30 10:00:00'::TIMESTAMP,
            '2025-11-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;INTERVAL=2;SKIP=BACKWARD;RSCALE=GREGORIAN;COUNT=6',
            '2025-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 21: FORWARD every 3 months from day 31
-- Apr has 30 days so FORWARD advances to May 1
INSERT INTO skip_test_results (test_name, status)
VALUES ('MONTHLY INTERVAL=3 SKIP=FORWARD from day 31',
    assert_occurrences_equal(
        'MONTHLY INTERVAL=3 FORWARD',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-05-01 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP,
            '2025-10-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;INTERVAL=3;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=4',
            '2025-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 22: OMIT every 2 months from day 31
-- Months without day 31 (Sep, Nov) are skipped; only 31-day months emit
INSERT INTO skip_test_results (test_name, status)
VALUES ('MONTHLY INTERVAL=2 SKIP=OMIT from day 31',
    assert_occurrences_equal(
        'MONTHLY INTERVAL=2 OMIT',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;INTERVAL=2;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=4',
            '2025-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 23: YEARLY INTERVAL=2 BACKWARD from leap day
-- Non-leap years get Feb 28; leap years restore to Feb 29
INSERT INTO skip_test_results (test_name, status)
VALUES ('YEARLY INTERVAL=2 SKIP=BACKWARD from leap day',
    assert_occurrences_equal(
        'YEARLY INTERVAL=2 BACKWARD',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2026-02-28 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP,
            '2030-02-28 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;INTERVAL=2;SKIP=BACKWARD;RSCALE=GREGORIAN;COUNT=4',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 24: YEARLY INTERVAL=2 FORWARD from leap day
-- Non-leap years forward to Mar 1; leap years restore to Feb 29
INSERT INTO skip_test_results (test_name, status)
VALUES ('YEARLY INTERVAL=2 SKIP=FORWARD from leap day',
    assert_occurrences_equal(
        'YEARLY INTERVAL=2 FORWARD',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2026-03-01 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;INTERVAL=2;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=3',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 25: YEARLY BYMONTH=2 with day 30 overflow
-- Jan 30 dtstart, BYMONTH=2 targets Feb which has no day 30; FORWARD to Mar 1
INSERT INTO skip_test_results (test_name, status)
VALUES ('YEARLY BYMONTH=2 SKIP=FORWARD day 30 overflow',
    assert_occurrences_equal(
        'YEARLY BYMONTH=2 FORWARD overflow',
        ARRAY[
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2026-03-01 10:00:00'::TIMESTAMP,
            '2027-03-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=2;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=3',
            '2025-01-30 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP: SKIP=FORWARD + UNTIL boundary (NULL check consistency)'
\echo '==================================================================='

-- Test: SKIP=FORWARD MONTHLY with UNTIL that falls before forwarded date
-- BYMONTHDAY=31 starting Jan 31. Feb has no 31st, FORWARD => Mar 1.
-- UNTIL=2025-02-28 should stop before the forwarded Mar 1 date.
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=FORWARD MONTHLY + UNTIL boundary',
    assert_occurrences_equal(
        'SKIP=FORWARD MONTHLY UNTIL boundary',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;RSCALE=GREGORIAN;UNTIL=20250228T100000Z',
            '2025-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test: SKIP=FORWARD YEARLY with UNTIL that falls before forwarded date
-- BYMONTH=2 starting Jan 30. Feb has no 30th in 2025, FORWARD => Mar 1 2025.
-- UNTIL=2025-02-28 should stop before the forwarded Mar 1 date.
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=FORWARD YEARLY + UNTIL boundary',
    assert_occurrences_equal(
        'SKIP=FORWARD YEARLY UNTIL boundary',
        ARRAY[]::TIMESTAMP[],
        (SELECT COALESCE(array_agg(occurrence ORDER BY occurrence), ARRAY[]::TIMESTAMP[]) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;SKIP=FORWARD;RSCALE=GREGORIAN;UNTIL=20250228T100000Z',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP: SKIP=OMIT maxdate/UNTIL boundary checks'
\echo '==================================================================='

-- Test: SKIP=OMIT MONTHLY with UNTIL that falls within omitted range
-- BYMONTHDAY=31 starting Jan 31 2024 with INTERVAL=1.
-- Feb, Apr have no 31st => omitted. UNTIL=2024-04-15.
-- Expected: Jan 31, Mar 31
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=OMIT MONTHLY + UNTIL boundary',
    assert_occurrences_equal(
        'SKIP=OMIT MONTHLY UNTIL boundary',
        ARRAY[
            '2024-01-31 10:00:00'::TIMESTAMP,
            '2024-03-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=OMIT;RSCALE=GREGORIAN;UNTIL=20240415T100000Z',
            '2024-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test: SKIP=OMIT MONTHLY with narrow maxdate window via between()
-- BYMONTHDAY=31 starting Jan 31 2024. Window ends Mar 1 2024.
-- Feb has no 31st => omitted. Mar 31 > maxdate. Only Jan 31 fits.
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=OMIT MONTHLY + narrow maxdate',
    assert_occurrences_equal(
        'SKIP=OMIT MONTHLY narrow maxdate',
        ARRAY[
            '2024-01-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=OMIT;RSCALE=GREGORIAN',
            '2024-01-31 10:00:00'::TIMESTAMP,
            '2024-01-01 00:00:00'::TIMESTAMP,
            '2024-03-01 00:00:00'::TIMESTAMP,
            true
        ) AS occurrence)
    )
);

-- Test: SKIP=OMIT MONTHLY with INTERVAL=2 and UNTIL
-- BYMONTHDAY=31 starting Jan 31 2024, INTERVAL=2.
-- Months: Jan(31), Mar(31), May(31), Jul(31), Sep(no 31, omit->Nov(no 31, omit->Jan 2025))
-- UNTIL=2024-08-15: Expected Jan 31, Mar 31, May 31, Jul 31
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=OMIT MONTHLY INTERVAL=2 + UNTIL',
    assert_occurrences_equal(
        'SKIP=OMIT MONTHLY INTERVAL=2 UNTIL',
        ARRAY[
            '2024-01-31 10:00:00'::TIMESTAMP,
            '2024-03-31 10:00:00'::TIMESTAMP,
            '2024-05-31 10:00:00'::TIMESTAMP,
            '2024-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=31;SKIP=OMIT;RSCALE=GREGORIAN;UNTIL=20240815T100000Z',
            '2024-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test: SKIP=OMIT YEARLY with UNTIL on Feb 29 (leap day)
-- Start Feb 29 2024 (leap year), INTERVAL=1.
-- 2025-2027 have no Feb 29 => omitted. UNTIL=2025-06-01.
-- Expected: only 2024-02-29
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=OMIT YEARLY leap day + UNTIL',
    assert_occurrences_equal(
        'SKIP=OMIT YEARLY leap day UNTIL',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;SKIP=OMIT;RSCALE=GREGORIAN;UNTIL=20250601T100000Z',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test: SKIP=OMIT YEARLY with INTERVAL=4 and UNTIL (leap day)
-- Start Feb 29 2024, INTERVAL=4. Next: 2028 (leap), 2032 (> UNTIL).
-- UNTIL=2030-01-01. Expected: 2024-02-29, 2028-02-29
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=OMIT YEARLY INTERVAL=4 leap day + UNTIL',
    assert_occurrences_equal(
        'SKIP=OMIT YEARLY INTERVAL=4 leap day UNTIL',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;INTERVAL=4;SKIP=OMIT;RSCALE=GREGORIAN;UNTIL=20300101T100000Z',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test: SKIP=OMIT MONTHLY INTERVAL=3 + narrow between() window
-- BYMONTHDAY=31, INTERVAL=3 starting Jan 31 2024.
-- Months: Jan(31), Apr(no 31, omit->Jul), Jul(31), Oct(31)...
-- Window: 2024-01-01 to 2024-08-01. Expected: Jan 31, Jul 31
INSERT INTO skip_test_results (test_name, status)
VALUES ('SKIP=OMIT MONTHLY INTERVAL=3 + narrow maxdate',
    assert_occurrences_equal(
        'SKIP=OMIT MONTHLY INTERVAL=3 narrow maxdate',
        ARRAY[
            '2024-01-31 10:00:00'::TIMESTAMP,
            '2024-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=31;SKIP=OMIT;RSCALE=GREGORIAN',
            '2024-01-31 10:00:00'::TIMESTAMP,
            '2024-01-01 00:00:00'::TIMESTAMP,
            '2024-08-01 00:00:00'::TIMESTAMP,
            true
        ) AS occurrence)
    )
);
\echo 'Test Results Summary'
\echo '==================================================================='

-- Display all test results
SELECT
    test_number,
    test_name,
    status
FROM skip_test_results
ORDER BY test_number;

-- Summary statistics
\echo ''
\echo 'Summary:'
SELECT
    COUNT(*) as total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') as passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') as failed
FROM skip_test_results;

-- Check if all tests passed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM skip_test_results
    WHERE status LIKE 'FAIL%';

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'SKIP TEST SUITE FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'SKIP TEST SUITE PASSED: All tests passed successfully!';
    END IF;
END $$;

ROLLBACK;
