#!/bin/bash
#
# PL/pgSQL Profiler Coverage Script
#
# Uses plpgsql_check profiler to measure code coverage of ALL rrule.* PL/pgSQL functions
# by running the full test suite and collecting execution statistics.
#
# Usage:
#   ./scripts/profiler-coverage.sh                    # Run full coverage analysis
#   ./scripts/profiler-coverage.sh <function_name>   # Profile specific function only
#
# Environment variables (with defaults):
#   PGHOST=localhost       # PostgreSQL host
#   PGPORT=54322           # PostgreSQL port
#   PGUSER=postgres        # PostgreSQL user
#   PGPASSWORD=postgres    # PostgreSQL password
#
# Output:
#   - Console summary with coverage statistics
#   - coverage-report.txt with detailed report including uncovered statements
#
# Coverage Notes:
#   The test workload exercises both "generator" and "filter" code paths:
#   - Pure BYWEEKNO rules use rrule_yearly_byweekno_set() as a generator
#   - BYMONTH+BYWEEKNO rules use byweekno_matches_for_year() as a WHERE filter
#   Both paths are tested to ensure full coverage. See ISSUES.md ISSUE-003.
#
# Requirements:
#   - PostgreSQL 17.x with plpgsql_check extension available
#   - plpgsql_check should be in shared_preload_libraries (or LOAD may be needed)
#   - psql command available in PATH
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-54322}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DB="rrule_profiler_coverage"
REPORT_FILE="$PROJECT_DIR/coverage-report.txt"
SINGLE_FUNCTION="${1:-}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PLPGSQL_CHECK PROFILER COVERAGE REPORT${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Database: $DB"
echo "Host: $PGHOST:$PGPORT"
if [ -n "$SINGLE_FUNCTION" ]; then
  echo "Mode: Single function ($SINGLE_FUNCTION)"
else
  echo "Mode: Full coverage (all rrule.* functions)"
fi
echo "Report: $REPORT_FILE"
echo ""

# Check PostgreSQL availability
check_postgres() {
  if ! command -v psql &> /dev/null; then
    echo -e "${RED}ERROR: psql command not found${NC}"
    exit 1
  fi

  if ! psql -d postgres -c "SELECT 1" &> /dev/null; then
    echo -e "${RED}ERROR: Cannot connect to PostgreSQL${NC}"
    exit 1
  fi

  echo -e "${GREEN}[OK] PostgreSQL connection verified${NC}"
}

# Check if plpgsql_check extension is available
check_extension() {
  if ! psql -d postgres -tAc "SELECT 1 FROM pg_available_extensions WHERE name = 'plpgsql_check'" | grep -q 1; then
    echo -e "${RED}ERROR: plpgsql_check extension not available${NC}"
    exit 1
  fi
  echo -e "${GREEN}[OK] plpgsql_check extension available${NC}"
}

# Setup profiler database
setup_database() {
  echo ""
  echo -e "${YELLOW}Setting up profiler database...${NC}"

  # Drop and recreate database
  psql -d postgres -c "DROP DATABASE IF EXISTS $DB" > /dev/null 2>&1 || true
  psql -d postgres -c "CREATE DATABASE $DB" > /dev/null

  # Install plpgsql_check extension and rrule schema (with subday for full coverage)
  psql -d "$DB" -q -c "CREATE EXTENSION IF NOT EXISTS plpgsql_check;" > /dev/null 2>&1
  (cd "$PROJECT_DIR/src" && psql -d "$DB" -f "install_with_subday.sql" > /dev/null 2>&1)

  echo -e "${GREEN}[OK] Database ready with rrule functions (including subday) and plpgsql_check${NC}"
}

# Generate the test SQL that exercises all functions
# This creates a comprehensive test workload without external file dependencies
generate_test_workload() {
  cat << 'TESTEOF'
-- ============================================================================
-- COMPREHENSIVE TEST WORKLOAD FOR PROFILER COVERAGE
-- ============================================================================
-- This exercises all code paths in the rrule schema by running representative
-- test cases from the full test suite.

SET timezone = 'UTC';
SET client_min_messages = WARNING;  -- Reduce noise

DO $$
DECLARE
    result TIMESTAMP[];
    result_tz TIMESTAMPTZ[];
    result_int INT;
    result_bool BOOLEAN;
    test_rrule TEXT;
BEGIN
    -- =========================================================================
    -- SECTION 1: Basic API Functions
    -- =========================================================================

    -- rrule."all"() - basic frequencies
    PERFORM rrule."all"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=WEEKLY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=MONTHLY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);

    -- Sub-day frequencies
    PERFORM rrule."all"('FREQ=HOURLY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=MINUTELY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=SECONDLY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);

    -- rrule."between"()
    PERFORM rrule."between"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP,
                            '2025-01-05 00:00:00'::TIMESTAMP, '2025-01-10 00:00:00'::TIMESTAMP);
    PERFORM rrule."between"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP,
                            '2025-01-05 00:00:00'::TIMESTAMP, '2025-01-10 00:00:00'::TIMESTAMP, true);

    -- rrule."after"() and rrule."before"()
    PERFORM rrule."after"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP, '2025-01-15 00:00:00'::TIMESTAMP);
    PERFORM rrule."after"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP, '2025-01-15 10:00:00'::TIMESTAMP, true);
    PERFORM rrule."before"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP, '2025-01-15 00:00:00'::TIMESTAMP);
    PERFORM rrule."before"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP, '2025-01-15 10:00:00'::TIMESTAMP, true);

    -- rrule."next"() and rrule."most_recent"()
    PERFORM rrule."next"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."most_recent"('FREQ=DAILY;COUNT=100', '2025-01-01 10:00:00'::TIMESTAMP);

    -- rrule."count"()
    PERFORM rrule."count"('FREQ=DAILY;COUNT=50', '2025-01-01 10:00:00'::TIMESTAMP);

    -- rrule."overlaps"() (uses TIMESTAMPTZ, explicitly call 6-arg version with NULL timezone)
    PERFORM rrule."overlaps"(
        '2025-01-01 10:00:00+00'::TIMESTAMPTZ, '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
        'FREQ=DAILY;COUNT=10'::TEXT, '2025-01-01 00:00:00+00'::TIMESTAMPTZ, '2025-01-31 23:59:59+00'::TIMESTAMPTZ,
        NULL::TEXT  -- timezone parameter (disambiguates from 5-arg version)
    );

    -- =========================================================================
    -- SECTION 2: TIMESTAMPTZ API
    -- =========================================================================
    -- Signatures:
    --   all(rrule, dtstart, timezone)
    --   between(rrule, dtstart, range_start, range_end, timezone, inc)
    --   after(rrule, dtstart, after_date, count, timezone, inc)
    --   before(rrule, dtstart, before_date, count, timezone, inc)
    --   next(rrule, dtstart, timezone, reference_time)
    --   most_recent(rrule, dtstart, timezone, reference_time)
    --   count(rrule, dtstart, timezone)

    PERFORM rrule."all"('FREQ=DAILY;COUNT=5'::TEXT, '2025-01-01 10:00:00-05'::TIMESTAMPTZ, 'America/New_York'::TEXT);
    PERFORM rrule."between"('FREQ=DAILY;COUNT=100'::TEXT, '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
                            '2025-01-05 00:00:00-05'::TIMESTAMPTZ, '2025-01-10 00:00:00-05'::TIMESTAMPTZ,
                            'America/New_York'::TEXT, false);
    PERFORM rrule."after"('FREQ=DAILY;COUNT=100'::TEXT, '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
                          '2025-01-15 00:00:00-05'::TIMESTAMPTZ, 1, 'America/New_York'::TEXT, false);
    PERFORM rrule."before"('FREQ=DAILY;COUNT=100'::TEXT, '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
                           '2025-01-15 00:00:00-05'::TIMESTAMPTZ, 1, 'America/New_York'::TEXT, false);
    PERFORM rrule."next"('FREQ=DAILY;COUNT=100'::TEXT, '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
                         'America/New_York'::TEXT, '2025-01-01 10:00:00-05'::TIMESTAMPTZ);
    PERFORM rrule."most_recent"('FREQ=DAILY;COUNT=100'::TEXT, '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
                                'America/New_York'::TEXT, '2025-01-15 10:00:00-05'::TIMESTAMPTZ);
    PERFORM rrule."count"('FREQ=DAILY;COUNT=50'::TEXT, '2025-01-01 10:00:00-05'::TIMESTAMPTZ, 'America/New_York'::TEXT);

    -- =========================================================================
    -- SECTION 3: BYDAY with all frequencies
    -- =========================================================================

    PERFORM rrule."all"('FREQ=DAILY;BYDAY=MO,WE,FR;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=MONTHLY;BYDAY=MO;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=MONTHLY;BYDAY=1MO;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);  -- First Monday
    PERFORM rrule."all"('FREQ=MONTHLY;BYDAY=-1FR;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP); -- Last Friday
    PERFORM rrule."all"('FREQ=YEARLY;BYDAY=MO;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;BYDAY=1MO,-1FR;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 4: BYMONTHDAY
    -- =========================================================================

    PERFORM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=15;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=1,15,-1;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTHDAY=15;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=DAILY;BYMONTHDAY=1,15;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 5: BYMONTH
    -- =========================================================================

    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=1,6,12;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=MONTHLY;BYMONTH=3,6,9,12;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=DAILY;BYMONTH=1;COUNT=31', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=WEEKLY;BYMONTH=1,7;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 6: BYYEARDAY
    -- =========================================================================

    PERFORM rrule."all"('FREQ=YEARLY;BYYEARDAY=1,100,200,365;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;BYYEARDAY=-1;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);  -- Last day of year

    -- =========================================================================
    -- SECTION 7: BYWEEKNO
    -- =========================================================================

    PERFORM rrule."all"('FREQ=YEARLY;BYWEEKNO=1,20,52;COUNT=10', '2025-01-06 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO;COUNT=5', '2025-01-06 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;BYWEEKNO=-1;COUNT=5', '2025-01-06 10:00:00'::TIMESTAMP);
    -- BYMONTH+BYWEEKNO: exercises byweekno_matches_for_year() as WHERE filter (ISSUE-003)
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=1,7;BYWEEKNO=1,26;COUNT=20', '2025-01-06 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 8: BYSETPOS
    -- =========================================================================

    PERFORM rrule."all"('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=1,7;BYDAY=SU;BYSETPOS=1;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=1,2,3,4,5,6,7;BYDAY=MO;BYSETPOS=1;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,2,3,-3,-2,-1;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 9: WKST (Week Start)
    -- =========================================================================

    PERFORM rrule."all"('FREQ=WEEKLY;WKST=SU;BYDAY=TU,TH;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=WEEKLY;WKST=MO;BYDAY=TU,TH;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;BYWEEKNO=1;WKST=SU;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 10: INTERVAL
    -- =========================================================================

    PERFORM rrule."all"('FREQ=DAILY;INTERVAL=2;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=WEEKLY;INTERVAL=2;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=MONTHLY;INTERVAL=3;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;INTERVAL=2;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=HOURLY;INTERVAL=6;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 11: UNTIL
    -- =========================================================================

    PERFORM rrule."all"('FREQ=DAILY;UNTIL=20250110T100000Z', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=WEEKLY;UNTIL=20250301T000000Z', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=MONTHLY;UNTIL=20251231T235959Z', '2025-01-01 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 12: TZID
    -- =========================================================================

    PERFORM rrule."all"('FREQ=DAILY;COUNT=5;TZID=America/New_York', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=DAILY;COUNT=5;TZID=Europe/London', '2025-03-30 01:30:00'::TIMESTAMP);  -- DST transition
    PERFORM rrule."all"('FREQ=DAILY;COUNT=5;TZID=America/Los_Angeles', '2025-03-09 02:30:00'::TIMESTAMP);  -- DST gap

    -- =========================================================================
    -- SECTION 13: SKIP (RFC 7529)
    -- =========================================================================

    -- MONTHLY SKIP cases
    PERFORM rrule."all"('FREQ=MONTHLY;SKIP=OMIT;COUNT=5', '2025-01-31 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=MONTHLY;SKIP=BACKWARD;COUNT=5', '2025-01-31 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=MONTHLY;SKIP=FORWARD;COUNT=5', '2025-01-31 10:00:00'::TIMESTAMP);

    -- YEARLY SKIP cases (Feb 29)
    PERFORM rrule."all"('FREQ=YEARLY;SKIP=OMIT;COUNT=5', '2024-02-29 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;SKIP=BACKWARD;COUNT=5', '2024-02-29 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;SKIP=FORWARD;COUNT=5', '2024-02-29 10:00:00'::TIMESTAMP);

    -- YEARLY+BYMONTH SKIP cases
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=2;SKIP=OMIT;COUNT=5', '2024-02-29 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=2;SKIP=BACKWARD;COUNT=5', '2024-02-29 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=2;SKIP=FORWARD;COUNT=5', '2024-02-29 10:00:00'::TIMESTAMP);

    -- SKIP with INTERVAL > 1
    PERFORM rrule."all"('FREQ=MONTHLY;INTERVAL=2;SKIP=BACKWARD;COUNT=10', '2025-01-31 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;INTERVAL=2;SKIP=BACKWARD;COUNT=5', '2024-02-29 10:00:00'::TIMESTAMP);

    -- DoS protection: impossible dates that trigger period limit termination
    -- Feb 30 never exists - forces OMIT/FORWARD to hit period_limit
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;SKIP=OMIT;COUNT=5', '2020-02-15 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;SKIP=FORWARD;COUNT=5', '2020-02-15 10:00:00'::TIMESTAMP);
    -- Apr 31 never exists
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=4;BYMONTHDAY=31;SKIP=OMIT;COUNT=5', '2020-04-15 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=4;BYMONTHDAY=31;SKIP=FORWARD;COUNT=5', '2020-04-15 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 14: Complex Combinations
    -- =========================================================================

    -- Quarterly reports: First Monday of each quarter
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=1,4,7,10;BYDAY=1MO;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

    -- Bi-weekly team meetings on Tuesday and Thursday
    PERFORM rrule."all"('FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP);

    -- Last Friday of every other month
    PERFORM rrule."all"('FREQ=MONTHLY;INTERVAL=2;BYDAY=-1FR;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

    -- 2nd and 4th Wednesday of each month
    PERFORM rrule."all"('FREQ=MONTHLY;BYDAY=2WE,4WE;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP);

    -- Every weekday
    PERFORM rrule."all"('FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=30', '2025-01-01 10:00:00'::TIMESTAMP);

    -- Thanksgiving (4th Thursday of November)
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 15: Edge Cases and Boundary Conditions
    -- =========================================================================

    -- Empty result set (UNTIL before DTSTART)
    PERFORM rrule."all"('FREQ=DAILY;UNTIL=20241231T000000Z', '2025-01-01 10:00:00'::TIMESTAMP);

    -- COUNT=1
    PERFORM rrule."all"('FREQ=DAILY;COUNT=1', '2025-01-01 10:00:00'::TIMESTAMP);

    -- Large COUNT (tests cap)
    PERFORM rrule."all"('FREQ=DAILY;COUNT=2000', '2025-01-01 10:00:00'::TIMESTAMP);

    -- Negative BYMONTHDAY
    PERFORM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=-1,-2,-3;COUNT=15', '2025-01-01 10:00:00'::TIMESTAMP);

    -- Feb 29 in non-leap year handling
    PERFORM rrule."all"('FREQ=MONTHLY;COUNT=12', '2024-02-29 10:00:00'::TIMESTAMP);

    -- Month-end dates
    PERFORM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=30;COUNT=12', '2025-01-30 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=31;COUNT=12', '2025-01-31 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 16: Internal Helper Functions (via indirect calls)
    -- =========================================================================

    -- Test weekday_to_number by using BYDAY with all days
    PERFORM rrule."all"('FREQ=WEEKLY;BYDAY=SU,MO,TU,WE,TH,FR,SA;COUNT=14', '2025-01-01 10:00:00'::TIMESTAMP);

    -- Test byweekno_matches via BYWEEKNO
    PERFORM rrule."all"('FREQ=YEARLY;BYWEEKNO=53;COUNT=5', '2020-12-28 10:00:00'::TIMESTAMP);

    -- Test parse_rrule_parts via complex rules
    PERFORM rrule."all"('FREQ=YEARLY;INTERVAL=1;BYMONTH=3;BYMONTHDAY=15;BYDAY=MO,TU,WE,TH,FR;WKST=MO;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 17: Time filter paths (BYHOUR/BYMINUTE/BYSECOND with DAILY)
    -- =========================================================================

    PERFORM rrule."all"('FREQ=DAILY;BYHOUR=9,17;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=DAILY;BYMINUTE=0,30;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);
    PERFORM rrule."all"('FREQ=DAILY;BYSECOND=0;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 18: Validation paths (error handling)
    -- =========================================================================

    -- These should raise exceptions - wrapped in BEGIN/EXCEPTION
    BEGIN
        PERFORM rrule."all"('FREQ=WEEKLY;BYMONTHDAY=15;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);
    EXCEPTION WHEN raise_exception THEN
        NULL;  -- Expected error
    END;

    BEGIN
        PERFORM rrule."all"('FREQ=YEARLY;BYWEEKNO=1;BYDAY=2MO;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);
    EXCEPTION WHEN raise_exception THEN
        NULL;  -- Expected error
    END;

    BEGIN
        PERFORM rrule."all"('INVALID_RRULE', '2025-01-01 10:00:00'::TIMESTAMP);
    EXCEPTION WHEN raise_exception THEN
        NULL;  -- Expected error
    END;

    BEGIN
        PERFORM rrule."all"('FREQ=DAILY;COUNT=5;UNTIL=20250110T000000Z', '2025-01-01 10:00:00'::TIMESTAMP);
    EXCEPTION WHEN raise_exception THEN
        NULL;  -- Expected error (COUNT and UNTIL both present)
    END;

    -- =========================================================================
    -- SECTION 19: All frequency branches with various BYxxx combinations
    -- =========================================================================

    -- DAILY with all compatible BYxxx
    PERFORM rrule."all"('FREQ=DAILY;BYDAY=MO;BYMONTH=1;BYMONTHDAY=6,13,20,27;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);

    -- WEEKLY with compatible BYxxx
    PERFORM rrule."all"('FREQ=WEEKLY;BYDAY=MO,WE,FR;BYMONTH=1,2,3;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP);

    -- MONTHLY with BYDAY ordinal + BYMONTH
    PERFORM rrule."all"('FREQ=MONTHLY;BYDAY=2TU;BYMONTH=1,4,7,10;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

    -- MONTHLY with BYMONTHDAY only
    PERFORM rrule."all"('FREQ=MONTHLY;BYMONTHDAY=1,15;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP);

    -- YEARLY with BYYEARDAY
    PERFORM rrule."all"('FREQ=YEARLY;BYYEARDAY=1,60,120,180,240,300,365;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP);

    -- YEARLY with BYWEEKNO and BYDAY
    PERFORM rrule."all"('FREQ=YEARLY;BYWEEKNO=1,26,52;BYDAY=MO,FR;COUNT=20', '2025-01-06 10:00:00'::TIMESTAMP);

    -- YEARLY with BYMONTH and BYMONTHDAY
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=6,12;BYMONTHDAY=15;COUNT=10', '2025-01-01 10:00:00'::TIMESTAMP);

    -- YEARLY with BYMONTH and BYDAY
    PERFORM rrule."all"('FREQ=YEARLY;BYMONTH=1,7;BYDAY=SU;COUNT=20', '2025-01-01 10:00:00'::TIMESTAMP);

    -- =========================================================================
    -- SECTION 20: Test version() function
    -- =========================================================================

    PERFORM rrule.version();

    -- =========================================================================
    -- SECTION 21: DoS protection branch coverage for _advance_yearly()
    -- =========================================================================
    -- These direct function calls exercise the DoS protection branches
    -- that can't be reached via public API (10-year window terminates first)
    DECLARE
        dos_result rrule._skip_result;
        dos_base TIMESTAMPTZ := '2021-02-28 10:00:00'::TIMESTAMPTZ;
        dos_basedate TIMESTAMPTZ := '2020-02-28 10:00:00'::TIMESTAMPTZ;
        dos_i INT;
    BEGIN
        -- Test OMIT limit branch (lines 1598-1600)
        dos_result.omit_count := 0;
        dos_result.period_count := 0;
        dos_result.done := FALSE;
        FOR dos_i IN 1..15 LOOP
            EXIT WHEN dos_result.done;
            dos_result := rrule._advance_yearly(
                dos_base, dos_basedate, 30, 1, 'OMIT', NULL,
                '2100-01-01'::TIMESTAMPTZ, 10,
                dos_result.omit_count, dos_result.period_count
            );
            dos_base := dos_result.current_base;
        END LOOP;

        -- Test FORWARD limit branch (lines 1620-1623)
        dos_base := '2021-02-28 10:00:00'::TIMESTAMPTZ;
        dos_result.omit_count := 0;
        dos_result.period_count := 0;
        dos_result.done := FALSE;
        FOR dos_i IN 1..15 LOOP
            EXIT WHEN dos_result.done;
            dos_result := rrule._advance_yearly(
                dos_base, dos_basedate, 30, 1, 'FORWARD', NULL,
                '2100-01-01'::TIMESTAMPTZ, 10,
                dos_result.omit_count, dos_result.period_count
            );
            dos_base := dos_result.current_base;
        END LOOP;

        -- Test OMIT + maxdate termination (lines 1589-1590)
        -- maxdate only 2 years away, will be exceeded before period_limit
        dos_base := '2021-02-28 10:00:00'::TIMESTAMPTZ;
        dos_result.omit_count := 0;
        dos_result.period_count := 0;
        dos_result.done := FALSE;
        FOR dos_i IN 1..5 LOOP
            EXIT WHEN dos_result.done;
            dos_result := rrule._advance_yearly(
                dos_base, dos_basedate, 30, 1, 'OMIT', NULL,
                '2023-01-01'::TIMESTAMPTZ, 100,
                dos_result.omit_count, dos_result.period_count
            );
            dos_base := dos_result.current_base;
        END LOOP;

        -- Test OMIT + UNTIL termination (lines 1593-1594)
        -- UNTIL only 2 years away, will be exceeded before period_limit
        dos_base := '2021-02-28 10:00:00'::TIMESTAMPTZ;
        dos_result.omit_count := 0;
        dos_result.period_count := 0;
        dos_result.done := FALSE;
        FOR dos_i IN 1..5 LOOP
            EXIT WHEN dos_result.done;
            dos_result := rrule._advance_yearly(
                dos_base, dos_basedate, 30, 1, 'OMIT',
                '2023-01-01'::TIMESTAMPTZ,
                '2100-01-01'::TIMESTAMPTZ, 100,
                dos_result.omit_count, dos_result.period_count
            );
            dos_base := dos_result.current_base;
        END LOOP;

        -- Test FORWARD + UNTIL termination (lines 1608-1610)
        -- UNTIL before forward_ts (Mar 1), terminates immediately
        dos_result := rrule._advance_yearly(
            '2021-02-28 10:00:00'::TIMESTAMPTZ, dos_basedate,
            30, 1, 'FORWARD',
            '2021-02-28 10:00:00'::TIMESTAMPTZ,
            '2100-01-01'::TIMESTAMPTZ, 100, 0, 0
        );

        -- Test FORWARD + maxdate termination (lines 1613-1615)
        -- maxdate before forward_ts (Mar 1), terminates immediately
        dos_result := rrule._advance_yearly(
            '2021-02-28 10:00:00'::TIMESTAMPTZ, dos_basedate,
            30, 1, 'FORWARD', NULL,
            '2021-02-28 10:00:00'::TIMESTAMPTZ, 100, 0, 0
        );
    END;

    -- =========================================================================
    -- SECTION 22: DoS protection branch coverage for _advance_monthly()
    -- =========================================================================
    -- Use day 32 which NEVER exists in any month - forces continuous OMIT/FORWARD
    DECLARE
        mon_result rrule._skip_result;
        mon_base TIMESTAMPTZ := '2020-02-29 10:00:00'::TIMESTAMPTZ;
        mon_basedate TIMESTAMPTZ := '2020-01-31 10:00:00'::TIMESTAMPTZ;
        mon_i INT;
    BEGIN
        -- Test OMIT limit branch (lines 1502-1503)
        mon_result.omit_count := 0;
        mon_result.period_count := 0;
        mon_result.done := FALSE;
        FOR mon_i IN 1..15 LOOP
            EXIT WHEN mon_result.done;
            mon_result := rrule._advance_monthly(
                mon_base, mon_basedate, 32, 1, 'OMIT', NULL,
                '2100-01-01'::TIMESTAMPTZ, 10,
                mon_result.omit_count, mon_result.period_count
            );
            mon_base := mon_result.current_base;
        END LOOP;

        -- Test FORWARD limit branch (lines 1524-1526)
        mon_base := '2020-02-29 10:00:00'::TIMESTAMPTZ;
        mon_result.omit_count := 0;
        mon_result.period_count := 0;
        mon_result.done := FALSE;
        FOR mon_i IN 1..15 LOOP
            EXIT WHEN mon_result.done;
            mon_result := rrule._advance_monthly(
                mon_base, mon_basedate, 32, 1, 'FORWARD', NULL,
                '2100-01-01'::TIMESTAMPTZ, 10,
                mon_result.omit_count, mon_result.period_count
            );
            mon_base := mon_result.current_base;
        END LOOP;

        -- Test OMIT + maxdate termination (lines 1493-1494)
        mon_base := '2020-02-29 10:00:00'::TIMESTAMPTZ;
        mon_result.omit_count := 0;
        mon_result.period_count := 0;
        mon_result.done := FALSE;
        FOR mon_i IN 1..5 LOOP
            EXIT WHEN mon_result.done;
            mon_result := rrule._advance_monthly(
                mon_base, mon_basedate, 32, 1, 'OMIT', NULL,
                '2020-04-01'::TIMESTAMPTZ, 100,
                mon_result.omit_count, mon_result.period_count
            );
            mon_base := mon_result.current_base;
        END LOOP;

        -- Test OMIT + UNTIL termination (lines 1497-1498)
        mon_base := '2020-02-29 10:00:00'::TIMESTAMPTZ;
        mon_result.omit_count := 0;
        mon_result.period_count := 0;
        mon_result.done := FALSE;
        FOR mon_i IN 1..5 LOOP
            EXIT WHEN mon_result.done;
            mon_result := rrule._advance_monthly(
                mon_base, mon_basedate, 32, 1, 'OMIT',
                '2020-04-01'::TIMESTAMPTZ,
                '2100-01-01'::TIMESTAMPTZ, 100,
                mon_result.omit_count, mon_result.period_count
            );
            mon_base := mon_result.current_base;
        END LOOP;

        -- Test FORWARD + UNTIL termination (lines 1512-1514)
        mon_result := rrule._advance_monthly(
            '2020-02-29 10:00:00'::TIMESTAMPTZ, mon_basedate,
            32, 1, 'FORWARD',
            '2020-02-29 10:00:00'::TIMESTAMPTZ,
            '2100-01-01'::TIMESTAMPTZ, 100, 0, 0
        );

        -- Test FORWARD + maxdate termination (lines 1517-1519)
        mon_result := rrule._advance_monthly(
            '2020-02-29 10:00:00'::TIMESTAMPTZ, mon_basedate,
            32, 1, 'FORWARD', NULL,
            '2020-02-29 10:00:00'::TIMESTAMPTZ, 100, 0, 0
        );
    END;

END;
$$;
TESTEOF
}

# Run profiled tests and generate report - ALL IN ONE SESSION
run_profiled_tests_and_report() {
  echo ""
  echo -e "${YELLOW}Running profiled tests (this may take a minute)...${NC}"
  echo ""

  # Determine what to profile
  if [ -n "$SINGLE_FUNCTION" ]; then
    FUNCTION_FILTER="AND p.proname = '${SINGLE_FUNCTION#rrule.}'"
    REPORT_TITLE="COVERAGE REPORT FOR: $SINGLE_FUNCTION"
  else
    FUNCTION_FILTER=""
    REPORT_TITLE="FULL COVERAGE REPORT FOR ALL rrule.* FUNCTIONS"
  fi

  # Generate test workload SQL
  TEST_SQL=$(generate_test_workload)

  # Run everything in a single psql session to preserve profiler state
  psql -d "$DB" -t -A << EOFMAIN > "$REPORT_FILE"
-- Enable the profiler for this session
SET plpgsql_check.profiler TO on;

-- Run test workload
$TEST_SQL

-- ============================================================================
-- COVERAGE REPORT
-- ============================================================================

\echo ''
\echo '=============================================================================='
\echo '$REPORT_TITLE'
\echo 'Generated: $(date "+%Y-%m-%d %H:%M:%S")'
\echo '=============================================================================='
\echo ''

-- Create temp table to hold all function coverage data
CREATE TEMP TABLE coverage_data (
    function_name TEXT,
    total_statements INT,
    executed_statements INT,
    uncovered_statements INT,
    coverage_pct NUMERIC(5,2)
);

-- Create temp table to hold uncovered statement details
CREATE TEMP TABLE uncovered_details (
    function_name TEXT,
    lineno INT,
    stmtname TEXT,
    parent_note TEXT
);

-- Enumerate all rrule functions and collect profiler data
DO \$\$
DECLARE
    func_rec RECORD;
    v_total_stmts INT;
    v_exec_stmts INT;
BEGIN
    FOR func_rec IN
        SELECT n.nspname || '.' || p.proname AS full_name,
               p.oid,
               pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'rrule'
          AND p.prokind = 'f'  -- Only functions (not aggregates)
          $FUNCTION_FILTER
        ORDER BY p.proname
    LOOP
        BEGIN
            -- Get statement counts (use table alias to avoid ambiguity with profiler's exec_stmts column)
            SELECT
                COUNT(*),
                COUNT(*) FILTER (WHERE pf.exec_stmts > 0)
            INTO v_total_stmts, v_exec_stmts
            FROM plpgsql_profiler_function_statements_tb(func_rec.oid) pf;

            IF v_total_stmts > 0 THEN
                INSERT INTO coverage_data (function_name, total_statements, executed_statements, uncovered_statements, coverage_pct)
                VALUES (
                    func_rec.full_name || '(' || func_rec.args || ')',
                    v_total_stmts,
                    v_exec_stmts,
                    v_total_stmts - v_exec_stmts,
                    ROUND(100.0 * v_exec_stmts / v_total_stmts, 2)
                );

                -- Collect uncovered statements
                INSERT INTO uncovered_details (function_name, lineno, stmtname, parent_note)
                SELECT
                    func_rec.full_name || '(' || func_rec.args || ')',
                    pf.lineno,
                    pf.stmtname,
                    pf.parent_note
                FROM plpgsql_profiler_function_statements_tb(func_rec.oid) pf
                WHERE pf.exec_stmts = 0;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Skip functions that don't have profiler data (e.g., SQL functions)
            NULL;
        END;
    END LOOP;
END;
\$\$;

\echo '=============================================================================='
\echo 'OVERALL SUMMARY'
\echo '=============================================================================='
\echo ''

SELECT
    'Total Functions Profiled: ' || COUNT(DISTINCT function_name)::TEXT AS info
FROM coverage_data
UNION ALL
SELECT
    'Total Statements: ' || SUM(total_statements)::TEXT
FROM coverage_data
UNION ALL
SELECT
    'Executed Statements: ' || SUM(executed_statements)::TEXT
FROM coverage_data
UNION ALL
SELECT
    'Uncovered Statements: ' || SUM(uncovered_statements)::TEXT
FROM coverage_data
UNION ALL
SELECT
    'Overall Coverage: ' ||
    ROUND(100.0 * SUM(executed_statements) / NULLIF(SUM(total_statements), 0), 2)::TEXT || '%'
FROM coverage_data;

\echo ''
\echo '=============================================================================='
\echo 'PER-FUNCTION COVERAGE'
\echo '=============================================================================='
\echo ''

SELECT
    function_name,
    total_statements AS total,
    executed_statements AS exec,
    uncovered_statements AS uncov,
    coverage_pct::TEXT || '%' AS coverage
FROM coverage_data
ORDER BY coverage_pct ASC, function_name;

\echo ''
\echo '=============================================================================='
\echo 'UNCOVERED STATEMENTS (exec_stmts = 0)'
\echo '=============================================================================='
\echo ''

SELECT
    function_name,
    lineno,
    stmtname,
    COALESCE(parent_note, '') AS context
FROM uncovered_details
ORDER BY function_name, lineno;

\echo ''
\echo '=============================================================================='
\echo 'FUNCTIONS WITH 100% COVERAGE'
\echo '=============================================================================='
\echo ''

SELECT function_name
FROM coverage_data
WHERE coverage_pct = 100.00
ORDER BY function_name;

\echo ''
\echo '=============================================================================='
\echo 'FUNCTIONS WITH <100% COVERAGE (NEED ATTENTION)'
\echo '=============================================================================='
\echo ''

SELECT
    function_name,
    total_statements AS total,
    uncovered_statements AS uncov,
    coverage_pct::TEXT || '%' AS coverage
FROM coverage_data
WHERE coverage_pct < 100.00
ORDER BY coverage_pct ASC, function_name;

\echo ''
\echo '=============================================================================='
\echo 'END OF REPORT'
\echo '=============================================================================='
EOFMAIN

  echo -e "${GREEN}[OK] Profiling complete${NC}"
  echo ""

  # Display summary to console
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}COVERAGE SUMMARY${NC}"
  echo -e "${BLUE}========================================${NC}"

  # Extract key stats from report
  grep -A 20 "OVERALL SUMMARY" "$REPORT_FILE" | head -25 || true

  echo ""
  echo -e "${CYAN}Full report saved to: $REPORT_FILE${NC}"
}

# Cleanup
cleanup() {
  echo ""
  echo -e "${YELLOW}Cleaning up...${NC}"
  psql -d postgres -c "DROP DATABASE IF EXISTS $DB" > /dev/null 2>&1 || true
  echo -e "${GREEN}[OK] Cleanup complete${NC}"
}

# Main
main() {
  check_postgres
  check_extension
  setup_database
  run_profiled_tests_and_report
  cleanup

  echo ""
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}PROFILER COVERAGE COMPLETE${NC}"
  echo -e "${GREEN}========================================${NC}"
}

main
