/**
 * Iteration Limit and Boundary Tests
 *
 * Tests for:
 * - ISSUE-014: FREQ=DAILY + BYMONTHDAY iteration limit edge cases
 * - ISSUE-015: 10-year boundary exact match inclusion
 *
 * These tests verify that:
 * 1. DAILY + BYMONTHDAY=31 works even with worst-case dtstart positions
 * 2. Occurrences falling exactly on the 10-year boundary are included
 *
 * Usage:
 *   psql -d your_database -f tests/test_iteration_limits.sql
 *
 * Expected output: All tests pass
 */

\set ON_ERROR_STOP on
\set ECHO all

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
CREATE TEMP TABLE iteration_test_results (
    test_number SERIAL PRIMARY KEY,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 1: ISSUE-014 - DAILY + BYMONTHDAY iteration limits'
\echo '==================================================================='

-- Test 1: DAILY;BYMONTHDAY=31 worst case dtstart (Feb 1)
-- Feb 1 to Mar 31 = 58 days in non-leap year. Old multiplier (40) was insufficient.
INSERT INTO iteration_test_results (test_name, status)
VALUES ('DAILY;BYMONTHDAY=31 from Feb 1 (worst case gap)',
    assert_occurrences_equal(
        'DAILY BYMONTHDAY=31 Feb 1 start',
        ARRAY[
            '2021-03-31 10:00:00'::TIMESTAMP,
            '2021-05-31 10:00:00'::TIMESTAMP,
            '2021-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;BYMONTHDAY=31;COUNT=3',
            '2021-02-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 2: DAILY;BYMONTHDAY=29 leap year edge case
-- Feb 29 exists in 2020, 2024, etc.
INSERT INTO iteration_test_results (test_name, status)
VALUES ('DAILY;BYMONTHDAY=29 leap year',
    assert_occurrences_equal(
        'DAILY BYMONTHDAY=29 leap year',
        ARRAY[
            '2020-01-29 10:00:00'::TIMESTAMP,
            '2020-02-29 10:00:00'::TIMESTAMP,
            '2020-03-29 10:00:00'::TIMESTAMP,
            '2020-04-29 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;BYMONTHDAY=29;COUNT=4',
            '2020-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 3: DAILY;BYMONTHDAY=31;COUNT=5 needs ~200 days coverage
-- 5 occurrences of day 31: Jan, Mar, May, Jul, Aug (or later depending on start)
INSERT INTO iteration_test_results (test_name, status)
VALUES ('DAILY;BYMONTHDAY=31;COUNT=5',
    assert_occurrences_equal(
        'DAILY BYMONTHDAY=31 COUNT=5',
        ARRAY[
            '2021-01-31 10:00:00'::TIMESTAMP,
            '2021-03-31 10:00:00'::TIMESTAMP,
            '2021-05-31 10:00:00'::TIMESTAMP,
            '2021-07-31 10:00:00'::TIMESTAMP,
            '2021-08-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;BYMONTHDAY=31;COUNT=5',
            '2021-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 4: DAILY;BYMONTHDAY=30 from Feb 1 (similar worst case)
-- Feb has no 30th, so first occurrence is Mar 30 (57 days from Feb 1)
INSERT INTO iteration_test_results (test_name, status)
VALUES ('DAILY;BYMONTHDAY=30 from Feb 1',
    assert_occurrences_equal(
        'DAILY BYMONTHDAY=30 Feb 1 start',
        ARRAY[
            '2021-03-30 10:00:00'::TIMESTAMP,
            '2021-04-30 10:00:00'::TIMESTAMP,
            '2021-05-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;BYMONTHDAY=30;COUNT=3',
            '2021-02-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 5: Verify TIMESTAMPTZ API also handles BYMONTHDAY=31 worst case
INSERT INTO iteration_test_results (test_name, status)
SELECT
    'TIMESTAMPTZ: DAILY;BYMONTHDAY=31 from Feb 1',
    assert_occurrences_equal(
        'TZ DAILY BYMONTHDAY=31',
        ARRAY[
            '2021-03-31 10:00:00'::TIMESTAMP,
            '2021-05-31 10:00:00'::TIMESTAMP,
            '2021-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=DAILY;BYMONTHDAY=31;COUNT=3',
            '2021-02-01 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
         ) AS occurrence)
    );

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 2: ISSUE-015 - 10-year boundary inclusion'
\echo '==================================================================='

-- Test 6: YEARLY;COUNT=11 from 2015-01-01 should return 11 results (includes 2025-01-01)
-- The 11th occurrence (2025-01-01) is exactly at dtstart + 10 years
INSERT INTO iteration_test_results (test_name, status)
VALUES ('YEARLY;COUNT=11 includes 10-year boundary',
    assert_true(
        'YEARLY COUNT=11 boundary',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=YEARLY;COUNT=11',
            '2015-01-01 10:00:00'::TIMESTAMP
        )) = 11
    )
);

-- Test 7: Verify the actual dates for YEARLY;COUNT=11
INSERT INTO iteration_test_results (test_name, status)
VALUES ('YEARLY;COUNT=11 exact dates',
    assert_occurrences_equal(
        'YEARLY COUNT=11 dates',
        ARRAY[
            '2015-01-01 10:00:00'::TIMESTAMP,
            '2016-01-01 10:00:00'::TIMESTAMP,
            '2017-01-01 10:00:00'::TIMESTAMP,
            '2018-01-01 10:00:00'::TIMESTAMP,
            '2019-01-01 10:00:00'::TIMESTAMP,
            '2020-01-01 10:00:00'::TIMESTAMP,
            '2021-01-01 10:00:00'::TIMESTAMP,
            '2022-01-01 10:00:00'::TIMESTAMP,
            '2023-01-01 10:00:00'::TIMESTAMP,
            '2024-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;COUNT=11',
            '2015-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 8: MONTHLY;COUNT=121 returns 121 results (120 months = 10 years, plus dtstart)
-- 121st occurrence is exactly at dtstart + 10 years
INSERT INTO iteration_test_results (test_name, status)
VALUES ('MONTHLY;COUNT=121 includes 10-year boundary',
    assert_true(
        'MONTHLY COUNT=121 boundary',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=MONTHLY;COUNT=121',
            '2015-01-01 10:00:00'::TIMESTAMP
        )) = 121
    )
);

-- Test 9: MONTHLY;INTERVAL=4 with COUNT=21 (boundary from plan)
-- Starting 2020-06-30, every 4 months: Jun, Oct, Feb, Jun, Oct...
-- 21 occurrences span 80 months = 6 years 8 months
INSERT INTO iteration_test_results (test_name, status)
VALUES ('MONTHLY;INTERVAL=4;COUNT=21',
    assert_true(
        'MONTHLY INTERVAL=4 COUNT=21',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=MONTHLY;COUNT=21;INTERVAL=4',
            '2020-06-30 10:00:00'::TIMESTAMP
        )) = 21
    )
);

-- Test 9b: YEARLY;INTERVAL=2 at 10-year boundary (CLAUDE.md Rule 10)
-- Every 2 years from 2015: 2015,2017,2019,2021,2023,2025 = 6 results
-- 2025-01-01 is exactly at the 10-year boundary and should be included
INSERT INTO iteration_test_results (test_name, status)
VALUES ('YEARLY;INTERVAL=2 includes 10-year boundary',
    assert_occurrences_equal(
        'YEARLY INTERVAL=2 boundary',
        ARRAY[
            '2015-01-01 10:00:00'::TIMESTAMP,
            '2017-01-01 10:00:00'::TIMESTAMP,
            '2019-01-01 10:00:00'::TIMESTAMP,
            '2021-01-01 10:00:00'::TIMESTAMP,
            '2023-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;INTERVAL=2;COUNT=10',
            '2015-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 10: TIMESTAMPTZ API also includes 10-year boundary
INSERT INTO iteration_test_results (test_name, status)
SELECT
    'TIMESTAMPTZ: YEARLY;COUNT=11 includes boundary',
    assert_true(
        'TZ YEARLY COUNT=11 boundary',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=YEARLY;COUNT=11',
            '2015-01-01 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        )) = 11
    );

-- Test 11: WEEKLY at boundary - 521 weeks = ~10 years
-- 520 weeks = 3640 days = 9.97 years, 521 weeks = 3647 days = 9.99 years
INSERT INTO iteration_test_results (test_name, status)
VALUES ('WEEKLY;COUNT=521 near 10-year boundary',
    assert_true(
        'WEEKLY COUNT=521 boundary',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=521',
            '2015-01-01 10:00:00'::TIMESTAMP
        )) = 521
    )
);

-- Test 12: DAILY with between() at exact 10-year boundary
-- Use between() with range near the boundary to verify exact boundary is included.
-- dtstart + 10 years = 2025-01-01. Query includes the boundary with inc=true.
INSERT INTO iteration_test_results (test_name, status)
VALUES ('DAILY between() includes 10-year boundary',
    assert_true(
        'DAILY 10-year boundary via between',
        (SELECT COUNT(*) FROM rrule."between"(
            'FREQ=DAILY',
            '2015-01-01 10:00:00'::TIMESTAMP,
            '2024-12-31 10:00:00'::TIMESTAMP,
            '2025-01-01 10:00:00'::TIMESTAMP,
            TRUE  -- inc=true to include end boundary
        )) = 2  -- Dec 31 and Jan 1
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 3: Generator parity for iteration limits'
\echo '==================================================================='

-- Test 13: Verify TIMESTAMP and TIMESTAMPTZ APIs produce same results for BYMONTHDAY
INSERT INTO iteration_test_results (test_name, status)
VALUES ('Generator parity: DAILY;BYMONTHDAY=31',
    assert_generator_parity(
        'DAILY BYMONTHDAY=31 parity',
        'FREQ=DAILY;BYMONTHDAY=31;COUNT=5',
        '2021-01-01 10:00:00'::TIMESTAMP,
        'UTC'
    )
);

-- Test 14: Verify generator parity for 10-year boundary case
INSERT INTO iteration_test_results (test_name, status)
VALUES ('Generator parity: YEARLY;COUNT=11 boundary',
    assert_generator_parity(
        'YEARLY COUNT=11 parity',
        'FREQ=YEARLY;COUNT=11',
        '2015-01-01 10:00:00'::TIMESTAMP,
        'UTC'
    )
);

-- Test 15: Verify generator parity for INTERVAL > 1 at boundary (CLAUDE.md Rule 10)
INSERT INTO iteration_test_results (test_name, status)
VALUES ('Generator parity: YEARLY;INTERVAL=2 boundary',
    assert_generator_parity(
        'YEARLY INTERVAL=2 parity',
        'FREQ=YEARLY;INTERVAL=2;COUNT=10',
        '2015-01-01 10:00:00'::TIMESTAMP,
        'UTC'
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST SUMMARY'
\echo '==================================================================='

SELECT status, test_name FROM iteration_test_results ORDER BY test_number;

\echo ''
\echo '-------------------------------------------------------------------'

DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM iteration_test_results
    WHERE status LIKE 'FAIL%';

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'ITERATION LIMITS TEST SUITE FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'ITERATION LIMITS TEST SUITE PASSED: All tests passed successfully!';
    END IF;
END $$;

ROLLBACK;
