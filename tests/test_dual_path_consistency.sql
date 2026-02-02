/**
 * Dual-Path Consistency Tests
 *
 * Tests three coverage gaps:
 *
 * Issue 6:  BYSETPOS + TIMESTAMPTZ API across DST transitions.
 *           All prior BYSETPOS tests used the TIMESTAMP API only.
 *
 * Issue 8:  BYWEEKNO multi-year cross-year handling.
 *           No prior multi-year YEARLY loop test exists for BYWEEKNO with COUNT>3.
 *
 * Issue 14: Cross-validation between TIMESTAMP and TIMESTAMPTZ APIs.
 *           Verifies TZID-in-string (TIMESTAMP API) produces equivalent wall-clock
 *           times to the explicit timezone parameter (TIMESTAMPTZ API).
 *
 * Usage:
 *   psql -d your_database -f tests/test_dual_path_consistency.sql
 */

\set ON_ERROR_STOP on
\set ECHO all
\set QUIET off

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

\echo ''
\echo '==================================================================='
\echo 'Dual-Path Consistency Tests'
\echo '==================================================================='
\echo ''

-- Results table
CREATE TEMP TABLE dual_path_test_results (
    test_category TEXT,
    test_name TEXT,
    status TEXT
);

-- =====================================================================
-- Issue 6: BYSETPOS + TIMESTAMPTZ API across DST transitions
-- =====================================================================
\echo ''
\echo '==================================================================='
\echo 'Issue 6: BYSETPOS + TIMESTAMPTZ API across DST'
\echo '==================================================================='

-- Test 6.1: BYSETPOS=1,-1 with FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR through
-- TIMESTAMPTZ API across DST spring-forward (March 2025, America/New_York).
-- Spring forward: March 9, 2025 at 2:00 AM EST -> 3:00 AM EDT.
-- First weekday of Feb 2025 = Mon Feb 3; last weekday = Fri Feb 28.
-- First weekday of Mar 2025 = Mon Mar 3; last weekday = Mon Mar 31.
-- First weekday of Apr 2025 = Tue Apr 1; last weekday = Wed Apr 30.
-- dtstart is Feb 1, 2025 at 9:30 AM EST (before DST).
-- Wall-clock time 9:30 AM should be preserved across the transition.
--
-- We verify by converting TIMESTAMPTZ results to wall-clock TIMESTAMP in
-- America/New_York and asserting exact values.
DO $$
DECLARE
    tz_results TIMESTAMPTZ[];
    wall_clock TIMESTAMP[];
    expected TIMESTAMP[];
BEGIN
    -- Expected wall-clock times (9:30 AM preserved across DST)
    expected := ARRAY[
        '2025-02-03 09:30:00'::TIMESTAMP,
        '2025-02-28 09:30:00'::TIMESTAMP,
        '2025-03-03 09:30:00'::TIMESTAMP,
        '2025-03-31 09:30:00'::TIMESTAMP,
        '2025-04-01 09:30:00'::TIMESTAMP,
        '2025-04-30 09:30:00'::TIMESTAMP
    ];

    SELECT array_agg(ts ORDER BY ts) INTO tz_results
    FROM rrule."all"(
        'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=6',
        '2025-02-01 09:30:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    -- Convert TIMESTAMPTZ to wall-clock in target timezone
    SELECT array_agg((ts AT TIME ZONE 'America/New_York') ORDER BY ts) INTO wall_clock
    FROM unnest(tz_results) AS ts;

    INSERT INTO dual_path_test_results VALUES (
        'Issue 6: BYSETPOS+TZ DST',
        'BYSETPOS=1,-1 weekdays across spring-forward (TIMESTAMPTZ API)',
        assert_occurrences_equal(
            'BYSETPOS spring-forward TIMESTAMPTZ',
            expected,
            wall_clock
        )
    );
END;
$$;

-- Test 6.2: BYSETPOS=1 with FREQ=MONTHLY;BYDAY=SU through TIMESTAMPTZ API
-- across DST fall-back (November 2025, America/New_York).
-- Fall back: November 2, 2025 at 2:00 AM EDT -> 1:00 AM EST.
-- First Sunday of Oct 2025 = Oct 5; first Sunday of Nov 2025 = Nov 2;
-- first Sunday of Dec 2025 = Dec 7.
-- dtstart: Sep 7, 2025 at 10:00 AM EDT.
-- Wall-clock 10:00 AM preserved across fall-back.
DO $$
DECLARE
    tz_results TIMESTAMPTZ[];
    wall_clock TIMESTAMP[];
    expected TIMESTAMP[];
BEGIN
    expected := ARRAY[
        '2025-09-07 10:00:00'::TIMESTAMP,
        '2025-10-05 10:00:00'::TIMESTAMP,
        '2025-11-02 10:00:00'::TIMESTAMP,
        '2025-12-07 10:00:00'::TIMESTAMP
    ];

    SELECT array_agg(ts ORDER BY ts) INTO tz_results
    FROM rrule."all"(
        'FREQ=MONTHLY;BYDAY=SU;BYSETPOS=1;COUNT=4',
        '2025-09-07 10:00:00-04'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg((ts AT TIME ZONE 'America/New_York') ORDER BY ts) INTO wall_clock
    FROM unnest(tz_results) AS ts;

    INSERT INTO dual_path_test_results VALUES (
        'Issue 6: BYSETPOS+TZ DST',
        'BYSETPOS=1 first Sunday across fall-back (TIMESTAMPTZ API)',
        assert_occurrences_equal(
            'BYSETPOS fall-back TIMESTAMPTZ',
            expected,
            wall_clock
        )
    );
END;
$$;

-- Test 6.3: Compare BYSETPOS results between TIMESTAMP API (with TZID=) and
-- TIMESTAMPTZ API across spring-forward to ensure both paths agree.
DO $$
DECLARE
    ts_results TIMESTAMP[];
    tz_results TIMESTAMPTZ[];
    tz_as_wall TIMESTAMP[];
BEGIN
    -- TIMESTAMP API with TZID in string
    SELECT array_agg(occurrence ORDER BY occurrence) INTO ts_results
    FROM rrule."all"(
        'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;TZID=America/New_York;COUNT=6',
        '2025-02-01 09:30:00'::TIMESTAMP
    ) AS occurrence;

    -- TIMESTAMPTZ API with explicit timezone
    SELECT array_agg(ts ORDER BY ts) INTO tz_results
    FROM rrule."all"(
        'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=6',
        '2025-02-01 09:30:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    -- Convert TIMESTAMPTZ results to wall-clock (TIMESTAMP) in America/New_York
    SELECT array_agg((ts AT TIME ZONE 'America/New_York') ORDER BY ts) INTO tz_as_wall
    FROM unnest(tz_results) AS ts;

    INSERT INTO dual_path_test_results VALUES (
        'Issue 6: BYSETPOS+TZ DST',
        'BYSETPOS cross-API parity: TIMESTAMP(TZID) vs TIMESTAMPTZ spring-forward',
        assert_occurrences_equal(
            'BYSETPOS cross-API parity spring-forward',
            ts_results,
            tz_as_wall
        )
    );
END;
$$;

-- =====================================================================
-- Issue 8: BYWEEKNO multi-year cross-year handling
-- =====================================================================
\echo ''
\echo '==================================================================='
\echo 'Issue 8: BYWEEKNO multi-year cross-year handling'
\echo '==================================================================='

-- Test 8.1: FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO;COUNT=5 starting from 2024.
-- Verify COUNT=5 produces exactly 5 results and they are monotonically increasing.
INSERT INTO dual_path_test_results (test_category, test_name, status)
VALUES (
    'Issue 8: BYWEEKNO multi-year',
    'BYWEEKNO=1;BYDAY=MO;COUNT=5 produces 5 results',
    (SELECT assert_true(
        'BYWEEKNO=1 multi-year COUNT=5',
        (SELECT COUNT(*) = 5
         FROM rrule."all"(
             'FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO;COUNT=5',
             '2024-01-01 10:00:00'::TIMESTAMP
         ) AS occurrence)
    ))
);

INSERT INTO dual_path_test_results (test_category, test_name, status)
VALUES (
    'Issue 8: BYWEEKNO multi-year',
    'BYWEEKNO=1;BYDAY=MO;COUNT=5 dates are monotonically increasing',
    (SELECT assert_true(
        'BYWEEKNO=1 monotonic dates',
        (SELECT bool_and(curr > prev)
         FROM (
             SELECT occurrence AS curr,
                    LAG(occurrence) OVER (ORDER BY occurrence) AS prev
             FROM rrule."all"(
                 'FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO;COUNT=5',
                 '2024-01-01 10:00:00'::TIMESTAMP
             ) AS occurrence
         ) sub
         WHERE prev IS NOT NULL)
    ))
);

-- Test 8.2: FREQ=YEARLY;BYWEEKNO=53;BYDAY=MO;COUNT=2
-- Only years with 53 ISO weeks produce results. between() clamps to 10 years from dtstart.
-- 53-week ISO years starting from 2015 within 10yr window (to 2025): 2015, 2020.
INSERT INTO dual_path_test_results (test_category, test_name, status)
VALUES (
    'Issue 8: BYWEEKNO multi-year',
    'BYWEEKNO=53;BYDAY=MO;COUNT=2 skips non-53-week years',
    assert_occurrences_equal(
        'BYWEEKNO=53 multi-year COUNT=2',
        ARRAY[
            '2015-12-28 10:00:00'::TIMESTAMP,
            '2020-12-28 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=YEARLY;BYWEEKNO=53;BYDAY=MO;COUNT=2',
            '2015-01-01 10:00:00'::TIMESTAMP,
            '2015-01-01 10:00:00'::TIMESTAMP,
            '2027-12-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 8.3: FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO,FR;INTERVAL=2;COUNT=6
-- Every 2 years, ISO week 1, Monday and Friday. Verify correct count and ordering.
INSERT INTO dual_path_test_results (test_category, test_name, status)
VALUES (
    'Issue 8: BYWEEKNO multi-year',
    'BYWEEKNO=1;BYDAY=MO,FR;INTERVAL=2;COUNT=6 produces 6 results',
    (SELECT assert_true(
        'BYWEEKNO=1 INTERVAL=2 COUNT=6',
        (SELECT COUNT(*) = 6
         FROM rrule."all"(
             'FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO,FR;INTERVAL=2;COUNT=6',
             '2024-01-01 10:00:00'::TIMESTAMP
         ) AS occurrence)
    ))
);

INSERT INTO dual_path_test_results (test_category, test_name, status)
VALUES (
    'Issue 8: BYWEEKNO multi-year',
    'BYWEEKNO=1;BYDAY=MO,FR;INTERVAL=2;COUNT=6 dates are monotonically increasing',
    (SELECT assert_true(
        'BYWEEKNO=1 INTERVAL=2 monotonic',
        (SELECT bool_and(curr > prev)
         FROM (
             SELECT occurrence AS curr,
                    LAG(occurrence) OVER (ORDER BY occurrence) AS prev
             FROM rrule."all"(
                 'FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO,FR;INTERVAL=2;COUNT=6',
                 '2024-01-01 10:00:00'::TIMESTAMP
             ) AS occurrence
         ) sub
         WHERE prev IS NOT NULL)
    ))
);

-- Test 8.4: BYWEEKNO=53 with BYDAY=TH;COUNT=2 (Thursday of week 53)
-- between() clamps to 10 years from dtstart, so only 2015 and 2020 are reachable.
INSERT INTO dual_path_test_results (test_category, test_name, status)
VALUES (
    'Issue 8: BYWEEKNO multi-year',
    'BYWEEKNO=53;BYDAY=TH;COUNT=2 exact dates',
    assert_occurrences_equal(
        'BYWEEKNO=53 BYDAY=TH COUNT=2',
        ARRAY[
            '2015-12-31 10:00:00'::TIMESTAMP,
            '2020-12-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=YEARLY;BYWEEKNO=53;BYDAY=TH;COUNT=2',
            '2015-01-01 10:00:00'::TIMESTAMP,
            '2015-01-01 10:00:00'::TIMESTAMP,
            '2027-12-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- =====================================================================
-- Issue 14: Cross-API parity (TIMESTAMP vs TIMESTAMPTZ)
-- =====================================================================
\echo ''
\echo '==================================================================='
\echo 'Issue 14: Cross-API parity (TIMESTAMP vs TIMESTAMPTZ)'
\echo '==================================================================='

-- Test 14.1: DAILY;COUNT=5 -- TIMESTAMP API (TZID=) vs TIMESTAMPTZ API
DO $$
DECLARE
    ts_results TIMESTAMP[];
    tz_results TIMESTAMPTZ[];
    tz_as_wall TIMESTAMP[];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO ts_results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=5;TZID=America/New_York',
        '2025-06-01 09:00:00'::TIMESTAMP
    ) AS occurrence;

    SELECT array_agg(ts ORDER BY ts) INTO tz_results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=5',
        '2025-06-01 09:00:00-04'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg((ts AT TIME ZONE 'America/New_York') ORDER BY ts) INTO tz_as_wall
    FROM unnest(tz_results) AS ts;

    INSERT INTO dual_path_test_results VALUES (
        'Issue 14: Cross-API parity',
        'DAILY;COUNT=5 TIMESTAMP(TZID) = TIMESTAMPTZ wall-clock (no DST crossing)',
        assert_occurrences_equal('DAILY cross-API no DST', ts_results, tz_as_wall)
    );
END;
$$;

-- Test 14.2: WEEKLY;COUNT=5 -- cross-API parity
DO $$
DECLARE
    ts_results TIMESTAMP[];
    tz_results TIMESTAMPTZ[];
    tz_as_wall TIMESTAMP[];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO ts_results
    FROM rrule."all"(
        'FREQ=WEEKLY;COUNT=5;TZID=America/New_York',
        '2025-07-07 14:00:00'::TIMESTAMP
    ) AS occurrence;

    SELECT array_agg(ts ORDER BY ts) INTO tz_results
    FROM rrule."all"(
        'FREQ=WEEKLY;COUNT=5',
        '2025-07-07 14:00:00-04'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg((ts AT TIME ZONE 'America/New_York') ORDER BY ts) INTO tz_as_wall
    FROM unnest(tz_results) AS ts;

    INSERT INTO dual_path_test_results VALUES (
        'Issue 14: Cross-API parity',
        'WEEKLY;COUNT=5 TIMESTAMP(TZID) = TIMESTAMPTZ wall-clock (no DST crossing)',
        assert_occurrences_equal('WEEKLY cross-API no DST', ts_results, tz_as_wall)
    );
END;
$$;

-- Test 14.3: MONTHLY;COUNT=5 -- cross-API parity
DO $$
DECLARE
    ts_results TIMESTAMP[];
    tz_results TIMESTAMPTZ[];
    tz_as_wall TIMESTAMP[];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO ts_results
    FROM rrule."all"(
        'FREQ=MONTHLY;COUNT=5;TZID=America/New_York',
        '2025-08-15 11:00:00'::TIMESTAMP
    ) AS occurrence;

    SELECT array_agg(ts ORDER BY ts) INTO tz_results
    FROM rrule."all"(
        'FREQ=MONTHLY;COUNT=5',
        '2025-08-15 11:00:00-04'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg((ts AT TIME ZONE 'America/New_York') ORDER BY ts) INTO tz_as_wall
    FROM unnest(tz_results) AS ts;

    INSERT INTO dual_path_test_results VALUES (
        'Issue 14: Cross-API parity',
        'MONTHLY;COUNT=5 TIMESTAMP(TZID) = TIMESTAMPTZ wall-clock (no DST crossing)',
        assert_occurrences_equal('MONTHLY cross-API no DST', ts_results, tz_as_wall)
    );
END;
$$;

-- Test 14.4: DAILY;COUNT=7 across DST spring-forward -- cross-API parity
-- March 8-14, 2025 (spring forward on March 9 in America/New_York)
DO $$
DECLARE
    ts_results TIMESTAMP[];
    tz_results TIMESTAMPTZ[];
    tz_as_wall TIMESTAMP[];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO ts_results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=7;TZID=America/New_York',
        '2025-03-08 10:00:00'::TIMESTAMP
    ) AS occurrence;

    SELECT array_agg(ts ORDER BY ts) INTO tz_results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=7',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg((ts AT TIME ZONE 'America/New_York') ORDER BY ts) INTO tz_as_wall
    FROM unnest(tz_results) AS ts;

    INSERT INTO dual_path_test_results VALUES (
        'Issue 14: Cross-API parity',
        'DAILY;COUNT=7 across DST spring-forward: both APIs preserve wall-clock time',
        assert_occurrences_equal('DAILY cross-API spring-forward', ts_results, tz_as_wall)
    );
END;
$$;

-- Test 14.5: WEEKLY;COUNT=4 across DST fall-back -- cross-API parity
-- October 25 through November 15, 2025 (fall back on Nov 2)
DO $$
DECLARE
    ts_results TIMESTAMP[];
    tz_results TIMESTAMPTZ[];
    tz_as_wall TIMESTAMP[];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO ts_results
    FROM rrule."all"(
        'FREQ=WEEKLY;COUNT=4;TZID=America/New_York',
        '2025-10-25 10:00:00'::TIMESTAMP
    ) AS occurrence;

    SELECT array_agg(ts ORDER BY ts) INTO tz_results
    FROM rrule."all"(
        'FREQ=WEEKLY;COUNT=4',
        '2025-10-25 10:00:00-04'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg((ts AT TIME ZONE 'America/New_York') ORDER BY ts) INTO tz_as_wall
    FROM unnest(tz_results) AS ts;

    INSERT INTO dual_path_test_results VALUES (
        'Issue 14: Cross-API parity',
        'WEEKLY;COUNT=4 across DST fall-back: both APIs preserve wall-clock time',
        assert_occurrences_equal('WEEKLY cross-API fall-back', ts_results, tz_as_wall)
    );
END;
$$;

-- Test 14.6: MONTHLY;COUNT=6 across spring-forward -- cross-API parity
-- Start January 2025, runs through June 2025 (crosses spring-forward in March)
DO $$
DECLARE
    ts_results TIMESTAMP[];
    tz_results TIMESTAMPTZ[];
    tz_as_wall TIMESTAMP[];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO ts_results
    FROM rrule."all"(
        'FREQ=MONTHLY;COUNT=6;TZID=America/New_York',
        '2025-01-15 08:30:00'::TIMESTAMP
    ) AS occurrence;

    SELECT array_agg(ts ORDER BY ts) INTO tz_results
    FROM rrule."all"(
        'FREQ=MONTHLY;COUNT=6',
        '2025-01-15 08:30:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg((ts AT TIME ZONE 'America/New_York') ORDER BY ts) INTO tz_as_wall
    FROM unnest(tz_results) AS ts;

    INSERT INTO dual_path_test_results VALUES (
        'Issue 14: Cross-API parity',
        'MONTHLY;COUNT=6 across spring-forward: both APIs preserve wall-clock time',
        assert_occurrences_equal('MONTHLY cross-API spring-forward', ts_results, tz_as_wall)
    );
END;
$$;

-- Test 14.7: Verify wall-clock time preservation explicitly for DST crossing
-- Both APIs must produce 10:00 AM wall-clock in every occurrence across spring-forward.
DO $$
DECLARE
    ts_results TIMESTAMP[];
    all_same_time BOOLEAN;
BEGIN
    -- TIMESTAMP API
    SELECT array_agg(occurrence ORDER BY occurrence) INTO ts_results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=5;TZID=America/New_York',
        '2025-03-08 10:00:00'::TIMESTAMP
    ) AS occurrence;

    SELECT bool_and(occurrence::TIME = '10:00:00'::TIME) INTO all_same_time
    FROM unnest(ts_results) AS occurrence;

    INSERT INTO dual_path_test_results VALUES (
        'Issue 14: Cross-API parity',
        'TIMESTAMP API preserves 10:00 AM wall-clock across spring-forward',
        assert_true('TIMESTAMP wall-clock preservation', all_same_time)
    );

    -- TIMESTAMPTZ API: check wall-clock times in target timezone
    SELECT bool_and((ts AT TIME ZONE 'America/New_York')::TIME = '10:00:00'::TIME) INTO all_same_time
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=5',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    INSERT INTO dual_path_test_results VALUES (
        'Issue 14: Cross-API parity',
        'TIMESTAMPTZ API preserves 10:00 AM wall-clock across spring-forward',
        assert_true('TIMESTAMPTZ wall-clock preservation', all_same_time)
    );
END;
$$;

-- =====================================================================
-- Print Test Results
-- =====================================================================
\echo ''
\echo '==================================================================='
\echo 'Test Results'
\echo '==================================================================='
\echo ''

SELECT
    test_category,
    test_name,
    CASE
        WHEN status LIKE 'PASS%' THEN '[PASS] ' || test_name
        ELSE '[FAIL] ' || test_name || ' - ' || status
    END AS result
FROM dual_path_test_results
ORDER BY test_category, test_name;

-- Final pass/fail summary
DO $$
DECLARE
    failed_count INT;
    total_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM dual_path_test_results
    WHERE status NOT LIKE 'PASS%';

    SELECT COUNT(*) INTO total_count
    FROM dual_path_test_results;

    RAISE NOTICE '';
    RAISE NOTICE '===================================================================';
    IF failed_count = 0 THEN
        RAISE NOTICE 'Dual-Path Consistency Tests: % / % PASSED', total_count, total_count;
        RAISE NOTICE '===================================================================';
    ELSE
        RAISE NOTICE 'Dual-Path Consistency Tests: % / % FAILED', failed_count, total_count;
        RAISE NOTICE '===================================================================';
        RAISE EXCEPTION 'Dual-path consistency tests failed';
    END IF;
END $$;

ROLLBACK;
