/**
 * Sub-Day Frequency Correctness Tests
 *
 * Tests HOURLY, MINUTELY, and SECONDLY frequencies which use separate code paths
 * (hourly_set, minutely_set, secondly_set) from the standard DAILY/WEEKLY/MONTHLY/YEARLY.
 *
 * These frequencies are disabled by default for security (DoS risk). This file must be
 * run with install_with_subday.sql to enable them.
 *
 * Usage:
 *   psql -d your_database -v rrule_install=src/install_with_subday.sql \
 *     -f tests/test_subday_correctness.sql
 *
 * Expected output: All tests pass with PASS status
 */

\set ON_ERROR_STOP on
\set ECHO all

-- Ensure we're testing in UTC timezone for consistency
SET timezone = 'UTC';

-- Install RRULE functions with sub-day support
\if :{?rrule_install}
\i :rrule_install
\else
DROP SCHEMA IF EXISTS rrule CASCADE;
CREATE SCHEMA IF NOT EXISTS rrule;
\i src/install_with_subday.sql
\endif

-- Ensure tests do not rely on search_path
SET search_path = public;

BEGIN;

-- Test results table
CREATE TEMP TABLE subday_test_results (
    test_id SERIAL PRIMARY KEY,
    test_category TEXT,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '==================================================================='
\echo 'SUB-DAY FREQUENCY CORRECTNESS TESTS'
\echo '==================================================================='
\echo ''

-- ============================================================================
-- SECTION 1: HOURLY Frequency Tests
-- ============================================================================
\echo '--- Section 1: HOURLY Frequency ---'

-- Test 1.1: HOURLY basic - 5 consecutive hours (exact array comparison)
DO $$
DECLARE
    actual TIMESTAMP[];
    expected TIMESTAMP[] := ARRAY[
        '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 11:00:00'::TIMESTAMP,
        '2025-01-01 12:00:00'::TIMESTAMP,
        '2025-01-01 13:00:00'::TIMESTAMP,
        '2025-01-01 14:00:00'::TIMESTAMP
    ];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"('FREQ=HOURLY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('HOURLY Basic', 'FREQ=HOURLY;COUNT=5 produces 5 consecutive hours',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || actual::TEXT END);
END;
$$;

-- Test 1.2: HOURLY with INTERVAL=3 (exact array comparison)
DO $$
DECLARE
    actual TIMESTAMP[];
    expected TIMESTAMP[] := ARRAY[
        '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 13:00:00'::TIMESTAMP,
        '2025-01-01 16:00:00'::TIMESTAMP,
        '2025-01-01 19:00:00'::TIMESTAMP
    ];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"('FREQ=HOURLY;INTERVAL=3;COUNT=4', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('HOURLY Basic', 'FREQ=HOURLY;INTERVAL=3;COUNT=4 skips 2 hours each step',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || actual::TEXT END);
END;
$$;

-- Test 1.3: HOURLY cross-day boundary (exact array comparison)
DO $$
DECLARE
    actual TIMESTAMP[];
    expected TIMESTAMP[] := ARRAY[
        '2025-01-01 20:00:00'::TIMESTAMP,
        '2025-01-02 02:00:00'::TIMESTAMP,
        '2025-01-02 08:00:00'::TIMESTAMP,
        '2025-01-02 14:00:00'::TIMESTAMP,
        '2025-01-02 20:00:00'::TIMESTAMP,
        '2025-01-03 02:00:00'::TIMESTAMP
    ];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"('FREQ=HOURLY;INTERVAL=6;COUNT=6', '2025-01-01 20:00:00'::TIMESTAMP) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('HOURLY Boundaries', 'FREQ=HOURLY;INTERVAL=6;COUNT=6 crosses midnight',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || actual::TEXT END);
END;
$$;

-- Test 1.4: HOURLY COUNT=1 produces exactly 1 result
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'HOURLY Boundaries',
    'FREQ=HOURLY;COUNT=1 produces exactly 1 result',
    CASE WHEN COUNT(*) = 1 THEN 'PASS'
    ELSE 'FAIL - Expected: 1, Got: ' || COUNT(*)::TEXT END
FROM rrule."all"(
    'FREQ=HOURLY;COUNT=1',
    '2025-01-01 10:00:00'::TIMESTAMP
) AS occurrence;

-- Test 1.5: HOURLY with BYDAY filter produces only matching day occurrences
-- HOURLY;BYDAY=MO;INTERVAL=6 starting Monday 10:00 → 10:00, 16:00, 22:00 (3 per Monday)
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'HOURLY Filters',
    'FREQ=HOURLY;BYDAY=MO;INTERVAL=6;COUNT=3 only Monday occurrences',
    CASE WHEN COUNT(*) = 3 AND COUNT(*) = COUNT(*) FILTER (WHERE EXTRACT(DOW FROM occurrence) = 1)
    THEN 'PASS'
    ELSE 'FAIL - Expected 3 Monday occurrences, got ' || COUNT(*)::TEXT || ' total, ' || COUNT(*) FILTER (WHERE EXTRACT(DOW FROM occurrence) = 1)::TEXT || ' Mondays' END
FROM rrule."all"(
    'FREQ=HOURLY;BYDAY=MO;INTERVAL=6;COUNT=3',
    '2025-01-06 10:00:00'::TIMESTAMP  -- Monday
) AS occurrence;

-- ============================================================================
-- SECTION 2: MINUTELY Frequency Tests
-- ============================================================================
\echo ''
\echo '--- Section 2: MINUTELY Frequency ---'

-- Test 2.1: MINUTELY basic - 15-minute intervals (exact array comparison)
DO $$
DECLARE
    actual TIMESTAMP[];
    expected TIMESTAMP[] := ARRAY[
        '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:15:00'::TIMESTAMP,
        '2025-01-01 10:30:00'::TIMESTAMP,
        '2025-01-01 10:45:00'::TIMESTAMP
    ];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"('FREQ=MINUTELY;INTERVAL=15;COUNT=4', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('MINUTELY Basic', 'FREQ=MINUTELY;INTERVAL=15;COUNT=4 produces quarter-hour steps',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || actual::TEXT END);
END;
$$;

-- Test 2.2: MINUTELY cross-hour boundary (exact array comparison)
DO $$
DECLARE
    actual TIMESTAMP[];
    expected TIMESTAMP[] := ARRAY[
        '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:20:00'::TIMESTAMP,
        '2025-01-01 10:40:00'::TIMESTAMP,
        '2025-01-01 11:00:00'::TIMESTAMP,
        '2025-01-01 11:20:00'::TIMESTAMP
    ];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"('FREQ=MINUTELY;INTERVAL=20;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('MINUTELY Boundaries', 'FREQ=MINUTELY;INTERVAL=20;COUNT=5 crosses hour boundary',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || actual::TEXT END);
END;
$$;

-- Test 2.3: MINUTELY COUNT=1 produces exactly 1 result
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'MINUTELY Boundaries',
    'FREQ=MINUTELY;COUNT=1 produces exactly 1 result',
    CASE WHEN COUNT(*) = 1 THEN 'PASS'
    ELSE 'FAIL - Expected: 1, Got: ' || COUNT(*)::TEXT END
FROM rrule."all"(
    'FREQ=MINUTELY;COUNT=1',
    '2025-01-01 10:00:00'::TIMESTAMP
) AS occurrence;

-- ============================================================================
-- SECTION 3: SECONDLY Frequency Tests
-- ============================================================================
\echo ''
\echo '--- Section 3: SECONDLY Frequency ---'

-- Test 3.1: SECONDLY basic - 30-second intervals (exact array comparison)
DO $$
DECLARE
    actual TIMESTAMP[];
    expected TIMESTAMP[] := ARRAY[
        '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:00:30'::TIMESTAMP,
        '2025-01-01 10:01:00'::TIMESTAMP,
        '2025-01-01 10:01:30'::TIMESTAMP
    ];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"('FREQ=SECONDLY;INTERVAL=30;COUNT=4', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('SECONDLY Basic', 'FREQ=SECONDLY;INTERVAL=30;COUNT=4 produces 30-second steps',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || actual::TEXT END);
END;
$$;

-- Test 3.2: SECONDLY cross-minute boundary (exact array comparison)
DO $$
DECLARE
    actual TIMESTAMP[];
    expected TIMESTAMP[] := ARRAY[
        '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:00:45'::TIMESTAMP,
        '2025-01-01 10:01:30'::TIMESTAMP
    ];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"('FREQ=SECONDLY;INTERVAL=45;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('SECONDLY Boundaries', 'FREQ=SECONDLY;INTERVAL=45;COUNT=3 crosses minute boundary',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || actual::TEXT END);
END;
$$;

-- Test 3.3: SECONDLY COUNT=1 produces exactly 1 result
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'SECONDLY Boundaries',
    'FREQ=SECONDLY;COUNT=1 produces exactly 1 result',
    CASE WHEN COUNT(*) = 1 THEN 'PASS'
    ELSE 'FAIL - Expected: 1, Got: ' || COUNT(*)::TEXT END
FROM rrule."all"(
    'FREQ=SECONDLY;COUNT=1',
    '2025-01-01 10:00:00'::TIMESTAMP
) AS occurrence;

-- ============================================================================
-- SECTION 4: TIMESTAMPTZ API Sub-Day Tests (timezone-aware)
-- ============================================================================
\echo ''
\echo '--- Section 4: TIMESTAMPTZ API Sub-Day Frequencies ---'

-- Test 4.1: HOURLY via TIMESTAMPTZ API with explicit timezone
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    -- 3 hourly occurrences in America/New_York
    expected := ARRAY[
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-01 11:00:00-05'::TIMESTAMPTZ,
        '2025-01-01 12:00:00-05'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=HOURLY;COUNT=3',
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('TIMESTAMPTZ HOURLY', 'HOURLY via TIMESTAMPTZ API with timezone',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 4.2: MINUTELY via TIMESTAMPTZ API
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    expected := ARRAY[
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-01 10:15:00-05'::TIMESTAMPTZ,
        '2025-01-01 10:30:00-05'::TIMESTAMPTZ,
        '2025-01-01 10:45:00-05'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=MINUTELY;INTERVAL=15;COUNT=4',
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('TIMESTAMPTZ MINUTELY', 'MINUTELY;INTERVAL=15 via TIMESTAMPTZ API',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 4.3: SECONDLY via TIMESTAMPTZ API
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    expected := ARRAY[
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-01 10:00:30-05'::TIMESTAMPTZ,
        '2025-01-01 10:01:00-05'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=SECONDLY;INTERVAL=30;COUNT=3',
        '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('TIMESTAMPTZ SECONDLY', 'SECONDLY;INTERVAL=30 via TIMESTAMPTZ API',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 4.4: HOURLY across DST spring-forward (America/New_York 2025-03-09 02:00 AM)
-- The TZ generator uses naive TIMESTAMP arithmetic which preserves wall-clock hours.
-- At spring-forward, the naive 02:00 maps to 03:00 EDT in wall-clock, producing a
-- duplicate with the next occurrence at 03:00.
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    -- Starting at 2025-03-09 00:00 EST, 4 hourly occurrences:
    -- 00:00 EST, 01:00 EST, 02:00 (gap) → 03:00 EDT, 03:00 EDT
    expected := ARRAY[
        '2025-03-09 05:00:00+00'::TIMESTAMPTZ,
        '2025-03-09 06:00:00+00'::TIMESTAMPTZ,
        '2025-03-09 07:00:00+00'::TIMESTAMPTZ,
        '2025-03-09 07:00:00+00'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=HOURLY;COUNT=4',
        '2025-03-09 00:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('TIMESTAMPTZ DST', 'HOURLY across DST spring-forward (known gap-time duplicate)',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- ============================================================================
-- SECTION 5: HOURLY Across DST Fall-Back (November 2, 2025)
-- ============================================================================
\echo ''
\echo '--- Section 5: HOURLY Across DST Fall-Back ---'

-- Test 5.1: HOURLY across November 2 fall-back (EST/EDT transition)
-- At 2:00 AM EDT, clocks fall back to 1:00 AM EST (America/New_York).
-- The TZ generator uses naive TIMESTAMP arithmetic (wall-clock hours).
-- Starting at 23:00 EDT, naive hours go: 23:00, 00:00, 01:00, 02:00, 03:00.
-- After fall-back, 01:00 maps to EST (UTC-5), so 01:00 EST = 06:00 UTC.
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
    result_count INT;
BEGIN
    -- Starting at 2025-11-01 23:00 EDT (03:00 UTC next day), 5 hourly occurrences:
    -- 23:00 EDT = 03:00 UTC, 00:00 = 04:00 UTC, 01:00 EST = 06:00 UTC,
    -- 02:00 EST = 07:00 UTC, 03:00 EST = 08:00 UTC
    expected := ARRAY[
        '2025-11-02 03:00:00+00'::TIMESTAMPTZ,
        '2025-11-02 04:00:00+00'::TIMESTAMPTZ,
        '2025-11-02 06:00:00+00'::TIMESTAMPTZ,
        '2025-11-02 07:00:00+00'::TIMESTAMPTZ,
        '2025-11-02 08:00:00+00'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence), COUNT(*)
    INTO actual, result_count
    FROM rrule."all"(
        'FREQ=HOURLY;COUNT=5',
        '2025-11-01 23:00:00-04'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('HOURLY DST Fall-Back',
        'HOURLY across November 2 fall-back preserves wall-clock hours',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- ============================================================================
-- TEST RESULTS SUMMARY
-- ============================================================================
\echo ''
\echo '==================================================================='
\echo 'TEST RESULTS SUMMARY'
\echo '==================================================================='
\echo ''

SELECT
    test_category,
    test_name,
    CASE
        WHEN status = 'PASS' THEN '  PASS ' || test_name
        ELSE '  FAIL ' || test_name || ' - ' || status
    END AS result
FROM subday_test_results
ORDER BY test_category, test_id;

\echo ''
\echo 'Category Summary:'
SELECT
    test_category,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status = 'PASS') AS passed,
    COUNT(*) FILTER (WHERE status != 'PASS') AS failed
FROM subday_test_results
GROUP BY test_category
ORDER BY test_category;

-- ================================================================================================================
-- SKIP=FORWARD TIME PRESERVATION TESTS (Sub-day install TZ generator)
-- ================================================================================================================

\echo ''
\echo '=================================================='
\echo 'Testing SKIP=FORWARD time preservation (sub-day TZ generator)'
\echo '=================================================='

-- MONTHLY SKIP=FORWARD with non-midnight dtstart should preserve time component
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'SKIP=FORWARD Time Preservation',
    'MONTHLY SKIP=FORWARD preserves time via TIMESTAMPTZ API (subday)',
    CASE WHEN actual = ARRAY['2025-03-01 14:30:00']::TIMESTAMP[]
         THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT array_agg(d ORDER BY d) AS actual
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
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'SKIP=FORWARD Time Preservation',
    'YEARLY SKIP=FORWARD preserves time via TIMESTAMPTZ API (subday)',
    CASE WHEN actual = ARRAY['2025-03-01 09:15:00']::TIMESTAMP[]
         THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT array_agg(d ORDER BY d) AS actual
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

-- ============================================================================
-- SECTION: rrule_day_time_set() Functional Tests
-- ============================================================================
\echo ''
\echo '--- rrule_day_time_set() Functional Tests ---'

-- Test: BYHOUR=9,17 produces correct hours
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'rrule_day_time_set()',
    'BYHOUR=9,17 with DAILY COUNT=6',
    CASE WHEN actual = ARRAY['2025-01-01 09:00:00', '2025-01-01 17:00:00',
                              '2025-01-02 09:00:00', '2025-01-02 17:00:00',
                              '2025-01-03 09:00:00', '2025-01-03 17:00:00']::TIMESTAMP[]
         THEN 'PASS' ELSE 'FAIL: got ' || actual::TEXT END
FROM (
    SELECT array_agg(d ORDER BY d) AS actual
    FROM rrule."all"(
        'FREQ=DAILY;BYHOUR=9,17;COUNT=6',
        '2025-01-01 00:00:00'::TIMESTAMP
    ) d
) sub;

-- Test: BYHOUR+BYMINUTE cross-product
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'rrule_day_time_set()',
    'BYHOUR=9 BYMINUTE=0,30 cross-product COUNT=4',
    CASE WHEN actual = ARRAY['2025-01-01 09:00:00', '2025-01-01 09:30:00',
                              '2025-01-02 09:00:00', '2025-01-02 09:30:00']::TIMESTAMP[]
         THEN 'PASS' ELSE 'FAIL: got ' || actual::TEXT END
FROM (
    SELECT array_agg(d ORDER BY d) AS actual
    FROM rrule."all"(
        'FREQ=DAILY;BYHOUR=9;BYMINUTE=0,30;COUNT=4',
        '2025-01-01 00:00:00'::TIMESTAMP
    ) d
) sub;

-- Test: All three levels (BYHOUR+BYMINUTE+BYSECOND)
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'rrule_day_time_set()',
    'BYHOUR=9 BYMINUTE=15 BYSECOND=0,30 COUNT=4',
    CASE WHEN actual = ARRAY['2025-01-01 09:15:00', '2025-01-01 09:15:30',
                              '2025-01-02 09:15:00', '2025-01-02 09:15:30']::TIMESTAMP[]
         THEN 'PASS' ELSE 'FAIL: got ' || actual::TEXT END
FROM (
    SELECT array_agg(d ORDER BY d) AS actual
    FROM rrule."all"(
        'FREQ=DAILY;BYHOUR=9;BYMINUTE=15;BYSECOND=0,30;COUNT=4',
        '2025-01-01 00:00:00'::TIMESTAMP
    ) d
) sub;

-- Test: Deduplication (BYHOUR=9,9 produces same as BYHOUR=9)
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'rrule_day_time_set()',
    'BYHOUR deduplication (9,9 same as 9)',
    CASE WHEN deduped = non_deduped
         THEN 'PASS' ELSE 'FAIL: deduped=' || deduped::TEXT || ' vs non_deduped=' || non_deduped::TEXT END
FROM (
    SELECT
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"('FREQ=DAILY;BYHOUR=9,9;COUNT=2', '2025-01-01 00:00:00'::TIMESTAMP) d) AS deduped,
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"('FREQ=DAILY;BYHOUR=9;COUNT=2', '2025-01-01 00:00:00'::TIMESTAMP) d) AS non_deduped
) sub;

-- ============================================================================
-- SECTION 6: UNTIL-based Sub-Day Tests
-- ============================================================================
\echo ''
\echo '--- Section 6: UNTIL-based Sub-Day Frequencies ---'

-- Test 6.1: HOURLY with UNTIL boundary
DO $$
DECLARE
    actual TIMESTAMP[];
    expected TIMESTAMP[] := ARRAY[
        '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 11:00:00'::TIMESTAMP,
        '2025-01-01 12:00:00'::TIMESTAMP,
        '2025-01-01 13:00:00'::TIMESTAMP
    ];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"('FREQ=HOURLY;UNTIL=20250101T130000Z', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('HOURLY UNTIL', 'FREQ=HOURLY;UNTIL produces correct bounded results',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 6.2: MINUTELY with UNTIL boundary
DO $$
DECLARE
    actual TIMESTAMP[];
    expected TIMESTAMP[] := ARRAY[
        '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:15:00'::TIMESTAMP,
        '2025-01-01 10:30:00'::TIMESTAMP,
        '2025-01-01 10:45:00'::TIMESTAMP
    ];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"('FREQ=MINUTELY;INTERVAL=15;UNTIL=20250101T104500Z', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('MINUTELY UNTIL', 'FREQ=MINUTELY;INTERVAL=15;UNTIL produces correct bounded results',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 6.3: SECONDLY with UNTIL boundary
DO $$
DECLARE
    actual TIMESTAMP[];
    expected TIMESTAMP[] := ARRAY[
        '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:00:30'::TIMESTAMP,
        '2025-01-01 10:01:00'::TIMESTAMP,
        '2025-01-01 10:01:30'::TIMESTAMP
    ];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"('FREQ=SECONDLY;INTERVAL=30;UNTIL=20250101T100130Z', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('SECONDLY UNTIL', 'FREQ=SECONDLY;INTERVAL=30;UNTIL produces correct bounded results',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- ============================================================================
-- SECTION 7: Sub-Day between()/after() API Tests
-- ============================================================================
\echo ''
\echo '--- Section 7: Sub-Day between()/after() API ---'

-- Test 7.1: between() for HOURLY frequency
DO $$
DECLARE
    actual TIMESTAMP[];
    expected TIMESTAMP[] := ARRAY[
        '2025-01-01 12:00:00'::TIMESTAMP,
        '2025-01-01 13:00:00'::TIMESTAMP,
        '2025-01-01 14:00:00'::TIMESTAMP
    ];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."between"(
        'FREQ=HOURLY;COUNT=10',
        '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 11:30:00'::TIMESTAMP,
        '2025-01-01 14:30:00'::TIMESTAMP
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('Sub-Day between()', 'HOURLY between() returns occurrences within range',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 7.2: after() for MINUTELY frequency
DO $$
DECLARE
    actual TIMESTAMP;
    expected TIMESTAMP := '2025-01-01 10:15:00'::TIMESTAMP;
BEGIN
    SELECT occurrence INTO actual
    FROM rrule."after"(
        'FREQ=MINUTELY;INTERVAL=15;COUNT=10',
        '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:00:00'::TIMESTAMP
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('Sub-Day after()', 'MINUTELY after() returns next occurrence after date',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 7.3: between() for SECONDLY frequency with inc=true
DO $$
DECLARE
    actual TIMESTAMP[];
    expected TIMESTAMP[] := ARRAY[
        '2025-01-01 10:00:30'::TIMESTAMP,
        '2025-01-01 10:01:00'::TIMESTAMP
    ];
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."between"(
        'FREQ=SECONDLY;INTERVAL=30;COUNT=10',
        '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:00:30'::TIMESTAMP,
        '2025-01-01 10:01:00'::TIMESTAMP,
        TRUE
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('Sub-Day between()', 'SECONDLY between() with inc=true includes boundaries',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

\echo ''
\echo 'Overall Summary:'
SELECT
    COUNT(*) AS total_tests,
    COUNT(*) FILTER (WHERE status = 'PASS') AS passed,
    COUNT(*) FILTER (WHERE status != 'PASS') AS failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'PASS') / COUNT(*), 1) || '%' AS pass_rate
FROM subday_test_results;

-- Fail if any tests failed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count FROM subday_test_results WHERE status != 'PASS';
    IF failed_count > 0 THEN
        RAISE EXCEPTION 'SUB-DAY TESTS FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'SUB-DAY TESTS PASSED: All tests passed!';
    END IF;
END $$;

ROLLBACK;
