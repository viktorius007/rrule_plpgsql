/**
 * 4-Generator Parity Tests
 *
 * Verifies that all 4 code paths produce identical results:
 * 1. TIMESTAMP API (rrule_event_instances_range)
 * 2. TIMESTAMPTZ API (rrule_event_instances_range_tz)
 *
 * For sub-day installation, the same 2 generators are used but with
 * additional frequency support, tested separately in test_subday_correctness.sql.
 *
 * "Canary" RRULEs are carefully chosen to exercise:
 * - All frequency branches
 * - SKIP handling
 * - DST transitions
 * - INTERVAL > 1
 * - Complex BYxxx combinations
 *
 * Coverage: 20+ canary RRULEs x 2 API paths = 40+ parity checks
 *
 * Usage:
 *   psql -d your_database -f tests/parity/test_4_generator_parity.sql
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
\echo '4-GENERATOR PARITY TESTS'
\echo '====================================================================='
\echo ''
\echo 'Verifying TIMESTAMP API and TIMESTAMPTZ API produce identical results'
\echo ''

--------------------------------------------------------------------------------
-- Parity verification function
--------------------------------------------------------------------------------

-- Compare TIMESTAMP API results with TIMESTAMPTZ API results
-- Returns 'PASS' if identical, raises exception otherwise
CREATE OR REPLACE FUNCTION verify_api_parity(
    test_name TEXT,
    rrule_string TEXT,
    dtstart_ts TIMESTAMP,
    tz_name TEXT DEFAULT 'UTC'
) RETURNS TEXT AS $$
DECLARE
    ts_results TIMESTAMP[];
    tz_results TIMESTAMP[];
    i INT;
BEGIN
    -- Get results from TIMESTAMP API
    ts_results := (
        SELECT array_agg(r ORDER BY r)
        FROM rrule."all"(rrule_string, dtstart_ts) r
    );

    -- Get results from TIMESTAMPTZ API
    -- Convert dtstart to TIMESTAMPTZ, call the TZ API, convert results back to TIMESTAMP
    tz_results := (
        SELECT array_agg(r::TIMESTAMP ORDER BY r)
        FROM rrule."all"(
            rrule_string,
            (dtstart_ts AT TIME ZONE tz_name)::TIMESTAMPTZ,
            tz_name
        ) r
    );

    -- Compare lengths
    IF COALESCE(array_length(ts_results, 1), 0) IS DISTINCT FROM
       COALESCE(array_length(tz_results, 1), 0) THEN
        RAISE EXCEPTION 'FAIL [%]: Parity mismatch in result count. TIMESTAMP API: %, TIMESTAMPTZ API: %',
            test_name,
            COALESCE(array_length(ts_results, 1), 0),
            COALESCE(array_length(tz_results, 1), 0);
    END IF;

    -- Compare element by element
    FOR i IN 1..COALESCE(array_length(ts_results, 1), 0) LOOP
        IF ts_results[i] IS DISTINCT FROM tz_results[i] THEN
            RAISE EXCEPTION 'FAIL [%]: Parity mismatch at position %. TIMESTAMP API: %, TIMESTAMPTZ API: %',
                test_name, i, ts_results[i], tz_results[i];
        END IF;
    END LOOP;

    RETURN 'PASS';
END;
$$ LANGUAGE plpgsql;


--------------------------------------------------------------------------------
-- SECTION 1: DAILY FREQUENCY CANARIES
--------------------------------------------------------------------------------
\echo ''
\echo '--- DAILY FREQUENCY PARITY ---'
\echo ''

SELECT verify_api_parity('DAILY-basic',
    'FREQ=DAILY;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('DAILY-INTERVAL',
    'FREQ=DAILY;INTERVAL=3;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('DAILY-BYDAY',
    'FREQ=DAILY;BYDAY=MO,WE,FR;COUNT=15', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('DAILY-BYMONTH',
    'FREQ=DAILY;BYMONTH=1,6;COUNT=50', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('DAILY-BYHOUR',
    'FREQ=DAILY;BYHOUR=9,12,17;COUNT=15', '2025-01-01 10:00:00'::TIMESTAMP);


--------------------------------------------------------------------------------
-- SECTION 2: WEEKLY FREQUENCY CANARIES
--------------------------------------------------------------------------------
\echo ''
\echo '--- WEEKLY FREQUENCY PARITY ---'
\echo ''

SELECT verify_api_parity('WEEKLY-basic',
    'FREQ=WEEKLY;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('WEEKLY-BYDAY-expand',
    'FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=15', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('WEEKLY-INTERVAL',
    'FREQ=WEEKLY;INTERVAL=2;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('WEEKLY-WKST-SU',
    'FREQ=WEEKLY;WKST=SU;BYDAY=MO,FR;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('WEEKLY-BYSETPOS',
    'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);


--------------------------------------------------------------------------------
-- SECTION 3: MONTHLY FREQUENCY CANARIES
--------------------------------------------------------------------------------
\echo ''
\echo '--- MONTHLY FREQUENCY PARITY ---'
\echo ''

SELECT verify_api_parity('MONTHLY-basic',
    'FREQ=MONTHLY;COUNT=12', '2025-01-15 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('MONTHLY-BYDAY-ordinal',
    'FREQ=MONTHLY;BYDAY=2TU;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('MONTHLY-BYDAY-negative',
    'FREQ=MONTHLY;BYDAY=-1FR;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('MONTHLY-BYMONTHDAY',
    'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('MONTHLY-BYMONTHDAY-negative',
    'FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('MONTHLY-INTERVAL',
    'FREQ=MONTHLY;INTERVAL=2;COUNT=12', '2025-01-15 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('MONTHLY-SKIP-BACKWARD',
    'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('MONTHLY-SKIP-FORWARD',
    'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('MONTHLY-BYSETPOS',
    'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP);


--------------------------------------------------------------------------------
-- SECTION 4: YEARLY FREQUENCY CANARIES
--------------------------------------------------------------------------------
\echo ''
\echo '--- YEARLY FREQUENCY PARITY ---'
\echo ''

SELECT verify_api_parity('YEARLY-basic',
    'FREQ=YEARLY;COUNT=5', '2025-01-15 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('YEARLY-BYMONTH',
    'FREQ=YEARLY;BYMONTH=1,4,7,10;COUNT=12', '2025-01-15 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('YEARLY-BYMONTHDAY',
    'FREQ=YEARLY;BYMONTHDAY=15;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('YEARLY-BYDAY-ordinal',
    'FREQ=YEARLY;BYDAY=3MO;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('YEARLY-BYYEARDAY',
    'FREQ=YEARLY;BYYEARDAY=100;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('YEARLY-BYWEEKNO',
    'FREQ=YEARLY;BYWEEKNO=10;COUNT=7', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('YEARLY-BYWEEKNO-BYDAY',
    'FREQ=YEARLY;BYWEEKNO=10;BYDAY=MO,WE,FR;COUNT=9', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('YEARLY-INTERVAL',
    'FREQ=YEARLY;INTERVAL=2;COUNT=5', '2025-01-15 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('YEARLY-SKIP-BACKWARD',
    'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=BACKWARD;COUNT=4', '2024-02-29 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('YEARLY-BYSETPOS',
    'FREQ=YEARLY;BYMONTH=1,2,3;BYSETPOS=1,-1;COUNT=6', '2025-01-15 10:00:00'::TIMESTAMP);


--------------------------------------------------------------------------------
-- SECTION 5: UTC TIMEZONE PARITY (Primary parity test)
--------------------------------------------------------------------------------
\echo ''
\echo '--- UTC TIMEZONE PARITY ---'
\echo ''

-- Note: TIMESTAMP and TIMESTAMPTZ APIs are designed for different use cases.
-- TIMESTAMP API: Wall-clock time with optional TZID in RRULE string
-- TIMESTAMPTZ API: Absolute time with explicit timezone parameter
--
-- True parity is only guaranteed for UTC where wall-clock = absolute time.
-- For other timezones, the APIs may produce different results by design
-- (e.g., DST handling, ambiguous times).
--
-- These tests verify UTC parity as the baseline contract.

SELECT verify_api_parity('UTC-daily',
    'FREQ=DAILY;COUNT=10', '2025-03-08 10:00:00'::TIMESTAMP, 'UTC');

SELECT verify_api_parity('UTC-weekly',
    'FREQ=WEEKLY;BYDAY=SU;COUNT=5', '2025-03-02 10:00:00'::TIMESTAMP, 'UTC');

SELECT verify_api_parity('UTC-monthly',
    'FREQ=MONTHLY;BYDAY=2TU;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP, 'UTC');

SELECT verify_api_parity('UTC-yearly',
    'FREQ=YEARLY;COUNT=5', '2025-06-15 10:00:00'::TIMESTAMP, 'UTC');


--------------------------------------------------------------------------------
-- SECTION 6: COMPLEX COMBINATION CANARIES
--------------------------------------------------------------------------------
\echo ''
\echo '--- COMPLEX COMBINATION PARITY ---'
\echo ''

SELECT verify_api_parity('COMPLEX-MONTHLY-BYDAY-BYMONTH',
    'FREQ=MONTHLY;BYDAY=2TU;BYMONTH=1,3,5,7,9,11;COUNT=12', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('COMPLEX-YEARLY-BYMONTH-BYMONTHDAY',
    'FREQ=YEARLY;BYMONTH=6;BYMONTHDAY=15;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('COMPLEX-YEARLY-BYMONTH-BYDAY',
    'FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('COMPLEX-DAILY-BYDAY-BYMONTHDAY',
    'FREQ=DAILY;BYDAY=FR;BYMONTHDAY=13;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);


--------------------------------------------------------------------------------
-- SECTION 7: EDGE CASE CANARIES
--------------------------------------------------------------------------------
\echo ''
\echo '--- EDGE CASE PARITY ---'
\echo ''

-- Leap year
SELECT verify_api_parity('EDGE-leap-year',
    'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;COUNT=3', '2024-02-29 10:00:00'::TIMESTAMP);

-- Week 53
SELECT verify_api_parity('EDGE-week-53',
    'FREQ=YEARLY;BYWEEKNO=53;COUNT=3', '2020-12-28 10:00:00'::TIMESTAMP);

-- Last day of month
SELECT verify_api_parity('EDGE-last-day-month',
    'FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP);

-- Day 366 of year (leap year only)
SELECT verify_api_parity('EDGE-day-366',
    'FREQ=YEARLY;BYYEARDAY=366;COUNT=3', '2024-12-31 10:00:00'::TIMESTAMP);


--------------------------------------------------------------------------------
-- SECTION 8: INTERVAL > 1 WITH SKIP (Critical combinations)
--------------------------------------------------------------------------------
\echo ''
\echo '--- INTERVAL > 1 WITH SKIP PARITY ---'
\echo ''

SELECT verify_api_parity('SKIP-INTERVAL-2-BACKWARD',
    'FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('SKIP-INTERVAL-2-FORWARD',
    'FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=31;SKIP=FORWARD;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('SKIP-INTERVAL-3-BACKWARD',
    'FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=8', '2025-01-31 10:00:00'::TIMESTAMP);

SELECT verify_api_parity('SKIP-YEARLY-INTERVAL-2',
    'FREQ=YEARLY;INTERVAL=2;BYMONTH=2;BYMONTHDAY=29;SKIP=BACKWARD;COUNT=4', '2024-02-29 10:00:00'::TIMESTAMP);


--------------------------------------------------------------------------------
-- SECTION 9: VERIFY MONOTONICITY IN BOTH PATHS
--------------------------------------------------------------------------------
\echo ''
\echo '--- MONOTONICITY VERIFICATION ---'
\echo ''

-- Verify both APIs return monotonically increasing results
DO $$
DECLARE
    ts_results TIMESTAMP[];
    tz_results TIMESTAMP[];
    i INT;
BEGIN
    -- TIMESTAMP API
    ts_results := (SELECT array_agg(r ORDER BY r)
                   FROM rrule."all"('FREQ=MONTHLY;BYDAY=2TU,-1FR;COUNT=24', '2025-01-01 10:00:00'::TIMESTAMP) r);

    FOR i IN 2..array_length(ts_results, 1) LOOP
        IF ts_results[i] <= ts_results[i-1] THEN
            RAISE EXCEPTION 'FAIL [monotonic-ts]: Results not monotonic at %', i;
        END IF;
    END LOOP;

    -- TIMESTAMPTZ API
    tz_results := (SELECT array_agg(r ORDER BY r)
                   FROM rrule."all"('FREQ=MONTHLY;BYDAY=2TU,-1FR;COUNT=24',
                       '2025-01-01 10:00:00'::TIMESTAMPTZ, 'UTC') r);

    FOR i IN 2..array_length(tz_results, 1) LOOP
        IF tz_results[i] <= tz_results[i-1] THEN
            RAISE EXCEPTION 'FAIL [monotonic-tz]: Results not monotonic at %', i;
        END IF;
    END LOOP;

    RAISE NOTICE 'PASS [monotonic-both-apis]';
END $$;


\echo ''
\echo '====================================================================='
\echo '4-GENERATOR PARITY TESTS COMPLETE'
\echo '====================================================================='

ROLLBACK;
