/**
 * RFC 5545 Rejection Matrix Tests
 *
 * Systematic tests for all RFC 5545 prohibition rules.
 * Every combination that MUST be rejected is tested with expected error patterns.
 *
 * Coverage: All 🚫 cells in SPEC_COMPLIANCE.md
 *
 * Usage:
 *   psql -d your_database -f tests/matrix/test_rejection_matrix.sql
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
\echo 'RFC 5545 REJECTION MATRIX TESTS'
\echo '====================================================================='
\echo ''
\echo 'Testing all combinations that MUST be rejected per RFC 5545'
\echo ''

--------------------------------------------------------------------------------
-- SECTION 1: MISSING REQUIRED PARAMETERS
--------------------------------------------------------------------------------
\echo ''
\echo '--- MISSING REQUIRED PARAMETERS ---'
\echo ''

-- Missing FREQ (required)
SELECT assert_rrule_rejected('missing-FREQ',
    'COUNT=10;BYMONTHDAY=15',
    '%FREQ parameter is required%');

-- Missing FREQ with other valid parameters
SELECT assert_rrule_rejected('missing-FREQ-with-UNTIL',
    'UNTIL=20251231T235959Z;BYDAY=MO',
    '%FREQ parameter is required%');

-- Invalid FREQ value
SELECT assert_rrule_rejected('invalid-FREQ-value',
    'FREQ=BIWEEKLY;COUNT=5',
    '%Unsupported frequency%');


--------------------------------------------------------------------------------
-- SECTION 2: MUTUALLY EXCLUSIVE PARAMETERS
--------------------------------------------------------------------------------
\echo ''
\echo '--- MUTUALLY EXCLUSIVE PARAMETERS ---'
\echo ''

-- COUNT and UNTIL together
SELECT assert_rrule_rejected('COUNT-and-UNTIL',
    'FREQ=DAILY;COUNT=10;UNTIL=20251231T235959Z',
    '%COUNT and UNTIL are mutually exclusive%');

-- COUNT and UNTIL with other parameters
SELECT assert_rrule_rejected('COUNT-and-UNTIL-with-BYDAY',
    'FREQ=WEEKLY;COUNT=5;UNTIL=20251231T235959Z;BYDAY=MO',
    '%COUNT and UNTIL are mutually exclusive%');


--------------------------------------------------------------------------------
-- SECTION 3: BYWEEKNO RESTRICTIONS
--------------------------------------------------------------------------------
\echo ''
\echo '--- BYWEEKNO RESTRICTIONS ---'
\echo ''

-- BYWEEKNO only valid with YEARLY
SELECT assert_rrule_rejected('BYWEEKNO-with-DAILY',
    'FREQ=DAILY;BYWEEKNO=10;COUNT=5',
    '%BYWEEKNO can only be used with FREQ=YEARLY%');

SELECT assert_rrule_rejected('BYWEEKNO-with-WEEKLY',
    'FREQ=WEEKLY;BYWEEKNO=10;COUNT=5',
    '%BYWEEKNO can only be used with FREQ=YEARLY%');

SELECT assert_rrule_rejected('BYWEEKNO-with-MONTHLY',
    'FREQ=MONTHLY;BYWEEKNO=10;COUNT=5',
    '%BYWEEKNO can only be used with FREQ=YEARLY%');

-- BYDAY ordinal with BYWEEKNO in YEARLY (RFC 5545 prohibition)
SELECT assert_rrule_rejected('BYWEEKNO-BYDAY-ordinal-positive',
    'FREQ=YEARLY;BYWEEKNO=10;BYDAY=2MO;COUNT=3',
    '%BYDAY with ordinal%cannot be used when FREQ=YEARLY and BYWEEKNO%');

SELECT assert_rrule_rejected('BYWEEKNO-BYDAY-ordinal-negative',
    'FREQ=YEARLY;BYWEEKNO=10;BYDAY=-1FR;COUNT=3',
    '%BYDAY with ordinal%cannot be used when FREQ=YEARLY and BYWEEKNO%');


--------------------------------------------------------------------------------
-- SECTION 4: BYMONTHDAY RESTRICTIONS
--------------------------------------------------------------------------------
\echo ''
\echo '--- BYMONTHDAY RESTRICTIONS ---'
\echo ''

-- BYMONTHDAY cannot be used with WEEKLY (RFC 5545)
SELECT assert_rrule_rejected('BYMONTHDAY-with-WEEKLY',
    'FREQ=WEEKLY;BYMONTHDAY=15;COUNT=5',
    '%BYMONTHDAY cannot be used with FREQ=WEEKLY%');

SELECT assert_rrule_rejected('BYMONTHDAY-with-WEEKLY-multiple',
    'FREQ=WEEKLY;BYMONTHDAY=1,15;COUNT=5',
    '%BYMONTHDAY cannot be used with FREQ=WEEKLY%');

SELECT assert_rrule_rejected('BYMONTHDAY-with-WEEKLY-negative',
    'FREQ=WEEKLY;BYMONTHDAY=-1;COUNT=5',
    '%BYMONTHDAY cannot be used with FREQ=WEEKLY%');


--------------------------------------------------------------------------------
-- SECTION 5: TIME FILTER SUPPORT (BYHOUR/BYMINUTE/BYSECOND)
-- Note: These combinations are now SUPPORTED per RFC 5545 time expansion.
-- See test_time_expansion.sql for comprehensive tests.
--------------------------------------------------------------------------------
\echo ''
\echo '--- TIME FILTER SUPPORT (now accepted) ---'
\echo ''

-- BYHOUR with WEEKLY/MONTHLY/YEARLY - now supported (time expansion)
SELECT assert_true('BYHOUR-with-WEEKLY-accepted',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=WEEKLY;BYHOUR=9;COUNT=5', '2025-01-06 09:00:00'::TIMESTAMP)));

SELECT assert_true('BYHOUR-with-MONTHLY-accepted',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=MONTHLY;BYHOUR=9;COUNT=5', '2025-01-01 09:00:00'::TIMESTAMP)));

SELECT assert_true('BYHOUR-with-YEARLY-accepted',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=YEARLY;BYHOUR=9;COUNT=5', '2025-01-01 09:00:00'::TIMESTAMP)));

-- BYMINUTE with WEEKLY/MONTHLY/YEARLY - now supported
SELECT assert_true('BYMINUTE-with-WEEKLY-accepted',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=WEEKLY;BYMINUTE=30;COUNT=5', '2025-01-06 09:30:00'::TIMESTAMP)));

SELECT assert_true('BYMINUTE-with-MONTHLY-accepted',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=MONTHLY;BYMINUTE=30;COUNT=5', '2025-01-01 09:30:00'::TIMESTAMP)));

SELECT assert_true('BYMINUTE-with-YEARLY-accepted',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=YEARLY;BYMINUTE=30;COUNT=5', '2025-01-01 09:30:00'::TIMESTAMP)));

-- BYSECOND with WEEKLY/MONTHLY/YEARLY - now supported
SELECT assert_true('BYSECOND-with-WEEKLY-accepted',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=WEEKLY;BYSECOND=0;COUNT=5', '2025-01-06 09:00:00'::TIMESTAMP)));

SELECT assert_true('BYSECOND-with-MONTHLY-accepted',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=MONTHLY;BYSECOND=0;COUNT=5', '2025-01-01 09:00:00'::TIMESTAMP)));

SELECT assert_true('BYSECOND-with-YEARLY-accepted',
    (SELECT COUNT(*) = 5 FROM rrule."all"('FREQ=YEARLY;BYSECOND=0;COUNT=5', '2025-01-01 09:00:00'::TIMESTAMP)));


--------------------------------------------------------------------------------
-- SECTION 6: INTERVAL VALIDATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- INTERVAL VALIDATION ---'
\echo ''

-- INTERVAL must be positive
SELECT assert_rrule_rejected('INTERVAL-zero',
    'FREQ=DAILY;INTERVAL=0;COUNT=5',
    '%INTERVAL must be a positive integer%');

SELECT assert_rrule_rejected('INTERVAL-negative',
    'FREQ=DAILY;INTERVAL=-1;COUNT=5',
    '%INTERVAL must be a positive integer%');


--------------------------------------------------------------------------------
-- SECTION 7: UNTIL FORMAT VALIDATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- UNTIL FORMAT VALIDATION ---'
\echo ''

-- UNTIL must include time component
SELECT assert_rrule_rejected('UNTIL-date-only',
    'FREQ=DAILY;UNTIL=20251231',
    '%date-only value%');

-- UNTIL must be in UTC (with Z suffix)
SELECT assert_rrule_rejected('UNTIL-no-Z',
    'FREQ=DAILY;UNTIL=20251231T235959',
    '%must be specified in UTC%');


--------------------------------------------------------------------------------
-- SECTION 8: SKIP PARAMETER VALIDATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- SKIP PARAMETER VALIDATION ---'
\echo ''

-- Invalid SKIP value
SELECT assert_rrule_rejected('SKIP-invalid',
    'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=IGNORE;COUNT=5',
    '%Invalid SKIP value%');


--------------------------------------------------------------------------------
-- SECTION 9: SUB-DAY FREQUENCY RESTRICTIONS (Standard Install Only)
--------------------------------------------------------------------------------
\echo ''
\echo '--- SUB-DAY FREQUENCY RESTRICTIONS ---'
\echo ''

-- These tests only run when subday frequencies are NOT installed
-- (hourly_set function doesn't exist in rrule schema)
DO $$
DECLARE
    result TEXT;
BEGIN
    -- Check if subday is installed by looking for hourly_set function
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'hourly_set'
               AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'rrule')) THEN
        -- Subday is installed, skip these tests
        RAISE NOTICE 'SKIP: Sub-day frequencies are enabled, skipping rejection tests';
        RETURN;
    END IF;

    -- HOURLY disabled in standard install
    SELECT assert_rrule_rejected('HOURLY-disabled',
        'FREQ=HOURLY;COUNT=5',
        '%Sub-day frequencies%disabled%') INTO result;
    IF result != 'PASS' THEN
        RAISE EXCEPTION '%', result;
    END IF;

    -- MINUTELY disabled in standard install
    SELECT assert_rrule_rejected('MINUTELY-disabled',
        'FREQ=MINUTELY;COUNT=5',
        '%Sub-day frequencies%disabled%') INTO result;
    IF result != 'PASS' THEN
        RAISE EXCEPTION '%', result;
    END IF;

    -- SECONDLY disabled in standard install
    SELECT assert_rrule_rejected('SECONDLY-disabled',
        'FREQ=SECONDLY;COUNT=5',
        '%Sub-day frequencies%disabled%') INTO result;
    IF result != 'PASS' THEN
        RAISE EXCEPTION '%', result;
    END IF;

    RAISE NOTICE 'PASS: All sub-day frequency rejection tests passed';
END $$;


--------------------------------------------------------------------------------
-- SECTION 10: BYDAY ORDINAL RESTRICTIONS
--------------------------------------------------------------------------------
\echo ''
\echo '--- BYDAY ORDINAL RESTRICTIONS ---'
\echo ''

-- BYDAY ordinal out of range (>53 for weeks, >5 for months)
-- Note: These may or may not be rejected depending on implementation
-- Testing that ordinals work within valid ranges

-- Valid: 5th Monday of month
SELECT assert_rrule_accepted('BYDAY-ordinal-5',
    'FREQ=MONTHLY;BYDAY=5MO;COUNT=12',
    12);

-- Valid: -5th Monday of month
SELECT assert_rrule_accepted('BYDAY-ordinal-neg5',
    'FREQ=MONTHLY;BYDAY=-5MO;COUNT=12',
    12);


--------------------------------------------------------------------------------
-- SECTION 11: BYMONTHDAY RANGE VALIDATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- BYMONTHDAY RANGE VALIDATION ---'
\echo ''

-- BYMONTHDAY out of range (>31 or <-31)
SELECT assert_rrule_rejected('BYMONTHDAY-32',
    'FREQ=MONTHLY;BYMONTHDAY=32;COUNT=5',
    '%BYMONTHDAY%out of valid range%');

SELECT assert_rrule_rejected('BYMONTHDAY-neg32',
    'FREQ=MONTHLY;BYMONTHDAY=-32;COUNT=5',
    '%BYMONTHDAY%out of valid range%');

-- BYMONTHDAY=0 is invalid
SELECT assert_rrule_rejected('BYMONTHDAY-zero',
    'FREQ=MONTHLY;BYMONTHDAY=0;COUNT=5',
    '%BYMONTHDAY=0%not valid%');


--------------------------------------------------------------------------------
-- SECTION 12: BYYEARDAY RANGE VALIDATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- BYYEARDAY RANGE VALIDATION ---'
\echo ''

-- BYYEARDAY out of range (>366 or <-366)
SELECT assert_rrule_rejected('BYYEARDAY-367',
    'FREQ=YEARLY;BYYEARDAY=367;COUNT=5',
    '%BYYEARDAY%out of valid range%');

SELECT assert_rrule_rejected('BYYEARDAY-neg367',
    'FREQ=YEARLY;BYYEARDAY=-367;COUNT=5',
    '%BYYEARDAY%out of valid range%');

-- BYYEARDAY=0 is invalid
SELECT assert_rrule_rejected('BYYEARDAY-zero',
    'FREQ=YEARLY;BYYEARDAY=0;COUNT=5',
    '%BYYEARDAY=0%not valid%');


--------------------------------------------------------------------------------
-- SECTION 13: BYWEEKNO RANGE VALIDATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- BYWEEKNO RANGE VALIDATION ---'
\echo ''

-- BYWEEKNO out of range (>53 or <-53)
SELECT assert_rrule_rejected('BYWEEKNO-54',
    'FREQ=YEARLY;BYWEEKNO=54;COUNT=5',
    '%BYWEEKNO%out of valid range%');

SELECT assert_rrule_rejected('BYWEEKNO-neg54',
    'FREQ=YEARLY;BYWEEKNO=-54;COUNT=5',
    '%BYWEEKNO%out of valid range%');

-- BYWEEKNO=0 is invalid
SELECT assert_rrule_rejected('BYWEEKNO-zero',
    'FREQ=YEARLY;BYWEEKNO=0;COUNT=5',
    '%BYWEEKNO=0%not valid%');


--------------------------------------------------------------------------------
-- SECTION 14: BYMONTH RANGE VALIDATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- BYMONTH RANGE VALIDATION ---'
\echo ''

-- BYMONTH out of range (>12 or <1)
SELECT assert_rrule_rejected('BYMONTH-13',
    'FREQ=YEARLY;BYMONTH=13;COUNT=5',
    '%BYMONTH%out of valid range%');

SELECT assert_rrule_rejected('BYMONTH-zero',
    'FREQ=YEARLY;BYMONTH=0;COUNT=5',
    '%BYMONTH=0%out of valid range%');


--------------------------------------------------------------------------------
-- SECTION 15: BYHOUR RANGE VALIDATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- BYHOUR RANGE VALIDATION ---'
\echo ''

-- BYHOUR out of range (>23 or <0)
SELECT assert_rrule_rejected('BYHOUR-24',
    'FREQ=DAILY;BYHOUR=24;COUNT=5',
    '%BYHOUR%out of valid range%');

SELECT assert_rrule_rejected('BYHOUR-negative',
    'FREQ=DAILY;BYHOUR=-1;COUNT=5',
    '%BYHOUR%out of valid range%');


--------------------------------------------------------------------------------
-- SECTION 16: BYMINUTE RANGE VALIDATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- BYMINUTE RANGE VALIDATION ---'
\echo ''

-- BYMINUTE out of range (>59 or <0)
SELECT assert_rrule_rejected('BYMINUTE-60',
    'FREQ=DAILY;BYMINUTE=60;COUNT=5',
    '%BYMINUTE%out of valid range%');

SELECT assert_rrule_rejected('BYMINUTE-negative',
    'FREQ=DAILY;BYMINUTE=-1;COUNT=5',
    '%BYMINUTE%out of valid range%');


--------------------------------------------------------------------------------
-- SECTION 17: BYSECOND RANGE VALIDATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- BYSECOND RANGE VALIDATION ---'
\echo ''

-- BYSECOND out of range
-- Note: RFC allows 60 for leap seconds, so BYSECOND=60 may be accepted
-- Testing BYSECOND=61 which should definitely be rejected
SELECT assert_rrule_rejected('BYSECOND-61',
    'FREQ=DAILY;BYSECOND=61;COUNT=5',
    '%BYSECOND%out of valid range%');

SELECT assert_rrule_rejected('BYSECOND-negative',
    'FREQ=DAILY;BYSECOND=-1;COUNT=5',
    '%BYSECOND%out of valid range%');


--------------------------------------------------------------------------------
-- SECTION 18: WKST VALIDATION
--------------------------------------------------------------------------------
\echo ''
\echo '--- WKST VALIDATION ---'
\echo ''

-- Invalid WKST value
SELECT assert_rrule_rejected('WKST-invalid',
    'FREQ=WEEKLY;WKST=XX;COUNT=5',
    '%Invalid WKST%');


--------------------------------------------------------------------------------
-- SECTION 19: INVALID BYDAY FORMAT
--------------------------------------------------------------------------------
\echo ''
\echo '--- INVALID BYDAY FORMAT ---'
\echo ''

-- Invalid day abbreviation
SELECT assert_rrule_rejected('BYDAY-invalid-day',
    'FREQ=WEEKLY;BYDAY=XY;COUNT=5',
    '%BYDAY%could not be parsed%');


\echo ''
\echo '====================================================================='
\echo 'RFC 5545 REJECTION MATRIX TESTS COMPLETE'
\echo '====================================================================='

ROLLBACK;
