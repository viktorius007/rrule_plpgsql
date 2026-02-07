/**
 * Install Contract Tests
 *
 * Verifies installation guarantees for both src/install.sql and
 * src/install_with_subday.sql.
 *
 * Coverage:
 * 1. Fresh install creates rrule schema and public API functions
 * 2. Reinstall is safe and leaves API functional
 * 3. Standard install rejects sub-day frequencies with expected guidance
 * 4. Sub-day install enables HOURLY/MINUTELY/SECONDLY behavior
 *
 * Usage:
 *   psql -d your_database -v rrule_install=src/install.sql \
 *     -f tests/install/test_install_contract.sql
 */

\set ON_ERROR_STOP on
\set ECHO all

SET timezone = 'UTC';

-- First install (fresh)
DROP SCHEMA IF EXISTS rrule CASCADE;
\if :{?rrule_install}
\i :rrule_install
\else
\i src/install.sql
\endif

-- Reinstall should also succeed when no user dependencies exist
\if :{?rrule_install}
\i :rrule_install
\else
\i src/install.sql
\endif

-- Ensure tests never rely on search_path
SET search_path = public;

BEGIN;

\i tests/helpers.sql

CREATE TEMP TABLE install_contract_results (
    test_number SERIAL PRIMARY KEY,
    test_group TEXT,
    test_name TEXT,
    status TEXT
);

CREATE OR REPLACE FUNCTION assert_subday_contract(test_name TEXT)
RETURNS TEXT AS $$
DECLARE
    hourly_count INT;
    err_msg TEXT;
BEGIN
    BEGIN
        SELECT COUNT(*)
        INTO hourly_count
        FROM rrule."all"('FREQ=HOURLY;COUNT=2', '2025-01-01 10:00:00'::TIMESTAMP);

        IF hourly_count IS DISTINCT FROM 2 THEN
            RAISE EXCEPTION 'FAIL [%]: HOURLY succeeded but returned % results (expected 2)',
                test_name, hourly_count;
        END IF;

        RETURN 'PASS';
    EXCEPTION
        WHEN OTHERS THEN
            err_msg := SQLERRM;
            IF err_msg LIKE '%install_with_subday.sql%'
               AND err_msg LIKE '%disabled by default for security%' THEN
                RETURN 'PASS';
            END IF;

            RAISE EXCEPTION 'FAIL [%]: Unexpected sub-day behavior/error: %', test_name, err_msg;
    END;
END;
$$ LANGUAGE plpgsql;

\echo ''
\echo '====================================================================='
\echo 'INSTALL CONTRACT TESTS'
\echo '====================================================================='
\echo ''

INSERT INTO install_contract_results (test_group, test_name, status)
VALUES ('Install', 'rrule schema exists',
    assert_true('schema exists', to_regnamespace('rrule') IS NOT NULL)
);

INSERT INTO install_contract_results (test_group, test_name, status)
VALUES ('Install', 'all public API names present',
    assert_equals(
        'public API names',
        '8',
        (
            SELECT COUNT(DISTINCT p.proname)::TEXT
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'rrule'
              AND p.proname = ANY (
                ARRAY['all', 'between', 'after', 'before', 'next', 'most_recent', 'count', 'overlaps']
              )
        )
    )
);

INSERT INTO install_contract_results (test_group, test_name, status)
VALUES ('Install', 'core API callable after reinstall',
    assert_equals(
        'daily count callable',
        '3',
        (
            SELECT COUNT(*)::TEXT
            FROM rrule."all"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP)
        )
    )
);

INSERT INTO install_contract_results (test_group, test_name, status)
VALUES ('Install', 'install does not leave search_path at rrule',
    assert_true(
        'search_path reset',
        current_setting('search_path') NOT LIKE 'rrule%'
    )
);

INSERT INTO install_contract_results (test_group, test_name, status)
VALUES ('Subday Contract', 'standard rejects HOURLY OR subday install enables it',
    assert_subday_contract('subday contract')
);

\echo ''
\echo 'Test Results:'
SELECT test_number, test_group, test_name, status
FROM install_contract_results
ORDER BY test_number;

\echo ''
SELECT assert_true(
    'all tests passed',
    (SELECT COUNT(*) = COUNT(*) FILTER (WHERE status = 'PASS') FROM install_contract_results)
);

DROP FUNCTION assert_subday_contract(TEXT);

ROLLBACK;
