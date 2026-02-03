/**
 * DoS Protection Budget Enforcement Tests
 *
 * Verifies that all iteration budget limits are properly enforced:
 * - 1000 result cap for unbounded rules
 * - 10-year window from dtstart
 * - calculate_safe_iteration_limit() values
 * - period_count increments in all code paths
 * - Sparse rule completion (high iteration, low yield)
 *
 * These tests ensure the implementation is resilient against
 * denial-of-service attacks through resource exhaustion.
 *
 * Usage:
 *   psql -d your_database -f tests/security/test_budget_enforcement.sql
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
\echo 'DoS PROTECTION BUDGET ENFORCEMENT TESTS'
\echo '====================================================================='
\echo ''

--------------------------------------------------------------------------------
-- SECTION 1: 1000 RESULT CAP VERIFICATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- 1000 RESULT CAP ---'
\echo ''

-- DAILY unbounded should cap at 1000
SELECT assert_equals('cap-DAILY-unbounded', '1000',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY', '2025-01-01 10:00:00'::TIMESTAMP)));

-- WEEKLY unbounded is capped by 10-year window (52 weeks * 10 years = ~521)
SELECT assert_true('cap-WEEKLY-unbounded',
    (SELECT COUNT(*) BETWEEN 500 AND 600 FROM rrule."all"('FREQ=WEEKLY', '2025-01-01 10:00:00'::TIMESTAMP)));

-- MONTHLY unbounded is capped by 10-year window (12 months * 10 years = 120)
SELECT assert_true('cap-MONTHLY-unbounded',
    (SELECT COUNT(*) BETWEEN 100 AND 130 FROM rrule."all"('FREQ=MONTHLY', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY unbounded (10-year window will cap this before 1000)
SELECT assert_true('cap-YEARLY-unbounded',
    (SELECT COUNT(*) <= 1000 FROM rrule."all"('FREQ=YEARLY', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Expanded rules should cap at 1000
-- DAILY with 24 hours/day generates many results quickly
SELECT assert_true('cap-expanded-BYHOUR',
    (SELECT COUNT(*) BETWEEN 900 AND 1000 FROM rrule."all"('FREQ=DAILY;BYHOUR=0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23', '2025-01-01 10:00:00'::TIMESTAMP)));

-- WEEKLY with BYDAY expansion
SELECT assert_equals('cap-WEEKLY-BYDAY', '1000',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 2: 10-YEAR WINDOW VERIFICATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- 10-YEAR WINDOW ---'
\echo ''

-- All results should be within 10 years of dtstart
-- Using 3652 days (10 years ~ 365.2 * 10) for reliable comparison
SELECT assert_true('window-10year-DAILY',
    (SELECT MAX(r) - '2025-01-01 10:00:00'::TIMESTAMP <= INTERVAL '3652 days'
     FROM rrule."all"('FREQ=DAILY', '2025-01-01 10:00:00'::TIMESTAMP) r));

SELECT assert_true('window-10year-WEEKLY',
    (SELECT MAX(r) - '2025-01-01 10:00:00'::TIMESTAMP <= INTERVAL '3652 days'
     FROM rrule."all"('FREQ=WEEKLY', '2025-01-01 10:00:00'::TIMESTAMP) r));

SELECT assert_true('window-10year-MONTHLY',
    (SELECT MAX(r) - '2025-01-01 10:00:00'::TIMESTAMP <= INTERVAL '3652 days'
     FROM rrule."all"('FREQ=MONTHLY', '2025-01-01 10:00:00'::TIMESTAMP) r));

SELECT assert_true('window-10year-YEARLY',
    (SELECT MAX(r) - '2025-01-01 10:00:00'::TIMESTAMP <= INTERVAL '3652 days'
     FROM rrule."all"('FREQ=YEARLY', '2025-01-01 10:00:00'::TIMESTAMP) r));


--------------------------------------------------------------------------------
-- SECTION 3: calculate_safe_iteration_limit() VERIFICATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- calculate_safe_iteration_limit() ---'
\echo ''

-- Verify the function exists and returns expected values
-- These values should be calibrated to prevent DoS while allowing legitimate queries

-- DAILY: 365 days/year * 10 years * 4 buffer = 14600, but capped differently
SELECT assert_true('limit-DAILY-reasonable',
    rrule.calculate_safe_iteration_limit('DAILY', NULL, 1000) >= 1000 AND
    rrule.calculate_safe_iteration_limit('DAILY', NULL, 1000) <= 100000);

-- WEEKLY: 52 weeks/year * 10 years * 4 buffer
SELECT assert_true('limit-WEEKLY-reasonable',
    rrule.calculate_safe_iteration_limit('WEEKLY', NULL, 1000) >= 1000 AND
    rrule.calculate_safe_iteration_limit('WEEKLY', NULL, 1000) <= 50000);

-- MONTHLY: Should be reasonable (implementation dependent)
SELECT assert_true('limit-MONTHLY-reasonable',
    rrule.calculate_safe_iteration_limit('MONTHLY', NULL, 1000) >= 1000 AND
    rrule.calculate_safe_iteration_limit('MONTHLY', NULL, 1000) <= 50000);

-- YEARLY: Should be reasonable (implementation dependent)
SELECT assert_true('limit-YEARLY-reasonable',
    rrule.calculate_safe_iteration_limit('YEARLY', NULL, 1000) >= 40 AND
    rrule.calculate_safe_iteration_limit('YEARLY', NULL, 1000) <= 50000);

-- With UNTIL constraint (function may have different signature)
-- Just verify the function returns reasonable values for all frequencies
SELECT assert_true('limit-with-various-max',
    rrule.calculate_safe_iteration_limit('DAILY', NULL, 500) IS NOT NULL);


--------------------------------------------------------------------------------
-- SECTION 4: SPARSE RULE COMPLETION
--------------------------------------------------------------------------------
\echo ''
\echo '--- SPARSE RULE COMPLETION ---'
\echo ''

-- Rules that iterate many periods but yield few results should complete

-- BYWEEKNO=53 only exists in some years
SELECT assert_true('sparse-BYWEEKNO-53',
    (SELECT COUNT(*) > 0 FROM rrule."all"(
        'FREQ=YEARLY;BYWEEKNO=53;COUNT=5', '2020-01-01 10:00:00'::TIMESTAMP)));

-- BYYEARDAY=366 only exists in leap years
SELECT assert_true('sparse-BYYEARDAY-366',
    (SELECT COUNT(*) > 0 FROM rrule."all"(
        'FREQ=YEARLY;BYYEARDAY=366;COUNT=3', '2020-01-01 10:00:00'::TIMESTAMP)));

-- Feb 29 only in leap years (without SKIP)
SELECT assert_true('sparse-feb29',
    (SELECT COUNT(*) > 0 FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;COUNT=3', '2020-02-29 10:00:00'::TIMESTAMP)));

-- BYMONTHDAY=31 - COUNT=10 satisfied by going into next year
SELECT assert_equals('sparse-BYMONTHDAY-31', '10',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=31;COUNT=10', '2025-01-31 10:00:00'::TIMESTAMP)));

-- Friday the 13th (very sparse)
SELECT assert_true('sparse-friday-13',
    (SELECT COUNT(*) > 0 FROM rrule."all"(
        'FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 5: between() CAP VERIFICATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- between() CAP ---'
\echo ''

-- between() should also cap at 1000
SELECT assert_equals('cap-between-1000', '1000',
    (SELECT COUNT(*)::TEXT FROM rrule."between"(
        'FREQ=DAILY', '2025-01-01 10:00:00'::TIMESTAMP,
        '2025-01-01'::TIMESTAMP, '2035-12-31'::TIMESTAMP)));

-- Large range should be capped
SELECT assert_true('cap-between-large-range',
    (SELECT COUNT(*) <= 1000 FROM rrule."between"(
        'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU', '2000-01-01 10:00:00'::TIMESTAMP,
        '2000-01-01'::TIMESTAMP, '2100-12-31'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 6: COUNT PARAMETER RESPECTED
--------------------------------------------------------------------------------
\echo ''
\echo '--- COUNT PARAMETER ---'
\echo ''

-- COUNT should limit before budget cap
SELECT assert_equals('COUNT-respected-small', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

SELECT assert_equals('COUNT-respected-medium', '100',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP)));

SELECT assert_equals('COUNT-respected-large', '500',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;COUNT=500', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 7: UNTIL PARAMETER RESPECTED
--------------------------------------------------------------------------------
\echo ''
\echo '--- UNTIL PARAMETER ---'
\echo ''

-- UNTIL should limit before budget cap
SELECT assert_equals('UNTIL-respected-short', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY;UNTIL=20250105T235959Z', '2025-01-01 10:00:00'::TIMESTAMP)));

SELECT assert_equals('UNTIL-respected-month', '31',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY;UNTIL=20250131T235959Z', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 8: EXPANDED RULES BUDGET
--------------------------------------------------------------------------------
\echo ''
\echo '--- EXPANDED RULES BUDGET ---'
\echo ''

-- Multiple BYMONTH values - 4x expansion
SELECT assert_true('expanded-BYMONTH',
    (SELECT COUNT(*) <= 1000 FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=1,4,7,10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Multiple BYMONTHDAY values - 2x expansion
SELECT assert_true('expanded-BYMONTHDAY',
    (SELECT COUNT(*) <= 1000 FROM rrule."all"(
        'FREQ=YEARLY;BYMONTHDAY=1,15', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Combined expansion
SELECT assert_true('expanded-combined',
    (SELECT COUNT(*) <= 1000 FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=1,4,7,10;BYMONTHDAY=1,15', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYSETPOS with large candidate set
SELECT assert_true('expanded-BYSETPOS',
    (SELECT COUNT(*) <= 1000 FROM rrule."all"(
        'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,2,3,4,5,-5,-4,-3,-2,-1', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 9: TIMESTAMPTZ API BUDGET
--------------------------------------------------------------------------------
\echo ''
\echo '--- TIMESTAMPTZ API BUDGET ---'
\echo ''

-- TIMESTAMPTZ API should have same caps
SELECT assert_equals('cap-tz-DAILY', '1000',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY', '2025-01-01 10:00:00'::TIMESTAMPTZ, 'UTC')));

-- WEEKLY is capped by 10-year window before 1000 results (~522 weeks)
SELECT assert_true('cap-tz-WEEKLY',
    (SELECT COUNT(*) BETWEEN 500 AND 600 FROM rrule."all"(
        'FREQ=WEEKLY', '2025-01-01 10:00:00'::TIMESTAMPTZ, 'America/New_York')));


--------------------------------------------------------------------------------
-- SECTION 10: WARNING FOR UNBOUNDED RULES
--------------------------------------------------------------------------------
\echo ''
\echo '--- UNBOUNDED RULE WARNING ---'
\echo ''

-- Unbounded rules should emit a warning (captured via client_min_messages)
-- We can't easily verify warnings in pure SQL, but we can verify the rule completes

-- This should complete (with warning) rather than hang
SELECT assert_equals('unbounded-completes-DAILY', '1000',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY', '2025-01-01 10:00:00'::TIMESTAMP)));

-- WEEKLY unbounded capped by 10-year window (~522 weeks)
SELECT assert_true('unbounded-completes-WEEKLY',
    (SELECT COUNT(*) BETWEEN 500 AND 600 FROM rrule."all"('FREQ=WEEKLY', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 11: SKIP BUDGET INCREMENT
--------------------------------------------------------------------------------
\echo ''
\echo '--- SKIP BUDGET INCREMENT ---'
\echo ''

-- SKIP=FORWARD should properly increment period_count
-- If not, this would run forever
SELECT assert_equals('budget-SKIP-FORWARD', '100',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=100', '2025-01-31 10:00:00'::TIMESTAMP)));

-- SKIP=BACKWARD should properly increment period_count
SELECT assert_equals('budget-SKIP-BACKWARD', '100',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=100', '2025-01-31 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 12: COMPLEX COMBINATIONS
--------------------------------------------------------------------------------
\echo ''
\echo '--- COMPLEX COMBINATIONS BUDGET ---'
\echo ''

-- Complex rule that generates many candidates but filters most
SELECT assert_true('complex-filters',
    (SELECT COUNT(*) <= 1000 FROM rrule."all"(
        'FREQ=DAILY;BYDAY=MO;BYMONTH=1;BYMONTHDAY=1,8,15,22,29', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY with all filters
SELECT assert_true('complex-YEARLY',
    (SELECT COUNT(*) <= 1000 FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=3;BYDAY=2MO', '2025-01-01 10:00:00'::TIMESTAMP)));


\echo ''
\echo '====================================================================='
\echo 'DoS PROTECTION BUDGET ENFORCEMENT TESTS COMPLETE'
\echo '====================================================================='

ROLLBACK;
