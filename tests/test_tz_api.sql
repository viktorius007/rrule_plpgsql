-- ================================================================================================================
-- TIMEZONE-AWARE API TEST SUITE
-- ================================================================================================================
--
-- This test suite verifies that the timezone-aware API properly preserves wall-clock times across
-- Daylight Saving Time (DST) transitions.
--
-- KEY TEST SCENARIOS:
-- 1. DST Spring Forward (March 2025) - Wall-clock times should stay constant despite gaining an hour
-- 2. DST Fall Back (November 2025) - Wall-clock times should stay constant despite repeating an hour
-- 3. Multiple timezone support
-- 4. TZID parameter in RRULE string
-- 5. Explicit timezone parameter override
-- 6. UTC timezone (no DST)
-- 7. Range queries across DST boundaries
--
-- ================================================================================================================

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


-- Test results table
CREATE TEMPORARY TABLE tz_api_test_results (
    test_suite VARCHAR,
    test_name VARCHAR,
    passed BOOLEAN,
    actual TEXT,
    expected TEXT
);

-- Helper function for simple assert tests (used by count/next/most_recent/overlaps tests)
-- This file uses its own assert_equal helper instead of helpers.sql because the TIMESTAMPTZ API
-- test pattern uses a 4-param signature (test_suite, test_name, actual, expected) and inserts
-- results into the tz_api_test_results table for per-suite tracking.
--
-- ASSERTION PATTERN: This file uses a soft-fail assertion pattern (RAISE WARNING + insert passed=false)
-- instead of the hard-fail pattern (RAISE EXCEPTION) used in other test files. This allows all tests
-- within a suite to execute even if earlier tests fail, collecting all failures for the end-of-file
-- summary. The final DO block raises EXCEPTION if any failures occurred, ensuring CI still catches them.
CREATE OR REPLACE FUNCTION assert_equal_soft(test_suite TEXT, test_name TEXT, actual TEXT, expected TEXT)
RETURNS TEXT AS $$
BEGIN
    INSERT INTO tz_api_test_results VALUES (test_suite, test_name, actual IS NOT DISTINCT FROM expected, actual, expected);
    IF actual IS NOT DISTINCT FROM expected THEN
        RETURN '[PASS]';
    ELSE
        RAISE WARNING 'Test failed: %', test_name;
        RAISE WARNING 'Expected: %', expected;
        RAISE WARNING 'Actual:   %', actual;
        RETURN '[FAIL]';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Helper function to format TIMESTAMPTZ in a specific timezone with correct abbreviation
-- This is needed because to_char(ts, 'TZ') uses the session timezone, not the target timezone
CREATE OR REPLACE FUNCTION format_ts_in_tz(ts TIMESTAMPTZ, tz_name TEXT)
RETURNS TEXT AS $$
DECLARE
    local_ts TIMESTAMP;
    utc_offset_hours INTEGER;
    tz_abbrev TEXT;
BEGIN
    -- Convert to local time in target timezone
    local_ts := ts AT TIME ZONE tz_name;

    -- Calculate UTC offset for this timestamp in this timezone
    -- offset = (UTC epoch - local epoch) / 3600
    utc_offset_hours := EXTRACT(EPOCH FROM ts)::BIGINT / 3600 -
                        EXTRACT(EPOCH FROM local_ts)::BIGINT / 3600;

    -- Determine abbreviation based on timezone and offset
    tz_abbrev := CASE tz_name
        WHEN 'America/New_York' THEN
            CASE utc_offset_hours WHEN 5 THEN 'EST' ELSE 'EDT' END
        WHEN 'America/Los_Angeles' THEN
            CASE utc_offset_hours WHEN 8 THEN 'PST' ELSE 'PDT' END
        WHEN 'Europe/London' THEN
            CASE utc_offset_hours WHEN 0 THEN 'GMT' ELSE 'BST' END
        WHEN 'UTC' THEN 'UTC'
        ELSE tz_name
    END;

    RETURN to_char(local_ts, 'YYYY-MM-DD HH24:MI:SS') || ' ' || tz_abbrev;
END;
$$ LANGUAGE plpgsql;


-- ================================================================================================================
-- TEST SUITE 1: DST Spring Forward (March 9, 2025 - America/New_York)
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 1: DST Spring Forward'
\echo '=================================================='
\echo 'Scenario: Daily meeting at 10:00 AM EST/EDT'
\echo 'Expected: Wall-clock time stays at 10:00 AM across DST boundary'
\echo 'Date: March 8-10, 2025 (DST spring forward on March 9 at 2 AM)'
\echo ''

-- Test 1.1: DAILY frequency across spring forward
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 EST',  -- Saturday, before DST
        '2025-03-09 10:00:00 EDT',  -- Sunday, after spring forward ← KEY TEST
        '2025-03-10 10:00:00 EDT'   -- Monday, after DST
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    -- Generate 3 daily occurrences starting March 8, 2025 at 10 AM EST
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,  -- 10 AM EST
        'America/New_York'
    ) ts;

    -- Format for comparison (using helper to get correct timezone abbreviation)
    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'DST Spring Forward',
        'DAILY frequency preserves 10 AM across spring forward',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );

    IF NOT matches THEN
        RAISE WARNING 'Test failed! Expected wall-clock time to stay at 10:00 AM';
        RAISE WARNING 'Expected: %', array_to_string(expected, ', ');
        RAISE WARNING 'Actual:   %', array_to_string(actual, ', ');
    END IF;
END;
$$;

-- Test 1.2: WEEKLY frequency across spring forward
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 EST',  -- Saturday
        '2025-03-15 10:00:00 EDT',  -- Next Saturday (after DST)
        '2025-03-22 10:00:00 EDT'   -- Next Saturday
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=WEEKLY;COUNT=3',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'DST Spring Forward',
        'WEEKLY frequency preserves 10 AM across spring forward',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 1.3: TZID parameter in RRULE string (no explicit timezone)
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 EST',
        '2025-03-09 10:00:00 EDT',
        '2025-03-10 10:00:00 EDT'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    -- Use TZID in RRULE string instead of explicit parameter
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'TZID=America/New_York;FREQ=DAILY;COUNT=3',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        NULL  -- No explicit timezone, should use TZID from RRULE
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'DST Spring Forward',
        'TZID in RRULE string works correctly',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 2: DST Fall Back (November 2, 2025 - America/New_York)
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 2: DST Fall Back'
\echo '=================================================='
\echo 'Scenario: Daily meeting at 10:00 AM EDT/EST'
\echo 'Expected: Wall-clock time stays at 10:00 AM across DST boundary'
\echo 'Date: November 1-3, 2025 (DST fall back on November 2 at 2 AM)'
\echo ''

-- Test 2.1: DAILY frequency across fall back
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-11-01 10:00:00 EDT',  -- Saturday, before DST
        '2025-11-02 10:00:00 EST',  -- Sunday, after fall back ← KEY TEST
        '2025-11-03 10:00:00 EST'   -- Monday, after DST
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-11-01 10:00:00-04'::TIMESTAMPTZ,  -- 10 AM EDT
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'DST Fall Back',
        'DAILY frequency preserves 10 AM across fall back',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );

    IF NOT matches THEN
        RAISE WARNING 'Test failed! Expected wall-clock time to stay at 10:00 AM';
        RAISE WARNING 'Expected: %', array_to_string(expected, ', ');
        RAISE WARNING 'Actual:   %', array_to_string(actual, ', ');
    END IF;
END;
$$;


-- ================================================================================================================
-- TEST SUITE 3: UTC Timezone (No DST)
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 3: UTC Timezone'
\echo '=================================================='
\echo 'Scenario: UTC has no DST, should behave consistently'
\echo ''

-- Test 3.1: DAILY in UTC
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 UTC',
        '2025-03-09 10:00:00 UTC',
        '2025-03-10 10:00:00 UTC'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-03-08 10:00:00+00'::TIMESTAMPTZ,
        'UTC'
    ) ts;

    -- Convert to target timezone (UTC) before formatting
    SELECT array_agg(to_char(ts AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS') || ' UTC' ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'UTC Timezone',
        'UTC has no DST drift',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 4: Different Timezones
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 4: Multiple Timezones'
\echo '=================================================='
\echo 'Scenario: Test various timezones with different DST rules'
\echo ''

-- Test 4.1: Los Angeles (different DST dates than NY)
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 PST',
        '2025-03-09 10:00:00 PDT',  -- DST spring forward (same date as NY)
        '2025-03-10 10:00:00 PDT'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-03-08 10:00:00-08'::TIMESTAMPTZ,
        'America/Los_Angeles'
    ) ts;

    -- Convert to target timezone and detect DST abbreviation based on LA offset
    SELECT array_agg(
        to_char(ts AT TIME ZONE 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI:SS') || ' ' ||
        CASE
            -- Calculate LA offset: (epoch_utc - epoch_naive) / 3600
            WHEN (EXTRACT(epoch FROM ts)::bigint - EXTRACT(epoch FROM (ts AT TIME ZONE 'America/Los_Angeles'))::bigint) / 3600 = 8
            THEN 'PST'
            ELSE 'PDT'
        END
        ORDER BY ordinality
    ) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Multiple Timezones',
        'Los Angeles PST/PDT transition works correctly',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 4.2: Europe/London (different DST rules)
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-29 10:00:00 GMT',  -- Saturday before DST
        '2025-03-30 10:00:00 BST',  -- Sunday, spring forward to BST
        '2025-03-31 10:00:00 BST'   -- Monday
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-03-29 10:00:00+00'::TIMESTAMPTZ,
        'Europe/London'
    ) ts;

    -- Convert to target timezone and detect GMT/BST based on London offset
    SELECT array_agg(
        to_char(ts AT TIME ZONE 'Europe/London', 'YYYY-MM-DD HH24:MI:SS') || ' ' ||
        CASE
            -- Calculate London offset: (epoch_utc - epoch_naive) / 3600
            -- GMT = 0, BST = -1 (negative because London is ahead of UTC in summer)
            WHEN (EXTRACT(epoch FROM ts)::bigint - EXTRACT(epoch FROM (ts AT TIME ZONE 'Europe/London'))::bigint) / 3600 = 0
            THEN 'GMT'
            ELSE 'BST'
        END
        ORDER BY ordinality
    ) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Multiple Timezones',
        'London GMT/BST transition works correctly',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 5: Range Queries
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 5: Range Queries (between)'
\echo '=================================================='
\echo 'Scenario: Query occurrences within a date range spanning DST'
\echo ''

-- Test 5.1: between() across spring forward
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-09 10:00:00 EDT',  -- Only the middle occurrence
        '2025-03-10 10:00:00 EDT'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."between"(
        'FREQ=DAILY;COUNT=10',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-09 00:00:00-04'::TIMESTAMPTZ,  -- Range: March 9-10
        '2025-03-11 00:00:00-04'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Range Queries',
        'between() works across DST boundary',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 5.2: between() with inc=true includes boundary occurrences
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 EST',
        '2025-03-09 10:00:00 EDT'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."between"(
        'FREQ=DAILY;COUNT=3',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-09 10:00:00-04'::TIMESTAMPTZ,
        'America/New_York',
        TRUE
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Range Queries',
        'between() inc=true includes boundaries',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 6: Offset Queries
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 6: Offset Queries (after/before)'
\echo '=================================================='
\echo 'Scenario: Get N occurrences after/before a date'
\echo ''

-- Test 6.1: after() across DST
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-09 10:00:00 EDT',
        '2025-03-10 10:00:00 EDT'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."after"(
        'FREQ=DAILY;COUNT=10',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-08 15:00:00-05'::TIMESTAMPTZ,  -- After first occurrence
        2,  -- Get 2 occurrences
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Offset Queries',
        'after() works across DST boundary',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 6.2: before() across DST
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 EST',
        '2025-03-09 10:00:00 EDT'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."before"(
        'FREQ=DAILY;COUNT=10',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-10 00:00:00-04'::TIMESTAMPTZ,  -- Before last occurrence
        2,  -- Get 2 occurrences
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Offset Queries',
        'before() works across DST boundary',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 6.3: after() with inc=true includes boundary occurrence
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-08 10:00:00 EST'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."after"(
        'FREQ=DAILY;COUNT=10',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        1,
        'America/New_York',
        TRUE
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Offset Queries',
        'after() inc=true includes boundary',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 6.4: before() with inc=true includes boundary occurrence
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-09 10:00:00 EDT'
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."before"(
        'FREQ=DAILY;COUNT=10',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-09 10:00:00-04'::TIMESTAMPTZ,
        1,
        'America/New_York',
        TRUE
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Offset Queries',
        'before() inc=true includes boundary',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 7: Complex RRULE Patterns
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 7: Complex Patterns'
\echo '=================================================='
\echo 'Scenario: Test complex RRULE patterns with BYxxx rules'
\echo ''

-- Test 7.1: BYDAY with DST
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-03-10 10:00:00 EDT',  -- Monday (first after DST)
        '2025-03-12 10:00:00 EDT',  -- Wednesday
        '2025-03-14 10:00:00 EDT'   -- Friday
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;BYDAY=MO,WE,FR;COUNT=3',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,  -- Saturday (not included)
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Complex Patterns',
        'BYDAY filter works across DST',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 7.2: MONTHLY with DST
DO $$
DECLARE
    results TIMESTAMPTZ[];
    expected TEXT[] := ARRAY[
        '2025-02-15 10:00:00 EST',  -- Before DST
        '2025-03-15 10:00:00 EDT',  -- After DST spring forward
        '2025-04-15 10:00:00 EDT'   -- After DST
    ];
    actual TEXT[];
    matches BOOLEAN;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3',
        '2025-02-15 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);
    matches := (actual = expected);

    INSERT INTO tz_api_test_results VALUES (
        'Complex Patterns',
        'MONTHLY frequency works across DST',
        matches,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 8: rrule."count"() with timezone parameter
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 8: rrule."count"() TIMESTAMPTZ API'
\echo '=================================================='
\echo ''

-- Test 8.1: count() with explicit timezone parameter
DO $$
DECLARE
    result INTEGER;
    expected INTEGER := 5;
    status TEXT;
BEGIN
    SELECT rrule."count"(
        'FREQ=DAILY;COUNT=5',
        '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal_soft(
        'count() API',
        'Explicit timezone parameter',
        result::TEXT,
        expected::TEXT
    );

    RAISE NOTICE 'Test 8.1: count() with explicit timezone % - Result: %', status, result;
END;
$$;

-- Test 8.2: count() with TZID in RRULE (no explicit timezone)
DO $$
DECLARE
    result INTEGER;
    expected INTEGER := 3;
    status TEXT;
BEGIN
    SELECT rrule."count"(
        'FREQ=WEEKLY;COUNT=3;TZID=Europe/London',
        '2025-03-08 10:00:00+00'::TIMESTAMPTZ,
        NULL  -- Should use TZID from RRULE
    ) INTO result;

    status := assert_equal_soft(
        'count() API',
        'TZID in RRULE (NULL timezone param)',
        result::TEXT,
        expected::TEXT
    );

    RAISE NOTICE 'Test 8.2: count() with TZID in RRULE % - Result: %', status, result;
END;
$$;

-- Test 8.3: count() timezone override (explicit param overrides TZID)
DO $$
DECLARE
    result INTEGER;
    expected INTEGER := 10;
    status TEXT;
BEGIN
    SELECT rrule."count"(
        'FREQ=DAILY;COUNT=10;TZID=Europe/London',
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'  -- Override TZID
    ) INTO result;

    status := assert_equal_soft(
        'count() API',
        'Timezone param overrides TZID',
        result::TEXT,
        expected::TEXT
    );

    RAISE NOTICE 'Test 8.3: count() timezone override % - Result: %', status, result;
END;
$$;

-- Test 8.4: count() defaults to UTC when no timezone specified
DO $$
DECLARE
    result INTEGER;
    expected INTEGER := 7;
    status TEXT;
BEGIN
    SELECT rrule."count"(
        'FREQ=DAILY;COUNT=7',  -- No TZID
        '2025-01-01 00:00:00+00'::TIMESTAMPTZ,
        NULL  -- No explicit timezone → should use UTC
    ) INTO result;

    status := assert_equal_soft(
        'count() API',
        'Defaults to UTC when no timezone',
        result::TEXT,
        expected::TEXT
    );

    RAISE NOTICE 'Test 8.4: count() defaults to UTC % - Result: %', status, result;
END;
$$;


-- ================================================================================================================
-- TEST SUITE 9: rrule."next"() with timezone parameter
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 9: rrule."next"() TIMESTAMPTZ API'
\echo '=================================================='
\echo ''

-- Test 9.1: next() with explicit timezone parameter (deterministic with fixed reference_time)
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule."next"(
        'FREQ=DAILY',
        '2020-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York',
        '2025-06-15 12:00:00+00'::TIMESTAMPTZ
    ) INTO result;

    status := assert_equal_soft(
        'next() API',
        'Returns next daily occurrence after reference_time',
        result::TEXT,
        '2025-06-15 14:00:00+00'
    );

    RAISE NOTICE 'Test 9.1: next() with explicit timezone % - Result: %', status, result;
END;
$$;

-- Test 9.2: next() with TZID in RRULE (using fixed reference_time for deterministic assertion)
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule."next"(
        'FREQ=WEEKLY;TZID=Europe/London',
        '2020-01-01 10:00:00+00'::TIMESTAMPTZ,
        NULL,
        '2025-06-15 12:00:00+00'::TIMESTAMPTZ
    ) INTO result;

    status := assert_equal_soft(
        'next() API',
        'TZID in RRULE returns future occurrence',
        result::TEXT,
        '2025-06-18 09:00:00+00'
    );

    RAISE NOTICE 'Test 9.2: next() with TZID in RRULE % - Result: %', status, result;
END;
$$;

-- Test 9.3: next() timezone override (using fixed reference_time for deterministic assertion)
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule."next"(
        'FREQ=MONTHLY;TZID=Europe/London',
        '2020-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York',
        '2025-06-15 12:00:00+00'::TIMESTAMPTZ
    ) INTO result;

    status := assert_equal_soft(
        'next() API',
        'Timezone param override works',
        result::TEXT,
        '2025-07-01 14:00:00+00'
    );

    RAISE NOTICE 'Test 9.3: next() timezone override % - Result: %', status, result;
END;
$$;

-- Test 9.4: next() with COUNT limit (should return NULL after COUNT reached)
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule."next"(
        'FREQ=DAILY;COUNT=1',
        '2020-01-01 10:00:00+00'::TIMESTAMPTZ,
        'UTC'
    ) INTO result;

    status := assert_equal_soft(
        'next() API',
        'Returns NULL when COUNT exhausted',
        COALESCE(result::TEXT, 'NULL'),
        'NULL'
    );

    RAISE NOTICE 'Test 9.4: next() with exhausted COUNT % - Result: %', status, COALESCE(result::TEXT, 'NULL');
END;
$$;


-- ================================================================================================================
-- TEST SUITE 10: rrule."most_recent"() with timezone parameter
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 10: rrule."most_recent"() TIMESTAMPTZ API'
\echo '=================================================='
\echo ''

-- Test 10.1: most_recent() with explicit timezone parameter (using fixed reference_time)
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule."most_recent"(
        'FREQ=DAILY',
        '2020-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York',
        '2025-06-15 12:00:00+00'::TIMESTAMPTZ
    ) INTO result;

    -- Before the fix for before() >1000 occurrences, this returned 2022-09-26 14:00:00+00
    -- (the 1000th occurrence instead of the correct last one before reference_time).
    -- The correct answer is 2025-06-14 10:00 AM EDT = 2025-06-14 14:00:00+00.
    status := assert_equal_soft(
        'most_recent() API',
        'Returns occurrence before reference_time',
        result::TEXT,
        '2025-06-14 14:00:00+00'
    );

    RAISE NOTICE 'Test 10.1: most_recent() with explicit timezone % - Result: %', status, result;
END;
$$;

-- Test 10.2: most_recent() with TZID in RRULE (using fixed reference_time)
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule."most_recent"(
        'FREQ=WEEKLY;TZID=Europe/London',
        '2020-01-01 10:00:00+00'::TIMESTAMPTZ,
        NULL,
        '2025-06-15 12:00:00+00'::TIMESTAMPTZ
    ) INTO result;

    status := assert_equal_soft(
        'most_recent() API',
        'TZID in RRULE returns past occurrence',
        result::TEXT,
        '2025-06-11 09:00:00+00'
    );

    RAISE NOTICE 'Test 10.2: most_recent() with TZID in RRULE % - Result: %', status, result;
END;
$$;

-- Test 10.3: most_recent() timezone override (using fixed reference_time)
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule."most_recent"(
        'FREQ=MONTHLY;TZID=Europe/London',
        '2020-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York',
        '2025-06-15 12:00:00+00'::TIMESTAMPTZ
    ) INTO result;

    status := assert_equal_soft(
        'most_recent() API',
        'Timezone param override works',
        result::TEXT,
        '2025-06-01 14:00:00+00'
    );

    RAISE NOTICE 'Test 10.3: most_recent() timezone override % - Result: %', status, result;
END;
$$;

-- Test 10.4: most_recent() with dtstart in future (should return NULL)
DO $$
DECLARE
    result TIMESTAMPTZ;
    status TEXT;
BEGIN
    SELECT rrule."most_recent"(
        'FREQ=DAILY',
        '2099-01-01 10:00:00+00'::TIMESTAMPTZ,
        'UTC',
        '2025-01-01 00:00:00+00'::TIMESTAMPTZ
    ) INTO result;

    status := assert_equal_soft(
        'most_recent() API',
        'Returns NULL when dtstart is in future',
        COALESCE(result::TEXT, 'NULL'),
        'NULL'
    );

    RAISE NOTICE 'Test 10.4: most_recent() with future dtstart % - Result: %', status, COALESCE(result::TEXT, 'NULL');
END;
$$;


-- ================================================================================================================
-- TEST SUITE 11: rrule."overlaps"() with timezone parameter
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 11: rrule."overlaps"() TIMESTAMPTZ API'
\echo '=================================================='
\echo ''

-- Test 11.1: rrule."overlaps"() with explicit timezone parameter - TRUE case
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule."overlaps"(
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-01 11:00:00-05'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=30',
        '2025-01-05 00:00:00-05'::TIMESTAMPTZ,
        '2025-01-10 23:59:59-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal_soft(
        'rrule."overlaps"() API',
        'Returns TRUE when event overlaps range',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 11.1: rrule."overlaps"() TRUE case % - Result: %', status, result;
END;
$$;

-- Test 11.2: rrule."overlaps"() with explicit timezone parameter - FALSE case
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule."overlaps"(
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-01 11:00:00-05'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=3',
        '2025-02-01 00:00:00-05'::TIMESTAMPTZ,
        '2025-02-28 23:59:59-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal_soft(
        'rrule."overlaps"() API',
        'Returns FALSE when no overlap',
        CASE WHEN result THEN 'true' ELSE 'false' END,
        'false'
    );

    RAISE NOTICE 'Test 11.2: rrule."overlaps"() FALSE case % - Result: %', status, result;
END;
$$;

-- Test 11.3: rrule."overlaps"() with TZID in RRULE
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule."overlaps"(
        '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
        '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
        'FREQ=WEEKLY;COUNT=10;TZID=Europe/London',
        '2025-01-15 00:00:00+00'::TIMESTAMPTZ,
        '2025-01-31 23:59:59+00'::TIMESTAMPTZ,
        NULL
    ) INTO result;

    status := assert_equal_soft(
        'rrule."overlaps"() API',
        'TZID in RRULE works correctly',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 11.3: rrule."overlaps"() with TZID in RRULE % - Result: %', status, result;
END;
$$;

-- Test 11.4: rrule."overlaps"() timezone override
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule."overlaps"(
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-01 11:00:00-05'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=20;TZID=Europe/London',
        '2025-01-10 00:00:00-05'::TIMESTAMPTZ,
        '2025-01-15 23:59:59-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal_soft(
        'rrule."overlaps"() API',
        'Timezone param overrides TZID',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 11.4: rrule."overlaps"() timezone override % - Result: %', status, result;
END;
$$;

-- Test 11.5: rrule."overlaps"() across DST boundary
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule."overlaps"(
        '2025-03-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-01 11:00:00-05'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=15',
        '2025-03-08 00:00:00-05'::TIMESTAMPTZ,
        '2025-03-10 23:59:59-04'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal_soft(
        'rrule."overlaps"() API',
        'Handles DST transitions correctly',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 11.5: rrule."overlaps"() across DST % - Result: %', status, result;
END;
$$;

-- Test 11.6: rrule."overlaps"() with NULL RRULE (single event, no recurrence)
DO $$
DECLARE
    result BOOLEAN;
    status TEXT;
BEGIN
    SELECT rrule."overlaps"(
        '2025-01-15 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-15 11:00:00-05'::TIMESTAMPTZ,
        NULL,
        '2025-01-01 00:00:00-05'::TIMESTAMPTZ,
        '2025-01-31 23:59:59-05'::TIMESTAMPTZ,
        'America/New_York'
    ) INTO result;

    status := assert_equal_soft(
        'rrule."overlaps"() API',
        'Handles NULL RRULE (single event)',
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 11.6: rrule."overlaps"() with NULL RRULE % - Result: %', status, result;
END;
$$;


-- ================================================================================================================
-- TEST SUITE 12: Timezone validation
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 12: Timezone Validation'
\echo '=================================================='
\echo ''

-- Test 12.1: Invalid timezone should raise exception
DO $$
DECLARE
    error_raised BOOLEAN := FALSE;
    status TEXT;
BEGIN
    BEGIN
        PERFORM rrule."count"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'Invalid/Timezone'
        );
    EXCEPTION WHEN OTHERS THEN
        error_raised := TRUE;
    END;

    status := assert_equal_soft(
        'Timezone Validation',
        'Invalid timezone raises exception',
        error_raised::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 12.1: Invalid timezone validation % - Error raised: %', status, error_raised;
END;
$$;


-- ================================================================================================================
-- TEST SUITE 13: UNTIL + Timezone Combinations (TIMESTAMPTZ API)
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 13: UNTIL + Timezone'
\echo '=================================================='
\echo 'Scenario: Test UNTIL boundary with timezone-aware recurrence'
\echo ''

-- Test 13.1: UNTIL with TIMESTAMPTZ API across DST transition
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[] := ARRAY[
        '2025-03-07 10:00:00 EST',
        '2025-03-08 10:00:00 EST',
        '2025-03-09 10:00:00 EDT',
        '2025-03-10 10:00:00 EDT',
        '2025-03-11 10:00:00 EDT'
    ];
    result_count INT;
BEGIN
    -- Daily at 10:00 AM ET starting March 7, range through March 11 (after spring-forward on March 9)
    -- Signature: between(rrule, dtstart, range_start, range_end, timezone, inc)
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."between"(
        'FREQ=DAILY',
        '2025-03-07 10:00:00-05'::TIMESTAMPTZ,  -- 10:00 AM EST
        '2025-03-07 00:00:00-05'::TIMESTAMPTZ,
        '2025-03-11 23:59:59-04'::TIMESTAMPTZ,   -- After DST
        'America/New_York',
        TRUE
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual
    FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    INSERT INTO tz_api_test_results VALUES (
        'UNTIL + Timezone',
        'UNTIL across DST with between() produces correct count and dates',
        result_count = 5 AND actual = expected,
        result_count::TEXT || ' dates: ' || array_to_string(actual, ', '),
        '5 dates: ' || array_to_string(expected, ', ')
    );
END;
$$;

-- Test 13.2: UNTIL boundary precision with TIMESTAMPTZ API
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[] := ARRAY[
        '2025-01-06 09:00:00 EST',
        '2025-01-13 09:00:00 EST',
        '2025-01-20 09:00:00 EST'
    ];
    result_count INT;
BEGIN
    -- Weekly on Mondays, range covers exactly 3 weeks
    -- Signature: between(rrule, dtstart, range_start, range_end, timezone, inc)
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."between"(
        'FREQ=WEEKLY;BYDAY=MO',
        '2025-01-06 09:00:00-05'::TIMESTAMPTZ,  -- Monday 9 AM EST
        '2025-01-06 00:00:00-05'::TIMESTAMPTZ,
        '2025-01-20 23:59:59-05'::TIMESTAMPTZ,
        'America/New_York',
        TRUE
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual
    FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    INSERT INTO tz_api_test_results VALUES (
        'UNTIL + Timezone',
        'UNTIL with WEEKLY+BYDAY produces exact 3 Monday dates',
        result_count = 3 AND actual = expected,
        result_count::TEXT || ' dates: ' || array_to_string(actual, ', '),
        '3 dates: ' || array_to_string(expected, ', ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 14: DST Gap and Ambiguous Time Tests
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 14: DST Gap and Ambiguous Times'
\echo '=================================================='
\echo 'Scenario: Test recurrence at times that fall into DST gaps or are ambiguous'
\echo ''

-- Test 14.1: Spring-forward gap time (2:30 AM on March 9, 2025 does not exist in America/New_York)
-- PostgreSQL resolves gap times by advancing to the next valid time (3:00 AM EDT → 07:00 UTC)
-- But timezone-aware recurrence should preserve wall-clock semantics
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    result_count INT;
BEGIN
    -- Daily recurrence at 2:30 AM starting March 8 (before spring forward)
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-03-08 02:30:00-05'::TIMESTAMPTZ,  -- 2:30 AM EST
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    -- Verify we get exactly 3 occurrences (no crash/skip on the gap date)
    INSERT INTO tz_api_test_results VALUES (
        'DST Gap Times',
        'Spring-forward gap: 2:30 AM produces 3 occurrences',
        result_count = 3,
        result_count::TEXT,
        '3'
    );

    -- Verify exact timestamps:
    -- Mar 8: 2:30 AM EST = 07:30 UTC
    -- Mar 9: 2:30 AM doesn't exist (spring forward); PG advances to 3:30 AM EDT = 07:30 UTC
    -- Mar 10: 2:30 AM EDT = 06:30 UTC
    INSERT INTO tz_api_test_results VALUES (
        'DST Gap Times',
        'Spring-forward gap: exact UTC timestamps',
        results IS NOT NULL
            AND array_length(results, 1) = 3
            AND EXTRACT(HOUR FROM results[1]) = 7 AND EXTRACT(MINUTE FROM results[1]) = 30
            AND results[1]::DATE = '2025-03-08'
            AND results[2]::DATE = '2025-03-09'
            AND results[3]::DATE = '2025-03-10'
            AND EXTRACT(HOUR FROM results[3]) = 6 AND EXTRACT(MINUTE FROM results[3]) = 30,
        COALESCE(results::TEXT, 'NULL'),
        'Mar 8 07:30 UTC, Mar 9 (gap-advanced), Mar 10 06:30 UTC'
    );
END;
$$;

-- Test 14.2: Fall-back ambiguous time (1:30 AM on November 2, 2025 occurs twice in America/New_York)
-- One in EDT (05:30 UTC) and one in EST (06:30 UTC). PostgreSQL picks one deterministically.
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    result_count INT;
BEGIN
    -- Daily recurrence at 1:30 AM starting November 1 (before fall back)
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-11-01 01:30:00-04'::TIMESTAMPTZ,  -- 1:30 AM EDT
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    -- Verify we get exactly 3 occurrences and wall-clock time stays at 1:30 AM
    INSERT INTO tz_api_test_results VALUES (
        'DST Gap Times',
        'Fall-back ambiguous: 1:30 AM produces 3 occurrences',
        result_count = 3,
        result_count::TEXT,
        '3'
    );

    -- Verify exact timestamps:
    -- Nov 1: 1:30 AM EDT = 05:30 UTC
    -- Nov 2: 1:30 AM EST (PG picks standard time) = 06:30 UTC
    -- Nov 3: 1:30 AM EST = 06:30 UTC
    INSERT INTO tz_api_test_results VALUES (
        'DST Gap Times',
        'Fall-back ambiguous: exact UTC timestamps',
        results IS NOT NULL
            AND array_length(results, 1) = 3
            AND results[1]::DATE = '2025-11-01'
            AND EXTRACT(HOUR FROM results[1]) = 5 AND EXTRACT(MINUTE FROM results[1]) = 30
            AND results[2]::DATE = '2025-11-02'
            AND EXTRACT(HOUR FROM results[2]) = 6 AND EXTRACT(MINUTE FROM results[2]) = 30
            AND results[3]::DATE = '2025-11-03'
            AND EXTRACT(HOUR FROM results[3]) = 6 AND EXTRACT(MINUTE FROM results[3]) = 30,
        COALESCE(results::TEXT, 'NULL'),
        'Nov 1 05:30 UTC, Nov 2 06:30 UTC, Nov 3 06:30 UTC'
    );

    -- Phase C1: Assert which UTC offset PostgreSQL chooses for the ambiguous Nov 2 time.
    -- PostgreSQL picks standard time (EST, UTC-5) for ambiguous fall-back times.
    -- RFC 5545 Section 3.3.5 says "use first occurrence" (daylight/EDT, UTC-4).
    -- This documents the known divergence: PG chooses post-transition (standard) offset.
    -- We verify by checking the UTC hour: 1:30 AM EST = 06:30 UTC; 1:30 AM EDT = 05:30 UTC.
    INSERT INTO tz_api_test_results VALUES (
        'DST Gap Times',
        'Fall-back: Nov 2 1:30 AM resolves to EST (UTC-5, standard time)',
        (SELECT EXTRACT(HOUR FROM ts) = 6 FROM unnest(results) ts WHERE ts::DATE = '2025-11-02' LIMIT 1),
        (SELECT 'UTC hour=' || EXTRACT(HOUR FROM ts)::TEXT FROM unnest(results) ts WHERE ts::DATE = '2025-11-02' LIMIT 1),
        'UTC hour=6'
    );
END;
$$;

-- Test 14.3: Daily recurrence spanning spring-forward with gap time
-- On the spring-forward date (March 9), 2:30 AM doesn't exist.
-- PostgreSQL advances gap times to the next valid time (3:30 AM EDT).
-- Non-gap dates should preserve the original 2:30 AM wall-clock time.
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    non_gap_consistent BOOLEAN;
    gap_day_wallclock TEXT;
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=5',
        '2025-03-07 02:30:00-05'::TIMESTAMPTZ,  -- 2:30 AM EST
        'America/New_York'
    ) ts;

    -- Non-gap dates (all except March 9) should show 02:30
    SELECT COUNT(DISTINCT to_char(ts AT TIME ZONE 'America/New_York', 'HH24:MI')) = 1
    INTO non_gap_consistent
    FROM unnest(results) ts
    WHERE ts::DATE != '2025-03-09';

    -- Gap date (March 9) should be advanced to 03:30 by PostgreSQL
    SELECT to_char(ts AT TIME ZONE 'America/New_York', 'HH24:MI')
    INTO gap_day_wallclock
    FROM unnest(results) ts
    WHERE ts::DATE = '2025-03-09';

    INSERT INTO tz_api_test_results VALUES (
        'DST Gap Times',
        'Daily across spring-forward: non-gap days preserve wall-clock',
        non_gap_consistent AND gap_day_wallclock = '03:30',
        'non_gap_consistent=' || non_gap_consistent::TEXT || ', gap_day=' || gap_day_wallclock,
        'non_gap_consistent=true, gap_day=03:30'
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 15: Non-Whole-Hour Timezone Offsets
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 15: Non-Whole-Hour Timezone Offsets'
\echo '=================================================='
\echo 'Scenario: Test timezones with 30-minute and 45-minute UTC offsets'
\echo ''

-- Test 15.1: Asia/Kolkata (UTC+05:30) - Half-hour offset, no DST
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[];
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-01-15 10:00:00+05:30'::TIMESTAMPTZ,  -- 10:00 AM IST
        'Asia/Kolkata'
    ) ts;

    -- Format as wall-clock times in Kolkata timezone
    SELECT array_agg(
        to_char(ts AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD HH24:MI:SS')
        ORDER BY ordinality
    ) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    expected := ARRAY[
        '2025-01-15 10:00:00',
        '2025-01-16 10:00:00',
        '2025-01-17 10:00:00'
    ];

    INSERT INTO tz_api_test_results VALUES (
        'Half-Hour Offsets',
        'Asia/Kolkata (UTC+05:30) preserves 10:00 AM wall-clock',
        actual = expected,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 15.2: Asia/Kathmandu (UTC+05:45) - 45-minute offset, no DST
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[];
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=WEEKLY;BYDAY=MO;COUNT=3',
        '2025-01-13 09:00:00+05:45'::TIMESTAMPTZ,  -- Monday 9:00 AM NPT
        'Asia/Kathmandu'
    ) ts;

    SELECT array_agg(
        to_char(ts AT TIME ZONE 'Asia/Kathmandu', 'YYYY-MM-DD HH24:MI:SS')
        ORDER BY ordinality
    ) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    expected := ARRAY[
        '2025-01-13 09:00:00',  -- Monday
        '2025-01-20 09:00:00',  -- Monday
        '2025-01-27 09:00:00'   -- Monday
    ];

    INSERT INTO tz_api_test_results VALUES (
        'Half-Hour Offsets',
        'Asia/Kathmandu (UTC+05:45) WEEKLY;BYDAY=MO preserves wall-clock',
        actual = expected,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 15.3: Australia/Adelaide (UTC+09:30/+10:30) - Half-hour offset + DST fall-back
-- April 6, 2025: ACDT (UTC+10:30) -> ACST (UTC+09:30) at 3:00 AM
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[];
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-04-05 10:00:00+10:30'::TIMESTAMPTZ,  -- 10:00 AM ACDT
        'Australia/Adelaide'
    ) ts;

    -- Wall-clock should stay at 10:00 AM across the DST transition
    SELECT array_agg(
        to_char(ts AT TIME ZONE 'Australia/Adelaide', 'YYYY-MM-DD HH24:MI:SS')
        ORDER BY ordinality
    ) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    expected := ARRAY[
        '2025-04-05 10:00:00',  -- ACDT (before fall-back)
        '2025-04-06 10:00:00',  -- ACST (after fall-back)
        '2025-04-07 10:00:00'   -- ACST
    ];

    INSERT INTO tz_api_test_results VALUES (
        'Half-Hour Offsets',
        'Australia/Adelaide half-hour offset + DST fall-back preserves wall-clock',
        actual = expected,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;


-- ================================================================================================================
-- TEST SUITE 16: Southern Hemisphere DST
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 16: Southern Hemisphere DST'
\echo '=================================================='
\echo 'Scenario: Test DST transitions in southern hemisphere (reversed seasons)'
\echo ''

-- Test 16.1: Australia/Sydney spring-forward (Oct 5, 2025: AEST -> AEDT at 2:00 AM)
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[];
    result_count INT;
BEGIN
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-10-04 10:00:00+10'::TIMESTAMPTZ,  -- 10:00 AM AEST
        'Australia/Sydney'
    ) ts;

    SELECT array_agg(
        to_char(ts AT TIME ZONE 'Australia/Sydney', 'YYYY-MM-DD HH24:MI:SS')
        ORDER BY ordinality
    ) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    expected := ARRAY[
        '2025-10-04 10:00:00',  -- AEST (before spring-forward)
        '2025-10-05 10:00:00',  -- AEDT (after spring-forward)
        '2025-10-06 10:00:00'   -- AEDT
    ];

    INSERT INTO tz_api_test_results VALUES (
        'Southern Hemisphere DST',
        'Sydney spring-forward: wall-clock preserved across Oct transition',
        actual = expected AND result_count = 3,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 16.2: Pacific/Auckland fall-back (Apr 6, 2025: NZDT -> NZST at 3:00 AM)
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[];
    result_count INT;
BEGIN
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-04-05 10:00:00+13'::TIMESTAMPTZ,  -- 10:00 AM NZDT
        'Pacific/Auckland'
    ) ts;

    SELECT array_agg(
        to_char(ts AT TIME ZONE 'Pacific/Auckland', 'YYYY-MM-DD HH24:MI:SS')
        ORDER BY ordinality
    ) INTO actual FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    expected := ARRAY[
        '2025-04-05 10:00:00',  -- NZDT (before fall-back)
        '2025-04-06 10:00:00',  -- NZST (after fall-back)
        '2025-04-07 10:00:00'   -- NZST
    ];

    INSERT INTO tz_api_test_results VALUES (
        'Southern Hemisphere DST',
        'Auckland fall-back: wall-clock preserved across Apr transition',
        actual = expected AND result_count = 3,
        array_to_string(actual, E'\n  '),
        array_to_string(expected, E'\n  ')
    );
END;
$$;

-- Test 16.3: Australia/Sydney year-boundary DST (January = AEDT, UTC+11)
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual_offsets INT[];
BEGIN
    SELECT array_agg(ts ORDER BY ts) INTO results
    FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=1;COUNT=3',
        '2024-01-15 10:00:00+11'::TIMESTAMPTZ,  -- 10:00 AM AEDT (January = summer)
        'Australia/Sydney'
    ) ts;

    -- January in Sydney is always AEDT (UTC+11), verify UTC offset
    -- AEDT: local time is UTC+11, so UTC hour = local hour - 11
    -- 10:00 AM AEDT = 23:00 UTC (previous day)
    SELECT array_agg(
        EXTRACT(HOUR FROM ts)::INT
        ORDER BY ordinality
    ) INTO actual_offsets FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    INSERT INTO tz_api_test_results VALUES (
        'Southern Hemisphere DST',
        'Sydney January occurrences use AEDT (UTC+11) not AEST',
        actual_offsets = ARRAY[23, 23, 23],
        array_to_string(actual_offsets::TEXT[], ', '),
        '23, 23, 23'
    );
END;
$$;


-- ================================================================================================================
-- RESULTS SUMMARY
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST RESULTS SUMMARY'
\echo '=================================================='
\echo ''

SELECT
    test_suite,
    test_name,
    CASE WHEN passed THEN '[PASS]' ELSE '[FAIL]' END as status
FROM tz_api_test_results
ORDER BY
    CASE test_suite
        WHEN 'DST Spring Forward' THEN 1
        WHEN 'DST Fall Back' THEN 2
        WHEN 'UTC Timezone' THEN 3
        WHEN 'Multiple Timezones' THEN 4
        WHEN 'Range Queries' THEN 5
        WHEN 'Offset Queries' THEN 6
        WHEN 'Complex Patterns' THEN 7
        WHEN 'count() API' THEN 8
        WHEN 'next() API' THEN 9
        WHEN 'most_recent() API' THEN 10
        WHEN 'rrule."overlaps"() API' THEN 11
        WHEN 'Timezone Validation' THEN 12
        WHEN 'UNTIL + Timezone' THEN 13
        WHEN 'DST Gap Times' THEN 14
        WHEN 'Half-Hour Offsets' THEN 15
        WHEN 'Southern Hemisphere DST' THEN 16
        WHEN 'YEARLY SKIP Drift TZ' THEN 17
        WHEN 'MONTHLY SKIP Drift TZ' THEN 18
        WHEN 'SKIP INTERVAL Parity TZ' THEN 19
        WHEN 'NULL Input TZ' THEN 20
        WHEN 'Edge Cases TZ' THEN 21
    END,
    test_name;

\echo ''
\echo 'Detailed failures (if any):'
\echo ''

SELECT
    test_suite || ': ' || test_name as test,
    'Expected: ' || expected as expected_output,
    'Actual: ' || actual as actual_output
FROM tz_api_test_results
WHERE NOT passed;

\echo ''
\echo 'Overall Summary:'
SELECT
    COUNT(*) as total_tests,
    SUM(CASE WHEN passed THEN 1 ELSE 0 END) as passed,
    SUM(CASE WHEN NOT passed THEN 1 ELSE 0 END) as failed,
    ROUND(100.0 * SUM(CASE WHEN passed THEN 1 ELSE 0 END) / COUNT(*), 1) || '%' as pass_rate
FROM tz_api_test_results;

-- ================================================================================================================
-- SKIP=FORWARD TIME PRESERVATION TESTS (TIMESTAMPTZ API)
-- ================================================================================================================

\echo ''
\echo '=================================================='
\echo 'Testing SKIP=FORWARD time preservation (TIMESTAMPTZ API)'
\echo '=================================================='

-- MONTHLY SKIP=FORWARD with non-midnight dtstart should preserve time component
-- Feb FORWARD→Mar 1, Mar restores to 31st (no drift). Both within range.
INSERT INTO tz_api_test_results (test_suite, test_name, passed, actual, expected)
SELECT
    'SKIP=FORWARD Time',
    'MONTHLY SKIP=FORWARD preserves time via TIMESTAMPTZ API',
    actual_val = ARRAY['2025-03-01 14:30:00','2025-03-31 14:30:00']::TIMESTAMP[],
    actual_val::TEXT,
    '{2025-03-01 14:30:00,2025-03-31 14:30:00}'
FROM (
    SELECT array_agg(d ORDER BY d) AS actual_val
    FROM (
        SELECT (occurrence AT TIME ZONE 'America/New_York')::TIMESTAMP AS d
        FROM rrule."between"(
            'FREQ=MONTHLY;SKIP=FORWARD;RSCALE=GREGORIAN',
            '2025-01-31 14:30:00-05'::TIMESTAMPTZ,
            '2025-02-01 00:00:00-05'::TIMESTAMPTZ,
            '2025-04-01 00:00:00-04'::TIMESTAMPTZ,
            'America/New_York'
        ) AS occurrence
    ) sub
) result;

-- YEARLY SKIP=FORWARD with non-midnight dtstart should preserve time component
INSERT INTO tz_api_test_results (test_suite, test_name, passed, actual, expected)
SELECT
    'SKIP=FORWARD Time',
    'YEARLY SKIP=FORWARD preserves time via TIMESTAMPTZ API',
    actual_val = ARRAY['2025-03-01 09:15:00']::TIMESTAMP[],
    actual_val::TEXT,
    '{2025-03-01 09:15:00}'
FROM (
    SELECT array_agg(d ORDER BY d) AS actual_val
    FROM (
        SELECT (occurrence AT TIME ZONE 'America/New_York')::TIMESTAMP AS d
        FROM rrule."between"(
            'FREQ=YEARLY;BYMONTH=2;SKIP=FORWARD;RSCALE=GREGORIAN',
            '2025-01-29 09:15:00-05'::TIMESTAMPTZ,
            '2025-02-01 00:00:00-05'::TIMESTAMPTZ,
            '2026-01-01 00:00:00-05'::TIMESTAMPTZ,
            'America/New_York'
        ) AS occurrence
    ) sub
) result;

-- ================================================================================================================
-- OVERLAPS BOUNDARY SEMANTICS TESTS (TIMESTAMPTZ API)
-- ================================================================================================================

\echo ''
\echo '=================================================='
\echo 'Testing overlaps() boundary semantics (TIMESTAMPTZ API)'
\echo '=================================================='

-- Overlap detection where occurrence falls exactly on boundary timestamp
INSERT INTO tz_api_test_results (test_suite, test_name, passed, actual, expected)
SELECT
    'Overlaps Boundary',
    'TIMESTAMPTZ overlaps() detects boundary occurrence',
    rrule."overlaps"(
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        NULL::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=5',
        '2025-01-03 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-05 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) = TRUE,
    (rrule."overlaps"(
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        NULL::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=5',
        '2025-01-03 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-05 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ))::TEXT,
    'true';

-- ================================================================================================================
-- TEST SUITE 17: YEARLY SKIP Drift Prevention (TIMESTAMPTZ API)
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 17: YEARLY SKIP Drift Prevention (TIMESTAMPTZ API)'
\echo '=================================================='
\echo ''

-- Test 17.1: YEARLY SKIP=FORWARD from leap day via TIMESTAMPTZ API
-- Each year re-attempts Feb 29. Non-leap years forward to Mar 1.
-- Leap year 2028 restores to Feb 29 — no cumulative drift.
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[] := ARRAY[
        '2024-02-29 10:00:00 EST',
        '2025-03-01 10:00:00 EST',
        '2026-03-01 10:00:00 EST',
        '2027-03-01 10:00:00 EST',
        '2028-02-29 10:00:00 EST'
    ];
    result_count INT;
BEGIN
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=YEARLY;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=5',
        '2024-02-29 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual
    FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    INSERT INTO tz_api_test_results VALUES (
        'YEARLY SKIP Drift TZ',
        'YEARLY SKIP=FORWARD from Feb 29 preserves wall-clock (TZ)',
        result_count = 5 AND actual = expected,
        result_count::TEXT || ' dates: ' || array_to_string(COALESCE(actual, ARRAY[]::TEXT[]), ', '),
        '5 dates: ' || array_to_string(expected, ', ')
    );
END;
$$;

-- Test 17.2: YEARLY SKIP=OMIT from leap day via TIMESTAMPTZ API
-- Mirrors Gap 2: only leap years produce results (3 within 10-year window)
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[] := ARRAY[
        '2024-02-29 10:00:00 EST',
        '2028-02-29 10:00:00 EST',
        '2032-02-29 10:00:00 EST'
    ];
    result_count INT;
BEGIN
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=YEARLY;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=5',
        '2024-02-29 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual
    FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    INSERT INTO tz_api_test_results VALUES (
        'YEARLY SKIP Drift TZ',
        'YEARLY SKIP=OMIT from Feb 29 returns only leap years (TZ)',
        result_count = 3 AND actual = expected,
        result_count::TEXT || ' dates: ' || array_to_string(COALESCE(actual, ARRAY[]::TEXT[]), ', '),
        '3 dates: ' || array_to_string(expected, ', ')
    );
END;
$$;

-- ================================================================================================================
-- TEST SUITE 18: MONTHLY SKIP Drift Prevention (TIMESTAMPTZ API)
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 18: MONTHLY SKIP Drift Prevention (TIMESTAMPTZ API)'
\echo '=================================================='
\echo ''

-- Test 18.1: MONTHLY INTERVAL=3 SKIP=OMIT from Jan 31 via TIMESTAMPTZ API
-- Mirrors Gap 4: OMIT advances by rule.interval months
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[] := ARRAY[
        '2025-01-31 10:00:00 EST',
        '2025-07-31 10:00:00 EDT',
        '2025-10-31 10:00:00 EDT',
        '2026-01-31 10:00:00 EST'
    ];
    result_count INT;
BEGIN
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=MONTHLY;INTERVAL=3;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=4',
        '2025-01-31 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual
    FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    INSERT INTO tz_api_test_results VALUES (
        'MONTHLY SKIP Drift TZ',
        'MONTHLY INTERVAL=3 SKIP=OMIT from Jan 31 (TZ)',
        result_count = 4 AND actual = expected,
        result_count::TEXT || ' dates: ' || array_to_string(COALESCE(actual, ARRAY[]::TEXT[]), ', '),
        '4 dates: ' || array_to_string(expected, ', ')
    );
END;
$$;

-- Test 18.2: MONTHLY SKIP=FORWARD from Jan 31 via TIMESTAMPTZ API
-- Each month re-attempts day 31. Feb forwards to Mar 1 (can't hold 31).
-- Mar restores to 31. Apr forwards to May 1 (can't hold 31). No cumulative drift.
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[] := ARRAY[
        '2025-01-31 10:00:00 EST',
        '2025-03-01 10:00:00 EST',
        '2025-03-31 10:00:00 EDT',
        '2025-05-01 10:00:00 EDT'
    ];
    result_count INT;
BEGIN
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=MONTHLY;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=4',
        '2025-01-31 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual
    FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    INSERT INTO tz_api_test_results VALUES (
        'MONTHLY SKIP Drift TZ',
        'MONTHLY SKIP=FORWARD from Jan 31 (TZ)',
        result_count = 4 AND actual = expected,
        result_count::TEXT || ' dates: ' || array_to_string(COALESCE(actual, ARRAY[]::TEXT[]), ', '),
        '4 dates: ' || array_to_string(expected, ', ')
    );
END;
$$;

-- ================================================================================================================
-- TEST SUITE 19: SKIP+INTERVAL>1 Parity Tests (TIMESTAMPTZ API)
-- Mirrors TIMESTAMP SKIP+INTERVAL tests through the TZ API to verify TZ generator parity.
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 19: SKIP+INTERVAL>1 Parity (TIMESTAMPTZ API)'
\echo '=================================================='
\echo ''

-- Test 19.1: MONTHLY INTERVAL=2 SKIP=BACKWARD from Jan 31 via TIMESTAMPTZ API
-- Mirrors test_coverage_gaps.sql Test 13.3
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[] := ARRAY[
        '2025-01-31 00:00:00 EST',
        '2025-03-31 00:00:00 EDT',
        '2025-05-31 00:00:00 EDT',
        '2025-07-31 00:00:00 EDT',
        '2025-09-30 00:00:00 EDT',
        '2025-11-30 00:00:00 EST'
    ];
    result_count INT;
BEGIN
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=MONTHLY;INTERVAL=2;SKIP=BACKWARD;RSCALE=GREGORIAN;COUNT=6',
        '2025-01-31 00:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual
    FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    INSERT INTO tz_api_test_results VALUES (
        'SKIP INTERVAL Parity TZ',
        'MONTHLY INTERVAL=2 SKIP=BACKWARD (TZ)',
        result_count = 6 AND actual = expected,
        result_count::TEXT || ' dates: ' || array_to_string(COALESCE(actual, ARRAY[]::TEXT[]), ', '),
        '6 dates: ' || array_to_string(expected, ', ')
    );
END;
$$;

-- Test 19.2: MONTHLY INTERVAL=2 SKIP=FORWARD from Jan 31 via TIMESTAMPTZ API
-- Mirrors test_coverage_gaps.sql Test 13.4
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[] := ARRAY[
        '2025-01-31 00:00:00 EST',
        '2025-03-31 00:00:00 EDT',
        '2025-05-31 00:00:00 EDT',
        '2025-07-31 00:00:00 EDT',
        '2025-10-01 00:00:00 EDT',
        '2025-12-01 00:00:00 EST'
    ];
    result_count INT;
BEGIN
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=MONTHLY;INTERVAL=2;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=6',
        '2025-01-31 00:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual
    FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    INSERT INTO tz_api_test_results VALUES (
        'SKIP INTERVAL Parity TZ',
        'MONTHLY INTERVAL=2 SKIP=FORWARD (TZ)',
        result_count = 6 AND actual = expected,
        result_count::TEXT || ' dates: ' || array_to_string(COALESCE(actual, ARRAY[]::TEXT[]), ', '),
        '6 dates: ' || array_to_string(expected, ', ')
    );
END;
$$;

-- Test 19.3: YEARLY INTERVAL=2 SKIP=BACKWARD from Feb 29 via TIMESTAMPTZ API
-- Mirrors test_coverage_gaps.sql Test 31.1
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[] := ARRAY[
        '2024-02-29 10:00:00 EST',
        '2026-02-28 10:00:00 EST',
        '2028-02-29 10:00:00 EST',
        '2030-02-28 10:00:00 EST'
    ];
    result_count INT;
BEGIN
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=YEARLY;INTERVAL=2;SKIP=BACKWARD;RSCALE=GREGORIAN;COUNT=4',
        '2024-02-29 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual
    FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    INSERT INTO tz_api_test_results VALUES (
        'SKIP INTERVAL Parity TZ',
        'YEARLY INTERVAL=2 SKIP=BACKWARD (TZ)',
        result_count = 4 AND actual = expected,
        result_count::TEXT || ' dates: ' || array_to_string(COALESCE(actual, ARRAY[]::TEXT[]), ', '),
        '4 dates: ' || array_to_string(expected, ', ')
    );
END;
$$;

-- Test 19.4: YEARLY INTERVAL=2 SKIP=FORWARD from Feb 29 via TIMESTAMPTZ API
-- Mirrors test_coverage_gaps.sql Test 31.2
DO $$
DECLARE
    results TIMESTAMPTZ[];
    actual TEXT[];
    expected TEXT[] := ARRAY[
        '2024-02-29 10:00:00 EST',
        '2026-03-01 10:00:00 EST',
        '2028-02-29 10:00:00 EST',
        '2030-03-01 10:00:00 EST'
    ];
    result_count INT;
BEGIN
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=YEARLY;INTERVAL=2;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=4',
        '2024-02-29 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) ts;

    SELECT array_agg(format_ts_in_tz(ts, 'America/New_York') ORDER BY ordinality) INTO actual
    FROM unnest(results) WITH ORDINALITY AS t(ts, ordinality);

    INSERT INTO tz_api_test_results VALUES (
        'SKIP INTERVAL Parity TZ',
        'YEARLY INTERVAL=2 SKIP=FORWARD (TZ)',
        result_count = 4 AND actual = expected,
        result_count::TEXT || ' dates: ' || array_to_string(COALESCE(actual, ARRAY[]::TEXT[]), ', '),
        '4 dates: ' || array_to_string(expected, ', ')
    );
END;
$$;

-- Test 19.5: TZ API sub-day frequency error message should mention install_with_subday.sql
-- In standard install: HOURLY is rejected, error must mention install_with_subday.sql
-- In sub-day install: HOURLY succeeds, test passes (sub-day is enabled)
DO $$
DECLARE
    err_msg TEXT;
BEGIN
    BEGIN
        PERFORM * FROM rrule."all"(
            'FREQ=HOURLY;COUNT=3',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        );
        -- Sub-day installation: HOURLY works, this is expected
        INSERT INTO tz_api_test_results VALUES (
            'TZ Sub-day Error',
            'FREQ=HOURLY via TZ API (sub-day enabled or error expected)',
            TRUE,
            'HOURLY succeeded (sub-day installation)',
            'HOURLY succeeds in sub-day install OR error mentions install_with_subday.sql'
        );
    EXCEPTION WHEN OTHERS THEN
        err_msg := SQLERRM;
        -- Standard installation: error must be helpful
        INSERT INTO tz_api_test_results VALUES (
            'TZ Sub-day Error',
            'FREQ=HOURLY via TZ API (sub-day enabled or error expected)',
            err_msg LIKE '%install_with_subday%',
            err_msg,
            'HOURLY succeeds in sub-day install OR error mentions install_with_subday.sql'
        );
    END;
END;
$$;

-- ================================================================================================================
-- TEST SUITE 20: TIMESTAMPTZ API NULL Input Handling
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 20: TIMESTAMPTZ API NULL Input Handling'
\echo '=================================================='
\echo ''

-- Test 20.1: NULL dtstart raises descriptive error via TIMESTAMPTZ API
DO $$
DECLARE
    err_msg TEXT;
BEGIN
    BEGIN
        PERFORM * FROM rrule."all"(
            'FREQ=DAILY;COUNT=3',
            NULL::TIMESTAMPTZ,
            'America/New_York'
        );
        -- Should not reach here
        INSERT INTO tz_api_test_results VALUES (
            'NULL Input TZ',
            'NULL dtstart raises error via TIMESTAMPTZ API',
            FALSE,
            'No exception raised',
            'Exception: dtstart is required and cannot be NULL'
        );
    EXCEPTION WHEN OTHERS THEN
        err_msg := SQLERRM;
        INSERT INTO tz_api_test_results VALUES (
            'NULL Input TZ',
            'NULL dtstart raises error via TIMESTAMPTZ API',
            err_msg = 'dtstart is required and cannot be NULL',
            err_msg,
            'dtstart is required and cannot be NULL'
        );
    END;
END;
$$;

-- Test 20.2: NULL timezone falls back to UTC via TIMESTAMPTZ API
-- When timezone is NULL, the function uses UTC as fallback rather than raising an error.
DO $$
DECLARE
    results TIMESTAMPTZ[];
    result_count INT;
    expected_count INT := 3;
BEGIN
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3',
        '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
        NULL
    ) ts;

    INSERT INTO tz_api_test_results VALUES (
        'NULL Input TZ',
        'NULL timezone falls back to UTC (no error)',
        result_count = expected_count,
        result_count::TEXT || ' occurrences returned',
        expected_count::TEXT || ' occurrences returned'
    );
END;
$$;

-- Test 20.3: MINUTELY via TIMESTAMPTZ API raises sub-day disabled error (standard install)
-- In sub-day install: MINUTELY works, test passes. In standard install: error must mention install_with_subday.
DO $$
DECLARE
    err_msg TEXT;
BEGIN
    BEGIN
        PERFORM * FROM rrule."all"(
            'FREQ=MINUTELY;COUNT=3',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'America/New_York'
        );
        -- Sub-day installation: MINUTELY works, this is expected
        INSERT INTO tz_api_test_results VALUES (
            'NULL Input TZ',
            'FREQ=MINUTELY via TZ API (sub-day enabled or error expected)',
            TRUE,
            'MINUTELY succeeded (sub-day installation)',
            'MINUTELY succeeds in sub-day install OR error mentions install_with_subday'
        );
    EXCEPTION WHEN OTHERS THEN
        err_msg := SQLERRM;
        -- Standard installation: error must be helpful
        INSERT INTO tz_api_test_results VALUES (
            'NULL Input TZ',
            'FREQ=MINUTELY via TZ API (sub-day enabled or error expected)',
            err_msg LIKE '%install_with_subday%',
            err_msg,
            'MINUTELY succeeds in sub-day install OR error mentions install_with_subday'
        );
    END;
END;
$$;

-- ================================================================================================================
-- TEST SUITE 21: Edge Cases for after(), before(), overlaps(), and TZ generator truncation
-- ================================================================================================================
\echo ''
\echo '=================================================='
\echo 'TEST SUITE 21: TIMESTAMPTZ API Edge Cases'
\echo '=================================================='
\echo ''

-- Test 21.1: after() with count=0 should return no rows (early return)
DO $$
DECLARE
    result_count INT;
BEGIN
    SELECT COUNT(*) INTO result_count
    FROM rrule."after"(
        'FREQ=DAILY;COUNT=10',
        '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
        '2025-01-01 00:00:00+00'::TIMESTAMPTZ,
        0,       -- count=0
        'UTC',
        TRUE     -- inc
    );

    INSERT INTO tz_api_test_results VALUES (
        'Edge Cases TZ',
        'after() with count=0 returns no rows',
        result_count = 0,
        result_count::TEXT,
        '0'
    );

    RAISE NOTICE 'Test 21.1: after() count=0 - Result count: %', result_count;
END;
$$;

-- Test 21.2: after() with count=-1 should return no rows (early return)
DO $$
DECLARE
    result_count INT;
BEGIN
    SELECT COUNT(*) INTO result_count
    FROM rrule."after"(
        'FREQ=DAILY;COUNT=10',
        '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
        '2025-01-01 00:00:00+00'::TIMESTAMPTZ,
        -1,      -- count=-1
        'UTC',
        TRUE
    );

    INSERT INTO tz_api_test_results VALUES (
        'Edge Cases TZ',
        'after() with count=-1 returns no rows',
        result_count = 0,
        result_count::TEXT,
        '0'
    );

    RAISE NOTICE 'Test 21.2: after() count=-1 - Result count: %', result_count;
END;
$$;

-- Test 21.3: before() with count=0 should return no rows (early return)
DO $$
DECLARE
    result_count INT;
BEGIN
    SELECT COUNT(*) INTO result_count
    FROM rrule."before"(
        'FREQ=DAILY;COUNT=10',
        '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
        '2025-01-15 00:00:00+00'::TIMESTAMPTZ,
        0,       -- count=0
        'UTC',
        TRUE
    );

    INSERT INTO tz_api_test_results VALUES (
        'Edge Cases TZ',
        'before() with count=0 returns no rows',
        result_count = 0,
        result_count::TEXT,
        '0'
    );

    RAISE NOTICE 'Test 21.3: before() count=0 - Result count: %', result_count;
END;
$$;

-- Test 21.4: before() with count=-1 should return no rows (early return)
DO $$
DECLARE
    result_count INT;
BEGIN
    SELECT COUNT(*) INTO result_count
    FROM rrule."before"(
        'FREQ=DAILY;COUNT=10',
        '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
        '2025-01-15 00:00:00+00'::TIMESTAMPTZ,
        -1,      -- count=-1
        'UTC',
        TRUE
    );

    INSERT INTO tz_api_test_results VALUES (
        'Edge Cases TZ',
        'before() with count=-1 returns no rows',
        result_count = 0,
        result_count::TEXT,
        '0'
    );

    RAISE NOTICE 'Test 21.4: before() count=-1 - Result count: %', result_count;
END;
$$;

-- Test 21.5: overlaps() with NULL mindate uses COALESCE default (CURRENT_TIMESTAMP - 10 years)
-- A daily recurring event starting 2025-01-01 should overlap with a range where mindate is NULL
-- and maxdate is well after dtstart. The COALESCE sets mindate to ~10 years before now.
DO $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT rrule."overlaps"(
        '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
        '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=30',
        NULL,    -- mindate NULL → COALESCE to CURRENT_TIMESTAMP - 10 years
        '2025-02-15 00:00:00+00'::TIMESTAMPTZ,
        'UTC'
    ) INTO result;

    INSERT INTO tz_api_test_results VALUES (
        'Edge Cases TZ',
        'overlaps() with NULL mindate uses COALESCE default',
        result = TRUE,
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 21.5: overlaps() NULL mindate - Result: %', result;
END;
$$;

-- Test 21.6: overlaps() with NULL maxdate uses COALESCE default (CURRENT_TIMESTAMP + 10 years)
-- A daily recurring event starting 2025-01-01 should overlap with a range where maxdate is NULL
-- and mindate is within the event range. The COALESCE sets maxdate to ~10 years after now.
DO $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT rrule."overlaps"(
        '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
        '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=30',
        '2025-01-05 00:00:00+00'::TIMESTAMPTZ,
        NULL,    -- maxdate NULL → COALESCE to CURRENT_TIMESTAMP + 10 years
        'UTC'
    ) INTO result;

    INSERT INTO tz_api_test_results VALUES (
        'Edge Cases TZ',
        'overlaps() with NULL maxdate uses COALESCE default',
        result = TRUE,
        result::TEXT,
        'true'
    );

    RAISE NOTICE 'Test 21.6: overlaps() NULL maxdate - Result: %', result;
END;
$$;

-- Test 21.7: TZ generator truncation at 1000 results for rules without COUNT/UNTIL
-- FREQ=DAILY with no COUNT/UNTIL generates indefinitely. The TZ all() caps at 1000.
-- We verify the result count is exactly 1000 (the cap limit).
DO $$
DECLARE
    result_count INT;
BEGIN
    SELECT COUNT(*) INTO result_count
    FROM rrule."all"(
        'FREQ=DAILY',
        '2020-01-01 10:00:00+00'::TIMESTAMPTZ,
        'UTC'
    );

    INSERT INTO tz_api_test_results VALUES (
        'Edge Cases TZ',
        'TZ all() truncates at 1000 for rule without COUNT/UNTIL',
        result_count = 1000,
        result_count::TEXT,
        '1000'
    );

    RAISE NOTICE 'Test 21.7: TZ generator truncation - Result count: %', result_count;
END;
$$;

-- Test 21.8: before() sliding window trimming returns only last N occurrences
-- FREQ=DAILY;COUNT=50 starting Jan 1 produces 50 days (Jan 1 through Feb 19).
-- before() with before_date=2025-02-20, count=3, inc=TRUE should return
-- the last 3 occurrences on or before Feb 20: Feb 17, Feb 18, Feb 19.
-- This exercises the array slicing at src/rrule.sql:3249-3252.
DO $$
DECLARE
    results TIMESTAMPTZ[];
    result_count INT;
    expected TIMESTAMPTZ[];
BEGIN
    SELECT array_agg(ts ORDER BY ts), COUNT(*) INTO results, result_count
    FROM rrule."before"(
        'FREQ=DAILY;COUNT=50',
        '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
        '2025-02-20 00:00:00+00'::TIMESTAMPTZ,
        3,       -- only last 3
        'UTC',
        TRUE     -- inclusive
    ) ts;

    expected := ARRAY[
        '2025-02-17 10:00:00+00'::TIMESTAMPTZ,
        '2025-02-18 10:00:00+00'::TIMESTAMPTZ,
        '2025-02-19 10:00:00+00'::TIMESTAMPTZ
    ];

    INSERT INTO tz_api_test_results VALUES (
        'Edge Cases TZ',
        'before() sliding window returns last 3 of 50 occurrences',
        result_count = 3 AND results = expected,
        result_count::TEXT || ' results: ' || COALESCE(results::TEXT, 'NULL'),
        '3 results: ' || expected::TEXT
    );

    RAISE NOTICE 'Test 21.8: before() sliding window - Count: %, Results: %', result_count, results;
END;
$$;


-- Fail transaction if any tests failed
DO $$
DECLARE
    failure_count INT;
BEGIN
    SELECT COUNT(*) INTO failure_count FROM tz_api_test_results WHERE NOT passed;
    IF failure_count > 0 THEN
        RAISE EXCEPTION '% test(s) failed', failure_count;
    END IF;
END;
$$;

ROLLBACK;

\echo ''
\echo '=================================================='
\echo 'All tests completed successfully!'
\echo '=================================================='
