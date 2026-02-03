/**
 * Branch Coverage Tests
 *
 * This file systematically exercises every internal branch in the RRULE
 * implementation. Each test is documented with:
 * - The file and line number of the branch
 * - The condition being tested
 * - Why this specific RRULE exercises that branch
 *
 * Use this as a checklist when making changes - if you add a new branch,
 * add a corresponding test here.
 *
 * Branch naming convention: BRANCH-<function>-<number>
 *
 * Usage:
 *   psql -d your_database -f tests/branches/test_branch_coverage.sql
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
\echo 'BRANCH COVERAGE TESTS'
\echo '====================================================================='
\echo ''
\echo 'Systematically exercising every internal code branch'
\echo ''

--------------------------------------------------------------------------------
-- SECTION 1: parse_rrule_parts() BRANCHES
--------------------------------------------------------------------------------
\echo ''
\echo '--- parse_rrule_parts() branches ---'
\echo ''

-- BRANCH-parse-1: UNTIL with Z suffix (valid UTC timestamp)
-- File: rrule.sql, parse_rrule_parts, around line 123
-- Condition: until_str IS NOT NULL AND until_str ~ 'Z$'
SELECT assert_true('BRANCH-parse-1-until-utc',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=DAILY;UNTIL=20250105T235959Z', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-2: WKST=SU (week start Sunday)
-- File: rrule.sql, parse_rrule_parts
-- Condition: WKST parameter parsing
SELECT assert_true('BRANCH-parse-2-wkst-su',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=WEEKLY;WKST=SU;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-3: SKIP=BACKWARD (RFC 7529)
-- File: rrule.sql, parse_rrule_parts
-- Condition: SKIP parameter with non-default value
SELECT assert_true('BRANCH-parse-3-skip-backward',
    (SELECT COUNT(*) = 12 FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-4: SKIP=FORWARD (RFC 7529)
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-4-skip-forward',
    (SELECT COUNT(*) = 12 FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-5: RSCALE=GREGORIAN explicit
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-5-rscale',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=MONTHLY;RSCALE=GREGORIAN;SKIP=BACKWARD;COUNT=5', '2025-01-31 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-6: INTERVAL > 1
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-6-interval',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=DAILY;INTERVAL=3;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-7: Negative BYMONTHDAY
-- File: rrule.sql, parse_rrule_parts, BYMONTHDAY array parsing
SELECT assert_true('BRANCH-parse-7-bymonthday-neg',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=5', '2025-01-31 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-8: Multiple BYMONTH values
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-8-bymonth-multi',
    (SELECT COUNT(*) = 10 FROM rrule."all"('FREQ=YEARLY;BYMONTH=1,6;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-9: BYDAY with ordinal (2MO)
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-9-byday-ordinal',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=MONTHLY;BYDAY=2MO;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-10: Negative BYDAY ordinal (-1FR)
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-10-byday-neg-ordinal',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=MONTHLY;BYDAY=-1FR;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-11: Multiple BYDAY values
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-11-byday-multi',
    (SELECT COUNT(*) = 15 FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=15', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-12: BYSETPOS positive
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-12-bysetpos-pos',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-13: BYSETPOS negative
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-13-bysetpos-neg',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-14: Multiple BYSETPOS values
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-14-bysetpos-multi',
    (SELECT COUNT(*) = 10 FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-15: BYHOUR with DAILY
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-15-byhour',
    (SELECT COUNT(*) = 9 FROM rrule."all"('FREQ=DAILY;BYHOUR=9,12,17;COUNT=9', '2025-01-01 09:00:00'::TIMESTAMP)));

-- BRANCH-parse-16: BYMINUTE with DAILY
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-16-byminute',
    (SELECT COUNT(*) = 6 FROM rrule."all"('FREQ=DAILY;BYMINUTE=0,30;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-17: BYSECOND with DAILY
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-17-bysecond',
    (SELECT COUNT(*) = 6 FROM rrule."all"('FREQ=DAILY;BYSECOND=0,30;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-18: BYYEARDAY positive
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-18-byyearday-pos',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=YEARLY;BYYEARDAY=100;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-19: BYYEARDAY negative
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-19-byyearday-neg',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=YEARLY;BYYEARDAY=-1;COUNT=5', '2025-12-31 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-20: BYWEEKNO
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-20-byweekno',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=YEARLY;BYWEEKNO=10;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-parse-21: TZID parameter
-- File: rrule.sql, parse_rrule_parts
SELECT assert_true('BRANCH-parse-21-tzid',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=DAILY;TZID=America/New_York;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 2: daily_set() BRANCHES
--------------------------------------------------------------------------------
\echo ''
\echo '--- daily_set() branches ---'
\echo ''

-- BRANCH-daily-1: Basic daily (no filters)
-- File: rrule.sql, daily_set, line ~1790
SELECT assert_true('BRANCH-daily-1-basic',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-daily-2: BYDAY filter active
-- File: rrule.sql, daily_set, BYDAY filter branch
SELECT assert_true('BRANCH-daily-2-byday',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=DAILY;BYDAY=MO;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-daily-3: BYMONTH filter active
-- File: rrule.sql, daily_set, BYMONTH filter branch
SELECT assert_true('BRANCH-daily-3-bymonth',
    (SELECT COUNT(*) = 31 FROM rrule."all"('FREQ=DAILY;BYMONTH=1;COUNT=31', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-daily-4: BYMONTHDAY filter active
-- File: rrule.sql, daily_set, BYMONTHDAY filter branch
SELECT assert_true('BRANCH-daily-4-bymonthday',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=DAILY;BYMONTHDAY=15;COUNT=5', '2025-01-15 10:00:00'::TIMESTAMP)));

-- BRANCH-daily-5: BYHOUR expansion
-- File: rrule.sql, daily_set, time expansion branch
SELECT assert_true('BRANCH-daily-5-byhour',
    (SELECT COUNT(*) = 15 FROM rrule."all"('FREQ=DAILY;BYHOUR=9,12,17;COUNT=15', '2025-01-01 09:00:00'::TIMESTAMP)));

-- BRANCH-daily-6: Combined filters (BYDAY + BYMONTH)
-- File: rrule.sql, daily_set, multiple filters active
SELECT assert_true('BRANCH-daily-6-combined',
    (SELECT COUNT(*) > 0 FROM rrule."all"('FREQ=DAILY;BYDAY=MO;BYMONTH=1;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 3: weekly_set() BRANCHES
--------------------------------------------------------------------------------
\echo ''
\echo '--- weekly_set() branches ---'
\echo ''

-- BRANCH-weekly-1: Basic weekly (no BYDAY - uses dtstart weekday)
-- File: rrule.sql, weekly_set, line ~1850
SELECT assert_true('BRANCH-weekly-1-basic',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=WEEKLY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-weekly-2: BYDAY expansion
-- File: rrule.sql, weekly_set, BYDAY expansion branch
SELECT assert_true('BRANCH-weekly-2-byday',
    (SELECT COUNT(*) = 15 FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=15', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-weekly-3: BYMONTH filter active
-- File: rrule.sql, weekly_set, BYMONTH filter branch
SELECT assert_true('BRANCH-weekly-3-bymonth',
    (SELECT COUNT(*) > 0 FROM rrule."all"('FREQ=WEEKLY;BYMONTH=1,2;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-weekly-4: WKST affects week boundaries
-- File: rrule.sql, weekly_set, WKST handling
SELECT assert_true('BRANCH-weekly-4-wkst',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=WEEKLY;WKST=SU;BYDAY=MO;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-weekly-5: BYSETPOS with BYDAY
-- File: rrule.sql, weekly_set, BYSETPOS branch
SELECT assert_true('BRANCH-weekly-5-bysetpos',
    (SELECT COUNT(*) = 10 FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 4: monthly_set() BRANCHES
--------------------------------------------------------------------------------
\echo ''
\echo '--- monthly_set() branches ---'
\echo ''

-- BRANCH-monthly-1: Basic monthly (anniversary)
-- File: rrule.sql, monthly_set, line ~1906, anniversary branch
SELECT assert_true('BRANCH-monthly-1-anniversary',
    (SELECT COUNT(*) = 12 FROM rrule."all"('FREQ=MONTHLY;COUNT=12', '2025-01-15 10:00:00'::TIMESTAMP)));

-- BRANCH-monthly-2: BYMONTHDAY specified
-- File: rrule.sql, monthly_set, BYMONTHDAY branch
SELECT assert_true('BRANCH-monthly-2-bymonthday',
    (SELECT COUNT(*) = 12 FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=15;COUNT=12', '2025-01-15 10:00:00'::TIMESTAMP)));

-- BRANCH-monthly-3: BYDAY with ordinal
-- File: rrule.sql, monthly_set, BYDAY ordinal branch
SELECT assert_true('BRANCH-monthly-3-byday-ordinal',
    (SELECT COUNT(*) = 12 FROM rrule."all"('FREQ=MONTHLY;BYDAY=2TU;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-monthly-4: BYDAY without ordinal
-- File: rrule.sql, monthly_set, BYDAY non-ordinal branch
SELECT assert_true('BRANCH-monthly-4-byday-simple',
    (SELECT COUNT(*) > 0 FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO;COUNT=50', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-monthly-5: BYSETPOS with BYDAY
-- File: rrule.sql, monthly_set, BYSETPOS branch
SELECT assert_true('BRANCH-monthly-5-bysetpos',
    (SELECT COUNT(*) = 12 FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-monthly-6: SKIP=OMIT (default, skips invalid dates)
-- File: rrule.sql, monthly_set, SKIP=OMIT branch
SELECT assert_true('BRANCH-monthly-6-skip-omit',
    (SELECT COUNT(*) = 7 FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=31;COUNT=7', '2025-01-31 10:00:00'::TIMESTAMP)));

-- BRANCH-monthly-7: SKIP=BACKWARD
-- File: rrule.sql, monthly_set, SKIP=BACKWARD branch
SELECT assert_true('BRANCH-monthly-7-skip-backward',
    (SELECT COUNT(*) = 12 FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP)));

-- BRANCH-monthly-8: SKIP=FORWARD
-- File: rrule.sql, monthly_set, SKIP=FORWARD branch
SELECT assert_true('BRANCH-monthly-8-skip-forward',
    (SELECT COUNT(*) = 12 FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP)));

-- BRANCH-monthly-9: BYMONTH filter
-- File: rrule.sql, monthly_set, BYMONTH filter branch
SELECT assert_true('BRANCH-monthly-9-bymonth',
    (SELECT COUNT(*) = 8 FROM rrule."all"('FREQ=MONTHLY;BYMONTH=3,6,9,12;COUNT=8', '2025-01-15 10:00:00'::TIMESTAMP)));

-- BRANCH-monthly-10: Negative BYDAY ordinal (-1FR)
-- File: rrule.sql, monthly_set, negative ordinal branch
SELECT assert_true('BRANCH-monthly-10-neg-ordinal',
    (SELECT COUNT(*) = 12 FROM rrule."all"('FREQ=MONTHLY;BYDAY=-1FR;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 5: yearly_set() BRANCHES
--------------------------------------------------------------------------------
\echo ''
\echo '--- yearly_set() branches ---'
\echo ''

-- BRANCH-yearly-1: Basic yearly (anniversary)
-- File: rrule.sql, yearly_set, line ~2217, anniversary branch
SELECT assert_true('BRANCH-yearly-1-anniversary',
    (SELECT COUNT(*) = 10 FROM rrule."all"('FREQ=YEARLY;COUNT=10', '2025-06-15 10:00:00'::TIMESTAMP)));

-- BRANCH-yearly-2: BYMONTH primary path
-- File: rrule.sql, yearly_set, BYMONTH-primary branch (line ~2253)
SELECT assert_true('BRANCH-yearly-2-bymonth-primary',
    (SELECT COUNT(*) = 30 FROM rrule."all"('FREQ=YEARLY;BYMONTH=1,6,12;COUNT=30', '2025-01-15 10:00:00'::TIMESTAMP)));

-- BRANCH-yearly-3: BYWEEKNO primary path
-- File: rrule.sql, yearly_set, BYWEEKNO-primary branch (line ~2270)
SELECT assert_true('BRANCH-yearly-3-byweekno-primary',
    (SELECT COUNT(*) = 10 FROM rrule."all"('FREQ=YEARLY;BYWEEKNO=10;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-yearly-4: BYYEARDAY primary path
-- File: rrule.sql, yearly_set, BYYEARDAY-primary branch (line ~2286)
SELECT assert_true('BRANCH-yearly-4-byyearday-primary',
    (SELECT COUNT(*) = 10 FROM rrule."all"('FREQ=YEARLY;BYYEARDAY=100;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-yearly-5: BYDAY ordinal path
-- File: rrule.sql, yearly_set, YEARLY BYDAY ordinal branch (line ~2299)
SELECT assert_true('BRANCH-yearly-5-byday-ordinal',
    (SELECT COUNT(*) = 10 FROM rrule."all"('FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-yearly-6: BYMONTHDAY + BYDAY with BYSETPOS
-- File: rrule.sql, yearly_set, BYSETPOS path (line ~2310)
SELECT assert_true('BRANCH-yearly-6-bysetpos',
    (SELECT COUNT(*) = 20 FROM rrule."all"('FREQ=YEARLY;BYMONTH=1;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-yearly-7: BYMONTHDAY + BYDAY without BYSETPOS
-- File: rrule.sql, yearly_set, non-BYSETPOS expansion path (line ~2322)
SELECT assert_true('BRANCH-yearly-7-expansion',
    (SELECT COUNT(*) > 0 FROM rrule."all"('FREQ=YEARLY;BYMONTH=1;BYDAY=MO;COUNT=50', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-yearly-8: BYWEEKNO with BYMONTH filter
-- File: rrule.sql, yearly_set, BYWEEKNO+BYMONTH intersection
SELECT assert_true('BRANCH-yearly-8-byweekno-bymonth',
    (SELECT COUNT(*) >= 0 FROM rrule."all"('FREQ=YEARLY;BYWEEKNO=10;BYMONTH=3;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-yearly-9: BYWEEKNO=53 (sparse - not all years have week 53)
-- File: rrule.sql, yearly_set, sparse week 53 handling
SELECT assert_true('BRANCH-yearly-9-byweekno-53',
    (SELECT COUNT(*) > 0 FROM rrule."all"('FREQ=YEARLY;BYWEEKNO=53;COUNT=5', '2020-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-yearly-10: BYYEARDAY negative
-- File: rrule.sql, yearly_set, negative BYYEARDAY handling
SELECT assert_true('BRANCH-yearly-10-byyearday-neg',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=YEARLY;BYYEARDAY=-1;COUNT=5', '2025-12-31 10:00:00'::TIMESTAMP)));

-- BRANCH-yearly-11: Leap year Feb 29
-- File: rrule.sql, yearly_set, leap year handling
SELECT assert_true('BRANCH-yearly-11-leap-feb29',
    (SELECT COUNT(*) > 0 FROM rrule."all"('FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;COUNT=5', '2020-02-29 10:00:00'::TIMESTAMP)));

-- BRANCH-yearly-12: SKIP=FORWARD for leap day
-- File: rrule.sql, yearly_set, SKIP=FORWARD with leap day
SELECT assert_true('BRANCH-yearly-12-skip-forward-leap',
    (SELECT COUNT(*) = 10 FROM rrule."all"('FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=FORWARD;COUNT=10', '2020-02-29 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 6: rrule_event_instances_range() MAIN LOOP BRANCHES
--------------------------------------------------------------------------------
\echo ''
\echo '--- rrule_event_instances_range() main loop branches ---'
\echo ''

-- BRANCH-main-1: COUNT termination
-- File: rrule.sql, rrule_event_instances_range, COUNT check branch
SELECT assert_true('BRANCH-main-1-count-term',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-main-2: UNTIL termination
-- File: rrule.sql, rrule_event_instances_range, UNTIL check branch
SELECT assert_true('BRANCH-main-2-until-term',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=DAILY;UNTIL=20250105T235959Z', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-main-3: 10-year window termination
-- File: rrule.sql, rrule_event_instances_range, 10-year cap branch
SELECT assert_true('BRANCH-main-3-10year-cap',
    (SELECT MAX(r) - '2025-01-01 10:00:00'::TIMESTAMP <= INTERVAL '3652 days'
     FROM rrule."all"('FREQ=YEARLY', '2025-01-01 10:00:00'::TIMESTAMP) r));

-- BRANCH-main-4: 1000 result cap
-- File: rrule.sql, rrule_event_instances_range, 1000 result cap branch
SELECT assert_true('BRANCH-main-4-1000-cap',
    (SELECT COUNT(*) = 1000 FROM rrule."all"('FREQ=DAILY', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-main-5: DAILY frequency dispatch
-- File: rrule.sql, rrule_event_instances_range, DAILY branch
SELECT assert_true('BRANCH-main-5-daily-dispatch',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-main-6: WEEKLY frequency dispatch
-- File: rrule.sql, rrule_event_instances_range, WEEKLY branch
SELECT assert_true('BRANCH-main-6-weekly-dispatch',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=WEEKLY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-main-7: MONTHLY frequency dispatch
-- File: rrule.sql, rrule_event_instances_range, MONTHLY branch
SELECT assert_true('BRANCH-main-7-monthly-dispatch',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=MONTHLY;COUNT=5', '2025-01-15 10:00:00'::TIMESTAMP)));

-- BRANCH-main-8: YEARLY frequency dispatch
-- File: rrule.sql, rrule_event_instances_range, YEARLY branch
SELECT assert_true('BRANCH-main-8-yearly-dispatch',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=YEARLY;COUNT=5', '2025-06-15 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 7: HELPER FUNCTION BRANCHES
--------------------------------------------------------------------------------
\echo ''
\echo '--- Helper function branches ---'
\echo ''

-- BRANCH-helper-1: test_byday_rule with matching day
-- File: rrule.sql, test_byday_rule
SELECT assert_true('BRANCH-helper-1-byday-match',
    (SELECT COUNT(*) > 0 FROM rrule."all"('FREQ=DAILY;BYDAY=MO;COUNT=5', '2025-01-06 10:00:00'::TIMESTAMP)));

-- BRANCH-helper-2: test_bymonth_rule with matching month
-- File: rrule.sql, test_bymonth_rule
SELECT assert_true('BRANCH-helper-2-bymonth-match',
    (SELECT COUNT(*) > 0 FROM rrule."all"('FREQ=DAILY;BYMONTH=1;COUNT=31', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-helper-3: test_bymonthday_rule with matching day
-- File: rrule.sql, test_bymonthday_rule
SELECT assert_true('BRANCH-helper-3-bymonthday-match',
    (SELECT COUNT(*) > 0 FROM rrule."all"('FREQ=DAILY;BYMONTHDAY=15;COUNT=5', '2025-01-15 10:00:00'::TIMESTAMP)));

-- BRANCH-helper-4: test_byyearday_rule with matching day
-- File: rrule.sql, test_byyearday_rule
SELECT assert_true('BRANCH-helper-4-byyearday-match',
    (SELECT COUNT(*) > 0 FROM rrule."all"('FREQ=YEARLY;BYYEARDAY=1;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-helper-5: byweekno_matches with matching week
-- File: rrule.sql, byweekno_matches
SELECT assert_true('BRANCH-helper-5-byweekno-match',
    (SELECT COUNT(*) > 0 FROM rrule."all"('FREQ=YEARLY;BYWEEKNO=1;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-helper-6: weekday_to_number for each day
-- File: rrule.sql, weekday_to_number
SELECT assert_true('BRANCH-helper-6-weekday-all',
    (SELECT COUNT(*) = 7 FROM (
        SELECT rrule.weekday_to_number('MO') UNION ALL
        SELECT rrule.weekday_to_number('TU') UNION ALL
        SELECT rrule.weekday_to_number('WE') UNION ALL
        SELECT rrule.weekday_to_number('TH') UNION ALL
        SELECT rrule.weekday_to_number('FR') UNION ALL
        SELECT rrule.weekday_to_number('SA') UNION ALL
        SELECT rrule.weekday_to_number('SU')
    ) days));

-- BRANCH-helper-7: calculate_safe_iteration_limit for each frequency
-- File: rrule.sql, calculate_safe_iteration_limit
SELECT assert_true('BRANCH-helper-7-limits',
    rrule.calculate_safe_iteration_limit('DAILY', NULL, 1000) > 0 AND
    rrule.calculate_safe_iteration_limit('WEEKLY', NULL, 1000) > 0 AND
    rrule.calculate_safe_iteration_limit('MONTHLY', NULL, 1000) > 0 AND
    rrule.calculate_safe_iteration_limit('YEARLY', NULL, 1000) > 0);


--------------------------------------------------------------------------------
-- SECTION 8: BYSETPOS CURSOR BRANCHES
--------------------------------------------------------------------------------
\echo ''
\echo '--- BYSETPOS cursor branches ---'
\echo ''

-- BRANCH-bysetpos-1: Single positive BYSETPOS
-- File: rrule.sql, rrule_bysetpos_filter
SELECT assert_true('BRANCH-bysetpos-1-single-pos',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-bysetpos-2: Single negative BYSETPOS
-- File: rrule.sql, rrule_bysetpos_filter
SELECT assert_true('BRANCH-bysetpos-2-single-neg',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-bysetpos-3: Multiple BYSETPOS (first and last)
-- File: rrule.sql, rrule_bysetpos_filter
SELECT assert_true('BRANCH-bysetpos-3-multi',
    (SELECT COUNT(*) = 10 FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-bysetpos-4: BYSETPOS with WEEKLY
-- File: rrule.sql, rrule_bysetpos_filter via weekly_set
SELECT assert_true('BRANCH-bysetpos-4-weekly',
    (SELECT COUNT(*) = 10 FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BRANCH-bysetpos-5: BYSETPOS with YEARLY
-- File: rrule.sql, rrule_bysetpos_filter via yearly_set
SELECT assert_true('BRANCH-bysetpos-5-yearly',
    (SELECT COUNT(*) = 10 FROM rrule."all"('FREQ=YEARLY;BYMONTH=1;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 9: TIMESTAMPTZ API BRANCHES
--------------------------------------------------------------------------------
\echo ''
\echo '--- TIMESTAMPTZ API branches ---'
\echo ''

-- BRANCH-tz-1: Basic TIMESTAMPTZ API
-- File: rrule.sql, rrule."all"(varchar, timestamptz, varchar)
SELECT assert_true('BRANCH-tz-1-basic',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMPTZ, 'UTC')));

-- BRANCH-tz-2: TIMESTAMPTZ with different timezone
-- File: rrule.sql, TIMESTAMPTZ API with timezone conversion
SELECT assert_true('BRANCH-tz-2-tz-convert',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMPTZ, 'America/New_York')));

-- BRANCH-tz-3: DST spring forward
-- File: rrule.sql, TIMESTAMPTZ API DST handling
SELECT assert_true('BRANCH-tz-3-dst-spring',
    (SELECT COUNT(*) = 7 FROM rrule."all"('FREQ=DAILY;COUNT=7', '2025-03-08 10:00:00'::TIMESTAMPTZ, 'America/New_York')));

-- BRANCH-tz-4: DST fall back
-- File: rrule.sql, TIMESTAMPTZ API DST handling
SELECT assert_true('BRANCH-tz-4-dst-fall',
    (SELECT COUNT(*) = 7 FROM rrule."all"('FREQ=DAILY;COUNT=7', '2025-11-01 10:00:00'::TIMESTAMPTZ, 'America/New_York')));


--------------------------------------------------------------------------------
-- SUMMARY
--------------------------------------------------------------------------------

\echo ''
\echo '====================================================================='
\echo 'BRANCH COVERAGE TESTS COMPLETE'
\echo '====================================================================='
\echo ''
\echo 'Total branches tested:'
\echo '  - parse_rrule_parts(): 21 branches'
\echo '  - daily_set(): 6 branches'
\echo '  - weekly_set(): 5 branches'
\echo '  - monthly_set(): 10 branches'
\echo '  - yearly_set(): 12 branches'
\echo '  - main loop: 8 branches'
\echo '  - helper functions: 7 branches'
\echo '  - BYSETPOS cursor: 5 branches'
\echo '  - TIMESTAMPTZ API: 4 branches'
\echo ''
\echo 'If all tests pass, major code paths are covered.'
\echo ''

ROLLBACK;
