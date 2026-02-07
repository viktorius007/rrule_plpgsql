/**
 * Installation Script with Sub-Day Frequencies Support
 *
 * ⚠️  WARNING: SECURITY-SENSITIVE INSTALLATION ⚠️
 *
 * This script installs the RRULE implementation WITH support for HOURLY,
 * MINUTELY, and SECONDLY frequencies.
 *
 * SECURITY IMPLICATIONS:
 * - HOURLY can generate 8,760 occurrences per year
 * - MINUTELY can generate 525,600 occurrences per year
 * - SECONDLY can generate 31,536,000 occurrences per year
 *
 * ⚠️  DO NOT USE THIS in multi-tenant environments without strict validation!
 *
 * REQUIRED BEFORE INSTALLATION:
 * 1. Review rrule_subday.sql header for complete security documentation
 * 2. Implement application-level validation (COUNT/UNTIL limits)
 * 3. Configure statement_timeout to prevent runaway queries:
 *    ALTER DATABASE your_db SET statement_timeout = '30s';
 * 4. Set up monitoring for long-running queries
 * 5. Test thoroughly in staging environment first
 *
 * RECOMMENDED VALIDATION LIMITS:
 * - HOURLY: COUNT <= 1000, UNTIL <= 7 days from dtstart
 * - MINUTELY: COUNT <= 1000, UNTIL <= 24 hours from dtstart
 * - SECONDLY: COUNT <= 1000, UNTIL <= 1 hour from dtstart
 *
 * INSTALLATION:
 *   cd src
 *   psql -d your_database -f install_with_subday.sql
 *
 * Or from within psql:
 *   \i src/install_with_subday.sql
 *
 * ALTERNATIVE (Safer):
 * If you don't need sub-day frequencies, use install.sql instead
 *
 * @package rrule_plpgsql
 * @license MIT
 * @security CRITICAL - Review before use
 */

\set ON_ERROR_STOP on

BEGIN;

\echo ''
\echo '====================================================================='
\echo 'Installing Pure PL/pgSQL RRULE Implementation WITH Sub-Day Frequencies'
\echo '====================================================================='
\echo ''
\echo '⚠️  WARNING: This installation includes HOURLY, MINUTELY, and SECONDLY'
\echo '⚠️  frequency support which can generate millions of occurrences.'
\echo ''
\echo '⚠️  SECURITY REQUIREMENTS:'
\echo '⚠️  - Implement application-level validation (see rrule_subday.sql)'
\echo '⚠️  - Configure statement_timeout'
\echo '⚠️  - Monitor for long-running queries'
\echo ''

-- Set timezone to UTC for consistent behavior
SET timezone = 'UTC';

-- Drop and recreate schema for clean reinstall
\echo 'Creating rrule schema...'

DO $$
DECLARE
    rrule_nsp OID;
    dep_list TEXT;
    error_msg TEXT;
BEGIN
    rrule_nsp := to_regnamespace('rrule');
    IF rrule_nsp IS NOT NULL THEN
        WITH rrule_objects AS (
            SELECT oid FROM pg_proc WHERE pronamespace = rrule_nsp
            UNION ALL
            SELECT oid FROM pg_type WHERE typnamespace = rrule_nsp
            UNION ALL
            SELECT oid FROM pg_class WHERE relnamespace = rrule_nsp
        ),
        deps AS (
            SELECT DISTINCT
                CASE d.classid
                    WHEN 'pg_proc'::regclass THEN format('%I.%I (%s)', pn.nspname, p.proname, 'function')
                    WHEN 'pg_class'::regclass THEN format('%I.%I (%s)', cn.nspname, c.relname,
                        CASE c.relkind
                            WHEN 'v' THEN 'view'
                            WHEN 'm' THEN 'materialized view'
                            WHEN 'r' THEN 'table'
                            WHEN 'S' THEN 'sequence'
                            ELSE 'relation'
                        END)
                    WHEN 'pg_type'::regclass THEN format('%I.%I (%s)', tn.nspname, t.typname, 'type')
                    ELSE pg_describe_object(d.classid, d.objid, d.objsubid)
                END AS dep_desc
            FROM pg_depend d
            JOIN rrule_objects ro ON d.refobjid = ro.oid
            LEFT JOIN pg_proc p ON d.classid = 'pg_proc'::regclass AND d.objid = p.oid
            LEFT JOIN pg_namespace pn ON p.pronamespace = pn.oid
            LEFT JOIN pg_class c ON d.classid = 'pg_class'::regclass AND d.objid = c.oid
            LEFT JOIN pg_namespace cn ON c.relnamespace = cn.oid
            LEFT JOIN pg_type t ON d.classid = 'pg_type'::regclass AND d.objid = t.oid
            LEFT JOIN pg_namespace tn ON t.typnamespace = tn.oid
            WHERE d.deptype IN ('n', 'a', 'i')
              AND d.objid NOT IN (SELECT oid FROM rrule_objects)
              AND (pn.nspname IS NULL OR pn.nspname <> 'rrule')
              AND (cn.nspname IS NULL OR cn.nspname <> 'rrule')
              AND (tn.nspname IS NULL OR tn.nspname <> 'rrule')
        )
        SELECT string_agg('  - ' || dep_desc, E'\n' ORDER BY dep_desc)
        INTO dep_list
        FROM deps;

        IF dep_list IS NOT NULL THEN
            error_msg := E'\n\n' ||
                '╔══════════════════════════════════════════════════════════════════════════════╗' || E'\n' ||
                '║ ERROR: Cannot drop rrule schema - dependent objects exist                   ║' || E'\n' ||
                '╠══════════════════════════════════════════════════════════════════════════════╣' || E'\n' ||
                '║                                                                             ║' || E'\n' ||
                '║ The following objects depend on the rrule schema:                            ║' || E'\n' ||
                '║                                                                             ║' || E'\n' ||
                COALESCE(dep_list, '  (Unable to list dependencies - check manually)') || E'\n' ||
                '║                                                                             ║' || E'\n' ||
                '║ SOLUTION: Manual Migration Process                                          ║' || E'\n' ||
                '║                                                                             ║' || E'\n' ||
                '║ See the complete migration guide:                                           ║' || E'\n' ||
                '║   github.com/sirrodgepodge/rrule_plpgsql/blob/main/docs/MIGRATION.md       ║' || E'\n' ||
                '║                                                                             ║' || E'\n' ||
                '║ You will need to:                                                           ║' || E'\n' ||
                '║   1. Install new version to rrule_update schema (installManual.sh)          ║' || E'\n' ||
                '║   2. Update YOUR dependencies above to use rrule_update                     ║' || E'\n' ||
                '║   3. Test thoroughly with your application                                  ║' || E'\n' ||
                '║   4. Drop old rrule schema and rename rrule_update to rrule                 ║' || E'\n' ||
                '║                                                                             ║' || E'\n' ||
                '║ The guide includes example scripts you can adapt for your specific needs.   ║' || E'\n' ||
                '║                                                                             ║' || E'\n' ||
                '╚══════════════════════════════════════════════════════════════════════════════╝' || E'\n';

            RAISE EXCEPTION '%', error_msg;
        END IF;
    END IF;

    EXECUTE 'DROP SCHEMA IF EXISTS rrule CASCADE';
END $$;

CREATE SCHEMA rrule;

\echo 'Installing core RRULE functions...'
\ir rrule.sql

\echo 'Installing sub-day frequency support...'
\ir rrule_subday.sql

\echo ''
\echo '====================================================================='
\echo 'Installation Complete!'
\echo '====================================================================='
\echo ''
\echo 'Installed API (rrule.js/python-dateutil compatible):'
\echo '  - rrule."all"(rrule, dtstart) -> SETOF TIMESTAMP'
\echo '  - rrule."between"(rrule, dtstart, start_date, end_date, inc DEFAULT false) -> SETOF TIMESTAMP'
\echo '  - rrule."after"(rrule, dtstart, after_date, inc DEFAULT false) -> TIMESTAMP'
\echo '  - rrule."before"(rrule, dtstart, before_date, inc DEFAULT false) -> TIMESTAMP'
\echo '  - rrule."count"(rrule, dtstart) -> INTEGER'
\echo ''
\echo 'Supported Frequencies:'
\echo '  ✅ DAILY, WEEKLY, MONTHLY, YEARLY'
\echo '  ⚠️  HOURLY, MINUTELY, SECONDLY (USE WITH CAUTION)'
\echo ''
\echo '⚠️  IMPORTANT SECURITY REMINDERS:'
\echo ''
\echo '1. Implement application-level validation:'
\echo '   - HOURLY: Limit COUNT to 1000, UNTIL to 7 days'
\echo '   - MINUTELY: Limit COUNT to 1000, UNTIL to 24 hours'
\echo '   - SECONDLY: Limit COUNT to 1000, UNTIL to 1 hour'
\echo ''
\echo '2. Configure database timeout:'
\echo '   ALTER DATABASE your_db SET statement_timeout = ''30s'';'
\echo ''
\echo '3. Monitor for long-running queries:'
\echo '   SELECT * FROM pg_stat_activity'
\echo '   WHERE state = ''active'' AND query_start < now() - interval ''10 seconds'';'
\echo ''
\echo 'See rrule_subday.sql for complete security documentation.'
\echo ''

COMMIT;

-- Reset session settings modified during installation
-- (prevents state leakage on pooled connections)
RESET timezone;
RESET search_path;
