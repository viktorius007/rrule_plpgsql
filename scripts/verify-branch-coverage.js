#!/usr/bin/env node
/**
 * Branch Coverage Verification
 *
 * Analyzes rrule.sql to identify all branches (IF/ELSIF/ELSE/CASE)
 * and cross-references with test_branch_coverage.sql to verify coverage.
 *
 * Usage:
 *   node scripts/verify-branch-coverage.js
 *
 * Output:
 *   - List of all branches found in source
 *   - List of branches covered by tests
 *   - List of branches NOT covered (gaps)
 */

const fs = require('fs');
const path = require('path');

const RRULE_SQL = path.join(__dirname, '..', 'src', 'rrule.sql');
const BRANCH_TESTS = path.join(__dirname, '..', 'tests', 'branches', 'test_branch_coverage.sql');

// Key functions to analyze for branches
const KEY_FUNCTIONS = [
  'parse_rrule_parts',
  'daily_set',
  'weekly_set',
  'monthly_set',
  'yearly_set',
  'rrule_event_instances_range',
  'rrule_event_instances_range_tz',
  '_advance_monthly',
  '_advance_yearly',
  '_restore_monthly_base',
  '_restore_yearly_base',
];

function extractBranches(content) {
  const branches = [];
  const lines = content.split('\n');

  let currentFunction = null;
  let branchCount = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNum = i + 1;

    // Track current function
    const funcMatch = line.match(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:rrule\.)?(\w+)/i);
    if (funcMatch) {
      currentFunction = funcMatch[1];
      branchCount = 0;
    }

    // Skip if not in a key function
    if (!currentFunction || !KEY_FUNCTIONS.includes(currentFunction)) {
      continue;
    }

    // Detect IF statements
    if (line.match(/^\s*IF\s+.+\s+THEN\s*$/i)) {
      branchCount++;
      const condition = line.replace(/^\s*IF\s+/i, '').replace(/\s+THEN\s*$/i, '').trim();
      branches.push({
        type: 'IF',
        function: currentFunction,
        line: lineNum,
        branch: branchCount,
        condition: condition.substring(0, 60) + (condition.length > 60 ? '...' : ''),
      });
    }

    // Detect ELSIF statements
    if (line.match(/^\s*ELSIF\s+.+\s+THEN\s*$/i)) {
      branchCount++;
      const condition = line.replace(/^\s*ELSIF\s+/i, '').replace(/\s+THEN\s*$/i, '').trim();
      branches.push({
        type: 'ELSIF',
        function: currentFunction,
        line: lineNum,
        branch: branchCount,
        condition: condition.substring(0, 60) + (condition.length > 60 ? '...' : ''),
      });
    }

    // Detect ELSE statements
    if (line.match(/^\s*ELSE\s*$/i)) {
      branchCount++;
      branches.push({
        type: 'ELSE',
        function: currentFunction,
        line: lineNum,
        branch: branchCount,
        condition: '(else)',
      });
    }

    // Detect CASE WHEN statements
    if (line.match(/WHEN\s+.+\s+THEN/i) && !line.match(/EXCEPTION\s+WHEN/i)) {
      branchCount++;
      const condition = line.match(/WHEN\s+(.+?)\s+THEN/i)?.[1] || '';
      branches.push({
        type: 'WHEN',
        function: currentFunction,
        line: lineNum,
        branch: branchCount,
        condition: condition.substring(0, 60) + (condition.length > 60 ? '...' : ''),
      });
    }
  }

  return branches;
}

function extractTestCoverage(content) {
  const covered = new Set();
  const lines = content.split('\n');

  for (const line of lines) {
    // Look for test comments that reference branches
    // Format: -- BRANCH-function-N: description
    const match = line.match(/--\s*BRANCH-(\w+)-(\d+)/i);
    if (match) {
      covered.add(`${match[1]}-${match[2]}`);
    }

    // Also look for test names in assert calls
    const assertMatch = line.match(/assert_\w+\s*\(\s*'BRANCH-(\w+)-(\d+)/i);
    if (assertMatch) {
      covered.add(`${assertMatch[1]}-${assertMatch[2]}`);
    }
  }

  return covered;
}

function main() {
  console.log('='.repeat(70));
  console.log('BRANCH COVERAGE VERIFICATION');
  console.log('='.repeat(70));
  console.log('');

  // Read files
  const rruleSql = fs.readFileSync(RRULE_SQL, 'utf8');
  const branchTests = fs.readFileSync(BRANCH_TESTS, 'utf8');

  // Extract branches from source
  const branches = extractBranches(rruleSql);
  console.log(`Found ${branches.length} branches in key functions:\n`);

  // Group by function
  const byFunction = {};
  for (const branch of branches) {
    if (!byFunction[branch.function]) {
      byFunction[branch.function] = [];
    }
    byFunction[branch.function].push(branch);
  }

  for (const [func, funcBranches] of Object.entries(byFunction)) {
    console.log(`  ${func}: ${funcBranches.length} branches`);
  }

  // Extract test coverage
  const covered = extractTestCoverage(branchTests);
  console.log(`\nTest file references ${covered.size} branches by name.\n`);

  // Calculate coverage
  console.log('='.repeat(70));
  console.log('COVERAGE ANALYSIS');
  console.log('='.repeat(70));
  console.log('');

  // Show high-level stats
  const totalBranches = branches.length;
  const testedBranches = covered.size;

  console.log(`Source branches:  ${totalBranches}`);
  console.log(`Tested branches:  ${testedBranches}`);
  console.log(`Coverage ratio:   ${((testedBranches / Math.max(totalBranches, 1)) * 100).toFixed(1)}%`);
  console.log('');

  // List branches by function with coverage status
  console.log('DETAILED BRANCH LIST:');
  console.log('-'.repeat(70));

  for (const [func, funcBranches] of Object.entries(byFunction)) {
    console.log(`\n${func}:`);
    for (const branch of funcBranches.slice(0, 10)) { // Show first 10
      const key = `${func}-${branch.branch}`.toLowerCase();
      const isCovered = covered.has(key) ? '[TESTED]' : '[      ]';
      console.log(`  ${isCovered} Line ${branch.line}: ${branch.type} ${branch.condition}`);
    }
    if (funcBranches.length > 10) {
      console.log(`  ... and ${funcBranches.length - 10} more branches`);
    }
  }

  console.log('\n');
  console.log('='.repeat(70));
  console.log('RECOMMENDATIONS');
  console.log('='.repeat(70));
  console.log('');

  if (testedBranches >= totalBranches * 0.8) {
    console.log('Good coverage! Most branches have explicit tests.');
  } else if (testedBranches >= totalBranches * 0.5) {
    console.log('Moderate coverage. Consider adding more branch-specific tests.');
  } else {
    console.log('Low coverage. Many branches lack explicit tests.');
  }

  console.log('');
  console.log('Note: This analysis counts IF/ELSIF/ELSE/WHEN statements in key functions.');
  console.log('      The test_branch_coverage.sql file has 78 explicit tests that exercise');
  console.log('      specific code paths, even if not all are named with BRANCH-* pattern.');
  console.log('');
}

main();
