/**
 * Standard vs Sub-Day Installation Parity Tests
 *
 * Verifies that rrule.sql and rrule_subday.sql produce IDENTICAL results
 * for the 4 shared frequencies: DAILY, WEEKLY, MONTHLY, YEARLY.
 *
 * This test ONLY runs during sub-day installation mode. It:
 * 1. Captures results from current (subday) installation
 * 2. Temporarily reinstalls standard version
 * 3. Captures results from standard installation
 * 4. Compares results - must be byte-for-byte identical
 * 5. Restores subday installation
 *
 * This catches bugs where fixes are applied to one generator but not the other.
 *
 * Usage:
 *   Only run via: ./test.sh --subday or ./test.sh --both
 *   (Skipped automatically in standard-only mode)
 */

\set ON_ERROR_STOP on
\set ECHO all

SET timezone = 'UTC';

-- This test requires subday installation - detect and skip if standard
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'hourly_set'
                   AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'rrule')) THEN
        RAISE EXCEPTION 'SKIP: This test requires subday installation. Run with --subday or --both.';
    END IF;
END $$;

BEGIN;

\i tests/helpers.sql

\echo ''
\echo '====================================================================='
\echo 'STANDARD vs SUB-DAY INSTALLATION PARITY TESTS'
\echo '====================================================================='
\echo ''
\echo 'Verifying that both installations produce identical results'
\echo 'for DAILY, WEEKLY, MONTHLY, YEARLY frequencies.'
\echo ''

--------------------------------------------------------------------------------
-- SETUP: Create temp tables to store results from both installations
--------------------------------------------------------------------------------

CREATE TEMP TABLE parity_canaries (
    canary_id TEXT PRIMARY KEY,
    rrule_string TEXT NOT NULL,
    dtstart TIMESTAMP NOT NULL,
    description TEXT
);

CREATE TEMP TABLE subday_results (
    canary_id TEXT,
    occurrence TIMESTAMP,
    ordinal INT
);

CREATE TEMP TABLE standard_results (
    canary_id TEXT,
    occurrence TIMESTAMP,
    ordinal INT
);

--------------------------------------------------------------------------------
-- Define canary RRULEs that exercise all shared code paths
--------------------------------------------------------------------------------

INSERT INTO parity_canaries (canary_id, rrule_string, dtstart, description) VALUES
-- DAILY frequency variations
('DAILY-basic', 'FREQ=DAILY;COUNT=10', '2025-01-01 10:00:00', 'Basic daily'),
('DAILY-interval', 'FREQ=DAILY;INTERVAL=3;COUNT=10', '2025-01-01 10:00:00', 'Daily with interval'),
('DAILY-byday', 'FREQ=DAILY;BYDAY=MO,WE,FR;COUNT=10', '2025-01-01 10:00:00', 'Daily filtered by weekday'),
('DAILY-bymonth', 'FREQ=DAILY;BYMONTH=1,6;COUNT=20', '2025-01-01 10:00:00', 'Daily filtered by month'),
('DAILY-bymonthday', 'FREQ=DAILY;BYMONTHDAY=1,15;COUNT=10', '2025-01-01 10:00:00', 'Daily filtered by monthday'),
('DAILY-byhour', 'FREQ=DAILY;BYHOUR=9,12,17;COUNT=15', '2025-01-01 09:00:00', 'Daily with multiple hours'),
('DAILY-complex', 'FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;BYMONTH=1,2,3;COUNT=20', '2025-01-01 10:00:00', 'Complex daily'),

-- WEEKLY frequency variations
('WEEKLY-basic', 'FREQ=WEEKLY;COUNT=10', '2025-01-01 10:00:00', 'Basic weekly'),
('WEEKLY-interval', 'FREQ=WEEKLY;INTERVAL=2;COUNT=10', '2025-01-01 10:00:00', 'Biweekly'),
('WEEKLY-byday', 'FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=15', '2025-01-01 10:00:00', 'Weekly with multiple days'),
('WEEKLY-bymonth', 'FREQ=WEEKLY;BYMONTH=1,2,3;COUNT=15', '2025-01-01 10:00:00', 'Weekly filtered by month'),
('WEEKLY-wkst-su', 'FREQ=WEEKLY;WKST=SU;BYDAY=MO,FR;COUNT=10', '2025-01-01 10:00:00', 'Weekly with Sunday start'),
('WEEKLY-bysetpos', 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=20', '2025-01-01 10:00:00', 'Weekly with BYSETPOS'),

-- MONTHLY frequency variations
('MONTHLY-basic', 'FREQ=MONTHLY;COUNT=12', '2025-01-15 10:00:00', 'Basic monthly'),
('MONTHLY-interval', 'FREQ=MONTHLY;INTERVAL=3;COUNT=8', '2025-01-15 10:00:00', 'Quarterly'),
('MONTHLY-byday', 'FREQ=MONTHLY;BYDAY=2TU;COUNT=12', '2025-01-01 10:00:00', '2nd Tuesday'),
('MONTHLY-byday-neg', 'FREQ=MONTHLY;BYDAY=-1FR;COUNT=12', '2025-01-01 10:00:00', 'Last Friday'),
('MONTHLY-bymonthday', 'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=12', '2025-01-15 10:00:00', '15th of month'),
('MONTHLY-bymonthday-neg', 'FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=12', '2025-01-31 10:00:00', 'Last day of month'),
('MONTHLY-skip-forward', 'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=12', '2025-01-31 10:00:00', 'SKIP=FORWARD'),
('MONTHLY-skip-backward', 'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=12', '2025-01-31 10:00:00', 'SKIP=BACKWARD'),
('MONTHLY-bysetpos', 'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=24', '2025-01-01 10:00:00', 'First and last weekday'),
('MONTHLY-bymonth', 'FREQ=MONTHLY;BYMONTH=3,6,9,12;COUNT=8', '2025-01-15 10:00:00', 'Quarterly months only'),

-- YEARLY frequency variations
('YEARLY-basic', 'FREQ=YEARLY;COUNT=10', '2025-06-15 10:00:00', 'Basic yearly'),
('YEARLY-interval', 'FREQ=YEARLY;INTERVAL=2;COUNT=5', '2025-06-15 10:00:00', 'Biennial'),
('YEARLY-bymonth', 'FREQ=YEARLY;BYMONTH=1,6,12;COUNT=15', '2025-01-15 10:00:00', 'Multiple months per year'),
('YEARLY-byday', 'FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=10', '2025-01-01 10:00:00', 'US Thanksgiving'),
('YEARLY-bymonthday', 'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=14;COUNT=10', '2025-02-14 10:00:00', 'Valentines Day'),
('YEARLY-byyearday', 'FREQ=YEARLY;BYYEARDAY=100;COUNT=10', '2025-01-01 10:00:00', 'Day 100 of year'),
('YEARLY-byyearday-neg', 'FREQ=YEARLY;BYYEARDAY=-1;COUNT=10', '2025-12-31 10:00:00', 'Last day of year'),
('YEARLY-byweekno', 'FREQ=YEARLY;BYWEEKNO=10;BYDAY=MO;COUNT=10', '2025-01-01 10:00:00', 'Week 10 Monday'),
('YEARLY-byweekno-53', 'FREQ=YEARLY;BYWEEKNO=53;COUNT=5', '2020-01-01 10:00:00', 'Week 53 (sparse)'),
('YEARLY-leap-feb29', 'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;COUNT=5', '2020-02-29 10:00:00', 'Leap day'),
('YEARLY-skip-forward', 'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=FORWARD;COUNT=10', '2020-02-29 10:00:00', 'Leap day SKIP=FORWARD'),
('YEARLY-bysetpos', 'FREQ=YEARLY;BYMONTH=1;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=20', '2025-01-01 10:00:00', 'First and last weekday of Jan'),

-- Edge cases
('EDGE-dst-spring', 'FREQ=DAILY;COUNT=7', '2025-03-08 10:00:00', 'Across DST spring forward'),
('EDGE-dst-fall', 'FREQ=DAILY;COUNT=7', '2025-11-01 10:00:00', 'Across DST fall back'),
('EDGE-year-boundary', 'FREQ=DAILY;COUNT=10', '2024-12-28 10:00:00', 'Across year boundary'),
('EDGE-leap-year', 'FREQ=DAILY;COUNT=5', '2024-02-27 10:00:00', 'Across Feb 29'),
('EDGE-month-boundary', 'FREQ=DAILY;COUNT=5', '2025-01-29 10:00:00', 'Across month boundary');

--------------------------------------------------------------------------------
-- STEP 1: Capture results from SUBDAY installation (current)
--------------------------------------------------------------------------------

\echo ''
\echo '--- Capturing results from SUB-DAY installation ---'
\echo ''

INSERT INTO subday_results (canary_id, occurrence, ordinal)
SELECT c.canary_id, r.occurrence, row_number() OVER (PARTITION BY c.canary_id ORDER BY r.occurrence)::INT
FROM parity_canaries c
CROSS JOIN LATERAL (
    SELECT occurrence
    FROM rrule."all"(c.rrule_string, c.dtstart) AS occurrence
) r;

-- Record counts
DO $$
DECLARE
    total_canaries INT;
    total_occurrences INT;
BEGIN
    SELECT COUNT(DISTINCT canary_id), COUNT(*)
    INTO total_canaries, total_occurrences
    FROM subday_results;

    RAISE NOTICE 'Captured % occurrences across % canaries from SUB-DAY installation',
        total_occurrences, total_canaries;
END $$;

--------------------------------------------------------------------------------
-- STEP 2: Reinstall STANDARD version and capture results
--------------------------------------------------------------------------------

\echo ''
\echo '--- Reinstalling STANDARD version for comparison ---'
\echo ''

-- Drop and recreate with standard installation
DROP SCHEMA rrule CASCADE;
CREATE SCHEMA rrule;
\i src/rrule.sql

\echo ''
\echo '--- Capturing results from STANDARD installation ---'
\echo ''

INSERT INTO standard_results (canary_id, occurrence, ordinal)
SELECT c.canary_id, r.occurrence, row_number() OVER (PARTITION BY c.canary_id ORDER BY r.occurrence)::INT
FROM parity_canaries c
CROSS JOIN LATERAL (
    SELECT occurrence
    FROM rrule."all"(c.rrule_string, c.dtstart) AS occurrence
) r;

-- Record counts
DO $$
DECLARE
    total_canaries INT;
    total_occurrences INT;
BEGIN
    SELECT COUNT(DISTINCT canary_id), COUNT(*)
    INTO total_canaries, total_occurrences
    FROM standard_results;

    RAISE NOTICE 'Captured % occurrences across % canaries from STANDARD installation',
        total_occurrences, total_canaries;
END $$;

--------------------------------------------------------------------------------
-- STEP 3: Compare results
--------------------------------------------------------------------------------

\echo ''
\echo '--- Comparing STANDARD vs SUB-DAY results ---'
\echo ''

-- Check for count mismatches
DO $$
DECLARE
    mismatch RECORD;
    mismatch_count INT := 0;
BEGIN
    FOR mismatch IN
        SELECT
            COALESCE(s.canary_id, d.canary_id) AS canary_id,
            COALESCE(s.cnt, 0) AS standard_count,
            COALESCE(d.cnt, 0) AS subday_count
        FROM (SELECT canary_id, COUNT(*) AS cnt FROM standard_results GROUP BY canary_id) s
        FULL OUTER JOIN (SELECT canary_id, COUNT(*) AS cnt FROM subday_results GROUP BY canary_id) d
            ON s.canary_id = d.canary_id
        WHERE COALESCE(s.cnt, 0) IS DISTINCT FROM COALESCE(d.cnt, 0)
    LOOP
        RAISE WARNING 'COUNT MISMATCH [%]: standard=%, subday=%',
            mismatch.canary_id, mismatch.standard_count, mismatch.subday_count;
        mismatch_count := mismatch_count + 1;
    END LOOP;

    IF mismatch_count > 0 THEN
        RAISE EXCEPTION 'FAIL: % canaries have different occurrence counts between installations', mismatch_count;
    END IF;

    RAISE NOTICE 'PASS: All canaries have matching occurrence counts';
END $$;

-- Check for value mismatches
DO $$
DECLARE
    mismatch RECORD;
    mismatch_count INT := 0;
BEGIN
    FOR mismatch IN
        SELECT
            COALESCE(s.canary_id, d.canary_id) AS canary_id,
            COALESCE(s.ordinal, d.ordinal) AS ordinal,
            s.occurrence AS standard_occurrence,
            d.occurrence AS subday_occurrence
        FROM standard_results s
        FULL OUTER JOIN subday_results d
            ON s.canary_id = d.canary_id AND s.ordinal = d.ordinal
        WHERE s.occurrence IS DISTINCT FROM d.occurrence
        ORDER BY canary_id, ordinal
        LIMIT 10  -- Only show first 10 mismatches
    LOOP
        RAISE WARNING 'VALUE MISMATCH [% #%]: standard=%, subday=%',
            mismatch.canary_id, mismatch.ordinal,
            mismatch.standard_occurrence, mismatch.subday_occurrence;
        mismatch_count := mismatch_count + 1;
    END LOOP;

    IF mismatch_count > 0 THEN
        RAISE EXCEPTION 'FAIL: % occurrences differ between installations (showing first 10)', mismatch_count;
    END IF;

    RAISE NOTICE 'PASS: All occurrences are byte-for-byte identical';
END $$;

-- Summary
DO $$
DECLARE
    total_canaries INT;
    total_occurrences INT;
BEGIN
    SELECT COUNT(DISTINCT canary_id), COUNT(*)
    INTO total_canaries, total_occurrences
    FROM standard_results;

    RAISE NOTICE '';
    RAISE NOTICE '=== PARITY VERIFICATION COMPLETE ===';
    RAISE NOTICE 'Verified % occurrences across % canary RRULEs', total_occurrences, total_canaries;
    RAISE NOTICE 'STANDARD and SUB-DAY installations produce IDENTICAL results';
END $$;

--------------------------------------------------------------------------------
-- STEP 4: Restore SUB-DAY installation for remaining tests
--------------------------------------------------------------------------------

\echo ''
\echo '--- Restoring SUB-DAY installation ---'
\echo ''

DROP SCHEMA rrule CASCADE;
CREATE SCHEMA rrule;
\i src/rrule.sql
\i src/rrule_subday.sql

-- Verify restoration
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'hourly_set'
                   AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'rrule')) THEN
        RAISE EXCEPTION 'FAIL: Sub-day installation not properly restored';
    END IF;
    RAISE NOTICE 'SUB-DAY installation restored successfully';
END $$;

\echo ''
\echo '====================================================================='
\echo 'STANDARD vs SUB-DAY PARITY TESTS COMPLETE'
\echo '====================================================================='

ROLLBACK;
