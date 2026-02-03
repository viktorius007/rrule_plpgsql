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
# Allowed: weekday_to_number, byweekno_matches, calculate_safe_iteration_limit, version,
#          _restore_monthly_base, _restore_yearly_base (date arithmetic only)
check_immutable_usage() {
  local count=0
  # Functions explicitly allowed to be IMMUTABLE (CLAUDE.md Rule 5)
  local allowed_funcs='weekday_to_number|byweekno_matches|calculate_safe_iteration_limit|version|_restore_monthly_base|_restore_yearly_base'

  for file in src/*.sql; do
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      # Look backward up to 50 lines for the CREATE FUNCTION declaration
      local start=$((lineno > 50 ? lineno - 50 : 1))
      local context
      context=$(sed -n "${start},${lineno}p" "$file")
      # Check if this IMMUTABLE belongs to an allowed function
      if echo "$context" | grep -qE "FUNCTION[[:space:]]+\"?(${allowed_funcs})\"?[[:space:]]*\("; then
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

# Rule 8: No unconditional PASS in WHEN OTHERS exception handlers
# Exception handlers should verify the error message content, not blindly pass
check_when_others_without_message_check() {
  local count=0
  for file in tests/test_*.sql; do
    # Find WHEN OTHERS blocks that have 'PASS' without CASE/IF on err_msg
    # Look for the pattern: WHEN OTHERS followed within 5 lines by a bare 'PASS'
    # without an intervening CASE or IF on err_msg
    local in_when_others=0
    local when_others_line=0
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      local content="${line_info#*:}"
      # Skip comment lines
      if echo "$content" | grep -qE '^[[:space:]]*--'; then continue; fi

      if echo "$content" | grep -qiE 'WHEN[[:space:]]+OTHERS[[:space:]]+THEN'; then
        in_when_others=1
        when_others_line=$lineno
      fi

      if [ "$in_when_others" -eq 1 ]; then
        # Check if we found a CASE/IF checking err_msg (good pattern)
        if echo "$content" | grep -qiE 'CASE[[:space:]]+WHEN[[:space:]]+err_msg|IF[[:space:]]+err_msg'; then
          in_when_others=0
          continue
        fi
        # Check if we found bare 'PASS' without err_msg check (bad pattern)
        if echo "$content" | grep -qE "'PASS'" && ! echo "$content" | grep -qiE 'err_msg'; then
          report_violation "$file" "$when_others_line" "WHEN OTHERS handler unconditionally returns PASS — check err_msg content"
          count=$((count + 1))
          in_when_others=0
          continue
        fi
        # Reset after END block
        if echo "$content" | grep -qiE '^[[:space:]]*END[[:space:]]*;'; then
          in_when_others=0
        fi
      fi
    done < <(grep -n '.' "$file")
  done
  report_rule_result "No unconditional PASS in WHEN OTHERS handlers (Rule 8)" "$count"
}

# Rule 8: No MIN(...) IS NOT NULL loose assertions
# MIN(col) IS NOT NULL only proves at least one row is non-NULL, not all rows
check_min_is_not_null() {
  local count=0
  for file in tests/test_*.sql; do
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      report_violation "$file" "$lineno" "MIN(...) IS NOT NULL is a loose assertion — use COUNT(*) FILTER (WHERE col IS NOT NULL)"
      count=$((count + 1))
    done < <(grep -n '.' "$file" | filter_comments | grep -E 'MIN[[:space:]]*\([^)]+\)[[:space:]]+IS[[:space:]]+NOT[[:space:]]+NULL' || true)
  done
  report_rule_result "No MIN(...) IS NOT NULL loose assertions (Rule 8)" "$count"
}

# Rule 8: No Unicode emoji in test files (use ASCII [PASS]/[FAIL] instead)
check_no_emoji() {
  local count=0
  for file in tests/test_*.sql; do
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      report_violation "$file" "$lineno" "Unicode emoji found — use ASCII [PASS]/[FAIL] instead"
      count=$((count + 1))
    done < <(grep -n '[✓✗✅❌✔✘]' "$file" 2>/dev/null || true)
  done
  report_rule_result "No Unicode emoji in test files (Rule 8)" "$count"
}

# Rule 8: COUNT(*)::TEXT assertion anti-pattern (advisory)
# Non-zero count-only assertions should use exact date arrays.
# Zero-count assertions (expected='0') and relative comparisons are acceptable.
check_count_text_antipattern() {
  local count=0
  for file in tests/test_*.sql; do
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      echo -e "  ${YELLOW}⚠${NC} ${file}:${lineno} — COUNT(*)::TEXT assertion — consider using exact date array assertion"
      count=$((count + 1))
    done < <(grep -n '.' "$file" | filter_comments | grep -E 'COUNT\(\*\)::TEXT' || true)
  done
  # Advisory rule: report count but always pass
  if [ "$count" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} No COUNT(*)::TEXT anti-pattern in tests (Rule 8, advisory)"
  else
    echo -e "${YELLOW}⚠${NC} COUNT(*)::TEXT assertions in tests (Rule 8, advisory) — ${count} warning(s)"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
  echo ""
}

# Rule 8: No inline CASE PASS/FAIL assertions in unit test files (advisory)
# Unit tests should use shared assertion helpers (assert_equals, assert_true, etc.)
# Advisory: reports warnings but does not fail the linter. Only checked in unit test
# files, not integration tests like test_table_operations.sql.
check_inline_case_assertions() {
  local count=0
  # Only check unit test files, not integration test files
  local unit_test_files="tests/test_rrule_functions.sql tests/test_tzid_support.sql"
  for file in $unit_test_files; do
    [ -f "$file" ] || continue
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      local content="${line_info#*:}"
      # Skip display/summary CASE blocks (e.g., formatting test results for output)
      if echo "$content" | grep -qiE 'LIKE.*PASS'; then continue; fi
      echo -e "  ${YELLOW}⚠${NC} ${file}:${lineno} — Inline CASE PASS/FAIL — consider using shared assertion helpers"
      count=$((count + 1))
    done < <(grep -n '.' "$file" | filter_comments | grep -E "THEN[[:space:]]*'PASS" || true)
  done
  # Advisory rule: report count but always pass
  if [ "$count" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} No inline CASE PASS/FAIL in unit tests (Rule 8, advisory)"
  else
    echo -e "${YELLOW}⚠${NC} No inline CASE PASS/FAIL in unit tests (Rule 8, advisory) — ${count} warning(s)"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
  echo ""
}

# Rule 1: parse_rrule_parts rejects duplicate FREQ
# Verify that the source code contains the duplicate FREQ check
check_duplicate_freq_rejection() {
  local count=0
  local file="src/rrule.sql"
  if [ -f "$file" ]; then
    if ! grep -q 'FREQ=.*FREQ=' "$file"; then
      report_violation "$file" "1" "Missing duplicate FREQ rejection in parse_rrule_parts()"
      count=$((count + 1))
    fi
  fi
  report_rule_result "Source rejects duplicate FREQ parameters (Rule 1)" "$count"
}

# Rule 5: Public API functions check for NULL dtstart
# Verify that the source code contains NULL dtstart validation
check_null_dtstart_validation() {
  local count=0
  local file="src/rrule.sql"
  if [ -f "$file" ]; then
    if ! grep -q 'dtstart IS NULL' "$file"; then
      report_violation "$file" "1" "Missing NULL dtstart validation in public API functions"
      count=$((count + 1))
    fi
  fi
  report_rule_result "Source validates NULL dtstart in public API (Rule 5)" "$count"
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
  check_when_others_without_message_check
  check_min_is_not_null
  check_no_emoji
  check_count_text_antipattern
  check_inline_case_assertions

  echo -e "${BLUE}Source file checks (src/*.sql)${NC}"
  echo ""
  check_null_comparison
  check_immutable_usage
  check_no_subday_in_standard_install
  check_inc_default_false
  check_duplicate_freq_rejection
  check_null_dtstart_validation

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
