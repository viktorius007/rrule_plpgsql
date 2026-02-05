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
    assert_occurrences_equal(
        'Single match',
        ARRAY['2025-01-05 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-05 09:00:00'::TIMESTAMP,
            '2025-01-05 11:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 2.3: Range includes an occurrence (inclusive range)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Edge Cases',
    'Range includes occurrence',
    assert_occurrences_equal(
        'Inclusive range',
        ARRAY['2025-01-03 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 00:00:00'::TIMESTAMP,
            '2025-01-03 23:59:59'::TIMESTAMP
        ) AS occurrence)
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
-- Both boundary timestamps (Jan 2 10:00 and Jan 3 10:00) are exact occurrence times,
-- and inc=false excludes boundary matches, so 0 occurrences are returned.
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
    assert_occurrences_equal(
        'Boundary inclusive',
        ARRAY[
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            TRUE
        ) AS occurrence)
    );

-- Test 2.7: Large range with UNTIL
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Edge Cases',
    'Large range with UNTIL limit',
    assert_occurrences_equal(
        'Large range UNTIL',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            '2025-01-04 10:00:00'::TIMESTAMP,
            '2025-01-05 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=DAILY;UNTIL=20250105T100000Z',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-12-31 23:59:59'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 2.8: between() with WEEKLY pattern
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Frequencies',
    'WEEKLY pattern in 2-week range',
    assert_occurrences_equal(
        'WEEKLY between',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-13 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=WEEKLY;BYDAY=MO;COUNT=10',
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-06 00:00:00'::TIMESTAMP,
            '2025-01-19 23:59:59'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 2.9: between() with MONTHLY pattern spanning partial months
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'between() Frequencies',
    'MONTHLY pattern partial months',
    assert_occurrences_equal(
        'MONTHLY between',
        ARRAY[
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-02-15 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=12',
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-01-10 00:00:00'::TIMESTAMP,
            '2025-02-20 23:59:59'::TIMESTAMP
        ) AS occurrence)
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
        '{"2025-01-01 10:00:00+00","2025-01-02 10:00:00+00","2025-01-03 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule."after"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2024-12-01 00:00:00+00'::TIMESTAMPTZ,
            10  -- Request 10 but only 3 exist
        ) d)
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
        '{"2025-01-05 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule."after"(
            'FREQ=DAILY;COUNT=100',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-05 00:00:00+00'::TIMESTAMPTZ,
            1
        ) d)
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
        '{"2025-01-01 10:00:00+00","2025-01-02 10:00:00+00","2025-01-03 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule."before"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-02-01 00:00:00+00'::TIMESTAMPTZ,
            10  -- Request 10 but only 3 exist
        ) d)
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
        '{"2025-01-09 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule."before"(
            'FREQ=DAILY;COUNT=100',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            1
        ) d)
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
-- Pass explicit reference_time to avoid NOW() dependency (TESTING_STANDARDS: fixed timestamps)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'most_recent() Edge Cases',
    'Returns NULL when dtstart in future',
    assert_equals(
        'NULL future dtstart',
        'NULL',
        (SELECT COALESCE(rrule."most_recent"(
            'FREQ=DAILY;COUNT=10',
            '2099-01-01 10:00:00'::TIMESTAMP,
            '2025-06-15 00:00:00'::TIMESTAMP
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
    assert_occurrences_equal(
        'Skip Feb 30',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,
            '2025-03-30 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP,
            '2025-05-30 10:00:00'::TIMESTAMP,
            '2025-06-30 10:00:00'::TIMESTAMP,
            '2025-07-30 10:00:00'::TIMESTAMP,
            '2025-08-30 10:00:00'::TIMESTAMP,
            '2025-09-30 10:00:00'::TIMESTAMP,
            '2025-10-30 10:00:00'::TIMESTAMP,
            '2025-11-30 10:00:00'::TIMESTAMP,
            '2025-12-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=30;COUNT=11',
            '2025-01-30 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 6.2: all() with BYDAY ordinal at month end
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'all() Edge Cases',
    'Last Friday of month (-1FR)',
    assert_occurrences_equal(
        'Last Friday',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-28 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-1FR;COUNT=3',
            '2025-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 6.3: all() with multiple BYMONTH
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'all() Edge Cases',
    'Multiple BYMONTH values',
    assert_occurrences_equal(
        'Multiple months',
        ARRAY[
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-04-15 10:00:00'::TIMESTAMP,
            '2025-07-15 10:00:00'::TIMESTAMP,
            '2025-10-15 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=1,4,7,10;COUNT=4',
            '2025-01-15 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 6.4: all() with complex BYDAY combination
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'all() Edge Cases',
    'Complex BYDAY: 2nd and 4th Tuesday',
    assert_occurrences_equal(
        'Complex BYDAY',
        ARRAY[
            '2025-01-14 10:00:00'::TIMESTAMP,
            '2025-01-28 10:00:00'::TIMESTAMP,
            '2025-02-11 10:00:00'::TIMESTAMP,
            '2025-02-25 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=2TU,4TU;COUNT=4',
            '2025-01-14 10:00:00'::TIMESTAMP
        ) AS occurrence)
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
    assert_occurrences_equal(
        'TZ API',
        ARRAY[
            '2025-01-15 09:00:00'::TIMESTAMP,
            '2025-01-16 09:00:00'::TIMESTAMP,
            '2025-01-17 09:00:00'::TIMESTAMP
        ],
        (SELECT array_agg((occurrence AT TIME ZONE 'America/New_York')::TIMESTAMP ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-15 09:00:00-05'::TIMESTAMPTZ,
            'America/New_York'
        ) AS occurrence)
    );

-- Test 7.2: rrule."between"() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule."between"() with timezone',
    assert_equals(
        'TZ between',
        '{"2025-01-02 15:00:00+00","2025-01-03 15:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule."between"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
            '2025-01-02 00:00:00-05'::TIMESTAMPTZ,
            '2025-01-03 23:59:59-05'::TIMESTAMPTZ,
            'America/New_York'
        ) d)
    );

-- Test 7.3: rrule."after"() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule."after"() with timezone',
    assert_equals(
        'TZ after',
        '{"2025-01-03 15:00:00+00","2025-01-04 15:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule."after"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
            '2025-01-03 00:00:00-05'::TIMESTAMPTZ,
            2,
            'America/New_York'
        ) d)
    );

-- Test 7.4: rrule."before"() TIMESTAMPTZ API
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'rrule.* API',
    'rrule."before"() with timezone',
    assert_equals(
        'TZ before',
        '{"2025-01-03 15:00:00+00","2025-01-04 15:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule."before"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
            '2025-01-05 00:00:00-05'::TIMESTAMPTZ,
            2,
            'America/New_York'
        ) d)
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
    assert_occurrences_equal(
        'YEARLY BYYEARDAY=-1',
        ARRAY['2025-12-31'::TIMESTAMP, '2026-12-31'::TIMESTAMP, '2027-12-31'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
          'FREQ=YEARLY;BYYEARDAY=-1;COUNT=3',
          '2025-01-01'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 8.2: Negative BYYEARDAY=-31 on YEARLY (Dec 1 in a non-leap year)
-- BYYEARDAY=-31 = day 335 in a 365-day year = Dec 1
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'Negative BYYEARDAY=-31 on YEARLY',
    assert_occurrences_equal(
        'YEARLY BYYEARDAY=-31',
        ARRAY['2025-12-01'::TIMESTAMP, '2026-12-01'::TIMESTAMP, '2027-12-01'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
          'FREQ=YEARLY;BYYEARDAY=-31;COUNT=3',
          '2025-01-01'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 8.3: Multiple negative BYYEARDAY values on YEARLY
-- BYYEARDAY=-1,-2 should generate Dec 31 and Dec 30
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'Multiple negative BYYEARDAY values (-1,-2)',
    assert_occurrences_equal(
        'YEARLY BYYEARDAY=-1,-2',
        ARRAY[
            '2025-12-30 00:00:00'::TIMESTAMP,
            '2025-12-31 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
          'FREQ=YEARLY;BYYEARDAY=-1,-2',
          '2025-01-01'::TIMESTAMP,
          '2025-12-01'::TIMESTAMP,
          '2025-12-31'::TIMESTAMP,
          TRUE
        ) AS occurrence)
    );

-- Test 8.4: Negative BYMONTHDAY=-1 as filter on DAILY
-- Should match the last day of each month (inc=true to include Dec 31)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'Negative BYMONTHDAY=-1 as DAILY filter',
    assert_occurrences_equal(
        'DAILY BYMONTHDAY=-1',
        ARRAY[
            '2025-01-31 00:00:00'::TIMESTAMP,
            '2025-02-28 00:00:00'::TIMESTAMP,
            '2025-03-31 00:00:00'::TIMESTAMP,
            '2025-04-30 00:00:00'::TIMESTAMP,
            '2025-05-31 00:00:00'::TIMESTAMP,
            '2025-06-30 00:00:00'::TIMESTAMP,
            '2025-07-31 00:00:00'::TIMESTAMP,
            '2025-08-31 00:00:00'::TIMESTAMP,
            '2025-09-30 00:00:00'::TIMESTAMP,
            '2025-10-31 00:00:00'::TIMESTAMP,
            '2025-11-30 00:00:00'::TIMESTAMP,
            '2025-12-31 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
          'FREQ=DAILY;BYMONTHDAY=-1',
          '2025-01-01'::TIMESTAMP,
          '2025-01-01'::TIMESTAMP,
          '2025-12-31'::TIMESTAMP,
          TRUE
        ) AS occurrence)
    );

-- Test 8.5: BYSETPOS with YEARLY (first Monday of each year)
-- 2025: first Monday = Jan 6. 2026: first Monday = Jan 5. 2027: first Monday = Jan 4.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'BYSETPOS with YEARLY (first Monday of year)',
    assert_occurrences_equal(
        'YEARLY BYSETPOS=1',
        ARRAY[
            '2025-01-06 00:00:00'::TIMESTAMP,
            '2026-01-05 00:00:00'::TIMESTAMP,
            '2027-01-04 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
          'FREQ=YEARLY;BYDAY=MO;BYSETPOS=1;COUNT=3',
          '2025-01-01'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 8.6: Negative BYMONTHDAY=-1 on MONTHLY verifies correct dates
-- Last day of Jan=31, Feb=28, Mar=31
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'Negative BYMONTHDAY=-1 on MONTHLY returns correct dates',
    assert_occurrences_equal(
        'MONTHLY BYMONTHDAY=-1 dates',
        ARRAY['2025-01-31'::TIMESTAMP, '2025-02-28'::TIMESTAMP, '2025-03-31'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
          'FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3',
          '2025-01-01'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 8.7: Negative BYMONTHDAY=-2 on MONTHLY (second to last day of month)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Negative Filters',
    'Negative BYMONTHDAY=-2 on MONTHLY',
    assert_occurrences_equal(
        'MONTHLY BYMONTHDAY=-2',
        ARRAY[
            '2025-01-30 00:00:00'::TIMESTAMP,
            '2025-02-27 00:00:00'::TIMESTAMP,
            '2025-03-30 00:00:00'::TIMESTAMP,
            '2025-04-29 00:00:00'::TIMESTAMP,
            '2025-05-30 00:00:00'::TIMESTAMP,
            '2025-06-29 00:00:00'::TIMESTAMP,
            '2025-07-30 00:00:00'::TIMESTAMP,
            '2025-08-30 00:00:00'::TIMESTAMP,
            '2025-09-29 00:00:00'::TIMESTAMP,
            '2025-10-30 00:00:00'::TIMESTAMP,
            '2025-11-29 00:00:00'::TIMESTAMP,
            '2025-12-30 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
          'FREQ=MONTHLY;BYMONTHDAY=-2',
          '2025-01-01'::TIMESTAMP,
          '2025-01-01'::TIMESTAMP,
          '2025-12-31'::TIMESTAMP
        ) AS occurrence)
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

-- Test 9.1a: BYDAY+BYMONTHDAY deduplication produces exactly 12 results
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Deduplication',
    'BYDAY+BYMONTHDAY COUNT=12 produces exactly 12 results',
    assert_occurrences_equal(
        'BYDAY+BYMONTHDAY count',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP, '2025-10-06 10:00:00'::TIMESTAMP,
            '2026-04-06 10:00:00'::TIMESTAMP, '2026-07-06 10:00:00'::TIMESTAMP,
            '2027-09-06 10:00:00'::TIMESTAMP, '2027-12-06 10:00:00'::TIMESTAMP,
            '2028-03-06 10:00:00'::TIMESTAMP, '2028-11-06 10:00:00'::TIMESTAMP,
            '2029-08-06 10:00:00'::TIMESTAMP, '2030-05-06 10:00:00'::TIMESTAMP,
            '2031-01-06 10:00:00'::TIMESTAMP, '2031-10-06 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
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
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;COUNT=5',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) d),
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO,MO;COUNT=5',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) d)
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
        WHEN status LIKE 'PASS%' THEN '  PASS ' || test_name
        ELSE '  FAIL ' || test_name || ' - ' || status
    END AS result
FROM coverage_gap_results
ORDER BY test_category, test_id;

\echo ''
\echo 'Category Summary:'
SELECT
    test_category,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') AS passed,
    COUNT(*) FILTER (WHERE status NOT LIKE 'PASS%') AS failed
FROM coverage_gap_results
GROUP BY test_category
ORDER BY test_category;

\echo ''
\echo 'Overall Summary:'
SELECT
    COUNT(*) AS total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') AS passed,
    COUNT(*) FILTER (WHERE status NOT LIKE 'PASS%') AS failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status LIKE 'PASS%') / COUNT(*), 1) || '%' AS pass_rate
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
-- Day 100: 2025 = Apr 10, 2026 = Apr 10, 2027 = Apr 10
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.3: BYYEARDAY duplicate values deduplicated',
    assert_occurrences_equal(
        'BYYEARDAY dedup',
        ARRAY[
            '2025-04-10 00:00:00'::TIMESTAMP,
            '2026-04-10 00:00:00'::TIMESTAMP,
            '2027-04-10 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYYEARDAY=100,100;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 11.4: BYWEEKNO duplicate values produce single occurrence set
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.4: BYWEEKNO duplicate values deduplicated',
    assert_occurrences_equal(
        'BYWEEKNO dedup',
        ARRAY[
            '2027-01-04 00:00:00'::TIMESTAMP,
            '2028-01-03 00:00:00'::TIMESTAMP,
            '2029-01-01 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYWEEKNO=1,1;BYDAY=MO;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 11.5: BYDAY trailing comma does not produce phantom Sunday
-- Ground truth: FREQ=WEEKLY;BYDAY=MO,TU;COUNT=2 starting Monday Jan 6 = Mon Jan 6 + Tue Jan 7
-- Both the clean and trailing-comma variants must match this expected array.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.5a: BYDAY=MO,TU matches expected array',
    assert_occurrences_equal(
        'BYDAY clean variant',
        ARRAY['2025-01-06 10:00:00'::TIMESTAMP, '2025-01-07 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,TU;COUNT=2', '2025-01-06 10:00:00'::TIMESTAMP) AS occurrence)
    );

INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Review-Driven Gaps',
    'Test 11.5b: BYDAY=MO,TU, (trailing comma) matches expected array',
    assert_occurrences_equal(
        'BYDAY trailing comma variant',
        ARRAY['2025-01-06 10:00:00'::TIMESTAMP, '2025-01-07 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence)
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
-- The correct answer is 2024-12-31, not the 1000th occurrence (2022-09-26)
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
-- Periods: Jan, Mar, May, Jul, Sep (FORWARD→Oct 1), Nov (FORWARD→Dec 1)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY INTERVAL>1 + SKIP',
    'Test 13.4: MONTHLY INTERVAL=2 SKIP=FORWARD from Jan 31',
    assert_equals(
        'Bi-monthly SKIP=FORWARD',
        '{"2025-01-31 00:00:00","2025-03-31 00:00:00","2025-05-31 00:00:00","2025-07-31 00:00:00","2025-10-01 00:00:00","2025-12-01 00:00:00"}',
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
    assert_occurrences_equal(
        'Large INTERVAL result',
        ARRAY['2025-01-01 00:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;INTERVAL=10000;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Coverage Gap 22: overlaps() TIMESTAMPTZ API with NULL timezone
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps() NULL tz',
    'Test 14.8: overlaps() NULL timezone (match)',
    assert_equals(
        'overlaps NULL tz TRUE',
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
    'overlaps() NULL tz',
    'Test 14.9: overlaps() NULL timezone (no match)',
    assert_equals(
        'overlaps NULL tz FALSE',
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

-- NOTE: Tests 14.8/14.9 cover the NULL-timezone path of the overlaps() TIMESTAMPTZ API.

-- ============================================================================
-- SECTION 15: BYHOUR/BYMINUTE/BYSECOND with DAILY frequency (standard install)
-- ============================================================================
\echo ''
\echo '--- Section 15: BYHOUR/BYMINUTE/BYSECOND with DAILY (standard install) ---'

-- Test 15.1: FREQ=DAILY;BYHOUR=9;COUNT=3
-- BYHOUR with DAILY expands each day to include an occurrence at hour 9
-- (preserves minute/second from dtstart)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYHOUR/BYMINUTE/BYSECOND with DAILY',
    'Test 15.1: FREQ=DAILY;BYHOUR=9;COUNT=3',
    assert_occurrences_equal(
        'DAILY BYHOUR=9',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,
            '2025-01-02 09:00:00'::TIMESTAMP,
            '2025-01-03 09:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;BYHOUR=9;COUNT=3',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 15.2: FREQ=DAILY;BYHOUR=9,17;COUNT=4
-- Multiple BYHOUR values expand each day to include occurrences at each specified hour
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYHOUR/BYMINUTE/BYSECOND with DAILY',
    'Test 15.2: FREQ=DAILY;BYHOUR=9,17;COUNT=4',
    assert_occurrences_equal(
        'DAILY BYHOUR=9,17',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,
            '2025-01-01 17:00:00'::TIMESTAMP,
            '2025-01-02 09:00:00'::TIMESTAMP,
            '2025-01-02 17:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;BYHOUR=9,17;COUNT=4',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 15.3: FREQ=DAILY;BYMINUTE=30;COUNT=3
-- BYMINUTE with DAILY expands each day to include an occurrence at minute 30
-- (preserves hour/second from dtstart)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYHOUR/BYMINUTE/BYSECOND with DAILY',
    'Test 15.3: FREQ=DAILY;BYMINUTE=30;COUNT=3',
    assert_occurrences_equal(
        'DAILY BYMINUTE=30',
        ARRAY[
            '2025-01-01 00:30:00'::TIMESTAMP,
            '2025-01-02 00:30:00'::TIMESTAMP,
            '2025-01-03 00:30:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;BYMINUTE=30;COUNT=3',
            '2025-01-01 00:30:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 15.4: FREQ=DAILY;BYSECOND=0;COUNT=3
-- BYSECOND with DAILY expands each day to include an occurrence at second 0
-- (preserves hour/minute from dtstart)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYHOUR/BYMINUTE/BYSECOND with DAILY',
    'Test 15.4: FREQ=DAILY;BYSECOND=0;COUNT=3',
    assert_occurrences_equal(
        'DAILY BYSECOND=0',
        ARRAY[
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-02 00:00:00'::TIMESTAMP,
            '2025-01-03 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;BYSECOND=0;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 15.5: FREQ=DAILY;BYHOUR=9;BYMINUTE=0,30;COUNT=4
-- Combining BYHOUR and BYMINUTE expands each day to all combinations
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYHOUR/BYMINUTE/BYSECOND with DAILY',
    'Test 15.5: FREQ=DAILY;BYHOUR=9;BYMINUTE=0,30;COUNT=4',
    assert_occurrences_equal(
        'DAILY BYHOUR+BYMINUTE',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,
            '2025-01-01 09:30:00'::TIMESTAMP,
            '2025-01-02 09:00:00'::TIMESTAMP,
            '2025-01-02 09:30:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;BYHOUR=9;BYMINUTE=0,30;COUNT=4',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- SECTION 16: NULL RRULE Input to Public API Functions
-- ============================================================================
-- NULL RRULE must raise "FREQ is required" error per RFC 5545 validation.
-- The STRICT modifier on internal functions previously caused NULL to silently
-- return empty results. Public API functions now guard against NULL explicitly.
-- ============================================================================
\echo ''
\echo '--- Section 16: NULL RRULE Input to Public API Functions ---'

-- Test 16.1: rrule."all"(NULL, dtstart) raises FREQ required error
DO $$
DECLARE
    err_msg TEXT;
    result_count INT;
BEGIN
    BEGIN
        SELECT COUNT(*) INTO result_count FROM rrule."all"(NULL, '2025-01-01 00:00:00'::TIMESTAMP);
        INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
            'NULL RRULE Input',
            'Test 16.1: rrule."all"(NULL, dtstart) raises error',
            'FAIL: expected exception but got ' || result_count || ' results'
        );
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
            INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
                'NULL RRULE Input',
                'Test 16.1: rrule."all"(NULL, dtstart) raises error',
                CASE WHEN err_msg LIKE '%FREQ%required%' THEN 'PASS' ELSE 'FAIL: wrong error: ' || LEFT(err_msg, 100) END
            );
    END;
END $$;

-- Test 16.2: rrule."between"(NULL, ...) raises FREQ required error
DO $$
DECLARE
    err_msg TEXT;
    result_count INT;
BEGIN
    BEGIN
        SELECT COUNT(*) INTO result_count FROM rrule."between"(NULL, '2025-01-01'::TIMESTAMP, '2025-01-01'::TIMESTAMP, '2025-12-31'::TIMESTAMP);
        INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
            'NULL RRULE Input',
            'Test 16.2: rrule."between"(NULL, ...) raises error',
            'FAIL: expected exception but got ' || result_count || ' results'
        );
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
            INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
                'NULL RRULE Input',
                'Test 16.2: rrule."between"(NULL, ...) raises error',
                CASE WHEN err_msg LIKE '%FREQ%required%' THEN 'PASS' ELSE 'FAIL: wrong error: ' || LEFT(err_msg, 100) END
            );
    END;
END $$;

-- Test 16.3: rrule."after"(NULL, ...) raises FREQ required error
DO $$
DECLARE
    err_msg TEXT;
    result_count INT;
BEGIN
    BEGIN
        SELECT COUNT(*) INTO result_count FROM rrule."after"(NULL, '2025-01-01'::TIMESTAMP, '2025-01-01'::TIMESTAMP);
        INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
            'NULL RRULE Input',
            'Test 16.3: rrule."after"(NULL, ...) raises error',
            'FAIL: expected exception but got ' || result_count || ' results'
        );
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
            INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
                'NULL RRULE Input',
                'Test 16.3: rrule."after"(NULL, ...) raises error',
                CASE WHEN err_msg LIKE '%FREQ%required%' THEN 'PASS' ELSE 'FAIL: wrong error: ' || LEFT(err_msg, 100) END
            );
    END;
END $$;

-- Test 16.4: rrule."before"(NULL, ...) raises FREQ required error
DO $$
DECLARE
    err_msg TEXT;
    result_count INT;
BEGIN
    BEGIN
        SELECT COUNT(*) INTO result_count FROM rrule."before"(NULL, '2025-01-01'::TIMESTAMP, '2025-12-31'::TIMESTAMP);
        INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
            'NULL RRULE Input',
            'Test 16.4: rrule."before"(NULL, ...) raises error',
            'FAIL: expected exception but got ' || result_count || ' results'
        );
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
            INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
                'NULL RRULE Input',
                'Test 16.4: rrule."before"(NULL, ...) raises error',
                CASE WHEN err_msg LIKE '%FREQ%required%' THEN 'PASS' ELSE 'FAIL: wrong error: ' || LEFT(err_msg, 100) END
            );
    END;
END $$;

-- Test 16.5: rrule."count"(NULL, dtstart) raises FREQ required error
DO $$
DECLARE
    err_msg TEXT;
    result_val TEXT;
BEGIN
    BEGIN
        SELECT rrule."count"(NULL, '2025-01-01'::TIMESTAMP)::TEXT INTO result_val;
        INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
            'NULL RRULE Input',
            'Test 16.5: rrule."count"(NULL, dtstart) raises error',
            'FAIL: expected exception but got ' || COALESCE(result_val, 'NULL')
        );
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
            INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
                'NULL RRULE Input',
                'Test 16.5: rrule."count"(NULL, dtstart) raises error',
                CASE WHEN err_msg LIKE '%FREQ%required%' THEN 'PASS' ELSE 'FAIL: wrong error: ' || LEFT(err_msg, 100) END
            );
    END;
END $$;

-- ============================================================================
-- SECTION 17: BYDAY Ordinal=5 (5th Occurrence in Month)
-- ============================================================================
\echo ''
\echo '--- Section 17: BYDAY Ordinal=5 (5th Occurrence in Month) ---'

-- Test 17.1: FREQ=MONTHLY;BYDAY=5MO;COUNT=3
-- The 5th Monday only exists in some months:
--   Jan 2025: 4 Mondays (no 5th)
--   Feb 2025: 4 Mondays (no 5th)
--   Mar 2025: 5 Mondays -> 5th Monday = March 31
--   Apr 2025: 4 Mondays (no 5th)
--   May 2025: 4 Mondays (no 5th)
--   Jun 2025: 5 Mondays -> 5th Monday = June 30
--   Jul 2025: 4 Mondays (no 5th)
--   Aug 2025: 4 Mondays (no 5th)
--   Sep 2025: 5 Mondays -> 5th Monday = September 29
-- So COUNT=3 should produce: March 31, June 30, September 29
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYDAY Ordinal=5',
    'Test 17.1: FREQ=MONTHLY;BYDAY=5MO;COUNT=3 (5th Monday)',
    assert_occurrences_equal(
        '5th Monday of month',
        ARRAY[
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-06-30 10:00:00'::TIMESTAMP,
            '2025-09-29 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=5MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- SECTION 18: WEEKLY + BYDAY + INTERVAL>1 + UNTIL Boundary
-- ============================================================================
\echo ''
\echo '--- Section 18: WEEKLY + BYDAY + INTERVAL>1 + UNTIL Boundary ---'

-- Test 18.1: FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;UNTIL=20250124T235959
-- dtstart = Monday Jan 6, 2025 at 10:00
-- Week of Jan 6 (active): MO=6, WE=8, FR=10
-- Week of Jan 13 (skipped due to INTERVAL=2)
-- Week of Jan 20 (active): MO=20, WE=22, FR=24
-- UNTIL is Jan 24 23:59:59 so FR Jan 24 at 10:00 is included
-- Expected: Jan 6, 8, 10, 20, 22, 24
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'WEEKLY INTERVAL>1 + UNTIL',
    'Test 18.1: Biweekly MO,WE,FR with UNTIL including last day',
    assert_occurrences_equal(
        'Biweekly MO,WE,FR UNTIL inclusive',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-08 10:00:00'::TIMESTAMP,
            '2025-01-10 10:00:00'::TIMESTAMP,
            '2025-01-20 10:00:00'::TIMESTAMP,
            '2025-01-22 10:00:00'::TIMESTAMP,
            '2025-01-24 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;UNTIL=20250124T235959Z',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 18.2: Same rule but UNTIL=20250123T235959Z excludes Jan 24
-- UNTIL is Jan 23 23:59:59 UTC, so FR Jan 24 at 10:00 is AFTER the UNTIL and excluded
-- Expected: Jan 6, 8, 10, 20, 22
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'WEEKLY INTERVAL>1 + UNTIL',
    'Test 18.2: Biweekly MO,WE,FR with UNTIL excluding last day',
    assert_occurrences_equal(
        'Biweekly MO,WE,FR UNTIL exclusive',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-08 10:00:00'::TIMESTAMP,
            '2025-01-10 10:00:00'::TIMESTAMP,
            '2025-01-20 10:00:00'::TIMESTAMP,
            '2025-01-22 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;UNTIL=20250123T235959Z',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- SECTION 19: Additional Coverage Gap Tests
-- ============================================================================
\echo ''
\echo '--- Section 19: Additional Coverage Gap Tests ---'

-- Test 19.1: Mixed ordinal + non-ordinal BYDAY
-- FREQ=MONTHLY;BYDAY=1MO,FR;COUNT=6 starting 2025-01-01 10:00:00
-- "1st Monday AND every Friday of each month"
-- January 2025: 1st Monday = Jan 6; Fridays = Jan 3, 10, 17, 24, 31
-- Sorted: Jan 3, 6, 10, 17, 24, 31
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Additional Coverage',
    'Test 19.1: Mixed ordinal + non-ordinal BYDAY (1MO,FR)',
    assert_occurrences_equal(
        'Mixed BYDAY 1MO,FR',
        ARRAY[
            '2025-01-03 10:00:00'::TIMESTAMP,
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-10 10:00:00'::TIMESTAMP,
            '2025-01-17 10:00:00'::TIMESTAMP,
            '2025-01-24 10:00:00'::TIMESTAMP,
            '2025-01-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=1MO,FR;COUNT=6',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 19.2: BYMONTHDAY mixing positive and negative
-- FREQ=MONTHLY;BYMONTHDAY=1,-1;COUNT=6 starting 2025-01-01 10:00:00
-- "1st and last day of each month"
-- Jan: 1, 31; Feb: 1, 28; Mar: 1, 31
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Additional Coverage',
    'Test 19.2: BYMONTHDAY positive and negative (1,-1)',
    assert_occurrences_equal(
        'BYMONTHDAY 1,-1',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-01 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=1,-1;COUNT=6',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 19.3: Empty string RRULE input raises exception (FREQ is required)
DO $$
DECLARE
    err_msg TEXT;
    result_count INT;
BEGIN
    BEGIN
        SELECT COUNT(*) INTO result_count FROM rrule."all"(
            '',
            '2025-01-01 00:00:00'::TIMESTAMP
        );
        -- Empty string should raise an error (FREQ is required)
        INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
            'Additional Coverage',
            'Test 19.3: Empty string RRULE raises error',
            'FAIL: expected exception but got ' || result_count || ' results'
        );
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
            INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
                'Additional Coverage',
                'Test 19.3: Empty string RRULE raises error',
                CASE WHEN err_msg LIKE '%FREQ%required%' THEN 'PASS' ELSE 'FAIL: wrong error: ' || LEFT(err_msg, 100) END
            );
    END;
END $$;

-- Test 19.4: rrule."version"() returns a non-empty TEXT string
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Additional Coverage',
    'Test 19.4: rrule."version"() returns non-empty string',
    assert_true(
        'version() non-empty',
        LENGTH(rrule."version"()) > 0
    );

-- ============================================================================
-- SECTION 20: Consensus Review Additions
-- ============================================================================
\echo ''
\echo '--- Section 20: Consensus Review Additions ---'

-- Test 20.1: RRULE: prefix is accepted by parser
-- iCalendar files include the "RRULE:" property prefix. The parser uses
-- substring regex that finds FREQ= anywhere in the string, so the prefix
-- is silently accepted. Verify this produces correct results.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Consensus Review',
    'Test 20.1: RRULE: prefix is accepted by parser',
    assert_occurrences_equal(
        'RRULE: prefix',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'RRULE:FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 20.2: Non-zero seconds in dtstart are preserved across recurrences
-- All other tests use :00 seconds. Verify second-level time preservation.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Consensus Review',
    'Test 20.2: Non-zero seconds preserved in dtstart',
    assert_occurrences_equal(
        'Seconds preservation',
        ARRAY[
            '2025-01-01 10:15:45'::TIMESTAMP,
            '2025-01-02 10:15:45'::TIMESTAMP,
            '2025-01-03 10:15:45'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:15:45'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 20.3: Explicit positive ordinal +1MO parses same as 1MO
-- RFC 5545 BYDAY allows optional +/- sign. Parser regex uses [+-]?
-- so +1MO and 1MO should produce identical results.
-- 1st Monday of each month from Jan 2025: Jan 6, Feb 3, Mar 3
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Consensus Review',
    'Test 20.3: Explicit positive ordinal +1MO equals 1MO',
    assert_occurrences_equal(
        '+1MO ordinal',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-02-03 10:00:00'::TIMESTAMP,
            '2025-03-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=+1MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 20.4: Resolved-date deduplication for BYMONTHDAY=31,-1
-- In January, both 31 and -1 resolve to Jan 31. The parser deduplicates
-- at the resolved-date level (seen_dates array), not input-value level.
-- Expected: one date per month (last day), not two.
-- Jan 31, Feb 28, Mar 31, Apr 30, May 31, Jun 30
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Consensus Review',
    'Test 20.4: Resolved-date dedup BYMONTHDAY=31,-1',
    assert_occurrences_equal(
        'BYMONTHDAY 31,-1 dedup',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-06-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31,-1;COUNT=6',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- SECTION 21: Consensus Review Quality Fixes
-- ============================================================================
\echo ''
\echo '--- Section 21: Consensus Review Quality Fixes ---'

-- Test 21.1: NULL dtstart raises explicit error
-- NULL dtstart is rejected by the public API with a descriptive error message
DO $$
DECLARE
    err_msg TEXT;
    result_count INT;
BEGIN
    BEGIN
        SELECT COUNT(*) INTO result_count FROM rrule."all"(
            'FREQ=DAILY;COUNT=3',
            NULL::TIMESTAMP
        );
        INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
            'Consensus Quality',
            'Test 21.1: NULL dtstart raises error',
            'FAIL: expected exception but got ' || result_count || ' results'
        );
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
            INSERT INTO coverage_gap_results (test_category, test_name, status) VALUES (
                'Consensus Quality',
                'Test 21.1: NULL dtstart raises error',
                CASE WHEN err_msg LIKE '%dtstart%NULL%' OR err_msg LIKE '%dtstart%required%' THEN 'PASS' ELSE 'FAIL: wrong error: ' || LEFT(err_msg, 100) END
            );
    END;
END $$;

-- Test 21.2: YEARLY+BYDAY+BYMONTH combination (all Mondays in March 2025)
-- March 2025 Mondays: 3rd, 10th, 17th, 24th, 31st
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Consensus Quality',
    'Test 21.2: YEARLY+BYDAY=MO+BYMONTH=3 (Mondays in March)',
    assert_occurrences_equal(
        'YEARLY BYDAY BYMONTH combo',
        ARRAY[
            '2025-03-03 10:00:00'::TIMESTAMP,
            '2025-03-10 10:00:00'::TIMESTAMP,
            '2025-03-17 10:00:00'::TIMESTAMP,
            '2025-03-24 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=MO;BYMONTH=3;COUNT=5',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 21.3: BYSETPOS with triple BYxxx (first weekday of January)
-- BYMONTH=1, BYDAY=weekdays, BYMONTHDAY=1-7, BYSETPOS=1 → first weekday in first week of Jan
-- Jan 2025: Wed Jan 1. Jan 2026: Thu Jan 1. Jan 2027: Fri Jan 1.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Consensus Quality',
    'Test 21.3: BYSETPOS with triple BYxxx (first weekday of January)',
    assert_occurrences_equal(
        'Triple BYxxx BYSETPOS',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2026-01-01 10:00:00'::TIMESTAMP,
            '2027-01-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=1;BYDAY=MO,TU,WE,TH,FR;BYMONTHDAY=1,2,3,4,5,6,7;BYSETPOS=1;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 21.4: RAISE WARNING on 1000-result cap (verify count capped at 1000)
-- PostgreSQL RAISE WARNING cannot be captured in PL/pgSQL exception handlers
-- (warnings don't trigger exceptions). We verify the cap behavior by checking
-- that an unbounded rule returns exactly 1000 results. Warning emission is
-- verified manually or via log inspection.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Consensus Quality',
    'Test 21.4: Unbounded FREQ=DAILY capped at 1000 results',
    assert_true(
        '1000-result cap',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=DAILY',
            '2025-01-01 00:00:00'::TIMESTAMP
        )) = 1000
    );

-- ============================================================================
-- SECTION 22: Group Consensus Review Issue Fixes
-- ============================================================================
\echo ''
\echo '--- Section 22: Group Consensus Review Issue Fixes ---'

-- Test 22.1: BYYEARDAY negative index across leap and non-leap years
-- BYYEARDAY=-306 = day (365-306+1)=60 in non-leap, day (366-306+1)=61 in leap
-- 2025 (non-leap): day 60 = Mar 1
-- 2026 (non-leap): day 60 = Mar 1
-- 2027 (non-leap): day 60 = Mar 1
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Group Consensus Fixes',
    'Test 22.1: BYYEARDAY=-306 across leap/non-leap years',
    assert_occurrences_equal(
        'BYYEARDAY=-306 leap span',
        ARRAY[
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2026-03-01 10:00:00'::TIMESTAMP,
            '2027-03-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYYEARDAY=-306;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 22.2: WEEKLY INTERVAL=2 with BYDAY not matching dtstart weekday
-- dtstart is Sunday Jan 5, 2025. BYDAY=TU. INTERVAL=2.
-- Week of Jan 5 (WKST=MO, so this week is Dec 30 - Jan 5): dtstart's week. TU = Dec 31 (before dtstart, skipped)
-- Next active week (skip 1): Mon Jan 13 week. Tue = Jan 14.
-- Then skip: Mon Jan 27 week. Tue = Jan 28. Then skip: Mon Feb 10 week. Tue = Feb 11.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Group Consensus Fixes',
    'Test 22.2: WEEKLY INTERVAL=2 BYDAY=TU dtstart on Sunday',
    assert_occurrences_equal(
        'WEEKLY INTERVAL=2 non-matching dtstart',
        ARRAY[
            '2025-01-14 10:00:00'::TIMESTAMP,
            '2025-01-28 10:00:00'::TIMESTAMP,
            '2025-02-11 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU;COUNT=3',
            '2025-01-05 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 22.3: Mixed ordinal BYDAY: 1MO,3FR (1st Monday and 3rd Friday)
-- Jan 2025: 1st Monday = Jan 6, 3rd Friday = Jan 17
-- Feb 2025: 1st Monday = Feb 3, 3rd Friday = Feb 21
-- Mar 2025: 1st Monday = Mar 3, 3rd Friday = Mar 21
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Group Consensus Fixes',
    'Test 22.3: Mixed ordinal BYDAY 1MO,3FR',
    assert_occurrences_equal(
        'Mixed ordinal 1MO,3FR',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-17 10:00:00'::TIMESTAMP,
            '2025-02-03 10:00:00'::TIMESTAMP,
            '2025-02-21 10:00:00'::TIMESTAMP,
            '2025-03-03 10:00:00'::TIMESTAMP,
            '2025-03-21 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=1MO,3FR;COUNT=6',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- SECTION 23: Consensus Review Gap Tests
-- ============================================================================
\echo ''
\echo '--- Section 23: Consensus Review Gap Tests ---'

-- Test 23.1: BYYEARDAY negative index spanning leap/non-leap years
-- BYYEARDAY=-307: non-leap year = Feb 28, leap year (2028) = Feb 29
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Consensus Review Gaps',
    'Test 23.1: BYYEARDAY=-307 spanning leap/non-leap years',
    assert_occurrences_equal(
        'BYYEARDAY negative leap',
        ARRAY[
            '2025-02-28 00:00:00'::TIMESTAMP,
            '2026-02-28 00:00:00'::TIMESTAMP,
            '2027-02-28 00:00:00'::TIMESTAMP,
            '2028-02-29 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYYEARDAY=-307;COUNT=4',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 23.2: WEEKLY BYDAY with non-matching dtstart and INTERVAL>1
-- dtstart=Sunday Jan 5, BYDAY=TU, INTERVAL=2: first Tuesday is Jan 14 (skips week of Jan 5)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Consensus Review Gaps',
    'Test 23.2: WEEKLY INTERVAL=2 BYDAY=TU with Sunday dtstart',
    assert_occurrences_equal(
        'WEEKLY nonmatch dtstart',
        ARRAY[
            '2025-01-14 00:00:00'::TIMESTAMP,
            '2025-01-28 00:00:00'::TIMESTAMP,
            '2025-02-11 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU;COUNT=3',
            '2025-01-05 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 23.3: Mixed ordinal BYDAY (1MO = first Monday, 3FR = third Friday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Consensus Review Gaps',
    'Test 23.3: MONTHLY BYDAY=1MO,3FR mixed ordinals',
    assert_occurrences_equal(
        'Mixed ordinal BYDAY',
        ARRAY[
            '2025-01-06 00:00:00'::TIMESTAMP,
            '2025-01-17 00:00:00'::TIMESTAMP,
            '2025-02-03 00:00:00'::TIMESTAMP,
            '2025-02-21 00:00:00'::TIMESTAMP,
            '2025-03-03 00:00:00'::TIMESTAMP,
            '2025-03-21 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=1MO,3FR;COUNT=6',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- SECTION 24: Code Path Coverage Gap Tests
-- Tests targeting untested branches identified by cross-referencing
-- src/rrule.sql code paths against existing test suites.
-- ============================================================================
\echo ''
\echo '--- Section 24: Code Path Coverage Gap Tests ---'

-- ============================================================================
-- 24.1: YEARLY SKIP=FORWARD drift prevention (no BYMONTHDAY/BYDAY)
-- Code: rrule.sql:2099-2106 — Feb 29 dtstart + FORWARD could produce wrong month
-- ============================================================================

-- Test 24.1a: YEARLY SKIP=FORWARD from leap day
-- 2024 leap, 2025-2027 non-leap (forward to Mar 1), 2028 leap (restores to Feb 29)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY SKIP Drift',
    'Test 24.1a: YEARLY SKIP=FORWARD from Feb 29 dtstart',
    assert_occurrences_equal(
        'YEARLY SKIP=FORWARD leap drift',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2026-03-01 10:00:00'::TIMESTAMP,
            '2027-03-01 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=5',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.2: YEARLY SKIP=OMIT drift prevention (no BYMONTHDAY/BYDAY)
-- Code: rrule.sql:2099-2102 — only leap years produce results
-- ============================================================================

-- Test 24.2a: YEARLY SKIP=OMIT from leap day — only leap years
-- COUNT=5 but only 3 leap years within 10-year window (2024, 2028, 2032)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY SKIP Drift',
    'Test 24.2a: YEARLY SKIP=OMIT from Feb 29 (leap years only)',
    assert_occurrences_equal(
        'YEARLY SKIP=OMIT leap only',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP,
            '2032-02-29 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=5',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 24.2b: YEARLY INTERVAL=2 SKIP=OMIT from leap day
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY SKIP Drift',
    'Test 24.2b: YEARLY INTERVAL=2 SKIP=OMIT from Feb 29',
    assert_occurrences_equal(
        'YEARLY INTERVAL=2 SKIP=OMIT',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP,
            '2032-02-29 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;INTERVAL=2;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=3',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.3: SKIP=FORWARD deduplication in rrule_month_bymonthday_set()
-- Code: rrule.sql:773-777 — multiple overflow values map to same date
-- ============================================================================

-- Test 24.3: MONTHLY BYMONTHDAY=29,30,31 SKIP=FORWARD — Feb overflow dedup
-- In Feb 2025 (28 days): 29,30,31 all overflow to Mar 1 — deduplication produces single Mar 1.
-- This tests the seen_dates dedup logic in rrule_month_bymonthday_set (lines 773-777).
-- Jan: 29,30,31. Feb: all 3 overflow -> Mar 1 (deduped). Mar: 29,30,31. Apr: 29,30, May 1 (30 overflow).
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'SKIP FORWARD Dedup',
    'Test 24.3: MONTHLY BYMONTHDAY=29,30,31 SKIP=FORWARD dedup in Feb',
    assert_occurrences_equal(
        'SKIP FORWARD dedup Feb',
        ARRAY[
            '2025-01-29 00:00:00'::TIMESTAMP,
            '2025-01-30 00:00:00'::TIMESTAMP,
            '2025-01-31 00:00:00'::TIMESTAMP,
            '2025-03-01 00:00:00'::TIMESTAMP,
            '2025-03-29 00:00:00'::TIMESTAMP,
            '2025-03-30 00:00:00'::TIMESTAMP,
            '2025-03-31 00:00:00'::TIMESTAMP,
            '2025-04-29 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=29,30,31;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=8',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.4: MONTHLY SKIP=OMIT with INTERVAL>1
-- Code: rrule.sql:2054-2058 — OMIT advances by rule.interval months
-- ============================================================================

-- Test 24.4a: MONTHLY INTERVAL=3 SKIP=OMIT from Jan 31
-- Jan 31 ok, Apr 30<31 OMIT, Jul 31 ok, Oct 31 ok, 2026-Jan 31 ok
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY SKIP OMIT INTERVAL',
    'Test 24.4a: MONTHLY INTERVAL=3 SKIP=OMIT from Jan 31',
    assert_occurrences_equal(
        'MONTHLY INTERVAL=3 SKIP=OMIT',
        ARRAY[
            '2025-01-31 00:00:00'::TIMESTAMP,
            '2025-07-31 00:00:00'::TIMESTAMP,
            '2025-10-31 00:00:00'::TIMESTAMP,
            '2026-01-31 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;INTERVAL=3;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=4',
            '2025-01-31 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 24.4b: MONTHLY INTERVAL=2 SKIP=OMIT from Jan 31 (all months have 31 days)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY SKIP OMIT INTERVAL',
    'Test 24.4b: MONTHLY INTERVAL=2 SKIP=OMIT from Jan 31 (all 31-day months)',
    assert_occurrences_equal(
        'MONTHLY INTERVAL=2 SKIP=OMIT all-31',
        ARRAY[
            '2025-01-31 00:00:00'::TIMESTAMP,
            '2025-03-31 00:00:00'::TIMESTAMP,
            '2025-05-31 00:00:00'::TIMESTAMP,
            '2025-07-31 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;INTERVAL=2;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=4',
            '2025-01-31 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.5: YEARLY + BYMONTH + BYYEARDAY intersection filter
-- Code: rrule.sql:1841 — intersection semantics untested
-- ============================================================================

-- Test 24.5: YEARLY BYMONTH=4 BYYEARDAY=100 intersection
-- Day 100 of 2025 = Apr 10. BYMONTH=4 generates Apr 1 (dtstart day=1).
-- BYYEARDAY=100 filter on Apr 1 -> no match. Verifies the intersection filter
-- correctly rejects non-matching BYYEARDAY when BYMONTH is primary.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY Multi-BY Intersection',
    'Test 24.5: YEARLY BYMONTH=4 BYYEARDAY=100 intersection (no match)',
    assert_equals(
        'BYMONTH+BYYEARDAY intersection empty',
        '0',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=YEARLY;BYMONTH=4;BYYEARDAY=100',
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2027-12-31 00:00:00'::TIMESTAMP,
            TRUE
        ))
    );

-- ============================================================================
-- 24.6: YEARLY + BYMONTH + BYWEEKNO intersection filter
-- Code: rrule.sql:1840 — week-year boundary could exclude valid dates
-- ============================================================================

-- Test 24.6: YEARLY BYMONTH=1 BYWEEKNO=2 BYDAY=MO,FR
-- ISO week 2 of 2025: Jan 6-12. Mon Jan 6, Fri Jan 10.
-- ISO week 2 of 2026: Jan 5-11. Mon Jan 5, Fri Jan 9.
-- Use between() to avoid COUNT semantics affecting result count.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY Multi-BY Intersection',
    'Test 24.6: YEARLY BYMONTH=1 BYWEEKNO=2 BYDAY=MO,FR',
    assert_occurrences_equal(
        'BYMONTH+BYWEEKNO+BYDAY intersection',
        ARRAY[
            '2025-01-06 00:00:00'::TIMESTAMP,
            '2025-01-10 00:00:00'::TIMESTAMP,
            '2026-01-05 00:00:00'::TIMESTAMP,
            '2026-01-09 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=YEARLY;BYMONTH=1;BYWEEKNO=2;BYDAY=MO,FR',
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2026-12-31 00:00:00'::TIMESTAMP,
            TRUE
        ) AS occurrence)
    );

-- ============================================================================
-- 24.7: YEARLY + BYWEEKNO + BYYEARDAY intersection filter
-- Code: rrule.sql:1849 — rare combination, filter logic untested
-- ============================================================================

-- Test 24.7: YEARLY BYWEEKNO=1 BYDAY=MO,TU,WE,TH,FR BYYEARDAY=1,2,3
-- ISO week 1 of 2025: Dec 30 2024 - Jan 5 2025. Yeardays 1-3 = Jan 1-3.
-- Weekdays in ISO week 1 AND yearday 1-3: Jan 1 (Wed), Jan 2 (Thu), Jan 3 (Fri)
-- 2026: ISO wk1 includes Jan 1 (Thu) and Jan 2 (Fri). Both are yeardays 1-2.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY Multi-BY Intersection',
    'Test 24.7: YEARLY BYWEEKNO=1 BYDAY=weekdays BYYEARDAY=1,2,3',
    assert_occurrences_equal(
        'BYWEEKNO+BYDAY+BYYEARDAY intersection',
        ARRAY[
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-02 00:00:00'::TIMESTAMP,
            '2025-01-03 00:00:00'::TIMESTAMP,
            '2026-01-01 00:00:00'::TIMESTAMP,
            '2026-01-02 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO,TU,WE,TH,FR;BYYEARDAY=1,2,3;COUNT=5',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.8: YEARLY + BYWEEKNO + BYMONTHDAY intersection filter
-- Code: rrule.sql:1850 — test_bymonthday_rule untested in this context
-- ============================================================================

-- Test 24.8: YEARLY BYWEEKNO=1 BYDAY=MO,TU,WE,TH,FR BYMONTHDAY=1
-- ISO week 1 weekdays filtered to 1st of month.
-- 2025: Jan 1 (Wed, ISO wk1). 2026: Jan 1 (Thu, ISO wk1).
-- 2027-2028: Jan 1 not in ISO wk1. 2029: Jan 1 (Mon, ISO wk1). 2030: Jan 1 (Tue, ISO wk1).
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY Multi-BY Intersection',
    'Test 24.8: YEARLY BYWEEKNO=1 BYDAY=weekdays BYMONTHDAY=1',
    assert_occurrences_equal(
        'BYWEEKNO+BYDAY+BYMONTHDAY intersection',
        ARRAY[
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2026-01-01 00:00:00'::TIMESTAMP,
            '2029-01-01 00:00:00'::TIMESTAMP,
            '2030-01-01 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO,TU,WE,TH,FR;BYMONTHDAY=1',
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2030-12-31 00:00:00'::TIMESTAMP,
            TRUE
        ) AS occurrence)
    );

-- ============================================================================
-- 24.9: YEARLY generate_series(1,12) with BYDAY+BYMONTHDAY (no BYMONTH)
-- Code: rrule.sql:1872-1882 — INTERSECT via monthly_set untested from yearly
-- ============================================================================

-- Test 24.9: YEARLY BYDAY=MO BYMONTHDAY=13 — "Monday the 13th"
-- 2025: Check all 12 months for Monday the 13th.
-- Jan 13 = Mon, Oct 13 = Mon. Other 13ths are not Monday.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY generate_series Path',
    'Test 24.9: YEARLY BYDAY=MO BYMONTHDAY=13 (Monday the 13th)',
    assert_occurrences_equal(
        'Monday the 13th',
        ARRAY[
            '2025-01-13 00:00:00'::TIMESTAMP,
            '2025-10-13 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=YEARLY;BYDAY=MO;BYMONTHDAY=13',
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-12-31 00:00:00'::TIMESTAMP,
            TRUE
        ) AS occurrence)
    );

-- ============================================================================
-- 24.10: YEARLY BYMONTH SKIP=FORWARD with day-31 dtstart (day overflow)
-- Code: rrule_yearly_bymonth_set:1616-1621
-- ============================================================================

-- Test 24.10: YEARLY BYMONTH=2,4 SKIP=FORWARD from Jan 31
-- Feb 31 overflows -> Mar 1, Apr 31 overflows -> May 1
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYMONTH SKIP Overflow',
    'Test 24.10: YEARLY BYMONTH=2,4 SKIP=FORWARD day 31 overflow',
    assert_occurrences_equal(
        'YEARLY BYMONTH SKIP=FORWARD overflow',
        ARRAY[
            '2025-03-01 00:00:00'::TIMESTAMP,
            '2025-05-01 00:00:00'::TIMESTAMP,
            '2026-03-01 00:00:00'::TIMESTAMP,
            '2026-05-01 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=2,4;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=4',
            '2025-01-31 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.11: YEARLY BYMONTH SKIP=OMIT with dtstart overflow
-- Code: rrule_yearly_bymonth_set:1622-1623
-- ============================================================================

-- Test 24.11: YEARLY BYMONTH=1,2,3 SKIP=OMIT from Jan 31
-- Jan 31 ok, Feb 31 OMIT (skip), Mar 31 ok
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYMONTH SKIP Overflow',
    'Test 24.11: YEARLY BYMONTH=1,2,3 SKIP=OMIT day 31 overflow',
    assert_occurrences_equal(
        'YEARLY BYMONTH SKIP=OMIT overflow',
        ARRAY[
            '2025-01-31 00:00:00'::TIMESTAMP,
            '2025-03-31 00:00:00'::TIMESTAMP,
            '2026-01-31 00:00:00'::TIMESTAMP,
            '2026-03-31 00:00:00'::TIMESTAMP,
            '2027-01-31 00:00:00'::TIMESTAMP,
            '2027-03-31 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=1,2,3;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=6',
            '2025-01-31 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.12: Year-scope BYDAY with negative ordinals beyond -1
-- Code: rrule_year_byday_set:628-637 — off-by-one in week subtraction
-- ============================================================================

-- Test 24.12a: YEARLY BYDAY=-3FR — 3rd-to-last Friday of each year
-- 2025: Last Friday = Dec 26. -2 = Dec 19. -3 = Dec 12.
-- 2026: Last Friday = Dec 25. -2 = Dec 18. -3 = Dec 11.
-- 2027: Last Friday = Dec 31. -2 = Dec 24. -3 = Dec 17.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Deep Negative',
    'Test 24.12a: YEARLY BYDAY=-3FR (3rd-to-last Friday)',
    assert_occurrences_equal(
        'BYDAY=-3FR',
        ARRAY[
            '2025-12-12 00:00:00'::TIMESTAMP,
            '2026-12-11 00:00:00'::TIMESTAMP,
            '2027-12-17 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-3FR;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 24.12b: YEARLY BYDAY=-2MO — 2nd-to-last Monday of each year
-- 2025: Last Monday = Dec 29. -2 = Dec 22.
-- 2026: Last Monday = Dec 28. -2 = Dec 21.
-- 2027: Last Monday = Dec 27. -2 = Dec 20.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Deep Negative',
    'Test 24.12b: YEARLY BYDAY=-2MO (2nd-to-last Monday)',
    assert_occurrences_equal(
        'BYDAY=-2MO',
        ARRAY[
            '2025-12-22 00:00:00'::TIMESTAMP,
            '2026-12-21 00:00:00'::TIMESTAMP,
            '2027-12-20 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-2MO;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.13: BYMONTH deduplication (BYMONTH=3,3) in yearly_bymonth_set
-- Code: rrule.sql:1595-1597 — duplicate months double results
-- ============================================================================

-- Test 24.13: YEARLY BYMONTH=3,3 — duplicate should not double results
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTH Dedup',
    'Test 24.13: YEARLY BYMONTH=3,3 does not double results',
    assert_occurrences_equal(
        'BYMONTH=3,3 dedup',
        ARRAY[
            '2025-03-15 00:00:00'::TIMESTAMP,
            '2026-03-15 00:00:00'::TIMESTAMP,
            '2027-03-15 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=3,3;COUNT=3',
            '2025-03-15 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.14: Warning emission when output_limit hit
-- Code: rrule.sql:2142-2147 — truncation warning
-- PostgreSQL RAISE WARNING cannot be captured in PL/pgSQL. We verify the cap
-- behavior by checking that an unbounded rule returns exactly 1000 results.
-- This is already tested in 14.5/21.4 but we add a YEARLY variant.
-- ============================================================================

-- Test 24.14: YEARLY with no COUNT/UNTIL hits 10-year window cap
-- Produces exactly 11 results (2025-2035 inclusive, boundary is now included with <=)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'API Limit Warning',
    'Test 24.14: YEARLY no COUNT/UNTIL caps at 10-year window (inclusive)',
    assert_equals(
        'YEARLY 10-year cap',
        '11',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=YEARLY',
            '2025-01-01 00:00:00'::TIMESTAMP
        ))
    );

-- ============================================================================
-- 24.15: YEARLY SKIP=FORWARD recovers to dtstart day on subsequent leap years
-- Verify that after FORWARD adjustment in a non-leap year, the next leap year
-- returns to Feb 29 (no cumulative drift).
-- ============================================================================

-- Test 24.15: YEARLY SKIP=FORWARD drift prevention — recovers to Feb 29
-- After FORWARD adjustment (Feb 29 -> Mar 1), the next iteration resets to
-- dtstart month+day (Feb 29). Non-leap years forward to Mar 1; leap years
-- restore to Feb 29. The 5th occurrence is 2028-02-29.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY SKIP Drift',
    'Test 24.15: YEARLY SKIP=FORWARD recovers on leap year (Feb 29)',
    assert_equals(
        'FORWARD drift recovery',
        '2028-02-29 10:00:00',
        (SELECT (array_agg(occurrence ORDER BY occurrence))[5]::TEXT FROM rrule."all"(
            'FREQ=YEARLY;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=5',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.16: MONTHLY SKIP=OMIT with INTERVAL=1 skips short months correctly
-- Verify basic OMIT behavior: day 31 in months with <31 days are skipped.
-- ============================================================================

-- Test 24.16: MONTHLY INTERVAL=1 SKIP=OMIT from Jan 31
-- Jan 31 ok, Feb OMIT, Mar 31 ok, Apr OMIT, May 31 ok, Jun OMIT
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY SKIP OMIT INTERVAL',
    'Test 24.16: MONTHLY INTERVAL=1 SKIP=OMIT from Jan 31',
    assert_occurrences_equal(
        'MONTHLY INTERVAL=1 SKIP=OMIT',
        ARRAY[
            '2025-01-31 00:00:00'::TIMESTAMP,
            '2025-03-31 00:00:00'::TIMESTAMP,
            '2025-05-31 00:00:00'::TIMESTAMP,
            '2025-07-31 00:00:00'::TIMESTAMP,
            '2025-08-31 00:00:00'::TIMESTAMP,
            '2025-10-31 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;SKIP=OMIT;RSCALE=GREGORIAN;COUNT=6',
            '2025-01-31 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.16b: YEARLY BYMONTH+BYWEEKNO+BYDAY COUNT regression (post-filter limiting)
-- Bug: yearly_set() passed max_results to inner set function, but post-filter
-- WHERE clauses (BYWEEKNO) rejected candidates after the limit was applied,
-- returning fewer results than COUNT requested.
-- ============================================================================

-- Test 24.16b: YEARLY BYMONTH+BYWEEKNO+BYDAY COUNT=4 returns exactly 4 results
-- BYMONTH=1 generates January dates, BYWEEKNO=2 filters to ISO week 2,
-- BYDAY=MO,FR selects Monday and Friday within that week.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY Post-Filter Limit',
    'Test 24.16b: YEARLY BYMONTH+BYWEEKNO+BYDAY COUNT=4 not truncated',
    assert_equals(
        'Post-filter COUNT regression',
        '4',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=1;BYWEEKNO=2;BYDAY=MO,FR;COUNT=4',
            '2025-01-01 00:00:00'::TIMESTAMP
        ))
    );

-- ============================================================================
-- 24.17: YEARLY BYDAY=-4SA — deeper negative ordinal
-- ============================================================================

-- Test 24.17: YEARLY BYDAY=-4SA (4th-to-last Saturday)
-- 2025: Last Sat = Dec 27. -2 = Dec 20. -3 = Dec 13. -4 = Dec 6.
-- 2026: Last Sat = Dec 26. -2 = Dec 19. -3 = Dec 12. -4 = Dec 5.
-- 2027: Last Sat = Dec 25. -2 = Dec 18. -3 = Dec 11. -4 = Dec 4.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Deep Negative',
    'Test 24.17: YEARLY BYDAY=-4SA (4th-to-last Saturday)',
    assert_occurrences_equal(
        'BYDAY=-4SA',
        ARRAY[
            '2025-12-06 00:00:00'::TIMESTAMP,
            '2026-12-05 00:00:00'::TIMESTAMP,
            '2027-12-04 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-4SA;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.18: YEARLY BYMONTH SKIP=BACKWARD with day overflow (complementary)
-- Code: rrule_yearly_bymonth_set:1609-1615
-- This path is partially tested in 11.7 but only for BYMONTH=2.
-- Test with multiple BYMONTH values including overflow months.
-- ============================================================================

-- Test 24.18: YEARLY BYMONTH=2,4 SKIP=BACKWARD from Jan 31
-- Feb 31 -> Feb 28, Apr 31 -> Apr 30
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYMONTH SKIP Overflow',
    'Test 24.18: YEARLY BYMONTH=2,4 SKIP=BACKWARD day 31 overflow',
    assert_occurrences_equal(
        'YEARLY BYMONTH SKIP=BACKWARD overflow',
        ARRAY[
            '2025-02-28 00:00:00'::TIMESTAMP,
            '2025-04-30 00:00:00'::TIMESTAMP,
            '2026-02-28 00:00:00'::TIMESTAMP,
            '2026-04-30 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=2,4;SKIP=BACKWARD;RSCALE=GREGORIAN;COUNT=4',
            '2025-01-31 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- 24.19: YEARLY + BYMONTH + BYYEARDAY non-matching intersection (empty result)
-- Verify that conflicting BYMONTH and BYYEARDAY correctly produce no results
-- ============================================================================

-- Test 24.19: YEARLY BYMONTH=1 BYYEARDAY=100 — day 100 is in April, not January
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY Multi-BY Intersection',
    'Test 24.19: YEARLY BYMONTH=1 BYYEARDAY=100 (conflicting, no results in Jan)',
    assert_equals(
        'BYMONTH+BYYEARDAY conflict',
        '0',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=YEARLY;BYMONTH=1;BYYEARDAY=100',
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-12-31 00:00:00'::TIMESTAMP,
            TRUE
        ))
    );

-- ============================================================================
-- 24.20: YEARLY + BYWEEKNO + BYMONTH intersection filter (BYWEEKNO-primary path)
-- When BYMONTH is NULL, the BYWEEKNO-primary code path handles generation.
-- BYMONTH filter must be applied as a WHERE-clause post-filter.
-- Issue #11: This filter was missing, allowing unfiltered results through.
-- ============================================================================

-- Test 24.20a: YEARLY BYWEEKNO=10 BYMONTH=6 — ISO week 10 falls in March, not June
-- BYWEEKNO generates March dates; BYMONTH=6 should filter all of them out → 0 results
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY Multi-BY Intersection',
    'Test 24.20a: YEARLY BYWEEKNO=10 BYMONTH=6 (conflicting, 0 results)',
    assert_equals(
        'BYWEEKNO+BYMONTH conflict',
        '0',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=YEARLY;BYWEEKNO=10;BYMONTH=6',
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2035-12-31 00:00:00'::TIMESTAMP,
            TRUE
        ))
    );

-- Test 24.20b: YEARLY BYWEEKNO=10 BYMONTH=3 BYDAY=all — ISO week 10 falls in March
-- BYMONTH-primary path generates March dates, BYWEEKNO filters to week 10
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY Multi-BY Intersection',
    'Test 24.20b: YEARLY BYWEEKNO=10 BYMONTH=3 BYDAY=all (compatible)',
    assert_occurrences_equal(
        'BYWEEKNO+BYMONTH compatible',
        ARRAY[
            '2025-03-03 00:00:00'::TIMESTAMP,
            '2025-03-04 00:00:00'::TIMESTAMP,
            '2025-03-05 00:00:00'::TIMESTAMP,
            '2025-03-06 00:00:00'::TIMESTAMP,
            '2025-03-07 00:00:00'::TIMESTAMP,
            '2025-03-08 00:00:00'::TIMESTAMP,
            '2025-03-09 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=YEARLY;BYMONTH=3;BYWEEKNO=10;BYDAY=MO,TU,WE,TH,FR,SA,SU',
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-12-31 00:00:00'::TIMESTAMP,
            TRUE
        ) AS occurrence)
    );

-- Test 24.20c: YEARLY BYWEEKNO=10 BYMONTH=6 BYDAY=all — week 10 is March, not June
-- Conflicting: BYMONTH=6 filters out all March dates → 0 results
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY Multi-BY Intersection',
    'Test 24.20c: YEARLY BYWEEKNO=10 BYMONTH=6 BYDAY=all (conflicting, 0 results)',
    assert_equals(
        'BYWEEKNO+BYMONTH conflict with BYDAY',
        '0',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=YEARLY;BYMONTH=6;BYWEEKNO=10;BYDAY=MO,TU,WE,TH,FR,SA,SU',
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2035-12-31 00:00:00'::TIMESTAMP,
            TRUE
        ))
    );


-- ============================================================================
-- Section 25: MONTHLY BYDAY Positive Ordinals
-- ============================================================================
\echo 'Section 25: MONTHLY BYDAY Positive Ordinals...'

-- Test 25.1: MONTHLY BYDAY=1MO (1st Monday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.1: MONTHLY BYDAY=1MO (1st Monday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=1MO',
        ARRAY['2025-01-06 10:00:00'::TIMESTAMP,'2025-02-03 10:00:00'::TIMESTAMP,'2025-03-03 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=1MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.2: MONTHLY BYDAY=1TU (1st Tuesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.2: MONTHLY BYDAY=1TU (1st Tuesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=1TU',
        ARRAY['2025-01-07 10:00:00'::TIMESTAMP,'2025-02-04 10:00:00'::TIMESTAMP,'2025-03-04 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=1TU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.3: MONTHLY BYDAY=1WE (1st Wednesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.3: MONTHLY BYDAY=1WE (1st Wednesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=1WE',
        ARRAY['2025-01-01 10:00:00'::TIMESTAMP,'2025-02-05 10:00:00'::TIMESTAMP,'2025-03-05 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=1WE;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.4: MONTHLY BYDAY=1TH (1st Thursday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.4: MONTHLY BYDAY=1TH (1st Thursday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=1TH',
        ARRAY['2025-01-02 10:00:00'::TIMESTAMP,'2025-02-06 10:00:00'::TIMESTAMP,'2025-03-06 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=1TH;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.5: MONTHLY BYDAY=1FR (1st Friday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.5: MONTHLY BYDAY=1FR (1st Friday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=1FR',
        ARRAY['2025-01-03 10:00:00'::TIMESTAMP,'2025-02-07 10:00:00'::TIMESTAMP,'2025-03-07 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=1FR;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.6: MONTHLY BYDAY=1SA (1st Saturday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.6: MONTHLY BYDAY=1SA (1st Saturday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=1SA',
        ARRAY['2025-01-04 10:00:00'::TIMESTAMP,'2025-02-01 10:00:00'::TIMESTAMP,'2025-03-01 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=1SA;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.7: MONTHLY BYDAY=1SU (1st Sunday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.7: MONTHLY BYDAY=1SU (1st Sunday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=1SU',
        ARRAY['2025-01-05 10:00:00'::TIMESTAMP,'2025-02-02 10:00:00'::TIMESTAMP,'2025-03-02 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=1SU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.8: MONTHLY BYDAY=2MO (2nd Monday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.8: MONTHLY BYDAY=2MO (2nd Monday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=2MO',
        ARRAY['2025-01-13 10:00:00'::TIMESTAMP,'2025-02-10 10:00:00'::TIMESTAMP,'2025-03-10 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=2MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.9: MONTHLY BYDAY=2TU (2nd Tuesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.9: MONTHLY BYDAY=2TU (2nd Tuesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=2TU',
        ARRAY['2025-01-14 10:00:00'::TIMESTAMP,'2025-02-11 10:00:00'::TIMESTAMP,'2025-03-11 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=2TU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.10: MONTHLY BYDAY=2WE (2nd Wednesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.10: MONTHLY BYDAY=2WE (2nd Wednesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=2WE',
        ARRAY['2025-01-08 10:00:00'::TIMESTAMP,'2025-02-12 10:00:00'::TIMESTAMP,'2025-03-12 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=2WE;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.11: MONTHLY BYDAY=2TH (2nd Thursday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.11: MONTHLY BYDAY=2TH (2nd Thursday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=2TH',
        ARRAY['2025-01-09 10:00:00'::TIMESTAMP,'2025-02-13 10:00:00'::TIMESTAMP,'2025-03-13 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=2TH;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.12: MONTHLY BYDAY=2FR (2nd Friday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.12: MONTHLY BYDAY=2FR (2nd Friday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=2FR',
        ARRAY['2025-01-10 10:00:00'::TIMESTAMP,'2025-02-14 10:00:00'::TIMESTAMP,'2025-03-14 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=2FR;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.13: MONTHLY BYDAY=2SA (2nd Saturday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.13: MONTHLY BYDAY=2SA (2nd Saturday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=2SA',
        ARRAY['2025-01-11 10:00:00'::TIMESTAMP,'2025-02-08 10:00:00'::TIMESTAMP,'2025-03-08 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=2SA;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.14: MONTHLY BYDAY=2SU (2nd Sunday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.14: MONTHLY BYDAY=2SU (2nd Sunday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=2SU',
        ARRAY['2025-01-12 10:00:00'::TIMESTAMP,'2025-02-09 10:00:00'::TIMESTAMP,'2025-03-09 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=2SU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.15: MONTHLY BYDAY=3MO (3rd Monday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.15: MONTHLY BYDAY=3MO (3rd Monday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=3MO',
        ARRAY['2025-01-20 10:00:00'::TIMESTAMP,'2025-02-17 10:00:00'::TIMESTAMP,'2025-03-17 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=3MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.16: MONTHLY BYDAY=3TU (3rd Tuesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.16: MONTHLY BYDAY=3TU (3rd Tuesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=3TU',
        ARRAY['2025-01-21 10:00:00'::TIMESTAMP,'2025-02-18 10:00:00'::TIMESTAMP,'2025-03-18 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=3TU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.17: MONTHLY BYDAY=3WE (3rd Wednesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.17: MONTHLY BYDAY=3WE (3rd Wednesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=3WE',
        ARRAY['2025-01-15 10:00:00'::TIMESTAMP,'2025-02-19 10:00:00'::TIMESTAMP,'2025-03-19 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=3WE;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.18: MONTHLY BYDAY=3TH (3rd Thursday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.18: MONTHLY BYDAY=3TH (3rd Thursday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=3TH',
        ARRAY['2025-01-16 10:00:00'::TIMESTAMP,'2025-02-20 10:00:00'::TIMESTAMP,'2025-03-20 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=3TH;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.19: MONTHLY BYDAY=3FR (3rd Friday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.19: MONTHLY BYDAY=3FR (3rd Friday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=3FR',
        ARRAY['2025-01-17 10:00:00'::TIMESTAMP,'2025-02-21 10:00:00'::TIMESTAMP,'2025-03-21 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=3FR;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.20: MONTHLY BYDAY=3SA (3rd Saturday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.20: MONTHLY BYDAY=3SA (3rd Saturday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=3SA',
        ARRAY['2025-01-18 10:00:00'::TIMESTAMP,'2025-02-15 10:00:00'::TIMESTAMP,'2025-03-15 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=3SA;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.21: MONTHLY BYDAY=3SU (3rd Sunday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.21: MONTHLY BYDAY=3SU (3rd Sunday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=3SU',
        ARRAY['2025-01-19 10:00:00'::TIMESTAMP,'2025-02-16 10:00:00'::TIMESTAMP,'2025-03-16 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=3SU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.22: MONTHLY BYDAY=4MO (4th Monday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.22: MONTHLY BYDAY=4MO (4th Monday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=4MO',
        ARRAY['2025-01-27 10:00:00'::TIMESTAMP,'2025-02-24 10:00:00'::TIMESTAMP,'2025-03-24 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=4MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.23: MONTHLY BYDAY=4TU (4th Tuesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.23: MONTHLY BYDAY=4TU (4th Tuesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=4TU',
        ARRAY['2025-01-28 10:00:00'::TIMESTAMP,'2025-02-25 10:00:00'::TIMESTAMP,'2025-03-25 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=4TU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.24: MONTHLY BYDAY=4WE (4th Wednesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.24: MONTHLY BYDAY=4WE (4th Wednesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=4WE',
        ARRAY['2025-01-22 10:00:00'::TIMESTAMP,'2025-02-26 10:00:00'::TIMESTAMP,'2025-03-26 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=4WE;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.25: MONTHLY BYDAY=4TH (4th Thursday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.25: MONTHLY BYDAY=4TH (4th Thursday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=4TH',
        ARRAY['2025-01-23 10:00:00'::TIMESTAMP,'2025-02-27 10:00:00'::TIMESTAMP,'2025-03-27 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=4TH;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.26: MONTHLY BYDAY=4FR (4th Friday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.26: MONTHLY BYDAY=4FR (4th Friday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=4FR',
        ARRAY['2025-01-24 10:00:00'::TIMESTAMP,'2025-02-28 10:00:00'::TIMESTAMP,'2025-03-28 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=4FR;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.27: MONTHLY BYDAY=4SA (4th Saturday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.27: MONTHLY BYDAY=4SA (4th Saturday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=4SA',
        ARRAY['2025-01-25 10:00:00'::TIMESTAMP,'2025-02-22 10:00:00'::TIMESTAMP,'2025-03-22 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=4SA;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.28: MONTHLY BYDAY=4SU (4th Sunday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.28: MONTHLY BYDAY=4SU (4th Sunday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=4SU',
        ARRAY['2025-01-26 10:00:00'::TIMESTAMP,'2025-02-23 10:00:00'::TIMESTAMP,'2025-03-23 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=4SU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.29: MONTHLY BYDAY=5MO (5th Monday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.29: MONTHLY BYDAY=5MO (5th Monday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=5MO',
        ARRAY['2025-03-31 10:00:00'::TIMESTAMP,'2025-06-30 10:00:00'::TIMESTAMP,'2025-09-29 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=5MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.30: MONTHLY BYDAY=5TU (5th Tuesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.30: MONTHLY BYDAY=5TU (5th Tuesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=5TU',
        ARRAY['2025-04-29 10:00:00'::TIMESTAMP,'2025-07-29 10:00:00'::TIMESTAMP,'2025-09-30 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=5TU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.31: MONTHLY BYDAY=5WE (5th Wednesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.31: MONTHLY BYDAY=5WE (5th Wednesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=5WE',
        ARRAY['2025-01-29 10:00:00'::TIMESTAMP,'2025-04-30 10:00:00'::TIMESTAMP,'2025-07-30 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=5WE;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.32: MONTHLY BYDAY=5TH (5th Thursday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.32: MONTHLY BYDAY=5TH (5th Thursday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=5TH',
        ARRAY['2025-01-30 10:00:00'::TIMESTAMP,'2025-05-29 10:00:00'::TIMESTAMP,'2025-07-31 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=5TH;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.33: MONTHLY BYDAY=5FR (5th Friday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.33: MONTHLY BYDAY=5FR (5th Friday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=5FR',
        ARRAY['2025-01-31 10:00:00'::TIMESTAMP,'2025-05-30 10:00:00'::TIMESTAMP,'2025-08-29 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=5FR;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.34: MONTHLY BYDAY=5SA (5th Saturday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.34: MONTHLY BYDAY=5SA (5th Saturday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=5SA',
        ARRAY['2025-03-29 10:00:00'::TIMESTAMP,'2025-05-31 10:00:00'::TIMESTAMP,'2025-08-30 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=5SA;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 25.35: MONTHLY BYDAY=5SU (5th Sunday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Ordinals',
    'Test 25.35: MONTHLY BYDAY=5SU (5th Sunday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=5SU',
        ARRAY['2025-03-30 10:00:00'::TIMESTAMP,'2025-06-29 10:00:00'::TIMESTAMP,'2025-08-31 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=5SU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- Section 26: MONTHLY BYDAY Negative Ordinals
-- ============================================================================
\echo 'Section 26: MONTHLY BYDAY Negative Ordinals...'

-- Test 26.1: MONTHLY BYDAY=-1MO (last Monday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.1: MONTHLY BYDAY=-1MO (last Monday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-1MO',
        ARRAY['2025-01-27 10:00:00'::TIMESTAMP,'2025-02-24 10:00:00'::TIMESTAMP,'2025-03-31 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-1MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.2: MONTHLY BYDAY=-1TU (last Tuesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.2: MONTHLY BYDAY=-1TU (last Tuesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-1TU',
        ARRAY['2025-01-28 10:00:00'::TIMESTAMP,'2025-02-25 10:00:00'::TIMESTAMP,'2025-03-25 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-1TU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.3: MONTHLY BYDAY=-1WE (last Wednesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.3: MONTHLY BYDAY=-1WE (last Wednesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-1WE',
        ARRAY['2025-01-29 10:00:00'::TIMESTAMP,'2025-02-26 10:00:00'::TIMESTAMP,'2025-03-26 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-1WE;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.4: MONTHLY BYDAY=-1TH (last Thursday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.4: MONTHLY BYDAY=-1TH (last Thursday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-1TH',
        ARRAY['2025-01-30 10:00:00'::TIMESTAMP,'2025-02-27 10:00:00'::TIMESTAMP,'2025-03-27 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-1TH;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.5: MONTHLY BYDAY=-1FR (last Friday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.5: MONTHLY BYDAY=-1FR (last Friday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-1FR',
        ARRAY['2025-01-31 10:00:00'::TIMESTAMP,'2025-02-28 10:00:00'::TIMESTAMP,'2025-03-28 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-1FR;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.6: MONTHLY BYDAY=-1SA (last Saturday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.6: MONTHLY BYDAY=-1SA (last Saturday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-1SA',
        ARRAY['2025-01-25 10:00:00'::TIMESTAMP,'2025-02-22 10:00:00'::TIMESTAMP,'2025-03-29 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-1SA;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.7: MONTHLY BYDAY=-1SU (last Sunday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.7: MONTHLY BYDAY=-1SU (last Sunday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-1SU',
        ARRAY['2025-01-26 10:00:00'::TIMESTAMP,'2025-02-23 10:00:00'::TIMESTAMP,'2025-03-30 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-1SU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.8: MONTHLY BYDAY=-2MO (2nd-last Monday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.8: MONTHLY BYDAY=-2MO (2nd-last Monday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-2MO',
        ARRAY['2025-01-20 10:00:00'::TIMESTAMP,'2025-02-17 10:00:00'::TIMESTAMP,'2025-03-24 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-2MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.9: MONTHLY BYDAY=-2TU (2nd-last Tuesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.9: MONTHLY BYDAY=-2TU (2nd-last Tuesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-2TU',
        ARRAY['2025-01-21 10:00:00'::TIMESTAMP,'2025-02-18 10:00:00'::TIMESTAMP,'2025-03-18 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-2TU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.10: MONTHLY BYDAY=-2WE (2nd-last Wednesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.10: MONTHLY BYDAY=-2WE (2nd-last Wednesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-2WE',
        ARRAY['2025-01-22 10:00:00'::TIMESTAMP,'2025-02-19 10:00:00'::TIMESTAMP,'2025-03-19 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-2WE;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.11: MONTHLY BYDAY=-2TH (2nd-last Thursday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.11: MONTHLY BYDAY=-2TH (2nd-last Thursday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-2TH',
        ARRAY['2025-01-23 10:00:00'::TIMESTAMP,'2025-02-20 10:00:00'::TIMESTAMP,'2025-03-20 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-2TH;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.12: MONTHLY BYDAY=-2FR (2nd-last Friday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.12: MONTHLY BYDAY=-2FR (2nd-last Friday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-2FR',
        ARRAY['2025-01-24 10:00:00'::TIMESTAMP,'2025-02-21 10:00:00'::TIMESTAMP,'2025-03-21 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-2FR;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.13: MONTHLY BYDAY=-2SA (2nd-last Saturday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.13: MONTHLY BYDAY=-2SA (2nd-last Saturday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-2SA',
        ARRAY['2025-01-18 10:00:00'::TIMESTAMP,'2025-02-15 10:00:00'::TIMESTAMP,'2025-03-22 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-2SA;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.14: MONTHLY BYDAY=-2SU (2nd-last Sunday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.14: MONTHLY BYDAY=-2SU (2nd-last Sunday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-2SU',
        ARRAY['2025-01-19 10:00:00'::TIMESTAMP,'2025-02-16 10:00:00'::TIMESTAMP,'2025-03-23 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-2SU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.15: MONTHLY BYDAY=-3MO (3rd-last Monday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.15: MONTHLY BYDAY=-3MO (3rd-last Monday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-3MO',
        ARRAY['2025-01-13 10:00:00'::TIMESTAMP,'2025-02-10 10:00:00'::TIMESTAMP,'2025-03-17 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-3MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.16: MONTHLY BYDAY=-3TU (3rd-last Tuesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.16: MONTHLY BYDAY=-3TU (3rd-last Tuesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-3TU',
        ARRAY['2025-01-14 10:00:00'::TIMESTAMP,'2025-02-11 10:00:00'::TIMESTAMP,'2025-03-11 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-3TU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.17: MONTHLY BYDAY=-3WE (3rd-last Wednesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.17: MONTHLY BYDAY=-3WE (3rd-last Wednesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-3WE',
        ARRAY['2025-01-15 10:00:00'::TIMESTAMP,'2025-02-12 10:00:00'::TIMESTAMP,'2025-03-12 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-3WE;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.18: MONTHLY BYDAY=-3TH (3rd-last Thursday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.18: MONTHLY BYDAY=-3TH (3rd-last Thursday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-3TH',
        ARRAY['2025-01-16 10:00:00'::TIMESTAMP,'2025-02-13 10:00:00'::TIMESTAMP,'2025-03-13 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-3TH;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.19: MONTHLY BYDAY=-3FR (3rd-last Friday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.19: MONTHLY BYDAY=-3FR (3rd-last Friday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-3FR',
        ARRAY['2025-01-17 10:00:00'::TIMESTAMP,'2025-02-14 10:00:00'::TIMESTAMP,'2025-03-14 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-3FR;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.20: MONTHLY BYDAY=-3SA (3rd-last Saturday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.20: MONTHLY BYDAY=-3SA (3rd-last Saturday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-3SA',
        ARRAY['2025-01-11 10:00:00'::TIMESTAMP,'2025-02-08 10:00:00'::TIMESTAMP,'2025-03-15 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-3SA;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.21: MONTHLY BYDAY=-3SU (3rd-last Sunday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.21: MONTHLY BYDAY=-3SU (3rd-last Sunday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-3SU',
        ARRAY['2025-01-12 10:00:00'::TIMESTAMP,'2025-02-09 10:00:00'::TIMESTAMP,'2025-03-16 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-3SU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.22: MONTHLY BYDAY=-4MO (4th-last Monday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.22: MONTHLY BYDAY=-4MO (4th-last Monday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-4MO',
        ARRAY['2025-01-06 10:00:00'::TIMESTAMP,'2025-02-03 10:00:00'::TIMESTAMP,'2025-03-10 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-4MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.23: MONTHLY BYDAY=-4TU (4th-last Tuesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.23: MONTHLY BYDAY=-4TU (4th-last Tuesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-4TU',
        ARRAY['2025-01-07 10:00:00'::TIMESTAMP,'2025-02-04 10:00:00'::TIMESTAMP,'2025-03-04 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-4TU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.24: MONTHLY BYDAY=-4WE (4th-last Wednesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.24: MONTHLY BYDAY=-4WE (4th-last Wednesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-4WE',
        ARRAY['2025-01-08 10:00:00'::TIMESTAMP,'2025-02-05 10:00:00'::TIMESTAMP,'2025-03-05 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-4WE;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.25: MONTHLY BYDAY=-4TH (4th-last Thursday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.25: MONTHLY BYDAY=-4TH (4th-last Thursday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-4TH',
        ARRAY['2025-01-09 10:00:00'::TIMESTAMP,'2025-02-06 10:00:00'::TIMESTAMP,'2025-03-06 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-4TH;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.26: MONTHLY BYDAY=-4FR (4th-last Friday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.26: MONTHLY BYDAY=-4FR (4th-last Friday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-4FR',
        ARRAY['2025-01-10 10:00:00'::TIMESTAMP,'2025-02-07 10:00:00'::TIMESTAMP,'2025-03-07 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-4FR;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.27: MONTHLY BYDAY=-4SA (4th-last Saturday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.27: MONTHLY BYDAY=-4SA (4th-last Saturday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-4SA',
        ARRAY['2025-01-04 10:00:00'::TIMESTAMP,'2025-02-01 10:00:00'::TIMESTAMP,'2025-03-08 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-4SA;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.28: MONTHLY BYDAY=-4SU (4th-last Sunday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.28: MONTHLY BYDAY=-4SU (4th-last Sunday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-4SU',
        ARRAY['2025-01-05 10:00:00'::TIMESTAMP,'2025-02-02 10:00:00'::TIMESTAMP,'2025-03-09 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-4SU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.29: MONTHLY BYDAY=-5MO (5th-last Monday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.29: MONTHLY BYDAY=-5MO (5th-last Monday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-5MO',
        ARRAY['2025-03-03 10:00:00'::TIMESTAMP,'2025-06-02 10:00:00'::TIMESTAMP,'2025-09-01 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-5MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.30: MONTHLY BYDAY=-5TU (5th-last Tuesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.30: MONTHLY BYDAY=-5TU (5th-last Tuesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-5TU',
        ARRAY['2025-04-01 10:00:00'::TIMESTAMP,'2025-07-01 10:00:00'::TIMESTAMP,'2025-09-02 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-5TU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.31: MONTHLY BYDAY=-5WE (5th-last Wednesday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.31: MONTHLY BYDAY=-5WE (5th-last Wednesday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-5WE',
        ARRAY['2025-01-01 10:00:00'::TIMESTAMP,'2025-04-02 10:00:00'::TIMESTAMP,'2025-07-02 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-5WE;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.32: MONTHLY BYDAY=-5TH (5th-last Thursday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.32: MONTHLY BYDAY=-5TH (5th-last Thursday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-5TH',
        ARRAY['2025-01-02 10:00:00'::TIMESTAMP,'2025-05-01 10:00:00'::TIMESTAMP,'2025-07-03 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-5TH;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.33: MONTHLY BYDAY=-5FR (5th-last Friday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.33: MONTHLY BYDAY=-5FR (5th-last Friday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-5FR',
        ARRAY['2025-01-03 10:00:00'::TIMESTAMP,'2025-05-02 10:00:00'::TIMESTAMP,'2025-08-01 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-5FR;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.34: MONTHLY BYDAY=-5SA (5th-last Saturday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.34: MONTHLY BYDAY=-5SA (5th-last Saturday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-5SA',
        ARRAY['2025-03-01 10:00:00'::TIMESTAMP,'2025-05-03 10:00:00'::TIMESTAMP,'2025-08-02 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-5SA;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 26.35: MONTHLY BYDAY=-5SU (5th-last Sunday)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY BYDAY Negative Ordinals',
    'Test 26.35: MONTHLY BYDAY=-5SU (5th-last Sunday)',
    assert_occurrences_equal(
        'MONTHLY BYDAY=-5SU',
        ARRAY['2025-03-02 10:00:00'::TIMESTAMP,'2025-06-01 10:00:00'::TIMESTAMP,'2025-08-03 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=-5SU;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- Section 27: YEARLY BYDAY Positive Ordinals
-- ============================================================================
\echo 'Section 27: YEARLY BYDAY Positive Ordinals...'

-- Test 27.1: YEARLY BYDAY=1MO (1st Monday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.1: YEARLY BYDAY=1MO (1st Monday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=1MO',
        ARRAY['2025-01-06 10:00:00'::TIMESTAMP,'2026-01-05 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=1MO;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.2: YEARLY BYDAY=1TU (1st Tuesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.2: YEARLY BYDAY=1TU (1st Tuesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=1TU',
        ARRAY['2025-01-07 10:00:00'::TIMESTAMP,'2026-01-06 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=1TU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.3: YEARLY BYDAY=1WE (1st Wednesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.3: YEARLY BYDAY=1WE (1st Wednesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=1WE',
        ARRAY['2025-01-01 10:00:00'::TIMESTAMP,'2026-01-07 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=1WE;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.4: YEARLY BYDAY=1TH (1st Thursday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.4: YEARLY BYDAY=1TH (1st Thursday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=1TH',
        ARRAY['2025-01-02 10:00:00'::TIMESTAMP,'2026-01-01 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=1TH;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.5: YEARLY BYDAY=1FR (1st Friday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.5: YEARLY BYDAY=1FR (1st Friday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=1FR',
        ARRAY['2025-01-03 10:00:00'::TIMESTAMP,'2026-01-02 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=1FR;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.6: YEARLY BYDAY=1SA (1st Saturday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.6: YEARLY BYDAY=1SA (1st Saturday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=1SA',
        ARRAY['2025-01-04 10:00:00'::TIMESTAMP,'2026-01-03 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=1SA;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.7: YEARLY BYDAY=1SU (1st Sunday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.7: YEARLY BYDAY=1SU (1st Sunday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=1SU',
        ARRAY['2025-01-05 10:00:00'::TIMESTAMP,'2026-01-04 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=1SU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.8: YEARLY BYDAY=2MO (2nd Monday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.8: YEARLY BYDAY=2MO (2nd Monday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=2MO',
        ARRAY['2025-01-13 10:00:00'::TIMESTAMP,'2026-01-12 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=2MO;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.9: YEARLY BYDAY=2TU (2nd Tuesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.9: YEARLY BYDAY=2TU (2nd Tuesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=2TU',
        ARRAY['2025-01-14 10:00:00'::TIMESTAMP,'2026-01-13 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=2TU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.10: YEARLY BYDAY=2WE (2nd Wednesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.10: YEARLY BYDAY=2WE (2nd Wednesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=2WE',
        ARRAY['2025-01-08 10:00:00'::TIMESTAMP,'2026-01-14 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=2WE;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.11: YEARLY BYDAY=2TH (2nd Thursday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.11: YEARLY BYDAY=2TH (2nd Thursday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=2TH',
        ARRAY['2025-01-09 10:00:00'::TIMESTAMP,'2026-01-08 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=2TH;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.12: YEARLY BYDAY=2FR (2nd Friday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.12: YEARLY BYDAY=2FR (2nd Friday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=2FR',
        ARRAY['2025-01-10 10:00:00'::TIMESTAMP,'2026-01-09 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=2FR;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.13: YEARLY BYDAY=2SA (2nd Saturday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.13: YEARLY BYDAY=2SA (2nd Saturday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=2SA',
        ARRAY['2025-01-11 10:00:00'::TIMESTAMP,'2026-01-10 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=2SA;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.14: YEARLY BYDAY=2SU (2nd Sunday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.14: YEARLY BYDAY=2SU (2nd Sunday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=2SU',
        ARRAY['2025-01-12 10:00:00'::TIMESTAMP,'2026-01-11 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=2SU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.15: YEARLY BYDAY=3MO (3rd Monday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.15: YEARLY BYDAY=3MO (3rd Monday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=3MO',
        ARRAY['2025-01-20 10:00:00'::TIMESTAMP,'2026-01-19 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=3MO;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.16: YEARLY BYDAY=3TU (3rd Tuesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.16: YEARLY BYDAY=3TU (3rd Tuesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=3TU',
        ARRAY['2025-01-21 10:00:00'::TIMESTAMP,'2026-01-20 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=3TU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.17: YEARLY BYDAY=3WE (3rd Wednesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.17: YEARLY BYDAY=3WE (3rd Wednesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=3WE',
        ARRAY['2025-01-15 10:00:00'::TIMESTAMP,'2026-01-21 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=3WE;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.18: YEARLY BYDAY=3TH (3rd Thursday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.18: YEARLY BYDAY=3TH (3rd Thursday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=3TH',
        ARRAY['2025-01-16 10:00:00'::TIMESTAMP,'2026-01-15 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=3TH;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.19: YEARLY BYDAY=3FR (3rd Friday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.19: YEARLY BYDAY=3FR (3rd Friday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=3FR',
        ARRAY['2025-01-17 10:00:00'::TIMESTAMP,'2026-01-16 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=3FR;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.20: YEARLY BYDAY=3SA (3rd Saturday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.20: YEARLY BYDAY=3SA (3rd Saturday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=3SA',
        ARRAY['2025-01-18 10:00:00'::TIMESTAMP,'2026-01-17 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=3SA;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.21: YEARLY BYDAY=3SU (3rd Sunday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.21: YEARLY BYDAY=3SU (3rd Sunday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=3SU',
        ARRAY['2025-01-19 10:00:00'::TIMESTAMP,'2026-01-18 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=3SU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.22: YEARLY BYDAY=4MO (4th Monday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.22: YEARLY BYDAY=4MO (4th Monday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=4MO',
        ARRAY['2025-01-27 10:00:00'::TIMESTAMP,'2026-01-26 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=4MO;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.23: YEARLY BYDAY=4TU (4th Tuesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.23: YEARLY BYDAY=4TU (4th Tuesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=4TU',
        ARRAY['2025-01-28 10:00:00'::TIMESTAMP,'2026-01-27 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=4TU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.24: YEARLY BYDAY=4WE (4th Wednesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.24: YEARLY BYDAY=4WE (4th Wednesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=4WE',
        ARRAY['2025-01-22 10:00:00'::TIMESTAMP,'2026-01-28 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=4WE;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.25: YEARLY BYDAY=4TH (4th Thursday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.25: YEARLY BYDAY=4TH (4th Thursday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=4TH',
        ARRAY['2025-01-23 10:00:00'::TIMESTAMP,'2026-01-22 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=4TH;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.26: YEARLY BYDAY=4FR (4th Friday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.26: YEARLY BYDAY=4FR (4th Friday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=4FR',
        ARRAY['2025-01-24 10:00:00'::TIMESTAMP,'2026-01-23 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=4FR;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.27: YEARLY BYDAY=4SA (4th Saturday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.27: YEARLY BYDAY=4SA (4th Saturday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=4SA',
        ARRAY['2025-01-25 10:00:00'::TIMESTAMP,'2026-01-24 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=4SA;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.28: YEARLY BYDAY=4SU (4th Sunday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.28: YEARLY BYDAY=4SU (4th Sunday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=4SU',
        ARRAY['2025-01-26 10:00:00'::TIMESTAMP,'2026-01-25 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=4SU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.29: YEARLY BYDAY=5MO (5th Monday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.29: YEARLY BYDAY=5MO (5th Monday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=5MO',
        ARRAY['2025-02-03 10:00:00'::TIMESTAMP,'2026-02-02 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=5MO;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.30: YEARLY BYDAY=5TU (5th Tuesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.30: YEARLY BYDAY=5TU (5th Tuesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=5TU',
        ARRAY['2025-02-04 10:00:00'::TIMESTAMP,'2026-02-03 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=5TU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.31: YEARLY BYDAY=5WE (5th Wednesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.31: YEARLY BYDAY=5WE (5th Wednesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=5WE',
        ARRAY['2025-01-29 10:00:00'::TIMESTAMP,'2026-02-04 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=5WE;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.32: YEARLY BYDAY=5TH (5th Thursday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.32: YEARLY BYDAY=5TH (5th Thursday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=5TH',
        ARRAY['2025-01-30 10:00:00'::TIMESTAMP,'2026-01-29 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=5TH;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.33: YEARLY BYDAY=5FR (5th Friday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.33: YEARLY BYDAY=5FR (5th Friday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=5FR',
        ARRAY['2025-01-31 10:00:00'::TIMESTAMP,'2026-01-30 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=5FR;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.34: YEARLY BYDAY=5SA (5th Saturday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.34: YEARLY BYDAY=5SA (5th Saturday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=5SA',
        ARRAY['2025-02-01 10:00:00'::TIMESTAMP,'2026-01-31 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=5SA;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 27.35: YEARLY BYDAY=5SU (5th Sunday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Ordinals',
    'Test 27.35: YEARLY BYDAY=5SU (5th Sunday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=5SU',
        ARRAY['2025-02-02 10:00:00'::TIMESTAMP,'2026-02-01 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=5SU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- Section 28: YEARLY BYDAY Negative Ordinals
-- ============================================================================
\echo 'Section 28: YEARLY BYDAY Negative Ordinals...'

-- Test 28.1: YEARLY BYDAY=-1MO (last Monday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.1: YEARLY BYDAY=-1MO (last Monday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-1MO',
        ARRAY['2025-12-29 10:00:00'::TIMESTAMP,'2026-12-28 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-1MO;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.2: YEARLY BYDAY=-1TU (last Tuesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.2: YEARLY BYDAY=-1TU (last Tuesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-1TU',
        ARRAY['2025-12-30 10:00:00'::TIMESTAMP,'2026-12-29 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-1TU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.3: YEARLY BYDAY=-1WE (last Wednesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.3: YEARLY BYDAY=-1WE (last Wednesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-1WE',
        ARRAY['2025-12-31 10:00:00'::TIMESTAMP,'2026-12-30 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-1WE;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.4: YEARLY BYDAY=-1TH (last Thursday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.4: YEARLY BYDAY=-1TH (last Thursday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-1TH',
        ARRAY['2025-12-25 10:00:00'::TIMESTAMP,'2026-12-31 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-1TH;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.5: YEARLY BYDAY=-1FR (last Friday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.5: YEARLY BYDAY=-1FR (last Friday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-1FR',
        ARRAY['2025-12-26 10:00:00'::TIMESTAMP,'2026-12-25 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-1FR;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.6: YEARLY BYDAY=-1SA (last Saturday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.6: YEARLY BYDAY=-1SA (last Saturday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-1SA',
        ARRAY['2025-12-27 10:00:00'::TIMESTAMP,'2026-12-26 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-1SA;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.7: YEARLY BYDAY=-1SU (last Sunday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.7: YEARLY BYDAY=-1SU (last Sunday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-1SU',
        ARRAY['2025-12-28 10:00:00'::TIMESTAMP,'2026-12-27 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-1SU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.8: YEARLY BYDAY=-2MO (2nd-last Monday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.8: YEARLY BYDAY=-2MO (2nd-last Monday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-2MO',
        ARRAY['2025-12-22 10:00:00'::TIMESTAMP,'2026-12-21 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-2MO;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.9: YEARLY BYDAY=-2TU (2nd-last Tuesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.9: YEARLY BYDAY=-2TU (2nd-last Tuesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-2TU',
        ARRAY['2025-12-23 10:00:00'::TIMESTAMP,'2026-12-22 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-2TU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.10: YEARLY BYDAY=-2WE (2nd-last Wednesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.10: YEARLY BYDAY=-2WE (2nd-last Wednesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-2WE',
        ARRAY['2025-12-24 10:00:00'::TIMESTAMP,'2026-12-23 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-2WE;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.11: YEARLY BYDAY=-2TH (2nd-last Thursday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.11: YEARLY BYDAY=-2TH (2nd-last Thursday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-2TH',
        ARRAY['2025-12-18 10:00:00'::TIMESTAMP,'2026-12-24 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-2TH;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.12: YEARLY BYDAY=-2FR (2nd-last Friday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.12: YEARLY BYDAY=-2FR (2nd-last Friday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-2FR',
        ARRAY['2025-12-19 10:00:00'::TIMESTAMP,'2026-12-18 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-2FR;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.13: YEARLY BYDAY=-2SA (2nd-last Saturday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.13: YEARLY BYDAY=-2SA (2nd-last Saturday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-2SA',
        ARRAY['2025-12-20 10:00:00'::TIMESTAMP,'2026-12-19 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-2SA;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.14: YEARLY BYDAY=-2SU (2nd-last Sunday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.14: YEARLY BYDAY=-2SU (2nd-last Sunday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-2SU',
        ARRAY['2025-12-21 10:00:00'::TIMESTAMP,'2026-12-20 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-2SU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.15: YEARLY BYDAY=-3MO (3rd-last Monday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.15: YEARLY BYDAY=-3MO (3rd-last Monday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-3MO',
        ARRAY['2025-12-15 10:00:00'::TIMESTAMP,'2026-12-14 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-3MO;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.16: YEARLY BYDAY=-3TU (3rd-last Tuesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.16: YEARLY BYDAY=-3TU (3rd-last Tuesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-3TU',
        ARRAY['2025-12-16 10:00:00'::TIMESTAMP,'2026-12-15 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-3TU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.17: YEARLY BYDAY=-3WE (3rd-last Wednesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.17: YEARLY BYDAY=-3WE (3rd-last Wednesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-3WE',
        ARRAY['2025-12-17 10:00:00'::TIMESTAMP,'2026-12-16 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-3WE;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.18: YEARLY BYDAY=-3TH (3rd-last Thursday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.18: YEARLY BYDAY=-3TH (3rd-last Thursday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-3TH',
        ARRAY['2025-12-11 10:00:00'::TIMESTAMP,'2026-12-17 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-3TH;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.19: YEARLY BYDAY=-3FR (3rd-last Friday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.19: YEARLY BYDAY=-3FR (3rd-last Friday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-3FR',
        ARRAY['2025-12-12 10:00:00'::TIMESTAMP,'2026-12-11 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-3FR;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.20: YEARLY BYDAY=-3SA (3rd-last Saturday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.20: YEARLY BYDAY=-3SA (3rd-last Saturday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-3SA',
        ARRAY['2025-12-13 10:00:00'::TIMESTAMP,'2026-12-12 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-3SA;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.21: YEARLY BYDAY=-3SU (3rd-last Sunday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.21: YEARLY BYDAY=-3SU (3rd-last Sunday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-3SU',
        ARRAY['2025-12-14 10:00:00'::TIMESTAMP,'2026-12-13 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-3SU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.22: YEARLY BYDAY=-4MO (4th-last Monday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.22: YEARLY BYDAY=-4MO (4th-last Monday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-4MO',
        ARRAY['2025-12-08 10:00:00'::TIMESTAMP,'2026-12-07 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-4MO;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.23: YEARLY BYDAY=-4TU (4th-last Tuesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.23: YEARLY BYDAY=-4TU (4th-last Tuesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-4TU',
        ARRAY['2025-12-09 10:00:00'::TIMESTAMP,'2026-12-08 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-4TU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.24: YEARLY BYDAY=-4WE (4th-last Wednesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.24: YEARLY BYDAY=-4WE (4th-last Wednesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-4WE',
        ARRAY['2025-12-10 10:00:00'::TIMESTAMP,'2026-12-09 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-4WE;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.25: YEARLY BYDAY=-4TH (4th-last Thursday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.25: YEARLY BYDAY=-4TH (4th-last Thursday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-4TH',
        ARRAY['2025-12-04 10:00:00'::TIMESTAMP,'2026-12-10 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-4TH;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.26: YEARLY BYDAY=-4FR (4th-last Friday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.26: YEARLY BYDAY=-4FR (4th-last Friday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-4FR',
        ARRAY['2025-12-05 10:00:00'::TIMESTAMP,'2026-12-04 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-4FR;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.27: YEARLY BYDAY=-4SA (4th-last Saturday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.27: YEARLY BYDAY=-4SA (4th-last Saturday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-4SA',
        ARRAY['2025-12-06 10:00:00'::TIMESTAMP,'2026-12-05 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-4SA;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.28: YEARLY BYDAY=-4SU (4th-last Sunday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.28: YEARLY BYDAY=-4SU (4th-last Sunday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-4SU',
        ARRAY['2025-12-07 10:00:00'::TIMESTAMP,'2026-12-06 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-4SU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.29: YEARLY BYDAY=-5MO (5th-last Monday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.29: YEARLY BYDAY=-5MO (5th-last Monday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-5MO',
        ARRAY['2025-12-01 10:00:00'::TIMESTAMP,'2026-11-30 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-5MO;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.30: YEARLY BYDAY=-5TU (5th-last Tuesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.30: YEARLY BYDAY=-5TU (5th-last Tuesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-5TU',
        ARRAY['2025-12-02 10:00:00'::TIMESTAMP,'2026-12-01 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-5TU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.31: YEARLY BYDAY=-5WE (5th-last Wednesday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.31: YEARLY BYDAY=-5WE (5th-last Wednesday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-5WE',
        ARRAY['2025-12-03 10:00:00'::TIMESTAMP,'2026-12-02 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-5WE;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.32: YEARLY BYDAY=-5TH (5th-last Thursday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.32: YEARLY BYDAY=-5TH (5th-last Thursday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-5TH',
        ARRAY['2025-11-27 10:00:00'::TIMESTAMP,'2026-12-03 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-5TH;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.33: YEARLY BYDAY=-5FR (5th-last Friday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.33: YEARLY BYDAY=-5FR (5th-last Friday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-5FR',
        ARRAY['2025-11-28 10:00:00'::TIMESTAMP,'2026-11-27 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-5FR;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.34: YEARLY BYDAY=-5SA (5th-last Saturday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.34: YEARLY BYDAY=-5SA (5th-last Saturday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-5SA',
        ARRAY['2025-11-29 10:00:00'::TIMESTAMP,'2026-11-28 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-5SA;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 28.35: YEARLY BYDAY=-5SU (5th-last Sunday of year)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Negative Ordinals',
    'Test 28.35: YEARLY BYDAY=-5SU (5th-last Sunday of year)',
    assert_occurrences_equal(
        'YEARLY BYDAY=-5SU',
        ARRAY['2025-11-30 10:00:00'::TIMESTAMP,'2026-11-29 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-5SU;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- Section 29: BYMONTHDAY Positive
-- ============================================================================
\echo 'Section 29: BYMONTHDAY Positive...'

-- Test 29.1: BYMONTHDAY=1
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.1: BYMONTHDAY=1',
    assert_occurrences_equal(
        'BYMONTHDAY=1',
        ARRAY['2025-01-01 10:00:00'::TIMESTAMP,'2025-02-01 10:00:00'::TIMESTAMP,'2025-03-01 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=1;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.2: BYMONTHDAY=2
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.2: BYMONTHDAY=2',
    assert_occurrences_equal(
        'BYMONTHDAY=2',
        ARRAY['2025-01-02 10:00:00'::TIMESTAMP,'2025-02-02 10:00:00'::TIMESTAMP,'2025-03-02 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=2;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.3: BYMONTHDAY=3
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.3: BYMONTHDAY=3',
    assert_occurrences_equal(
        'BYMONTHDAY=3',
        ARRAY['2025-01-03 10:00:00'::TIMESTAMP,'2025-02-03 10:00:00'::TIMESTAMP,'2025-03-03 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=3;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.4: BYMONTHDAY=4
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.4: BYMONTHDAY=4',
    assert_occurrences_equal(
        'BYMONTHDAY=4',
        ARRAY['2025-01-04 10:00:00'::TIMESTAMP,'2025-02-04 10:00:00'::TIMESTAMP,'2025-03-04 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=4;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.5: BYMONTHDAY=5
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.5: BYMONTHDAY=5',
    assert_occurrences_equal(
        'BYMONTHDAY=5',
        ARRAY['2025-01-05 10:00:00'::TIMESTAMP,'2025-02-05 10:00:00'::TIMESTAMP,'2025-03-05 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=5;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.6: BYMONTHDAY=6
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.6: BYMONTHDAY=6',
    assert_occurrences_equal(
        'BYMONTHDAY=6',
        ARRAY['2025-01-06 10:00:00'::TIMESTAMP,'2025-02-06 10:00:00'::TIMESTAMP,'2025-03-06 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=6;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.7: BYMONTHDAY=7
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.7: BYMONTHDAY=7',
    assert_occurrences_equal(
        'BYMONTHDAY=7',
        ARRAY['2025-01-07 10:00:00'::TIMESTAMP,'2025-02-07 10:00:00'::TIMESTAMP,'2025-03-07 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=7;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.8: BYMONTHDAY=8
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.8: BYMONTHDAY=8',
    assert_occurrences_equal(
        'BYMONTHDAY=8',
        ARRAY['2025-01-08 10:00:00'::TIMESTAMP,'2025-02-08 10:00:00'::TIMESTAMP,'2025-03-08 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=8;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.9: BYMONTHDAY=9
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.9: BYMONTHDAY=9',
    assert_occurrences_equal(
        'BYMONTHDAY=9',
        ARRAY['2025-01-09 10:00:00'::TIMESTAMP,'2025-02-09 10:00:00'::TIMESTAMP,'2025-03-09 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=9;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.10: BYMONTHDAY=10
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.10: BYMONTHDAY=10',
    assert_occurrences_equal(
        'BYMONTHDAY=10',
        ARRAY['2025-01-10 10:00:00'::TIMESTAMP,'2025-02-10 10:00:00'::TIMESTAMP,'2025-03-10 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=10;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.11: BYMONTHDAY=11
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.11: BYMONTHDAY=11',
    assert_occurrences_equal(
        'BYMONTHDAY=11',
        ARRAY['2025-01-11 10:00:00'::TIMESTAMP,'2025-02-11 10:00:00'::TIMESTAMP,'2025-03-11 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=11;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.12: BYMONTHDAY=12
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.12: BYMONTHDAY=12',
    assert_occurrences_equal(
        'BYMONTHDAY=12',
        ARRAY['2025-01-12 10:00:00'::TIMESTAMP,'2025-02-12 10:00:00'::TIMESTAMP,'2025-03-12 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=12;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.13: BYMONTHDAY=13
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.13: BYMONTHDAY=13',
    assert_occurrences_equal(
        'BYMONTHDAY=13',
        ARRAY['2025-01-13 10:00:00'::TIMESTAMP,'2025-02-13 10:00:00'::TIMESTAMP,'2025-03-13 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=13;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.14: BYMONTHDAY=14
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.14: BYMONTHDAY=14',
    assert_occurrences_equal(
        'BYMONTHDAY=14',
        ARRAY['2025-01-14 10:00:00'::TIMESTAMP,'2025-02-14 10:00:00'::TIMESTAMP,'2025-03-14 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=14;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.15: BYMONTHDAY=15
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.15: BYMONTHDAY=15',
    assert_occurrences_equal(
        'BYMONTHDAY=15',
        ARRAY['2025-01-15 10:00:00'::TIMESTAMP,'2025-02-15 10:00:00'::TIMESTAMP,'2025-03-15 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.16: BYMONTHDAY=16
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.16: BYMONTHDAY=16',
    assert_occurrences_equal(
        'BYMONTHDAY=16',
        ARRAY['2025-01-16 10:00:00'::TIMESTAMP,'2025-02-16 10:00:00'::TIMESTAMP,'2025-03-16 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=16;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.17: BYMONTHDAY=17
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.17: BYMONTHDAY=17',
    assert_occurrences_equal(
        'BYMONTHDAY=17',
        ARRAY['2025-01-17 10:00:00'::TIMESTAMP,'2025-02-17 10:00:00'::TIMESTAMP,'2025-03-17 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=17;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.18: BYMONTHDAY=18
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.18: BYMONTHDAY=18',
    assert_occurrences_equal(
        'BYMONTHDAY=18',
        ARRAY['2025-01-18 10:00:00'::TIMESTAMP,'2025-02-18 10:00:00'::TIMESTAMP,'2025-03-18 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=18;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.19: BYMONTHDAY=19
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.19: BYMONTHDAY=19',
    assert_occurrences_equal(
        'BYMONTHDAY=19',
        ARRAY['2025-01-19 10:00:00'::TIMESTAMP,'2025-02-19 10:00:00'::TIMESTAMP,'2025-03-19 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=19;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.20: BYMONTHDAY=20
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.20: BYMONTHDAY=20',
    assert_occurrences_equal(
        'BYMONTHDAY=20',
        ARRAY['2025-01-20 10:00:00'::TIMESTAMP,'2025-02-20 10:00:00'::TIMESTAMP,'2025-03-20 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=20;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.21: BYMONTHDAY=21
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.21: BYMONTHDAY=21',
    assert_occurrences_equal(
        'BYMONTHDAY=21',
        ARRAY['2025-01-21 10:00:00'::TIMESTAMP,'2025-02-21 10:00:00'::TIMESTAMP,'2025-03-21 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=21;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.22: BYMONTHDAY=22
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.22: BYMONTHDAY=22',
    assert_occurrences_equal(
        'BYMONTHDAY=22',
        ARRAY['2025-01-22 10:00:00'::TIMESTAMP,'2025-02-22 10:00:00'::TIMESTAMP,'2025-03-22 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=22;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.23: BYMONTHDAY=23
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.23: BYMONTHDAY=23',
    assert_occurrences_equal(
        'BYMONTHDAY=23',
        ARRAY['2025-01-23 10:00:00'::TIMESTAMP,'2025-02-23 10:00:00'::TIMESTAMP,'2025-03-23 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=23;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.24: BYMONTHDAY=24
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.24: BYMONTHDAY=24',
    assert_occurrences_equal(
        'BYMONTHDAY=24',
        ARRAY['2025-01-24 10:00:00'::TIMESTAMP,'2025-02-24 10:00:00'::TIMESTAMP,'2025-03-24 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=24;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.25: BYMONTHDAY=25
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.25: BYMONTHDAY=25',
    assert_occurrences_equal(
        'BYMONTHDAY=25',
        ARRAY['2025-01-25 10:00:00'::TIMESTAMP,'2025-02-25 10:00:00'::TIMESTAMP,'2025-03-25 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=25;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.26: BYMONTHDAY=26
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.26: BYMONTHDAY=26',
    assert_occurrences_equal(
        'BYMONTHDAY=26',
        ARRAY['2025-01-26 10:00:00'::TIMESTAMP,'2025-02-26 10:00:00'::TIMESTAMP,'2025-03-26 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=26;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.27: BYMONTHDAY=27
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.27: BYMONTHDAY=27',
    assert_occurrences_equal(
        'BYMONTHDAY=27',
        ARRAY['2025-01-27 10:00:00'::TIMESTAMP,'2025-02-27 10:00:00'::TIMESTAMP,'2025-03-27 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=27;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.28: BYMONTHDAY=28
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.28: BYMONTHDAY=28',
    assert_occurrences_equal(
        'BYMONTHDAY=28',
        ARRAY['2025-01-28 10:00:00'::TIMESTAMP,'2025-02-28 10:00:00'::TIMESTAMP,'2025-03-28 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=28;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.29: BYMONTHDAY=29
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.29: BYMONTHDAY=29',
    assert_occurrences_equal(
        'BYMONTHDAY=29',
        ARRAY['2025-01-29 10:00:00'::TIMESTAMP,'2025-03-29 10:00:00'::TIMESTAMP,'2025-04-29 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=29;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.30: BYMONTHDAY=30
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.30: BYMONTHDAY=30',
    assert_occurrences_equal(
        'BYMONTHDAY=30',
        ARRAY['2025-01-30 10:00:00'::TIMESTAMP,'2025-03-30 10:00:00'::TIMESTAMP,'2025-04-30 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=30;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 29.31: BYMONTHDAY=31
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Positive',
    'Test 29.31: BYMONTHDAY=31',
    assert_occurrences_equal(
        'BYMONTHDAY=31',
        ARRAY['2025-01-31 10:00:00'::TIMESTAMP,'2025-03-31 10:00:00'::TIMESTAMP,'2025-05-31 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- Section 30: BYMONTHDAY Negative
-- ============================================================================
\echo 'Section 30: BYMONTHDAY Negative...'

-- Test 30.1: BYMONTHDAY=-1 (1th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.1: BYMONTHDAY=-1 (1th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-1',
        ARRAY['2025-01-31 10:00:00'::TIMESTAMP,'2025-02-28 10:00:00'::TIMESTAMP,'2025-03-31 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.2: BYMONTHDAY=-2 (2th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.2: BYMONTHDAY=-2 (2th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-2',
        ARRAY['2025-01-30 10:00:00'::TIMESTAMP,'2025-02-27 10:00:00'::TIMESTAMP,'2025-03-30 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-2;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.3: BYMONTHDAY=-3 (3th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.3: BYMONTHDAY=-3 (3th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-3',
        ARRAY['2025-01-29 10:00:00'::TIMESTAMP,'2025-02-26 10:00:00'::TIMESTAMP,'2025-03-29 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-3;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.4: BYMONTHDAY=-4 (4th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.4: BYMONTHDAY=-4 (4th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-4',
        ARRAY['2025-01-28 10:00:00'::TIMESTAMP,'2025-02-25 10:00:00'::TIMESTAMP,'2025-03-28 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-4;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.5: BYMONTHDAY=-5 (5th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.5: BYMONTHDAY=-5 (5th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-5',
        ARRAY['2025-01-27 10:00:00'::TIMESTAMP,'2025-02-24 10:00:00'::TIMESTAMP,'2025-03-27 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-5;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.6: BYMONTHDAY=-6 (6th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.6: BYMONTHDAY=-6 (6th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-6',
        ARRAY['2025-01-26 10:00:00'::TIMESTAMP,'2025-02-23 10:00:00'::TIMESTAMP,'2025-03-26 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-6;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.7: BYMONTHDAY=-7 (7th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.7: BYMONTHDAY=-7 (7th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-7',
        ARRAY['2025-01-25 10:00:00'::TIMESTAMP,'2025-02-22 10:00:00'::TIMESTAMP,'2025-03-25 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-7;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.8: BYMONTHDAY=-8 (8th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.8: BYMONTHDAY=-8 (8th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-8',
        ARRAY['2025-01-24 10:00:00'::TIMESTAMP,'2025-02-21 10:00:00'::TIMESTAMP,'2025-03-24 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-8;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.9: BYMONTHDAY=-9 (9th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.9: BYMONTHDAY=-9 (9th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-9',
        ARRAY['2025-01-23 10:00:00'::TIMESTAMP,'2025-02-20 10:00:00'::TIMESTAMP,'2025-03-23 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-9;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.10: BYMONTHDAY=-10 (10th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.10: BYMONTHDAY=-10 (10th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-10',
        ARRAY['2025-01-22 10:00:00'::TIMESTAMP,'2025-02-19 10:00:00'::TIMESTAMP,'2025-03-22 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-10;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.11: BYMONTHDAY=-11 (11th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.11: BYMONTHDAY=-11 (11th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-11',
        ARRAY['2025-01-21 10:00:00'::TIMESTAMP,'2025-02-18 10:00:00'::TIMESTAMP,'2025-03-21 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-11;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.12: BYMONTHDAY=-12 (12th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.12: BYMONTHDAY=-12 (12th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-12',
        ARRAY['2025-01-20 10:00:00'::TIMESTAMP,'2025-02-17 10:00:00'::TIMESTAMP,'2025-03-20 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-12;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.13: BYMONTHDAY=-13 (13th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.13: BYMONTHDAY=-13 (13th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-13',
        ARRAY['2025-01-19 10:00:00'::TIMESTAMP,'2025-02-16 10:00:00'::TIMESTAMP,'2025-03-19 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-13;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.14: BYMONTHDAY=-14 (14th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.14: BYMONTHDAY=-14 (14th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-14',
        ARRAY['2025-01-18 10:00:00'::TIMESTAMP,'2025-02-15 10:00:00'::TIMESTAMP,'2025-03-18 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-14;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.15: BYMONTHDAY=-15 (15th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.15: BYMONTHDAY=-15 (15th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-15',
        ARRAY['2025-01-17 10:00:00'::TIMESTAMP,'2025-02-14 10:00:00'::TIMESTAMP,'2025-03-17 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-15;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.16: BYMONTHDAY=-16 (16th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.16: BYMONTHDAY=-16 (16th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-16',
        ARRAY['2025-01-16 10:00:00'::TIMESTAMP,'2025-02-13 10:00:00'::TIMESTAMP,'2025-03-16 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-16;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.17: BYMONTHDAY=-17 (17th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.17: BYMONTHDAY=-17 (17th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-17',
        ARRAY['2025-01-15 10:00:00'::TIMESTAMP,'2025-02-12 10:00:00'::TIMESTAMP,'2025-03-15 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-17;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.18: BYMONTHDAY=-18 (18th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.18: BYMONTHDAY=-18 (18th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-18',
        ARRAY['2025-01-14 10:00:00'::TIMESTAMP,'2025-02-11 10:00:00'::TIMESTAMP,'2025-03-14 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-18;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.19: BYMONTHDAY=-19 (19th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.19: BYMONTHDAY=-19 (19th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-19',
        ARRAY['2025-01-13 10:00:00'::TIMESTAMP,'2025-02-10 10:00:00'::TIMESTAMP,'2025-03-13 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-19;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.20: BYMONTHDAY=-20 (20th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.20: BYMONTHDAY=-20 (20th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-20',
        ARRAY['2025-01-12 10:00:00'::TIMESTAMP,'2025-02-09 10:00:00'::TIMESTAMP,'2025-03-12 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-20;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.21: BYMONTHDAY=-21 (21th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.21: BYMONTHDAY=-21 (21th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-21',
        ARRAY['2025-01-11 10:00:00'::TIMESTAMP,'2025-02-08 10:00:00'::TIMESTAMP,'2025-03-11 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-21;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.22: BYMONTHDAY=-22 (22th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.22: BYMONTHDAY=-22 (22th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-22',
        ARRAY['2025-01-10 10:00:00'::TIMESTAMP,'2025-02-07 10:00:00'::TIMESTAMP,'2025-03-10 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-22;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.23: BYMONTHDAY=-23 (23th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.23: BYMONTHDAY=-23 (23th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-23',
        ARRAY['2025-01-09 10:00:00'::TIMESTAMP,'2025-02-06 10:00:00'::TIMESTAMP,'2025-03-09 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-23;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.24: BYMONTHDAY=-24 (24th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.24: BYMONTHDAY=-24 (24th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-24',
        ARRAY['2025-01-08 10:00:00'::TIMESTAMP,'2025-02-05 10:00:00'::TIMESTAMP,'2025-03-08 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-24;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.25: BYMONTHDAY=-25 (25th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.25: BYMONTHDAY=-25 (25th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-25',
        ARRAY['2025-01-07 10:00:00'::TIMESTAMP,'2025-02-04 10:00:00'::TIMESTAMP,'2025-03-07 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-25;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.26: BYMONTHDAY=-26 (26th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.26: BYMONTHDAY=-26 (26th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-26',
        ARRAY['2025-01-06 10:00:00'::TIMESTAMP,'2025-02-03 10:00:00'::TIMESTAMP,'2025-03-06 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-26;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.27: BYMONTHDAY=-27 (27th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.27: BYMONTHDAY=-27 (27th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-27',
        ARRAY['2025-01-05 10:00:00'::TIMESTAMP,'2025-02-02 10:00:00'::TIMESTAMP,'2025-03-05 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-27;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.28: BYMONTHDAY=-28 (28th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.28: BYMONTHDAY=-28 (28th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-28',
        ARRAY['2025-01-04 10:00:00'::TIMESTAMP,'2025-02-01 10:00:00'::TIMESTAMP,'2025-03-04 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-28;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.29: BYMONTHDAY=-29 (29th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.29: BYMONTHDAY=-29 (29th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-29',
        ARRAY['2025-01-03 10:00:00'::TIMESTAMP,'2025-03-03 10:00:00'::TIMESTAMP,'2025-04-02 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-29;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.30: BYMONTHDAY=-30 (30th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.30: BYMONTHDAY=-30 (30th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-30',
        ARRAY['2025-01-02 10:00:00'::TIMESTAMP,'2025-03-02 10:00:00'::TIMESTAMP,'2025-04-01 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-30;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 30.31: BYMONTHDAY=-31 (31th from end)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYMONTHDAY Negative',
    'Test 30.31: BYMONTHDAY=-31 (31th from end)',
    assert_occurrences_equal(
        'BYMONTHDAY=-31',
        ARRAY['2025-01-01 10:00:00'::TIMESTAMP,'2025-03-01 10:00:00'::TIMESTAMP,'2025-05-01 10:00:00'::TIMESTAMP],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=-31;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- Section 31: Consensus Review — TRUE CONCERN Gap Tests
-- Tests added to address gaps identified by 3-agent consensus review.
-- ============================================================================
\echo ''
\echo '--- Section 31: Consensus Review Gap Tests ---'

-- Test 31.1: YEARLY INTERVAL=2 SKIP=BACKWARD from Feb 29 leap year
-- 2024 leap -> Feb 29, 2026 non-leap -> Feb 28 (backward), 2028 leap -> Feb 29, 2030 non-leap -> Feb 28
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY SKIP INTERVAL',
    'Test 31.1: YEARLY INTERVAL=2 SKIP=BACKWARD from Feb 29',
    assert_occurrences_equal(
        'YEARLY INTERVAL=2 SKIP=BACKWARD',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2026-02-28 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP,
            '2030-02-28 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;INTERVAL=2;SKIP=BACKWARD;RSCALE=GREGORIAN;COUNT=4',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 31.2: YEARLY INTERVAL=2 SKIP=FORWARD from Feb 29 leap year
-- 2024 leap -> Feb 29, 2026 non-leap -> Mar 1 (forward), 2028 leap -> Feb 29, 2030 non-leap -> Mar 1
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY SKIP INTERVAL',
    'Test 31.2: YEARLY INTERVAL=2 SKIP=FORWARD from Feb 29',
    assert_occurrences_equal(
        'YEARLY INTERVAL=2 SKIP=FORWARD',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2026-03-01 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP,
            '2030-03-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;INTERVAL=2;SKIP=FORWARD;RSCALE=GREGORIAN;COUNT=4',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 31.3: YEARLY BYDAY=20MO (20th Monday of year)
-- 2025: 20th Monday = May 19. 2026: 20th Monday = May 18. 2027: 20th Monday = May 17.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Large Ordinal',
    'Test 31.3: YEARLY BYDAY=20MO (20th Monday)',
    assert_occurrences_equal(
        'YEARLY BYDAY=20MO',
        ARRAY[
            '2025-05-19 10:00:00'::TIMESTAMP,
            '2026-05-18 10:00:00'::TIMESTAMP,
            '2027-05-17 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=20MO;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 31.4: YEARLY BYDAY=53MO (53rd Monday — only years with 53 Mondays)
-- 2024 starts on Mon, has 53 Mondays: 53rd = Dec 30. 2029 starts on Mon: 53rd = Dec 31.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'YEARLY BYDAY Large Ordinal',
    'Test 31.4: YEARLY BYDAY=53MO (53rd Monday, sparse)',
    assert_occurrences_equal(
        'YEARLY BYDAY=53MO',
        ARRAY[
            '2024-12-30 10:00:00'::TIMESTAMP,
            '2029-12-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
            'FREQ=YEARLY;BYDAY=53MO',
            '2024-01-01 10:00:00'::TIMESTAMP,
            '2024-01-01 00:00:00'::TIMESTAMP,
            '2034-12-31 00:00:00'::TIMESTAMP,
            TRUE
        ) AS occurrence)
    );

-- Test 31.5: BYSETPOS with BYYEARDAY
-- FREQ=YEARLY;BYYEARDAY=1,100,200,-1;BYSETPOS=1,-1 selects first (Jan 1) and last (Dec 31)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'BYSETPOS BYYEARDAY',
    'Test 31.5: YEARLY BYYEARDAY=1,100,200,-1 BYSETPOS=1,-1',
    assert_occurrences_equal(
        'BYSETPOS+BYYEARDAY',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-12-31 10:00:00'::TIMESTAMP,
            '2026-01-01 10:00:00'::TIMESTAMP,
            '2026-12-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYYEARDAY=1,100,200,-1;BYSETPOS=1,-1;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 31.6: overlaps() with NULL rrule (single-event overlap check)
-- NULL rrule falls through to single-event check instead of raising exception
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps NULL RRULE',
    'Test 31.6: overlaps() with NULL rrule overlapping',
    assert_true(
        'overlaps NULL rrule single event',
        (SELECT rrule."overlaps"(
            '2025-06-15 10:00:00'::TIMESTAMPTZ,
            '2025-06-15 11:00:00'::TIMESTAMPTZ,
            NULL::TEXT,
            '2025-06-01 00:00:00'::TIMESTAMPTZ,
            '2025-06-30 00:00:00'::TIMESTAMPTZ,
            'UTC'
        ))
    );

-- Test 31.7: overlaps() with NULL rrule, non-overlapping range
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'overlaps NULL RRULE',
    'Test 31.7: overlaps() NULL rrule non-overlapping',
    assert_equals(
        'overlaps NULL rrule no overlap',
        'false',
        (SELECT rrule."overlaps"(
            '2025-06-15 10:00:00'::TIMESTAMPTZ,
            '2025-06-15 11:00:00'::TIMESTAMPTZ,
            NULL::TEXT,
            '2025-07-01 00:00:00'::TIMESTAMPTZ,
            '2025-07-31 00:00:00'::TIMESTAMPTZ,
            'UTC'
        ))::TEXT
    );

-- ============================================================================
-- Section 32: API Limits and Boundary Tests
-- Tests for public API caps, edge cases in before()/count()/version(),
-- and MONTHLY behavior when dtstart day does not exist in all months.
-- ============================================================================
\echo ''
\echo '--- Section 32: API Limits and Boundary Tests ---'

-- Test 32.1: Daily no COUNT/UNTIL hits 1000-occurrence cap
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'API Limits',
    'Test 32.1: DAILY no COUNT/UNTIL caps at 1000 occurrences',
    assert_equals(
        'DAILY 1000-occurrence cap',
        '1000',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=DAILY',
            '2025-01-01 10:00:00'::TIMESTAMP
        ))
    );

-- Test 32.2: Yearly COUNT=20 capped by 10-year window (returns 11 with inclusive boundary)
-- 10-year window is now inclusive: dtstart through dtstart + 10 years = 11 years of occurrences
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'API Limits',
    'Test 32.2: YEARLY COUNT=20 capped by 10-year window (inclusive)',
    assert_equals(
        'YEARLY COUNT=20 10-year cap',
        '11',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=YEARLY;COUNT=20',
            '2025-01-01 10:00:00'::TIMESTAMP
        ))
    );

-- Test 32.3: before() inc=TRUE at exact occurrence boundary
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'API Boundary',
    'Test 32.3: before() inc=TRUE returns occurrence at exact boundary',
    assert_equals(
        'before inc=TRUE exact boundary',
        '2025-01-03 10:00:00',
        (SELECT rrule."before"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            TRUE
        ))::TEXT
    );

-- Test 32.4: before() inc=FALSE at dtstart returns NULL (nothing strictly before)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'API Boundary',
    'Test 32.4: before() inc=FALSE at dtstart returns NULL',
    assert_equals(
        'before inc=FALSE at dtstart',
        'NULL',
        COALESCE(
            (SELECT rrule."before"(
                'FREQ=DAILY;COUNT=5',
                '2025-01-01 10:00:00'::TIMESTAMP,
                '2025-01-01 10:00:00'::TIMESTAMP,
                FALSE
            ))::TEXT,
            'NULL'
        )
    );

-- Test 32.5: count() with COUNT=1 returns exactly 1
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'API Boundary',
    'Test 32.5: count() with COUNT=1 returns 1',
    assert_equals(
        'count with COUNT=1',
        '1',
        (SELECT rrule."count"(
            'FREQ=DAILY;COUNT=1',
            '2025-01-01 10:00:00'::TIMESTAMP
        ))::TEXT
    );

-- Test 32.6: before() COUNT=1 inc=TRUE at dtstart returns dtstart
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'API Boundary',
    'Test 32.6: before() COUNT=1 inc=TRUE at dtstart returns dtstart',
    assert_equals(
        'before COUNT=1 inc=TRUE at dtstart',
        '2025-01-01 10:00:00',
        (SELECT rrule."before"(
            'FREQ=DAILY;COUNT=1',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:00:00'::TIMESTAMP,
            TRUE
        ))::TEXT
    );

-- Test 32.7: version() returns current version string
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'API Metadata',
    'Test 32.7: version() returns version string',
    assert_equals(
        'version function',
        '1.1.1',
        (SELECT rrule."version"())
    );

-- Test 32.8: Monthly COUNT=6 with dtstart day=30 skips months without 30th
-- Feb has no 30th, so it is skipped. Result: Jan, Mar, Apr, May, Jun, Jul.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'MONTHLY Day Skip',
    'Test 32.8: MONTHLY COUNT=6 dtstart day=30 skips Feb',
    assert_occurrences_equal(
        'MONTHLY day=30 skips short months',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,
            '2025-03-30 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP,
            '2025-05-30 10:00:00'::TIMESTAMP,
            '2025-06-30 10:00:00'::TIMESTAMP,
            '2025-07-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;COUNT=6',
            '2025-01-30 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- ============================================================================
-- SECTION 25: before() Beyond 1000-Result Cap
-- ============================================================================
\echo ''
\echo '--- Section 25: before() Beyond 1000-Result Cap ---'

-- Test 33.1: before() returns the 1500th occurrence (beyond the 1000-result cap)
-- FREQ=DAILY;COUNT=1500 starting 2020-01-01 produces 1500 occurrences.
-- The 1500th occurrence is 2020-01-01 + 1499 days = 2024-02-08.
-- before() uses max_count=50000000 internally, so it must find the true last
-- occurrence even though all() would cap at 1000.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() >1000 cap',
    'Test 33.1: before() finds 1500th occurrence beyond 1000-cap',
    assert_equals(
        'before beyond cap',
        '2024-02-08 00:00:00',
        (SELECT rrule."before"(
            'FREQ=DAILY;COUNT=1500',
            '2020-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            FALSE
        ))::TEXT
    );

-- Test 33.2: before() with inc=TRUE at exact 1500th occurrence boundary
-- When before_date equals the 1500th occurrence and inc=TRUE, it should
-- return that occurrence (2024-02-08).
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() >1000 cap',
    'Test 33.2: before() inc=TRUE at exact 1500th occurrence',
    assert_equals(
        'before inc=TRUE at 1500th',
        '2024-02-08 00:00:00',
        (SELECT rrule."before"(
            'FREQ=DAILY;COUNT=1500',
            '2020-01-01 00:00:00'::TIMESTAMP,
            '2024-02-08 00:00:00'::TIMESTAMP,
            TRUE
        ))::TEXT
    );

-- Test 33.3: all() caps at 1000 for the same COUNT=1500 rule
-- Confirms the 1000-result cap exists in all(), proving that before()
-- bypasses it. The 1000th daily occurrence from 2020-01-01 is
-- 2020-01-01 + 999 days = 2022-09-27.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() >1000 cap',
    'Test 33.3: all() caps at 1000 for COUNT=1500 rule',
    assert_equals(
        'all() capped at 1000',
        '1000',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=DAILY;COUNT=1500',
            '2020-01-01 00:00:00'::TIMESTAMP
        ))
    );

-- ============================================================================
-- SECTION 34: before() Safety Warning Tests
-- ============================================================================
\echo ''
\echo '=================================================='
\echo 'Testing before() safety warning for unbounded rules'
\echo '=================================================='

-- Test 34.1: TIMESTAMP before() with unbounded rule scanning >1000 occurrences
-- FREQ=DAILY from 2020-01-01 before 2025-01-01 = ~1826 occurrences (no COUNT/UNTIL)
-- Should return 2024-12-31 AND emit a warning
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Warning',
    'Test 34.1: TIMESTAMP before() unbounded rule >1000 occurrences returns correct result',
    assert_equals(
        'before() unbounded >1000',
        '2024-12-31 00:00:00',
        (SELECT rrule."before"(
            'FREQ=DAILY',
            '2020-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP
        ))::TEXT
    );

-- Test 34.2: TIMESTAMP before() with bounded rule (COUNT) - no warning
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Warning',
    'Test 34.2: TIMESTAMP before() bounded rule (COUNT=500) returns correct result',
    assert_equals(
        'before() bounded COUNT=500',
        '2021-05-14 00:00:00',
        (SELECT rrule."before"(
            'FREQ=DAILY;COUNT=500',
            '2020-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP
        ))::TEXT
    );

-- Test 34.3: TIMESTAMP before() with bounded rule (UNTIL) - no warning
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Warning',
    'Test 34.3: TIMESTAMP before() bounded rule (UNTIL) returns correct result',
    assert_equals(
        'before() bounded UNTIL',
        '2021-06-30 00:00:00',
        (SELECT rrule."before"(
            'FREQ=DAILY;UNTIL=20210630T235959Z',
            '2020-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP
        ))::TEXT
    );

-- Test 34.4: TIMESTAMPTZ before() with unbounded rule scanning >1000 occurrences
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Warning',
    'Test 34.4: TIMESTAMPTZ before() unbounded rule >1000 occurrences returns correct result',
    assert_equals(
        'before() TZ unbounded >1000',
        '2024-12-31 05:00:00+00',
        (SELECT (rrule."before"(
            'FREQ=DAILY',
            '2020-01-01 00:00:00-05'::TIMESTAMPTZ,
            '2025-01-01 00:00:00-05'::TIMESTAMPTZ,
            1,
            'America/New_York'
        ))::TEXT)
    );

-- Test 34.5: TIMESTAMPTZ before() with bounded rule - no warning
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Warning',
    'Test 34.5: TIMESTAMPTZ before() bounded rule (COUNT=100) returns correct result',
    assert_equals(
        'before() TZ bounded COUNT=100',
        '2020-04-09 04:00:00+00',
        (SELECT (rrule."before"(
            'FREQ=DAILY;COUNT=100',
            '2020-01-01 00:00:00-05'::TIMESTAMPTZ,
            '2025-01-01 00:00:00-05'::TIMESTAMPTZ,
            1,
            'America/New_York'
        ))::TEXT)
    );

-- Test 34.6: TIMESTAMP before() with small unbounded rule (<= 1000) - no warning
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'before() Warning',
    'Test 34.6: TIMESTAMP before() unbounded rule <=1000 occurrences returns correct result',
    assert_equals(
        'before() unbounded <=1000',
        '2024-12-25 00:00:00',
        (SELECT rrule."before"(
            'FREQ=WEEKLY',
            '2020-01-01 00:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP
        ))::TEXT
    );

-- Fail if any tests failed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count FROM coverage_gap_results WHERE status NOT LIKE 'PASS%';
    IF failed_count > 0 THEN
        RAISE EXCEPTION 'COVERAGE GAP TESTS FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'COVERAGE GAP TESTS PASSED: All tests passed!';
    END IF;
END $$;


-- ============================================================================
-- SECTION: Issue 14 — TIMESTAMP after() with sparse rules
-- after() previously used max_count=2, causing insufficient period_limit
-- for sparse rules where the target date is far from dtstart.
-- ============================================================================
\echo ''
\echo '--- Issue 14: TIMESTAMP after() sparse rule coverage ---'

-- Test: after() with FREQ=DAILY;COUNT=365 and after_date 100 days from dtstart.
-- With the old max_count=2, period_limit=80 daily periods, the generator couldn't
-- reach day 100. With max_count=1000, period_limit=40000, this works.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 14: after() sparse rules',
    'after() finds daily occurrence >80 periods from dtstart',
    assert_equals(
        'after() daily far from dtstart',
        '2020-04-11 00:00:00',
        (SELECT rrule."after"(
            'FREQ=DAILY;COUNT=365',
            '2020-01-01 00:00:00'::TIMESTAMP,
            '2020-04-10 00:00:00'::TIMESTAMP,
            FALSE
        )::TEXT)
    );

-- Test: after() far from dtstart with FREQ=WEEKLY
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 14: after() sparse rules',
    'after() finds weekly occurrence 2 years from dtstart',
    assert_equals(
        'after() weekly 2yr',
        '2022-01-05 00:00:00',
        (SELECT rrule."after"(
            'FREQ=WEEKLY;BYDAY=WE',
            '2020-01-01 00:00:00'::TIMESTAMP,
            '2022-01-01 00:00:00'::TIMESTAMP,
            FALSE
        )::TEXT)
    );


-- ============================================================================
-- SECTION: Issue 19 — overlaps() false-positive with duration-expanded
-- adjusted_mindate for single events (NULL rrule)
-- ============================================================================
\echo ''
\echo '--- Issue 19: overlaps() false-positive for single events ---'

-- Test: Single event [Jan 1, Jan 10] should NOT overlap query range [Jan 11, Jan 20].
-- The event ends on Jan 10 and the query starts on Jan 11 — no overlap.
-- Previously, duration expansion shifted adjusted_mindate to Jan 2, causing a false positive.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 19: overlaps() single event',
    'TIMESTAMP: single event ending before query window returns FALSE',
    assert_equals(
        'overlaps() no false positive',
        'false',
        (SELECT rrule."overlaps"(
            '2020-01-01 00:00:00'::TIMESTAMPTZ,   -- dtstart
            '2020-01-10 00:00:00'::TIMESTAMPTZ,   -- dtend (9-day event)
            NULL::TEXT,                              -- no rrule (single event)
            '2020-01-11 00:00:00'::TIMESTAMPTZ,   -- mindate (query start)
            '2020-01-20 00:00:00'::TIMESTAMPTZ,   -- maxdate (query end)
            'UTC'
        )::TEXT)
    );

-- Test: Single event [Jan 1, Jan 10] SHOULD overlap query range [Jan 5, Jan 15].
-- The event ends on Jan 10 which is >= Jan 5 (mindate), and starts on Jan 1 which is < Jan 15 (maxdate).
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 19: overlaps() single event',
    'TIMESTAMP: single event overlapping query window returns TRUE',
    assert_equals(
        'overlaps() true positive',
        'true',
        (SELECT rrule."overlaps"(
            '2020-01-01 00:00:00'::TIMESTAMPTZ,
            '2020-01-10 00:00:00'::TIMESTAMPTZ,
            NULL::TEXT,
            '2020-01-05 00:00:00'::TIMESTAMPTZ,
            '2020-01-15 00:00:00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test: Single event [Jan 1, Jan 10] should NOT overlap [Jan 10 00:00:01, Jan 20].
-- Event ends exactly at Jan 10 00:00:00, query starts at Jan 10 00:00:01 — no overlap.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 19: overlaps() single event',
    'TIMESTAMP: single event boundary — ends just before query start returns FALSE',
    assert_equals(
        'overlaps() boundary false',
        'false',
        (SELECT rrule."overlaps"(
            '2020-01-01 00:00:00'::TIMESTAMPTZ,
            '2020-01-10 00:00:00'::TIMESTAMPTZ,
            NULL::TEXT,
            '2020-01-10 00:00:01'::TIMESTAMPTZ,
            '2020-01-20 00:00:00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test: Single event [Jan 1, Jan 10] SHOULD overlap [Jan 10, Jan 20] (dtend == mindate).
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 19: overlaps() single event',
    'TIMESTAMP: single event boundary — dtend equals mindate returns TRUE',
    assert_equals(
        'overlaps() boundary true',
        'true',
        (SELECT rrule."overlaps"(
            '2020-01-01 00:00:00'::TIMESTAMPTZ,
            '2020-01-10 00:00:00'::TIMESTAMPTZ,
            NULL::TEXT,
            '2020-01-10 00:00:00'::TIMESTAMPTZ,
            '2020-01-20 00:00:00'::TIMESTAMPTZ,
            'UTC'
        )::TEXT)
    );

-- Test: TIMESTAMPTZ overlaps() — same false-positive scenario with timezone
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 19: overlaps() single event',
    'TIMESTAMPTZ: single event ending before query window returns FALSE',
    assert_equals(
        'overlaps() TZ no false positive',
        'false',
        (SELECT rrule."overlaps"(
            '2020-01-01 00:00:00'::TIMESTAMPTZ,
            '2020-01-10 00:00:00'::TIMESTAMPTZ,
            NULL::TEXT,
            '2020-01-11 00:00:00'::TIMESTAMPTZ,
            '2020-01-20 00:00:00'::TIMESTAMPTZ,
            'America/New_York'
        )::TEXT)
    );


-- ============================================================================
-- SECTION: Issue 25 — after() maxdate anchored to dtstart+10y instead of
-- GREATEST(dtstart, after_date)+10y
-- ============================================================================
\echo ''
\echo '--- Issue 25: after() maxdate anchoring ---'

-- Test: TIMESTAMP after() with after_date more than 10 years from dtstart.
-- FREQ=YEARLY;COUNT=20 produces 20 yearly occurrences starting from 2000.
-- The 15th occurrence is 2014, the 20th is 2019. after_date=2013-06-01 is >10y from dtstart.
-- Previously returned NULL because maxdate was 2010 (2000+10y), missing occurrences after 2010.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 25: after() maxdate anchoring',
    'TIMESTAMP: after() finds occurrence >10 years from dtstart',
    assert_equals(
        'after() beyond 10y from dtstart',
        '2014-01-01 00:00:00',
        (SELECT rrule."after"(
            'FREQ=YEARLY;COUNT=20',
            '2000-01-01 00:00:00'::TIMESTAMP,
            '2013-06-01 00:00:00'::TIMESTAMP,
            FALSE
        )::TEXT)
    );

-- Test: TIMESTAMP after() — last occurrence of a 20-year rule
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 25: after() maxdate anchoring',
    'TIMESTAMP: after() finds last occurrence of 20-year yearly rule',
    assert_equals(
        'after() 20th year',
        '2019-01-01 00:00:00',
        (SELECT rrule."after"(
            'FREQ=YEARLY;COUNT=20',
            '2000-01-01 00:00:00'::TIMESTAMP,
            '2018-06-01 00:00:00'::TIMESTAMP,
            FALSE
        )::TEXT)
    );

-- Test: TIMESTAMPTZ after() with after_date more than 10 years from dtstart.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 25: after() maxdate anchoring',
    'TIMESTAMPTZ: after() finds occurrence >10 years from dtstart',
    assert_equals(
        'after() TZ beyond 10y',
        '2014-01-01 05:00:00+00',
        (SELECT (x.*)::TEXT FROM rrule."after"(
            'FREQ=YEARLY;COUNT=20',
            '2000-01-01 00:00:00-05'::TIMESTAMPTZ,
            '2013-06-01 00:00:00-05'::TIMESTAMPTZ,
            1,
            'America/New_York',
            FALSE
        ) x LIMIT 1)
    );

-- Test: TIMESTAMP after() — after_date within 10y of dtstart still works (regression check)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 25: after() maxdate anchoring',
    'TIMESTAMP: after() within 10y still works (regression)',
    assert_equals(
        'after() within 10y regression',
        '2006-01-01 00:00:00',
        (SELECT rrule."after"(
            'FREQ=YEARLY;COUNT=20',
            '2000-01-01 00:00:00'::TIMESTAMP,
            '2005-06-01 00:00:00'::TIMESTAMP,
            FALSE
        )::TEXT)
    );

-- Test Issue 31: before() iteration budget is reasonable
-- Verify before() still works correctly with reduced max_count (1M instead of 50M)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 31: before() iteration budget',
    'TIMESTAMP: before() finds last occurrence with reduced budget',
    assert_equals(
        'before() with reduced budget',
        '2025-12-01 00:00:00',
        (SELECT rrule."before"(
            'FREQ=MONTHLY;COUNT=24',
            '2024-01-01 00:00:00'::TIMESTAMP,
            '2026-01-01 00:00:00'::TIMESTAMP,
            FALSE
        )::TEXT)
    );

-- Test Issue 31: TIMESTAMPTZ before() with reduced budget
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 31: before() iteration budget',
    'TIMESTAMPTZ: before() finds last occurrence with reduced budget',
    assert_equals(
        'TZ before() with reduced budget',
        '2025-12-01 15:00:00+00',
        (SELECT (rrule."before"(
            'FREQ=MONTHLY;COUNT=24',
            '2024-01-01 10:00:00-05'::TIMESTAMPTZ,
            '2026-01-01 10:00:00-05'::TIMESTAMPTZ,
            1,
            'America/New_York',
            FALSE
        ))::TEXT)
    );

-- Test Issue 31: before() with DAILY rule over long range still works
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 31: before() iteration budget',
    'DAILY before() over multi-year range finds correct last occurrence',
    assert_equals(
        'DAILY before() multi-year',
        '2024-12-31 00:00:00',
        (SELECT rrule."before"(
            'FREQ=DAILY;COUNT=1000',
            '2022-04-07 00:00:00'::TIMESTAMP,
            '2025-06-01 00:00:00'::TIMESTAMP,
            FALSE
        )::TEXT)
    );

-- =====================================================================
-- Issue 1: between() 10-year window clamp
-- =====================================================================

-- Test: TIMESTAMP between() clamps end_date to dtstart + 10 years
-- A 50-year range should be clamped, returning only occurrences within 10 years of dtstart
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 1: between() 10yr clamp',
    'TIMESTAMP between() clamps 50yr range to 10yr',
    assert_equals(
        'between() 10yr clamp',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=YEARLY;BYMONTH=6;BYMONTHDAY=15',
            '2020-01-01 00:00:00'::TIMESTAMP,
            '2020-01-01 00:00:00'::TIMESTAMP,
            '2070-01-01 00:00:00'::TIMESTAMP,
            TRUE
        )),
        '10'
    );

-- Test: TIMESTAMPTZ between() clamps end_date to dtstart + 10 years
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 1: between() 10yr clamp',
    'TIMESTAMPTZ between() clamps 50yr range to 10yr',
    assert_equals(
        'between() TZ 10yr clamp',
        (SELECT COUNT(*)::TEXT FROM rrule."between"(
            'FREQ=YEARLY;BYMONTH=6;BYMONTHDAY=15',
            '2020-01-01 00:00:00+00'::TIMESTAMPTZ,
            '2020-01-01 00:00:00+00'::TIMESTAMPTZ,
            '2070-01-01 00:00:00+00'::TIMESTAMPTZ,
            'UTC',
            TRUE
        )),
        '10'
    );



-- =====================================================================
-- Issue 61: WEEKLY + BYMONTH sparsity requires increased iteration limit
-- =====================================================================

-- Test: FREQ=WEEKLY;BYMONTH=12 with COUNT=5 starting in January
-- With BYMONTH=12, only ~4-5 weeks per year match (December weeks).
-- Starting in January, this is extremely sparse (~4/52 = 8% match rate).
-- The 15x WEEKLY multiplier (up from 10x) ensures sufficient iterations.
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 61: WEEKLY+BYMONTH sparsity',
    'FREQ=WEEKLY;BYMONTH=12;COUNT=5 returns 5 results from January start',
    assert_equals(
        'WEEKLY+BYMONTH count',
        '5',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=WEEKLY;BYMONTH=12;COUNT=5',
            '2025-01-01 00:00:00'::TIMESTAMP
        ))
    );

-- Test: Verify the exact dates for WEEKLY+BYMONTH=12
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 61: WEEKLY+BYMONTH sparsity',
    'FREQ=WEEKLY;BYMONTH=12;COUNT=5 returns correct December dates',
    assert_occurrences_equal(
        'WEEKLY+BYMONTH dates',
        ARRAY[
            '2025-12-03 00:00:00'::TIMESTAMP,
            '2025-12-10 00:00:00'::TIMESTAMP,
            '2025-12-17 00:00:00'::TIMESTAMP,
            '2025-12-24 00:00:00'::TIMESTAMP,
            '2025-12-31 00:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=WEEKLY;BYMONTH=12;COUNT=5',
            '2025-01-01 00:00:00'::TIMESTAMP
         ) AS occurrence)
    );

-- Test: WEEKLY+BYMONTH with INTERVAL > 1 (Rule #10: always test INTERVAL > 1)
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 61: WEEKLY+BYMONTH sparsity',
    'FREQ=WEEKLY;INTERVAL=2;BYMONTH=12;COUNT=3 works correctly',
    assert_equals(
        'WEEKLY+BYMONTH+INTERVAL count',
        '3',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYMONTH=12;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ))
    );

-- Test: TIMESTAMPTZ variant of WEEKLY+BYMONTH
INSERT INTO coverage_gap_results (test_category, test_name, status)
SELECT
    'Issue 61: WEEKLY+BYMONTH sparsity',
    'TIMESTAMPTZ: FREQ=WEEKLY;BYMONTH=12;COUNT=5 returns 5 results',
    assert_equals(
        'TZ WEEKLY+BYMONTH count',
        '5',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=WEEKLY;BYMONTH=12;COUNT=5',
            '2025-01-01 00:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ))
    );


ROLLBACK;
