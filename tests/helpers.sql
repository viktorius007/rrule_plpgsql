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
