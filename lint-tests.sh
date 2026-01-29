#!/bin/bash
#
# Static SQL Linter for rrule_plpgsql coding standards
#
# Enforces project conventions defined in CLAUDE.md Development Rules
# against all .sql files. Pure bash — no database connection required.
#
# Usage:
#   ./lint-tests.sh          # Run all checks
#   npm run lint:tests       # Run via npm
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_VIOLATIONS=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}STATIC SQL LINTER${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# --- Utility functions ---

report_violation() {
  local file="$1"
  local line="$2"
  local message="$3"
  echo -e "  ${RED}✗${NC} ${file}:${line} — ${message}"
  TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + 1))
}

report_rule_result() {
  local rule_name="$1"
  local violation_count="$2"
  if [ "$violation_count" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} ${rule_name}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "${RED}✗${NC} ${rule_name} (${violation_count} violation(s))"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  echo ""
}

# Helper: filter grep -n output to exclude comment lines.
# Input: "lineno:content" lines from grep -n
# Filters out lines where content starts with -- or * (SQL comments / block comment bodies)
filter_comments() {
  grep -v '^[0-9]*:[[:space:]]*--' | grep -v '^[0-9]*:[[:space:]]*\*' || true
}

# --- Check functions ---
# All rules enforced here are defined in CLAUDE.md Development Rules.
# Test file checks enforce Rule 8 (Testing Standards).
# Source file checks enforce Rules 2, 5, 6, and 7.

# Rule 8: No COMMIT in test files
check_no_commit() {
  local count=0
  for file in tests/test_*.sql; do
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      report_violation "$file" "$lineno" "COMMIT; found — use ROLLBACK instead"
      count=$((count + 1))
    done < <(grep -n '.' "$file" | filter_comments | grep -iE 'COMMIT[[:space:]]*;' | grep -viE 'ROLLBACK' || true)
  done
  report_rule_result "No COMMIT in test files (Rule 8)" "$count"
}

# Rule 8: Every test file must have BEGIN and ROLLBACK
check_transaction_wrapper() {
  local count=0
  for file in tests/test_*.sql; do
    if ! grep -q '^BEGIN;' "$file"; then
      report_violation "$file" "1" "Missing BEGIN; — test files must be wrapped in BEGIN; ... ROLLBACK;"
      count=$((count + 1))
    fi
    if ! grep -q '^ROLLBACK;' "$file"; then
      local last_line
      last_line=$(wc -l < "$file" | tr -d ' ')
      report_violation "$file" "$last_line" "Missing ROLLBACK; — test files must end with ROLLBACK;"
      count=$((count + 1))
    fi
  done
  report_rule_result "Test files have BEGIN/ROLLBACK wrapper (Rule 8)" "$count"
}

# Rule 8: No NOW() in test files
check_no_now() {
  local count=0
  for file in tests/test_*.sql; do
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      report_violation "$file" "$lineno" "NOW() found — use fixed reference timestamps"
      count=$((count + 1))
    done < <(grep -n '.' "$file" | filter_comments | grep -iE 'NOW[[:space:]]*\(\)' || true)
  done
  report_rule_result "No NOW() in test files (Rule 8)" "$count"
}

# Rule 8: No always-true assertions
check_no_always_true_assertions() {
  local count=0
  for file in tests/test_*.sql; do
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      report_violation "$file" "$lineno" "COUNT(*) >= 0 is always true — use exact assertions"
      count=$((count + 1))
    done < <(grep -n '.' "$file" | filter_comments | grep -E 'COUNT[[:space:]]*\([[:space:]]*\*[[:space:]]*\)[[:space:]]*>=[[:space:]]*0' || true)
  done
  report_rule_result "No always-true assertions (Rule 8)" "$count"
}

# Rule 8: array_agg must have ORDER BY
check_array_agg_order_by() {
  local count=0
  for file in tests/test_*.sql; do
    # Find line numbers containing array_agg(
    while IFS= read -r lineno; do
      # Check if this line is a comment
      local line_content
      line_content=$(sed -n "${lineno}p" "$file")
      if echo "$line_content" | grep -qE '^[[:space:]]*--'; then
        continue
      fi
      if echo "$line_content" | grep -qE '^[[:space:]]*\*'; then
        continue
      fi

      # Look ahead 10 lines for ORDER BY within the array_agg call
      local lookahead
      lookahead=$(sed -n "${lineno},$((lineno + 10))p" "$file")
      if ! echo "$lookahead" | grep -qi 'ORDER BY'; then
        report_violation "$file" "$lineno" "array_agg() without ORDER BY"
        count=$((count + 1))
      fi
    done < <(grep -nE 'array_agg[[:space:]]*\(' "$file" | filter_comments | sed 's/:.*//' || true)
  done
  report_rule_result "array_agg must have ORDER BY (Rule 8)" "$count"
}

# Rule 8: No permanent tables in test files
check_no_permanent_tables() {
  local count=0
  for file in tests/test_*.sql; do
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      report_violation "$file" "$lineno" "CREATE TABLE without TEMP/TEMPORARY — use CREATE TEMP TABLE"
      count=$((count + 1))
    done < <(grep -n '.' "$file" | filter_comments | grep -iE 'CREATE[[:space:]]+TABLE' | grep -viE 'CREATE[[:space:]]+(TEMP|TEMPORARY)[[:space:]]+TABLE' || true)
  done
  report_rule_result "No permanent tables in test files (Rule 8)" "$count"
}

# Rule 2: Schema-qualified API calls in test files
check_schema_qualification() {
  local count=0
  # Public API function names that must be schema-qualified
  # Uses POSIX character classes for macOS compatibility
  local api_funcs='"all"[[:space:]]*\(|"between"[[:space:]]*\(|"after"[[:space:]]*\(|"before"[[:space:]]*\(|"next"[[:space:]]*\(|"most_recent"[[:space:]]*\(|"count"[[:space:]]*\(|"overlaps"[[:space:]]*\('

  for file in tests/test_*.sql; do
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      local content="${line_info#*:}"
      # Skip comment lines
      if echo "$content" | grep -qE '^[[:space:]]*--'; then continue; fi
      if echo "$content" | grep -qE '^[[:space:]]*\*'; then continue; fi

      # Strip all rrule."func"( patterns from the line, then check if any
      # unqualified API calls remain. Uses POSIX classes for BSD sed compat.
      local stripped
      stripped=$(echo "$content" | sed 's/rrule[[:space:]]*\.[[:space:]]*"[a-z_]*"[[:space:]]*(//g')
      if echo "$stripped" | grep -qE "$api_funcs"; then
        report_violation "$file" "$lineno" "Unqualified API call — use rrule.\"func\"() prefix"
        count=$((count + 1))
      fi
    done < <(grep -nE "$api_funcs" "$file" || true)
  done
  report_rule_result "Schema-qualified API calls in test files (Rule 2)" "$count"
}

# Rule 5: No = NULL / <> NULL / != NULL in source files
check_null_comparison() {
  local count=0
  for file in src/*.sql; do
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      local content="${line_info#*:}"
      # Exclude := NULL (PL/pgSQL assignment) and DEFAULT NULL
      if echo "$content" | grep -qE ':=[[:space:]]*NULL|DEFAULT[[:space:]]+NULL'; then
        continue
      fi
      report_violation "$file" "$lineno" "Use IS NULL / IS NOT NULL instead of =/!=/<> NULL"
      count=$((count + 1))
    done < <(grep -n '.' "$file" | filter_comments | grep -E '([^:!<>])=[[:space:]]*NULL|<>[[:space:]]*NULL|!=[[:space:]]*NULL' || true)
  done
  report_rule_result "No = NULL / <> NULL / != NULL in source files (Rule 5)" "$count"
}

# Rule 5: IMMUTABLE only for pure-computation helpers
# Allowed: weekday_to_number, byweekno_matches, calculate_safe_iteration_limit
check_immutable_usage() {
  local count=0
  # Functions explicitly allowed to be IMMUTABLE (CLAUDE.md Rule 5)
  local allowed_funcs='weekday_to_number|byweekno_matches|calculate_safe_iteration_limit'

  for file in src/*.sql; do
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      # Look backward up to 50 lines for the CREATE FUNCTION declaration
      local start=$((lineno > 50 ? lineno - 50 : 1))
      local context
      context=$(sed -n "${start},${lineno}p" "$file")
      # Check if this IMMUTABLE belongs to an allowed function
      if echo "$context" | grep -qE "FUNCTION[[:space:]]+(${allowed_funcs})[[:space:]]*\("; then
        continue
      fi
      report_violation "$file" "$lineno" "IMMUTABLE found — use STABLE or VOLATILE"
      count=$((count + 1))
    done < <(grep -n '.' "$file" | filter_comments | grep -iE '\bIMMUTABLE\b' || true)
  done
  report_rule_result "IMMUTABLE only for pure-computation helpers (Rule 5)" "$count"
}

# Rule 6: No sub-day frequencies in standard install
check_no_subday_in_standard_install() {
  local count=0
  local file="src/install.sql"
  if [ -f "$file" ]; then
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      report_violation "$file" "$lineno" "Sub-day frequency reference in standard install"
      count=$((count + 1))
    done < <(grep -n '.' "$file" | filter_comments | grep -E 'HOURLY|MINUTELY|SECONDLY' || true)
  fi
  report_rule_result "No sub-day frequencies in standard install (Rule 6)" "$count"
}

# Rule 7: inc defaults to FALSE
check_inc_default_false() {
  local count=0
  for file in src/*.sql; do
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      report_violation "$file" "$lineno" "inc parameter must DEFAULT FALSE"
      count=$((count + 1))
    done < <(grep -n '.' "$file" | filter_comments | grep -iE '\binc\b.*DEFAULT[[:space:]]+TRUE' || true)
  done
  report_rule_result "inc defaults to FALSE (Rule 7)" "$count"
}

# --- Main ---

main() {
  echo -e "${BLUE}Test file checks (tests/test_*.sql)${NC}"
  echo ""
  check_no_commit
  check_transaction_wrapper
  check_no_now
  check_no_always_true_assertions
  check_array_agg_order_by
  check_no_permanent_tables
  check_schema_qualification

  echo -e "${BLUE}Source file checks (src/*.sql)${NC}"
  echo ""
  check_null_comparison
  check_immutable_usage
  check_no_subday_in_standard_install
  check_inc_default_false

  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}SUMMARY${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""
  echo -e "  Rules passed:  ${GREEN}${PASS_COUNT}${NC}"
  echo -e "  Rules failed:  ${RED}${FAIL_COUNT}${NC}"
  echo -e "  Total violations: ${TOTAL_VIOLATIONS}"
  echo ""

  if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ ALL CHECKS PASSED${NC}"
    exit 0
  else
    echo -e "${RED}❌ CHECKS FAILED${NC}"
    exit 1
  fi
}

main
