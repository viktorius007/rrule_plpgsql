/**
 * Coverage Gap Tests
 *
 * This file contains tests to achieve 100% coverage of the public API functions.
 * It specifically targets gaps identified in the existing test suite:
 *
 * 1. rrule."overlaps"() - Comprehensive edge case testing
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

-- Test results table
CREATE TEMP TABLE coverage_gap_results (
    test_id SERIAL PRIMARY KEY,
    test_category TEXT,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '==================================================================='
\echo 'COVERAGE GAP TESTS'
\echo '==================================================================='
\echo ''

-- ============================================================================
-- SECTION 1: rrule."overlaps"() Comprehensive Tests
-- ============================================================================
\echo '--- Section 1: rrule."overlaps"() Comprehensive Tests ---'

-- Test 1.1: Event entirely within query range (should return TRUE)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule."overlaps"() Scenarios',
    'Event entirely within range',
    assert_equals(
        'Event within range',
        'true',
        (SELECT rrule."overlaps"(
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
    'rrule."overlaps"() Scenarios',
    'Event overlaps range start',
    assert_equals(
        'Overlap at start',
        'true',
        (SELECT rrule."overlaps"(
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
    'rrule."overlaps"() Scenarios',
    'Event overlaps range end',
    assert_equals(
        'Overlap at end',
        'true',
        (SELECT rrule."overlaps"(
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
    'rrule."overlaps"() Scenarios',
    'Event spans entire range',
    assert_equals(
        'Spans range',
        'true',
        (SELECT rrule."overlaps"(
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
    'rrule."overlaps"() Scenarios',
    'No overlap - event before range',
    assert_equals(
        'No overlap before',
        'false',
        (SELECT rrule."overlaps"(
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
    'rrule."overlaps"() Scenarios',
    'No overlap - event after range',
    assert_equals(
        'No overlap after',
        'false',
        (SELECT rrule."overlaps"(
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
    'rrule."overlaps"() Scenarios',
    'Exact boundary at range start',
    assert_equals(
        'Boundary start',
        'true',
        (SELECT rrule."overlaps"(
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
    'rrule."overlaps"() Scenarios',
    'Exact boundary at range end',
    assert_equals(
        'Boundary end',
        'true',
        (SELECT rrule."overlaps"(
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
    'rrule."overlaps"() Scenarios',
    'NULL RRULE - single event within range',
    assert_equals(
        'NULL RRULE within',
        'true',
        (SELECT rrule."overlaps"(
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
    'rrule."overlaps"() Scenarios',
    'NULL RRULE - single event outside range',
    assert_equals(
        'NULL RRULE outside',
        'false',
        (SELECT rrule."overlaps"(
            '2025-02-15 10:00:00+00'::TIMESTAMPTZ,
            '2025-02-15 11:00:00+00'::TIMESTAMPTZ,
            NULL::TEXT,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.11: rrule."overlaps"() with WEEKLY frequency
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule."overlaps"() Frequencies',
    'WEEKLY frequency overlap',
    assert_equals(
        'WEEKLY overlap',
        'true',
        (SELECT rrule."overlaps"(
            '2025-01-06 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-06 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=WEEKLY;BYDAY=MO;COUNT=10'::TEXT,
            '2025-01-13 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.12: rrule."overlaps"() with MONTHLY frequency
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule."overlaps"() Frequencies',
    'MONTHLY frequency overlap',
    assert_equals(
        'MONTHLY overlap',
        'true',
        (SELECT rrule."overlaps"(
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-15 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=6'::TEXT,
            '2025-03-01 00:00:00+00'::TIMESTAMPTZ,
            '2025-03-31 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.13: rrule."overlaps"() with YEARLY frequency
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule."overlaps"() Frequencies',
    'YEARLY frequency overlap',
    assert_equals(
        'YEARLY overlap',
        'true',
        (SELECT rrule."overlaps"(
            '2025-07-04 10:00:00+00'::TIMESTAMPTZ,
            '2025-07-04 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=YEARLY;BYMONTH=7;BYMONTHDAY=4;COUNT=5'::TEXT,
            '2026-07-01 00:00:00+00'::TIMESTAMPTZ,
            '2026-07-31 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.14: rrule."overlaps"() with BYSETPOS
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule."overlaps"() Complex',
    'BYSETPOS pattern overlap',
    assert_equals(
        'BYSETPOS overlap',
        'true',
        (SELECT rrule."overlaps"(
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=12'::TEXT,
            '2025-03-01 00:00:00+00'::TIMESTAMPTZ,
            '2025-03-31 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.15: rrule."overlaps"() with zero-duration event (point in time)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule."overlaps"() Edge Cases',
    'Zero-duration event',
    assert_equals(
        'Zero duration',
        'true',
        (SELECT rrule."overlaps"(
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=5'::TEXT,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 1.16: Inverted event interval (dtend < dtstart)
-- When dtend precedes dtstart, overlaps() still finds recurrence occurrences in the query range.
-- The function checks whether any occurrence falls within [min, max], independent of dtend ordering.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule."overlaps"() Edge Cases',
    'Inverted event interval (dtend < dtstart)',
    assert_equals(
        'Inverted dtend/dtstart',
        'true',
        (SELECT rrule."overlaps"(
            '2025-01-15 11:00:00+00'::TIMESTAMPTZ,
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
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
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
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
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
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
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
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 11:00:00'::TIMESTAMP,
            '2025-01-03 11:00:00'::TIMESTAMP
        ))
    );

-- Test 2.5: between() with boundary-exclusive default (inc=false)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Edge Cases',
    'Boundary exclusive default (inc=false)',
    assert_equals(
        'Boundary exclusive',
        '0',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            FALSE
        ))
    );

-- Test 2.6: between() with inc=true includes boundaries
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Edge Cases',
    'Boundary inclusive (inc=true)',
    assert_equals(
        'Boundary inclusive',
        '2',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            TRUE
        ))
    );

-- Test 2.7: Large range with UNTIL
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Edge Cases',
    'Large range with UNTIL limit',
    assert_equals(
        'Large range UNTIL',
        '5',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=DAILY;UNTIL=20250105T100000Z',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-12-31 23:59:59'::TIMESTAMP
        ))
    );

-- Test 2.8: between() with WEEKLY pattern
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Frequencies',
    'WEEKLY pattern in 2-week range',
    assert_equals(
        'WEEKLY between',
        '2',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=WEEKLY;BYDAY=MO;COUNT=10',
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-06 00:00:00'::TIMESTAMP,
            '2025-01-19 23:59:59'::TIMESTAMP
        ))
    );

-- Test 2.9: between() with MONTHLY pattern spanning partial months
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Frequencies',
    'MONTHLY pattern partial months',
    assert_equals(
        'MONTHLY between',
        '2',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=12',
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-01-10 00:00:00'::TIMESTAMP,
            '2025-02-20 23:59:59'::TIMESTAMP
        ))
    );

-- Test 2.10: Inverted range (start > end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Edge Cases',
    'Inverted range (start > end)',
    assert_equals(
        'Inverted range',
        '0',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-10 00:00:00'::TIMESTAMP,
            '2025-01-03 00:00:00'::TIMESTAMP
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
        (SELECT COUNT(*)::TEXT FROM rrule."after"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2024-12-01 00:00:00+00'::TIMESTAMPTZ,
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
        (SELECT COUNT(*)::TEXT FROM rrule."after"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-02-01 00:00:00+00'::TIMESTAMPTZ,
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
        (SELECT COUNT(*)::TEXT FROM rrule."after"(
            'FREQ=DAILY;COUNT=100',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-05 00:00:00+00'::TIMESTAMPTZ,
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
        (SELECT occurrence::TEXT FROM rrule."after"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 3.5: after() with inc=true includes the boundary occurrence
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'after() Edge Cases',
    'Inclusive boundary (inc=true)',
    assert_equals(
        'After inclusive',
        '2025-01-03 10:00:00',
        (SELECT occurrence::TEXT FROM rrule."after"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            TRUE
        ) AS occurrence)
    );

-- Test 3.6: before() when count exceeds available occurrences
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Edge Cases',
    'Count exceeds available occurrences',
    assert_equals(
        'Exceeds available',
        '3',
        (SELECT COUNT(*)::TEXT FROM rrule."before"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-02-01 00:00:00+00'::TIMESTAMPTZ,
            10  -- Request 10 but only 3 exist
        ))
    );

-- Test 3.7: before() with no matches (all occurrences after before_date)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Edge Cases',
    'No matches - all after before_date',
    assert_equals(
        'No matches',
        '0',
        (SELECT COUNT(*)::TEXT FROM rrule."before"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-10 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-01 00:00:00+00'::TIMESTAMPTZ,
            5
        ))
    );

-- Test 3.8: before() with count=1 (single result)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Edge Cases',
    'Single result (count=1)',
    assert_equals(
        'Single result',
        '1',
        (SELECT COUNT(*)::TEXT FROM rrule."before"(
            'FREQ=DAILY;COUNT=100',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            1
        ))
    );

-- Test 3.9: before() returns the most recent occurrence before the given date
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Edge Cases',
    'Returns most recent occurrence before date',
    assert_equals(
        'Most recent',
        '2025-01-09 10:00:00',
        (SELECT occurrence::TEXT FROM rrule."before"(
            'FREQ=DAILY;COUNT=100',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-10 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 3.10: before() with inc=true includes the boundary occurrence
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Edge Cases',
    'Inclusive boundary (inc=true)',
    assert_equals(
        'Before inclusive',
        '2025-01-10 10:00:00',
        (SELECT occurrence::TEXT FROM rrule."before"(
            'FREQ=DAILY;COUNT=100',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-10 10:00:00'::TIMESTAMP,
            TRUE
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
        (SELECT COALESCE(rrule."next"(
            'FREQ=DAILY;COUNT=5',
            '2020-01-01 10:00:00'::TIMESTAMP,
            '2025-06-01 00:00:00'::TIMESTAMP
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
        (SELECT COALESCE(rrule."next"(
            'FREQ=DAILY;UNTIL=20200131T235959Z',
            '2020-01-01 10:00:00'::TIMESTAMP,
            '2025-06-01 00:00:00'::TIMESTAMP
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
        (SELECT COALESCE(rrule."most_recent"(
            'FREQ=DAILY;COUNT=10',
            '2099-01-01 10:00:00'::TIMESTAMP
        )::TEXT, 'NULL'))
    );

-- Test 4.4: most_recent() returns correct occurrence for known reference time
-- Daily from Jan 1 at 10:00 AM; reference = June 16 at 8:00 AM
-- Most recent daily occurrence before June 16 8:00 AM is June 15 10:00 AM
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'most_recent() Edge Cases',
    'Returns correct occurrence for known reference time',
    assert_equals(
        'Exact most_recent',
        '2025-06-15 10:00:00',
        (SELECT rrule."most_recent"(
            'FREQ=DAILY',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-06-16 08:00:00'::TIMESTAMP
        )::TEXT)
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
        (SELECT rrule."count"(
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
        (SELECT rrule."count"(
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
        (SELECT rrule."count"(
            'FREQ=DAILY;UNTIL=20250107T235959Z',
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
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
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
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
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
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
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
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=2TU,4TU;COUNT=4',
            '2025-01-14 10:00:00'::TIMESTAMP
        ))
    );

-- ============================================================================
-- SECTION 7: Schema-qualified API (rrule.*)
-- ============================================================================
\echo ''
\echo '--- Section 7: Schema-qualified API Tests ---'

-- Test 7.1: rrule."all"() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule."all"() with timezone',
    assert_equals(
        'TZ API',
        '3',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
            'America/New_York'
        ))
    );

-- Test 7.2: rrule."between"() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule."between"() with timezone',
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

-- Test 7.3: rrule."after"() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule."after"() with timezone',
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

-- Test 7.4: rrule."before"() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule."before"() with timezone',
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

-- Test 7.5: rrule."count"() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule."count"() with timezone',
    assert_equals(
        'TZ count',
        '5',
        (SELECT rrule."count"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
            'America/New_York'
        )::TEXT)
    );

-- Test 7.6: rrule."overlaps"() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule."overlaps"() with timezone',
    assert_equals(
        'TZ overlaps',
        'true',
        (SELECT rrule."overlaps"(
            '2025-01-05 10:00:00-05'::TIMESTAMPTZ,
            '2025-01-05 11:00:00-05'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=10'::TEXT,
            '2025-01-03 00:00:00-05'::TIMESTAMPTZ,
            '2025-01-10 23:59:59-05'::TIMESTAMPTZ,
            'America/New_York'
        )::TEXT)
    );

-- ============================================================================
-- SECTION 8: Negative BYYEARDAY/BYMONTHDAY Filter Tests
-- ============================================================================
\echo ''
\echo '--- Section 8: Negative BYYEARDAY/BYMONTHDAY Filter Tests ---'

-- Test 8.1: Negative BYYEARDAY=-1 on YEARLY (last day of year = Dec 31)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'Negative BYYEARDAY=-1 on YEARLY (last day of year)',
    assert_equals(
        'YEARLY BYYEARDAY=-1',
        '2025-12-31 00:00:00',
        (SELECT occurrence::TEXT FROM rrule."all"(
          'FREQ=YEARLY;BYYEARDAY=-1;COUNT=3',
          '2025-01-01'::TIMESTAMP
        ) AS occurrence LIMIT 1)
    );

-- Test 8.2: Negative BYYEARDAY=-31 on YEARLY (Dec 1 in a non-leap year)
-- BYYEARDAY=-31 = day 335 in a 365-day year = Dec 1
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'Negative BYYEARDAY=-31 on YEARLY',
    assert_equals(
        'YEARLY BYYEARDAY=-31',
        '3',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
          'FREQ=YEARLY;BYYEARDAY=-31;COUNT=3',
          '2025-01-01'::TIMESTAMP
        ))
    );

-- Test 8.3: Multiple negative BYYEARDAY values on YEARLY
-- BYYEARDAY=-1,-2 should generate Dec 31 and Dec 30
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'Multiple negative BYYEARDAY values (-1,-2)',
    assert_equals(
        'YEARLY BYYEARDAY=-1,-2',
        '2',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
          'FREQ=YEARLY;BYYEARDAY=-1,-2',
          '2025-01-01'::TIMESTAMP,
          '2025-12-01'::TIMESTAMP,
          '2025-12-31'::TIMESTAMP,
          TRUE
        ))
    );

-- Test 8.4: Negative BYMONTHDAY=-1 as filter on DAILY
-- Should match the last day of each month (inc=true to include Dec 31)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'Negative BYMONTHDAY=-1 as DAILY filter',
    assert_equals(
        'DAILY BYMONTHDAY=-1',
        '12',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
          'FREQ=DAILY;BYMONTHDAY=-1',
          '2025-01-01'::TIMESTAMP,
          '2025-01-01'::TIMESTAMP,
          '2025-12-31'::TIMESTAMP,
          TRUE
        ))
    );

-- Test 8.5: BYSETPOS with YEARLY (first Monday of each year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'BYSETPOS with YEARLY (first Monday of year)',
    assert_equals(
        'YEARLY BYSETPOS=1',
        '3',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
          'FREQ=YEARLY;BYDAY=MO;BYSETPOS=1;COUNT=3',
          '2025-01-01'::TIMESTAMP
        ))
    );

-- Test 8.6: Negative BYMONTHDAY=-1 on MONTHLY verifies correct dates
-- Last day of Jan=31, Feb=28, Mar=31
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'Negative BYMONTHDAY=-1 on MONTHLY returns correct dates',
    assert_equals(
        'MONTHLY BYMONTHDAY=-1 dates',
        '2025-01-31 00:00:00',
        (SELECT occurrence::TEXT FROM rrule."all"(
          'FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3',
          '2025-01-01'::TIMESTAMP
        ) AS occurrence LIMIT 1)
    );

-- Test 8.7: Negative BYMONTHDAY=-2 on MONTHLY (second to last day of month)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'Negative BYMONTHDAY=-2 on MONTHLY',
    assert_equals(
        'MONTHLY BYMONTHDAY=-2',
        '12',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
          'FREQ=MONTHLY;BYMONTHDAY=-2',
          '2025-01-01'::TIMESTAMP,
          '2025-01-01'::TIMESTAMP,
          '2025-12-31'::TIMESTAMP
        ))
    );

-- ============================================================================
-- SECTION 9: Deduplication Tests
-- ============================================================================
\echo ''
\echo '--- Section 9: Deduplication Tests ---'

-- Test 9.1: BYDAY+BYMONTHDAY deduplication when both match same date
-- January 6, 2025 is a Monday. BYDAY=MO and BYMONTHDAY=6 both match it.
-- The result should have no duplicate dates.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Deduplication',
    'BYDAY+BYMONTHDAY produce unique dates',
    assert_equals(
        'BYDAY+BYMONTHDAY dedup',
        'true',
        (SELECT (COUNT(*) = COUNT(DISTINCT occurrence))::TEXT FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=MO;BYMONTHDAY=6;COUNT=12',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- SECTION 10: Duplicate BYxxx Input Tests
-- ============================================================================
\echo ''
\echo '--- Section 10: Duplicate BYxxx Input Tests ---'

-- Test 10.1: BYDAY=MO,MO should produce same result as BYDAY=MO (no duplicate dates)
-- Parser deduplicates BYxxx arrays at parse time, so MO,MO becomes ARRAY['MO'].
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Duplicate BYxxx Inputs',
    'BYDAY=MO,MO produces unique dates (deduplicated)',
    assert_equals(
        'BYDAY=MO,MO dedup',
        'true',
        (SELECT (COUNT(*) = COUNT(DISTINCT occurrence))::TEXT FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO,MO;COUNT=5',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 10.2: BYDAY=MO,MO produces same count as BYDAY=MO
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Duplicate BYxxx Inputs',
    'BYDAY=MO,MO same count as BYDAY=MO',
    assert_equals(
        'BYDAY duplicate count',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;COUNT=5',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) AS occurrence),
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO,MO;COUNT=5',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 10.3: BYMONTHDAY=1,1 should not produce duplicate occurrences
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Duplicate BYxxx Inputs',
    'BYMONTHDAY=1,1 produces unique dates (deduplicated)',
    assert_equals(
        'BYMONTHDAY=1,1 dedup',
        'true',
        (SELECT (COUNT(*) = COUNT(DISTINCT occurrence))::TEXT FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=1,1;COUNT=6',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 10.4: BYMONTH=1,1 should not produce duplicate occurrences
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Duplicate BYxxx Inputs',
    'BYMONTH=1,1 produces unique dates (deduplicated)',
    assert_equals(
        'BYMONTH=1,1 dedup',
        'true',
        (SELECT (COUNT(*) = COUNT(DISTINCT occurrence))::TEXT FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=1,1;COUNT=3',
            '2025-01-15 10:00:00'::TIMESTAMP
        ) AS occurrence)
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

-- ==========================================
-- Section 11: Review-Driven Coverage Gap Tests
-- Tests for edge cases identified by third-party code review
-- ==========================================
\echo '--- Section 11: Review-Driven Coverage Gap Tests ---'

-- Test 11.1: overlaps() with maxdate mid-period should not false-positive
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.1: overlaps() no false positive past maxdate',
    assert_equals(
        'overlaps maxdate boundary',
        'false',
        (SELECT rrule."overlaps"(
            '2025-01-20 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=MONTHLY',
            '2025-02-01 00:00:00+00'::TIMESTAMPTZ,
            '2025-02-15 00:00:00+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 11.2: overlaps() with sparse rule over wide range
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.2: overlaps() finds sparse rule occurrence',
    assert_equals(
        'overlaps sparse rule',
        'true',
        (SELECT rrule."overlaps"(
            '2025-01-31 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-31 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=MONTHLY;BYMONTHDAY=31',
            '2025-03-01 00:00:00+00'::TIMESTAMPTZ,
            '2025-12-31 00:00:00+00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test 11.3: BYYEARDAY duplicate values produce single occurrence per year
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.3: BYYEARDAY duplicate values deduplicated',
    assert_equals(
        'BYYEARDAY dedup',
        '3',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=YEARLY;BYYEARDAY=100,100;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ))
    );

-- Test 11.4: BYWEEKNO duplicate values produce single occurrence set
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.4: BYWEEKNO duplicate values deduplicated',
    assert_equals(
        'BYWEEKNO dedup',
        '3',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=YEARLY;BYWEEKNO=1,1;BYDAY=MO;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ))
    );

-- Test 11.5: BYDAY trailing comma does not produce phantom Sunday
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.5: BYDAY trailing comma no phantom Sunday',
    assert_equals(
        'BYDAY trailing comma',
        (SELECT array_agg(occurrence ORDER BY occurrence)::TEXT
         FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,TU;COUNT=2', '2025-01-06 10:00:00'::TIMESTAMP) AS occurrence),
        (SELECT array_agg(occurrence ORDER BY occurrence)::TEXT
         FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,TU,;COUNT=2', '2025-01-06 10:00:00'::TIMESTAMP) AS occurrence)
    );

-- Test 11.6: SKIP=FORWARD with YEARLY+BYMONTH on day 30 (February)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.6: SKIP=FORWARD YEARLY+BYMONTH=2 day 30',
    assert_equals(
        'SKIP FORWARD yearly bymonth',
        '2025-03-01 10:00:00',
        (SELECT (array_agg(occurrence ORDER BY occurrence))[1]::TEXT
         FROM rrule."between"(
             'FREQ=YEARLY;BYMONTH=2;SKIP=FORWARD;RSCALE=GREGORIAN',
             '2025-01-30 10:00:00'::TIMESTAMP,
             '2025-01-01 00:00:00'::TIMESTAMP,
             '2026-01-01 00:00:00'::TIMESTAMP
         ) AS occurrence)
    );

-- Test 11.7: SKIP=BACKWARD with YEARLY+BYMONTH on day 30 (February)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.7: SKIP=BACKWARD YEARLY+BYMONTH=2 day 30',
    assert_equals(
        'SKIP BACKWARD yearly bymonth',
        '2025-02-28 10:00:00',
        (SELECT (array_agg(occurrence ORDER BY occurrence))[1]::TEXT
         FROM rrule."between"(
             'FREQ=YEARLY;BYMONTH=2;SKIP=BACKWARD;RSCALE=GREGORIAN',
             '2025-01-30 10:00:00'::TIMESTAMP,
             '2025-01-01 00:00:00'::TIMESTAMP,
             '2026-01-01 00:00:00'::TIMESTAMP
         ) AS occurrence)
    );

-- Test 11.8: SKIP=OMIT with YEARLY+BYMONTH on day 30 (February)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.8: SKIP=OMIT YEARLY+BYMONTH=2 day 30',
    assert_equals(
        'SKIP OMIT yearly bymonth',
        '0',
        (SELECT COUNT(*)::TEXT
         FROM rrule."between"(
             'FREQ=YEARLY;BYMONTH=2;SKIP=OMIT;RSCALE=GREGORIAN',
             '2025-01-30 10:00:00'::TIMESTAMP,
             '2025-01-01 00:00:00'::TIMESTAMP,
             '2026-01-01 00:00:00'::TIMESTAMP
         ) AS occurrence)
    );

-- Test 11.9: SKIP=FORWARD with YEARLY+BYMONTH on day 29 (non-leap year February)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.9: SKIP=FORWARD YEARLY+BYMONTH=2 day 29 non-leap',
    assert_equals(
        'SKIP FORWARD day 29 non-leap',
        '2025-03-01 10:00:00',
        (SELECT (array_agg(occurrence ORDER BY occurrence))[1]::TEXT
         FROM rrule."between"(
             'FREQ=YEARLY;BYMONTH=2;SKIP=FORWARD;RSCALE=GREGORIAN',
             '2025-01-29 10:00:00'::TIMESTAMP,
             '2025-01-01 00:00:00'::TIMESTAMP,
             '2026-01-01 00:00:00'::TIMESTAMP
         ) AS occurrence)
    );

-- ================================================================================================================
-- before() CORRECTNESS FOR >1000 OCCURRENCES
-- ================================================================================================================

\echo ''
\echo '=================================================='
\echo 'Testing before() correctness for >1000 occurrences'
\echo '=================================================='

-- TIMESTAMP API: FREQ=DAILY from 2020-01-01, before_date 2025-01-01 (~1826 occurrences)
-- The correct answer is 2024-12-31, not the 1000th occurrence (2022-09-27)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Correctness',
    'Test 12.1: TIMESTAMP before() with >1000 occurrences returns correct last occurrence',
    assert_equals(
        'before() >1000 occurrences',
        '2024-12-31 00:00:00',
        (SELECT rrule."before"(
            'FREQ=DAILY',
            '2020-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP
        ))::TEXT
    );

-- TIMESTAMPTZ API: Same test with timezone
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Correctness',
    'Test 12.2: TIMESTAMPTZ before() with >1000 occurrences returns correct last occurrence',
    assert_equals(
        'before() >1000 occurrences (TZ)',
        '2024-12-31 05:00:00+00',
        (SELECT (rrule."before"(
            'FREQ=DAILY',
            '2020-01-01 00:00:00-05'::TIMESTAMPTZ,
            '2025-01-01 00:00:00-05'::TIMESTAMPTZ,
            1,
            'America/New_York'
        ))::TEXT)
    );

-- ============================================================================
-- SECTION 13: Additional Coverage Gap Tests
-- ============================================================================
\echo ''
\echo '--- Section 13: Additional Coverage Gap Tests ---'

-- Test 13.1: YEARLY INTERVAL=4 with leap year start (drift prevention)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY INTERVAL>1',
    'Test 13.1: YEARLY INTERVAL=4 from leap year Feb 29',
    assert_equals(
        'YEARLY INTERVAL=4 leap year',
        '{"2024-02-29 00:00:00","2028-02-29 00:00:00","2032-02-29 00:00:00"}',
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=YEARLY;INTERVAL=4;COUNT=3',
            '2024-02-29 00:00:00'::TIMESTAMP
        ) d)::TEXT
    );

-- Test 13.2: YEARLY INTERVAL=2 with BYMONTH (biennial)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY INTERVAL>1',
    'Test 13.2: YEARLY INTERVAL=2 BYMONTH=6',
    assert_equals(
        'Biennial June',
        '{"2025-06-15 00:00:00","2027-06-15 00:00:00","2029-06-15 00:00:00"}',
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=YEARLY;INTERVAL=2;BYMONTH=6;COUNT=3',
            '2025-06-15 00:00:00'::TIMESTAMP
        ) d)::TEXT
    );

-- Test 13.3: MONTHLY INTERVAL=2 with SKIP=BACKWARD
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY INTERVAL>1 + SKIP',
    'Test 13.3: MONTHLY INTERVAL=2 SKIP=BACKWARD from Jan 31',
    assert_equals(
        'Bi-monthly SKIP=BACKWARD',
        '{"2025-01-31 00:00:00","2025-03-31 00:00:00","2025-05-31 00:00:00","2025-07-31 00:00:00","2025-09-30 00:00:00","2025-11-30 00:00:00"}',
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=MONTHLY;INTERVAL=2;SKIP=BACKWARD;RSCALE=GREGORIAN;COUNT=6',
            '2025-01-31 00:00:00'::TIMESTAMP
        ) d)::TEXT
    );

-- Test 13.4: MONTHLY INTERVAL=2 with SKIP=FORWARD
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY INTERVAL>1 + SKIP',
    'Test 13.4: MONTHLY INTERVAL=2 SKIP=FORWARD from Jan 31',
    assert_equals(
        'Bi-monthly SKIP=FORWARD',
        '{"2025-01-31 00:00:00","2025-03-31 00:00:00","2025-05-31 00:00:00","2025-07-31 00:00:00","2025-10-01 00:00:00","2025-12-31 00:00:00"}',
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=MONTHLY;INTERVAL=2;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=6',
            '2025-01-31 00:00:00'::TIMESTAMP
        ) d)::TEXT
    );

-- Test 13.5: WEEKLY + BYMONTH interaction (Mondays in January)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'WEEKLY + BYMONTH',
    'Test 13.5: WEEKLY BYDAY=MO BYMONTH=1 (January Mondays)',
    assert_equals(
        'January Mondays',
        '{"2025-01-06 00:00:00","2025-01-13 00:00:00","2025-01-20 00:00:00","2025-01-27 00:00:00"}',
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;BYMONTH=1;COUNT=4',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) d)::TEXT
    );

-- Test 13.6: TIMESTAMPTZ next() with explicit timezone param
-- Pass explicit reference_time to avoid NOW() dependency (TESTING_STANDARDS: fixed timestamps)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'TIMESTAMPTZ next()/most_recent()',
    'Test 13.6: next() with explicit timezone parameter',
    assert_equals(
        'TZ next()',
        '2025-01-02 05:00:00+00',
        (SELECT rrule."next"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 00:00:00-05'::TIMESTAMPTZ,
            'America/New_York',
            '2025-01-01 00:00:00-05'::TIMESTAMPTZ
        ))::TEXT
    );

-- Test 13.7: TIMESTAMPTZ most_recent() with explicit timezone param
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'TIMESTAMPTZ next()/most_recent()',
    'Test 13.7: most_recent() with explicit timezone parameter',
    assert_equals(
        'TZ most_recent()',
        '2025-01-05 05:00:00+00',
        (SELECT rrule."most_recent"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 00:00:00-05'::TIMESTAMPTZ,
            'America/New_York',
            '2025-01-06 00:00:00-05'::TIMESTAMPTZ
        ))::TEXT
    );

-- Test 13.8: FREQ=HOURLY in standard install should be rejected
-- (Skip this test when sub-day frequencies are enabled)
DO $$
DECLARE
    test_passed BOOLEAN := FALSE;
    subday_enabled BOOLEAN := FALSE;
BEGIN
    -- Detect if sub-day frequencies are enabled by checking for hourly_set function
    SELECT EXISTS(
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'rrule' AND p.proname = 'hourly_set'
    ) INTO subday_enabled;

    IF subday_enabled THEN
        -- Sub-day is enabled, skip this test (it only applies to standard install)
        INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
            'Sub-day rejection in standard install',
            'Test 13.8: FREQ=HOURLY rejected in standard install',
            'PASS'
        );
    ELSE
        BEGIN
            PERFORM rrule."all"('FREQ=HOURLY;COUNT=3', '2025-01-01 00:00:00'::TIMESTAMP);
        EXCEPTION
            WHEN raise_exception THEN
                IF SQLERRM LIKE '%not supported in standard installation%' OR SQLERRM LIKE '%Unsupported frequency%' THEN
                    test_passed := TRUE;
                END IF;
        END;

        INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
            'Sub-day rejection in standard install',
            'Test 13.8: FREQ=HOURLY rejected in standard install',
            CASE WHEN test_passed THEN 'PASS' ELSE 'FAIL' END
        );
    END IF;
END $$;

-- Test 13.9: FREQ=MINUTELY in standard install should be rejected
-- (Skip this test when sub-day frequencies are enabled)
DO $$
DECLARE
    test_passed BOOLEAN := FALSE;
    subday_enabled BOOLEAN := FALSE;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'rrule' AND p.proname = 'minutely_set'
    ) INTO subday_enabled;

    IF subday_enabled THEN
        INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
            'Sub-day rejection in standard install',
            'Test 13.9: FREQ=MINUTELY rejected in standard install',
            'PASS'
        );
    ELSE
        BEGIN
            PERFORM rrule."all"('FREQ=MINUTELY;COUNT=3', '2025-01-01 00:00:00'::TIMESTAMP);
        EXCEPTION
            WHEN raise_exception THEN
                IF SQLERRM LIKE '%not supported in standard installation%' OR SQLERRM LIKE '%Unsupported frequency%' THEN
                    test_passed := TRUE;
                END IF;
        END;

        INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
            'Sub-day rejection in standard install',
            'Test 13.9: FREQ=MINUTELY rejected in standard install',
            CASE WHEN test_passed THEN 'PASS' ELSE 'FAIL' END
        );
    END IF;
END $$;

-- ============================================================================
-- SECTION 14: Version, API Limits, and Additional Coverage Tests
-- ============================================================================
\echo ''
\echo '--- Section 14: Version, API Limits, and Additional Coverage ---'

-- Coverage Gap 15: version() function untested
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'version() API',
    'Test 14.1: version() returns semver string',
    assert_true(
        'version() semver',
        (SELECT rrule."version"() ~ '^\d+\.\d+\.\d+$')
    );

-- Coverage Gap 17: BYSETPOS + YEARLY undertested
-- First weekday of Jan 2025 = Jan 1 (Wed), last weekday = Jan 31 (Fri)
-- First weekday of Jul 2025 = Jul 1 (Tue), last weekday = Jul 31 (Thu)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYSETPOS + YEARLY',
    'Test 14.2: BYSETPOS=1,-1 with YEARLY BYMONTH BYDAY weekdays',
    assert_equals(
        'BYSETPOS+YEARLY first/last weekday',
        '{"2025-01-01 00:00:00","2025-07-31 00:00:00","2026-01-01 00:00:00","2026-07-31 00:00:00"}',
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=1,7;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=4',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) d)::TEXT
    );

-- Coverage Gap 18: WKST + INTERVAL>1 + BYDAY interaction
-- dtstart=Sunday Jan 5 exposes difference: WKST=SU starts week on Jan 5, WKST=MO starts on Jan 6
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'WKST + INTERVAL>1',
    'Test 14.3: WKST=SU biweekly TU,TH (week starts Sunday)',
    assert_equals(
        'WKST=SU biweekly',
        '{"2025-01-07 00:00:00","2025-01-09 00:00:00","2025-01-21 00:00:00","2025-01-23 00:00:00"}',
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;WKST=SU;COUNT=4',
            '2025-01-05 00:00:00'::TIMESTAMP
        ) d)::TEXT
    );

INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'WKST + INTERVAL>1',
    'Test 14.4: WKST=MO biweekly TU,TH (different week boundary)',
    assert_equals(
        'WKST=MO biweekly',
        '{"2025-01-14 00:00:00","2025-01-16 00:00:00","2025-01-28 00:00:00","2025-01-30 00:00:00"}',
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;WKST=MO;COUNT=4',
            '2025-01-05 00:00:00'::TIMESTAMP
        ) d)::TEXT
    );

-- Coverage Gap 19: 1000-result cap
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'API Limits',
    'Test 14.5: all() caps at 1000 results for infinite rule',
    assert_equals(
        '1000-result cap',
        '1000',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=DAILY',
            '2025-01-01 00:00:00'::TIMESTAMP
        ))
    );

-- Coverage Gap 20: 10-year window cap
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'API Limits',
    'Test 14.6: all() caps at 10-year window from dtstart',
    assert_true(
        '10-year window cap',
        (SELECT MAX(d) <= '2025-01-01 00:00:00'::TIMESTAMP + INTERVAL '10 years'
         FROM rrule."all"(
            'FREQ=YEARLY;COUNT=20',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) d)
    );

-- Coverage Gap 21: Very large INTERVAL values
-- INTERVAL=10000 days = ~27 years; from 2025-01-01, only 1 result fits in 10-year window
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Large INTERVAL',
    'Test 14.7: DAILY INTERVAL=10000 COUNT=3 completes without error',
    assert_equals(
        'Large INTERVAL result',
        '1',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=DAILY;INTERVAL=10000;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ))
    );

-- Coverage Gap 22: overlaps() with 5-param signature (no timezone parameter)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() 5-param',
    'Test 14.8: overlaps() 5-param signature (match)',
    assert_equals(
        'overlaps 5-param TRUE',
        'true',
        (SELECT rrule."overlaps"(
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-15 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=5',
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 23:59:59+00'::TIMESTAMPTZ,
            NULL::TEXT
        )::TEXT)
    );

INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() 5-param',
    'Test 14.9: overlaps() 5-param signature (no match)',
    assert_equals(
        'overlaps 5-param FALSE',
        'false',
        (SELECT rrule."overlaps"(
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=3',
            '2025-02-01 00:00:00+00'::TIMESTAMPTZ,
            '2025-02-28 23:59:59+00'::TIMESTAMPTZ,
            NULL::TEXT
        )::TEXT)
    );

-- NOTE: The true 5-param overlaps() (src/rrule.sql:2461) cannot be called distinctly
-- because the 6-param version (src/rrule.sql:3156) has DEFAULT NULL for timezone,
-- making the signatures ambiguous. Tests 14.8/14.9 above cover the NULL-timezone
-- path which exercises the TIMESTAMP generator via the 6-param dispatch.

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
