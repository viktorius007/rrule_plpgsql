/**
 * Migration Contract Tests
 *
 * Verifies migration safety and dependency behavior documented in docs/MIGRATION.md.
 *
 * Coverage:
 * 1. Reinstall fails when dependent objects exist
 * 2. Error message includes migration guidance
 * 3. Manual side-by-side migration flow is executable end-to-end (smoke)
 *
 * Usage:
 *   psql -d your_database -v rrule_install=src/install.sql \
 *     -f tests/install/test_migration_contract.sql
 */

\set ON_ERROR_STOP on
\set ECHO all

SET timezone = 'UTC';

DROP SCHEMA IF EXISTS rrule_update CASCADE;
DROP SCHEMA IF EXISTS rrule CASCADE;

\if :{?rrule_install}
\i :rrule_install
\else
\i src/install.sql
\endif

-- Create a dependent object that should block schema replacement.
CREATE OR REPLACE VIEW public.migration_contract_view AS
SELECT *
FROM rrule."all"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP);

-- Reinstall with dependency present: should fail with migration guidance.
\set ON_ERROR_STOP off
\if :{?rrule_install}
\i :rrule_install
\else
\i src/install.sql
\endif
ROLLBACK;
\set dependency_error_message :'LAST_ERROR_MESSAGE'

-- Verify the dependent object still works, then clean it up so subsequent suites
-- can reinstall normally.
SELECT COUNT(*)::TEXT AS dep_view_count
FROM public.migration_contract_view;
\gset
DROP VIEW public.migration_contract_view;

\set ON_ERROR_STOP on

SET search_path = public;

BEGIN;

\i tests/helpers.sql

CREATE TEMP TABLE migration_contract_results (
    test_number SERIAL PRIMARY KEY,
    test_group TEXT,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '====================================================================='
\echo 'MIGRATION CONTRACT TESTS'
\echo '====================================================================='
\echo ''

INSERT INTO migration_contract_results (test_group, test_name, status)
VALUES ('Dependency Guard', 'reinstall fails when dependent objects exist',
    assert_true(
        'dependency failure message',
        position('Cannot drop rrule schema - dependent objects exist' IN :'dependency_error_message') > 0
    )
);

INSERT INTO migration_contract_results (test_group, test_name, status)
VALUES ('Dependency Guard', 'error references migration guidance',
    assert_true(
        'migration guidance in error',
        position('Manual Migration Process' IN :'dependency_error_message') > 0
    )
);

INSERT INTO migration_contract_results (test_group, test_name, status)
VALUES ('Dependency Guard', 'dependent view remains usable after failed reinstall',
    assert_equals(
        'dependent view count before cleanup',
        '3',
        :'dep_view_count'
    )
);

-- Smoke-test manual migration flow from docs/MIGRATION.md.
-- This test validates migration choreography (side-by-side schema, cutover, rename)
-- using a minimal replacement all() implementation in rrule_update.
CREATE SCHEMA rrule_update;

CREATE OR REPLACE FUNCTION rrule_update."all"(p_rrule TEXT, p_dtstart TIMESTAMP)
RETURNS SETOF TIMESTAMP
LANGUAGE sql
STABLE
AS $$
    WITH parsed AS (
        SELECT COALESCE((regexp_match(upper(p_rrule), 'COUNT=([0-9]+)'))[1]::INT, 1) AS c
    )
    SELECT (p_dtstart + make_interval(days => gs - 1))::TIMESTAMP
    FROM parsed, generate_series(1, c) AS gs;
$$;

CREATE OR REPLACE VIEW public.migration_contract_view_new AS
SELECT *
FROM rrule_update."all"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP);

INSERT INTO migration_contract_results (test_group, test_name, status)
VALUES ('Migration Flow', 'rrule_update view works before cutover',
    assert_equals(
        'rrule_update view count',
        '3',
        (SELECT COUNT(*)::TEXT FROM public.migration_contract_view_new)
    )
);

DROP VIEW IF EXISTS public.migration_contract_view;
ALTER VIEW public.migration_contract_view_new RENAME TO migration_contract_view;

INSERT INTO migration_contract_results (test_group, test_name, status)
VALUES ('Migration Flow', 'view swap succeeds',
    assert_equals(
        'view swap count',
        '3',
        (SELECT COUNT(*)::TEXT FROM public.migration_contract_view)
    )
);

DROP SCHEMA rrule CASCADE;
ALTER SCHEMA rrule_update RENAME TO rrule;

CREATE OR REPLACE VIEW public.migration_contract_view AS
SELECT *
FROM rrule."all"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP);

INSERT INTO migration_contract_results (test_group, test_name, status)
VALUES ('Migration Flow', 'cutover and rename back to rrule succeeds',
    assert_equals(
        'final cutover count',
        '3',
        (SELECT COUNT(*)::TEXT FROM public.migration_contract_view)
    )
);

\echo ''
\echo 'Test Results:'
SELECT test_number, test_group, test_name, status
FROM migration_contract_results
ORDER BY test_number;

\echo ''
SELECT assert_true(
    'all migration tests passed',
    (SELECT COUNT(*) = COUNT(*) FILTER (WHERE status = 'PASS') FROM migration_contract_results)
);

ROLLBACK;
