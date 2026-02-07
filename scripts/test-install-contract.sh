#!/bin/bash

set -e

export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-54322}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"

DB="${DATABASE_URL:-rrule_install_contract}"
TEST_FILES=(
  "tests/install/test_install_contract.sql"
  "tests/install/test_migration_contract.sql"
)

run_mode() {
  local install_script="$1"
  local mode_label="$2"

  echo ""
  echo "=== ${mode_label} ==="

  psql -d postgres -c "DROP DATABASE IF EXISTS ${DB}" > /dev/null 2>&1 || true
  psql -d postgres -c "CREATE DATABASE ${DB}" > /dev/null

  for test_file in "${TEST_FILES[@]}"; do
    echo "Running ${test_file}"
    psql -d "${DB}" -v rrule_install="${install_script}" -f "${test_file}" > /dev/null
  done
}

run_mode "src/install.sql" "Standard install contract tests"
run_mode "src/install_with_subday.sql" "Sub-day install contract tests"

echo ""
echo "Install contract tests passed."
