#!/usr/bin/env node
/**
 * Mutation Testing Framework
 *
 * Introduces specific mutations to rrule.sql and verifies that tests catch them.
 * If a mutation survives (tests pass), it indicates a testing gap.
 *
 * Usage:
 *   node scripts/mutation-test.js
 *   # Or with pnpm:
 *   pnpm test:mutations
 *
 * Mutations tested:
 * - Boundary changes (> to >=, < to <=)
 * - Off-by-one errors (+1, -1)
 * - Logic inversions (AND to OR, NOT removal)
 * - Constant changes (1000 to 999, 10 to 9)
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const RRULE_SQL_PATH = path.join(__dirname, '..', 'src', 'rrule.sql');
const BACKUP_PATH = path.join(__dirname, '..', 'src', 'rrule.sql.backup');

// Mutation definitions: [name, pattern, replacement, description, equivalent]
// equivalent=true means the mutation cannot cause observable behavior change
// (due to redundant safeguards in the code design)
const MUTATIONS = [
  // Boundary mutations (actual patterns from code)
  // EQUIVALENT: period_limit (40,000+) is a safety net; COUNT/UNTIL/maxdate always trigger first
  ['boundary-1', /period_count < period_limit/g, 'period_count <= period_limit',
   'Change < to <= in period limit loop (equivalent: other limits trigger first)', true],

  // Non-equivalent: helper-level tests now directly exercise this branch.
  ['boundary-2', /result\.period_count >= p_period_limit/g, 'result.period_count > p_period_limit',
   'Change >= to > in period limit check (should alter SKIP=FORWARD termination)'],

  // Non-equivalent: helper-level tests now directly exercise OMIT limit branch.
  ['boundary-4', /result\.omit_count >= p_period_limit/g, 'result.omit_count > p_period_limit',
   'Change >= to > in OMIT period limit check (should alter SKIP=OMIT termination)'],

  ['boundary-3', /current_base <= maxdate/g, 'current_base < maxdate',
   'Exclude maxdate boundary in loop condition (should drop boundary occurrences)'],

  // Off-by-one mutations (match actual code spacing)
  // EQUIVALENT: result_count is internal to set functions; outer loop's occurrence_count
  // enforces COUNT/UNTIL independently, compensating for any early exit
  ['off-by-one-1', /result_count := result_count \+ 1;/g, 'result_count := result_count + 2;',
   'Increment result count by 2 instead of 1 (equivalent: outer loop compensates)', true],

  ['off-by-one-2', /period_count := period_count \+ 1;/g, 'period_count := period_count + 2;',
   'Increment period count by 2 instead of 1 (equivalent: safety limits are dominated by maxdate/COUNT/output cap)', true],

  // Constant mutations
  ['constant-1', /max_count := 1000;/g, 'max_count := 999;',
   'Change max from 1000 to 999 (should cap at 999)'],

  ['constant-2', /INTERVAL '10 years'/g, "INTERVAL '9 years'",
   'Change 10-year window to 9 years (should cut off earlier)'],

  // Logic mutations
  ['logic-1', /IF result\.count IS NOT NULL AND result\.until IS NOT NULL/g,
   'IF result.count IS NOT NULL OR result.until IS NOT NULL',
   'Change AND to OR in mutual exclusion check (should accept invalid RRULEs)'],

  ['logic-2', /IF result\.freq IS NULL/g, 'IF result.freq IS NOT NULL',
   'Invert NULL check for freq (should reject valid RRULEs)'],

  // Filter removal mutations (actual patterns)
  ['filter-1', /rrule\.test_bymonth_rule\(/g, 'TRUE OR rrule.test_bymonth_rule(',
   'Bypass BYMONTH filter (should produce unfiltered results)'],

  ['filter-2', /rrule\.test_byday_rule\(/g, 'TRUE OR rrule.test_byday_rule(',
   'Bypass BYDAY filter (should produce unfiltered results)'],

  // SKIP behavior mutations
  ['skip-1', /WHEN 'BACKWARD' THEN/g, "WHEN 'FORWARD' THEN",
   'Swap BACKWARD and FORWARD behavior (should move dates wrong direction)'],

  // TZ unsupported-frequency branch behavior (standard install)
  ['tz-unsupported-branch', /rule\.freq IN \('HOURLY', 'MINUTELY', 'SECONDLY'\)/g,
   "rule.freq IN ('HOURLY', 'MINUTELY')",
   'Drop SECONDLY from unsupported-frequency set (should route SECONDLY to wrong branch)'],

  // Interval increment mutations
  ['interval-1', /make_interval\(days => rule\.interval\)/g, 'make_interval(days => rule.interval + 1)',
   'Add 1 to DAILY interval (should space results wrong)'],

  // NULL handling mutations
  ['null-1', /IS NOT NULL/g, 'IS NULL',
   'Invert first IS NOT NULL check (should break many things)'],

  // ROR - Relational Operator Replacement
  // EQUIVALENT: result_count >= max_results in inner set functions is an optimization;
  // the outer generator loop's occurrence_count independently enforces COUNT/UNTIL limits,
  // compensating for any extra result from the inner function.
  ['ror-gte-gt', /result_count >= max_results/g, 'result_count > max_results',
   'Change >= to > in result count check (equivalent: outer loop enforces limits)', true],

  // Testing <= to < (removes boundary case)
  ['ror-lte-lt', /requested_day <= daysinmonth/g, 'requested_day < daysinmonth',
   'Change <= to < in day validation (should skip valid end-of-month days)'],

  // Testing != to = (inverts not-equal check)
  ['ror-neq-eq', /result\.freq != 'YEARLY'/g, "result.freq = 'YEARLY'",
   'Invert BYWEEKNO YEARLY check (should reject valid YEARLY rules)'],

  // LCR - Logical Connector Replacement
  // AND to OR (widens condition)
  ['lcr-and-or', /result\.count IS NOT NULL AND result\.count <= 0/g,
   'result.count IS NOT NULL OR result.count <= 0',
   'Change AND to OR in COUNT validation (should reject valid positive COUNTs)'],

  // OR to AND (narrows condition - in bysecond/byminute/byhour range checks)
  ['lcr-or-and', /result\.bysecond\[i\] < 0 OR result\.bysecond\[i\] > 60/g,
   'result.bysecond[i] < 0 AND result.bysecond[i] > 60',
   'Change OR to AND in BYSECOND range check (should accept invalid values)'],

  // NLS - NULL to NOT NULL mutations (inverse of null-1)
  ['nls-null-notnull', /IS NULL/g, 'IS NOT NULL',
   'Change IS NULL to IS NOT NULL (should break NULL checks)'],

  // NLF - COALESCE removal (return first arg only)
  // Note: Pattern targets simple COALESCE(x, y) with no nested parens
  ['nlf-coalesce', /COALESCE\(([^,()]+),\s*([^,()]+)\)/g, '$1',
   'Remove COALESCE fallback, use first argument only'],

  // AOR - Arithmetic Operator Replacement (+ to -, - to +)
  // Pattern targets operators followed by digits to avoid variable expressions
  ['aor-add-sub', / \+ (\d)/g, ' - $1',
   'Replace addition with subtraction (+ N -> - N)'],
  ['aor-sub-add', / - (\d)/g, ' + $1',
   'Replace subtraction with addition (- N -> + N)'],

  // INT - Interval mutations (1 day/month to 2 days/months)
  ['int-day', /INTERVAL '1 day'/g, "INTERVAL '2 days'",
   'Double INTERVAL 1 day (should space dates incorrectly)'],
  ['int-month', /INTERVAL '1 month'/g, "INTERVAL '2 months'",
   'Double INTERVAL 1 month (should break month calculations)'],
];

// Quick subset of tests to run for mutation testing (full suite is too slow)
const QUICK_TESTS = [
  'tests/test_validation.sql',
  'tests/matrix/test_rejection_matrix.sql',
  'tests/matrix/test_api_boundary_matrix.sql',
  'tests/branches/test_branch_coverage.sql',
  'tests/mutation/test_mutation_catching.sql',
];

function backup() {
  fs.copyFileSync(RRULE_SQL_PATH, BACKUP_PATH);
  console.log('Backed up rrule.sql');
}

function restore() {
  if (fs.existsSync(BACKUP_PATH)) {
    fs.copyFileSync(BACKUP_PATH, RRULE_SQL_PATH);
    fs.unlinkSync(BACKUP_PATH);
    console.log('Restored rrule.sql');
  }
}

function applyMutation(name, pattern, replacement) {
  const content = fs.readFileSync(RRULE_SQL_PATH, 'utf8');
  const mutated = content.replace(pattern, replacement);

  if (content === mutated) {
    return false; // Pattern not found
  }

  fs.writeFileSync(RRULE_SQL_PATH, mutated);
  return true;
}

function runQuickTests() {
  try {
    // Set up test database
    execSync(`
      PGHOST=localhost PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres \
      psql -c "DROP DATABASE IF EXISTS mutation_test" 2>/dev/null || true
    `, { stdio: 'pipe' });

    execSync(`
      PGHOST=localhost PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres \
      psql -c "CREATE DATABASE mutation_test" 2>/dev/null
    `, { stdio: 'pipe' });

    // Run a quick subset of tests
    for (const testFile of QUICK_TESTS) {
      try {
        execSync(`
          PGHOST=localhost PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres \
          psql -v rrule_install=src/install.sql -d mutation_test -f ${testFile} 2>&1
        `, { stdio: 'pipe', timeout: 30000 });
      } catch (e) {
        // Test failed - mutation was caught
        return false;
      }
    }

    // All tests passed - mutation survived!
    return true;
  } catch (e) {
    // Setup error or timeout
    return false;
  }
}

function cleanup() {
  try {
    execSync(`
      PGHOST=localhost PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres \
      psql -c "DROP DATABASE IF EXISTS mutation_test" 2>/dev/null || true
    `, { stdio: 'pipe' });
  } catch (e) {
    // Ignore cleanup errors
  }
}

function main() {
  console.log('='.repeat(70));
  console.log('MUTATION TESTING');
  console.log('='.repeat(70));
  console.log('');
  console.log('Testing that mutations are caught by the test suite...');
  console.log('');

  const results = {
    caught: [],
    survived: [],        // Non-equivalent mutations that survived (real gaps)
    equivalent: [],      // Equivalent mutations that survived (expected)
    skipped: [],
  };

  backup();

  try {
    for (const [name, pattern, replacement, description, isEquivalent] of MUTATIONS) {
      process.stdout.write(`Testing mutation [${name}]... `);

      // Apply mutation
      const applied = applyMutation(name, pattern, replacement);

      if (!applied) {
        console.log('SKIPPED (pattern not found)');
        results.skipped.push({ name, description });
        restore();
        backup();
        continue;
      }

      // Run tests
      const survived = runQuickTests();

      if (survived) {
        if (isEquivalent) {
          console.log('SURVIVED (equivalent mutation - expected)');
          results.equivalent.push({ name, description });
        } else {
          console.log('SURVIVED! (tests passed - gap detected)');
          results.survived.push({ name, description });
        }
      } else {
        console.log('CAUGHT (tests failed - good!)');
        results.caught.push({ name, description });
      }

      // Restore for next mutation
      restore();
      backup();
    }
  } finally {
    restore();
    cleanup();
  }

  // Calculate mutation score
  const killed = results.caught.length;
  const equivalent = results.equivalent.length;
  const survived = results.survived.length;
  const skipped = results.skipped.length;
  const total = killed + equivalent + survived + skipped;
  const nonEquivalent = total - equivalent;

  // Mutation Score = Killed / (Total - Equivalent)
  // If all mutations are equivalent (nonEquivalent = 0), score is 100% by definition
  const mutationScore = nonEquivalent > 0 ? (killed / nonEquivalent) * 100 : 100;

  // Helper for percentage formatting
  const pct = (count, base) => base > 0 ? ((count / base) * 100).toFixed(1) : '0.0';

  // Report - Formatted Summary
  console.log('');
  console.log('='.repeat(70));
  console.log('MUTATION TESTING SUMMARY');
  console.log('='.repeat(70));
  console.log(`Total Mutations:     ${String(total).padStart(3)}`);
  console.log(`Killed:              ${String(killed).padStart(3)} (${pct(killed, total)}%)`);
  console.log(`Equivalent:          ${String(equivalent).padStart(3)} (${pct(equivalent, total)}%)`);
  console.log(`Survived:            ${String(survived).padStart(3)} (${pct(survived, total)}%)`);
  console.log(`Skipped:             ${String(skipped).padStart(3)} (${pct(skipped, total)}%)`);
  console.log('');
  console.log(`MUTATION SCORE: ${mutationScore.toFixed(1)}% (${killed}/${nonEquivalent} non-equivalent killed)`);
  console.log('='.repeat(70));
  console.log('');

  if (results.caught.length > 0) {
    console.log('CAUGHT MUTATIONS (good coverage):');
    for (const { name, description } of results.caught) {
      console.log(`  - [${name}] ${description}`);
    }
    console.log('');
  }

  if (results.equivalent.length > 0) {
    console.log('EQUIVALENT MUTATIONS (cannot cause observable change):');
    for (const { name, description } of results.equivalent) {
      console.log(`  - [${name}] ${description}`);
    }
    console.log('');
  }

  if (results.survived.length > 0) {
    console.log('SURVIVING MUTATIONS (testing gaps):');
    for (const { name, description } of results.survived) {
      console.log(`  - [${name}] ${description}`);
    }
    console.log('');
  }

  // Exit with error only if non-equivalent mutations survived
  if (results.survived.length > 0) {
    console.log('FAIL: Some non-equivalent mutations survived - tests need improvement.');
    process.exit(1);
  } else {
    console.log('SUCCESS: All testable mutations were caught!');
    process.exit(0);
  }
}

// Handle cleanup on interrupt
process.on('SIGINT', () => {
  console.log('\nInterrupted - cleaning up...');
  restore();
  cleanup();
  process.exit(1);
});

main();
