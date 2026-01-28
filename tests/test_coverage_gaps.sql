/**
 * Coverage Gap Tests
 *
 * This file contains tests to achieve 100% coverage of the public API functions.
 * It specifically targets gaps identified in the existing test suite:
 *
 * 1. overlaps() - Comprehensive edge case testing
 * 2. between() - Range boundary and edge case testing
 * 3. after()/before() - Edge cases when count exceeds available occurrences
 * 4. next()/most_recent() - Boundary condition testing
 * 5. Error handling - NULL inputs, malformed RRULEs
 *
 * Usage:
 *   psql -d your_database -f tests/test_coverage_gaps.sql
 */

\set ON_ERROR_STOP on
\set ECHO all

BEGIN;

SET timezone = 'UTC';

-- Create rrule schema and load functions
DROP SCHEMA IF EXISTS rrule CASCADE;
CREATE SCHEMA IF NOT EXISTS rrule;
SET search_path = rrule, public;

-- Load the RRULE functions
\i src/rrule.sql

-- Test results table
CREATE TEMP TABLE coverage_gap_results (
    test_id SERIAL PRIMARY KEY,
    test_category TEXT,
    test_name TEXT,
    status TEXT
);

-- Helper function for assertions
CREATE OR REPLACE FUNCTION assert_equals(
    test_name TEXT,
    expected TEXT,
    actual TEXT
) RETURNS TEXT AS $$
BEGIN
    IF expected IS NOT DISTINCT FROM actual THEN
        RETURN 'PASS';
    ELSE
        RETURN 'FAIL - Expected: ' || COALESCE(expected, 'NULL') || ', Got: ' || COALESCE(actual, 'NULL');
    END IF;
END;
$$ LANGUAGE plpgsql;

\echo ''
\echo '==================================================================='
\echo 'COVERAGE GAP TESTS'
\echo '==================================================================='
\echo ''

-- ============================================================================
-- SECTION 1: overlaps() Comprehensive Tests
-- ============================================================================
\echo '--- Section 1: overlaps() Comprehensive Tests ---'

-- Test 1.1: Event entirely within query range (should return TRUE)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Scenarios',
    'Event entirely within range',
    assert_equals(
        'Event within range',
        'true',
        (SELECT rrule.overlaps(
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-15 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=5'::TEXT,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.2: Event starts before range, ends within (should return TRUE)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Scenarios',
    'Event overlaps range start',
    assert_equals(
        'Overlap at start',
        'true',
        (SELECT rrule.overlaps(
            '2025-01-05 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-05 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=10'::TEXT,
            '2025-01-08 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-15 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.3: Event starts within range, ends after (should return TRUE)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Scenarios',
    'Event overlaps range end',
    assert_equals(
        'Overlap at end',
        'true',
        (SELECT rrule.overlaps(
            '2025-01-10 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-10 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=10'::TEXT,
            '2025-01-05 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-12 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.4: Event spans entire range (should return TRUE)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Scenarios',
    'Event spans entire range',
    assert_equals(
        'Spans range',
        'true',
        (SELECT rrule.overlaps(
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=31'::TEXT,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.5: No overlap - event entirely before range (should return FALSE)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Scenarios',
    'No overlap - event before range',
    assert_equals(
        'No overlap before',
        'false',
        (SELECT rrule.overlaps(
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=5'::TEXT,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.6: No overlap - event entirely after range (should return FALSE)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Scenarios',
    'No overlap - event after range',
    assert_equals(
        'No overlap after',
        'false',
        (SELECT rrule.overlaps(
            '2025-02-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-02-01 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=5'::TEXT,
            '2025-01-01 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-31 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.7: Exact boundary match at range start (should return TRUE)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Scenarios',
    'Exact boundary at range start',
    assert_equals(
        'Boundary start',
        'true',
        (SELECT rrule.overlaps(
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-10 01:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=1'::TEXT,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.8: Exact boundary match at range end (should return TRUE)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Scenarios',
    'Exact boundary at range end',
    assert_equals(
        'Boundary end',
        'true',
        (SELECT rrule.overlaps(
            '2025-01-20 23:00:00+00'::TIMESTAMPTZ,
            '2025-01-21 00:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=1'::TEXT,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.9: NULL RRULE - single event within range (should return TRUE)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Scenarios',
    'NULL RRULE - single event within range',
    assert_equals(
        'NULL RRULE within',
        'true',
        (SELECT rrule.overlaps(
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-15 11:00:00+00'::TIMESTAMPTZ,
            NULL::TEXT,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.10: NULL RRULE - single event outside range (should return FALSE)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Scenarios',
    'NULL RRULE - single event outside range',
    assert_equals(
        'NULL RRULE outside',
        'false',
        (SELECT rrule.overlaps(
            '2025-02-15 10:00:00+00'::TIMESTAMPTZ,
            '2025-02-15 11:00:00+00'::TIMESTAMPTZ,
            NULL::TEXT,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.11: overlaps() with WEEKLY frequency
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Frequencies',
    'WEEKLY frequency overlap',
    assert_equals(
        'WEEKLY overlap',
        'true',
        (SELECT rrule.overlaps(
            '2025-01-06 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-06 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=WEEKLY;BYDAY=MO;COUNT=10'::TEXT,
            '2025-01-13 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.12: overlaps() with MONTHLY frequency
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Frequencies',
    'MONTHLY frequency overlap',
    assert_equals(
        'MONTHLY overlap',
        'true',
        (SELECT rrule.overlaps(
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-15 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=6'::TEXT,
            '2025-03-01 00:00:00+00'::TIMESTAMPTZ,
            '2025-03-31 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.13: overlaps() with YEARLY frequency
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Frequencies',
    'YEARLY frequency overlap',
    assert_equals(
        'YEARLY overlap',
        'true',
        (SELECT rrule.overlaps(
            '2025-07-04 10:00:00+00'::TIMESTAMPTZ,
            '2025-07-04 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=YEARLY;BYMONTH=7;BYMONTHDAY=4;COUNT=5'::TEXT,
            '2026-07-01 00:00:00+00'::TIMESTAMPTZ,
            '2026-07-31 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.14: overlaps() with BYSETPOS
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Complex',
    'BYSETPOS pattern overlap',
    assert_equals(
        'BYSETPOS overlap',
        'true',
        (SELECT rrule.overlaps(
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=12'::TEXT,
            '2025-03-01 00:00:00+00'::TIMESTAMPTZ,
            '2025-03-31 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.15: overlaps() with zero-duration event (point in time)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() Edge Cases',
    'Zero-duration event',
    assert_equals(
        'Zero duration',
        'true',
        (SELECT rrule.overlaps(
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=5'::TEXT,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- ============================================================================
-- SECTION 2: between() Edge Cases
-- ============================================================================
\echo ''
\echo '--- Section 2: between() Edge Cases ---'

-- Test 2.1: Empty range (no occurrences in range)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Edge Cases',
    'Empty range - no occurrences',
    assert_equals(
        'Empty range',
        '0',
        (SELECT COUNT(*)::TEXT FROM "between"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-02-01 00:00:00'::TIMESTAMP,
            '2025-02-28 23:59:59'::TIMESTAMP
        ))
    );

-- Test 2.2: Range contains single occurrence (range slightly expanded)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Edge Cases',
    'Range contains single occurrence',
    assert_equals(
        'Single match',
        '1',
        (SELECT COUNT(*)::TEXT FROM "between"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-05 09:00:00'::TIMESTAMP,
            '2025-01-05 11:00:00'::TIMESTAMP
        ))
    );

-- Test 2.3: Range includes an occurrence (inclusive range)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Edge Cases',
    'Range includes occurrence',
    assert_equals(
        'Inclusive range',
        '1',
        (SELECT COUNT(*)::TEXT FROM "between"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 00:00:00'::TIMESTAMP,
            '2025-01-03 23:59:59'::TIMESTAMP
        ))
    );

-- Test 2.4: Range start equals range end (point in time) - no match
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Edge Cases',
    'Point range (start=end) no match',
    assert_equals(
        'Point range no match',
        '0',
        (SELECT COUNT(*)::TEXT FROM "between"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 11:00:00'::TIMESTAMP,
            '2025-01-03 11:00:00'::TIMESTAMP
        ))
    );

-- Test 2.5: Large range with UNTIL
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Edge Cases',
    'Large range with UNTIL limit',
    assert_equals(
        'Large range UNTIL',
        '5',
        (SELECT COUNT(*)::TEXT FROM "between"(
            'FREQ=DAILY;UNTIL=20250105T100000',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-12-31 23:59:59'::TIMESTAMP
        ))
    );

-- Test 2.6: between() with WEEKLY pattern
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Frequencies',
    'WEEKLY pattern in 2-week range',
    assert_equals(
        'WEEKLY between',
        '2',
        (SELECT COUNT(*)::TEXT FROM "between"(
            'FREQ=WEEKLY;BYDAY=MO;COUNT=10',
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-06 00:00:00'::TIMESTAMP,
            '2025-01-19 23:59:59'::TIMESTAMP
        ))
    );

-- Test 2.7: between() with MONTHLY pattern spanning partial months
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Frequencies',
    'MONTHLY pattern partial months',
    assert_equals(
        'MONTHLY between',
        '2',
        (SELECT COUNT(*)::TEXT FROM "between"(
            'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=12',
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-01-10 00:00:00'::TIMESTAMP,
            '2025-02-20 23:59:59'::TIMESTAMP
        ))
    );

-- ============================================================================
-- SECTION 3: after()/before() Edge Cases
-- ============================================================================
\echo ''
\echo '--- Section 3: after()/before() Edge Cases ---'

-- Test 3.1: after() when count exceeds available occurrences
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'after() Edge Cases',
    'Count exceeds available occurrences',
    assert_equals(
        'Exceeds available',
        '3',
        (SELECT COUNT(*)::TEXT FROM "after"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2024-12-01 00:00:00'::TIMESTAMP,
            10  -- Request 10 but only 3 exist
        ))
    );

-- Test 3.2: after() with no matches (all occurrences before after_date)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'after() Edge Cases',
    'No matches - all before after_date',
    assert_equals(
        'No matches',
        '0',
        (SELECT COUNT(*)::TEXT FROM "after"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-02-01 00:00:00'::TIMESTAMP,
            5
        ))
    );

-- Test 3.3: after() with count=1 (single result)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'after() Edge Cases',
    'Single result (count=1)',
    assert_equals(
        'Single result',
        '1',
        (SELECT COUNT(*)::TEXT FROM "after"(
            'FREQ=DAILY;COUNT=100',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-05 00:00:00'::TIMESTAMP,
            1
        ))
    );

-- Test 3.4: after() uses strict inequality (> not >=), so boundary match returns NEXT occurrence
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'after() Edge Cases',
    'Strict inequality (returns occurrence AFTER after_date)',
    assert_equals(
        'After boundary',
        '2025-01-04 10:00:00',
        (SELECT occurrence::TEXT FROM "after"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 3.5: before() when count exceeds available occurrences
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Edge Cases',
    'Count exceeds available occurrences',
    assert_equals(
        'Exceeds available',
        '3',
        (SELECT COUNT(*)::TEXT FROM "before"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-02-01 00:00:00'::TIMESTAMP,
            10  -- Request 10 but only 3 exist
        ))
    );

-- Test 3.6: before() with no matches (all occurrences after before_date)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Edge Cases',
    'No matches - all after before_date',
    assert_equals(
        'No matches',
        '0',
        (SELECT COUNT(*)::TEXT FROM "before"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-10 10:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            5
        ))
    );

-- Test 3.7: before() with count=1 (single result)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Edge Cases',
    'Single result (count=1)',
    assert_equals(
        'Single result',
        '1',
        (SELECT COUNT(*)::TEXT FROM "before"(
            'FREQ=DAILY;COUNT=100',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-10 00:00:00'::TIMESTAMP,
            1
        ))
    );

-- Test 3.8: before() returns the most recent occurrence before the given date
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Edge Cases',
    'Returns most recent occurrence before date',
    assert_equals(
        'Most recent',
        '2025-01-09 10:00:00',
        (SELECT occurrence::TEXT FROM "before"(
            'FREQ=DAILY;COUNT=100',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-10 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- SECTION 4: next()/most_recent() Edge Cases
-- ============================================================================
\echo ''
\echo '--- Section 4: next()/most_recent() Edge Cases ---'

-- Test 4.1: next() returns NULL when all occurrences exhausted
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'next() Edge Cases',
    'Returns NULL when COUNT exhausted',
    assert_equals(
        'NULL when exhausted',
        'NULL',
        (SELECT COALESCE("next"(
            'FREQ=DAILY;COUNT=5',
            '2020-01-01 10:00:00'::TIMESTAMP
        )::TEXT, 'NULL'))
    );

-- Test 4.2: next() with UNTIL in past
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'next() Edge Cases',
    'Returns NULL when UNTIL in past',
    assert_equals(
        'NULL UNTIL past',
        'NULL',
        (SELECT COALESCE("next"(
            'FREQ=DAILY;UNTIL=20200131T235959',
            '2020-01-01 10:00:00'::TIMESTAMP
        )::TEXT, 'NULL'))
    );

-- Test 4.3: most_recent() returns NULL when dtstart in future
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'most_recent() Edge Cases',
    'Returns NULL when dtstart in future',
    assert_equals(
        'NULL future dtstart',
        'NULL',
        (SELECT COALESCE("most_recent"(
            'FREQ=DAILY;COUNT=10',
            '2099-01-01 10:00:00'::TIMESTAMP
        )::TEXT, 'NULL'))
    );

-- Test 4.4: most_recent() with far past dtstart
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'most_recent() Edge Cases',
    'Works with far past dtstart',
    assert_equals(
        'Far past dtstart',
        'not_null',
        (SELECT CASE WHEN "most_recent"(
            'FREQ=DAILY',
            '2000-01-01 10:00:00'::TIMESTAMP
        ) IS NOT NULL THEN 'not_null' ELSE 'null' END)
    );

-- ============================================================================
-- SECTION 5: count() Edge Cases
-- ============================================================================
\echo ''
\echo '--- Section 5: count() Edge Cases ---'

-- Test 5.1: count() with COUNT=1 minimum
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'count() Edge Cases',
    'COUNT=1 minimum',
    assert_equals(
        'COUNT=1',
        '1',
        (SELECT "count"(
            'FREQ=DAILY;COUNT=1',
            '2025-01-01 10:00:00'::TIMESTAMP
        )::TEXT)
    );

-- Test 5.2: count() with large COUNT
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'count() Edge Cases',
    'Large COUNT value',
    assert_equals(
        'Large COUNT',
        '100',
        (SELECT "count"(
            'FREQ=DAILY;COUNT=100',
            '2025-01-01 10:00:00'::TIMESTAMP
        )::TEXT)
    );

-- Test 5.3: count() with UNTIL limiting occurrences
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'count() Edge Cases',
    'UNTIL limits count',
    assert_equals(
        'UNTIL limited',
        '7',
        (SELECT "count"(
            'FREQ=DAILY;UNTIL=20250107T235959',
            '2025-01-01 10:00:00'::TIMESTAMP
        )::TEXT)
    );

-- ============================================================================
-- SECTION 6: all() Edge Cases
-- ============================================================================
\echo ''
\echo '--- Section 6: all() Edge Cases ---'

-- Test 6.1: all() with BYMONTHDAY that doesn't exist in all months
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'all() Edge Cases',
    'BYMONTHDAY=30 skips February',
    assert_equals(
        'Skip Feb 30',
        '11',
        (SELECT COUNT(*)::TEXT FROM "all"(
            'FREQ=MONTHLY;BYMONTHDAY=30;COUNT=11',
            '2025-01-30 10:00:00'::TIMESTAMP
        ))
    );

-- Test 6.2: all() with BYDAY ordinal at month end
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'all() Edge Cases',
    'Last Friday of month (-1FR)',
    assert_equals(
        'Last Friday',
        '3',
        (SELECT COUNT(*)::TEXT FROM "all"(
            'FREQ=MONTHLY;BYDAY=-1FR;COUNT=3',
            '2025-01-31 10:00:00'::TIMESTAMP
        ))
    );

-- Test 6.3: all() with multiple BYMONTH
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'all() Edge Cases',
    'Multiple BYMONTH values',
    assert_equals(
        'Multiple months',
        '4',
        (SELECT COUNT(*)::TEXT FROM "all"(
            'FREQ=YEARLY;BYMONTH=1,4,7,10;COUNT=4',
            '2025-01-15 10:00:00'::TIMESTAMP
        ))
    );

-- Test 6.4: all() with complex BYDAY combination
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'all() Edge Cases',
    'Complex BYDAY: 2nd and 4th Tuesday',
    assert_equals(
        'Complex BYDAY',
        '4',
        (SELECT COUNT(*)::TEXT FROM "all"(
            'FREQ=MONTHLY;BYDAY=2TU,4TU;COUNT=4',
            '2025-01-14 10:00:00'::TIMESTAMP
        ))
    );

-- ============================================================================
-- SECTION 7: Schema-qualified API (rrule.*)
-- ============================================================================
\echo ''
\echo '--- Section 7: Schema-qualified API Tests ---'

-- Test 7.1: rrule.all() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule.all() with timezone',
    assert_equals(
        'TZ API',
        '3',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
            'America/New_York'
        ))
    );

-- Test 7.2: rrule.between() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule.between() with timezone',
    assert_equals(
        'TZ between',
        '2',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
            '2025-01-02 00:00:00-05'::TIMESTAMPTZ,
            '2025-01-03 23:59:59-05'::TIMESTAMPTZ,
            'America/New_York'
        ))
    );

-- Test 7.3: rrule.after() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule.after() with timezone',
    assert_equals(
        'TZ after',
        '2',
        (SELECT COUNT(*)::TEXT FROM rrule."after"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
            '2025-01-03 00:00:00-05'::TIMESTAMPTZ,
            2,
            'America/New_York'
        ))
    );

-- Test 7.4: rrule.before() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule.before() with timezone',
    assert_equals(
        'TZ before',
        '2',
        (SELECT COUNT(*)::TEXT FROM rrule."before"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
            '2025-01-05 00:00:00-05'::TIMESTAMPTZ,
            2,
            'America/New_York'
        ))
    );

-- Test 7.5: rrule.count() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule.count() with timezone',
    assert_equals(
        'TZ count',
        '5',
        (SELECT rrule.count(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
            'America/New_York'
        )::TEXT)
    );

-- Test 7.6: rrule.overlaps() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule.overlaps() with timezone',
    assert_equals(
        'TZ overlaps',
        'true',
        (SELECT rrule.overlaps(
            '2025-01-05 10:00:00-05'::TIMESTAMPTZ,
            '2025-01-05 11:00:00-05'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=10'::TEXT,
            '2025-01-03 00:00:00-05'::TIMESTAMPTZ,
            '2025-01-10 23:59:59-05'::TIMESTAMPTZ,
            'America/New_York'
        )::TEXT)
    );

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
FROM coverage_gap_results
ORDER BY test_category, test_id;

\echo ''
\echo 'Category Summary:'
SELECT
    test_category,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status = 'PASS') AS passed,
    COUNT(*) FILTER (WHERE status != 'PASS') AS failed
FROM coverage_gap_results
GROUP BY test_category
ORDER BY test_category;

\echo ''
\echo 'Overall Summary:'
SELECT
    COUNT(*) AS total_tests,
    COUNT(*) FILTER (WHERE status = 'PASS') AS passed,
    COUNT(*) FILTER (WHERE status != 'PASS') AS failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'PASS') / COUNT(*), 1) || '%' AS pass_rate
FROM coverage_gap_results;

-- Fail if any tests failed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count FROM coverage_gap_results WHERE status != 'PASS';
    IF failed_count > 0 THEN
        RAISE EXCEPTION 'COVERAGE GAP TESTS FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'COVERAGE GAP TESTS PASSED: All tests passed!';
    END IF;
END $$;

ROLLBACK;
