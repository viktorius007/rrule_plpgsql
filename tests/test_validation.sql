/**
 * RFC 5545 Constraint Validation Tests
 *
 * Tests all 18 RFC 5545 MUST/MUST NOT constraint validations implemented
 * in parse_rrule_parts() to ensure invalid RRULEs are properly rejected
 * with clear, descriptive error messages.
 *
 * Usage:
 *   psql -d your_database -f tests/test_validation.sql
 *
 * Expected output: All tests pass with PASS markers
 */

\set ON_ERROR_STOP on
\set ECHO all

-- Test database setup
-- Ensure we're testing in UTC timezone for consistency
SET timezone = 'UTC';

-- Install RRULE functions (allow override via -v rrule_install=...)
\if :{?rrule_install}
\i :rrule_install
\else
DROP SCHEMA IF EXISTS rrule CASCADE;
CREATE SCHEMA IF NOT EXISTS rrule;
\i src/rrule.sql
\endif

-- Ensure tests do not rely on search_path
SET search_path = public;

BEGIN;

\i tests/helpers.sql

-- Helper function to test that invalid RRULEs are rejected
CREATE OR REPLACE FUNCTION assert_rrule_rejected(
    test_name TEXT,
    invalid_rrule TEXT,
    expected_error_pattern TEXT
)
RETURNS TEXT AS $$
DECLARE
    result TIMESTAMP[];
BEGIN
    -- Try to use the invalid RRULE
    BEGIN
        result := (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(invalid_rrule, '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence);
        -- If we get here, the RRULE was NOT rejected (test failed)
        RAISE EXCEPTION 'FAIL [%]: RRULE was accepted when it should have been rejected: %',
            test_name, invalid_rrule;
    EXCEPTION
        WHEN raise_exception THEN
            -- Check if error message matches expected pattern
            IF SQLERRM LIKE expected_error_pattern THEN
                RETURN 'PASS [' || test_name || ']';
            ELSE
                RAISE EXCEPTION 'FAIL [%]: Wrong error message. Expected pattern: %, Got: %',
                    test_name, expected_error_pattern, SQLERRM;
            END IF;
    END;
END;
$$ LANGUAGE plpgsql;

-- Helper function to test that valid RRULEs are accepted
CREATE OR REPLACE FUNCTION assert_rrule_accepted(
    test_name TEXT,
    valid_rrule TEXT,
    expected_count INT
)
RETURNS TEXT AS $$
DECLARE
    result TIMESTAMP[];
    actual_count INT;
BEGIN
    result := (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(valid_rrule, '2025-01-01 10:00:00'::TIMESTAMP) AS occurrence);
    actual_count := array_length(result, 1);

    IF actual_count IS DISTINCT FROM expected_count THEN
        RAISE EXCEPTION 'FAIL [%]: Expected % occurrences, got %',
            test_name, expected_count, actual_count;
    END IF;

    RETURN 'PASS [' || test_name || ']';
END;
$$ LANGUAGE plpgsql;

-- Test results tracking
CREATE TEMP TABLE validation_test_results (
    test_number SERIAL PRIMARY KEY,
    test_category TEXT,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 1: Critical MUST/MUST NOT Constraint Violations'
\echo '====================================================================='

-- Test 1.1: FREQ is REQUIRED
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('FREQ Required', 'Missing FREQ (should be rejected)',
    assert_rrule_rejected(
        'Missing FREQ',
        'COUNT=10;BYMONTHDAY=15',
        '%FREQ parameter is required%'
    )
);

-- Test 1.2: Valid FREQ accepted
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('FREQ Required', 'Valid FREQ=DAILY (should be accepted)',
    assert_rrule_accepted(
        'Valid FREQ',
        'FREQ=DAILY;COUNT=5',
        5
    )
);

-- Test 1.3: COUNT and UNTIL mutually exclusive
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('COUNT+UNTIL Mutual Exclusion', 'COUNT and UNTIL together (should be rejected)',
    assert_rrule_rejected(
        'COUNT + UNTIL together',
        'FREQ=DAILY;COUNT=10;UNTIL=20251231T235959Z',
        '%COUNT and UNTIL are mutually exclusive%'
    )
);

-- Test 1.4: COUNT alone is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('COUNT+UNTIL Mutual Exclusion', 'COUNT alone (should be accepted)',
    assert_rrule_accepted(
        'COUNT alone',
        'FREQ=DAILY;COUNT=5',
        5
    )
);

-- Test 1.5: UNTIL alone is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('COUNT+UNTIL Mutual Exclusion', 'UNTIL alone (should be accepted)',
    assert_rrule_accepted(
        'UNTIL alone',
        'FREQ=DAILY;UNTIL=20250105T235959Z',
        5
    )
);

-- Test 1.5a: UNTIL date-only is invalid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('COUNT+UNTIL Mutual Exclusion', 'UNTIL date-only (should be rejected)',
    assert_rrule_rejected(
        'UNTIL date-only',
        'FREQ=DAILY;UNTIL=20250105',
        '%date-only value%'
    )
);

-- Test 1.5b: UNTIL without Z is invalid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('COUNT+UNTIL Mutual Exclusion', 'UNTIL without Z (should be rejected)',
    assert_rrule_rejected(
        'UNTIL without Z',
        'FREQ=DAILY;UNTIL=20250105T235959',
        '%must be specified in UTC%'
    )
);

-- Test 1.5c: INTERVAL must be positive
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('INTERVAL Validation', 'INTERVAL=0 (should be rejected)',
    assert_rrule_rejected(
        'INTERVAL=0 invalid',
        'FREQ=DAILY;INTERVAL=0;COUNT=3',
        '%INTERVAL must be a positive integer%'
    )
);

-- Test 1.6: BYWEEKNO only with YEARLY
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Only With YEARLY', 'BYWEEKNO with MONTHLY (should be rejected)',
    assert_rrule_rejected(
        'BYWEEKNO with MONTHLY',
        'FREQ=MONTHLY;BYWEEKNO=10;COUNT=3',
        '%BYWEEKNO can only be used with FREQ=YEARLY%'
    )
);

-- Test 1.7: BYWEEKNO with WEEKLY should fail
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Only With YEARLY', 'BYWEEKNO with WEEKLY (should be rejected)',
    assert_rrule_rejected(
        'BYWEEKNO with WEEKLY',
        'FREQ=WEEKLY;BYWEEKNO=5;COUNT=3',
        '%BYWEEKNO can only be used with FREQ=YEARLY%'
    )
);

-- Test 1.8: BYWEEKNO with DAILY should fail
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Only With YEARLY', 'BYWEEKNO with DAILY (should be rejected)',
    assert_rrule_rejected(
        'BYWEEKNO with DAILY',
        'FREQ=DAILY;BYWEEKNO=1;COUNT=3',
        '%BYWEEKNO can only be used with FREQ=YEARLY%'
    )
);

-- Test 1.9: BYWEEKNO with YEARLY is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Only With YEARLY', 'BYWEEKNO with YEARLY (should be accepted)',
    assert_rrule_accepted(
        'BYWEEKNO with YEARLY',
        'FREQ=YEARLY;BYWEEKNO=1;COUNT=3',
        3
    )
);

-- Test 1.10: BYYEARDAY not with DAILY
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Not With DAILY/WEEKLY/MONTHLY', 'BYYEARDAY with DAILY (should be rejected)',
    assert_rrule_rejected(
        'BYYEARDAY with DAILY',
        'FREQ=DAILY;BYYEARDAY=100;COUNT=3',
        '%BYYEARDAY cannot be used with FREQ=DAILY%'
    )
);

-- Test 1.11: BYYEARDAY not with WEEKLY
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Not With DAILY/WEEKLY/MONTHLY', 'BYYEARDAY with WEEKLY (should be rejected)',
    assert_rrule_rejected(
        'BYYEARDAY with WEEKLY',
        'FREQ=WEEKLY;BYYEARDAY=200;COUNT=3',
        '%BYYEARDAY cannot be used with FREQ=WEEKLY%'
    )
);

-- Test 1.12: BYYEARDAY not with MONTHLY
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Not With DAILY/WEEKLY/MONTHLY', 'BYYEARDAY with MONTHLY (should be rejected)',
    assert_rrule_rejected(
        'BYYEARDAY with MONTHLY',
        'FREQ=MONTHLY;BYYEARDAY=300;COUNT=3',
        '%BYYEARDAY cannot be used with FREQ=MONTHLY%'
    )
);

-- Test 1.13: BYYEARDAY with YEARLY is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Not With DAILY/WEEKLY/MONTHLY', 'BYYEARDAY with YEARLY (should be accepted)',
    assert_rrule_accepted(
        'BYYEARDAY with YEARLY',
        'FREQ=YEARLY;BYYEARDAY=100;COUNT=3',
        3
    )
);

-- Test 1.14: BYDAY ordinals only with MONTHLY/YEARLY
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Only With MONTHLY/YEARLY', 'BYDAY=2MO with WEEKLY (should be rejected)',
    assert_rrule_rejected(
        'BYDAY ordinal with WEEKLY',
        'FREQ=WEEKLY;BYDAY=2MO;COUNT=3',
        '%BYDAY with ordinal%can only be used with FREQ=MONTHLY or FREQ=YEARLY%'
    )
);

-- Test 1.15: BYDAY ordinal with DAILY should fail
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Only With MONTHLY/YEARLY', 'BYDAY=-1FR with DAILY (should be rejected)',
    assert_rrule_rejected(
        'BYDAY ordinal with DAILY',
        'FREQ=DAILY;BYDAY=-1FR;COUNT=3',
        '%BYDAY with ordinal%can only be used with FREQ=MONTHLY or FREQ=YEARLY%'
    )
);

-- Test 1.16: BYDAY without ordinal with WEEKLY is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Only With MONTHLY/YEARLY', 'BYDAY=MO,FR with WEEKLY (should be accepted)',
    assert_rrule_accepted(
        'BYDAY no ordinal with WEEKLY',
        'FREQ=WEEKLY;BYDAY=MO,FR;COUNT=6',
        6
    )
);

-- Test 1.17: BYDAY with ordinal and MONTHLY is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Only With MONTHLY/YEARLY', 'BYDAY=2TU with MONTHLY (should be accepted)',
    assert_rrule_accepted(
        'BYDAY ordinal with MONTHLY',
        'FREQ=MONTHLY;BYDAY=2TU;COUNT=3',
        3
    )
);

-- Test 1.18: BYDAY with ordinal and YEARLY is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Only With MONTHLY/YEARLY', 'BYDAY=-1FR with YEARLY (should be accepted)',
    assert_rrule_accepted(
        'BYDAY ordinal with YEARLY',
        'FREQ=YEARLY;BYDAY=-1FR;BYMONTH=12;COUNT=3',
        3
    )
);

-- Test 1.18a: BYDAY ordinal cannot be zero (0MO)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Cannot Be Zero', 'BYDAY=0MO with MONTHLY (should be rejected)',
    assert_rrule_rejected(
        'BYDAY zero ordinal',
        'FREQ=MONTHLY;BYDAY=0MO;COUNT=3',
        '%BYDAY ordinal cannot be zero%'
    )
);

-- Test 1.18b: BYDAY ordinal cannot be +0 (positive zero)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Cannot Be Zero', 'BYDAY=+0TU with YEARLY (should be rejected)',
    assert_rrule_rejected(
        'BYDAY positive zero ordinal',
        'FREQ=YEARLY;BYDAY=+0TU;BYMONTH=3;COUNT=3',
        '%BYDAY ordinal cannot be zero%'
    )
);

-- Test 1.18c: BYDAY ordinal cannot be -0 (negative zero)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Cannot Be Zero', 'BYDAY=-0FR with MONTHLY (should be rejected)',
    assert_rrule_rejected(
        'BYDAY negative zero ordinal',
        'FREQ=MONTHLY;BYDAY=-0FR;COUNT=3',
        '%BYDAY ordinal cannot be zero%'
    )
);

-- Test 1.18d: BYDAY ordinal cannot be 00 (double zero)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Cannot Be Zero', 'BYDAY=00WE with YEARLY (should be rejected)',
    assert_rrule_rejected(
        'BYDAY double zero ordinal',
        'FREQ=YEARLY;BYDAY=00WE;BYMONTH=6;COUNT=3',
        '%BYDAY ordinal cannot be zero%'
    )
);

-- Test 1.18e: BYDAY without ordinal is still valid (MO)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Cannot Be Zero', 'BYDAY=MO with MONTHLY (should be accepted)',
    assert_rrule_accepted(
        'BYDAY without ordinal',
        'FREQ=MONTHLY;BYDAY=MO;COUNT=3',
        3
    )
);

-- Test 1.18f: BYDAY with valid positive ordinal is still valid (1MO, 2TU)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Cannot Be Zero', 'BYDAY=1MO,2TU with MONTHLY (should be accepted)',
    assert_rrule_accepted(
        'BYDAY valid positive ordinals',
        'FREQ=MONTHLY;BYDAY=1MO,2TU;COUNT=3',
        3
    )
);

-- Test 1.18g: BYDAY ordinal out of range (>53)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Range', 'BYDAY=54MO (should be rejected)',
    assert_rrule_rejected(
        'BYDAY ordinal too large',
        'FREQ=MONTHLY;BYDAY=54MO;COUNT=1',
        '%out of valid range%'
    )
);

-- Test 1.18h: BYDAY ordinal out of range (<-53)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinal Range', 'BYDAY=-54SU (should be rejected)',
    assert_rrule_rejected(
        'BYDAY ordinal too small',
        'FREQ=YEARLY;BYDAY=-54SU;COUNT=1',
        '%out of valid range%'
    )
);

-- Test 1.19: BYSETPOS requires another BYxxx
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSETPOS Requires Other BYxxx', 'BYSETPOS alone (should be rejected)',
    assert_rrule_rejected(
        'BYSETPOS alone',
        'FREQ=DAILY;BYSETPOS=1;COUNT=3',
        '%BYSETPOS requires at least one other BYxxx parameter%'
    )
);

-- Test 1.20: BYSETPOS with BYDAY is valid
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSETPOS Requires Other BYxxx', 'BYSETPOS with BYDAY (should be accepted)',
    assert_rrule_accepted(
        'BYSETPOS with BYDAY',
        'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3',
        3
    )
);

-- Test 1.21: BYMONTHDAY not valid with WEEKLY
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTHDAY Not With WEEKLY', 'BYMONTHDAY with WEEKLY (should be rejected)',
    assert_rrule_rejected(
        'BYMONTHDAY with WEEKLY',
        'FREQ=WEEKLY;BYMONTHDAY=15;COUNT=3',
        '%BYMONTHDAY cannot be used with FREQ=WEEKLY%'
    )
);

-- Test 1.22: BYMONTHDAY valid with DAILY (alternative)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTHDAY Not With WEEKLY', 'BYMONTHDAY with DAILY (should be accepted)',
    assert_rrule_accepted(
        'BYMONTHDAY with DAILY',
        'FREQ=DAILY;BYMONTHDAY=15;COUNT=3',
        3
    )
);

-- Test 1.23: BYDAY with ordinals cannot be used with YEARLY + BYWEEKNO
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Not With YEARLY+BYWEEKNO', 'BYDAY ordinals with YEARLY+BYWEEKNO (should be rejected)',
    assert_rrule_rejected(
        'BYDAY ordinals with YEARLY+BYWEEKNO',
        'FREQ=YEARLY;BYWEEKNO=10;BYDAY=2MO;COUNT=3',
        '%BYDAY with ordinal%cannot be used when FREQ=YEARLY and BYWEEKNO is specified%'
    )
);

-- Test 1.24: BYDAY without ordinals valid with YEARLY + BYWEEKNO
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYDAY Ordinals Not With YEARLY+BYWEEKNO', 'BYDAY without ordinals with YEARLY+BYWEEKNO (should be accepted)',
    assert_rrule_accepted(
        'BYDAY without ordinals with YEARLY+BYWEEKNO',
        'FREQ=YEARLY;BYWEEKNO=10;BYDAY=MO;COUNT=3',
        3
    )
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 2: Parameter Range Validations'
\echo '====================================================================='

-- Test 2.1-2.4: BYSECOND range (0-60)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSECOND Range 0-60', 'BYSECOND=61 (should be rejected)',
    assert_rrule_rejected(
        'BYSECOND out of range high',
        'FREQ=DAILY;BYSECOND=61;COUNT=1',
        '%BYSECOND=61 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSECOND Range 0-60', 'BYSECOND=-1 (should be rejected)',
    assert_rrule_rejected(
        'BYSECOND negative',
        'FREQ=DAILY;BYSECOND=-1;COUNT=1',
        '%BYSECOND=-1 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSECOND Range 0-60', 'BYSECOND=0 (should be accepted)',
    assert_rrule_accepted(
        'BYSECOND=0 valid',
        'FREQ=DAILY;BYSECOND=0;COUNT=2',
        2
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSECOND Range 0-60', 'BYSECOND=59 (should be accepted)',
    assert_rrule_accepted(
        'BYSECOND=59 valid',
        'FREQ=DAILY;BYSECOND=59;COUNT=2',
        2
    )
);

-- Test 2.5: BYSECOND=60 (leap second) should be accepted and treated as 59
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSECOND Range 0-60', 'BYSECOND=60 (should be accepted)',
    assert_rrule_accepted(
        'BYSECOND=60 valid',
        'FREQ=DAILY;BYSECOND=60;COUNT=2',
        2
    )
);

-- Test 2.5-2.8: BYMINUTE range (0-59)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMINUTE Range 0-59', 'BYMINUTE=60 (should be rejected)',
    assert_rrule_rejected(
        'BYMINUTE out of range',
        'FREQ=DAILY;BYMINUTE=60;COUNT=1',
        '%BYMINUTE=60 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMINUTE Range 0-59', 'BYMINUTE=-1 (should be rejected)',
    assert_rrule_rejected(
        'BYMINUTE negative',
        'FREQ=DAILY;BYMINUTE=-1;COUNT=1',
        '%BYMINUTE=-1 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMINUTE Range 0-59', 'BYMINUTE=0 (should be accepted)',
    assert_rrule_accepted(
        'BYMINUTE=0 valid',
        'FREQ=DAILY;BYMINUTE=0;COUNT=2',
        2
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMINUTE Range 0-59', 'BYMINUTE=59 (should be accepted)',
    assert_rrule_accepted(
        'BYMINUTE=59 valid',
        'FREQ=DAILY;BYMINUTE=59;COUNT=2',
        2
    )
);

-- Test 2.9-2.12: BYHOUR range (0-23)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR Range 0-23', 'BYHOUR=24 (should be rejected)',
    assert_rrule_rejected(
        'BYHOUR out of range',
        'FREQ=DAILY;BYHOUR=24;COUNT=1',
        '%BYHOUR=24 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR Range 0-23', 'BYHOUR=-1 (should be rejected)',
    assert_rrule_rejected(
        'BYHOUR negative',
        'FREQ=DAILY;BYHOUR=-1;COUNT=1',
        '%BYHOUR=-1 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR Range 0-23', 'BYHOUR=12 (should be accepted)',
    assert_rrule_accepted(
        'BYHOUR=12 valid',
        'FREQ=DAILY;BYHOUR=12;COUNT=2',
        2
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR Range 0-23', 'BYHOUR=23 (should be accepted - 11 PM)',
    assert_rrule_accepted(
        'BYHOUR=23 valid',
        'FREQ=DAILY;BYHOUR=23;COUNT=2',
        2
    )
);

-- Test 2.13-2.16: BYMONTH range (1-12)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTH Range 1-12', 'BYMONTH=13 (should be rejected)',
    assert_rrule_rejected(
        'BYMONTH out of range high',
        'FREQ=YEARLY;BYMONTH=13;COUNT=1',
        '%BYMONTH=13 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTH Range 1-12', 'BYMONTH=0 (should be rejected)',
    assert_rrule_rejected(
        'BYMONTH out of range low',
        'FREQ=YEARLY;BYMONTH=0;COUNT=1',
        '%BYMONTH=0 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTH Range 1-12', 'BYMONTH=1 (should be accepted - January)',
    assert_rrule_accepted(
        'BYMONTH=1 valid',
        'FREQ=YEARLY;BYMONTH=1;COUNT=2',
        2
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTH Range 1-12', 'BYMONTH=12 (should be accepted - December)',
    assert_rrule_accepted(
        'BYMONTH=12 valid',
        'FREQ=YEARLY;BYMONTH=12;COUNT=2',
        2
    )
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 3: Zero Values and Extended Range Validations'
\echo '====================================================================='

-- Test 3.0: COUNT=0 (should be rejected)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('COUNT Validation', 'COUNT=0 (should be rejected)',
    assert_rrule_rejected(
        'COUNT=0 invalid',
        'FREQ=DAILY;COUNT=0',
        '%COUNT must be a positive integer%'
    )
);

-- Test 3.0a: COUNT=-1 (negative COUNT is now rejected)
-- The parser now explicitly checks for negative COUNT values and raises an error.
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('COUNT Validation', 'COUNT=-1 (should be rejected)',
    assert_rrule_rejected(
        'COUNT=-1 invalid',
        'FREQ=DAILY;COUNT=-1',
        '%COUNT must be a positive integer%'
    )
);

-- Test 3.1-3.4: BYMONTHDAY validation
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTHDAY Validation', 'BYMONTHDAY=0 (should be rejected)',
    assert_rrule_rejected(
        'BYMONTHDAY=0 invalid',
        'FREQ=MONTHLY;BYMONTHDAY=0;COUNT=1',
        '%BYMONTHDAY=0 is not valid%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTHDAY Validation', 'BYMONTHDAY=32 (should be rejected)',
    assert_rrule_rejected(
        'BYMONTHDAY out of range',
        'FREQ=MONTHLY;BYMONTHDAY=32;COUNT=1',
        '%BYMONTHDAY=32 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTHDAY Validation', 'BYMONTHDAY=-32 (should be rejected)',
    assert_rrule_rejected(
        'BYMONTHDAY negative out of range',
        'FREQ=MONTHLY;BYMONTHDAY=-32;COUNT=1',
        '%BYMONTHDAY=-32 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYMONTHDAY Validation', 'BYMONTHDAY=-1 (should be accepted - last day)',
    assert_rrule_accepted(
        'BYMONTHDAY=-1 valid',
        'FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3',
        3
    )
);

-- Test 3.5-3.8: BYYEARDAY validation
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Validation', 'BYYEARDAY=0 (should be rejected)',
    assert_rrule_rejected(
        'BYYEARDAY=0 invalid',
        'FREQ=YEARLY;BYYEARDAY=0;COUNT=1',
        '%BYYEARDAY=0 is not valid%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Validation', 'BYYEARDAY=367 (should be rejected)',
    assert_rrule_rejected(
        'BYYEARDAY out of range',
        'FREQ=YEARLY;BYYEARDAY=367;COUNT=1',
        '%BYYEARDAY=367 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Validation', 'BYYEARDAY=-367 (should be rejected)',
    assert_rrule_rejected(
        'BYYEARDAY negative out of range',
        'FREQ=YEARLY;BYYEARDAY=-367;COUNT=1',
        '%BYYEARDAY=-367 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYYEARDAY Validation', 'BYYEARDAY=-1 (should be accepted - Dec 31)',
    assert_rrule_accepted(
        'BYYEARDAY=-1 valid',
        'FREQ=YEARLY;BYYEARDAY=-1;COUNT=3',
        3
    )
);

-- Test 3.9-3.12: BYWEEKNO validation
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Validation', 'BYWEEKNO=0 (should be rejected)',
    assert_rrule_rejected(
        'BYWEEKNO=0 invalid',
        'FREQ=YEARLY;BYWEEKNO=0;COUNT=1',
        '%BYWEEKNO=0 is not valid%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Validation', 'BYWEEKNO=54 (should be rejected)',
    assert_rrule_rejected(
        'BYWEEKNO out of range',
        'FREQ=YEARLY;BYWEEKNO=54;COUNT=1',
        '%BYWEEKNO=54 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Validation', 'BYWEEKNO=-54 (should be rejected)',
    assert_rrule_rejected(
        'BYWEEKNO negative out of range',
        'FREQ=YEARLY;BYWEEKNO=-54;COUNT=1',
        '%BYWEEKNO=-54 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYWEEKNO Validation', 'BYWEEKNO=1 (should be accepted - first week)',
    assert_rrule_accepted(
        'BYWEEKNO=1 valid',
        'FREQ=YEARLY;BYWEEKNO=1;COUNT=3',
        3
    )
);

-- Test 3.13-3.16: BYSETPOS validation
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSETPOS Validation', 'BYSETPOS=0 (should be rejected)',
    assert_rrule_rejected(
        'BYSETPOS=0 invalid',
        'FREQ=MONTHLY;BYDAY=MO;BYSETPOS=0;COUNT=1',
        '%BYSETPOS=0 is not valid%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSETPOS Validation', 'BYSETPOS=367 (should be rejected)',
    assert_rrule_rejected(
        'BYSETPOS out of range',
        'FREQ=MONTHLY;BYDAY=MO;BYSETPOS=367;COUNT=1',
        '%BYSETPOS=367 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSETPOS Validation', 'BYSETPOS=-367 (should be rejected)',
    assert_rrule_rejected(
        'BYSETPOS negative out of range',
        'FREQ=MONTHLY;BYDAY=MO;BYSETPOS=-367;COUNT=1',
        '%BYSETPOS=-367 is out of valid range%'
    )
);

INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYSETPOS Validation', 'BYSETPOS=-1 (should be accepted - last position)',
    assert_rrule_accepted(
        'BYSETPOS=-1 valid',
        'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3',
        3
    )
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 4: Complex Validation Scenarios'
\echo '====================================================================='

-- Test 4.1: Multiple violations (should report first one encountered)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Complex Scenarios', 'Multiple violations (missing FREQ + COUNT+UNTIL)',
    assert_rrule_rejected(
        'Multiple violations',
        'COUNT=10;UNTIL=20251231T235959Z;BYMONTHDAY=15',
        '%FREQ parameter is required%'  -- First validation should trigger
    )
);

-- Test 4.2: Complex valid RRULE with many parameters
-- BYMONTH=1,6 limits to Jan and June; BYDAY=MO limits to Mondays; BYMONTHDAY=1,8,15,22 picks weeks
-- This is much less sparse than Friday-the-13th and reliably produces 5 results within 10 years
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Complex Scenarios', 'Complex valid RRULE (all constraints satisfied)',
    assert_rrule_accepted(
        'Complex valid RRULE',
        'FREQ=MONTHLY;BYDAY=MO;BYMONTH=1,6;COUNT=5',
        5
    )
);

-- Test 4.3: Edge case - BYMONTHDAY=31 (valid even though not all months have 31 days)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Complex Scenarios', 'BYMONTHDAY=31 (valid - handled by SKIP logic)',
    assert_rrule_accepted(
        'BYMONTHDAY=31 valid',
        'FREQ=MONTHLY;BYMONTHDAY=31;COUNT=12',
        12
    )
);

-- Test 4.4: BYYEARDAY=366 (valid - leap years)
-- Note: With 10-year default window from 2025, only 2 leap years exist (2028, 2032)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Complex Scenarios', 'BYYEARDAY=366 (valid for leap years)',
    assert_rrule_accepted(
        'BYYEARDAY=366 valid',
        'FREQ=YEARLY;BYYEARDAY=366;COUNT=2',
        2
    )
);

-- Test 4.5: Multiple BYxxx with BYSETPOS (valid)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Complex Scenarios', 'Multiple BYxxx + BYSETPOS (valid complex pattern)',
    assert_rrule_accepted(
        'Multiple BYxxx + BYSETPOS',
        'FREQ=YEARLY;BYMONTH=1,7;BYDAY=MO,FR;BYSETPOS=1,-1;COUNT=4',
        4
    )
);

\echo ''
\echo '====================================================================='
\echo 'Test Results Summary'
\echo '====================================================================='

-- Display all test results grouped by category
SELECT
    test_category,
    COUNT(*) as total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') as passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') as failed
FROM validation_test_results
GROUP BY test_category
ORDER BY test_category;

\echo ''
\echo 'Overall Summary:'
SELECT
    COUNT(*) as total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') as passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') as failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status LIKE 'PASS%') / COUNT(*), 1) as pass_percentage
FROM validation_test_results;

\echo ''
\echo 'Detailed Results:'
SELECT
    test_number,
    test_category,
    test_name,
    status
FROM validation_test_results
ORDER BY test_number;

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 5: Syntax Robustness Tests'
\echo '====================================================================='

-- Test 5.1: Duplicate FREQ parameters should be rejected
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Syntax Robustness', 'Duplicate FREQ=DAILY;FREQ=WEEKLY (rejected)',
    assert_rrule_rejected(
        'Duplicate FREQ rejected',
        'FREQ=DAILY;FREQ=WEEKLY;COUNT=3',
        '%Duplicate FREQ%'
    )
);

-- Test 5.2: Unknown parameters are silently ignored
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Syntax Robustness', 'Unknown parameter FOOBAR=XYZ (silently ignored)',
    assert_rrule_accepted(
        'Unknown param ignored',
        'FREQ=DAILY;FOOBAR=XYZ;COUNT=3',
        3
    )
);

-- Test 5.3: Extra semicolons in RRULE string
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Syntax Robustness', 'Extra semicolons FREQ=DAILY;;COUNT=3',
    assert_rrule_accepted(
        'Extra semicolons',
        'FREQ=DAILY;;COUNT=3',
        3
    )
);

-- Test 5.4: Trailing semicolon
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Syntax Robustness', 'Trailing semicolon FREQ=DAILY;COUNT=3;',
    assert_rrule_accepted(
        'Trailing semicolon',
        'FREQ=DAILY;COUNT=3;',
        3
    )
);

-- Test 5.5: Lowercase freq (should NOT be recognized - parser uses uppercase regex)
-- lowercase 'freq=daily' won't match 'FREQ=([A-Z]+)' so FREQ will be NULL → rejected
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Syntax Robustness', 'Lowercase freq=daily (not recognized)',
    assert_rrule_rejected(
        'Lowercase freq',
        'freq=daily;count=3',
        '%FREQ parameter is required%'
    )
);

-- Test 5.6: Mixed case - FREQ uppercase but value lowercase (FREQ=daily)
-- 'FREQ=([A-Z]+)' requires uppercase value
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Syntax Robustness', 'Mixed case FREQ=daily (not recognized)',
    assert_rrule_rejected(
        'Mixed case freq value',
        'FREQ=daily;COUNT=3',
        '%FREQ parameter is required%'
    )
);

-- Test 5.7: Lowercase RSCALE value should still be accepted (rscale uses [^;]+ pattern via SKIP handling)
-- RSCALE=gregorian is tested in test_skip_support.sql but let's verify lowercase acceptance here too
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Syntax Robustness', 'Lowercase RSCALE=gregorian accepted',
    assert_rrule_accepted(
        'Lowercase RSCALE value',
        'FREQ=MONTHLY;RSCALE=gregorian;SKIP=OMIT;COUNT=3',
        3
    )
);

-- Test 5.8: Whitespace in values (spaces around = break regex parsing)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Syntax Robustness', 'Whitespace FREQ = DAILY (not recognized)',
    assert_rrule_rejected(
        'Whitespace around equals',
        'FREQ = DAILY;COUNT=3',
        '%FREQ parameter is required%'
    )
);

-- Test 5.9: Invalid WKST value (XX is not a valid day abbreviation)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('WKST Validation', 'WKST=XX (should be rejected)',
    assert_rrule_rejected(
        'Invalid WKST value',
        'FREQ=WEEKLY;WKST=XX;COUNT=3',
        '%Invalid WKST value%'
    )
);

-- Test 5.10: Lowercase WKST value (parser requires uppercase two-letter abbreviation)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('WKST Validation', 'WKST=monday (should be rejected)',
    assert_rrule_rejected(
        'Lowercase WKST value',
        'FREQ=WEEKLY;WKST=monday;COUNT=3',
        '%Invalid WKST value%'
    )
);

-- Test 5.11: Single-character WKST value (M is not valid, must be two-letter)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('WKST Validation', 'WKST=M (should be rejected)',
    assert_rrule_rejected(
        'Single char WKST value',
        'FREQ=WEEKLY;WKST=M;COUNT=3',
        '%Invalid WKST value%'
    )
);

-- Test 5.12: Valid WKST values should still be accepted
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('WKST Validation', 'WKST=SU (should be accepted)',
    assert_rrule_accepted(
        'Valid WKST=SU',
        'FREQ=WEEKLY;WKST=SU;COUNT=3',
        3
    )
);

-- Test 5.13: NULL dtstart should be rejected with descriptive error
DO $$
DECLARE
    err_msg TEXT;
    result_count INT;
BEGIN
    BEGIN
        SELECT COUNT(*) INTO result_count FROM rrule."all"(
            'FREQ=DAILY;COUNT=3',
            NULL::TIMESTAMP
        );
        INSERT INTO validation_test_results (test_category, test_name, status) VALUES (
            'NULL Input Validation',
            'NULL dtstart rejected',
            'FAIL: expected exception but got ' || result_count || ' results'
        );
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
            INSERT INTO validation_test_results (test_category, test_name, status) VALUES (
                'NULL Input Validation',
                'NULL dtstart rejected',
                CASE WHEN err_msg LIKE '%dtstart%NULL%' OR err_msg LIKE '%dtstart%required%' THEN 'PASS' ELSE 'FAIL: wrong error: ' || LEFT(err_msg, 100) END
            );
    END;
END $$;

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 6: BYxxx Parse-Failure Detection'
\echo '====================================================================='

-- These tests verify that when a BYxxx keyword is present but its value
-- cannot be parsed (non-numeric garbage), a descriptive error is raised
-- instead of silently treating it as NULL.

-- Test 6.1: BYDAY with invalid day code
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYxxx Parse Failure', 'BYDAY=XY (unparseable day code)',
    assert_rrule_rejected(
        'BYDAY unparseable',
        'FREQ=WEEKLY;BYDAY=XY;COUNT=3',
        '%BYDAY value could not be parsed%'
    )
);

-- Test 6.2: BYDAY with lowercase day code
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYxxx Parse Failure', 'BYDAY=mo (lowercase not recognized)',
    assert_rrule_rejected(
        'BYDAY lowercase',
        'FREQ=WEEKLY;BYDAY=mo;COUNT=3',
        '%BYDAY value could not be parsed%'
    )
);

-- Test 6.3: Valid BYDAY still works
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYxxx Parse Failure', 'BYDAY=MO,FR (valid - still accepted)',
    assert_rrule_accepted(
        'BYDAY valid still works',
        'FREQ=WEEKLY;BYDAY=MO,FR;COUNT=4',
        4
    )
);

-- Test 6.4: BYMONTH with text value
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYxxx Parse Failure', 'BYMONTH=FOO (unparseable)',
    assert_rrule_rejected(
        'BYMONTH unparseable',
        'FREQ=YEARLY;BYMONTH=FOO;COUNT=3',
        '%BYMONTH value could not be parsed%'
    )
);

-- Test 6.5: Valid BYMONTH still works
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYxxx Parse Failure', 'BYMONTH=1,6 (valid - still accepted)',
    assert_rrule_accepted(
        'BYMONTH valid still works',
        'FREQ=YEARLY;BYMONTH=1,6;COUNT=4',
        4
    )
);

-- Test 6.6: BYMONTHDAY with text value
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYxxx Parse Failure', 'BYMONTHDAY=ABC (unparseable)',
    assert_rrule_rejected(
        'BYMONTHDAY unparseable',
        'FREQ=MONTHLY;BYMONTHDAY=ABC;COUNT=3',
        '%BYMONTHDAY value could not be parsed%'
    )
);

-- Test 6.7: BYYEARDAY with text value
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYxxx Parse Failure', 'BYYEARDAY=XYZ (unparseable)',
    assert_rrule_rejected(
        'BYYEARDAY unparseable',
        'FREQ=YEARLY;BYYEARDAY=XYZ;COUNT=3',
        '%BYYEARDAY value could not be parsed%'
    )
);

-- Test 6.8: BYWEEKNO with text value
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYxxx Parse Failure', 'BYWEEKNO=ABC (unparseable)',
    assert_rrule_rejected(
        'BYWEEKNO unparseable',
        'FREQ=YEARLY;BYWEEKNO=ABC;COUNT=3',
        '%BYWEEKNO value could not be parsed%'
    )
);

-- Test 6.9: BYSETPOS with text value
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYxxx Parse Failure', 'BYSETPOS=FOO (unparseable)',
    assert_rrule_rejected(
        'BYSETPOS unparseable',
        'FREQ=MONTHLY;BYDAY=MO;BYSETPOS=FOO;COUNT=3',
        '%BYSETPOS value could not be parsed%'
    )
);

-- Test 6.10: BYHOUR with text value
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYxxx Parse Failure', 'BYHOUR=ABC (unparseable)',
    assert_rrule_rejected(
        'BYHOUR unparseable',
        'FREQ=DAILY;BYHOUR=ABC;COUNT=3',
        '%BYHOUR value could not be parsed%'
    )
);

-- Test 6.11: BYMINUTE with text value
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYxxx Parse Failure', 'BYMINUTE=XYZ (unparseable)',
    assert_rrule_rejected(
        'BYMINUTE unparseable',
        'FREQ=DAILY;BYMINUTE=XYZ;COUNT=3',
        '%BYMINUTE value could not be parsed%'
    )
);

-- Test 6.12: BYSECOND with text value
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYxxx Parse Failure', 'BYSECOND=FOO (unparseable)',
    assert_rrule_rejected(
        'BYSECOND unparseable',
        'FREQ=DAILY;BYSECOND=FOO;COUNT=3',
        '%BYSECOND value could not be parsed%'
    )
);

------------------------------------------------------------------------------------------------------
-- Timezone Validation Tests (validate_timezone helper function)
------------------------------------------------------------------------------------------------------

-- Test 7.1: Valid timezone should succeed
DO $$
DECLARE
  test_passed BOOLEAN := TRUE;
BEGIN
  BEGIN
    PERFORM rrule.validate_timezone('America/New_York');
  EXCEPTION
    WHEN OTHERS THEN
      test_passed := FALSE;
  END;

  INSERT INTO validation_test_results (test_category, test_name, status) VALUES (
    'Timezone Validation',
    'Valid timezone (America/New_York)',
    CASE WHEN test_passed THEN 'PASS [Valid timezone accepted]' ELSE 'FAIL [Valid timezone rejected]' END
  );
END $$;

-- Test 7.2: NULL timezone should succeed (optional parameter)
DO $$
DECLARE
  test_passed BOOLEAN := TRUE;
BEGIN
  BEGIN
    PERFORM rrule.validate_timezone(NULL);
  EXCEPTION
    WHEN OTHERS THEN
      test_passed := FALSE;
  END;

  INSERT INTO validation_test_results (test_category, test_name, status) VALUES (
    'Timezone Validation',
    'NULL timezone (optional parameter)',
    CASE WHEN test_passed THEN 'PASS [NULL accepted]' ELSE 'FAIL [NULL rejected]' END
  );
END $$;

-- Test 7.3: Invalid timezone should raise exception
DO $$
DECLARE
  test_passed BOOLEAN := FALSE;
BEGIN
  BEGIN
    PERFORM rrule.validate_timezone('Invalid/Timezone');
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE '%Invalid timezone%' THEN
        test_passed := TRUE;
      END IF;
  END;

  INSERT INTO validation_test_results (test_category, test_name, status) VALUES (
    'Timezone Validation',
    'Invalid timezone should raise exception',
    CASE WHEN test_passed THEN 'PASS [Exception raised]' ELSE 'FAIL [No exception]' END
  );
END $$;

-- Test 7.4: Integration with rrule."all"() TZID parameter
DO $$
DECLARE
  test_passed BOOLEAN := FALSE;
BEGIN
  BEGIN
    PERFORM rrule."all"('FREQ=DAILY;COUNT=1;TZID=Invalid/Zone', '2025-01-01'::TIMESTAMP);
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE '%Invalid timezone%' THEN
        test_passed := TRUE;
      END IF;
  END;

  INSERT INTO validation_test_results (test_category, test_name, status) VALUES (
    'Timezone Validation',
    'Integration with rrule."all"() TZID',
    CASE WHEN test_passed THEN 'PASS [TZID validated]' ELSE 'FAIL [TZID not validated]' END
  );
END $$;

-- ============================================================================
-- SECTION 8: BYHOUR/BYMINUTE/BYSECOND Frequency Restriction Tests
-- ============================================================================
\echo ''
\echo '--- Section 8: BYHOUR/BYMINUTE/BYSECOND Frequency Restrictions ---'

-- Test 8.1: BYHOUR with WEEKLY should be rejected
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR/BYMINUTE/BYSECOND Restrictions', 'BYHOUR with FREQ=WEEKLY (should be rejected)',
    assert_rrule_rejected(
        'BYHOUR with WEEKLY',
        'FREQ=WEEKLY;BYHOUR=9;COUNT=3',
        '%BYHOUR is not supported with FREQ=WEEKLY%'
    )
);

-- Test 8.2: BYHOUR with MONTHLY should be rejected
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR/BYMINUTE/BYSECOND Restrictions', 'BYHOUR with FREQ=MONTHLY (should be rejected)',
    assert_rrule_rejected(
        'BYHOUR with MONTHLY',
        'FREQ=MONTHLY;BYHOUR=9;COUNT=3',
        '%BYHOUR is not supported with FREQ=MONTHLY%'
    )
);

-- Test 8.3: BYHOUR with YEARLY should be rejected
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR/BYMINUTE/BYSECOND Restrictions', 'BYHOUR with FREQ=YEARLY (should be rejected)',
    assert_rrule_rejected(
        'BYHOUR with YEARLY',
        'FREQ=YEARLY;BYHOUR=9;COUNT=3',
        '%BYHOUR is not supported with FREQ=YEARLY%'
    )
);

-- Test 8.4: BYMINUTE with MONTHLY should be rejected
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR/BYMINUTE/BYSECOND Restrictions', 'BYMINUTE with FREQ=MONTHLY (should be rejected)',
    assert_rrule_rejected(
        'BYMINUTE with MONTHLY',
        'FREQ=MONTHLY;BYMINUTE=30;COUNT=3',
        '%BYMINUTE is not supported with FREQ=MONTHLY%'
    )
);

-- Test 8.5: BYSECOND with YEARLY should be rejected
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('BYHOUR/BYMINUTE/BYSECOND Restrictions', 'BYSECOND with FREQ=YEARLY (should be rejected)',
    assert_rrule_rejected(
        'BYSECOND with YEARLY',
        'FREQ=YEARLY;BYSECOND=0;COUNT=3',
        '%BYSECOND is not supported with FREQ=YEARLY%'
    )
);

-- ============================================================================
-- SECTION 9: Additional Edge Case Validations
-- ============================================================================
\echo ''
\echo '--- Section 9: Additional Edge Case Validations ---'

-- Test 9.1: Empty RRULE string should be rejected (missing FREQ)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Empty/Malformed RRULE', 'Empty string (should be rejected)',
    assert_rrule_rejected(
        'Empty RRULE',
        '',
        '%FREQ parameter is required%'
    )
);

-- Test 9.2: Negative INTERVAL value
-- The parser now explicitly checks for negative INTERVAL values and raises an error.
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('INTERVAL Validation', 'INTERVAL=-1 (should be rejected)',
    assert_rrule_rejected(
        'INTERVAL=-1 invalid',
        'FREQ=DAILY;INTERVAL=-1;COUNT=3',
        '%INTERVAL must be a positive integer%'
    )
);

-- Test 9.3: UNTIL with syntactically valid but semantically invalid date (month 13)
-- Passes the regex check ([0-9TZ]+) and the Z-suffix check, but fails the ::TIMESTAMPTZ cast.
-- This exercises the EXCEPTION WHEN OTHERS handler in parse_rrule_parts().
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('UNTIL Cast Validation', 'UNTIL=20251301T000000Z (month 13, invalid cast)',
    assert_rrule_rejected(
        'UNTIL invalid cast month 13',
        'FREQ=DAILY;UNTIL=20251301T000000Z;COUNT=5',
        '%UNTIL%20251301T000000Z%is not a valid timestamp%'
    )
);

-- Test 9.4: UNTIL with syntactically valid but semantically invalid date (Feb 30)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('UNTIL Cast Validation', 'UNTIL=20250230T000000Z (Feb 30, invalid cast)',
    assert_rrule_rejected(
        'UNTIL invalid cast Feb 30',
        'FREQ=DAILY;UNTIL=20250230T000000Z;COUNT=5',
        '%UNTIL%20250230T000000Z%is not a valid timestamp%'
    )
);

-- ============================================================================
-- SECTION 10: Additional Error Rejection Tests
-- ============================================================================
\echo ''
\echo '--- Section 10: Additional Error Rejection Tests ---'

-- Test 10.1: Invalid SKIP value should be rejected
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('SKIP Validation', 'SKIP=INVALID (should be rejected)',
    assert_rrule_rejected(
        'SKIP=INVALID rejected',
        'FREQ=MONTHLY;SKIP=INVALID;BYMONTHDAY=31;COUNT=3',
        '%Invalid SKIP value. SKIP must be one of: OMIT, BACKWARD, FORWARD%'
    )
);

-- Test 10.2: Unsupported frequency BIWEEKLY should be rejected
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Frequency Validation', 'FREQ=BIWEEKLY (should be rejected)',
    assert_rrule_rejected(
        'FREQ=BIWEEKLY rejected',
        'FREQ=BIWEEKLY;COUNT=3',
        '%Unsupported frequency: BIWEEKLY. Valid values are: DAILY, WEEKLY, MONTHLY, YEARLY%'
    )
);

-- Test 10.3: HOURLY not supported in standard installation
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('Frequency Validation', 'FREQ=HOURLY standard install (should be rejected)',
    assert_rrule_rejected(
        'FREQ=HOURLY standard rejected',
        'FREQ=HOURLY;COUNT=3',
        '%not supported in standard installation%'
    )
);

-- Test 10.4: Unsupported RSCALE value should be rejected
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('RSCALE Validation', 'RSCALE=HEBREW (should be rejected)',
    assert_rrule_rejected(
        'RSCALE=HEBREW rejected',
        'FREQ=MONTHLY;RSCALE=HEBREW;COUNT=3',
        '%Unsupported RSCALE value%Only GREGORIAN calendar is currently supported%'
    )
);

-- ============================================================================
-- SECTION 11: INTERVAL Upper Bound Validation
-- ============================================================================
\echo ''
\echo '--- Section 11: INTERVAL Upper Bound Validation ---'

-- Test 11.1: INTERVAL=10000 at boundary (should be accepted)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('INTERVAL Upper Bound', 'INTERVAL=10000 (boundary, should be accepted)',
    assert_rrule_accepted(
        'INTERVAL=10000 accepted',
        'FREQ=DAILY;INTERVAL=10000;COUNT=3',
        1
    )
);

-- Test 11.2: INTERVAL=10001 exceeds cap (should be rejected)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('INTERVAL Upper Bound', 'INTERVAL=10001 (should be rejected)',
    assert_rrule_rejected(
        'INTERVAL=10001 rejected',
        'FREQ=DAILY;INTERVAL=10001;COUNT=3',
        '%INTERVAL must not exceed 10000%'
    )
);

-- Test 11.3: INTERVAL=1 regression check (should be accepted)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('INTERVAL Upper Bound', 'INTERVAL=1 (regression, should be accepted)',
    assert_rrule_accepted(
        'INTERVAL=1 regression',
        'FREQ=DAILY;INTERVAL=1;COUNT=5',
        5
    )
);

-- Test 11.4: INTERVAL=10000 with WEEKLY (should be accepted)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('INTERVAL Upper Bound', 'INTERVAL=10000 WEEKLY (should be accepted)',
    assert_rrule_accepted(
        'INTERVAL=10000 WEEKLY accepted',
        'FREQ=WEEKLY;INTERVAL=10000;COUNT=2',
        1
    )
);

-- Test 11.5: INTERVAL=10000 with MONTHLY (should be accepted)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('INTERVAL Upper Bound', 'INTERVAL=10000 MONTHLY (should be accepted)',
    assert_rrule_accepted(
        'INTERVAL=10000 MONTHLY accepted',
        'FREQ=MONTHLY;INTERVAL=10000;COUNT=2',
        1
    )
);

-- Test 11.6: INTERVAL=10000 with YEARLY (should be accepted)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('INTERVAL Upper Bound', 'INTERVAL=10000 YEARLY (should be accepted)',
    assert_rrule_accepted(
        'INTERVAL=10000 YEARLY accepted',
        'FREQ=YEARLY;INTERVAL=10000;COUNT=2',
        1
    )
);

-- Test 11.7: Very large INTERVAL (should be rejected)
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('INTERVAL Upper Bound', 'INTERVAL=999999 (should be rejected)',
    assert_rrule_rejected(
        'INTERVAL=999999 rejected',
        'FREQ=YEARLY;INTERVAL=999999;COUNT=1',
        '%INTERVAL must not exceed 10000%'
    )
);

------------------------------------------------------------------------------------------------------
-- Test 12: NULL date range parameters in between()/after()/before()
------------------------------------------------------------------------------------------------------

-- Helper to test NULL parameter rejection in API functions
CREATE OR REPLACE FUNCTION assert_null_param_rejected(
    test_name TEXT,
    call_sql TEXT,
    expected_error_pattern TEXT
)
RETURNS TEXT AS $$
DECLARE
    dummy TIMESTAMP;
BEGIN
    BEGIN
        EXECUTE call_sql INTO dummy;
        RAISE EXCEPTION 'FAIL [%]: NULL parameter was accepted when it should have been rejected', test_name;
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM LIKE expected_error_pattern THEN
                RETURN 'PASS [' || test_name || ']';
            ELSE
                RAISE EXCEPTION 'FAIL [%]: Wrong error message. Expected pattern: %, Got: %',
                    test_name, expected_error_pattern, SQLERRM;
            END IF;
    END;
END;
$$ LANGUAGE plpgsql;

-- Test 12.1: between() TIMESTAMP - NULL start_date
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('NULL Date Params', 'between() TIMESTAMP - NULL start_date',
    assert_null_param_rejected(
        'between() NULL start_date',
        $$SELECT * FROM rrule."between"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP, NULL::TIMESTAMP, '2025-01-10 10:00:00'::TIMESTAMP) LIMIT 1$$,
        '%start_date is required and cannot be NULL%'
    )
);

-- Test 12.2: between() TIMESTAMP - NULL end_date
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('NULL Date Params', 'between() TIMESTAMP - NULL end_date',
    assert_null_param_rejected(
        'between() NULL end_date',
        $$SELECT * FROM rrule."between"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP, '2025-01-01 10:00:00'::TIMESTAMP, NULL::TIMESTAMP) LIMIT 1$$,
        '%end_date is required and cannot be NULL%'
    )
);

-- Test 12.3: after() TIMESTAMP - NULL after_date
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('NULL Date Params', 'after() TIMESTAMP - NULL after_date',
    assert_null_param_rejected(
        'after() NULL after_date',
        $$SELECT rrule."after"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP, NULL::TIMESTAMP)$$,
        '%after_date is required and cannot be NULL%'
    )
);

-- Test 12.4: before() TIMESTAMP - NULL before_date
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('NULL Date Params', 'before() TIMESTAMP - NULL before_date',
    assert_null_param_rejected(
        'before() NULL before_date',
        $$SELECT rrule."before"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP, NULL::TIMESTAMP)$$,
        '%before_date is required and cannot be NULL%'
    )
);

-- Test 12.5: between() TIMESTAMPTZ - NULL range_start
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('NULL Date Params', 'between() TIMESTAMPTZ - NULL range_start',
    assert_null_param_rejected(
        'between() TIMESTAMPTZ NULL range_start',
        $$SELECT * FROM rrule."between"('FREQ=DAILY;COUNT=3'::TEXT, '2025-01-01 10:00:00+00'::TIMESTAMPTZ, NULL::TIMESTAMPTZ, '2025-01-10 10:00:00+00'::TIMESTAMPTZ) LIMIT 1$$,
        '%range_start is required and cannot be NULL%'
    )
);

-- Test 12.6: between() TIMESTAMPTZ - NULL range_end
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('NULL Date Params', 'between() TIMESTAMPTZ - NULL range_end',
    assert_null_param_rejected(
        'between() TIMESTAMPTZ NULL range_end',
        $$SELECT * FROM rrule."between"('FREQ=DAILY;COUNT=3'::TEXT, '2025-01-01 10:00:00+00'::TIMESTAMPTZ, '2025-01-01 10:00:00+00'::TIMESTAMPTZ, NULL::TIMESTAMPTZ) LIMIT 1$$,
        '%range_end is required and cannot be NULL%'
    )
);

-- Test 12.7: after() TIMESTAMPTZ - NULL after_date
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('NULL Date Params', 'after() TIMESTAMPTZ - NULL after_date',
    assert_null_param_rejected(
        'after() TIMESTAMPTZ NULL after_date',
        $$SELECT * FROM rrule."after"('FREQ=DAILY;COUNT=3'::TEXT, '2025-01-01 10:00:00+00'::TIMESTAMPTZ, NULL::TIMESTAMPTZ, 1) LIMIT 1$$,
        '%after_date is required and cannot be NULL%'
    )
);

-- Test 12.8: before() TIMESTAMPTZ - NULL before_date
INSERT INTO validation_test_results (test_category, test_name, status)
VALUES ('NULL Date Params', 'before() TIMESTAMPTZ - NULL before_date',
    assert_null_param_rejected(
        'before() TIMESTAMPTZ NULL before_date',
        $$SELECT * FROM rrule."before"('FREQ=DAILY;COUNT=3'::TEXT, '2025-01-01 10:00:00+00'::TIMESTAMPTZ, NULL::TIMESTAMPTZ, 1) LIMIT 1$$,
        '%before_date is required and cannot be NULL%'
    )
);

------------------------------------------------------------------------------------------------------
-- Check if all tests passed
------------------------------------------------------------------------------------------------------

DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM validation_test_results
    WHERE status LIKE 'FAIL%';

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'VALIDATION TEST SUITE FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'VALIDATION TEST SUITE PASSED: All % tests passed successfully!',
            (SELECT COUNT(*) FROM validation_test_results);
    END IF;
END $$;

ROLLBACK;
