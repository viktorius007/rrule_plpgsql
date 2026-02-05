/**
 * DoS Protection Tests for _advance_yearly() SKIP Branches
 *
 * Tests the two critical DoS protection branches that terminate
 * SKIP loops when period limits are reached:
 * - Line 1598-1600: omit_count >= p_period_limit (SKIP=OMIT)
 * - Line 1620-1623: period_count >= p_period_limit (SKIP=FORWARD)
 *
 * These branches prevent infinite loops when processing rules with
 * impossible or rarely-occurring dates (e.g., Feb 30 never exists).
 *
 * Why these tests matter:
 * - A bug in these branches could cause production database hangs
 * - Normal tests don't trigger these branches because:
 *   1. COUNT terminates first (most tests use small COUNT values)
 *   2. 10-year window limits YEARLY rules to ~10 iterations
 *   3. Period limit uses 10x multiplier (COUNT=5 gives limit=50)
 *
 * Strategy:
 * - Use impossible dates (Feb 30) that can NEVER exist
 * - Direct function testing with controlled small period_limit
 * - Verify termination happens due to DoS protection, not other conditions
 *
 * Usage:
 *   psql -d your_database -f tests/security/test_dos_protection_yearly.sql
 */

\set ON_ERROR_STOP on
\set ECHO all

SET timezone = 'UTC';

\if :{?rrule_install}
\i :rrule_install
\else
DROP SCHEMA IF EXISTS rrule CASCADE;
CREATE SCHEMA IF NOT EXISTS rrule;
\i src/rrule.sql
\endif

SET search_path = public;

BEGIN;

\i tests/helpers.sql

\echo ''
\echo '====================================================================='
\echo 'DoS PROTECTION TESTS FOR _advance_yearly() SKIP BRANCHES'
\echo '====================================================================='

--------------------------------------------------------------------------------
-- SECTION 1: SKIP=OMIT PERIOD LIMIT TERMINATION (Lines 1598-1600)
--------------------------------------------------------------------------------
\echo ''
\echo '--- SECTION 1: SKIP=OMIT period limit termination ---'

-- Test 1.1: Feb 30 NEVER exists - forces OMIT every year until limit hit
-- With COUNT=5 and period_limit=50 (10x), this should:
-- - Try Feb 30 for up to 50 years (all OMIT)
-- - Terminate via omit_count >= period_limit
-- - Return empty array (no valid dates found)
SELECT assert_equals('dos-omit-impossible-date', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;SKIP=OMIT;COUNT=5',
        '2020-02-15 10:00:00'::TIMESTAMP)));

-- Test 1.2: Verify completion within reasonable time (DoS protection works)
-- This would hang without the limit. Higher COUNT = higher period_limit.
SELECT assert_equals('dos-omit-terminates-large-count', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;SKIP=OMIT;COUNT=100',
        '2020-02-15 10:00:00'::TIMESTAMP)));

-- Test 1.3: Feb 31 also never exists
SELECT assert_equals('dos-omit-feb31', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=31;SKIP=OMIT;COUNT=10',
        '2020-02-15 10:00:00'::TIMESTAMP)));

-- Test 1.4: April 31 never exists (April has 30 days)
SELECT assert_equals('dos-omit-apr31', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=4;BYMONTHDAY=31;SKIP=OMIT;COUNT=10',
        '2020-04-15 10:00:00'::TIMESTAMP)));

--------------------------------------------------------------------------------
-- SECTION 2: SKIP=FORWARD PERIOD LIMIT (Lines 1620-1623)
--------------------------------------------------------------------------------
\echo ''
\echo '--- SECTION 2: SKIP=FORWARD period limit ---'

-- Test 2.1: Feb 30 with SKIP=FORWARD -> always forwards to Mar 2
-- COUNT=5 should return 5 dates (all Mar 2 of successive years)
-- This tests the FORWARD path works correctly
SELECT assert_equals('dos-forward-impossible-date', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;SKIP=FORWARD;COUNT=5',
        '2020-02-15 10:00:00'::TIMESTAMP)));

-- Test 2.2: Verify FORWARD dates are correct (FORWARD goes to 1st of next month)
-- Per implementation: SKIP=FORWARD emits 1st of next month
SELECT assert_true('dos-forward-correct-date',
    (SELECT MIN(r)::DATE = '2020-03-01'::DATE
     FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;SKIP=FORWARD;COUNT=1',
        '2020-02-15 10:00:00'::TIMESTAMP) r));

-- Test 2.3: April 31 with FORWARD -> May 1 (1st of next month)
SELECT assert_true('dos-forward-apr31',
    (SELECT MIN(r)::DATE = '2020-05-01'::DATE
     FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=4;BYMONTHDAY=31;SKIP=FORWARD;COUNT=1',
        '2020-04-15 10:00:00'::TIMESTAMP) r));

-- Test 2.4: Feb 31 with FORWARD -> Mar 1 (1st of next month)
SELECT assert_true('dos-forward-feb31',
    (SELECT MIN(r)::DATE = '2020-03-01'::DATE
     FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=31;SKIP=FORWARD;COUNT=1',
        '2020-02-15 10:00:00'::TIMESTAMP) r));

--------------------------------------------------------------------------------
-- SECTION 3: DIRECT _advance_yearly() FUNCTION TESTS
--------------------------------------------------------------------------------
\echo ''
\echo '--- SECTION 3: Direct _advance_yearly() function tests ---'

-- Test 3.1: Force OMIT limit with controlled small period_limit
-- This directly tests the DoS protection branch at lines 1598-1600
DO $$
DECLARE
    result rrule._skip_result;
    current_base TIMESTAMPTZ := '2021-02-28 10:00:00'::TIMESTAMPTZ;
    basedate TIMESTAMPTZ := '2020-02-28 10:00:00'::TIMESTAMPTZ;
    iterations INT := 0;
    max_iterations INT := 25;
    small_limit INT := 10;
BEGIN
    result.omit_count := 0;
    result.period_count := 0;
    result.done := FALSE;

    -- Advance with impossible date (day 30 in Feb) forcing OMITs
    -- Each call will OMIT because Feb 30 never exists
    WHILE NOT result.done AND iterations < max_iterations LOOP
        result := rrule._advance_yearly(
            current_base,
            basedate,
            30,                  -- dtstart_day = 30 (never exists in Feb)
            1,                   -- interval = 1
            'OMIT',              -- skip mode
            NULL,                -- no UNTIL
            '2100-01-01'::TIMESTAMPTZ,  -- far future maxdate
            small_limit,         -- small period_limit for testing
            result.omit_count,
            result.period_count
        );
        current_base := result.current_base;
        iterations := iterations + 1;
    END LOOP;

    -- Verify: terminated due to omit_count hitting limit
    IF result.done AND result.omit_count >= small_limit THEN
        RAISE NOTICE 'PASS [dos-direct-omit-limit]: OMIT limit triggered at omit_count=%', result.omit_count;
    ELSIF iterations >= max_iterations THEN
        RAISE EXCEPTION 'FAIL [dos-direct-omit-limit]: Did not terminate within % iterations', max_iterations;
    ELSE
        RAISE EXCEPTION 'FAIL [dos-direct-omit-limit]: Terminated for wrong reason. done=%, omit_count=%, period_count=%',
            result.done, result.omit_count, result.period_count;
    END IF;
END $$;

-- Test 3.2: Force FORWARD limit with controlled small period_limit
-- This directly tests the DoS protection branch at lines 1620-1623
DO $$
DECLARE
    result rrule._skip_result;
    current_base TIMESTAMPTZ := '2021-02-28 10:00:00'::TIMESTAMPTZ;
    basedate TIMESTAMPTZ := '2020-02-28 10:00:00'::TIMESTAMPTZ;
    iterations INT := 0;
    max_iterations INT := 25;
    small_limit INT := 10;
    forward_count INT := 0;
BEGIN
    result.omit_count := 0;
    result.period_count := 0;
    result.done := FALSE;

    -- Advance with impossible date (day 30 in Feb), SKIP=FORWARD
    -- Each call will FORWARD because Feb 30 never exists
    WHILE NOT result.done AND iterations < max_iterations LOOP
        result := rrule._advance_yearly(
            current_base,
            basedate,
            30,                  -- dtstart_day = 30 (never exists in Feb)
            1,                   -- interval = 1
            'FORWARD',           -- skip mode
            NULL,                -- no UNTIL
            '2100-01-01'::TIMESTAMPTZ,  -- far future maxdate
            small_limit,         -- small period_limit for testing
            result.omit_count,
            result.period_count
        );
        current_base := result.current_base;
        iterations := iterations + 1;

        IF result.forward_ts IS NOT NULL THEN
            forward_count := forward_count + 1;
        END IF;
    END LOOP;

    -- Verify: terminated due to period_count hitting limit
    IF result.done AND result.period_count >= small_limit THEN
        RAISE NOTICE 'PASS [dos-direct-forward-limit]: FORWARD limit triggered at period_count=%, forward emissions=%',
            result.period_count, forward_count;
    ELSIF iterations >= max_iterations THEN
        RAISE EXCEPTION 'FAIL [dos-direct-forward-limit]: Did not terminate within % iterations', max_iterations;
    ELSE
        RAISE EXCEPTION 'FAIL [dos-direct-forward-limit]: Terminated for wrong reason. done=%, period_count=%',
            result.done, result.period_count;
    END IF;
END $$;

-- Test 3.3: Verify OMIT increments omit_count correctly
DO $$
DECLARE
    result rrule._skip_result;
    current_base TIMESTAMPTZ := '2021-02-28 10:00:00'::TIMESTAMPTZ;
    basedate TIMESTAMPTZ := '2020-02-28 10:00:00'::TIMESTAMPTZ;
BEGIN
    result.omit_count := 5;  -- Start with existing count
    result.period_count := 0;
    result.done := FALSE;

    -- Single call should increment omit_count by 1
    result := rrule._advance_yearly(
        current_base,
        basedate,
        30,                  -- impossible day
        1,
        'OMIT',
        NULL,
        '2100-01-01'::TIMESTAMPTZ,
        100,                 -- high limit so we don't terminate
        result.omit_count,
        result.period_count
    );

    IF result.omit_count = 6 THEN
        RAISE NOTICE 'PASS [dos-omit-increment]: omit_count incremented from 5 to %', result.omit_count;
    ELSE
        RAISE EXCEPTION 'FAIL [dos-omit-increment]: Expected omit_count=6, got %', result.omit_count;
    END IF;
END $$;

-- Test 3.4: Verify FORWARD increments period_count correctly
DO $$
DECLARE
    result rrule._skip_result;
    current_base TIMESTAMPTZ := '2021-02-28 10:00:00'::TIMESTAMPTZ;
    basedate TIMESTAMPTZ := '2020-02-28 10:00:00'::TIMESTAMPTZ;
BEGIN
    result.omit_count := 0;
    result.period_count := 7;  -- Start with existing count
    result.done := FALSE;

    -- Single call should increment period_count by 1
    result := rrule._advance_yearly(
        current_base,
        basedate,
        30,                  -- impossible day
        1,
        'FORWARD',
        NULL,
        '2100-01-01'::TIMESTAMPTZ,
        100,                 -- high limit so we don't terminate
        result.omit_count,
        result.period_count
    );

    IF result.period_count = 8 THEN
        RAISE NOTICE 'PASS [dos-forward-increment]: period_count incremented from 7 to %', result.period_count;
    ELSE
        RAISE EXCEPTION 'FAIL [dos-forward-increment]: Expected period_count=8, got %', result.period_count;
    END IF;
END $$;

-- Test 3.5: OMIT terminates via maxdate (lines 1589-1590)
-- maxdate is close, will be exceeded before period_limit
DO $$
DECLARE
    result rrule._skip_result;
    current_base TIMESTAMPTZ := '2021-02-28 10:00:00'::TIMESTAMPTZ;
    basedate TIMESTAMPTZ := '2020-02-28 10:00:00'::TIMESTAMPTZ;
    iterations INT := 0;
BEGIN
    result.omit_count := 0;
    result.period_count := 0;
    result.done := FALSE;

    WHILE NOT result.done AND iterations < 10 LOOP
        result := rrule._advance_yearly(
            current_base,
            basedate,
            30,                  -- impossible day
            1,
            'OMIT',
            NULL,                -- no UNTIL
            '2023-01-01'::TIMESTAMPTZ,  -- maxdate only 2 years away
            100,                 -- high period_limit (won't be hit)
            result.omit_count,
            result.period_count
        );
        current_base := result.current_base;
        iterations := iterations + 1;
    END LOOP;

    -- Should terminate via maxdate check, not period_limit
    IF result.done AND result.omit_count < 100 THEN
        RAISE NOTICE 'PASS [dos-omit-maxdate]: Terminated via maxdate at omit_count=%', result.omit_count;
    ELSE
        RAISE EXCEPTION 'FAIL [dos-omit-maxdate]: Expected maxdate termination, got omit_count=%', result.omit_count;
    END IF;
END $$;

-- Test 3.6: OMIT terminates via UNTIL (lines 1593-1594)
-- UNTIL is close, will be exceeded before period_limit
DO $$
DECLARE
    result rrule._skip_result;
    current_base TIMESTAMPTZ := '2021-02-28 10:00:00'::TIMESTAMPTZ;
    basedate TIMESTAMPTZ := '2020-02-28 10:00:00'::TIMESTAMPTZ;
    iterations INT := 0;
BEGIN
    result.omit_count := 0;
    result.period_count := 0;
    result.done := FALSE;

    WHILE NOT result.done AND iterations < 10 LOOP
        result := rrule._advance_yearly(
            current_base,
            basedate,
            30,                  -- impossible day
            1,
            'OMIT',
            '2023-01-01'::TIMESTAMPTZ,  -- UNTIL only 2 years away
            '2100-01-01'::TIMESTAMPTZ,  -- far maxdate
            100,                 -- high period_limit (won't be hit)
            result.omit_count,
            result.period_count
        );
        current_base := result.current_base;
        iterations := iterations + 1;
    END LOOP;

    -- Should terminate via UNTIL check, not period_limit
    IF result.done AND result.omit_count < 100 THEN
        RAISE NOTICE 'PASS [dos-omit-until]: Terminated via UNTIL at omit_count=%', result.omit_count;
    ELSE
        RAISE EXCEPTION 'FAIL [dos-omit-until]: Expected UNTIL termination, got omit_count=%', result.omit_count;
    END IF;
END $$;

-- Test 3.7: FORWARD terminates via UNTIL (lines 1608-1610)
-- UNTIL before forward_ts (Mar 1), terminates immediately
DO $$
DECLARE
    result rrule._skip_result;
BEGIN
    result := rrule._advance_yearly(
        '2021-02-28 10:00:00'::TIMESTAMPTZ,
        '2020-02-28 10:00:00'::TIMESTAMPTZ,
        30,                  -- impossible day -> forward to Mar 1
        1,
        'FORWARD',
        '2021-02-28 10:00:00'::TIMESTAMPTZ,  -- UNTIL before Mar 1
        '2100-01-01'::TIMESTAMPTZ,
        100, 0, 0
    );

    -- forward_ts should be NULL (cleared) and done should be TRUE
    IF result.done AND result.forward_ts IS NULL THEN
        RAISE NOTICE 'PASS [dos-forward-until]: FORWARD terminated via UNTIL, forward_ts cleared';
    ELSE
        RAISE EXCEPTION 'FAIL [dos-forward-until]: Expected UNTIL termination with NULL forward_ts, got done=%, forward_ts=%',
            result.done, result.forward_ts;
    END IF;
END $$;

-- Test 3.8: FORWARD terminates via maxdate (lines 1613-1615)
-- maxdate before forward_ts (Mar 1), terminates immediately
DO $$
DECLARE
    result rrule._skip_result;
BEGIN
    result := rrule._advance_yearly(
        '2021-02-28 10:00:00'::TIMESTAMPTZ,
        '2020-02-28 10:00:00'::TIMESTAMPTZ,
        30,                  -- impossible day -> forward to Mar 1
        1,
        'FORWARD',
        NULL,                -- no UNTIL
        '2021-02-28 10:00:00'::TIMESTAMPTZ,  -- maxdate before Mar 1
        100, 0, 0
    );

    -- forward_ts should be NULL (cleared) and done should be TRUE
    IF result.done AND result.forward_ts IS NULL THEN
        RAISE NOTICE 'PASS [dos-forward-maxdate]: FORWARD terminated via maxdate, forward_ts cleared';
    ELSE
        RAISE EXCEPTION 'FAIL [dos-forward-maxdate]: Expected maxdate termination with NULL forward_ts, got done=%, forward_ts=%',
            result.done, result.forward_ts;
    END IF;
END $$;

--------------------------------------------------------------------------------
-- SECTION 4: REGRESSION - NORMAL SKIP BEHAVIOR STILL WORKS
--------------------------------------------------------------------------------
\echo ''
\echo '--- SECTION 4: Regression - normal SKIP still works ---'

-- Test 4.1: SKIP=OMIT with achievable date completes normally
-- Feb 29 exists in leap years (2020, 2024, 2028), so this should work
SELECT assert_equals('regression-omit-works', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=OMIT;COUNT=3',
        '2020-02-29 10:00:00'::TIMESTAMP)));

-- Test 4.2: Verify SKIP=OMIT returns correct leap year dates
SELECT assert_occurrences_equal('regression-omit-correct-dates',
    ARRAY[
        '2020-02-29 10:00:00'::TIMESTAMP,
        '2024-02-29 10:00:00'::TIMESTAMP,
        '2028-02-29 10:00:00'::TIMESTAMP
    ],
    (SELECT array_agg(r ORDER BY r) FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=OMIT;COUNT=3',
        '2020-02-29 10:00:00'::TIMESTAMP) r));

-- Test 4.3: SKIP=FORWARD with achievable date completes normally
SELECT assert_equals('regression-forward-works', '10',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=FORWARD;COUNT=10',
        '2020-02-29 10:00:00'::TIMESTAMP)));

-- Test 4.4: SKIP=BACKWARD with achievable date completes normally
SELECT assert_equals('regression-backward-works', '10',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=BACKWARD;COUNT=10',
        '2020-02-29 10:00:00'::TIMESTAMP)));

-- Test 4.5: Normal YEARLY without SKIP still works
SELECT assert_equals('regression-yearly-normal', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;COUNT=5',
        '2020-06-15 10:00:00'::TIMESTAMP)));

--------------------------------------------------------------------------------
-- SECTION 5: EDGE CASES AND BOUNDARY CONDITIONS
--------------------------------------------------------------------------------
\echo ''
\echo '--- SECTION 5: Edge cases and boundary conditions ---'

-- Test 5.1: INTERVAL > 1 with impossible date (OMIT)
-- Every 2 years, Feb 30 still never exists
SELECT assert_equals('edge-interval2-omit', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;INTERVAL=2;BYMONTH=2;BYMONTHDAY=30;SKIP=OMIT;COUNT=5',
        '2020-02-15 10:00:00'::TIMESTAMP)));

-- Test 5.2: INTERVAL > 1 with impossible date (FORWARD)
-- Should still produce forwarded dates every 2 years
SELECT assert_equals('edge-interval2-forward', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;INTERVAL=2;BYMONTH=2;BYMONTHDAY=30;SKIP=FORWARD;COUNT=5',
        '2020-02-15 10:00:00'::TIMESTAMP)));

-- Test 5.3: UNTIL that would be exceeded before period_limit
-- UNTIL in 2022 should terminate before DoS limit
SELECT assert_equals('edge-until-terminates-first', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;SKIP=OMIT;UNTIL=20220101T000000Z',
        '2020-02-15 10:00:00'::TIMESTAMP)));

-- Test 5.4: Feb 30 with SKIP=BACKWARD should return Feb 28/29
-- Unlike OMIT/FORWARD, BACKWARD should produce valid dates
SELECT assert_equals('edge-backward-impossible', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;SKIP=BACKWARD;COUNT=5',
        '2020-02-15 10:00:00'::TIMESTAMP)));

-- Test 5.5: Verify BACKWARD produces end-of-Feb dates
SELECT assert_true('edge-backward-correct-dates',
    (SELECT MIN(r)::DATE IN ('2020-02-29'::DATE)  -- leap year = Feb 29
     FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;SKIP=BACKWARD;COUNT=1',
        '2020-02-15 10:00:00'::TIMESTAMP) r));

\echo ''
\echo '====================================================================='
\echo 'DoS PROTECTION TESTS FOR _advance_yearly() COMPLETE'
\echo '====================================================================='

ROLLBACK;
