#!/bin/bash

set -e

export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-54322}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"

DB="${DATABASE_URL:-rrule_perf_pg17}"
RUNS="${PERF_RUNS:-7}"
THRESHOLD="${PERF_THRESHOLD:-0.20}"

cleanup() {
  psql -d postgres -c "DROP DATABASE IF EXISTS ${DB}" > /dev/null 2>&1 || true
}

trap cleanup EXIT

echo "========================================"
echo "PG17 PERFORMANCE REGRESSION CHECK"
echo "========================================"
echo "Database: ${DB}"
echo "Host: ${PGHOST}:${PGPORT}"
echo "Runs: ${RUNS}"
echo "Threshold: ${THRESHOLD}"
echo ""

if ! command -v psql > /dev/null 2>&1; then
  echo "ERROR: psql command not found"
  exit 1
fi

psql -d postgres -c "SELECT 1" > /dev/null

psql -d postgres -c "DROP DATABASE IF EXISTS ${DB}" > /dev/null 2>&1 || true
psql -d postgres -c "CREATE DATABASE ${DB}" > /dev/null

# Install standard API for benchmark workload.
psql -d "${DB}" -f src/install.sql > /dev/null

node scripts/perf-report.js \
  --db "${DB}" \
  --baseline tests/performance/perf_baseline_pg17.json \
  --runs "${RUNS}" \
  --threshold "${THRESHOLD}" \
  "$@"
