/**
 * DoS Protection Tests for _advance_monthly() SKIP Branches
 *
 * Tests the critical DoS protection branches that terminate
 * SKIP loops when period limits are reached:
 * - Lines 1502-1503: omit_count >= p_period_limit (SKIP=OMIT)
 * - Lines 1524-1526: period_count >= p_period_limit (SKIP=FORWARD)
 *
 * Also tests early termination via maxdate and UNTIL:
 * - Lines 1493-1494: maxdate check in OMIT
 * - Lines 1497-1498: UNTIL check in OMIT
 * - Lines 1512-1514: UNTIL check in FORWARD
 * - Lines 1517-1519: maxdate check in FORWARD
 *
 * These branches prevent infinite loops when processing rules with
 * impossible or rarely-occurring dates (e.g., 31st of month in Feb).
 *
 * Usage:
 *   psql -d your_database -f tests/security/test_dos_protection_monthly.sql
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
\echo 'DoS PROTECTION TESTS FOR _advance_monthly() SKIP BRANCHES'
\echo '====================================================================='

--------------------------------------------------------------------------------
-- SECTION 1: SKIP=OMIT PERIOD LIMIT TERMINATION (Lines 1502-1503)
--------------------------------------------------------------------------------
\echo ''
\echo '--- SECTION 1: SKIP=OMIT period limit termination ---'

-- Test 1.1: 31st of month with SKIP=OMIT
-- Months without 31 days (Feb, Apr, Jun, Sep, Nov) are skipped
-- COUNT=12 returns 12 valid results from months that have 31 days
SELECT assert_equals('dos-omit-monthly-31st', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=OMIT;COUNT=12',
        '2020-01-31 10:00:00'::TIMESTAMP)));

-- Test 1.2: Verify completion with larger COUNT - limited by 10-year window
-- 10 years * ~7 months with 31 days/year = ~70 results
SELECT assert_true('dos-omit-monthly-terminates',
    (SELECT COUNT(*) BETWEEN 50 AND 100
     FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=OMIT;COUNT=100',
        '2020-01-31 10:00:00'::TIMESTAMP)));

--------------------------------------------------------------------------------
-- SECTION 2: SKIP=FORWARD PERIOD LIMIT (Lines 1524-1526)
--------------------------------------------------------------------------------
\echo ''
\echo '--- SECTION 2: SKIP=FORWARD period limit ---'

-- Test 2.1: 31st with SKIP=FORWARD produces forwarded dates
SELECT assert_equals('dos-forward-monthly-31st', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=12',
        '2020-01-31 10:00:00'::TIMESTAMP)));

-- Test 2.2: Verify FORWARD dates are 1st of next month for short months
-- Feb 31 -> Mar 1
SELECT assert_true('dos-forward-monthly-correct',
    (SELECT r::DATE = '2020-03-01'::DATE
     FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=2',
        '2020-01-31 10:00:00'::TIMESTAMP) r
     ORDER BY r OFFSET 1 LIMIT 1));

--------------------------------------------------------------------------------
-- SECTION 3: DIRECT _advance_monthly() FUNCTION TESTS
--------------------------------------------------------------------------------
\echo ''
\echo '--- SECTION 3: Direct _advance_monthly() function tests ---'

-- Test 3.1: Force OMIT limit with controlled small period_limit
-- Use day 32 which NEVER exists in any month - forces continuous OMITs
DO $$
DECLARE
    result rrule._skip_result;
    current_base TIMESTAMPTZ := '2020-02-29 10:00:00'::TIMESTAMPTZ;
    basedate TIMESTAMPTZ := '2020-01-31 10:00:00'::TIMESTAMPTZ;
    iterations INT := 0;
    max_iterations INT := 25;
    small_limit INT := 10;
BEGIN
    result.omit_count := 0;
    result.period_count := 0;
    result.done := FALSE;

    -- Advance with day 32, which NEVER exists in any month
    WHILE NOT result.done AND iterations < max_iterations LOOP
        result := rrule._advance_monthly(
            current_base,
            basedate,
            32,                  -- dtstart_day = 32 (NEVER exists)
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
        RAISE NOTICE 'PASS [dos-monthly-direct-omit-limit]: OMIT limit triggered at omit_count=%', result.omit_count;
    ELSIF iterations >= max_iterations THEN
        RAISE EXCEPTION 'FAIL [dos-monthly-direct-omit-limit]: Did not terminate within % iterations', max_iterations;
    ELSE
        RAISE EXCEPTION 'FAIL [dos-monthly-direct-omit-limit]: Terminated for wrong reason. done=%, omit_count=%, period_count=%',
            result.done, result.omit_count, result.period_count;
    END IF;
END $$;

-- Test 3.2: Force FORWARD limit with controlled small period_limit
-- Use day 32 which NEVER exists - forces continuous FORWARDs
DO $$
DECLARE
    result rrule._skip_result;
    current_base TIMESTAMPTZ := '2020-02-29 10:00:00'::TIMESTAMPTZ;
    basedate TIMESTAMPTZ := '2020-01-31 10:00:00'::TIMESTAMPTZ;
    iterations INT := 0;
    max_iterations INT := 25;
    small_limit INT := 10;
    forward_count INT := 0;
BEGIN
    result.omit_count := 0;
    result.period_count := 0;
    result.done := FALSE;

    WHILE NOT result.done AND iterations < max_iterations LOOP
        result := rrule._advance_monthly(
            current_base,
            basedate,
            32,                  -- dtstart_day = 32 (NEVER exists)
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
        RAISE NOTICE 'PASS [dos-monthly-direct-forward-limit]: FORWARD limit triggered at period_count=%, forward emissions=%',
            result.period_count, forward_count;
    ELSIF iterations >= max_iterations THEN
        RAISE EXCEPTION 'FAIL [dos-monthly-direct-forward-limit]: Did not terminate within % iterations', max_iterations;
    ELSE
        RAISE EXCEPTION 'FAIL [dos-monthly-direct-forward-limit]: Terminated for wrong reason. done=%, period_count=%',
            result.done, result.period_count;
    END IF;
END $$;

-- Test 3.3: OMIT terminates via maxdate (lines 1493-1494)
-- Use day 32 so we keep OMITing until maxdate is exceeded
DO $$
DECLARE
    result rrule._skip_result;
    current_base TIMESTAMPTZ := '2020-02-29 10:00:00'::TIMESTAMPTZ;
    basedate TIMESTAMPTZ := '2020-01-31 10:00:00'::TIMESTAMPTZ;
    iterations INT := 0;
BEGIN
    result.omit_count := 0;
    result.period_count := 0;
    result.done := FALSE;

    WHILE NOT result.done AND iterations < 10 LOOP
        result := rrule._advance_monthly(
            current_base,
            basedate,
            32,                  -- day 32 NEVER exists
            1,
            'OMIT',
            NULL,                -- no UNTIL
            '2020-04-01'::TIMESTAMPTZ,  -- maxdate only 2 months away
            100,                 -- high period_limit (won't be hit)
            result.omit_count,
            result.period_count
        );
        current_base := result.current_base;
        iterations := iterations + 1;
    END LOOP;

    IF result.done AND result.omit_count < 100 THEN
        RAISE NOTICE 'PASS [dos-monthly-omit-maxdate]: Terminated via maxdate at omit_count=%', result.omit_count;
    ELSE
        RAISE EXCEPTION 'FAIL [dos-monthly-omit-maxdate]: Expected maxdate termination, got omit_count=%', result.omit_count;
    END IF;
END $$;

-- Test 3.4: OMIT terminates via UNTIL (lines 1497-1498)
-- Use day 32 so we keep OMITing until UNTIL is exceeded
DO $$
DECLARE
    result rrule._skip_result;
    current_base TIMESTAMPTZ := '2020-02-29 10:00:00'::TIMESTAMPTZ;
    basedate TIMESTAMPTZ := '2020-01-31 10:00:00'::TIMESTAMPTZ;
    iterations INT := 0;
BEGIN
    result.omit_count := 0;
    result.period_count := 0;
    result.done := FALSE;

    WHILE NOT result.done AND iterations < 10 LOOP
        result := rrule._advance_monthly(
            current_base,
            basedate,
            32,                  -- day 32 NEVER exists
            1,
            'OMIT',
            '2020-04-01'::TIMESTAMPTZ,  -- UNTIL only 2 months away
            '2100-01-01'::TIMESTAMPTZ,  -- far maxdate
            100,                 -- high period_limit (won't be hit)
            result.omit_count,
            result.period_count
        );
        current_base := result.current_base;
        iterations := iterations + 1;
    END LOOP;

    IF result.done AND result.omit_count < 100 THEN
        RAISE NOTICE 'PASS [dos-monthly-omit-until]: Terminated via UNTIL at omit_count=%', result.omit_count;
    ELSE
        RAISE EXCEPTION 'FAIL [dos-monthly-omit-until]: Expected UNTIL termination, got omit_count=%', result.omit_count;
    END IF;
END $$;

-- Test 3.5: FORWARD terminates via UNTIL (lines 1512-1514)
-- Day 32 -> forward to 1st of next month (Mar 1), but UNTIL is before that
DO $$
DECLARE
    result rrule._skip_result;
BEGIN
    result := rrule._advance_monthly(
        '2020-02-29 10:00:00'::TIMESTAMPTZ,
        '2020-01-31 10:00:00'::TIMESTAMPTZ,
        32,                  -- day 32 -> forward to Mar 1
        1,
        'FORWARD',
        '2020-02-29 10:00:00'::TIMESTAMPTZ,  -- UNTIL before Mar 1
        '2100-01-01'::TIMESTAMPTZ,
        100, 0, 0
    );

    IF result.done AND result.forward_ts IS NULL THEN
        RAISE NOTICE 'PASS [dos-monthly-forward-until]: FORWARD terminated via UNTIL, forward_ts cleared';
    ELSE
        RAISE EXCEPTION 'FAIL [dos-monthly-forward-until]: Expected UNTIL termination with NULL forward_ts, got done=%, forward_ts=%',
            result.done, result.forward_ts;
    END IF;
END $$;

-- Test 3.6: FORWARD terminates via maxdate (lines 1517-1519)
-- Day 32 -> forward to 1st of next month (Mar 1), but maxdate is before that
DO $$
DECLARE
    result rrule._skip_result;
BEGIN
    result := rrule._advance_monthly(
        '2020-02-29 10:00:00'::TIMESTAMPTZ,
        '2020-01-31 10:00:00'::TIMESTAMPTZ,
        32,                  -- day 32 -> forward to Mar 1
        1,
        'FORWARD',
        NULL,                -- no UNTIL
        '2020-02-29 10:00:00'::TIMESTAMPTZ,  -- maxdate before Mar 1
        100, 0, 0
    );

    IF result.done AND result.forward_ts IS NULL THEN
        RAISE NOTICE 'PASS [dos-monthly-forward-maxdate]: FORWARD terminated via maxdate, forward_ts cleared';
    ELSE
        RAISE EXCEPTION 'FAIL [dos-monthly-forward-maxdate]: Expected maxdate termination with NULL forward_ts, got done=%, forward_ts=%',
            result.done, result.forward_ts;
    END IF;
END $$;

-- Test 3.7: Verify omit_count increments correctly
-- Use day 32 which never exists, so OMIT is triggered
DO $$
DECLARE
    result rrule._skip_result;
BEGIN
    result.omit_count := 5;
    result.period_count := 0;
    result.done := FALSE;

    result := rrule._advance_monthly(
        '2020-02-29 10:00:00'::TIMESTAMPTZ,
        '2020-01-31 10:00:00'::TIMESTAMPTZ,
        32, 1, 'OMIT', NULL,
        '2100-01-01'::TIMESTAMPTZ,
        100,
        result.omit_count,
        result.period_count
    );

    IF result.omit_count = 6 THEN
        RAISE NOTICE 'PASS [dos-monthly-omit-increment]: omit_count incremented from 5 to %', result.omit_count;
    ELSE
        RAISE EXCEPTION 'FAIL [dos-monthly-omit-increment]: Expected omit_count=6, got %', result.omit_count;
    END IF;
END $$;

-- Test 3.8: Verify period_count increments correctly
-- Use day 32 which never exists, so FORWARD is triggered
DO $$
DECLARE
    result rrule._skip_result;
BEGIN
    result.omit_count := 0;
    result.period_count := 7;
    result.done := FALSE;

    result := rrule._advance_monthly(
        '2020-02-29 10:00:00'::TIMESTAMPTZ,
        '2020-01-31 10:00:00'::TIMESTAMPTZ,
        32, 1, 'FORWARD', NULL,
        '2100-01-01'::TIMESTAMPTZ,
        100,
        result.omit_count,
        result.period_count
    );

    IF result.period_count = 8 THEN
        RAISE NOTICE 'PASS [dos-monthly-forward-increment]: period_count incremented from 7 to %', result.period_count;
    ELSE
        RAISE EXCEPTION 'FAIL [dos-monthly-forward-increment]: Expected period_count=8, got %', result.period_count;
    END IF;
END $$;

--------------------------------------------------------------------------------
-- SECTION 4: REGRESSION - NORMAL MONTHLY SKIP BEHAVIOR
--------------------------------------------------------------------------------
\echo ''
\echo '--- SECTION 4: Regression - normal SKIP still works ---'

-- Test 4.1: SKIP=OMIT with achievable date
SELECT assert_equals('regression-monthly-omit', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=15;SKIP=OMIT;COUNT=5',
        '2020-01-15 10:00:00'::TIMESTAMP)));

-- Test 4.2: SKIP=FORWARD with achievable date
SELECT assert_equals('regression-monthly-forward', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=15;SKIP=FORWARD;COUNT=5',
        '2020-01-15 10:00:00'::TIMESTAMP)));

-- Test 4.3: SKIP=BACKWARD with achievable date
SELECT assert_equals('regression-monthly-backward', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=15;SKIP=BACKWARD;COUNT=5',
        '2020-01-15 10:00:00'::TIMESTAMP)));

-- Test 4.4: Normal MONTHLY without SKIP
SELECT assert_equals('regression-monthly-normal', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;COUNT=12',
        '2020-06-15 10:00:00'::TIMESTAMP)));

\echo ''
\echo '====================================================================='
\echo 'DoS PROTECTION TESTS FOR _advance_monthly() COMPLETE'
\echo '====================================================================='

ROLLBACK;
