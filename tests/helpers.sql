/**
 * Shared Test Helper Functions
 *
 * This file provides common assertion functions used across test suites.
 * Include it after BEGIN; in each test file:
 *
 *   BEGIN;
 *   \i tests/helpers.sql
 *
 * Functions:
 * - assert_occurrences_equal(test_name, expected, actual) — compares TIMESTAMP arrays element-by-element
 * - assert_equals(test_name, expected, actual) — compares TEXT values
 * - assert_true(test_name, condition) — asserts a BOOLEAN condition
 */

-- Compare expected vs actual TIMESTAMP arrays element-by-element
CREATE OR REPLACE FUNCTION assert_occurrences_equal(
    test_name TEXT,
    expected TIMESTAMP[],
    actual TIMESTAMP[]
)
RETURNS TEXT AS $$
DECLARE
    i INT;
BEGIN
    -- NOTE: array_agg() returns NULL when no rows match (not an empty array).
    -- Tests expecting empty results use ARRAY[]::TIMESTAMP[], which has NULL array_length.
    -- IS DISTINCT FROM and COALESCE handle both NULL and empty arrays: NULL/empty both → length 0/NULL.
    -- This allows tests comparing NULL actual (no results) vs empty expected to pass correctly.
    IF array_length(expected, 1) IS DISTINCT FROM array_length(actual, 1) THEN
        RAISE EXCEPTION 'FAIL [%]: Expected % occurrences, got %',
            test_name,
            COALESCE(array_length(expected, 1), 0),
            COALESCE(array_length(actual, 1), 0);
    END IF;

    FOR i IN 1..COALESCE(array_length(expected, 1), 0) LOOP
        IF expected[i] IS DISTINCT FROM actual[i] THEN
            RAISE EXCEPTION 'FAIL [%]: Occurrence #% differs. Expected %, got %',
                test_name, i, expected[i], actual[i];
        END IF;
    END LOOP;

    RETURN 'PASS [' || test_name || ']';
END;
$$ LANGUAGE plpgsql;

-- Compare two TEXT values for equality
CREATE OR REPLACE FUNCTION assert_equals(
    test_name TEXT,
    expected TEXT,
    actual TEXT
) RETURNS TEXT AS $$
BEGIN
    IF expected IS NOT DISTINCT FROM actual THEN
        RETURN 'PASS';
    ELSE
        RAISE EXCEPTION 'FAIL [%]: Expected: %, Got: %',
            test_name,
            COALESCE(expected, 'NULL'),
            COALESCE(actual, 'NULL');
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Assert a boolean condition is true
CREATE OR REPLACE FUNCTION assert_true(
    test_name TEXT,
    condition BOOLEAN
) RETURNS TEXT AS $$
BEGIN
    IF condition THEN
        RETURN 'PASS';
    ELSE
        RAISE EXCEPTION 'FAIL [%]: Condition was false', test_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Assert a boolean condition is false
CREATE OR REPLACE FUNCTION assert_false(
    test_name TEXT,
    condition BOOLEAN
) RETURNS TEXT AS $$
BEGIN
    IF NOT condition THEN
        RETURN 'PASS';
    ELSE
        RAISE EXCEPTION 'FAIL [%]: Condition was true (expected false)', test_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Verify results are monotonically increasing (no duplicate, all ascending)
CREATE OR REPLACE FUNCTION assert_monotonic(
    test_name TEXT,
    results TIMESTAMP[]
) RETURNS TEXT AS $$
DECLARE
    i INT;
BEGIN
    IF results IS NULL OR array_length(results, 1) IS NULL THEN
        RETURN 'PASS';  -- Empty/NULL is trivially monotonic
    END IF;

    FOR i IN 2..array_length(results, 1) LOOP
        IF results[i] <= results[i-1] THEN
            RAISE EXCEPTION 'FAIL [%]: Results not monotonic at position %. % <= %',
                test_name, i, results[i], results[i-1];
        END IF;
    END LOOP;

    RETURN 'PASS';
END;
$$ LANGUAGE plpgsql;

-- Verify TIMESTAMP API and TIMESTAMPTZ API produce identical results (wall-clock time)
-- This checks parity between the two generator paths
CREATE OR REPLACE FUNCTION assert_generator_parity(
    test_name TEXT,
    rrule_string TEXT,
    dtstart TIMESTAMP,
    timezone_name TEXT DEFAULT 'UTC'
) RETURNS TEXT AS $$
DECLARE
    ts_results TIMESTAMP[];
    tz_results TIMESTAMP[];
    i INT;
BEGIN
    -- Get results from TIMESTAMP API (with TZID in RRULE)
    ts_results := (
        SELECT array_agg(r ORDER BY r)
        FROM rrule."all"(rrule_string, dtstart) r
    );

    -- Get results from TIMESTAMPTZ API (with explicit timezone parameter)
    tz_results := (
        SELECT array_agg(r::TIMESTAMP ORDER BY r)
        FROM rrule."all"(
            regexp_replace(rrule_string, ';?TZID=[^;]+', '', 'g'),
            (dtstart AT TIME ZONE timezone_name),
            timezone_name
        ) r
    );

    -- Compare lengths
    IF COALESCE(array_length(ts_results, 1), 0) IS DISTINCT FROM
       COALESCE(array_length(tz_results, 1), 0) THEN
        RAISE EXCEPTION 'FAIL [%]: Generator parity mismatch. TIMESTAMP API: % results, TIMESTAMPTZ API: % results',
            test_name,
            COALESCE(array_length(ts_results, 1), 0),
            COALESCE(array_length(tz_results, 1), 0);
    END IF;

    -- Compare element by element
    FOR i IN 1..COALESCE(array_length(ts_results, 1), 0) LOOP
        IF ts_results[i] IS DISTINCT FROM tz_results[i] THEN
            RAISE EXCEPTION 'FAIL [%]: Generator parity mismatch at position %. TIMESTAMP API: %, TIMESTAMPTZ API: %',
                test_name, i, ts_results[i], tz_results[i];
        END IF;
    END LOOP;

    RETURN 'PASS';
END;
$$ LANGUAGE plpgsql;

-- Verify an RRULE is rejected with expected error pattern
-- (Note: This is also defined in test_validation.sql for local use;
--  this version is for use in other test files)
CREATE OR REPLACE FUNCTION assert_rrule_rejected(
    test_name TEXT,
    invalid_rrule TEXT,
    expected_error_pattern TEXT
) RETURNS TEXT AS $$
DECLARE
    result TIMESTAMP[];
BEGIN
    BEGIN
        result := (SELECT array_agg(occurrence ORDER BY occurrence)
                   FROM rrule."all"(invalid_rrule, '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence);
        RAISE EXCEPTION 'FAIL [%]: RRULE was accepted when it should have been rejected: %',
            test_name, invalid_rrule;
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM LIKE expected_error_pattern THEN
                RETURN 'PASS';
            ELSE
                RAISE EXCEPTION 'FAIL [%]: Wrong error message. Expected pattern: %, Got: %',
                    test_name, expected_error_pattern, SQLERRM;
            END IF;
    END;
END;
$$ LANGUAGE plpgsql;

-- Verify an RRULE is accepted and produces expected count
CREATE OR REPLACE FUNCTION assert_rrule_accepted(
    test_name TEXT,
    valid_rrule TEXT,
    expected_count INT
) RETURNS TEXT AS $$
DECLARE
    result TIMESTAMP[];
    actual_count INT;
BEGIN
    result := (SELECT array_agg(occurrence ORDER BY occurrence)
               FROM rrule."all"(valid_rrule, '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence);
    actual_count := COALESCE(array_length(result, 1), 0);

    IF actual_count IS DISTINCT FROM expected_count THEN
        RAISE EXCEPTION 'FAIL [%]: Expected % occurrences, got %',
            test_name, expected_count, actual_count;
    END IF;

    RETURN 'PASS';
END;
$$ LANGUAGE plpgsql;
