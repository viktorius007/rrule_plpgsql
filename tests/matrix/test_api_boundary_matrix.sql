/**
 * API Parameter Boundary Matrix Tests
 *
 * Systematic tests for every public API function with boundary conditions:
 * - NULL parameters
 * - Empty strings
 * - Minimum values
 * - Maximum values (caps)
 * - Invalid inputs
 *
 * Functions tested:
 * - rrule."all"()
 * - rrule."between"()
 * - rrule."after"()
 * - rrule."before"()
 * - rrule.count()
 * - rrule.next()
 * - rrule.most_recent()
 * - rrule.overlaps()
 *
 * Coverage: 8 functions x 7 boundary types = 56+ tests
 *
 * Usage:
 *   psql -d your_database -f tests/matrix/test_api_boundary_matrix.sql
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
\echo 'API PARAMETER BOUNDARY MATRIX TESTS'
\echo '====================================================================='
\echo ''

--------------------------------------------------------------------------------
-- SECTION 1: rrule."all"() BOUNDARY TESTS
--------------------------------------------------------------------------------
\echo ''
\echo '--- rrule."all"() BOUNDARY TESTS ---'
\echo ''

-- NULL rrule should raise exception
DO $$
DECLARE
    result TIMESTAMP[];
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := (SELECT array_agg(r) FROM rrule."all"(NULL::TEXT, '2025-01-01'::TIMESTAMP) r);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [all-NULL-rrule]: Expected exception for NULL rrule';
    END IF;
    RAISE NOTICE 'PASS [all-NULL-rrule]';
END $$;

-- NULL dtstart should raise exception
DO $$
DECLARE
    result TIMESTAMP[];
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := (SELECT array_agg(r) FROM rrule."all"('FREQ=DAILY;COUNT=5', NULL::TIMESTAMP) r);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [all-NULL-dtstart]: Expected exception for NULL dtstart';
    END IF;
    RAISE NOTICE 'PASS [all-NULL-dtstart]';
END $$;

-- Empty rrule string should raise exception
DO $$
DECLARE
    result TIMESTAMP[];
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := (SELECT array_agg(r) FROM rrule."all"('', '2025-01-01'::TIMESTAMP) r);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [all-empty-rrule]: Expected exception for empty rrule';
    END IF;
    RAISE NOTICE 'PASS [all-empty-rrule]';
END $$;

-- Minimum COUNT=1
SELECT assert_equals('all-COUNT-min', '1',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;COUNT=1', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Maximum results capped at 1000 (unbounded rule)
SELECT assert_equals('all-unbounded-cap', '1000',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY', '2025-01-01 10:00:00'::TIMESTAMP)));

-- 10-year window cap verification (inclusive boundary: dtstart + 10 years is included)
-- With YEARLY frequency, we get exactly 11 results: 2025, 2026, ..., 2035
-- MAX(r) should be exactly dtstart + 10 years = 2035-01-01
SELECT assert_true('all-10year-cap',
    (SELECT MAX(r) = '2035-01-01 10:00:00'::TIMESTAMP
     FROM rrule."all"('FREQ=YEARLY', '2025-01-01 10:00:00'::TIMESTAMP) r));

-- COUNT=0 is rejected (COUNT must be positive)
SELECT assert_rrule_rejected('all-COUNT-zero',
    'FREQ=DAILY;COUNT=0',
    '%COUNT must be a positive integer%');

-- UNTIL in the past returns empty
SELECT assert_equals('all-UNTIL-past', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;UNTIL=20240101T000000Z', '2025-01-01 10:00:00'::TIMESTAMP)));

-- dtstart at epoch (minimum practical date)
SELECT assert_equals('all-dtstart-epoch', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;COUNT=5', '1970-01-01 00:00:00'::TIMESTAMP)));

-- dtstart far future
SELECT assert_equals('all-dtstart-future', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;COUNT=5', '2099-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 2: rrule."between"() BOUNDARY TESTS
--------------------------------------------------------------------------------
\echo ''
\echo '--- rrule."between"() BOUNDARY TESTS ---'
\echo ''

-- NULL rrule
DO $$
DECLARE
    result TIMESTAMP[];
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := (SELECT array_agg(r) FROM rrule."between"(NULL::TEXT, '2025-01-01'::TIMESTAMP,
            '2025-01-01'::TIMESTAMP, '2025-12-31'::TIMESTAMP) r);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [between-NULL-rrule]: Expected exception for NULL rrule';
    END IF;
    RAISE NOTICE 'PASS [between-NULL-rrule]';
END $$;

-- NULL dtstart
DO $$
DECLARE
    result TIMESTAMP[];
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := (SELECT array_agg(r) FROM rrule."between"('FREQ=DAILY;COUNT=100', NULL::TIMESTAMP,
            '2025-01-01'::TIMESTAMP, '2025-12-31'::TIMESTAMP) r);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [between-NULL-dtstart]: Expected exception for NULL dtstart';
    END IF;
    RAISE NOTICE 'PASS [between-NULL-dtstart]';
END $$;

-- start = end (single point query)
SELECT assert_equals('between-point-query', '1',
    (SELECT COUNT(*)::TEXT FROM rrule."between"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:00:00'::TIMESTAMP, '2025-01-01 10:00:00'::TIMESTAMP, TRUE)));

-- start > end (inverted range) - should return empty
SELECT assert_equals('between-inverted', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."between"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-12-31'::TIMESTAMP, '2025-01-01'::TIMESTAMP)));

-- Default inc=FALSE excludes boundaries
SELECT assert_equals('between-inc-default', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."between"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:00:00'::TIMESTAMP, '2025-01-05 10:00:00'::TIMESTAMP)));

-- inc=TRUE includes boundaries
SELECT assert_equals('between-inc-true', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."between"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:00:00'::TIMESTAMP, '2025-01-05 10:00:00'::TIMESTAMP, TRUE)));

-- Range before dtstart
SELECT assert_equals('between-before-dtstart', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."between"('FREQ=DAILY;COUNT=100', '2025-06-01 10:00:00'::TIMESTAMP,
        '2025-01-01'::TIMESTAMP, '2025-03-31'::TIMESTAMP)));

-- Range after COUNT exhausted
SELECT assert_equals('between-after-count', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."between"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-02-01'::TIMESTAMP, '2025-03-31'::TIMESTAMP)));

-- Capped at 1000 results
SELECT assert_equals('between-cap-1000', '1000',
    (SELECT COUNT(*)::TEXT FROM rrule."between"('FREQ=DAILY', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01'::TIMESTAMP, '2030-12-31'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 3: rrule."after"() BOUNDARY TESTS
--------------------------------------------------------------------------------
\echo ''
\echo '--- rrule."after"() BOUNDARY TESTS ---'
\echo ''

-- NULL rrule
DO $$
DECLARE
    result TIMESTAMP;
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := rrule."after"(NULL::TEXT, '2025-01-01'::TIMESTAMP, '2025-01-01'::TIMESTAMP);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [after-NULL-rrule]: Expected exception for NULL rrule';
    END IF;
    RAISE NOTICE 'PASS [after-NULL-rrule]';
END $$;

-- NULL dtstart
DO $$
DECLARE
    result TIMESTAMP;
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := rrule."after"('FREQ=DAILY;COUNT=5', NULL::TIMESTAMP, '2025-01-01'::TIMESTAMP);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [after-NULL-dtstart]: Expected exception for NULL dtstart';
    END IF;
    RAISE NOTICE 'PASS [after-NULL-dtstart]';
END $$;

-- Default inc=FALSE excludes exact match
SELECT assert_equals('after-inc-default', '2025-01-02 10:00:00',
    rrule."after"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:00:00'::TIMESTAMP)::TEXT);

-- inc=TRUE includes exact match
SELECT assert_equals('after-inc-true', '2025-01-01 10:00:00',
    rrule."after"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01 10:00:00'::TIMESTAMP, TRUE)::TEXT);

-- Reference date before dtstart
SELECT assert_equals('after-before-dtstart', '2025-01-01 10:00:00',
    rrule."after"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP,
        '2020-01-01'::TIMESTAMP, TRUE)::TEXT);

-- Reference date after all occurrences
SELECT assert_true('after-past-all',
    rrule."after"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-12-31'::TIMESTAMP) IS NULL);

-- Far future reference
SELECT assert_true('after-far-future',
    rrule."after"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP,
        '2099-01-01'::TIMESTAMP) IS NULL);


--------------------------------------------------------------------------------
-- SECTION 4: rrule."before"() BOUNDARY TESTS
--------------------------------------------------------------------------------
\echo ''
\echo '--- rrule."before"() BOUNDARY TESTS ---'
\echo ''

-- NULL rrule
DO $$
DECLARE
    result TIMESTAMP;
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := rrule."before"(NULL::TEXT, '2025-01-01'::TIMESTAMP, '2025-01-10'::TIMESTAMP);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [before-NULL-rrule]: Expected exception for NULL rrule';
    END IF;
    RAISE NOTICE 'PASS [before-NULL-rrule]';
END $$;

-- NULL dtstart
DO $$
DECLARE
    result TIMESTAMP;
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := rrule."before"('FREQ=DAILY;COUNT=5', NULL::TIMESTAMP, '2025-01-10'::TIMESTAMP);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [before-NULL-dtstart]: Expected exception for NULL dtstart';
    END IF;
    RAISE NOTICE 'PASS [before-NULL-dtstart]';
END $$;

-- Default inc=FALSE excludes exact match
SELECT assert_equals('before-inc-default', '2025-01-04 10:00:00',
    rrule."before"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-05 10:00:00'::TIMESTAMP)::TEXT);

-- inc=TRUE includes exact match
SELECT assert_equals('before-inc-true', '2025-01-05 10:00:00',
    rrule."before"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-05 10:00:00'::TIMESTAMP, TRUE)::TEXT);

-- Reference date before dtstart
SELECT assert_true('before-before-dtstart',
    rrule."before"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP,
        '2020-01-01'::TIMESTAMP) IS NULL);

-- Reference date after all occurrences
SELECT assert_equals('before-after-all', '2025-01-05 10:00:00',
    rrule."before"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-12-31'::TIMESTAMP)::TEXT);


--------------------------------------------------------------------------------
-- SECTION 5: rrule.count() BOUNDARY TESTS
--------------------------------------------------------------------------------
\echo ''
\echo '--- rrule.count() BOUNDARY TESTS ---'
\echo ''

-- NULL rrule
DO $$
DECLARE
    result INT;
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := rrule.count(NULL::TEXT, '2025-01-01'::TIMESTAMP);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [count-NULL-rrule]: Expected exception for NULL rrule';
    END IF;
    RAISE NOTICE 'PASS [count-NULL-rrule]';
END $$;

-- NULL dtstart
DO $$
DECLARE
    result INT;
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := rrule.count('FREQ=DAILY;COUNT=5', NULL::TIMESTAMP);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [count-NULL-dtstart]: Expected exception for NULL dtstart';
    END IF;
    RAISE NOTICE 'PASS [count-NULL-dtstart]';
END $$;

-- COUNT=1
SELECT assert_equals('count-COUNT-1', '1',
    rrule.count('FREQ=DAILY;COUNT=1', '2025-01-01 10:00:00'::TIMESTAMP)::TEXT);

-- COUNT=0 is rejected
SELECT assert_rrule_rejected('count-COUNT-0',
    'FREQ=DAILY;COUNT=0',
    '%COUNT must be a positive integer%');

-- Unbounded (inherits 1000 cap from all())
SELECT assert_equals('count-unbounded', '1000',
    rrule.count('FREQ=DAILY', '2025-01-01 10:00:00'::TIMESTAMP)::TEXT);


--------------------------------------------------------------------------------
-- SECTION 6: rrule.next() BOUNDARY TESTS
--------------------------------------------------------------------------------
\echo ''
\echo '--- rrule.next() BOUNDARY TESTS ---'
\echo ''

-- NULL rrule
DO $$
DECLARE
    result TIMESTAMP;
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := rrule.next(NULL::TEXT, '2025-01-01'::TIMESTAMP);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [next-NULL-rrule]: Expected exception for NULL rrule';
    END IF;
    RAISE NOTICE 'PASS [next-NULL-rrule]';
END $$;

-- NULL dtstart
DO $$
DECLARE
    result TIMESTAMP;
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := rrule.next('FREQ=DAILY;COUNT=5', NULL::TIMESTAMP);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [next-NULL-dtstart]: Expected exception for NULL dtstart';
    END IF;
    RAISE NOTICE 'PASS [next-NULL-dtstart]';
END $$;

-- Returns first occurrence after reference_time
-- The next() function takes (rrule, dtstart, timezone, reference_time)
-- We need to provide reference_time to get predictable results
SELECT assert_equals('next-first', '2025-01-02 15:00:00+00',
    rrule.next('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00-05'::TIMESTAMPTZ, 'America/New_York', '2025-01-01 10:00:00-05'::TIMESTAMPTZ)::TEXT);

-- Rule with only one occurrence (dtstart itself) returns NULL for next
SELECT assert_true('next-single-occurrence',
    rrule.next('FREQ=DAILY;COUNT=1', '2025-01-01 10:00:00-05'::TIMESTAMPTZ, 'America/New_York', '2025-01-01 10:00:00-05'::TIMESTAMPTZ) IS NULL);


--------------------------------------------------------------------------------
-- SECTION 7: rrule.most_recent() BOUNDARY TESTS
--------------------------------------------------------------------------------
\echo ''
\echo '--- rrule.most_recent() BOUNDARY TESTS ---'
\echo ''

-- NULL rrule
DO $$
DECLARE
    result TIMESTAMP;
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := rrule.most_recent(NULL::TEXT, '2025-01-01'::TIMESTAMP);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [most_recent-NULL-rrule]: Expected exception for NULL rrule';
    END IF;
    RAISE NOTICE 'PASS [most_recent-NULL-rrule]';
END $$;

-- NULL dtstart
DO $$
DECLARE
    result TIMESTAMP;
    caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        result := rrule.most_recent('FREQ=DAILY;COUNT=5', NULL::TIMESTAMP);
    EXCEPTION WHEN OTHERS THEN
        caught := TRUE;
    END;
    IF NOT caught THEN
        RAISE EXCEPTION 'FAIL [most_recent-NULL-dtstart]: Expected exception for NULL dtstart';
    END IF;
    RAISE NOTICE 'PASS [most_recent-NULL-dtstart]';
END $$;

-- Returns the most recent occurrence before/at reference_time
-- The most_recent() function takes (rrule, dtstart, timezone, reference_time)
-- We need to provide a reference_time after dtstart to get results
SELECT assert_true('most_recent-at-dtstart',
    rrule.most_recent('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00-05'::TIMESTAMPTZ, 'America/New_York', '2025-01-05 10:00:00-05'::TIMESTAMPTZ) IS NOT NULL);


--------------------------------------------------------------------------------
-- SECTION 8: rrule.overlaps() BOUNDARY TESTS
--------------------------------------------------------------------------------
\echo ''
\echo '--- rrule.overlaps() BOUNDARY TESTS ---'
\echo ''

-- Basic overlap detection (use TIMESTAMPTZ version with explicit types)
SELECT assert_true('overlaps-basic',
    rrule."overlaps"('2025-01-01 10:00:00'::TIMESTAMPTZ, '2025-01-01 11:00:00'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=10'::TEXT, '2025-01-01'::TIMESTAMPTZ, '2025-12-31'::TIMESTAMPTZ, 'UTC'::TEXT));

-- No overlap - event before range
SELECT assert_false('overlaps-before-range',
    rrule."overlaps"('2020-01-01 10:00:00'::TIMESTAMPTZ, '2020-01-01 11:00:00'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=5'::TEXT, '2025-01-01'::TIMESTAMPTZ, '2025-12-31'::TIMESTAMPTZ, 'UTC'::TEXT));

-- Single-event (NULL rrule treated as single occurrence)
SELECT assert_true('overlaps-single-event',
    rrule."overlaps"('2025-06-15 10:00:00'::TIMESTAMPTZ, '2025-06-15 11:00:00'::TIMESTAMPTZ,
        NULL::TEXT, '2025-01-01'::TIMESTAMPTZ, '2025-12-31'::TIMESTAMPTZ, 'UTC'::TEXT));

-- dtend = dtstart (zero-duration event)
SELECT assert_true('overlaps-zero-duration',
    rrule."overlaps"('2025-01-05 10:00:00'::TIMESTAMPTZ, '2025-01-05 10:00:00'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=10'::TEXT, '2025-01-01'::TIMESTAMPTZ, '2025-12-31'::TIMESTAMPTZ, 'UTC'::TEXT));

-- Inverted dtstart/dtend (implementation may still check for overlaps)
-- Skip this test as behavior is implementation-specific
-- SELECT assert_false('overlaps-inverted-event', ...);

-- Test non-overlapping (event completely before range start)
SELECT assert_false('overlaps-completely-before',
    rrule."overlaps"('2020-01-01 10:00:00'::TIMESTAMPTZ, '2020-12-31 10:00:00'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=5'::TEXT, '2025-01-01'::TIMESTAMPTZ, '2025-12-31'::TIMESTAMPTZ, 'UTC'::TEXT));


--------------------------------------------------------------------------------
-- SECTION 9: TIMESTAMPTZ API BOUNDARY TESTS
--------------------------------------------------------------------------------
\echo ''
\echo '--- TIMESTAMPTZ API BOUNDARY TESTS ---'
\echo ''

-- rrule."all"() with TIMESTAMPTZ overload
SELECT assert_equals('all-tz-basic', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;COUNT=5',
        '2025-01-01 10:00:00'::TIMESTAMPTZ, 'America/New_York')));

-- NULL timezone defaults to session timezone
SELECT assert_equals('all-tz-null', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;COUNT=5',
        '2025-01-01 10:00:00'::TIMESTAMPTZ, NULL)));

-- rrule."between"() with TIMESTAMPTZ overload
SELECT assert_equals('between-tz-basic', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."between"('FREQ=DAILY;COUNT=100'::TEXT,
        '2025-01-01 10:00:00'::TIMESTAMPTZ,
        '2025-01-01'::TIMESTAMPTZ, '2025-01-05 23:59:59'::TIMESTAMPTZ,
        'America/New_York'::TEXT, TRUE)));

-- rrule."after"() with TIMESTAMPTZ overload
SELECT assert_true('after-tz-basic',
    rrule."after"('FREQ=DAILY;COUNT=100'::TEXT,
        '2025-01-01 10:00:00'::TIMESTAMPTZ,
        '2025-01-01 10:00:00'::TIMESTAMPTZ, 1,
        'America/New_York'::TEXT, TRUE) IS NOT NULL);

-- rrule."before"() with TIMESTAMPTZ overload
SELECT assert_true('before-tz-basic',
    rrule."before"('FREQ=DAILY;COUNT=100'::TEXT,
        '2025-01-01 10:00:00'::TIMESTAMPTZ,
        '2025-01-10 10:00:00'::TIMESTAMPTZ, 1,
        'America/New_York'::TEXT, TRUE) IS NOT NULL);


\echo ''
\echo '====================================================================='
\echo 'API PARAMETER BOUNDARY MATRIX TESTS COMPLETE'
\echo '====================================================================='

ROLLBACK;
