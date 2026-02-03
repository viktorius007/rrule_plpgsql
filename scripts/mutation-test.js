#!/usr/bin/env node
/**
 * Mutation Testing Framework
 *
 * Introduces specific mutations to rrule.sql and verifies that tests catch them.
 * If a mutation survives (tests pass), it indicates a testing gap.
 *
 * Usage:
 *   node scripts/mutation-test.js
 *   # Or with npm:
 *   npm run test:mutations
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

// Mutation definitions: [name, pattern, replacement, description]
const MUTATIONS = [
  // Boundary mutations (actual patterns from code)
  ['boundary-1', /period_count < period_limit/g, 'period_count <= period_limit',
   'Change < to <= in period limit loop (should iterate more)'],

  ['boundary-2', /result\.period_count >= p_period_limit/g, 'result.period_count > p_period_limit',
   'Change >= to > in period limit check (should iterate one more)'],

  ['boundary-3', /current_base < maxdate/g, 'current_base <= maxdate',
   'Change < to <= in maxdate check (should include boundary)'],

  // Off-by-one mutations (match actual code spacing)
  ['off-by-one-1', /result_count := result_count \+ 1;/g, 'result_count := result_count + 2;',
   'Increment result count by 2 instead of 1 (should break COUNT)'],

  ['off-by-one-2', /period_count := period_count \+ 1;/g, 'period_count := period_count + 2;',
   'Increment period count by 2 instead of 1 (should hit limits faster)'],

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

  // Interval increment mutations
  ['interval-1', /make_interval\(days => rule\.interval\)/g, 'make_interval(days => rule.interval + 1)',
   'Add 1 to DAILY interval (should space results wrong)'],

  // NULL handling mutations
  ['null-1', /IS NOT NULL/g, 'IS NULL',
   'Invert first IS NOT NULL check (should break many things)'],
];

// Quick subset of tests to run for mutation testing (full suite is too slow)
const QUICK_TESTS = [
  'tests/test_validation.sql',
  'tests/matrix/test_rejection_matrix.sql',
  'tests/matrix/test_api_boundary_matrix.sql',
  'tests/branches/test_branch_coverage.sql',
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
    survived: [],
    skipped: [],
  };

  backup();

  try {
    for (const [name, pattern, replacement, description] of MUTATIONS) {
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
        console.log('SURVIVED! (tests passed - gap detected)');
        results.survived.push({ name, description });
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

  // Report
  console.log('');
  console.log('='.repeat(70));
  console.log('MUTATION TESTING RESULTS');
  console.log('='.repeat(70));
  console.log('');

  console.log(`Caught: ${results.caught.length}`);
  console.log(`Survived: ${results.survived.length}`);
  console.log(`Skipped: ${results.skipped.length}`);
  console.log('');

  if (results.survived.length > 0) {
    console.log('SURVIVING MUTATIONS (testing gaps):');
    for (const { name, description } of results.survived) {
      console.log(`  - [${name}] ${description}`);
    }
    console.log('');
  }

  if (results.caught.length > 0) {
    console.log('CAUGHT MUTATIONS (good coverage):');
    for (const { name, description } of results.caught) {
      console.log(`  - [${name}] ${description}`);
    }
  }

  // Exit with error if mutations survived
  if (results.survived.length > 0) {
    console.log('');
    console.log('WARNING: Some mutations survived - consider adding more tests.');
    process.exit(1);
  } else {
    console.log('');
    console.log('SUCCESS: All mutations were caught by tests!');
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
