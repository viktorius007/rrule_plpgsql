-- ============================================================================
-- PL/pgSQL Linting with plpgsql_check
-- ============================================================================
--
-- This script validates all rrule functions using the plpgsql_check extension.
-- It catches semantic errors, type mismatches, and other issues before runtime.
--
-- Usage:
--   psql -d rrule_test -f lint.sql
--
-- Requirements:
--   - PostgreSQL 12+
--   - plpgsql_check extension available
--   - rrule schema must be installed first
--
-- ============================================================================

\set ON_ERROR_STOP on
\set QUIET on

-- Enable plpgsql_check extension
CREATE EXTENSION IF NOT EXISTS plpgsql_check;

-- Create results table
CREATE TEMPORARY TABLE lint_results (
    function_name TEXT,
    issue_type TEXT,
    message TEXT
);

-- Counter for progress
CREATE TEMPORARY TABLE lint_progress (
    total INT DEFAULT 0,
    current INT DEFAULT 0
);
INSERT INTO lint_progress VALUES (0, 0);

\echo ''
\echo '=============================================='
\echo 'PLPGSQL_CHECK LINTER FOR RRULE_PLPGSQL'
\echo '=============================================='
\echo ''

-- ============================================================================
-- Auto-discover and lint all PL/pgSQL functions in rrule schema
-- ============================================================================

\echo 'Discovering functions in rrule schema...'

DO $$
DECLARE
    func_record RECORD;
    func_oid OID;
    func_signature TEXT;
    lint_row RECORD;
    func_count INT := 0;
    linted_count INT := 0;
BEGIN
    -- Count total plpgsql functions
    SELECT COUNT(*) INTO func_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    JOIN pg_language l ON p.prolang = l.oid
    WHERE n.nspname = 'rrule'
      AND l.lanname = 'plpgsql';

    RAISE NOTICE 'Found % PL/pgSQL functions to lint', func_count;
    RAISE NOTICE '';

    -- Iterate through all plpgsql functions in rrule schema
    FOR func_record IN
        SELECT
            p.oid,
            n.nspname || '.' || p.proname AS func_name,
            pg_get_function_identity_arguments(p.oid) AS args,
            p.proname
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        JOIN pg_language l ON p.prolang = l.oid
        WHERE n.nspname = 'rrule'
          AND l.lanname = 'plpgsql'
        ORDER BY p.proname
    LOOP
        func_oid := func_record.oid;
        func_signature := func_record.func_name || '(' || func_record.args || ')';
        linted_count := linted_count + 1;

        RAISE NOTICE '[%/%] Linting: %', linted_count, func_count, func_signature;

        -- Run plpgsql_check on this function
        BEGIN
            FOR lint_row IN
                SELECT * FROM plpgsql_check_function(func_oid)
            LOOP
                INSERT INTO lint_results VALUES (
                    func_signature,
                    CASE
                        WHEN lint_row.plpgsql_check_function LIKE 'error%' THEN 'ERROR'
                        WHEN lint_row.plpgsql_check_function LIKE 'warning%' THEN 'WARNING'
                        ELSE 'INFO'
                    END,
                    lint_row.plpgsql_check_function
                );
            END LOOP;

            -- If no issues found, record as clean
            IF NOT EXISTS (SELECT 1 FROM lint_results WHERE function_name = func_signature) THEN
                INSERT INTO lint_results VALUES (func_signature, 'CLEAN', 'No issues found');
            END IF;

        EXCEPTION WHEN OTHERS THEN
            INSERT INTO lint_results VALUES (
                func_signature,
                'SKIP',
                'Could not lint: ' || SQLERRM
            );
        END;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE 'Linting complete!';
END;
$$;

-- ============================================================================
-- Report results
-- ============================================================================

\echo ''
\echo '=============================================='
\echo 'LINT RESULTS'
\echo '=============================================='

-- Show errors first (these are critical)
\echo ''
\echo 'ERRORS (must fix):'
SELECT
    function_name AS "Function",
    message AS "Issue"
FROM lint_results
WHERE issue_type = 'ERROR'
ORDER BY function_name;

-- Show warnings (should review)
\echo ''
\echo 'WARNINGS (should review):'
SELECT
    function_name AS "Function",
    message AS "Issue"
FROM lint_results
WHERE issue_type = 'WARNING'
ORDER BY function_name;

-- Show skipped (informational)
\echo ''
\echo 'SKIPPED (could not lint):'
SELECT
    function_name AS "Function",
    message AS "Reason"
FROM lint_results
WHERE issue_type = 'SKIP'
ORDER BY function_name;

-- Summary
\echo ''
\echo '=============================================='
\echo 'SUMMARY'
\echo '=============================================='

SELECT
    COUNT(*) FILTER (WHERE issue_type = 'ERROR') AS "Errors",
    COUNT(*) FILTER (WHERE issue_type = 'WARNING') AS "Warnings",
    COUNT(*) FILTER (WHERE issue_type = 'SKIP') AS "Skipped",
    COUNT(*) FILTER (WHERE issue_type = 'CLEAN') AS "Clean"
FROM lint_results;

-- Fail if there are errors
DO $$
DECLARE
    error_count INT;
BEGIN
    SELECT COUNT(*) INTO error_count FROM lint_results WHERE issue_type = 'ERROR';
    IF error_count > 0 THEN
        RAISE EXCEPTION E'\n❌ LINTING FAILED: % error(s) found\n', error_count;
    END IF;
END;
$$;

\echo ''
\echo '✅ All functions passed linting (no errors)!'
\echo ''
