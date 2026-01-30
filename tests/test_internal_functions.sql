/**
 * Internal Helper Functions Tests
 *
 * This file tests the internal/helper functions that support the public API.
 * These functions are not part of the public API but are critical for correctness.
 *
 * Internal functions tested:
 * - parse_rrule_parts() - RRULE string parsing
 * - weekday_to_number() - Day name to number conversion
 * - get_week_start() - Week boundary calculation
 * - get_week_number() - ISO week number calculation
 * - validate_timezone() - Timezone validation
 * - test_byday_rule() - BYDAY rule testing
 * - test_bymonth_rule() - BYMONTH rule testing
 * - test_bymonthday_rule() - BYMONTHDAY rule testing
 * - test_byyearday_rule() - BYYEARDAY rule testing
 * - rrule_month_byday_set() - Monthly BYDAY generation
 * - rrule_month_bymonthday_set() - Monthly BYMONTHDAY generation
 * - rrule_week_byday_set() - Weekly BYDAY generation
 * - daily_set() - Daily occurrence generation
 * - weekly_set() - Weekly occurrence generation
 * - monthly_set() - Monthly occurrence generation
 * - yearly_set() - Yearly occurrence generation
 * - calculate_safe_iteration_limit() - DoS protection
 *
 * Usage:
 *   psql -d your_database -f tests/test_internal_functions.sql
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
CREATE TEMP TABLE internal_test_results (
    test_id SERIAL PRIMARY KEY,
    test_category TEXT,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '==================================================================='
\echo 'INTERNAL HELPER FUNCTIONS TESTS'
\echo '==================================================================='
\echo ''

-- ============================================================================
-- SECTION 1: weekday_to_number() Tests
-- ============================================================================
\echo '--- Section 1: weekday_to_number() ---'

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weekday_to_number()', 'MO = 1', assert_equals('MO', '1', rrule.weekday_to_number('MO')::TEXT);

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weekday_to_number()', 'TU = 2', assert_equals('TU', '2', rrule.weekday_to_number('TU')::TEXT);

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weekday_to_number()', 'WE = 3', assert_equals('WE', '3', rrule.weekday_to_number('WE')::TEXT);

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weekday_to_number()', 'TH = 4', assert_equals('TH', '4', rrule.weekday_to_number('TH')::TEXT);

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weekday_to_number()', 'FR = 5', assert_equals('FR', '5', rrule.weekday_to_number('FR')::TEXT);

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weekday_to_number()', 'SA = 6', assert_equals('SA', '6', rrule.weekday_to_number('SA')::TEXT);

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weekday_to_number()', 'SU = 0', assert_equals('SU', '0', rrule.weekday_to_number('SU')::TEXT);

-- ============================================================================
-- SECTION 2: get_week_start() Tests
-- ============================================================================
\echo ''
\echo '--- Section 2: get_week_start() ---'

-- Test with different WKST values
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'get_week_start()', 'Monday start (MO)',
    assert_equals('WKST=MO', '2025-01-06 00:00:00+00',
        rrule.get_week_start('2025-01-08 10:00:00+00'::TIMESTAMPTZ, 'MO')::TEXT);

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'get_week_start()', 'Sunday start (SU)',
    assert_equals('WKST=SU', '2025-01-05 00:00:00+00',
        rrule.get_week_start('2025-01-08 10:00:00+00'::TIMESTAMPTZ, 'SU')::TEXT);

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'get_week_start()', 'Saturday start (SA)',
    assert_equals('WKST=SA', '2025-01-04 00:00:00+00',
        rrule.get_week_start('2025-01-08 10:00:00+00'::TIMESTAMPTZ, 'SA')::TEXT);

-- ============================================================================
-- SECTION 3: get_week_number() Tests
-- ============================================================================
\echo ''
\echo '--- Section 3: get_week_number() ---'

-- ISO 8601 week numbers with WKST=MO:
-- Jan 15 2025 (Wednesday) → ISO week 3
-- Jan 1 2025 (Wednesday) → ISO week 1 (Jan 1 is in week containing Jan 4)
-- Dec 30 2024 (Monday) → ISO week 1 of 2025 (belongs to next year's week 1)
-- Dec 29 2014 (Monday) → ISO week 1 of 2015 (2015 starts on Thursday)
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'get_week_number()', 'Jan 15 2025 = ISO week 3',
    assert_equals('Week 3', '3', rrule.get_week_number('2025-01-15 10:00:00+00'::TIMESTAMPTZ, 'MO')::TEXT);

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'get_week_number()', 'Jan 1 2025 = ISO week 1',
    assert_equals('Week 1', '1', rrule.get_week_number('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'MO')::TEXT);

-- Cross-year boundary: Dec 30 2024 is Monday, belongs to ISO week 1 of 2025
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'get_week_number()', 'Dec 30 2024 = week 1 (cross-year)',
    assert_equals('Cross-year week 1', '1', rrule.get_week_number('2024-12-30 10:00:00+00'::TIMESTAMPTZ, 'MO')::TEXT);

-- Mid-year check: July 1 2025 (Tuesday) = ISO week 27
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'get_week_number()', 'Jul 1 2025 = ISO week 27',
    assert_equals('Week 27', '27', rrule.get_week_number('2025-07-01 10:00:00+00'::TIMESTAMPTZ, 'MO')::TEXT);

-- ============================================================================
-- SECTION 4: validate_timezone() Tests
-- ============================================================================
\echo ''
\echo '--- Section 4: validate_timezone() ---'

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'validate_timezone()', 'Valid timezone America/New_York',
    assert_true('Valid TZ', (SELECT rrule.validate_timezone('America/New_York') IS NOT NULL));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'validate_timezone()', 'Valid timezone UTC',
    assert_true('UTC', (SELECT rrule.validate_timezone('UTC') IS NOT NULL));

-- NULL timezone - function returns VOID without error (NULL is allowed)
DO $$
BEGIN
    PERFORM rrule.validate_timezone(NULL);
    INSERT INTO internal_test_results (test_category, test_name, status)
    VALUES ('validate_timezone()', 'NULL timezone allowed', 'PASS');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO internal_test_results (test_category, test_name, status)
    VALUES ('validate_timezone()', 'NULL timezone allowed', 'FAIL - Exception: ' || SQLERRM);
END;
$$;

-- ============================================================================
-- SECTION 5: test_byday_rule() Tests
-- ============================================================================
\echo ''
\echo '--- Section 5: test_byday_rule() ---'

-- Test BYDAY matching
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'test_byday_rule()', 'Wednesday matches WE',
    assert_true('WE match', rrule.test_byday_rule('2025-01-08 10:00:00+00'::TIMESTAMPTZ, ARRAY['WE']));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'test_byday_rule()', 'Wednesday does not match MO',
    assert_true('MO no match', NOT rrule.test_byday_rule('2025-01-08 10:00:00+00'::TIMESTAMPTZ, ARRAY['MO']));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'test_byday_rule()', 'Wednesday matches MO,WE,FR',
    assert_true('Multi match', rrule.test_byday_rule('2025-01-08 10:00:00+00'::TIMESTAMPTZ, ARRAY['MO','WE','FR']));

-- ============================================================================
-- SECTION 6: test_bymonth_rule() Tests
-- ============================================================================
\echo ''
\echo '--- Section 6: test_bymonth_rule() ---'

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'test_bymonth_rule()', 'January matches BYMONTH=1',
    assert_true('Jan match', rrule.test_bymonth_rule('2025-01-08 10:00:00+00'::TIMESTAMPTZ, ARRAY[1]));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'test_bymonth_rule()', 'January does not match BYMONTH=6',
    assert_true('Jun no match', NOT rrule.test_bymonth_rule('2025-01-08 10:00:00+00'::TIMESTAMPTZ, ARRAY[6]));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'test_bymonth_rule()', 'January matches BYMONTH=1,4,7,10',
    assert_true('Multi match', rrule.test_bymonth_rule('2025-01-08 10:00:00+00'::TIMESTAMPTZ, ARRAY[1,4,7,10]));

-- ============================================================================
-- SECTION 7: test_bymonthday_rule() Tests
-- ============================================================================
\echo ''
\echo '--- Section 7: test_bymonthday_rule() ---'

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'test_bymonthday_rule()', 'Day 8 matches BYMONTHDAY=8',
    assert_true('Day 8 match', rrule.test_bymonthday_rule('2025-01-08 10:00:00+00'::TIMESTAMPTZ, ARRAY[8]));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'test_bymonthday_rule()', 'Day 8 does not match BYMONTHDAY=15',
    assert_true('Day 15 no match', NOT rrule.test_bymonthday_rule('2025-01-08 10:00:00+00'::TIMESTAMPTZ, ARRAY[15]));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'test_bymonthday_rule()', 'Day 8 matches BYMONTHDAY=1,8,15',
    assert_true('Multi match', rrule.test_bymonthday_rule('2025-01-08 10:00:00+00'::TIMESTAMPTZ, ARRAY[1,8,15]));

-- Negative BYMONTHDAY - the test_ functions check positive day numbers
-- Negative indices are handled at a higher level (in monthly_set)
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'test_bymonthday_rule()', 'Day 31 matches BYMONTHDAY=31',
    assert_true('Day 31 match', rrule.test_bymonthday_rule('2025-01-31 10:00:00+00'::TIMESTAMPTZ, ARRAY[31]));

-- ============================================================================
-- SECTION 8: test_byyearday_rule() Tests
-- ============================================================================
\echo ''
\echo '--- Section 8: test_byyearday_rule() ---'

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'test_byyearday_rule()', 'Jan 8 = day 8 of year',
    assert_true('Day 8 match', rrule.test_byyearday_rule('2025-01-08 10:00:00+00'::TIMESTAMPTZ, ARRAY[8]));

-- Negative indices handled at higher level - test with positive day number
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'test_byyearday_rule()', 'Dec 31 = day 365 of 2025',
    assert_true('Day 365 match', rrule.test_byyearday_rule('2025-12-31 10:00:00+00'::TIMESTAMPTZ, ARRAY[365]));

-- ============================================================================
-- SECTION 9: parse_rrule_parts() Tests
-- ============================================================================
\echo ''
\echo '--- Section 9: parse_rrule_parts() ---'

-- Test basic parsing
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'parse_rrule_parts()', 'Parse FREQ=DAILY',
    assert_equals('DAILY', 'DAILY',
        (SELECT (rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=DAILY;COUNT=5')).freq));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'parse_rrule_parts()', 'Parse COUNT=5',
    assert_equals('5', '5',
        (SELECT (rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=DAILY;COUNT=5')).count::TEXT));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'parse_rrule_parts()', 'Parse INTERVAL=2',
    assert_equals('2', '2',
        (SELECT (rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=DAILY;INTERVAL=2;COUNT=5')).interval::TEXT));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'parse_rrule_parts()', 'Parse BYDAY=MO,WE,FR',
    assert_equals('MO,WE,FR', 'MO,WE,FR',
        (SELECT array_to_string((rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=5')).byday, ',')));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'parse_rrule_parts()', 'Parse BYMONTH=1,6,12',
    assert_equals('1,6,12', '1,6,12',
        (SELECT array_to_string((rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=YEARLY;BYMONTH=1,6,12;COUNT=5')).bymonth::TEXT[], ',')));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'parse_rrule_parts()', 'Parse WKST=SU',
    assert_equals('SU', 'SU',
        (SELECT (rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=WEEKLY;WKST=SU;COUNT=5')).wkst));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'parse_rrule_parts()', 'WKST defaults to MO or NULL',
    assert_true('Default WKST',
        (SELECT (rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=WEEKLY;COUNT=5')).wkst IS NULL
         OR (rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=WEEKLY;COUNT=5')).wkst = 'MO'));

-- ============================================================================
-- SECTION 10: calculate_safe_iteration_limit() Tests
-- ============================================================================
\echo ''
\echo '--- Section 10: calculate_safe_iteration_limit() ---'

-- Exact expected values based on function implementation:
-- DAILY: effective_max * 40 → 1000 * 40 = 40000
-- WEEKLY: effective_max * 10 → 1000 * 10 = 10000
-- MONTHLY: GREATEST(effective_max * 20, 1200) → GREATEST(20000, 1200) = 20000
-- YEARLY: effective_max * 10 → 1000 * 10 = 10000
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'calculate_safe_iteration_limit()', 'DAILY(10, 1000) = 40000',
    assert_equals('Daily exact', '40000', rrule.calculate_safe_iteration_limit('DAILY', 10, 1000)::TEXT);

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'calculate_safe_iteration_limit()', 'WEEKLY(10, 1000) = 10000',
    assert_equals('Weekly exact', '10000', rrule.calculate_safe_iteration_limit('WEEKLY', 10, 1000)::TEXT);

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'calculate_safe_iteration_limit()', 'MONTHLY(10, 1000) = 20000',
    assert_equals('Monthly exact', '20000', rrule.calculate_safe_iteration_limit('MONTHLY', 10, 1000)::TEXT);

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'calculate_safe_iteration_limit()', 'YEARLY(10, 1000) = 10000',
    assert_equals('Yearly exact', '10000', rrule.calculate_safe_iteration_limit('YEARLY', 10, 1000)::TEXT);

-- MONTHLY minimum floor: GREATEST(effective_max * 20, 1200) with small effective_max
-- effective_max=5 → GREATEST(100, 1200) = 1200
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'calculate_safe_iteration_limit()', 'MONTHLY min floor(NULL, 5) = 1200',
    assert_equals('Monthly floor', '1200', rrule.calculate_safe_iteration_limit('MONTHLY', NULL, 5)::TEXT);

-- DoS protection: MINUTELY caps at 1440 regardless of input
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'calculate_safe_iteration_limit()', 'MINUTELY DoS cap(NULL, 5000) = 1440',
    assert_equals('Minutely DoS cap', '1440', rrule.calculate_safe_iteration_limit('MINUTELY', NULL, 5000)::TEXT);

-- DoS protection: SECONDLY caps at 3600
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'calculate_safe_iteration_limit()', 'SECONDLY DoS cap(NULL, 10000) = 3600',
    assert_equals('Secondly DoS cap', '3600', rrule.calculate_safe_iteration_limit('SECONDLY', NULL, 10000)::TEXT);

-- NULL handling: both NULL → returns NULL
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'calculate_safe_iteration_limit()', 'NULL count + NULL max = NULL',
    assert_true('Both NULL', rrule.calculate_safe_iteration_limit('DAILY', NULL, NULL) IS NULL);

-- ============================================================================
-- SECTION 11: rrule_month_byday_set() Tests
-- ============================================================================
\echo ''
\echo '--- Section 11: rrule_month_byday_set() ---'

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'rrule_month_byday_set()', 'Generate Mondays in January 2025',
    assert_equals('4 Mondays',
        '{"2025-01-06 10:00:00+00","2025-01-13 10:00:00+00","2025-01-20 10:00:00+00","2025-01-27 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule.rrule_month_byday_set('2025-01-15 10:00:00+00'::TIMESTAMPTZ, ARRAY['MO'], NULL) d));

-- January 2025: 4 Mondays (6,13,20,27) + 5 Wednesdays (1,8,15,22,29) + 5 Fridays (3,10,17,24,31) = 14
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'rrule_month_byday_set()', 'Generate MO,WE,FR in January 2025',
    assert_equals('14 days', '14',
        (SELECT COUNT(*)::TEXT FROM rrule.rrule_month_byday_set('2025-01-15 10:00:00+00'::TIMESTAMPTZ, ARRAY['MO','WE','FR'], NULL)));

-- ============================================================================
-- SECTION 12: rrule_month_bymonthday_set() Tests
-- ============================================================================
\echo ''
\echo '--- Section 12: rrule_month_bymonthday_set() ---'

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'rrule_month_bymonthday_set()', 'Generate day 15 in January',
    assert_equals('Day 15',
        '{"2025-01-15 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule.rrule_month_bymonthday_set('2025-01-15 10:00:00+00'::TIMESTAMPTZ, ARRAY[15], 'OMIT', NULL) d));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'rrule_month_bymonthday_set()', 'Generate days 1,15 in January',
    assert_equals('Days 1 and 15',
        '{"2025-01-01 10:00:00+00","2025-01-15 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule.rrule_month_bymonthday_set('2025-01-15 10:00:00+00'::TIMESTAMPTZ, ARRAY[1,15], 'OMIT', NULL) d));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'rrule_month_bymonthday_set()', 'SKIP=OMIT for Feb 30',
    assert_equals('0 days', '0',
        (SELECT COUNT(*)::TEXT FROM rrule.rrule_month_bymonthday_set('2025-02-15 10:00:00+00'::TIMESTAMPTZ, ARRAY[30], 'OMIT', NULL)));

-- ============================================================================
-- SECTION 13: rrule_week_byday_set() Tests
-- ============================================================================
\echo ''
\echo '--- Section 13: rrule_week_byday_set() ---'

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'rrule_week_byday_set()', 'Generate MO in week (WKST=MO)',
    assert_equals('MO in week',
        '{"2025-01-06 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule.rrule_week_byday_set('2025-01-08 10:00:00+00'::TIMESTAMPTZ, ARRAY['MO'], 'MO', NULL) d));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'rrule_week_byday_set()', 'Generate MO,WE,FR in week',
    assert_equals('MO,WE,FR in week',
        '{"2025-01-06 10:00:00+00","2025-01-08 10:00:00+00","2025-01-10 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule.rrule_week_byday_set('2025-01-08 10:00:00+00'::TIMESTAMPTZ, ARRAY['MO','WE','FR'], 'MO', NULL) d));

-- ============================================================================
-- SECTION 14: daily_set() Tests
-- ============================================================================
\echo ''
\echo '--- Section 14: daily_set() ---'

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'daily_set()', 'Generate 1 day with BYDAY filter',
    assert_equals('WE filter on Wed Jan 8',
        '{"2025-01-08 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule.daily_set(
            '2025-01-08 10:00:00+00'::TIMESTAMPTZ,
            rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=DAILY;BYDAY=WE;COUNT=5'),
            NULL
        ) d));

-- ============================================================================
-- SECTION 15: weekly_set() Tests
-- ============================================================================
\echo ''
\echo '--- Section 15: weekly_set() ---'

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weekly_set()', 'Generate days in a week',
    assert_equals('MO,WE,FR in week of Jan 6',
        '{"2025-01-06 10:00:00+00","2025-01-08 10:00:00+00","2025-01-10 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule.weekly_set(
            '2025-01-08 10:00:00+00'::TIMESTAMPTZ,
            rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=10'),
            NULL
        ) d));

-- ============================================================================
-- SECTION 16: monthly_set() Tests
-- ============================================================================
\echo ''
\echo '--- Section 16: monthly_set() ---'

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'monthly_set()', 'Generate days in a month with BYDAY',
    assert_equals('Mondays in Jan 2025',
        '{"2025-01-06 10:00:00+00","2025-01-13 10:00:00+00","2025-01-20 10:00:00+00","2025-01-27 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule.monthly_set(
            '2025-01-08 10:00:00+00'::TIMESTAMPTZ,
            rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=MONTHLY;BYDAY=MO;COUNT=10'),
            NULL
        ) d));

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'monthly_set()', 'Generate days in a month with BYMONTHDAY',
    assert_equals('Day 15 in Jan',
        '{"2025-01-15 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule.monthly_set(
            '2025-01-08 10:00:00+00'::TIMESTAMPTZ,
            rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=10'),
            NULL
        ) d));

-- ============================================================================
-- SECTION 17: yearly_set() Tests
-- ============================================================================
\echo ''
\echo '--- Section 17: yearly_set() ---'

INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'yearly_set()', 'Generate days in a year with BYMONTH',
    assert_equals('BYMONTH=1,6 in 2025',
        '{"2025-01-08 10:00:00+00","2025-06-08 10:00:00+00"}',
        (SELECT array_agg(d ORDER BY d)::TEXT FROM rrule.yearly_set(
            '2025-01-08 10:00:00+00'::TIMESTAMPTZ,
            rrule.parse_rrule_parts('2025-01-01 10:00:00+00'::TIMESTAMPTZ, 'FREQ=YEARLY;BYMONTH=1,6;COUNT=10'),
            NULL
        ) d));

-- ============================================================================
-- SECTION 18: rrule_year_byday_set() Tests
-- ============================================================================
\echo ''
\echo '--- Section 18: rrule_year_byday_set() ---'

-- Test 18.1: First Monday of year (ordinal BYDAY)
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'rrule_year_byday_set()', 'First Monday of year via YEARLY;BYDAY=1MO',
    assert_true(
        'First Monday of year',
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=1MO;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) d) = ARRAY['2025-01-06 00:00:00', '2026-01-05 00:00:00', '2027-01-04 00:00:00']::TIMESTAMP[]
    );

-- Test 18.2: Last Friday of year (negative ordinal)
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'rrule_year_byday_set()', 'Last Friday of year via YEARLY;BYDAY=-1FR',
    assert_true(
        'Last Friday of year',
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-1FR;COUNT=3',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) d) = ARRAY['2025-12-26 00:00:00', '2026-12-25 00:00:00', '2027-12-31 00:00:00']::TIMESTAMP[]
    );

-- Test 18.3: All Mondays of year (unqualified BYDAY, first 5)
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'rrule_year_byday_set()', 'All Mondays of year (first 5)',
    assert_true(
        'First 5 Mondays of 2025',
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=MO;COUNT=5',
            '2025-01-01 00:00:00'::TIMESTAMP
        ) d) = ARRAY['2025-01-06 00:00:00', '2025-01-13 00:00:00', '2025-01-20 00:00:00',
              '2025-01-27 00:00:00', '2025-02-03 00:00:00']::TIMESTAMP[]
    );

-- ============================================================================
-- SECTION 19: byweekno_matches() Tests
-- ============================================================================
\echo ''
\echo '--- Section 19: byweekno_matches() ---'

-- byweekno_matches(week_num INT, weeks_in_year INT, byweekno INT[]) returns BOOLEAN
-- Takes computed week number and total weeks in year (not raw timestamps).

-- Test 19.1: Positive BYWEEKNO match (week 3 matches BYWEEKNO=3)
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'byweekno_matches()', 'Week 3 matches BYWEEKNO=3',
    assert_true('Week 3 match',
        rrule.byweekno_matches(3, 52, ARRAY[3]));

-- Test 19.2: Negative BYWEEKNO match (week -1 = last week of year)
-- 52-week year: week -1 = week 52
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'byweekno_matches()', 'Week 52 matches BYWEEKNO=-1 (52-week year)',
    assert_true('Week -1 match',
        rrule.byweekno_matches(52, 52, ARRAY[-1]));

-- Test 19.3: Non-matching BYWEEKNO
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'byweekno_matches()', 'Week 3 does not match BYWEEKNO=10',
    assert_true('Week 10 no match',
        NOT rrule.byweekno_matches(3, 52, ARRAY[10]));

-- Test 19.4: Multiple BYWEEKNO values
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'byweekno_matches()', 'Week 3 matches BYWEEKNO=1,3,5',
    assert_true('Multi week match',
        rrule.byweekno_matches(3, 52, ARRAY[1,3,5]));

-- Test 19.5: NULL BYWEEKNO always matches (no filter)
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'byweekno_matches()', 'NULL BYWEEKNO always matches',
    assert_true('NULL match',
        rrule.byweekno_matches(3, 52, NULL));

-- ============================================================================
-- SECTION 20: weeks_in_year() Tests
-- ============================================================================
\echo ''
\echo '--- Section 20: weeks_in_year() ---'

-- weeks_in_year(year_start TIMESTAMPTZ, wkst TEXT) returns INT
-- Takes a timestamp representing the start of the year and WKST day code.

-- Test 20.1: 2025 has 52 ISO weeks (WKST=MO)
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weeks_in_year()', '2025 has 52 ISO weeks (WKST=MO)',
    assert_equals('2025 weeks', '52', rrule.weeks_in_year('2025-01-01 00:00:00+00'::TIMESTAMPTZ, 'MO')::TEXT);

-- Test 20.2: 2020 has 53 ISO weeks (Jan 1 = Wednesday, Dec 31 = Thursday)
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weeks_in_year()', '2020 has 53 ISO weeks (WKST=MO)',
    assert_equals('2020 weeks', '53', rrule.weeks_in_year('2020-01-01 00:00:00+00'::TIMESTAMPTZ, 'MO')::TEXT);

-- Test 20.3: 2015 has 53 ISO weeks
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weeks_in_year()', '2015 has 53 ISO weeks (WKST=MO)',
    assert_equals('2015 weeks', '53', rrule.weeks_in_year('2015-01-01 00:00:00+00'::TIMESTAMPTZ, 'MO')::TEXT);

-- Test 20.4: 2024 has 52 ISO weeks (leap year)
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weeks_in_year()', '2024 has 52 ISO weeks (WKST=MO)',
    assert_equals('2024 weeks', '52', rrule.weeks_in_year('2024-01-01 00:00:00+00'::TIMESTAMPTZ, 'MO')::TEXT);

-- Test 20.5: 2026 has 53 ISO weeks (Jan 1 = Thursday)
INSERT INTO internal_test_results (test_category, test_name, status)
SELECT 'weeks_in_year()', '2026 has 53 ISO weeks (WKST=MO)',
    assert_equals('2026 weeks', '53', rrule.weeks_in_year('2026-01-01 00:00:00+00'::TIMESTAMPTZ, 'MO')::TEXT);

-- ============================================================================
-- SECTION 21: validate_timezone() Invalid Input Test
-- ============================================================================
\echo ''
\echo '--- Section 21: validate_timezone() Invalid Input ---'

-- Test 21.1: Invalid timezone should raise exception
DO $$
DECLARE
    test_passed BOOLEAN := FALSE;
BEGIN
    BEGIN
        PERFORM rrule.validate_timezone('Invalid/Zone');
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM LIKE '%Invalid timezone%' THEN
                test_passed := TRUE;
            END IF;
    END;

    INSERT INTO internal_test_results (test_category, test_name, status)
    VALUES ('validate_timezone()', 'Invalid/Zone raises exception',
        CASE WHEN test_passed THEN 'PASS' ELSE 'FAIL - No exception for invalid timezone' END);
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
FROM internal_test_results
ORDER BY test_category, test_id;

\echo ''
\echo 'Category Summary:'
SELECT
    test_category,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status = 'PASS') AS passed,
    COUNT(*) FILTER (WHERE status != 'PASS') AS failed
FROM internal_test_results
GROUP BY test_category
ORDER BY test_category;

\echo ''
\echo 'Overall Summary:'
SELECT
    COUNT(*) AS total_tests,
    COUNT(*) FILTER (WHERE status = 'PASS') AS passed,
    COUNT(*) FILTER (WHERE status != 'PASS') AS failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'PASS') / COUNT(*), 1) || '%' AS pass_rate
FROM internal_test_results;

-- Fail if any tests failed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count FROM internal_test_results WHERE status != 'PASS';
    IF failed_count > 0 THEN
        RAISE EXCEPTION 'INTERNAL FUNCTION TESTS FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'INTERNAL FUNCTION TESTS PASSED: All tests passed!';
    END IF;
END $$;

ROLLBACK;
