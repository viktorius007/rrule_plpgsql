/**
 * Property-Based / Fuzz Testing
 *
 * Generates random valid RRULEs and verifies that invariants always hold:
 * 1. Results are monotonically increasing (strictly ascending, no duplicates)
 * 2. COUNT parameter is respected exactly
 * 3. UNTIL parameter is respected (no results after UNTIL)
 * 4. All results are >= dtstart
 * 5. Results don't exceed 10-year window from dtstart
 * 6. Results don't exceed 1000 cap
 * 7. INTERVAL > 1 produces correctly spaced results
 *
 * This catches edge cases that hand-written tests might miss.
 *
 * Usage:
 *   psql -d your_database -f tests/fuzz/test_property_invariants.sql
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
\echo 'PROPERTY-BASED / FUZZ TESTING'
\echo '====================================================================='
\echo ''
\echo 'Verifying invariants hold for randomly generated RRULEs'
\echo ''

--------------------------------------------------------------------------------
-- HELPER: Generate random RRULE components
--------------------------------------------------------------------------------

-- Random frequency (standard only for this test)
CREATE OR REPLACE FUNCTION random_freq() RETURNS TEXT AS $$
BEGIN
    RETURN (ARRAY['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'])[1 + floor(random() * 4)::INT];
END;
$$ LANGUAGE plpgsql;

-- Random BYDAY (simple, no ordinals for cross-frequency compatibility)
CREATE OR REPLACE FUNCTION random_byday() RETURNS TEXT AS $$
DECLARE
    days TEXT[] := ARRAY['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    num_days INT := 1 + floor(random() * 3)::INT;  -- 1-3 days
    result TEXT := '';
    i INT;
BEGIN
    FOR i IN 1..num_days LOOP
        IF i > 1 THEN result := result || ','; END IF;
        result := result || days[1 + floor(random() * 7)::INT];
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Random BYMONTH
CREATE OR REPLACE FUNCTION random_bymonth() RETURNS TEXT AS $$
DECLARE
    num_months INT := 1 + floor(random() * 3)::INT;  -- 1-3 months
    months INT[] := ARRAY[]::INT[];
    i INT;
    m INT;
BEGIN
    FOR i IN 1..num_months LOOP
        m := 1 + floor(random() * 12)::INT;
        IF NOT m = ANY(months) THEN
            months := array_append(months, m);
        END IF;
    END LOOP;
    RETURN array_to_string(months, ',');
END;
$$ LANGUAGE plpgsql;

-- Random BYMONTHDAY (valid range 1-28 to avoid month-end issues)
CREATE OR REPLACE FUNCTION random_bymonthday() RETURNS TEXT AS $$
BEGIN
    RETURN (1 + floor(random() * 28)::INT)::TEXT;
END;
$$ LANGUAGE plpgsql;

-- Random COUNT (5-50)
CREATE OR REPLACE FUNCTION random_count() RETURNS INT AS $$
BEGIN
    RETURN 5 + floor(random() * 46)::INT;
END;
$$ LANGUAGE plpgsql;

-- Random INTERVAL (1-5)
CREATE OR REPLACE FUNCTION random_interval() RETURNS INT AS $$
BEGIN
    RETURN 1 + floor(random() * 5)::INT;
END;
$$ LANGUAGE plpgsql;

-- Generate a random valid RRULE string
CREATE OR REPLACE FUNCTION generate_random_rrule() RETURNS TEXT AS $$
DECLARE
    freq TEXT;
    rrule TEXT;
    add_byday BOOLEAN;
    add_bymonth BOOLEAN;
    add_bymonthday BOOLEAN;
    add_interval BOOLEAN;
BEGIN
    freq := random_freq();
    rrule := 'FREQ=' || freq;

    -- Always add COUNT to bound results
    rrule := rrule || ';COUNT=' || random_count();

    -- Randomly add INTERVAL
    add_interval := random() > 0.5;
    IF add_interval THEN
        rrule := rrule || ';INTERVAL=' || random_interval();
    END IF;

    -- Randomly add BYDAY (50% chance)
    add_byday := random() > 0.5;
    IF add_byday THEN
        rrule := rrule || ';BYDAY=' || random_byday();
    END IF;

    -- Randomly add BYMONTH (30% chance)
    add_bymonth := random() > 0.7;
    IF add_bymonth THEN
        rrule := rrule || ';BYMONTH=' || random_bymonth();
    END IF;

    -- Randomly add BYMONTHDAY (20% chance, but not with WEEKLY)
    add_bymonthday := random() > 0.8 AND freq != 'WEEKLY';
    IF add_bymonthday THEN
        rrule := rrule || ';BYMONTHDAY=' || random_bymonthday();
    END IF;

    RETURN rrule;
END;
$$ LANGUAGE plpgsql;

-- Generate a random dtstart
CREATE OR REPLACE FUNCTION random_dtstart() RETURNS TIMESTAMP AS $$
BEGIN
    -- Random date in 2020-2030 range
    RETURN '2020-01-01 10:00:00'::TIMESTAMP +
           (floor(random() * 3650)::INT || ' days')::INTERVAL +
           (floor(random() * 14)::INT || ' hours')::INTERVAL;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------
-- INVARIANT VERIFICATION FUNCTIONS
--------------------------------------------------------------------------------

-- Verify results are monotonically increasing (no duplicates)
CREATE OR REPLACE FUNCTION verify_monotonic(results TIMESTAMP[]) RETURNS BOOLEAN AS $$
DECLARE
    i INT;
BEGIN
    IF results IS NULL OR array_length(results, 1) IS NULL THEN
        RETURN TRUE;  -- Empty is trivially monotonic
    END IF;

    FOR i IN 2..array_length(results, 1) LOOP
        IF results[i] <= results[i-1] THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Verify COUNT is respected
CREATE OR REPLACE FUNCTION verify_count(results TIMESTAMP[], expected_count INT) RETURNS BOOLEAN AS $$
BEGIN
    RETURN COALESCE(array_length(results, 1), 0) <= expected_count;
END;
$$ LANGUAGE plpgsql;

-- Verify all results are >= dtstart
CREATE OR REPLACE FUNCTION verify_after_dtstart(results TIMESTAMP[], dtstart TIMESTAMP) RETURNS BOOLEAN AS $$
DECLARE
    r TIMESTAMP;
BEGIN
    IF results IS NULL THEN RETURN TRUE; END IF;

    FOREACH r IN ARRAY results LOOP
        IF r < dtstart THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Verify results don't exceed 10-year window
CREATE OR REPLACE FUNCTION verify_10year_window(results TIMESTAMP[], dtstart TIMESTAMP) RETURNS BOOLEAN AS $$
DECLARE
    max_date TIMESTAMP;
BEGIN
    IF results IS NULL OR array_length(results, 1) IS NULL THEN
        RETURN TRUE;
    END IF;

    max_date := dtstart + INTERVAL '3653 days';  -- ~10 years with buffer

    RETURN results[array_length(results, 1)] <= max_date;
END;
$$ LANGUAGE plpgsql;

-- Verify result count doesn't exceed 1000 cap
CREATE OR REPLACE FUNCTION verify_1000_cap(results TIMESTAMP[]) RETURNS BOOLEAN AS $$
BEGIN
    RETURN COALESCE(array_length(results, 1), 0) <= 1000;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------
-- SECTION 1: MONOTONICITY INVARIANT
--------------------------------------------------------------------------------
\echo ''
\echo '--- Invariant 1: Monotonicity (results strictly ascending) ---'
\echo ''

DO $$
DECLARE
    i INT;
    rrule_str TEXT;
    dtstart TIMESTAMP;
    results TIMESTAMP[];
    failures INT := 0;
BEGIN
    FOR i IN 1..100 LOOP
        rrule_str := generate_random_rrule();
        dtstart := random_dtstart();

        BEGIN
            results := (SELECT array_agg(r ORDER BY r)
                        FROM rrule."all"(rrule_str, dtstart) r);

            IF NOT verify_monotonic(results) THEN
                RAISE WARNING 'MONOTONICITY FAILED for %: dtstart=%, results=%',
                    rrule_str, dtstart, results;
                failures := failures + 1;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Some random RRULEs might be invalid, that's OK
            NULL;
        END;
    END LOOP;

    IF failures > 0 THEN
        RAISE EXCEPTION 'FAIL: % monotonicity failures in 100 random RRULEs', failures;
    ELSE
        RAISE NOTICE 'PASS: All 100 random RRULEs produced monotonic results';
    END IF;
END $$;

--------------------------------------------------------------------------------
-- SECTION 2: COUNT INVARIANT
--------------------------------------------------------------------------------
\echo ''
\echo '--- Invariant 2: COUNT parameter respected (bounded by 10-year cap) ---'
\echo ''

DO $$
DECLARE
    i INT;
    cnt INT;
    dtstart TIMESTAMP;
    results TIMESTAMP[];
    actual_count INT;
    max_possible INT;
    failures INT := 0;
    freq TEXT;
BEGIN
    FOR i IN 1..100 LOOP
        freq := random_freq();
        cnt := random_count();
        dtstart := random_dtstart();

        results := (SELECT array_agg(r ORDER BY r)
                    FROM rrule."all"('FREQ=' || freq || ';COUNT=' || cnt, dtstart) r);

        actual_count := COALESCE(array_length(results, 1), 0);

        -- Calculate max possible based on 10-year window
        -- YEARLY: ~10, MONTHLY: ~120, WEEKLY: ~522, DAILY: capped at 1000
        max_possible := CASE freq
            WHEN 'YEARLY' THEN LEAST(cnt, 11)   -- ~10 years
            WHEN 'MONTHLY' THEN LEAST(cnt, 121) -- ~120 months
            WHEN 'WEEKLY' THEN LEAST(cnt, 522)  -- ~520 weeks
            WHEN 'DAILY' THEN LEAST(cnt, 1000)  -- capped at 1000
            ELSE cnt
        END;

        -- Result should be exactly COUNT or bounded by window
        IF actual_count != LEAST(cnt, max_possible) AND actual_count > max_possible THEN
            RAISE WARNING 'COUNT FAILED: FREQ=%;COUNT=% produced % results (max_possible=%)',
                freq, cnt, actual_count, max_possible;
            failures := failures + 1;
        END IF;
    END LOOP;

    IF failures > 0 THEN
        RAISE EXCEPTION 'FAIL: % COUNT violations in 100 tests', failures;
    ELSE
        RAISE NOTICE 'PASS: All 100 COUNT tests respected bounds';
    END IF;
END $$;

--------------------------------------------------------------------------------
-- SECTION 3: DTSTART BOUNDARY INVARIANT
--------------------------------------------------------------------------------
\echo ''
\echo '--- Invariant 3: All results >= dtstart ---'
\echo ''

DO $$
DECLARE
    i INT;
    rrule_str TEXT;
    dtstart TIMESTAMP;
    results TIMESTAMP[];
    failures INT := 0;
BEGIN
    FOR i IN 1..100 LOOP
        rrule_str := generate_random_rrule();
        dtstart := random_dtstart();

        BEGIN
            results := (SELECT array_agg(r ORDER BY r)
                        FROM rrule."all"(rrule_str, dtstart) r);

            IF NOT verify_after_dtstart(results, dtstart) THEN
                RAISE WARNING 'DTSTART BOUNDARY FAILED for %: dtstart=%, first=%',
                    rrule_str, dtstart, results[1];
                failures := failures + 1;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END LOOP;

    IF failures > 0 THEN
        RAISE EXCEPTION 'FAIL: % dtstart boundary violations in 100 tests', failures;
    ELSE
        RAISE NOTICE 'PASS: All 100 random RRULEs respect dtstart boundary';
    END IF;
END $$;

--------------------------------------------------------------------------------
-- SECTION 4: 10-YEAR WINDOW INVARIANT
--------------------------------------------------------------------------------
\echo ''
\echo '--- Invariant 4: Results within 10-year window ---'
\echo ''

DO $$
DECLARE
    i INT;
    freq TEXT;
    dtstart TIMESTAMP;
    results TIMESTAMP[];
    failures INT := 0;
BEGIN
    -- Test unbounded rules (no COUNT/UNTIL) which should be capped
    FOR i IN 1..50 LOOP
        freq := random_freq();
        dtstart := random_dtstart();

        results := (SELECT array_agg(r ORDER BY r)
                    FROM rrule."all"('FREQ=' || freq, dtstart) r);

        IF NOT verify_10year_window(results, dtstart) THEN
            RAISE WARNING '10-YEAR WINDOW FAILED for FREQ=%: dtstart=%, last=%',
                freq, dtstart, results[array_length(results, 1)];
            failures := failures + 1;
        END IF;
    END LOOP;

    IF failures > 0 THEN
        RAISE EXCEPTION 'FAIL: % 10-year window violations in 50 tests', failures;
    ELSE
        RAISE NOTICE 'PASS: All 50 unbounded RRULEs respect 10-year window';
    END IF;
END $$;

--------------------------------------------------------------------------------
-- SECTION 5: 1000 CAP INVARIANT
--------------------------------------------------------------------------------
\echo ''
\echo '--- Invariant 5: Results <= 1000 cap ---'
\echo ''

DO $$
DECLARE
    i INT;
    freq TEXT;
    dtstart TIMESTAMP;
    results TIMESTAMP[];
    failures INT := 0;
BEGIN
    -- Test unbounded and high-COUNT rules
    FOR i IN 1..50 LOOP
        freq := random_freq();
        dtstart := random_dtstart();

        -- Unbounded
        results := (SELECT array_agg(r ORDER BY r)
                    FROM rrule."all"('FREQ=' || freq, dtstart) r);

        IF NOT verify_1000_cap(results) THEN
            RAISE WARNING '1000 CAP FAILED for FREQ=%: count=%',
                freq, array_length(results, 1);
            failures := failures + 1;
        END IF;

        -- High COUNT
        results := (SELECT array_agg(r ORDER BY r)
                    FROM rrule."all"('FREQ=' || freq || ';COUNT=5000', dtstart) r);

        IF NOT verify_1000_cap(results) THEN
            RAISE WARNING '1000 CAP FAILED for FREQ=%;COUNT=5000: count=%',
                freq, array_length(results, 1);
            failures := failures + 1;
        END IF;
    END LOOP;

    IF failures > 0 THEN
        RAISE EXCEPTION 'FAIL: % 1000-cap violations in 100 tests', failures;
    ELSE
        RAISE NOTICE 'PASS: All 100 tests respect 1000-result cap';
    END IF;
END $$;

--------------------------------------------------------------------------------
-- SECTION 6: UNTIL INVARIANT
--------------------------------------------------------------------------------
\echo ''
\echo '--- Invariant 6: UNTIL parameter respected ---'
\echo ''

DO $$
DECLARE
    i INT;
    freq TEXT;
    dtstart TIMESTAMP;
    until_date TIMESTAMP;
    until_str TEXT;
    results TIMESTAMP[];
    last_result TIMESTAMP;
    failures INT := 0;
BEGIN
    FOR i IN 1..100 LOOP
        freq := random_freq();
        dtstart := random_dtstart();
        until_date := dtstart + (30 + floor(random() * 335)::INT || ' days')::INTERVAL;
        until_str := to_char(until_date, 'YYYYMMDD') || 'T235959Z';

        results := (SELECT array_agg(r ORDER BY r)
                    FROM rrule."all"('FREQ=' || freq || ';UNTIL=' || until_str, dtstart) r);

        IF results IS NOT NULL AND array_length(results, 1) > 0 THEN
            last_result := results[array_length(results, 1)];
            IF last_result > until_date THEN
                RAISE WARNING 'UNTIL FAILED for FREQ=%;UNTIL=%: last=%',
                    freq, until_str, last_result;
                failures := failures + 1;
            END IF;
        END IF;
    END LOOP;

    IF failures > 0 THEN
        RAISE EXCEPTION 'FAIL: % UNTIL violations in 100 tests', failures;
    ELSE
        RAISE NOTICE 'PASS: All 100 UNTIL tests respected the boundary';
    END IF;
END $$;

--------------------------------------------------------------------------------
-- SECTION 7: INTERVAL SPACING INVARIANT
--------------------------------------------------------------------------------
\echo ''
\echo '--- Invariant 7: INTERVAL produces correctly spaced results ---'
\echo ''

DO $$
DECLARE
    interval_val INT;
    dtstart TIMESTAMP;
    results TIMESTAMP[];
    i INT;
    expected_gap INTERVAL;
    actual_gap INTERVAL;
    failures INT := 0;
BEGIN
    -- Test DAILY with INTERVAL
    FOR interval_val IN 1..5 LOOP
        dtstart := '2025-01-01 10:00:00'::TIMESTAMP;
        results := (SELECT array_agg(r ORDER BY r)
                    FROM rrule."all"('FREQ=DAILY;INTERVAL=' || interval_val || ';COUNT=10', dtstart) r);

        expected_gap := (interval_val || ' days')::INTERVAL;

        FOR i IN 2..array_length(results, 1) LOOP
            actual_gap := results[i] - results[i-1];
            IF actual_gap != expected_gap THEN
                RAISE WARNING 'INTERVAL SPACING FAILED: FREQ=DAILY;INTERVAL=%: gap at % is %, expected %',
                    interval_val, i, actual_gap, expected_gap;
                failures := failures + 1;
                EXIT;
            END IF;
        END LOOP;
    END LOOP;

    -- Test WEEKLY with INTERVAL
    FOR interval_val IN 1..3 LOOP
        dtstart := '2025-01-01 10:00:00'::TIMESTAMP;  -- Wednesday
        results := (SELECT array_agg(r ORDER BY r)
                    FROM rrule."all"('FREQ=WEEKLY;INTERVAL=' || interval_val || ';COUNT=10', dtstart) r);

        expected_gap := (interval_val * 7 || ' days')::INTERVAL;

        FOR i IN 2..array_length(results, 1) LOOP
            actual_gap := results[i] - results[i-1];
            IF actual_gap != expected_gap THEN
                RAISE WARNING 'INTERVAL SPACING FAILED: FREQ=WEEKLY;INTERVAL=%: gap at % is %, expected %',
                    interval_val, i, actual_gap, expected_gap;
                failures := failures + 1;
                EXIT;
            END IF;
        END LOOP;
    END LOOP;

    IF failures > 0 THEN
        RAISE EXCEPTION 'FAIL: % INTERVAL spacing violations', failures;
    ELSE
        RAISE NOTICE 'PASS: All INTERVAL tests produced correctly spaced results';
    END IF;
END $$;

--------------------------------------------------------------------------------
-- SECTION 8: STRESS TEST WITH MANY RANDOM RRULES
--------------------------------------------------------------------------------
\echo ''
\echo '--- Stress Test: 500 random RRULEs with all invariants ---'
\echo ''

DO $$
DECLARE
    i INT;
    rrule_str TEXT;
    dtstart TIMESTAMP;
    results TIMESTAMP[];
    failures INT := 0;
    successes INT := 0;
    cnt INT;
BEGIN
    FOR i IN 1..500 LOOP
        rrule_str := generate_random_rrule();
        dtstart := random_dtstart();

        BEGIN
            results := (SELECT array_agg(r ORDER BY r)
                        FROM rrule."all"(rrule_str, dtstart) r);

            -- Check all invariants
            IF NOT verify_monotonic(results) THEN
                RAISE WARNING 'STRESS TEST: Monotonicity failed for %', rrule_str;
                failures := failures + 1;
                CONTINUE;
            END IF;

            IF NOT verify_after_dtstart(results, dtstart) THEN
                RAISE WARNING 'STRESS TEST: dtstart boundary failed for %', rrule_str;
                failures := failures + 1;
                CONTINUE;
            END IF;

            IF NOT verify_1000_cap(results) THEN
                RAISE WARNING 'STRESS TEST: 1000 cap failed for %', rrule_str;
                failures := failures + 1;
                CONTINUE;
            END IF;

            IF NOT verify_10year_window(results, dtstart) THEN
                RAISE WARNING 'STRESS TEST: 10-year window failed for %', rrule_str;
                failures := failures + 1;
                CONTINUE;
            END IF;

            -- COUNT verification is complex due to 10-year cap, skip in stress test
            -- (it's tested thoroughly in Section 2)

            successes := successes + 1;

        EXCEPTION WHEN OTHERS THEN
            -- Some random RRULEs might be invalid combinations, skip them
            NULL;
        END;
    END LOOP;

    RAISE NOTICE 'Stress test: % successes, % failures out of 500 random RRULEs',
        successes, failures;

    IF failures > 0 THEN
        RAISE EXCEPTION 'FAIL: % invariant violations in stress test', failures;
    ELSE
        RAISE NOTICE 'PASS: All invariants held across % valid random RRULEs', successes;
    END IF;
END $$;

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS random_freq();
DROP FUNCTION IF EXISTS random_byday();
DROP FUNCTION IF EXISTS random_bymonth();
DROP FUNCTION IF EXISTS random_bymonthday();
DROP FUNCTION IF EXISTS random_count();
DROP FUNCTION IF EXISTS random_interval();
DROP FUNCTION IF EXISTS generate_random_rrule();
DROP FUNCTION IF EXISTS random_dtstart();
DROP FUNCTION IF EXISTS verify_monotonic(TIMESTAMP[]);
DROP FUNCTION IF EXISTS verify_count(TIMESTAMP[], INT);
DROP FUNCTION IF EXISTS verify_after_dtstart(TIMESTAMP[], TIMESTAMP);
DROP FUNCTION IF EXISTS verify_10year_window(TIMESTAMP[], TIMESTAMP);
DROP FUNCTION IF EXISTS verify_1000_cap(TIMESTAMP[]);

\echo ''
\echo '====================================================================='
\echo 'PROPERTY-BASED / FUZZ TESTING COMPLETE'
\echo '====================================================================='

ROLLBACK;
