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

\i tests/helpers.sql

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
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('HOURLY Basic', 'FREQ=HOURLY;COUNT=5 produces 5 consecutive hours',
    assert_occurrences_equal(
        'FREQ=HOURLY;COUNT=5 produces 5 consecutive hours',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 11:00:00'::TIMESTAMP,
            '2025-01-01 12:00:00'::TIMESTAMP,
            '2025-01-01 13:00:00'::TIMESTAMP,
            '2025-01-01 14:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=HOURLY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 1.2: HOURLY with INTERVAL=3 (exact array comparison)
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('HOURLY Basic', 'FREQ=HOURLY;INTERVAL=3;COUNT=4 skips 2 hours each step',
    assert_occurrences_equal(
        'FREQ=HOURLY;INTERVAL=3;COUNT=4 skips 2 hours each step',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 13:00:00'::TIMESTAMP,
            '2025-01-01 16:00:00'::TIMESTAMP,
            '2025-01-01 19:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=HOURLY;INTERVAL=3;COUNT=4', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 1.3: HOURLY cross-day boundary (exact array comparison)
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('HOURLY Boundaries', 'FREQ=HOURLY;INTERVAL=6;COUNT=6 crosses midnight',
    assert_occurrences_equal(
        'FREQ=HOURLY;INTERVAL=6;COUNT=6 crosses midnight',
        ARRAY[
            '2025-01-01 20:00:00'::TIMESTAMP,
            '2025-01-02 02:00:00'::TIMESTAMP,
            '2025-01-02 08:00:00'::TIMESTAMP,
            '2025-01-02 14:00:00'::TIMESTAMP,
            '2025-01-02 20:00:00'::TIMESTAMP,
            '2025-01-03 02:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=HOURLY;INTERVAL=6;COUNT=6', '2025-01-01 20:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 1.4: HOURLY COUNT=1 produces exactly 1 result
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'HOURLY Boundaries',
    'FREQ=HOURLY;COUNT=1 produces exactly 1 result',
    assert_equals(
        'FREQ=HOURLY;COUNT=1 produces exactly 1 result',
        '1',
        COUNT(*)::TEXT
    )
FROM rrule."all"(
    'FREQ=HOURLY;COUNT=1',
    '2025-01-01 10:00:00'::TIMESTAMP
) AS occurrence;

-- Test 1.5: HOURLY with BYDAY filter produces only matching day occurrences
-- HOURLY;BYDAY=MO;INTERVAL=6 starting Monday 10:00 → 10:00, 16:00, 22:00 (3 per Monday)
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('HOURLY Filters', 'FREQ=HOURLY;BYDAY=MO;INTERVAL=6;COUNT=3 only Monday occurrences',
    assert_occurrences_equal(
        'FREQ=HOURLY;BYDAY=MO;INTERVAL=6;COUNT=3 only Monday occurrences',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-06 16:00:00'::TIMESTAMP,
            '2025-01-06 22:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=HOURLY;BYDAY=MO;INTERVAL=6;COUNT=3', '2025-01-06 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- ============================================================================
-- SECTION 2: MINUTELY Frequency Tests
-- ============================================================================
\echo ''
\echo '--- Section 2: MINUTELY Frequency ---'

-- Test 2.1: MINUTELY basic - 15-minute intervals (exact array comparison)
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('MINUTELY Basic', 'FREQ=MINUTELY;INTERVAL=15;COUNT=4 produces quarter-hour steps',
    assert_occurrences_equal(
        'FREQ=MINUTELY;INTERVAL=15;COUNT=4 produces quarter-hour steps',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:15:00'::TIMESTAMP,
            '2025-01-01 10:30:00'::TIMESTAMP,
            '2025-01-01 10:45:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=MINUTELY;INTERVAL=15;COUNT=4', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 2.2: MINUTELY cross-hour boundary (exact array comparison)
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('MINUTELY Boundaries', 'FREQ=MINUTELY;INTERVAL=20;COUNT=5 crosses hour boundary',
    assert_occurrences_equal(
        'FREQ=MINUTELY;INTERVAL=20;COUNT=5 crosses hour boundary',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:20:00'::TIMESTAMP,
            '2025-01-01 10:40:00'::TIMESTAMP,
            '2025-01-01 11:00:00'::TIMESTAMP,
            '2025-01-01 11:20:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=MINUTELY;INTERVAL=20;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 2.3: MINUTELY COUNT=1 produces exactly 1 result
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'MINUTELY Boundaries',
    'FREQ=MINUTELY;COUNT=1 produces exactly 1 result',
    assert_equals(
        'FREQ=MINUTELY;COUNT=1 produces exactly 1 result',
        '1',
        COUNT(*)::TEXT
    )
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
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('SECONDLY Basic', 'FREQ=SECONDLY;INTERVAL=30;COUNT=4 produces 30-second steps',
    assert_occurrences_equal(
        'FREQ=SECONDLY;INTERVAL=30;COUNT=4 produces 30-second steps',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:00:30'::TIMESTAMP,
            '2025-01-01 10:01:00'::TIMESTAMP,
            '2025-01-01 10:01:30'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=SECONDLY;INTERVAL=30;COUNT=4', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 3.2: SECONDLY cross-minute boundary (exact array comparison)
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('SECONDLY Boundaries', 'FREQ=SECONDLY;INTERVAL=45;COUNT=3 crosses minute boundary',
    assert_occurrences_equal(
        'FREQ=SECONDLY;INTERVAL=45;COUNT=3 crosses minute boundary',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:00:45'::TIMESTAMP,
            '2025-01-01 10:01:30'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=SECONDLY;INTERVAL=45;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 3.3: SECONDLY COUNT=1 produces exactly 1 result
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'SECONDLY Boundaries',
    'FREQ=SECONDLY;COUNT=1 produces exactly 1 result',
    assert_equals(
        'FREQ=SECONDLY;COUNT=1 produces exactly 1 result',
        '1',
        COUNT(*)::TEXT
    )
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
-- Note: assert_occurrences_equal only supports TIMESTAMP[], so TIMESTAMPTZ tests
-- use inline CASE WHEN comparison to avoid type mismatch.
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
        WHEN status LIKE 'PASS%' THEN '  PASS ' || test_name
        ELSE '  FAIL ' || test_name || ' - ' || status
    END AS result
FROM subday_test_results
ORDER BY test_category, test_id;

\echo ''
\echo 'Category Summary:'
SELECT
    test_category,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') AS passed,
    COUNT(*) FILTER (WHERE status NOT LIKE 'PASS%') AS failed
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
-- Feb FORWARD→Mar 1, Mar restores to 31st (no drift). Both within range.
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'SKIP=FORWARD Time Preservation',
    'MONTHLY SKIP=FORWARD preserves time via TIMESTAMPTZ API (subday)',
    assert_occurrences_equal(
        'MONTHLY SKIP=FORWARD preserves time via TIMESTAMPTZ API (subday)',
        ARRAY['2025-03-01 14:30:00','2025-03-31 14:30:00']::TIMESTAMP[],
        actual
    )
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
    assert_occurrences_equal(
        'YEARLY SKIP=FORWARD preserves time via TIMESTAMPTZ API (subday)',
        ARRAY['2025-03-01 09:15:00']::TIMESTAMP[],
        actual
    )
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
    assert_occurrences_equal(
        'BYHOUR=9,17 with DAILY COUNT=6',
        ARRAY['2025-01-01 09:00:00', '2025-01-01 17:00:00',
              '2025-01-02 09:00:00', '2025-01-02 17:00:00',
              '2025-01-03 09:00:00', '2025-01-03 17:00:00']::TIMESTAMP[],
        actual
    )
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
    assert_occurrences_equal(
        'BYHOUR=9 BYMINUTE=0,30 cross-product COUNT=4',
        ARRAY['2025-01-01 09:00:00', '2025-01-01 09:30:00',
              '2025-01-02 09:00:00', '2025-01-02 09:30:00']::TIMESTAMP[],
        actual
    )
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
    assert_occurrences_equal(
        'BYHOUR=9 BYMINUTE=15 BYSECOND=0,30 COUNT=4',
        ARRAY['2025-01-01 09:15:00', '2025-01-01 09:15:30',
              '2025-01-02 09:15:00', '2025-01-02 09:15:30']::TIMESTAMP[],
        actual
    )
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
    assert_true(
        'BYHOUR deduplication (9,9 same as 9)',
        deduped = non_deduped
    )
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
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('HOURLY UNTIL', 'FREQ=HOURLY;UNTIL produces correct bounded results',
    assert_occurrences_equal(
        'FREQ=HOURLY;UNTIL produces correct bounded results',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 11:00:00'::TIMESTAMP,
            '2025-01-01 12:00:00'::TIMESTAMP,
            '2025-01-01 13:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=HOURLY;UNTIL=20250101T130000Z', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 6.2: MINUTELY with UNTIL boundary
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('MINUTELY UNTIL', 'FREQ=MINUTELY;INTERVAL=15;UNTIL produces correct bounded results',
    assert_occurrences_equal(
        'FREQ=MINUTELY;INTERVAL=15;UNTIL produces correct bounded results',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:15:00'::TIMESTAMP,
            '2025-01-01 10:30:00'::TIMESTAMP,
            '2025-01-01 10:45:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=MINUTELY;INTERVAL=15;UNTIL=20250101T104500Z', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- Test 6.3: SECONDLY with UNTIL boundary
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('SECONDLY UNTIL', 'FREQ=SECONDLY;INTERVAL=30;UNTIL produces correct bounded results',
    assert_occurrences_equal(
        'FREQ=SECONDLY;INTERVAL=30;UNTIL produces correct bounded results',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:00:30'::TIMESTAMP,
            '2025-01-01 10:01:00'::TIMESTAMP,
            '2025-01-01 10:01:30'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=SECONDLY;INTERVAL=30;UNTIL=20250101T100130Z', '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence)
    )
);

-- ============================================================================
-- SECTION 7: Sub-Day between()/after() API Tests
-- ============================================================================
\echo ''
\echo '--- Section 7: Sub-Day between()/after() API ---'

-- Test 7.1: between() for HOURLY frequency
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('Sub-Day between()', 'HOURLY between() returns occurrences within range',
    assert_occurrences_equal(
        'HOURLY between() returns occurrences within range',
        ARRAY[
            '2025-01-01 12:00:00'::TIMESTAMP,
            '2025-01-01 13:00:00'::TIMESTAMP,
            '2025-01-01 14:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."between"(
             'FREQ=HOURLY;COUNT=10',
             '2025-01-01 10:00:00'::TIMESTAMP,
             '2025-01-01 11:30:00'::TIMESTAMP,
             '2025-01-01 14:30:00'::TIMESTAMP
         ) AS occurrence)
    )
);

-- Test 7.2: after() for MINUTELY frequency
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('Sub-Day after()', 'MINUTELY after() returns next occurrence after date',
    assert_equals(
        'MINUTELY after() returns next occurrence after date',
        '2025-01-01 10:15:00',
        (SELECT occurrence::TEXT
         FROM rrule."after"(
             'FREQ=MINUTELY;INTERVAL=15;COUNT=10',
             '2025-01-01 10:00:00'::TIMESTAMP,
             '2025-01-01 10:00:00'::TIMESTAMP
         ) AS occurrence)
    )
);

-- Test 7.3: between() for SECONDLY frequency with inc=true
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('Sub-Day between()', 'SECONDLY between() with inc=true includes boundaries',
    assert_occurrences_equal(
        'SECONDLY between() with inc=true includes boundaries',
        ARRAY[
            '2025-01-01 10:00:30'::TIMESTAMP,
            '2025-01-01 10:01:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."between"(
             'FREQ=SECONDLY;INTERVAL=30;COUNT=10',
             '2025-01-01 10:00:00'::TIMESTAMP,
             '2025-01-01 10:00:30'::TIMESTAMP,
             '2025-01-01 10:01:00'::TIMESTAMP,
             TRUE
         ) AS occurrence)
    )
);

-- ============================================================================
-- SECTION 8: WEEKLY TIMESTAMPTZ TZ Generator Boundary Check Regression
-- ============================================================================
\echo ''
\echo '--- Section 8: WEEKLY TZ Generator Boundary Checks ---'

-- Test 8.1: WEEKLY + BYMONTH + UNTIL via TIMESTAMPTZ API
-- Regression test: the subday TZ generator WEEKLY branch previously had EXIT WHEN
-- checks (UNTIL, maxdate) INSIDE the BYxxx filter IF block. When BYMONTH filtered
-- out an occurrence past UNTIL, the loop would not exit and would continue scanning
-- weeks indefinitely until hitting the 10-year safety cap. With the fix, EXIT WHEN
-- checks run BEFORE the filter block, so the loop terminates promptly at UNTIL.
--
-- WEEKLY on Mondays starting 2025-01-06, BYMONTH=1 limits to January only,
-- UNTIL=2025-02-28 means the rule should stop checking after February.
-- Expected: only the January Mondays (Jan 6, 13, 20, 27).
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    expected := ARRAY[
        '2025-01-06 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-13 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-20 10:00:00-05'::TIMESTAMPTZ,
        '2025-01-27 10:00:00-05'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=WEEKLY;BYMONTH=1;UNTIL=20250228T235959Z',
        '2025-01-06 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('WEEKLY TZ Boundary',
        'WEEKLY+BYMONTH+UNTIL via TIMESTAMPTZ exits at UNTIL not at safety cap',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- ============================================================================
-- SECTION 9: MONTHLY SKIP via Subday TZ Generator (TIMESTAMPTZ API)
-- ============================================================================
\echo ''
\echo '--- Section 9: MONTHLY SKIP via Subday TZ Generator ---'

-- Test 9.1: SKIP=OMIT + MONTHLY via TIMESTAMPTZ API
-- Starting Jan 31, months without day 31 are omitted.
-- Jan(31)→Feb(28,skip)→Mar(31)→Apr(30,skip)→May(31)→Jun(30,skip)→Jul(31)→Aug(31)
-- Expected: Jan 31, Mar 31, May 31, Jul 31, Aug 31
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    expected := ARRAY[
        '2025-01-31 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-31 10:00:00-04'::TIMESTAMPTZ,
        '2025-05-31 10:00:00-04'::TIMESTAMPTZ,
        '2025-07-31 10:00:00-04'::TIMESTAMPTZ,
        '2025-08-31 10:00:00-04'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=MONTHLY;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=5',
        '2025-01-31 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('MONTHLY SKIP TZ',
        'SKIP=OMIT+MONTHLY skips months without day 31 via TIMESTAMPTZ API',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 9.2: SKIP=BACKWARD + MONTHLY via TIMESTAMPTZ API
-- Starting Jan 31, short months fall back to last day.
-- Jan 31, Feb 28, Mar 31, Apr 30, May 31
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    expected := ARRAY[
        '2025-01-31 10:00:00-05'::TIMESTAMPTZ,
        '2025-02-28 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-31 10:00:00-04'::TIMESTAMPTZ,
        '2025-04-30 10:00:00-04'::TIMESTAMPTZ,
        '2025-05-31 10:00:00-04'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=MONTHLY;SKIP=BACKWARD;RSCALE=GREGORIAN;COUNT=5',
        '2025-01-31 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('MONTHLY SKIP TZ',
        'SKIP=BACKWARD+MONTHLY falls back to last day via TIMESTAMPTZ API',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 9.3: SKIP=FORWARD + MONTHLY via TIMESTAMPTZ API
-- Starting Jan 31, short months advance to 1st of next month.
-- Jan 31, Mar 1 (Feb forward), Mar 31, May 1 (Apr forward), May 31
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    expected := ARRAY[
        '2025-01-31 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-01 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-31 10:00:00-04'::TIMESTAMPTZ,
        '2025-05-01 10:00:00-04'::TIMESTAMPTZ,
        '2025-05-31 10:00:00-04'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=MONTHLY;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=5',
        '2025-01-31 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('MONTHLY SKIP TZ',
        'SKIP=FORWARD+MONTHLY advances to 1st of next month via TIMESTAMPTZ API',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 9.4: SKIP=OMIT + MONTHLY + INTERVAL=2 via TIMESTAMPTZ API
-- Starting Jan 31, INTERVAL=2: Jan→Mar→May→Jul→Sep→Nov→Jan 2026
-- Sep has 30 days (omit), Nov has 30 days (omit), Jan 2026 has 31 days.
-- Expected: Jan 31, Mar 31, May 31, Jul 31, Jan 31 2026
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    expected := ARRAY[
        '2025-01-31 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-31 10:00:00-04'::TIMESTAMPTZ,
        '2025-05-31 10:00:00-04'::TIMESTAMPTZ,
        '2025-07-31 10:00:00-04'::TIMESTAMPTZ,
        '2026-01-31 10:00:00-05'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=MONTHLY;INTERVAL=2;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=5',
        '2025-01-31 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('MONTHLY SKIP TZ',
        'SKIP=OMIT+MONTHLY+INTERVAL=2 skips short months via TIMESTAMPTZ API',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- ============================================================================
-- SECTION 10: YEARLY SKIP via Subday TZ Generator (TIMESTAMPTZ API)
-- ============================================================================
\echo ''
\echo '--- Section 10: YEARLY SKIP via Subday TZ Generator ---'

-- Test 10.1: SKIP=OMIT + YEARLY via TIMESTAMPTZ API
-- Starting Feb 29, 2024 (leap year). Non-leap years are omitted.
-- Leap years within 10-year cap (2024-2034): 2024, 2028, 2032
-- The all() function caps at 10 years from dtstart, so 2036 and 2040 are beyond range.
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    expected := ARRAY[
        '2024-02-29 10:00:00-05'::TIMESTAMPTZ,
        '2028-02-29 10:00:00-05'::TIMESTAMPTZ,
        '2032-02-29 10:00:00-05'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=YEARLY;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=5',
        '2024-02-29 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('YEARLY SKIP TZ',
        'SKIP=OMIT+YEARLY only returns leap years via TIMESTAMPTZ API (10yr cap)',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 10.2: SKIP=FORWARD + YEARLY via TIMESTAMPTZ API
-- Starting Feb 29, 2024. Non-leap years advance to Mar 1.
-- 2024: Feb 29, 2025: Mar 1, 2026: Mar 1, 2027: Mar 1, 2028: Feb 29
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    expected := ARRAY[
        '2024-02-29 10:00:00-05'::TIMESTAMPTZ,
        '2025-03-01 10:00:00-05'::TIMESTAMPTZ,
        '2026-03-01 10:00:00-05'::TIMESTAMPTZ,
        '2027-03-01 10:00:00-05'::TIMESTAMPTZ,
        '2028-02-29 10:00:00-05'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=YEARLY;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=5',
        '2024-02-29 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('YEARLY SKIP TZ',
        'SKIP=FORWARD+YEARLY advances to Mar 1 in non-leap years via TIMESTAMPTZ API',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 10.3: SKIP=BACKWARD + YEARLY via TIMESTAMPTZ API
-- Starting Feb 29, 2024. Non-leap years fall back to Feb 28.
-- 2024: Feb 29, 2025: Feb 28, 2026: Feb 28, 2027: Feb 28, 2028: Feb 29
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    expected := ARRAY[
        '2024-02-29 10:00:00-05'::TIMESTAMPTZ,
        '2025-02-28 10:00:00-05'::TIMESTAMPTZ,
        '2026-02-28 10:00:00-05'::TIMESTAMPTZ,
        '2027-02-28 10:00:00-05'::TIMESTAMPTZ,
        '2028-02-29 10:00:00-05'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=YEARLY;SKIP=BACKWARD;RSCALE=GREGORIAN;COUNT=5',
        '2024-02-29 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('YEARLY SKIP TZ',
        'SKIP=BACKWARD+YEARLY falls back to Feb 28 in non-leap years via TIMESTAMPTZ API',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

-- Test 10.4: SKIP=OMIT + YEARLY + INTERVAL=2 via TIMESTAMPTZ API
-- Starting Feb 29, 2024, INTERVAL=2: 2024→2026→2028→2030→2032→...
-- Feb 29 exists in: 2024 (yes), 2026 (no), 2028 (yes), 2030 (no), 2032 (yes)
-- The all() function caps at 10 years from dtstart (2034), so only 3 leap years are reachable.
-- Expected: Feb 29 2024, Feb 29 2028, Feb 29 2032
DO $$
DECLARE
    actual TIMESTAMPTZ[];
    expected TIMESTAMPTZ[];
BEGIN
    expected := ARRAY[
        '2024-02-29 10:00:00-05'::TIMESTAMPTZ,
        '2028-02-29 10:00:00-05'::TIMESTAMPTZ,
        '2032-02-29 10:00:00-05'::TIMESTAMPTZ
    ];

    SELECT array_agg(occurrence ORDER BY occurrence) INTO actual
    FROM rrule."all"(
        'FREQ=YEARLY;INTERVAL=2;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=5',
        '2024-02-29 10:00:00-05'::TIMESTAMPTZ,
        'America/New_York'
    ) AS occurrence;

    INSERT INTO subday_test_results (test_category, test_name, status)
    VALUES ('YEARLY SKIP TZ',
        'SKIP=OMIT+YEARLY+INTERVAL=2 skips non-leap years via TIMESTAMPTZ API (10yr cap)',
        CASE WHEN actual = expected THEN 'PASS'
        ELSE 'FAIL - Expected: ' || expected::TEXT || ', Got: ' || COALESCE(actual::TEXT, 'NULL') END);
END;
$$;

\echo ''
\echo 'Overall Summary:'
SELECT
    COUNT(*) AS total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') AS passed,
    COUNT(*) FILTER (WHERE status NOT LIKE 'PASS%') AS failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status LIKE 'PASS%') / COUNT(*), 1) || '%' AS pass_rate
FROM subday_test_results;

-- Fail if any tests failed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count FROM subday_test_results WHERE status NOT LIKE 'PASS%';
    IF failed_count > 0 THEN
        RAISE EXCEPTION 'SUB-DAY TESTS FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'SUB-DAY TESTS PASSED: All tests passed!';
    END IF;
END $$;

-- ============================================================================
-- SECTION 11: TIMESTAMP Generator Type Declaration Regression Test
-- Verifies the subday TIMESTAMP generator works after normalizing
-- its variable declaration to use %ROWTYPE + SELECT * INTO (Finding #5).
-- ============================================================================
\echo ''
\echo '--- Section 11: TIMESTAMP Generator Type Declaration Regression ---'

-- Test 11.1: Simple HOURLY rule through TIMESTAMP API (subday generator)
INSERT INTO subday_test_results (test_category, test_name, status)
VALUES ('TIMESTAMP Generator', 'HOURLY;INTERVAL=2;COUNT=4 via TIMESTAMP API after %ROWTYPE normalization',
    assert_occurrences_equal(
        'HOURLY;INTERVAL=2;COUNT=4 via TIMESTAMP API after %ROWTYPE normalization',
        ARRAY[
            '2025-06-15 08:00:00'::TIMESTAMP,
            '2025-06-15 10:00:00'::TIMESTAMP,
            '2025-06-15 12:00:00'::TIMESTAMP,
            '2025-06-15 14:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=HOURLY;INTERVAL=2;COUNT=4', '2025-06-15 08:00:00'::TIMESTAMP) AS occurrence)
    )
);

\echo ''
\echo 'Overall Summary (with Section 11):'
SELECT
    COUNT(*) AS total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') AS passed,
    COUNT(*) FILTER (WHERE status NOT LIKE 'PASS%') AS failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status LIKE 'PASS%') / COUNT(*), 1) || '%' AS pass_rate
FROM subday_test_results;


-- ============================================================================
-- SECTION 12: Issue 15+16 — Subday generator guards and negative BYMONTHDAY
-- ============================================================================
\echo ''
\echo '--- Section 12: Issue 15 (bymonthday/bymonth guards) + Issue 16 (negative BYMONTHDAY) ---'

-- Test Issue 16: BYMONTHDAY=-1 with HOURLY (negative values)
-- BYMONTHDAY=-1 means last day of month. Previously the naive date_part check rejected negatives.
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'Issue 16: Negative BYMONTHDAY',
    'HOURLY + BYMONTHDAY=-1 returns last day of month',
    assert_occurrences_equal(
        'HOURLY BYMONTHDAY=-1',
        ARRAY[
            '2025-01-31 09:00:00'::TIMESTAMP,
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-01-31 11:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=HOURLY;BYMONTHDAY=-1;COUNT=3', '2025-01-31 09:00:00'::TIMESTAMP) AS occurrence)
    );

-- Test Issue 16: BYMONTHDAY=-1 with MINUTELY
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'Issue 16: Negative BYMONTHDAY',
    'MINUTELY + BYMONTHDAY=-1 returns last day of month',
    assert_occurrences_equal(
        'MINUTELY BYMONTHDAY=-1',
        ARRAY[
            '2025-01-31 09:00:00'::TIMESTAMP,
            '2025-01-31 09:01:00'::TIMESTAMP,
            '2025-01-31 09:02:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=MINUTELY;BYMONTHDAY=-1;COUNT=3', '2025-01-31 09:00:00'::TIMESTAMP) AS occurrence)
    );

-- Test Issue 16: BYMONTHDAY=-1 with SECONDLY
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'Issue 16: Negative BYMONTHDAY',
    'SECONDLY + BYMONTHDAY=-1 returns last day of month',
    assert_occurrences_equal(
        'SECONDLY BYMONTHDAY=-1',
        ARRAY[
            '2025-01-31 09:00:00'::TIMESTAMP,
            '2025-01-31 09:00:01'::TIMESTAMP,
            '2025-01-31 09:00:02'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=SECONDLY;BYMONTHDAY=-1;COUNT=3', '2025-01-31 09:00:00'::TIMESTAMP) AS occurrence)
    );

-- Test Issue 15: HOURLY + BYMONTH filter (guard ensures enough candidates)
INSERT INTO subday_test_results (test_category, test_name, status)
SELECT
    'Issue 15: BYMONTH guard',
    'HOURLY + BYMONTH=1 returns only January hours',
    assert_equals(
        'HOURLY BYMONTH=1 count',
        '3',
        (SELECT COUNT(*)::TEXT
         FROM rrule."all"('FREQ=HOURLY;BYMONTH=1;COUNT=3', '2025-01-31 22:00:00'::TIMESTAMP) AS occurrence)
    );

ROLLBACK;
