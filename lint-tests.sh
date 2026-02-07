#!/bin/bash
#
# Static SQL Linter for rrule_plpgsql coding standards
#
# Usage:
#   ./lint-tests.sh       # Run all checks

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

# Check if line content starts with SQL comment (-- or *)
is_comment() {
  [[ "$1" =~ ^[[:space:]]*(--|\[*]) ]]
}

# SQL test files covered by static lint checks (includes matrix/branch/security suites).
shopt -s nullglob
TEST_SQL_FILES=(
  tests/test_*.sql
  tests/matrix/*.sql
  tests/branches/*.sql
  tests/security/*.sql
  tests/parity/*.sql
  tests/mutation/*.sql
  tests/fuzz/*.sql
)

# --- Check functions ---

# Rule 8: No COMMIT in test files
check_no_commit() {
  local count=0
  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"
    local content="${rest#*:}"
    is_comment "$content" && continue
    [[ "$content" =~ ROLLBACK ]] && continue
    report_violation "$file" "$lineno" "COMMIT; found — use ROLLBACK instead"
    count=$((count + 1))
  done < <(grep -niE 'COMMIT[[:space:]]*;' "${TEST_SQL_FILES[@]}" 2>/dev/null || true)
  report_rule_result "No COMMIT in test files (Rule 8)" "$count"
}

# Rule 8: Every test file must have BEGIN and ROLLBACK
check_transaction_wrapper() {
  local count=0
  for file in "${TEST_SQL_FILES[@]}"; do
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
  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"
    local content="${rest#*:}"
    is_comment "$content" && continue
    report_violation "$file" "$lineno" "NOW() found — use fixed reference timestamps"
    count=$((count + 1))
  done < <(grep -niE 'NOW[[:space:]]*\(\)' "${TEST_SQL_FILES[@]}" 2>/dev/null || true)
  report_rule_result "No NOW() in test files (Rule 8)" "$count"
}

# Rule 8: No always-true assertions
check_no_always_true_assertions() {
  local count=0
  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"
    local content="${rest#*:}"
    is_comment "$content" && continue
    report_violation "$file" "$lineno" "COUNT(*) >= 0 is always true — use exact assertions"
    count=$((count + 1))
  done < <(grep -nE 'COUNT[[:space:]]*\([[:space:]]*\*[[:space:]]*\)[[:space:]]*>=[[:space:]]*0' "${TEST_SQL_FILES[@]}" 2>/dev/null || true)
  report_rule_result "No always-true assertions (Rule 8)" "$count"
}

# Rule 8: array_agg must have ORDER BY
check_array_agg_order_by() {
  local count=0
  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"
    local content="${rest#*:}"
    is_comment "$content" && continue

    # Look ahead 10 lines for ORDER BY
    local lookahead
    lookahead=$(sed -n "${lineno},$((lineno + 10))p" "$file")
    if ! [[ "$lookahead" =~ [Oo][Rr][Dd][Ee][Rr][[:space:]]+[Bb][Yy] ]]; then
      report_violation "$file" "$lineno" "array_agg() without ORDER BY"
      count=$((count + 1))
    fi
  done < <(grep -nE 'array_agg[[:space:]]*\(' "${TEST_SQL_FILES[@]}" 2>/dev/null || true)
  report_rule_result "array_agg must have ORDER BY (Rule 8)" "$count"
}

# Rule 8: No permanent tables in test files
check_no_permanent_tables() {
  local count=0
  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"
    local content="${rest#*:}"
    is_comment "$content" && continue
    # Skip if TEMP or TEMPORARY present
    [[ "$content" =~ [Tt][Ee][Mm][Pp]([Oo][Rr][Aa][Rr][Yy])?[[:space:]]+[Tt][Aa][Bb][Ll][Ee] ]] && continue
    report_violation "$file" "$lineno" "CREATE TABLE without TEMP/TEMPORARY — use CREATE TEMP TABLE"
    count=$((count + 1))
  done < <(grep -niE 'CREATE[[:space:]]+TABLE' "${TEST_SQL_FILES[@]}" 2>/dev/null || true)
  report_rule_result "No permanent tables in test files (Rule 8)" "$count"
}

# Rule 2: Schema-qualified API calls in test files
check_schema_qualification() {
  local count=0
  local api_pattern='"(all|between|after|before|next|most_recent|count|overlaps)"[[:space:]]*\('

  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"
    local content="${rest#*:}"
    is_comment "$content" && continue

    # Strip all rrule."func"( patterns, then check if unqualified calls remain
    local stripped="${content//rrule./}"
    # If stripping rrule. removed the match, it was qualified
    if [[ "$stripped" == "$content" ]]; then
      report_violation "$file" "$lineno" "Unqualified API call — use rrule.\"func\"() prefix"
      count=$((count + 1))
    fi
  done < <(grep -nE "$api_pattern" "${TEST_SQL_FILES[@]}" 2>/dev/null || true)
  report_rule_result "Schema-qualified API calls in test files (Rule 2)" "$count"
}

# Rule 5: No = NULL / <> NULL / != NULL in source files
check_null_comparison() {
  local count=0
  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"
    local content="${rest#*:}"
    is_comment "$content" && continue
    # Exclude := NULL and DEFAULT NULL
    [[ "$content" =~ :=.*NULL ]] && continue
    [[ "$content" =~ DEFAULT[[:space:]]+NULL ]] && continue
    report_violation "$file" "$lineno" "Use IS NULL / IS NOT NULL instead of =/!=/<> NULL"
    count=$((count + 1))
  done < <(grep -nE '([^:!<>])=[[:space:]]*NULL|<>[[:space:]]*NULL|!=[[:space:]]*NULL' src/*.sql 2>/dev/null || true)
  report_rule_result "No = NULL / <> NULL / != NULL in source files (Rule 5)" "$count"
}

# Rule 5: IMMUTABLE only for pure-computation helpers
check_immutable_usage() {
  local count=0
  local allowed_funcs='weekday_to_number|byweekno_matches|calculate_safe_iteration_limit|version|_restore_monthly_base|_restore_yearly_base'

  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"
    local content="${rest#*:}"
    is_comment "$content" && continue

    # Look backward up to 50 lines for allowed function
    local start=$((lineno > 50 ? lineno - 50 : 1))
    local context
    context=$(sed -n "${start},${lineno}p" "$file")
    if [[ "$context" =~ FUNCTION[[:space:]]+\"?(${allowed_funcs})\"?[[:space:]]*\( ]]; then
      continue
    fi
    report_violation "$file" "$lineno" "IMMUTABLE found — use STABLE or VOLATILE"
    count=$((count + 1))
  done < <(grep -niE '\bIMMUTABLE\b' src/*.sql 2>/dev/null || true)
  report_rule_result "IMMUTABLE only for pure-computation helpers (Rule 5)" "$count"
}

# Rule 6: No sub-day frequencies in standard install
check_no_subday_in_standard_install() {
  local count=0
  local file="src/install.sql"
  if [ -f "$file" ]; then
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      local content="${line_info#*:}"
      is_comment "$content" && continue
      report_violation "$file" "$lineno" "Sub-day frequency reference in standard install"
      count=$((count + 1))
    done < <(grep -nE 'HOURLY|MINUTELY|SECONDLY' "$file" 2>/dev/null || true)
  fi
  report_rule_result "No sub-day frequencies in standard install (Rule 6)" "$count"
}

# Rule 7: inc defaults to FALSE
check_inc_default_false() {
  local count=0
  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"
    local content="${rest#*:}"
    is_comment "$content" && continue
    report_violation "$file" "$lineno" "inc parameter must DEFAULT FALSE"
    count=$((count + 1))
  done < <(grep -niE '\binc\b.*DEFAULT[[:space:]]+TRUE' src/*.sql 2>/dev/null || true)
  report_rule_result "inc defaults to FALSE (Rule 7)" "$count"
}

# Rule 8: No unconditional PASS in WHEN OTHERS exception handlers
check_when_others_without_message_check() {
  local count=0
  # Find WHEN OTHERS blocks first, then analyze (not iterating every line)
  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"

    # Look ahead 10 lines for the pattern
    local lookahead
    lookahead=$(sed -n "${lineno},$((lineno + 10))p" "$file")

    # Good if it has CASE/IF checking err_msg
    [[ "$lookahead" =~ (CASE[[:space:]]+WHEN|IF)[[:space:]]+err_msg ]] && continue

    # Bad if it has 'PASS' without err_msg check
    if [[ "$lookahead" =~ \'PASS\' ]] && ! [[ "$lookahead" =~ err_msg.*\'PASS\' ]]; then
      report_violation "$file" "$lineno" "WHEN OTHERS handler unconditionally returns PASS — check err_msg content"
      count=$((count + 1))
    fi
  done < <(grep -niE 'WHEN[[:space:]]+OTHERS[[:space:]]+THEN' "${TEST_SQL_FILES[@]}" 2>/dev/null || true)
  report_rule_result "No unconditional PASS in WHEN OTHERS handlers (Rule 8)" "$count"
}

# Rule 8: No MIN(...) IS NOT NULL loose assertions
check_min_is_not_null() {
  local count=0
  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"
    local content="${rest#*:}"
    is_comment "$content" && continue
    report_violation "$file" "$lineno" "MIN(...) IS NOT NULL is a loose assertion — use COUNT(*) FILTER (WHERE col IS NOT NULL)"
    count=$((count + 1))
  done < <(grep -nE 'MIN[[:space:]]*\([^)]+\)[[:space:]]+IS[[:space:]]+NOT[[:space:]]+NULL' "${TEST_SQL_FILES[@]}" 2>/dev/null || true)
  report_rule_result "No MIN(...) IS NOT NULL loose assertions (Rule 8)" "$count"
}

# Rule 8: No Unicode emoji in test files
check_no_emoji() {
  local count=0
  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"
    report_violation "$file" "$lineno" "Unicode emoji found — use ASCII [PASS]/[FAIL] instead"
    count=$((count + 1))
  done < <(grep -n '[✓✗✅❌✔✘]' "${TEST_SQL_FILES[@]}" 2>/dev/null || true)
  report_rule_result "No Unicode emoji in test files (Rule 8)" "$count"
}

# Rule 8: COUNT(*)::TEXT assertion anti-pattern (advisory)
check_count_text_antipattern() {
  local count=0
  while IFS= read -r line_info; do
    local file="${line_info%%:*}"
    local rest="${line_info#*:}"
    local lineno="${rest%%:*}"
    local content="${rest#*:}"
    is_comment "$content" && continue
    echo -e "  ${YELLOW}⚠${NC} ${file}:${lineno} — COUNT(*)::TEXT assertion — consider using exact date array assertion"
    count=$((count + 1))
  done < <(grep -nE 'COUNT\(\*\)::TEXT' "${TEST_SQL_FILES[@]}" 2>/dev/null || true)
  if [ "$count" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} No COUNT(*)::TEXT anti-pattern in tests (Rule 8, advisory)"
  else
    echo -e "${YELLOW}⚠${NC} COUNT(*)::TEXT assertions in tests (Rule 8, advisory) — ${count} warning(s)"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
  echo ""
}

# Rule 8: No inline CASE PASS/FAIL assertions in unit test files (advisory)
check_inline_case_assertions() {
  local count=0
  local unit_test_files="tests/test_rrule_functions.sql tests/test_tzid_support.sql"
  for file in $unit_test_files; do
    [ -f "$file" ] || continue
    while IFS= read -r line_info; do
      local lineno="${line_info%%:*}"
      local content="${line_info#*:}"
      is_comment "$content" && continue
      [[ "$content" =~ LIKE.*PASS ]] && continue
      echo -e "  ${YELLOW}⚠${NC} ${file}:${lineno} — Inline CASE PASS/FAIL — consider using shared assertion helpers"
      count=$((count + 1))
    done < <(grep -nE "THEN[[:space:]]*'PASS" "$file" 2>/dev/null || true)
  done
  if [ "$count" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} No inline CASE PASS/FAIL in unit tests (Rule 8, advisory)"
  else
    echo -e "${YELLOW}⚠${NC} No inline CASE PASS/FAIL in unit tests (Rule 8, advisory) — ${count} warning(s)"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
  echo ""
}

# Rule 1: parse_rrule_parts rejects duplicate FREQ
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
  echo -e "${BLUE}Test file checks (tests/**/*.sql)${NC}"
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
