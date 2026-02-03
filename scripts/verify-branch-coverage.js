#!/usr/bin/env node
/**
 * Branch Coverage Verification
 *
 * Analyzes rrule.sql to identify all branches (IF/ELSIF/ELSE/CASE)
 * and cross-references with test_branch_coverage.sql to verify coverage.
 *
 * Usage:
 *   node scripts/verify-branch-coverage.js
 *   node scripts/verify-branch-coverage.js --verbose   # Show all branches
 *   node scripts/verify-branch-coverage.js --critical  # Show only critical untested
 *
 * Output:
 *   - List of all branches found in source
 *   - List of branches covered by tests
 *   - List of branches NOT covered (gaps)
 *   - Risk classification for each branch
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

// Map shortened test names to full function names
const FUNCTION_ALIASES = {
  'parse': 'parse_rrule_parts',
  'daily': 'daily_set',
  'weekly': 'weekly_set',
  'monthly': 'monthly_set',
  'yearly': 'yearly_set',
  'main': 'rrule_event_instances_range',
  'tz': 'rrule_event_instances_range_tz',
  'helper': 'helper_functions',
  'bysetpos': 'rrule_bysetpos_filter',
  'advance_monthly': '_advance_monthly',
  'advance_yearly': '_advance_yearly',
};

// Reverse map: full name -> short name (for matching)
const REVERSE_ALIASES = {};
for (const [short, full] of Object.entries(FUNCTION_ALIASES)) {
  REVERSE_ALIASES[full] = short;
}

// Risk classification patterns
function classifyRisk(condition, functionName) {
  // _advance_* functions are SKIP state machines - always critical
  if (functionName.startsWith('_advance_')) {
    return 'critical';
  }

  // parse_rrule_parts: validation branches
  if (functionName === 'parse_rrule_parts') {
    if (/RAISE|Invalid|Duplicate|EXCEPTION/i.test(condition)) {
      return 'critical';
    }
    return 'high';
  }

  // Exception handlers are always critical
  if (/WHEN OTHERS|EXCEPTION/i.test(condition)) {
    return 'critical';
  }

  // SKIP logic is critical
  if (/skip.*OMIT|skip.*FORWARD|skip.*BACKWARD|p_skip|result\.skip/i.test(condition)) {
    return 'critical';
  }

  // BYxxx expansion is high risk
  if (/rule\.by(?:day|month|monthday|yearday|weekno|setpos|hour|minute|second)/i.test(condition)) {
    return 'high';
  }

  // Frequency dispatch is high risk
  if (/freq\s*=\s*'(?:DAILY|WEEKLY|MONTHLY|YEARLY)'/i.test(condition)) {
    return 'high';
  }

  // Output/iteration limits are high risk
  if (/output_limit|result_count|period_limit|rule\.count|rule\.until/i.test(condition)) {
    return 'high';
  }

  // NULL checks are medium
  if (/IS NULL|IS NOT NULL|COALESCE/i.test(condition)) {
    return 'medium';
  }

  // Date part extractions are medium
  if (/date_part|EXTRACT/i.test(condition)) {
    return 'medium';
  }

  // Loop controls are low
  if (/EXIT WHEN|CONTINUE WHEN|RETURN;$/i.test(condition)) {
    return 'low';
  }

  return 'medium';
}

function extractBranches(content) {
  const branches = [];
  const lines = content.split('\n');

  let currentFunction = null;
  let branchCount = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNum = i + 1;

    // Track current function - detect ANY function definition
    const funcMatch = line.match(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:rrule\.)?["']?(\w+)["']?/i);
    if (funcMatch) {
      const funcName = funcMatch[1];
      // Only track branches in KEY_FUNCTIONS, reset for others
      if (KEY_FUNCTIONS.includes(funcName)) {
        currentFunction = funcName;
        branchCount = 0;
      } else {
        currentFunction = null; // Not a key function, stop tracking
      }
    }

    // Skip if not in a key function
    if (!currentFunction) {
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
        condition: condition.substring(0, 70) + (condition.length > 70 ? '...' : ''),
        risk: classifyRisk(condition, currentFunction),
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
        condition: condition.substring(0, 70) + (condition.length > 70 ? '...' : ''),
        risk: classifyRisk(condition, currentFunction),
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
        risk: classifyRisk('else', currentFunction),
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
        condition: condition.substring(0, 70) + (condition.length > 70 ? '...' : ''),
        risk: classifyRisk(condition, currentFunction),
      });
    }

    // Detect EXCEPTION WHEN statements (separate from regular WHEN)
    if (line.match(/WHEN\s+OTHERS\s+THEN/i)) {
      branchCount++;
      branches.push({
        type: 'EXCEPTION',
        function: currentFunction,
        line: lineNum,
        branch: branchCount,
        condition: 'WHEN OTHERS (exception handler)',
        risk: 'critical',
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
      let funcName = match[1].toLowerCase();
      // Map alias to full function name
      funcName = FUNCTION_ALIASES[funcName] || funcName;
      covered.add(`${funcName}-${match[2]}`);
    }

    // Also look for test names in assert calls
    const assertMatch = line.match(/assert_\w+\s*\(\s*'BRANCH-(\w+)-(\d+)/i);
    if (assertMatch) {
      let funcName = assertMatch[1].toLowerCase();
      // Map alias to full function name
      funcName = FUNCTION_ALIASES[funcName] || funcName;
      covered.add(`${funcName}-${assertMatch[2]}`);
    }
  }

  return covered;
}

function main() {
  const verbose = process.argv.includes('--verbose');
  const criticalOnly = process.argv.includes('--critical');

  console.log('='.repeat(70));
  console.log('BRANCH COVERAGE VERIFICATION');
  console.log('='.repeat(70));
  console.log('');

  // Read files
  const rruleSql = fs.readFileSync(RRULE_SQL, 'utf8');
  const branchTests = fs.readFileSync(BRANCH_TESTS, 'utf8');

  // Extract branches from source
  const branches = extractBranches(rruleSql);

  // Group by function
  const byFunction = {};
  for (const branch of branches) {
    if (!byFunction[branch.function]) {
      byFunction[branch.function] = [];
    }
    byFunction[branch.function].push(branch);
  }

  console.log(`Found ${branches.length} branches in key functions:\n`);
  for (const [func, funcBranches] of Object.entries(byFunction)) {
    console.log(`  ${func}: ${funcBranches.length} branches`);
  }

  // Extract test coverage
  const covered = extractTestCoverage(branchTests);
  console.log(`\nTest file references ${covered.size} branches by name.\n`);

  // Calculate coverage with risk breakdown
  const stats = {
    total: branches.length,
    tested: 0,
    untested: 0,
    byRisk: {
      critical: { total: 0, tested: 0, untested: [] },
      high: { total: 0, tested: 0, untested: [] },
      medium: { total: 0, tested: 0, untested: [] },
      low: { total: 0, tested: 0, untested: [] },
    },
  };

  for (const branch of branches) {
    const key = `${branch.function}-${branch.branch}`.toLowerCase();
    const isTested = covered.has(key);
    branch.tested = isTested;

    stats.byRisk[branch.risk].total++;
    if (isTested) {
      stats.tested++;
      stats.byRisk[branch.risk].tested++;
    } else {
      stats.untested++;
      stats.byRisk[branch.risk].untested.push(branch);
    }
  }

  console.log('='.repeat(70));
  console.log('COVERAGE ANALYSIS');
  console.log('='.repeat(70));
  console.log('');

  const pct = ((stats.tested / Math.max(stats.total, 1)) * 100).toFixed(1);
  console.log(`Source branches:  ${stats.total}`);
  console.log(`Tested branches:  ${stats.tested}`);
  console.log(`Coverage ratio:   ${pct}%`);
  console.log('');
  console.log('By Risk Level:');
  for (const [risk, data] of Object.entries(stats.byRisk)) {
    const rPct = data.total > 0 ? ((data.tested / data.total) * 100).toFixed(0) : 0;
    console.log(`  ${risk.toUpperCase().padEnd(8)}: ${data.tested}/${data.total} tested (${rPct}%)`);
  }

  console.log('');
  console.log('By Function:');
  for (const [func, funcBranches] of Object.entries(byFunction)) {
    const funcTested = funcBranches.filter(b => b.tested).length;
    const funcPct = ((funcTested / funcBranches.length) * 100).toFixed(0);
    console.log(`  ${func}: ${funcTested}/${funcBranches.length} (${funcPct}%)`);
  }

  // Show untested critical branches
  console.log('');
  console.log('-'.repeat(70));
  console.log('UNTESTED CRITICAL BRANCHES (Must test):');
  console.log('-'.repeat(70));
  for (const branch of stats.byRisk.critical.untested) {
    console.log(`  Line ${branch.line}: ${branch.function} - ${branch.condition}`);
  }
  if (stats.byRisk.critical.untested.length === 0) {
    console.log('  (all critical branches are tested)');
  }

  if (!criticalOnly) {
    // Show untested high-risk branches
    console.log('');
    console.log('-'.repeat(70));
    console.log('UNTESTED HIGH-RISK BRANCHES (Should test):');
    console.log('-'.repeat(70));
    const highUntested = stats.byRisk.high.untested;
    const showCount = verbose ? highUntested.length : Math.min(15, highUntested.length);
    for (let i = 0; i < showCount; i++) {
      const branch = highUntested[i];
      console.log(`  Line ${branch.line}: ${branch.function} - ${branch.condition}`);
    }
    if (highUntested.length > showCount) {
      console.log(`  ... and ${highUntested.length - showCount} more (use --verbose to see all)`);
    }
    if (highUntested.length === 0) {
      console.log('  (all high-risk branches are tested)');
    }
  }

  // Recommendations
  console.log('');
  console.log('='.repeat(70));
  console.log('RECOMMENDATIONS');
  console.log('='.repeat(70));
  console.log('');

  if (stats.byRisk.critical.untested.length > 0) {
    console.log(`URGENT: ${stats.byRisk.critical.untested.length} critical branches lack tests.`);
    console.log('        Add tests for these validation and error handling paths.');
  } else if (stats.tested >= stats.total * 0.8) {
    console.log('Good coverage! Most branches have explicit tests.');
    console.log('Consider documenting remaining branches as equivalent or low-risk.');
  } else if (stats.tested >= stats.total * 0.5) {
    console.log('Moderate coverage. Focus on adding tests for high-risk branches.');
  } else {
    console.log('Low coverage. Many branches lack explicit tests.');
    console.log('Priority: Cover all critical branches first, then high-risk.');
  }

  console.log('');
  console.log('Run `node scripts/coverage-report.js` for detailed JSON report.');
  console.log('');
}

main();
