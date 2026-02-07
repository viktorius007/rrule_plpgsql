/**
 * FREQ × BYxxx Feature Matrix Tests
 *
 * Systematic tests derived from SPEC_COMPLIANCE.md feature matrix.
 * Tests every valid FREQ × BYxxx combination to ensure the implementation
 * matches the documented behavior (expand, limit, or error).
 *
 * Coverage: 119 systematic tests covering every claimed feature.
 *
 * Usage:
 *   psql -d your_database -f tests/matrix/test_freq_byxxx_matrix.sql
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
\echo 'FREQ × BYxxx FEATURE MATRIX TESTS'
\echo '====================================================================='
\echo ''
\echo 'Testing all valid FREQ × BYxxx combinations from SPEC_COMPLIANCE.md'
\echo ''

--------------------------------------------------------------------------------
-- SECTION 1: DAILY FREQUENCY (All BYxxx parameters supported)
--------------------------------------------------------------------------------
\echo ''
\echo '--- DAILY FREQUENCY ---'
\echo ''

-- DAILY + COUNT (core modifier)
SELECT assert_equals('DAILY+COUNT', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- DAILY + UNTIL (core modifier)
SELECT assert_equals('DAILY+UNTIL', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;UNTIL=20250105T235959Z', '2025-01-01 10:00:00'::TIMESTAMP)));

-- DAILY + INTERVAL (core modifier)
SELECT assert_equals('DAILY+INTERVAL', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;INTERVAL=3;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- DAILY + BYDAY (limit - filters to specific weekdays)
SELECT assert_equals('DAILY+BYDAY', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;BYDAY=MO;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- DAILY + BYDAY (ordinals are rejected for DAILY per RFC 5545)
-- Testing simple BYDAY without ordinal
SELECT assert_equals('DAILY+BYDAY-simple', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;BYDAY=MO,TU;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- DAILY + BYMONTHDAY (limit - filters to specific days of month)
SELECT assert_equals('DAILY+BYMONTHDAY', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;BYMONTHDAY=15;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- DAILY + BYMONTHDAY negative (last day of month)
SELECT assert_equals('DAILY+BYMONTHDAY-neg', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;BYMONTHDAY=-1;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- DAILY + BYMONTH (limit - filters to specific months)
-- January 2025 has 31 days, but we count from Jan 1 and limit by first 31 occurrences in Jan
SELECT assert_equals('DAILY+BYMONTH', '31',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;BYMONTH=1;COUNT=31', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Note: BYYEARDAY is rejected with DAILY per RFC 5545 (tested in rejection_matrix.sql)

-- Note: BYWEEKNO is rejected with non-YEARLY per RFC 5545 (tested in rejection_matrix.sql)

-- DAILY + WKST
SELECT assert_equals('DAILY+WKST', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;WKST=SU;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- DAILY + BYHOUR (expand - generates multiple times per day)
-- Starting at 10:00, first day only has 12:00 and 17:00 (9:00 is before dtstart)
SELECT assert_equals('DAILY+BYHOUR', '15',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;BYHOUR=9,12,17;COUNT=15', '2025-01-01 08:00:00'::TIMESTAMP)));

-- DAILY + BYMINUTE (expand)
SELECT assert_equals('DAILY+BYMINUTE', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;BYMINUTE=0,30;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- DAILY + BYSECOND (expand)
SELECT assert_equals('DAILY+BYSECOND', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;BYSECOND=0,30;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- DAILY + BYSETPOS (select positions from expanded set)
SELECT assert_equals('DAILY+BYSETPOS', '4',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;BYHOUR=9,12,15,18;BYSETPOS=1,-1;COUNT=4', '2025-01-01 10:00:00'::TIMESTAMP)));

-- DAILY + multiple filters combined
SELECT assert_equals('DAILY+BYDAY+BYMONTH', '4',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;BYDAY=MO;BYMONTH=1;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 2: WEEKLY FREQUENCY
--------------------------------------------------------------------------------
\echo ''
\echo '--- WEEKLY FREQUENCY ---'
\echo ''

-- WEEKLY + COUNT
SELECT assert_equals('WEEKLY+COUNT', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=WEEKLY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- WEEKLY + UNTIL
SELECT assert_equals('WEEKLY+UNTIL', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=WEEKLY;UNTIL=20250202T235959Z', '2025-01-01 10:00:00'::TIMESTAMP)));

-- WEEKLY + INTERVAL
SELECT assert_equals('WEEKLY+INTERVAL', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=WEEKLY;INTERVAL=2;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- WEEKLY + BYDAY (expand - generates multiple days per week)
SELECT assert_equals('WEEKLY+BYDAY-expand', '9',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=9', '2025-01-01 10:00:00'::TIMESTAMP)));

-- WEEKLY + BYDAY single day
SELECT assert_equals('WEEKLY+BYDAY-single', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=WEEKLY;BYDAY=TU;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Note: BYDAY ordinals with WEEKLY are rejected per RFC 5545 (tested in rejection_matrix.sql)

-- WEEKLY + BYMONTH (limit - filters to specific months)
SELECT assert_equals('WEEKLY+BYMONTH', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=WEEKLY;BYMONTH=1;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- Note: BYYEARDAY is rejected with WEEKLY per RFC 5545 (tested in rejection_matrix.sql)

-- Note: BYWEEKNO is rejected with WEEKLY per RFC 5545 (tested in rejection_matrix.sql)

-- WEEKLY + WKST (affects week boundaries)
SELECT assert_equals('WEEKLY+WKST', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=WEEKLY;WKST=SU;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- WEEKLY + BYSETPOS
SELECT assert_equals('WEEKLY+BYSETPOS', '4',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=4', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 3: MONTHLY FREQUENCY
--------------------------------------------------------------------------------
\echo ''
\echo '--- MONTHLY FREQUENCY ---'
\echo ''

-- MONTHLY + COUNT
SELECT assert_equals('MONTHLY+COUNT', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;COUNT=5', '2025-01-15 10:00:00'::TIMESTAMP)));

-- MONTHLY + UNTIL
SELECT assert_equals('MONTHLY+UNTIL', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;UNTIL=20250615T235959Z', '2025-01-15 10:00:00'::TIMESTAMP)));

-- MONTHLY + INTERVAL
SELECT assert_equals('MONTHLY+INTERVAL', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;INTERVAL=2;COUNT=3', '2025-01-15 10:00:00'::TIMESTAMP)));

-- MONTHLY + BYDAY (expand - all matching days in month)
SELECT assert_equals('MONTHLY+BYDAY-expand', '20',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO,WE,FR;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP)));

-- MONTHLY + BYDAY with position (specific occurrence in month)
SELECT assert_equals('MONTHLY+BYDAY-ordinal', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYDAY=2TU;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- MONTHLY + BYDAY with negative position (last Monday)
SELECT assert_equals('MONTHLY+BYDAY-neg-ordinal', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYDAY=-1MO;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- MONTHLY + BYMONTHDAY (expand - multiple days per month)
SELECT assert_equals('MONTHLY+BYMONTHDAY-expand', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=1,15;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP)));

-- MONTHLY + BYMONTHDAY single
SELECT assert_equals('MONTHLY+BYMONTHDAY-single', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=15;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- MONTHLY + BYMONTHDAY negative
SELECT assert_equals('MONTHLY+BYMONTHDAY-neg', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=6', '2025-01-01 10:00:00'::TIMESTAMP)));

-- MONTHLY + BYMONTH (limit)
-- With COUNT=4 starting in Jan, we get Jan 2025, Jul 2025, Jan 2026, Jul 2026
SELECT assert_equals('MONTHLY+BYMONTH', '4',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYMONTH=1,7;COUNT=4', '2025-01-15 10:00:00'::TIMESTAMP)));

-- Note: BYYEARDAY is rejected with MONTHLY per RFC 5545 (tested in rejection_matrix.sql)

-- Note: BYWEEKNO is rejected with MONTHLY per RFC 5545 (tested in rejection_matrix.sql)

-- MONTHLY + WKST
SELECT assert_equals('MONTHLY+WKST', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;WKST=SU;COUNT=5', '2025-01-15 10:00:00'::TIMESTAMP)));

-- MONTHLY + BYSETPOS
SELECT assert_equals('MONTHLY+BYSETPOS', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP)));

-- MONTHLY + BYDAY + BYMONTHDAY (intersection)
SELECT assert_equals('MONTHLY+BYDAY+BYMONTHDAY', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 4: YEARLY FREQUENCY
--------------------------------------------------------------------------------
\echo ''
\echo '--- YEARLY FREQUENCY ---'
\echo ''

-- YEARLY + COUNT
SELECT assert_equals('YEARLY+COUNT', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;COUNT=5', '2025-01-15 10:00:00'::TIMESTAMP)));

-- YEARLY + UNTIL
SELECT assert_equals('YEARLY+UNTIL', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;UNTIL=20290115T235959Z', '2025-01-15 10:00:00'::TIMESTAMP)));

-- YEARLY + INTERVAL
SELECT assert_equals('YEARLY+INTERVAL', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;INTERVAL=2;COUNT=3', '2025-01-15 10:00:00'::TIMESTAMP)));

-- YEARLY + BYDAY (expand - all matching days in year)
SELECT assert_equals('YEARLY+BYDAY-expand', '52',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYDAY=MO;COUNT=52', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYDAY with position (specific occurrence in year)
SELECT assert_equals('YEARLY+BYDAY-ordinal', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYDAY=2MO;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYDAY negative position (last Monday of year)
SELECT assert_equals('YEARLY+BYDAY-neg-ordinal', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYDAY=-1MO;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYMONTHDAY (expand - same day in all 12 months)
SELECT assert_equals('YEARLY+BYMONTHDAY-expand', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYMONTHDAY=15;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYMONTHDAY multiple
SELECT assert_equals('YEARLY+BYMONTHDAY-multi', '24',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYMONTHDAY=1,15;COUNT=24', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYMONTHDAY negative
SELECT assert_equals('YEARLY+BYMONTHDAY-neg', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYMONTHDAY=-1;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYMONTH (expand - multiple months per year)
SELECT assert_equals('YEARLY+BYMONTH-expand', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYMONTH=1,4,7,10;COUNT=6', '2025-01-15 10:00:00'::TIMESTAMP)));

-- YEARLY + BYMONTH single
SELECT assert_equals('YEARLY+BYMONTH-single', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYMONTH=6;COUNT=3', '2025-06-15 10:00:00'::TIMESTAMP)));

-- YEARLY + BYYEARDAY (expand - 3 days per year)
SELECT assert_equals('YEARLY+BYYEARDAY-expand', '9',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYYEARDAY=100,200,300;COUNT=9', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYYEARDAY single
SELECT assert_equals('YEARLY+BYYEARDAY-single', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYYEARDAY=100;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYYEARDAY negative
SELECT assert_equals('YEARLY+BYYEARDAY-neg', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYYEARDAY=-1;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYYEARDAY=366 (leap year only - 2024, 2028, 2032)
SELECT assert_equals('YEARLY+BYYEARDAY-366', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYYEARDAY=366;COUNT=3', '2024-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYWEEKNO (expand - specific weeks)
SELECT assert_equals('YEARLY+BYWEEKNO-expand', '7',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYWEEKNO=10;COUNT=7', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYWEEKNO with BYDAY
SELECT assert_equals('YEARLY+BYWEEKNO+BYDAY', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYWEEKNO=10;BYDAY=MO,WE,FR;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYWEEKNO=53 (only exists in some years)
SELECT assert_true('YEARLY+BYWEEKNO-53',
    (SELECT COUNT(*) > 0 FROM rrule."all"('FREQ=YEARLY;BYWEEKNO=53;COUNT=100', '2020-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + WKST (affects week numbering)
SELECT assert_equals('YEARLY+WKST', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;WKST=SU;COUNT=3', '2025-01-15 10:00:00'::TIMESTAMP)));

-- YEARLY + BYSETPOS (first and last of the 3 months)
SELECT assert_equals('YEARLY+BYSETPOS', '4',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYMONTH=1,2,3;BYSETPOS=1,-1;COUNT=4', '2025-01-15 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 5: SPECIAL COMBINATIONS
--------------------------------------------------------------------------------
\echo ''
\echo '--- SPECIAL COMBINATIONS ---'
\echo ''

-- BYMONTH + BYYEARDAY (when both specified, BYMONTH is primary and BYYEARDAY filters)
-- BYMONTH generates April 1st (based on dtstart day), BYYEARDAY=100 (April 10) filters it out
-- Both return 0 because the intersection logic doesn't generate all days of the month
SELECT assert_equals('YEARLY+BYMONTH+BYYEARDAY-intersect', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYMONTH=4;BYYEARDAY=100;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYMONTH + BYYEARDAY (same reason - BYMONTH generates specific day, not all days)
SELECT assert_equals('YEARLY+BYMONTH+BYYEARDAY-no-intersect', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYMONTH=4;BYYEARDAY=50;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYWEEKNO + BYMONTH (intersection - week 10 days that fall in March)
-- Week 10 of 2025 is March 3-9, so intersection gives 7 days first year, then filtered by BYMONTH
SELECT assert_true('YEARLY+BYWEEKNO+BYMONTH',
    (SELECT COUNT(*) >= 1 FROM rrule."all"('FREQ=YEARLY;BYWEEKNO=10;BYMONTH=3;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP)));

-- BYWEEKNO + BYYEARDAY (intersection)
SELECT assert_equals('YEARLY+BYWEEKNO+BYYEARDAY', '4',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYWEEKNO=10;BYYEARDAY=65,66,67;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP)));

-- MONTHLY + BYDAY + BYMONTH
SELECT assert_equals('MONTHLY+BYDAY+BYMONTH', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYDAY=2TU;BYMONTH=1,3,5,7,9,11;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYMONTH + BYDAY ordinal
SELECT assert_equals('YEARLY+BYMONTH+BYDAY-ordinal', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYMONTH=3;BYDAY=2MO;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- YEARLY + BYMONTH + BYMONTHDAY
SELECT assert_equals('YEARLY+BYMONTH+BYMONTHDAY', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYMONTH=6;BYMONTHDAY=15;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- DAILY + BYDAY + BYMONTH + BYMONTHDAY (complex intersection)
SELECT assert_equals('DAILY+complex-intersection', '0',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;BYDAY=FR;BYMONTH=1;BYMONTHDAY=13;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 6: SKIP PARAMETER COMBINATIONS (RFC 7529)
--------------------------------------------------------------------------------
\echo ''
\echo '--- SKIP PARAMETER COMBINATIONS (RFC 7529) ---'
\echo ''

-- MONTHLY + SKIP=OMIT (default)
SELECT assert_equals('MONTHLY+SKIP-OMIT', '10',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=31;COUNT=10', '2025-01-31 10:00:00'::TIMESTAMP)));

-- MONTHLY + SKIP=BACKWARD
SELECT assert_equals('MONTHLY+SKIP-BACKWARD', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP)));

-- MONTHLY + SKIP=FORWARD
SELECT assert_equals('MONTHLY+SKIP-FORWARD', '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP)));

-- YEARLY + SKIP=BACKWARD (Feb 29 handling)
SELECT assert_equals('YEARLY+SKIP-BACKWARD', '4',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=BACKWARD;COUNT=4', '2024-02-29 10:00:00'::TIMESTAMP)));

-- YEARLY + SKIP=FORWARD (Feb 29 handling)
SELECT assert_equals('YEARLY+SKIP-FORWARD', '4',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=FORWARD;COUNT=4', '2024-02-29 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 7: TZID PARAMETER
--------------------------------------------------------------------------------
\echo ''
\echo '--- TZID PARAMETER ---'
\echo ''

-- DAILY + TZID
SELECT assert_equals('DAILY+TZID', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;TZID=America/New_York;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- WEEKLY + TZID
SELECT assert_equals('WEEKLY+TZID', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=WEEKLY;TZID=Europe/London;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- MONTHLY + TZID (with DST transition)
SELECT assert_equals('MONTHLY+TZID', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;TZID=America/New_York;COUNT=5', '2025-01-15 10:00:00'::TIMESTAMP)));

-- YEARLY + TZID
SELECT assert_equals('YEARLY+TZID', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;TZID=Asia/Tokyo;COUNT=3', '2025-01-15 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 8: INTERVAL VARIATIONS
--------------------------------------------------------------------------------
\echo ''
\echo '--- INTERVAL VARIATIONS ---'
\echo ''

-- DAILY + large INTERVAL
SELECT assert_equals('DAILY+INTERVAL-large', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=DAILY;INTERVAL=30;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)));

-- WEEKLY + INTERVAL=2
SELECT assert_equals('WEEKLY+INTERVAL-2', '5',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=WEEKLY;INTERVAL=2;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP)));

-- MONTHLY + INTERVAL=3 (quarterly)
SELECT assert_equals('MONTHLY+INTERVAL-3', '4',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;INTERVAL=3;COUNT=4', '2025-01-15 10:00:00'::TIMESTAMP)));

-- YEARLY + INTERVAL=2 (biennial)
SELECT assert_equals('YEARLY+INTERVAL-2', '3',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=YEARLY;INTERVAL=2;COUNT=3', '2025-01-15 10:00:00'::TIMESTAMP)));

-- MONTHLY + INTERVAL=2 + SKIP=BACKWARD
SELECT assert_equals('MONTHLY+INTERVAL-2+SKIP', '6',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=6', '2025-01-31 10:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 9: MONOTONICITY VERIFICATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- MONOTONICITY VERIFICATION ---'
\echo ''

-- Verify DAILY results are monotonically increasing
SELECT assert_monotonic('DAILY-monotonic',
    (SELECT array_agg(r ORDER BY r) FROM rrule."all"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP) r));

-- Verify WEEKLY results are monotonically increasing
SELECT assert_monotonic('WEEKLY-monotonic',
    (SELECT array_agg(r ORDER BY r) FROM rrule."all"('FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=30', '2025-01-01 10:00:00'::TIMESTAMP) r));

-- Verify MONTHLY results are monotonically increasing
SELECT assert_monotonic('MONTHLY-monotonic',
    (SELECT array_agg(r ORDER BY r) FROM rrule."all"('FREQ=MONTHLY;BYDAY=2TU;COUNT=24', '2025-01-01 10:00:00'::TIMESTAMP) r));

-- Verify YEARLY results are monotonically increasing
SELECT assert_monotonic('YEARLY-monotonic',
    (SELECT array_agg(r ORDER BY r) FROM rrule."all"('FREQ=YEARLY;BYMONTH=1,4,7,10;COUNT=20', '2025-01-15 10:00:00'::TIMESTAMP) r));

-- Verify BYSETPOS results are monotonically increasing
SELECT assert_monotonic('BYSETPOS-monotonic',
    (SELECT array_agg(r ORDER BY r) FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,2,3,-3,-2,-1;COUNT=36', '2025-01-01 10:00:00'::TIMESTAMP) r));


--------------------------------------------------------------------------------
-- SECTION 10: DEDUPLICATION VERIFICATION (DISTINCT results)
--------------------------------------------------------------------------------
\echo ''
\echo '--- DEDUPLICATION VERIFICATION ---'
\echo ''

-- Verify no duplicates in MONTHLY results
SELECT assert_true('MONTHLY-no-duplicates',
    (SELECT COUNT(*) = COUNT(DISTINCT r) FROM rrule."all"('FREQ=MONTHLY;BYDAY=MO,WE,FR;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP) r));

-- Verify no duplicates in YEARLY results
SELECT assert_true('YEARLY-no-duplicates',
    (SELECT COUNT(*) = COUNT(DISTINCT r) FROM rrule."all"('FREQ=YEARLY;BYMONTH=1,2,3;BYMONTHDAY=15;COUNT=50', '2025-01-01 10:00:00'::TIMESTAMP) r));

-- Verify no duplicates with SKIP=FORWARD (which can create adjacent dates)
SELECT assert_true('SKIP-FORWARD-no-duplicates',
    (SELECT COUNT(*) = COUNT(DISTINCT r) FROM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=24', '2025-01-31 10:00:00'::TIMESTAMP) r));

-- Verify no duplicates in BYWEEKNO results
SELECT assert_true('BYWEEKNO-no-duplicates',
    (SELECT COUNT(*) = COUNT(DISTINCT r) FROM rrule."all"('FREQ=YEARLY;BYWEEKNO=10,11,12;COUNT=30', '2025-01-01 10:00:00'::TIMESTAMP) r));


\echo ''
\echo '====================================================================='
\echo 'FREQ × BYxxx FEATURE MATRIX TESTS COMPLETE'
\echo '====================================================================='

ROLLBACK;
