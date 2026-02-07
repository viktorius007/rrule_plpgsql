/**
 * Master Installation Script for rrule_plpgsql
 *
 * This script installs all necessary functions for RRULE processing
 * using pure PL/pgSQL (no C extensions required).
 *
 * Installation:
 *   psql -d your_database -f install.sql
 *
 * Or from within psql:
 *   \i install.sql
 *
 * Dependencies: PostgreSQL 17.x
 *
 * Components installed:
 * 1. RRULE schema (namespace isolation)
 * 2. RRULE core functions (comprehensive RFC 5545 & RFC 7529 implementation)
 * 3. RRULE public API (standard rrule.js/python-dateutil compatible methods)
 * 4. Full validation with descriptive error messages
 *
 * @package rrule_plpgsql
 * @license MIT
 */

\set ON_ERROR_STOP on

BEGIN;

\echo ''
\echo '==================================================================='
\echo 'Installing Pure PL/pgSQL RRULE Implementation'
\echo '==================================================================='
\echo ''

-- Set timezone to UTC for consistent behavior
SET timezone = 'UTC';

-- Drop and recreate schema for clean reinstall
-- Note: Without CASCADE, this will error if there are dependent objects
-- (e.g., user views using rrule functions). This is safer than silently
-- dropping user objects.
\echo 'Creating rrule schema...'

-- Try to drop schema with helpful error message if dependencies exist
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

\echo 'Installing RRULE functions...'
\ir rrule.sql

\echo ''
\echo '==================================================================='
\echo 'Installation Complete!'
\echo '==================================================================='
\echo ''
\echo 'PUBLIC API - All functions support both TIMESTAMP and TIMESTAMPTZ:'
\echo ''
\echo 'Core Functions:'
\echo '  - rrule."all"(rrule, dtstart) -> SETOF TIMESTAMP'
\echo '  - rrule."all"(rrule, dtstart_tz, timezone DEFAULT NULL) -> SETOF TIMESTAMPTZ'
\echo '  - rrule."between"(rrule, dtstart, start, end, inc DEFAULT false) -> SETOF TIMESTAMP'
\echo '  - rrule."between"(rrule, dtstart_tz, start_tz, end_tz, tz DEFAULT NULL, inc DEFAULT false) -> SETOF TIMESTAMPTZ'
\echo '  - rrule."after"(rrule, dtstart, after, inc DEFAULT false) -> TIMESTAMP'
\echo '  - rrule."after"(rrule, dtstart_tz, after_tz, cnt, tz DEFAULT NULL, inc DEFAULT false) -> SETOF TIMESTAMPTZ'
\echo '  - rrule."before"(rrule, dtstart, before, inc DEFAULT false) -> TIMESTAMP'
\echo '  - rrule."before"(rrule, dtstart_tz, before_tz, cnt, tz DEFAULT NULL, inc DEFAULT false) -> SETOF TIMESTAMPTZ'
\echo '  - rrule."count"(rrule, dtstart) -> INTEGER'
\echo '  - rrule."count"(rrule, dtstart_tz, timezone DEFAULT NULL) -> INTEGER'
\echo ''
\echo 'Convenience Functions:'
\echo '  - rrule."next"(rrule, dtstart) -> TIMESTAMP'
\echo '  - rrule."next"(rrule, dtstart_tz, timezone DEFAULT NULL) -> TIMESTAMPTZ'
\echo '  - rrule."most_recent"(rrule, dtstart) -> TIMESTAMP'
\echo '  - rrule."most_recent"(rrule, dtstart_tz, timezone DEFAULT NULL) -> TIMESTAMPTZ'
\echo ''
\echo 'Advanced:'
\echo '  - rrule."overlaps"(dtstart_tz, dtend_tz, rrule, min_tz, max_tz, tz DEFAULT NULL) -> BOOLEAN'
\echo ''
\echo 'Timezone Resolution Priority (for TIMESTAMPTZ functions):'
\echo '  1. Explicit timezone parameter (if provided)'
\echo '  2. TZID in RRULE string (e.g., TZID=America/New_York)'
\echo '  3. UTC (fallback)'
\echo ''
\echo 'Features:'
\echo '  - Full RFC 5545 & RFC 7529 compliance'
\echo '  - TZID (timezone) support'
\echo '  - SKIP parameter (OMIT, BACKWARD, FORWARD) for month-end handling'
\echo '  - 18 RFC 5545 constraint validations with descriptive errors'
\echo '  - Schema-based namespacing (rrule.* prevents conflicts)'
\echo ''
\echo 'Example usage (SETOF - streaming, memory efficient):'
\echo '  SELECT * FROM rrule."all"('
\echo '    ''FREQ=DAILY;COUNT=5'','
\echo '    ''2025-01-01 10:00:00''::TIMESTAMP'
\echo '  );'
\echo ''
\echo 'Example usage (array - if you need materialized array):'
\echo '  SELECT array_agg(occurrence) FROM rrule."all"('
\echo '    ''FREQ=DAILY;COUNT=5;TZID=America/New_York'','
\echo '    ''2025-01-01 10:00:00''::TIMESTAMP'
\echo '  ) AS occurrence;'
\echo ''
\echo 'To use functions without schema prefix, add to search_path:'
\echo '  SET search_path TO rrule, public;'
\echo ''

COMMIT;

-- Reset session settings modified during installation
-- (prevents state leakage on pooled connections)
RESET timezone;
RESET search_path;
