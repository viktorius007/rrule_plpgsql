/**
 * Performance Optimization Tests
 *
 * Tests all performance optimizations implemented in rrule_plpgsql:
 * - max_results early exit optimization (prevents over-generation)
 * - Helper functions (weekday_to_number, number_to_weekday)
 * - make_interval() usage (type-safe interval construction)
 * - date_part() instead of to_char() (faster weekday filtering)
 *
 * Usage:
 *   psql -d your_database -f tests/test_optimizations.sql
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

-- Helper function: Verify that a rule produces exactly the expected number of results
-- Note: this checks output count only, not the actual dates — see Category 5 tests for date correctness verification.
CREATE OR REPLACE FUNCTION verify_result_count(
    freq TEXT,
    byday_rule TEXT,
    count_limit INT
) RETURNS TEXT AS $$
DECLARE
    actual_result_count INT;
    rrule_string CHARACTER VARYING;
    results TIMESTAMP[];
BEGIN
    rrule_string := 'FREQ=' || freq;
    IF byday_rule IS NOT NULL THEN
        rrule_string := rrule_string || ';BYDAY=' || byday_rule;
    END IF;
    rrule_string := rrule_string || ';COUNT=' || count_limit;

    -- Use array_agg instead of COUNT to avoid PL/pgSQL SETOF function issues
    -- Note: Use rrule."all" for fully qualified name (all is a reserved word)
    SELECT array_agg(occurrence ORDER BY occurrence) INTO results
    FROM rrule."all"(rrule_string, '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence;

    actual_result_count := COALESCE(array_length(results, 1), 0);

    IF actual_result_count != count_limit THEN
        RETURN 'FAILED - Got ' || actual_result_count || ' results, expected ' || count_limit;
    END IF;

    RETURN 'PASSED';
END;
$$ LANGUAGE plpgsql;

\echo ''
\echo '==================================================================='
\echo 'Performance Optimization Tests'
\echo '==================================================================='
\echo ''
\echo 'These tests verify all performance optimizations work correctly:'
\echo '- max_results early exit: Stop generating dates when COUNT reached'
\echo '- Helper functions: Efficient weekday conversion'
\echo '- make_interval(): Type-safe interval construction'
\echo '- date_part(): Fast numeric weekday filtering'
\echo ''

-- Create test results table
CREATE TEMP TABLE optimization_test_results (
    test_category TEXT,
    test_name TEXT,
    status TEXT,
    notes TEXT
);

------------------------------------------------------------------------------------------------------
-- Category 1: Early Exit Optimization (max_results parameter)
------------------------------------------------------------------------------------------------------
\echo '==================================================================='
\echo 'Category 1: Early Exit Optimization'
\echo '==================================================================='

-- Test 1.1: MONTHLY + BYDAY with small COUNT
-- Before optimization: Would generate 4-5 Mondays per month, use only 1
-- After optimization: Should generate only 1 Monday
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Early Exit: MONTHLY BYDAY',
    'COUNT=1 with BYDAY=MO (should generate only 1 date)',
    verify_result_count('MONTHLY', 'MO', 1)
);

INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Early Exit: MONTHLY BYDAY',
    'COUNT=2 with BYDAY=MO (should generate only 2 dates)',
    verify_result_count('MONTHLY', 'MO', 2)
);

-- Test 1.2: MONTHLY + BYDAY with multiple days
-- Before optimization: Would generate ~12-15 dates (all MO/WE/FR in month)
-- After optimization: Should stop at COUNT limit
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Early Exit: MONTHLY BYDAY Multiple',
    'COUNT=3 with BYDAY=MO,WE,FR (should stop at 3)',
    verify_result_count('MONTHLY', 'MO,WE,FR', 3)
);

INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Early Exit: MONTHLY BYDAY Multiple',
    'COUNT=10 with BYDAY=MO,WE,FR (should stop at 10)',
    verify_result_count('MONTHLY', 'MO,WE,FR', 10)
);

-- Test 1.3: WEEKLY + BYDAY early exit
-- Before optimization: Would generate all 7 days
-- After optimization: Should stop at COUNT limit
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Early Exit: WEEKLY BYDAY',
    'COUNT=2 with BYDAY=MO,TU,WE,TH,FR (should stop at 2)',
    verify_result_count('WEEKLY', 'MO,TU,WE,TH,FR', 2)
);

-- Test 1.4: DAILY early exit
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Early Exit: DAILY',
    'COUNT=10 (should generate exactly 10 dates)',
    verify_result_count('DAILY', NULL, 10)
);

-- Test 1.5: Complex case - MONTHLY with BYMONTHDAY
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Early Exit: MONTHLY BYMONTHDAY',
    'COUNT=5 with BYMONTHDAY=1,15,31',
    assert_equals(
        'MONTHLY BYMONTHDAY count',
        '5',
        (SELECT COALESCE(array_length(array_agg(occurrence ORDER BY occurrence), 1), 0)::TEXT
         FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=1,15,31;COUNT=5', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

-- Test 1.6: Edge case - COUNT=1 (absolute minimum)
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Early Exit: Edge Cases',
    'COUNT=1 with complex BYDAY (should generate exactly 1)',
    verify_result_count('MONTHLY', 'MO,TU,WE,TH,FR,SA,SU', 1)
);

------------------------------------------------------------------------------------------------------
-- Category 2: Helper Functions
------------------------------------------------------------------------------------------------------
\echo ''
\echo '==================================================================='
\echo 'Category 2: Helper Functions'
\echo '==================================================================='

-- Test 2.1: weekday_to_number() helper
-- FREQ=MONTHLY;BYDAY=MO;COUNT=3 from 2025-01-01 10:00:00
-- BYDAY=MO without ordinal in MONTHLY expands to ALL Mondays per month
-- First 3 Mondays in January 2025: Jan 6, 13, 20
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Helper Functions',
    'weekday_to_number() with MONTHLY BYDAY=MO',
    assert_occurrences_equal(
        'weekday_to_number() helper',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-13 10:00:00'::TIMESTAMP,
            '2025-01-20 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 2.2: number_to_weekday() helper (used by date_part optimization)
-- This is tested implicitly by date_part tests below

------------------------------------------------------------------------------------------------------
-- Category 3: make_interval() Usage
------------------------------------------------------------------------------------------------------
\echo ''
\echo '==================================================================='
\echo 'Category 3: make_interval() Usage'
\echo '==================================================================='

-- Test 3.1: WEEKLY with make_interval
-- FREQ=WEEKLY;BYDAY=MO,TU,WE;COUNT=9 from 2025-01-01 (Wednesday)
-- Week 1: Wed Jan 1
-- Week 2: Mon Jan 6, Tue Jan 7, Wed Jan 8
-- Week 3: Mon Jan 13, Tue Jan 14, Wed Jan 15
-- Week 4: Mon Jan 20, Tue Jan 21 (stops at 9)
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'make_interval()',
    'WEEKLY BYDAY=MO,TU,WE COUNT=9',
    assert_occurrences_equal(
        'make_interval() WEEKLY',
        ARRAY[
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-06 00:00:00'::TIMESTAMP,
            '2025-01-07 00:00:00'::TIMESTAMP,
            '2025-01-08 00:00:00'::TIMESTAMP,
            '2025-01-13 00:00:00'::TIMESTAMP,
            '2025-01-14 00:00:00'::TIMESTAMP,
            '2025-01-15 00:00:00'::TIMESTAMP,
            '2025-01-20 00:00:00'::TIMESTAMP,
            '2025-01-21 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,TU,WE;COUNT=9', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

-- Test 3.2: YEARLY with BYMONTH using make_interval
-- FREQ=YEARLY;BYMONTH=1,6,12;COUNT=6 from 2025-01-01
-- Year 1: Jan 1, Jun 1, Dec 1
-- Year 2: Jan 1, Jun 1, Dec 1
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'make_interval()',
    'YEARLY BYMONTH=1,6,12 COUNT=6',
    assert_occurrences_equal(
        'make_interval() YEARLY',
        ARRAY[
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-06-01 00:00:00'::TIMESTAMP,
            '2025-12-01 00:00:00'::TIMESTAMP,
            '2026-01-01 00:00:00'::TIMESTAMP,
            '2026-06-01 00:00:00'::TIMESTAMP,
            '2026-12-01 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=YEARLY;BYMONTH=1,6,12;COUNT=6', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

------------------------------------------------------------------------------------------------------
-- Category 4: date_part() Optimization
------------------------------------------------------------------------------------------------------
\echo ''
\echo '==================================================================='
\echo 'Category 4: date_part() Optimization'
\echo '==================================================================='

-- Test 4.1: date_part() with DAILY + BYDAY filter
-- FREQ=DAILY;BYDAY=MO;UNTIL=20250131T235959Z from 2025-01-01
-- Every day in January 2025, but only Mondays: Jan 6, 13, 20, 27
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'date_part()',
    'DAILY with BYDAY=MO filter',
    assert_occurrences_equal(
        'date_part() DAILY',
        ARRAY[
            '2025-01-06 00:00:00'::TIMESTAMP,
            '2025-01-13 00:00:00'::TIMESTAMP,
            '2025-01-20 00:00:00'::TIMESTAMP,
            '2025-01-27 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=DAILY;BYDAY=MO;UNTIL=20250131T235959Z', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

-- Test 4.2: date_part() with WEEKLY + BYDAY
-- FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=9 from 2025-01-01 (Wednesday)
-- Week 1: Wed Jan 1, Fri Jan 3
-- Week 2: Mon Jan 6, Wed Jan 8, Fri Jan 10
-- Week 3: Mon Jan 13, Wed Jan 15, Fri Jan 17
-- Week 4: Mon Jan 20 (stops at 9)
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'date_part()',
    'WEEKLY BYDAY=MO,WE,FR COUNT=9',
    assert_occurrences_equal(
        'date_part() WEEKLY',
        ARRAY[
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-03 00:00:00'::TIMESTAMP,
            '2025-01-06 00:00:00'::TIMESTAMP,
            '2025-01-08 00:00:00'::TIMESTAMP,
            '2025-01-10 00:00:00'::TIMESTAMP,
            '2025-01-13 00:00:00'::TIMESTAMP,
            '2025-01-15 00:00:00'::TIMESTAMP,
            '2025-01-17 00:00:00'::TIMESTAMP,
            '2025-01-20 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=9', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

------------------------------------------------------------------------------------------------------
-- Category 5: Correctness Verification
------------------------------------------------------------------------------------------------------
\echo ''
\echo '==================================================================='
\echo 'Category 5: Correctness Verification'
\echo '==================================================================='

-- Test 5.1: Verify dates are correct despite optimization
-- Expected: First 3 Mondays in 2025
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Correctness Verification',
    'WEEKLY BYDAY=MO produces correct dates',
    assert_occurrences_equal(
        'WEEKLY correctness',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-13 10:00:00'::TIMESTAMP,
            '2025-01-20 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 5.2: Verify MONTHLY BYDAY correctness
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Correctness Verification',
    'MONTHLY BYDAY=MO produces correct dates',
    assert_occurrences_equal(
        'MONTHLY correctness',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-13 10:00:00'::TIMESTAMP,
            '2025-01-20 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 5.3: Verify DAILY correctness
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Correctness Verification',
    'DAILY COUNT=10 produces correct consecutive dates',
    assert_occurrences_equal(
        'DAILY correctness',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            '2025-01-04 10:00:00'::TIMESTAMP,
            '2025-01-05 10:00:00'::TIMESTAMP,
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-07 10:00:00'::TIMESTAMP,
            '2025-01-08 10:00:00'::TIMESTAMP,
            '2025-01-09 10:00:00'::TIMESTAMP,
            '2025-01-10 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=DAILY;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 5.4: Verify MONTHLY+BYMONTHDAY correctness
-- BYMONTHDAY=1,15,31: Jan 1, Jan 15, Jan 31, Feb 1, Feb 15 (Feb has no 31st, skipped)
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Correctness Verification',
    'MONTHLY BYMONTHDAY=1,15,31 produces correct dates',
    assert_occurrences_equal(
        'MONTHLY BYMONTHDAY correctness',
        ARRAY[
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-15 00:00:00'::TIMESTAMP,
            '2025-01-31 00:00:00'::TIMESTAMP,
            '2025-02-01 00:00:00'::TIMESTAMP,
            '2025-02-15 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=1,15,31;COUNT=5', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

-- Test 5.5: Verify WEEKLY+multi-BYDAY correctness
-- 2025-01-01 is Wednesday; BYDAY=MO,WE,FR
-- Week 1: Wed Jan 1, Fri Jan 3
-- Week 2: Mon Jan 6, Wed Jan 8, Fri Jan 10
-- Week 3: Mon Jan 13, Wed Jan 15, Fri Jan 17
-- Week 4: Mon Jan 20
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Correctness Verification',
    'WEEKLY BYDAY=MO,WE,FR produces correct dates',
    assert_occurrences_equal(
        'WEEKLY multi-BYDAY correctness',
        ARRAY[
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-03 00:00:00'::TIMESTAMP,
            '2025-01-06 00:00:00'::TIMESTAMP,
            '2025-01-08 00:00:00'::TIMESTAMP,
            '2025-01-10 00:00:00'::TIMESTAMP,
            '2025-01-13 00:00:00'::TIMESTAMP,
            '2025-01-15 00:00:00'::TIMESTAMP,
            '2025-01-17 00:00:00'::TIMESTAMP,
            '2025-01-20 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=9', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

-- Test 5.6: Verify YEARLY+BYMONTH correctness
-- YEARLY;BYMONTH=1,6,12 starting 2025-01-01
-- Year 1: Jan 1, Jun 1, Dec 1
-- Year 2: Jan 1, Jun 1, Dec 1
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Correctness Verification',
    'YEARLY BYMONTH=1,6,12 produces correct dates',
    assert_occurrences_equal(
        'YEARLY BYMONTH correctness',
        ARRAY[
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-06-01 00:00:00'::TIMESTAMP,
            '2025-12-01 00:00:00'::TIMESTAMP,
            '2026-01-01 00:00:00'::TIMESTAMP,
            '2026-06-01 00:00:00'::TIMESTAMP,
            '2026-12-01 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=YEARLY;BYMONTH=1,6,12;COUNT=6', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

------------------------------------------------------------------------------------------------------
-- Issue 2: UNTIL before dtstart early exit optimization
------------------------------------------------------------------------------------------------------

-- Test 6.1: UNTIL before dtstart returns empty result set (TIMESTAMP API, DAILY)
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'UNTIL Early Exit',
    'DAILY UNTIL before dtstart returns empty',
    assert_occurrences_equal(
        'DAILY UNTIL < dtstart',
        ARRAY[]::TIMESTAMP[],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=DAILY;UNTIL=20240101T000000Z', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

-- Test 6.2: UNTIL before dtstart returns empty (WEEKLY)
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'UNTIL Early Exit',
    'WEEKLY UNTIL before dtstart returns empty',
    assert_occurrences_equal(
        'WEEKLY UNTIL < dtstart',
        ARRAY[]::TIMESTAMP[],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=WEEKLY;UNTIL=20240601T000000Z', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

-- Test 6.3: UNTIL before dtstart returns empty (MONTHLY)
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'UNTIL Early Exit',
    'MONTHLY UNTIL before dtstart returns empty',
    assert_occurrences_equal(
        'MONTHLY UNTIL < dtstart',
        ARRAY[]::TIMESTAMP[],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=MONTHLY;UNTIL=20240601T000000Z', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

-- Test 6.4: UNTIL before dtstart returns empty (YEARLY)
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'UNTIL Early Exit',
    'YEARLY UNTIL before dtstart returns empty',
    assert_occurrences_equal(
        'YEARLY UNTIL < dtstart',
        ARRAY[]::TIMESTAMP[],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=YEARLY;UNTIL=20200101T000000Z', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

-- Test 6.5: UNTIL before dtstart returns empty (TIMESTAMPTZ API)
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'UNTIL Early Exit',
    'TIMESTAMPTZ DAILY UNTIL before dtstart returns empty',
    assert_equals(
        'TZ DAILY UNTIL < dtstart',
        '0',
        (SELECT COUNT(*)::TEXT
         FROM rrule."all"('FREQ=DAILY;UNTIL=20240101T000000Z', '2025-01-01 00:00:00-05'::TIMESTAMPTZ, 'America/New_York'))
    )
);

-- Test 6.6: UNTIL equal to dtstart returns the dtstart occurrence (boundary check)
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'UNTIL Early Exit',
    'UNTIL equal to dtstart returns dtstart',
    assert_occurrences_equal(
        'UNTIL = dtstart',
        ARRAY['2025-01-01 00:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=DAILY;UNTIL=20250101T000000Z', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

------------------------------------------------------------------------------------------------------
-- Issue 9: Stale current in outer loop UNTIL exit (sparse rules)
------------------------------------------------------------------------------------------------------

-- Test 7.1: MONTHLY BYMONTHDAY=31 with UNTIL in a short-month period
-- Months without day 31: Feb, Apr, Jun, Sep, Nov
-- With UNTIL=2025-04-30, only Jan 31 and Mar 31 should appear
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Stale Current Fix',
    'MONTHLY BYMONTHDAY=31 UNTIL in short month',
    assert_occurrences_equal(
        'BYMONTHDAY=31 UNTIL=Apr30',
        ARRAY[
            '2025-01-31 00:00:00'::TIMESTAMP,
            '2025-03-31 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=31;UNTIL=20250430T000000Z', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

-- Test 7.2: MONTHLY BYMONTHDAY=31 INTERVAL=2 with UNTIL (tests INTERVAL > 1)
-- Starting Jan 2025, every 2 months on day 31: Jan 31, Mar 31, May 31, Jul 31
-- UNTIL=2025-06-30 means only Jan 31, Mar 31, May 31
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Stale Current Fix',
    'MONTHLY BYMONTHDAY=31 INTERVAL=2 UNTIL',
    assert_occurrences_equal(
        'BYMONTHDAY=31 INTERVAL=2 UNTIL=Jun30',
        ARRAY[
            '2025-01-31 00:00:00'::TIMESTAMP,
            '2025-03-31 00:00:00'::TIMESTAMP,
            '2025-05-31 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=31;INTERVAL=2;UNTIL=20250630T000000Z', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

-- Test 7.3: YEARLY BYDAY=MO with UNTIL - sparse yearly rule
-- First Monday of each year. 2025: Jan 6, 2026: Jan 5
-- UNTIL=2025-12-31 means only 2025 occurrences
INSERT INTO optimization_test_results (test_category, test_name, status)
VALUES (
    'Stale Current Fix',
    'YEARLY BYDAY with UNTIL exits correctly',
    assert_occurrences_equal(
        'YEARLY BYDAY UNTIL',
        ARRAY[
            '2025-01-06 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=YEARLY;BYDAY=MO;BYSETPOS=1;BYMONTH=1;UNTIL=20251231T235959Z', '2025-01-01'::TIMESTAMP) AS occurrence)
    )
);

------------------------------------------------------------------------------------------------------
-- Print Test Results
------------------------------------------------------------------------------------------------------
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
FROM optimization_test_results
ORDER BY test_category, test_name;

-- Check if all tests passed
DO $$
DECLARE
    failed_count INT;
    total_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM optimization_test_results
    WHERE status NOT LIKE 'PASS%';

    SELECT COUNT(*) INTO total_count
    FROM optimization_test_results;

    RAISE NOTICE '';
    RAISE NOTICE '===================================================================';
    IF failed_count = 0 THEN
        RAISE NOTICE 'Performance Optimization Tests: % / % PASSED', total_count, total_count;
        RAISE NOTICE '===================================================================';
    ELSE
        RAISE NOTICE 'Performance Optimization Tests: % / % FAILED', failed_count, total_count;
        RAISE NOTICE '===================================================================';
        RAISE EXCEPTION 'Performance optimization tests failed';
    END IF;
END $$;

ROLLBACK;
