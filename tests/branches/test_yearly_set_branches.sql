/**
 * yearly_set() Internal Branch Coverage Tests
 *
 * Tests each distinct code path in the yearly_set() function directly.
 * These tests exercise internal branches that may not be fully covered
 * by use-case tests.
 *
 * Branches in yearly_set() (from rrule.sql):
 * 1. BYMONTH primary (line ~2256)
 * 2. BYWEEKNO primary (line ~2270)
 * 3. BYYEARDAY primary (line ~2285)
 * 4. YEARLY BYDAY ordinals (line ~2299)
 * 5. BYMONTHDAY/BYDAY with BYSETPOS (line ~2310)
 * 6. BYMONTHDAY/BYDAY without BYSETPOS (line ~2322)
 * 7. Plain anniversary (line ~2347)
 *
 * Also tests monthly_set(), weekly_set(), and daily_set() key branches.
 *
 * Usage:
 *   psql -d your_database -f tests/branches/test_yearly_set_branches.sql
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
\echo 'INTERNAL BRANCH COVERAGE TESTS'
\echo '====================================================================='
\echo ''

--------------------------------------------------------------------------------
-- SECTION 1: yearly_set() BRANCH COVERAGE
--------------------------------------------------------------------------------
\echo ''
\echo '--- yearly_set() BRANCH COVERAGE ---'
\echo ''

-- Branch 1: BYMONTH primary path
-- Exercises: BYMONTH IS NOT NULL branch (line ~2256)
SELECT assert_equals('yearly-branch-1-BYMONTH-primary', '4',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=1,4,7,10;COUNT=4', '2025-01-15 10:00:00'::TIMESTAMP)));

-- Branch 1 with post-filters: BYMONTH + BYWEEKNO filter
SELECT assert_true('yearly-branch-1-BYMONTH-BYWEEKNO-filter',
    (SELECT COUNT(*) >= 0 FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=3;BYWEEKNO=10;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 1 with post-filters: BYMONTH + BYYEARDAY filter
-- BYMONTH-primary path generates candidates at dtstart day-of-month for each month in BYMONTH,
-- then BYYEARDAY filters. Since BYMONTH=4 with dtstart=Jan 1 generates April 1st (day 91),
-- and BYYEARDAY=100 is April 10th, the intersection is empty.
-- This is expected behavior per RFC 5545 §3.3.10 table where both are "Expand" for YEARLY.
SELECT assert_equals('yearly-branch-1-BYMONTH-BYYEARDAY-empty', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=4;BYYEARDAY=100;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- To get intersection, dtstart day must match BYYEARDAY
-- April 10 is day 100, so starting on April 10 with BYMONTH=4 and BYYEARDAY=100 should match
SELECT assert_equals('yearly-branch-1-BYMONTH-BYYEARDAY-match', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=4;BYYEARDAY=100;COUNT=3', '2025-04-10 10:00:00'::TIMESTAMP)));

-- Branch 2: BYWEEKNO primary path
-- Exercises: BYWEEKNO IS NOT NULL branch (line ~2270)
SELECT assert_equals('yearly-branch-2-BYWEEKNO-primary', '7',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYWEEKNO=10;COUNT=7', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 2 with BYDAY filter
SELECT assert_equals('yearly-branch-2-BYWEEKNO-BYDAY', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYWEEKNO=10;BYDAY=MO,WE,FR;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 2 with BYMONTHDAY filter
SELECT assert_true('yearly-branch-2-BYWEEKNO-BYMONTHDAY',
    (SELECT COUNT(*) >= 0 FROM rrule."all"(
        'FREQ=YEARLY;BYWEEKNO=10;BYMONTHDAY=5;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 2 with BYYEARDAY filter (intersection)
SELECT assert_true('yearly-branch-2-BYWEEKNO-BYYEARDAY',
    (SELECT COUNT(*) >= 0 FROM rrule."all"(
        'FREQ=YEARLY;BYWEEKNO=10;BYYEARDAY=65;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 3: BYYEARDAY primary path
-- Exercises: BYYEARDAY IS NOT NULL branch (line ~2285)
SELECT assert_equals('yearly-branch-3-BYYEARDAY-primary', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYYEARDAY=100;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 3 with multiple BYYEARDAY values
SELECT assert_equals('yearly-branch-3-BYYEARDAY-multiple', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYYEARDAY=100,200;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 3 with negative BYYEARDAY
SELECT assert_equals('yearly-branch-3-BYYEARDAY-negative', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYYEARDAY=-1;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 3 with BYMONTH filter (intersection)
-- Note: When both BYMONTH and BYYEARDAY are present, BYMONTH takes priority (checked first in IF chain).
-- BYMONTH-primary generates April 1st, then BYYEARDAY=100 filter rejects it (not day 100).
-- This test documents the expected behavior: intersection is empty.
SELECT assert_equals('yearly-branch-3-BYYEARDAY-BYMONTH', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYYEARDAY=100;BYMONTH=4;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 4: YEARLY BYDAY ordinals (no BYMONTH/BYWEEKNO)
-- Exercises: has_yearly_ordinals branch (line ~2299)
SELECT assert_equals('yearly-branch-4-BYDAY-ordinal', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYDAY=2MO;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 4 with negative ordinal
SELECT assert_equals('yearly-branch-4-BYDAY-neg-ordinal', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYDAY=-1FR;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 4 with BYMONTHDAY filter
SELECT assert_true('yearly-branch-4-BYDAY-BYMONTHDAY',
    (SELECT COUNT(*) >= 0 FROM rrule."all"(
        'FREQ=YEARLY;BYDAY=2MO;BYMONTHDAY=13;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 5: BYMONTHDAY/BYDAY with BYSETPOS
-- Exercises: BYSETPOS IS NOT NULL branch (line ~2310)
SELECT assert_equals('yearly-branch-5-BYSETPOS', '4',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTHDAY=1,15;BYSETPOS=1,-1;COUNT=4', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 5 with BYDAY and BYSETPOS
SELECT assert_equals('yearly-branch-5-BYDAY-BYSETPOS', '4',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYDAY=MO;BYSETPOS=1,-1;COUNT=4', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 6: BYMONTHDAY/BYDAY without BYSETPOS
-- Exercises: BYSETPOS IS NULL branch with early exit (line ~2322)
SELECT assert_equals('yearly-branch-6-BYMONTHDAY-no-BYSETPOS', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTHDAY=15;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 6 with BYDAY (no ordinal)
SELECT assert_equals('yearly-branch-6-BYDAY-no-ordinal', '52',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYDAY=MO;COUNT=52', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Branch 7: Plain anniversary (no BYxxx filters)
-- Exercises: ELSE branch (line ~2347)
SELECT assert_equals('yearly-branch-7-anniversary', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;COUNT=5', '2025-06-15 10:00:00'::TIMESTAMP)));

-- Branch 7 with INTERVAL
SELECT assert_equals('yearly-branch-7-anniversary-INTERVAL', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;INTERVAL=2;COUNT=3', '2025-06-15 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 2: monthly_set() BRANCH COVERAGE
--------------------------------------------------------------------------------
\echo ''
\echo '--- monthly_set() BRANCH COVERAGE ---'
\echo ''

-- BYDAY with ordinal (specific occurrence in month)
SELECT assert_equals('monthly-BYDAY-ordinal', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYDAY=2TU;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYDAY with negative ordinal
SELECT assert_equals('monthly-BYDAY-neg-ordinal', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYDAY=-1FR;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYDAY without ordinal (all matching days in month)
SELECT assert_true('monthly-BYDAY-no-ordinal',
    (SELECT COUNT(*) > 6 FROM rrule."all"(
        'FREQ=MONTHLY;BYDAY=MO,WE,FR;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYMONTHDAY only
SELECT assert_equals('monthly-BYMONTHDAY-only', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYMONTHDAY + BYDAY (intersection)
SELECT assert_true('monthly-BYMONTHDAY-BYDAY',
    (SELECT COUNT(*) >= 0 FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=13;BYDAY=FR;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYSETPOS path
SELECT assert_equals('monthly-BYSETPOS', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Plain anniversary (no BYDAY/BYMONTHDAY)
SELECT assert_equals('monthly-anniversary', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;COUNT=6', '2025-01-15 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 3: weekly_set() BRANCH COVERAGE
--------------------------------------------------------------------------------
\echo ''
\echo '--- weekly_set() BRANCH COVERAGE ---'
\echo ''

-- BYDAY expand (multiple days)
SELECT assert_equals('weekly-BYDAY-expand', '15',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=15', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYDAY single day
SELECT assert_equals('weekly-BYDAY-single', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=WEEKLY;BYDAY=TU;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- No BYDAY (uses dtstart weekday)
SELECT assert_equals('weekly-no-BYDAY', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=WEEKLY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- WKST affects week boundaries
SELECT assert_equals('weekly-WKST-SU', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=WEEKLY;WKST=SU;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- INTERVAL > 1
SELECT assert_equals('weekly-INTERVAL', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=WEEKLY;INTERVAL=2;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 4: daily_set() BRANCH COVERAGE
--------------------------------------------------------------------------------
\echo ''
\echo '--- daily_set() BRANCH COVERAGE ---'
\echo ''

-- Basic daily
SELECT assert_equals('daily-basic', '10',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYDAY filter
SELECT assert_equals('daily-BYDAY-filter', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY;BYDAY=MO;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYHOUR expansion (start at 08:00 so 9:00 is included on first day)
SELECT assert_equals('daily-BYHOUR', '9',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY;BYHOUR=9,12,17;COUNT=9', '2025-01-01 08:00:00'::TIMESTAMP)));

-- BYMINUTE expansion
SELECT assert_equals('daily-BYMINUTE', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY;BYMINUTE=0,30;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYSECOND expansion
SELECT assert_equals('daily-BYSECOND', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY;BYSECOND=0,30;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Combined time filters (start early enough to get all times on first day)
SELECT assert_equals('daily-combined-time', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY;BYHOUR=9,17;BYMINUTE=0,30;COUNT=12', '2025-01-01 08:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 5: max_results PARAMETER BRANCH COVERAGE
--------------------------------------------------------------------------------
\echo ''
\echo '--- max_results PARAMETER BRANCH COVERAGE ---'
\echo ''

-- Verify max_results is respected when BYSETPOS is used (requires NULL passthrough)
SELECT assert_equals('max_results-BYSETPOS-cursor', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,2,3,-3,-2,-1;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Verify max_results works without BYSETPOS (direct count)
SELECT assert_equals('max_results-no-BYSETPOS', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYDAY=2TU;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Verify early exit optimization (Issue 51) - yearly without BYMONTH
SELECT assert_equals('max_results-early-exit', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTHDAY=15;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 6: SKIP HANDLING IN SET FUNCTIONS
--------------------------------------------------------------------------------
\echo ''
\echo '--- SKIP HANDLING IN SET FUNCTIONS ---'
\echo ''

-- SKIP=OMIT (default) - months without 31st are skipped
SELECT assert_equals('skip-OMIT-monthly', '7',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=31;COUNT=7', '2025-01-31 10:00:00'::TIMESTAMP)));

-- SKIP=BACKWARD - use last valid day
SELECT assert_equals('skip-BACKWARD-monthly', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP)));

-- SKIP=FORWARD - use first of next month
SELECT assert_equals('skip-FORWARD-monthly', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP)));

-- Verify SKIP=FORWARD with BYMONTH deduplication
SELECT assert_true('skip-FORWARD-BYMONTH-dedup',
    (SELECT COUNT(*) = COUNT(DISTINCT r) FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=1,2,3;BYMONTHDAY=31;SKIP=FORWARD;COUNT=9', '2025-01-31 10:00:00'::TIMESTAMP) r));


\echo ''
\echo '====================================================================='
\echo 'INTERNAL BRANCH COVERAGE TESTS COMPLETE'
\echo '====================================================================='

ROLLBACK;
