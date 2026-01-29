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
-- HOURLY;BYDAY=MO;INTERVAL=6 starting Monday 10:00 → 10:00, 16:00, 22:00 (all Monday)
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'HOURLY Filters',
    'FREQ=HOURLY;BYDAY=MO;INTERVAL=6;COUNT=4 only Monday occurrences',
    CASE WHEN COUNT(*) = COUNT(*) FILTER (WHERE EXTRACT(DOW FROM occurrence) = 1)
    THEN 'PASS'
    ELSE 'FAIL - Non-Monday occurrences found' END
FROM rrule."all"(
    'FREQ=HOURLY;BYDAY=MO;INTERVAL=6;COUNT=4',
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
