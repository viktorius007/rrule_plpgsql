#!/bin/bash
#
# PL/pgSQL Linter for rrule_plpgsql
#
# Validates all rrule functions using the plpgsql_check PostgreSQL extension.
# This catches semantic errors, type mismatches, and other issues before runtime.
#
# Runs two lint passes:
#   Pass 1: Standard installation (install.sql) — DAILY/WEEKLY/MONTHLY/YEARLY
#   Pass 2: Subday installation (install_with_subday.sql) — includes HOURLY/MINUTELY/SECONDLY
#
# Usage:
#   ./lint.sh              # Run linter
#   pnpm lint              # Run via pnpm
#
# Environment variables (with defaults):
#   PGHOST=localhost       # PostgreSQL host
#   PGPORT=54322           # PostgreSQL port (default: Supabase local)
#   PGUSER=postgres        # PostgreSQL user
#   PGPASSWORD=postgres    # PostgreSQL password
#   DATABASE_URL=<name>    # Override database name (default: rrule_lint_{branch})
#
# Requirements:
#   - PostgreSQL 17.x with plpgsql_check extension available
#   - psql command available in PATH
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-54322}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"

_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/-.' '_' || echo "default")
DB="${DATABASE_URL:-rrule_lint_${_BRANCH}}"

# Acquire per-database lock to prevent concurrent lint runs against the same DB.
# If another process holds the lock, exit silently (e.g., stop hook overlapping with agent).
# Uses mkdir (atomic on all platforms) instead of flock (not available on macOS).
LOCKDIR="/tmp/${DB}.lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    # Check if the holding process is still alive; clean up stale locks
    if [ -f "$LOCKDIR/pid" ] && kill -0 "$(cat "$LOCKDIR/pid")" 2>/dev/null; then
        exit 0
    fi
    rm -rf "$LOCKDIR"
    mkdir "$LOCKDIR" 2>/dev/null || exit 0
fi
echo $$ > "$LOCKDIR/pid"
trap 'rm -rf "$LOCKDIR"' EXIT

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PLPGSQL_CHECK LINTER${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Database: $DB"
echo "Host: $PGHOST:$PGPORT"
echo ""

# Check PostgreSQL availability
check_postgres() {
  if ! command -v psql &> /dev/null; then
    echo -e "${RED}ERROR: psql command not found${NC}"
    echo "Please install PostgreSQL and ensure psql is in your PATH"
    exit 1
  fi

  if ! psql -d postgres -c "SELECT 1" &> /dev/null; then
    echo -e "${RED}ERROR: Cannot connect to PostgreSQL${NC}"
    echo "Please ensure PostgreSQL is running and accessible"
    exit 1
  fi

  echo -e "${GREEN}✓ PostgreSQL connection verified${NC}"
}

# Check if plpgsql_check extension is available
check_extension() {
  if ! psql -d postgres -tAc "SELECT 1 FROM pg_available_extensions WHERE name = 'plpgsql_check'" | grep -q 1; then
    echo -e "${YELLOW}WARNING: plpgsql_check extension not available${NC}"
    echo "Install plpgsql_check or enable it in your PostgreSQL instance"
    echo ""
    echo "For Supabase, enable it in the dashboard under Database > Extensions"
    echo "For local PostgreSQL: https://github.com/okbob/plpgsql_check#installation"
    echo ""
    exit 1
  fi
  echo -e "${GREEN}✓ plpgsql_check extension available${NC}"
}

# Setup lint database with a given install script
# $1 = install script filename (default: install.sql)
# Returns 0 on success, 1 on failure
setup_database() {
  local install_script="${1:-install.sql}"
  echo ""
  echo -e "${YELLOW}Setting up lint database (${install_script})...${NC}"

  # Drop and recreate database
  psql -d postgres -c "DROP DATABASE IF EXISTS $DB" > /dev/null 2>&1 || true
  psql -d postgres -c "CREATE DATABASE $DB" > /dev/null

  # Install rrule schema (install scripts expect to be run from src/ directory)
  # Capture output so install errors are visible and detectable
  local install_output
  if install_output=$(cd src && psql -d "$DB" -f "$install_script" 2>&1); then
    echo -e "${GREEN}✓ Lint database ready${NC}"
    return 0
  else
    echo -e "${RED}ERROR: Installation failed for ${install_script}${NC}"
    echo "$install_output" | tail -10
    return 1
  fi
}

# Run linter
run_lint() {
  echo ""
  echo -e "${BLUE}Running plpgsql_check on all functions...${NC}"
  echo ""

  if psql -d "$DB" -f lint.sql 2>&1; then
    return 0
  else
    return 1
  fi
}

# Cleanup
cleanup() {
  echo ""
  echo -e "${YELLOW}Cleaning up...${NC}"
  psql -d postgres -c "DROP DATABASE IF EXISTS $DB" > /dev/null 2>&1 || true
  echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Run a single lint pass
# $1 = pass label (e.g., "Pass 1: standard installation")
# $2 = install script filename
# Returns 0 on success, 1 on failure
run_lint_pass() {
  local label="$1"
  local install_script="$2"

  echo ""
  echo -e "${BLUE}=== Lint ${label} ===${NC}"

  if ! setup_database "$install_script"; then
    echo -e "${RED}${label} FAILED (installation error)${NC}"
    return 1
  fi

  if run_lint; then
    echo -e "${GREEN}${label} PASSED${NC}"
    return 0
  else
    echo -e "${RED}${label} FAILED${NC}"
    return 1
  fi
}

# Main
main() {
  check_postgres
  check_extension

  local exit_code=0

  # === Lint pass 1: standard installation ===
  if ! run_lint_pass "pass 1: standard installation" "install.sql"; then
    exit_code=1
  fi

  # === Lint pass 2: subday installation ===
  if ! run_lint_pass "pass 2: subday installation" "install_with_subday.sql"; then
    exit_code=1
  fi

  # Final summary
  echo ""
  if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}LINTING PASSED (both standard and subday)${NC}"
  else
    echo -e "${RED}LINTING FAILED${NC}"
  fi

  cleanup
  exit $exit_code
}

main
