/**
 * Comprehensive TZID (Timezone) Support Tests for rrule_plpgsql
 *
 * These tests verify that TZID parameter handling works correctly,
 * including DST transitions, multiple timezones, and edge cases.
 *
 * Test categories:
 * 1. Basic TZID functionality (no DST)
 * 2. DST transitions (Spring forward - lose an hour)
 * 3. DST transitions (Fall back - gain an hour)
 * 4. Multiple timezones (America, Europe, Asia, Australia)
 * 5. Edge cases (invalid TZID, missing TZID, legacy behavior)
 * 6. TZID with all frequency types
 * 7. TZID with complex RRULE patterns
 *
 * Usage:
 *   psql -d your_database -f test_tzid_support.sql
 *
 * Expected output: All tests should pass with "PASS" markers
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

CREATE TEMP TABLE tzid_test_results (
    test_number SERIAL PRIMARY KEY,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 1: Basic TZID Functionality'
\echo '==================================================================='

-- Test 1: TZID without DST transition (America/New_York in summer)
INSERT INTO tzid_test_results (test_name, status)
VALUES ('TZID America/New_York (no DST)',
    assert_occurrences_equal(
        'TZID America/New_York (no DST)',
        ARRAY[
            '2025-06-01 10:00:00'::TIMESTAMP,
            '2025-06-02 10:00:00'::TIMESTAMP,
            '2025-06-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;TZID=America/New_York',
            '2025-06-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 2: TZID Europe/London (no DST in winter)
INSERT INTO tzid_test_results (test_name, status)
VALUES ('TZID Europe/London (no DST)',
    assert_occurrences_equal(
        'TZID Europe/London (no DST)',
        ARRAY[
            '2025-12-01 14:00:00'::TIMESTAMP,
            '2025-12-02 14:00:00'::TIMESTAMP,
            '2025-12-03 14:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;TZID=Europe/London',
            '2025-12-01 14:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 3: TZID Asia/Tokyo (no DST ever)
INSERT INTO tzid_test_results (test_name, status)
VALUES ('TZID Asia/Tokyo (no DST)',
    assert_occurrences_equal(
        'TZID Asia/Tokyo (no DST)',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,
            '2025-01-02 09:00:00'::TIMESTAMP,
            '2025-01-03 09:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;TZID=Asia/Tokyo',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 2: DST Transitions - Spring Forward (Lose Hour)'
\echo '==================================================================='

-- Test 4: America/New_York DST Spring Forward 2025 (March 9, 2:00 AM → 3:00 AM)
-- Daily occurrences at 10:00 AM should remain at 10:00 AM wall-clock time
INSERT INTO tzid_test_results (test_name, status)
VALUES ('DST Spring Forward - America/New_York Daily',
    assert_occurrences_equal(
        'DST Spring Forward - America/New_York Daily',
        ARRAY[
            '2025-03-08 10:00:00'::TIMESTAMP,  -- Saturday, before DST (EST = UTC-5)
            '2025-03-09 10:00:00'::TIMESTAMP,  -- Sunday, DST starts at 2am (EDT = UTC-4)
            '2025-03-10 10:00:00'::TIMESTAMP   -- Monday, after DST (EDT = UTC-4)
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;TZID=America/New_York',
            '2025-03-08 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 5: Europe/London DST Spring Forward 2025 (March 30, 1:00 AM → 2:00 AM)
INSERT INTO tzid_test_results (test_name, status)
VALUES ('DST Spring Forward - Europe/London Daily',
    assert_occurrences_equal(
        'DST Spring Forward - Europe/London Daily',
        ARRAY[
            '2025-03-29 09:00:00'::TIMESTAMP,  -- Saturday, before DST (GMT = UTC+0)
            '2025-03-30 09:00:00'::TIMESTAMP,  -- Sunday, DST starts at 1am (BST = UTC+1)
            '2025-03-31 09:00:00'::TIMESTAMP   -- Monday, after DST (BST = UTC+1)
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;TZID=Europe/London',
            '2025-03-29 09:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 6: Weekly recurrence across DST transition
INSERT INTO tzid_test_results (test_name, status)
VALUES ('DST Spring Forward - Weekly recurrence',
    assert_occurrences_equal(
        'DST Spring Forward - Weekly recurrence',
        ARRAY[
            '2025-03-03 10:00:00'::TIMESTAMP,  -- Monday before DST
            '2025-03-10 10:00:00'::TIMESTAMP   -- Monday after DST (still 10 AM)
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=2;BYDAY=MO;TZID=America/New_York',
            '2025-03-03 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 3: DST Transitions - Fall Back (Gain Hour)'
\echo '==================================================================='

-- Test 7: America/New_York DST Fall Back 2025 (November 2, 2:00 AM → 1:00 AM)
-- Daily occurrences at 10:00 AM should remain at 10:00 AM wall-clock time
INSERT INTO tzid_test_results (test_name, status)
VALUES ('DST Fall Back - America/New_York Daily',
    assert_occurrences_equal(
        'DST Fall Back - America/New_York Daily',
        ARRAY[
            '2025-11-01 10:00:00'::TIMESTAMP,  -- Saturday, before DST ends (EDT = UTC-4)
            '2025-11-02 10:00:00'::TIMESTAMP,  -- Sunday, DST ends at 2am (EST = UTC-5)
            '2025-11-03 10:00:00'::TIMESTAMP   -- Monday, after DST ends (EST = UTC-5)
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;TZID=America/New_York',
            '2025-11-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 8: Europe/London DST Fall Back 2025 (October 26, 2:00 AM → 1:00 AM)
INSERT INTO tzid_test_results (test_name, status)
VALUES ('DST Fall Back - Europe/London Daily',
    assert_occurrences_equal(
        'DST Fall Back - Europe/London Daily',
        ARRAY[
            '2025-10-25 09:00:00'::TIMESTAMP,  -- Saturday, before DST ends (BST = UTC+1)
            '2025-10-26 09:00:00'::TIMESTAMP,  -- Sunday, DST ends at 2am (GMT = UTC+0)
            '2025-10-27 09:00:00'::TIMESTAMP   -- Monday, after DST ends (GMT = UTC+0)
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;TZID=Europe/London',
            '2025-10-25 09:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 4: Multiple Timezones'
\echo '==================================================================='

-- Test 9: Australia/Sydney (Southern Hemisphere - DST in Oct-Apr)
INSERT INTO tzid_test_results (test_name, status)
VALUES ('TZID Australia/Sydney',
    assert_occurrences_equal(
        'TZID Australia/Sydney',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;TZID=Australia/Sydney',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 10: America/Los_Angeles (PST/PDT - 3 hours behind NY)
INSERT INTO tzid_test_results (test_name, status)
VALUES ('TZID America/Los_Angeles',
    assert_occurrences_equal(
        'TZID America/Los_Angeles',
        ARRAY[
            '2025-06-15 09:00:00'::TIMESTAMP,
            '2025-06-16 09:00:00'::TIMESTAMP,
            '2025-06-17 09:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;TZID=America/Los_Angeles',
            '2025-06-15 09:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 11: Asia/Kolkata (IST = UTC+5:30, no DST, half-hour offset)
INSERT INTO tzid_test_results (test_name, status)
VALUES ('TZID Asia/Kolkata (half-hour offset)',
    assert_occurrences_equal(
        'TZID Asia/Kolkata (half-hour offset)',
        ARRAY[
            '2025-01-01 10:30:00'::TIMESTAMP,
            '2025-01-02 10:30:00'::TIMESTAMP,
            '2025-01-03 10:30:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;TZID=Asia/Kolkata',
            '2025-01-01 10:30:00'::TIMESTAMP
        ) AS occurrence
    )
));

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 5: Edge Cases'
\echo '==================================================================='

-- Test 12: No TZID (legacy behavior - should work as UTC)
INSERT INTO tzid_test_results (test_name, status)
VALUES ('No TZID (legacy UTC behavior)',
    assert_occurrences_equal(
        'No TZID (legacy UTC behavior)',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 12a: Session timezone should not affect TIMESTAMP API results
SET timezone = 'America/Los_Angeles';
INSERT INTO tzid_test_results (test_name, status)
VALUES ('Session timezone independence (TIMESTAMP API)',
    assert_occurrences_equal(
        'Session timezone independence',
        ARRAY[
            '2025-01-01 00:30:00'::TIMESTAMP,
            '2025-01-08 00:30:00'::TIMESTAMP,
            '2025-01-15 00:30:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=3;BYDAY=WE',
            '2025-01-01 00:30:00'::TIMESTAMP
        ) AS occurrence
    )
));
SET timezone = 'UTC';

-- Test 13: Invalid TZID should raise exception
DO $$
DECLARE
    error_raised BOOLEAN := FALSE;
    error_message TEXT;
BEGIN
    BEGIN
        PERFORM (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;TZID=Invalid/Timezone',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence);
    EXCEPTION
        WHEN OTHERS THEN
            error_raised := TRUE;
            error_message := SQLERRM;

            IF error_message LIKE '%Invalid timezone%' THEN
                INSERT INTO tzid_test_results (test_name, status)
                VALUES ('Invalid TZID raises exception',
                        'PASS [Invalid TZID raises exception]');
            ELSE
                INSERT INTO tzid_test_results (test_name, status)
                VALUES ('Invalid TZID raises exception',
                        'FAIL: Wrong error message: ' || error_message);
            END IF;
    END;

    IF NOT error_raised THEN
        INSERT INTO tzid_test_results (test_name, status)
        VALUES ('Invalid TZID raises exception',
                'FAIL: Expected exception was not raised');
    END IF;
END $$;

-- Test 13a: lowercase tzid key should be validated the same as TZID
DO $$
DECLARE
    error_raised BOOLEAN := FALSE;
    error_message TEXT;
BEGIN
    BEGIN
        PERFORM (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;tzid=Invalid/Timezone',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence);
    EXCEPTION
        WHEN OTHERS THEN
            error_raised := TRUE;
            error_message := SQLERRM;

            IF error_message LIKE '%Invalid timezone%' THEN
                INSERT INTO tzid_test_results (test_name, status)
                VALUES ('Invalid lowercase tzid raises exception',
                        'PASS [Invalid lowercase tzid raises exception]');
            ELSE
                INSERT INTO tzid_test_results (test_name, status)
                VALUES ('Invalid lowercase tzid raises exception',
                        'FAIL: Wrong error message: ' || error_message);
            END IF;
    END;

    IF NOT error_raised THEN
        INSERT INTO tzid_test_results (test_name, status)
        VALUES ('Invalid lowercase tzid raises exception',
                'FAIL: Expected exception was not raised');
    END IF;
END $$;

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 6: TZID with Different Frequencies'
\echo '==================================================================='

-- Test 14: WEEKLY with TZID
INSERT INTO tzid_test_results (test_name, status)
VALUES ('WEEKLY with TZID',
    assert_occurrences_equal(
        'WEEKLY with TZID',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-13 10:00:00'::TIMESTAMP,
            '2025-01-20 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=3;TZID=America/New_York',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 15: MONTHLY with TZID
INSERT INTO tzid_test_results (test_name, status)
VALUES ('MONTHLY with TZID',
    assert_occurrences_equal(
        'MONTHLY with TZID',
        ARRAY[
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-02-15 10:00:00'::TIMESTAMP,
            '2025-03-15 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;COUNT=3;TZID=America/New_York',
            '2025-01-15 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 16: YEARLY with TZID
INSERT INTO tzid_test_results (test_name, status)
VALUES ('YEARLY with TZID',
    assert_occurrences_equal(
        'YEARLY with TZID',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2026-01-01 10:00:00'::TIMESTAMP,
            '2027-01-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;COUNT=3;TZID=America/New_York',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 7: TZID with Complex RRULE Patterns'
\echo '==================================================================='

-- Test 17: TZID with BYDAY (weekdays only) across DST
INSERT INTO tzid_test_results (test_name, status)
VALUES ('TZID with BYDAY across DST',
    assert_occurrences_equal(
        'TZID with BYDAY across DST',
        ARRAY[
            '2025-03-07 10:00:00'::TIMESTAMP,  -- Friday before DST
            '2025-03-10 10:00:00'::TIMESTAMP,  -- Monday after DST
            '2025-03-11 10:00:00'::TIMESTAMP   -- Tuesday after DST
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3;BYDAY=MO,TU,WE,TH,FR;TZID=America/New_York',
            '2025-03-07 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 18: TZID with BYMONTH
INSERT INTO tzid_test_results (test_name, status)
VALUES ('TZID with BYMONTH',
    assert_occurrences_equal(
        'TZID with BYMONTH',
        ARRAY[
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-07-15 10:00:00'::TIMESTAMP,
            '2026-01-15 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=1,7;COUNT=3;TZID=America/New_York',
            '2025-01-15 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 19: TZID with INTERVAL
INSERT INTO tzid_test_results (test_name, status)
VALUES ('TZID with INTERVAL',
    assert_occurrences_equal(
        'TZID with INTERVAL',
        ARRAY[
            '2025-03-07 10:00:00'::TIMESTAMP,  -- Friday before DST
            '2025-03-09 10:00:00'::TIMESTAMP,  -- Sunday (DST transition day!)
            '2025-03-11 10:00:00'::TIMESTAMP   -- Tuesday after DST
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;INTERVAL=2;COUNT=3;TZID=America/New_York',
            '2025-03-07 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 20: after() with TZID
INSERT INTO tzid_test_results (test_name, status)
VALUES ('after() with TZID',
    assert_equals(
        'after() with TZID',
        '2025-03-09 10:00:00',
        (SELECT rrule."after"(
            'FREQ=DAILY;COUNT=10;TZID=America/New_York',
            '2025-03-08 10:00:00'::TIMESTAMP,
            '2025-03-08 12:00:00'::TIMESTAMP
        )::TEXT)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 8: UNTIL + TZID Combinations'
\echo '==================================================================='

-- Test 21: UNTIL with TZID (TIMESTAMP API)
-- RFC 5545: When DTSTART has TZID, UNTIL must be in UTC.
-- This tests that a UTC UNTIL works correctly with TZID.
INSERT INTO tzid_test_results (test_name, status)
VALUES ('UNTIL with TZID (UTC boundary)',
    assert_occurrences_equal(
        'UNTIL with TZID (UTC boundary)',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;UNTIL=20250103T150000Z;TZID=America/New_York',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 22: UNTIL with TZID across DST transition
-- Start before spring-forward, UNTIL after spring-forward
-- Wall-clock time should remain consistent
INSERT INTO tzid_test_results (test_name, status)
VALUES ('UNTIL with TZID across DST',
    assert_occurrences_equal(
        'UNTIL with TZID across DST',
        ARRAY[
            '2025-03-07 10:00:00'::TIMESTAMP,
            '2025-03-08 10:00:00'::TIMESTAMP,
            '2025-03-09 10:00:00'::TIMESTAMP,
            '2025-03-10 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;UNTIL=20250310T140000Z;TZID=America/New_York',
            '2025-03-07 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 23: UNTIL without TZID (local time, no timezone reference)
-- When no TZID is specified, UNTIL should work as a local timestamp boundary
INSERT INTO tzid_test_results (test_name, status)
VALUES ('UNTIL without TZID (local time)',
    assert_occurrences_equal(
        'UNTIL without TZID (local time)',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;UNTIL=20250103T100000Z',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 24: UNTIL with TZID and WEEKLY frequency
INSERT INTO tzid_test_results (test_name, status)
VALUES ('UNTIL with TZID WEEKLY',
    assert_occurrences_equal(
        'UNTIL with TZID WEEKLY',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-13 10:00:00'::TIMESTAMP,
            '2025-01-20 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;UNTIL=20250121T000000Z;TZID=America/New_York',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

-- Test 24a: UTC UNTIL before first absolute occurrence should produce zero rows
-- DTSTART is wall-clock New York 23:00 (= 2025-01-02 04:00Z), but UNTIL is 2025-01-01 23:00Z.
INSERT INTO tzid_test_results (test_name, status)
VALUES ('UNTIL before first absolute occurrence',
    assert_occurrences_equal(
        'UNTIL before first absolute occurrence',
        ARRAY[]::TIMESTAMP[],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;UNTIL=20250101T230000Z;TZID=America/New_York',
            '2025-01-01 23:00:00'::TIMESTAMP
        ) AS occurrence
    )
));

\echo ''
\echo '==================================================================='
\echo 'TEST RESULTS SUMMARY'
\echo '==================================================================='

SELECT
    COUNT(*) AS total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') AS passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') AS failed
FROM tzid_test_results;

\echo ''
\echo 'Detailed Results:'
\echo ''

SELECT
    test_number,
    CASE
        WHEN status LIKE 'PASS%' THEN '[PASS] ' || test_name
        ELSE '[FAIL] ' || test_name || ' - ' || status
    END AS result
FROM tzid_test_results
ORDER BY test_number;

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 9: DST Gap and Ambiguous Times (TZID API)'
\echo '==================================================================='

-- Test 25: Spring-forward gap time (2:30 AM on March 9, 2025 does not exist)
-- TZID API uses TIMESTAMP arithmetic; wall-clock 2:30 AM on gap date
-- will be advanced by PostgreSQL to 3:30 AM EDT when converting.
-- Non-gap dates preserve 2:30 AM wall-clock time.
DO $$
DECLARE
    actual TIMESTAMP[];
    result_count INT;
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence), COUNT(*) INTO actual, result_count
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3;TZID=America/New_York',
        '2025-03-08 02:30:00'::TIMESTAMP
    ) AS occurrence;

    -- Must produce exactly 3 occurrences (no crash/skip on the gap date)
    -- Wall-clock: Mar 8 02:30, Mar 9 03:30 (gap coerced forward), Mar 10 02:30
    IF result_count = 3
        AND actual[1] = '2025-03-08 02:30:00'::TIMESTAMP
        AND actual[2] = '2025-03-09 03:30:00'::TIMESTAMP
        AND actual[3] = '2025-03-10 02:30:00'::TIMESTAMP
    THEN
        INSERT INTO tzid_test_results (test_name, status)
        VALUES ('DST spring-forward gap 2:30 AM (TZID)', 'PASS [DST gap]');
    ELSE
        INSERT INTO tzid_test_results (test_name, status)
        VALUES ('DST spring-forward gap 2:30 AM (TZID)',
            'FAIL: Expected [02:30,03:30,02:30], got ' || result_count || ': ' || actual::TEXT);
    END IF;
END;
$$;

-- Test 26: Fall-back ambiguous time (1:30 AM on November 2, 2025 occurs twice)
-- TZID API uses TIMESTAMP arithmetic; wall-clock 1:30 AM stays consistent.
DO $$
DECLARE
    actual TIMESTAMP[];
    result_count INT;
BEGIN
    SELECT array_agg(occurrence ORDER BY occurrence), COUNT(*) INTO actual, result_count
    FROM rrule."all"(
        'FREQ=DAILY;COUNT=3;TZID=America/New_York',
        '2025-11-01 01:30:00'::TIMESTAMP
    ) AS occurrence;

    -- Wall-clock times should stay at 01:30 for all 3 days
    IF result_count = 3
        AND actual[1] = '2025-11-01 01:30:00'::TIMESTAMP
        AND actual[2] = '2025-11-02 01:30:00'::TIMESTAMP
        AND actual[3] = '2025-11-03 01:30:00'::TIMESTAMP
    THEN
        INSERT INTO tzid_test_results (test_name, status)
        VALUES ('DST fall-back ambiguous 1:30 AM (TZID)', 'PASS [DST ambiguous]');
    ELSE
        INSERT INTO tzid_test_results (test_name, status)
        VALUES ('DST fall-back ambiguous 1:30 AM (TZID)',
            'FAIL: Expected 3 occurrences at 01:30, got ' || result_count || ': ' || actual::TEXT);
    END IF;
END;
$$;

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 10: Full API Surface with TZID'
\echo '==================================================================='

-- Test 27: between() with TZID
INSERT INTO tzid_test_results (test_name, status)
VALUES ('between() with TZID',
    assert_occurrences_equal(
        'between() with TZID',
        ARRAY[
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=DAILY;COUNT=5;TZID=America/New_York',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 00:00:00'::TIMESTAMP,
            '2025-01-03 23:59:59'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 28: before() with TZID
INSERT INTO tzid_test_results (test_name, status)
VALUES ('before() with TZID',
    assert_equals(
        'before() with TZID',
        '2025-01-02 10:00:00',
        (SELECT rrule."before"(
            'FREQ=DAILY;COUNT=5;TZID=America/New_York',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 00:00:00'::TIMESTAMP
        )::TEXT)
    )
);

-- Test 29: count() with TZID
INSERT INTO tzid_test_results (test_name, status)
VALUES ('count() with TZID',
    assert_equals(
        'count() with TZID',
        '5',
        (SELECT rrule."count"(
            'FREQ=DAILY;COUNT=5;TZID=America/New_York',
            '2025-01-01 10:00:00'::TIMESTAMP
        )::TEXT)
    )
);

-- Test 30: next() with TZID (explicit reference_time for determinism)
INSERT INTO tzid_test_results (test_name, status)
VALUES ('next() with TZID',
    assert_equals(
        'next() with TZID',
        '2025-01-02 10:00:00',
        (SELECT rrule."next"(
            'FREQ=DAILY;COUNT=5;TZID=America/New_York',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 00:00:00'::TIMESTAMP
        )::TEXT)
    )
);

-- Test 31: most_recent() with TZID (explicit reference_time for determinism)
INSERT INTO tzid_test_results (test_name, status)
VALUES ('most_recent() with TZID',
    assert_equals(
        'most_recent() with TZID',
        '2025-01-02 10:00:00',
        (SELECT rrule."most_recent"(
            'FREQ=DAILY;COUNT=5;TZID=America/New_York',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 08:00:00'::TIMESTAMP
        )::TEXT)
    )
);

-- Check if all tests passed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM tzid_test_results
    WHERE status LIKE 'FAIL%';

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'TZID TEST SUITE FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'TZID TEST SUITE PASSED: All tests passed successfully!';
    END IF;
END $$;

ROLLBACK;
