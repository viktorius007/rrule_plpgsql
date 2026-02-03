#!/usr/bin/env node
/**
 * Coverage Report Generator
 *
 * Generates a detailed JSON report of branch coverage including:
 * - Exact line numbers of untested branches
 * - The condition being checked
 * - Classification by risk level (Critical, High, Medium, Low)
 * - Suggested test cases for each untested branch
 *
 * Usage:
 *   node scripts/coverage-report.js
 *   node scripts/coverage-report.js --json    # Output only JSON
 *
 * Output:
 *   coverage-report.json
 */

const fs = require('fs');
const path = require('path');

const RRULE_SQL = path.join(__dirname, '..', 'src', 'rrule.sql');
const BRANCH_TESTS = path.join(__dirname, '..', 'tests', 'branches', 'test_branch_coverage.sql');
const OUTPUT_JSON = path.join(__dirname, '..', 'coverage-report.json');

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

// Risk classification rules
const RISK_RULES = {
  // Critical: Error handling, validation, SKIP logic, DST
  critical: [
    /RAISE EXCEPTION/i,
    /SKIP.*OMIT|SKIP.*FORWARD|SKIP.*BACKWARD/i,
    /p_skip\s*=/i,
    /result\.skip/i,
    /invalid|error|exception/i,
    /DST|timezone|AT TIME ZONE/i,
    /duplicate/i,
  ],
  // High: BYxxx expansion paths, period limits, COUNT/UNTIL
  high: [
    /rule\.by(?:day|month|monthday|yearday|weekno|setpos|hour|minute|second)/i,
    /output_limit|result_count|period_limit/i,
    /rule\.count|rule\.until/i,
    /FREQ\s*=/i,
    /freq\s*=\s*'(?:DAILY|WEEKLY|MONTHLY|YEARLY)'/i,
  ],
  // Medium: NULL guards, simple filters
  medium: [
    /IS NULL|IS NOT NULL/i,
    /COALESCE/i,
    /date_part/i,
    /EXTRACT/i,
  ],
  // Low: Redundant safety checks, defensive code
  low: [
    /EXIT WHEN/i,
    /CONTINUE WHEN/i,
    /RETURN;$/,
  ],
};

function classifyRisk(condition, branchType, functionName) {
  // Special case: parse_rrule_parts validation = Critical
  if (functionName === 'parse_rrule_parts') {
    if (condition.includes('RAISE') || condition.includes('Invalid') || condition.includes('Duplicate')) {
      return 'critical';
    }
    // Most parse_rrule_parts branches are validation
    return 'high';
  }

  // Special case: _advance_monthly/_advance_yearly SKIP logic = Critical
  if (functionName.startsWith('_advance_')) {
    return 'critical';
  }

  // Check against risk rules
  for (const pattern of RISK_RULES.critical) {
    if (pattern.test(condition)) return 'critical';
  }
  for (const pattern of RISK_RULES.high) {
    if (pattern.test(condition)) return 'high';
  }
  for (const pattern of RISK_RULES.medium) {
    if (pattern.test(condition)) return 'medium';
  }
  for (const pattern of RISK_RULES.low) {
    if (pattern.test(condition)) return 'low';
  }

  return 'medium'; // Default
}

function suggestTest(branch, functionName) {
  const condition = branch.condition.toLowerCase();

  // Parse function suggestions
  if (functionName === 'parse_rrule_parts') {
    if (condition.includes('until') && condition.includes('z$')) {
      return "Test UNTIL without Z suffix: 'FREQ=DAILY;UNTIL=20250101T120000' should raise error";
    }
    if (condition.includes('until') && condition.includes('8}')) {
      return "Test date-only UNTIL: 'FREQ=DAILY;UNTIL=20250101' should raise error";
    }
    if (condition.includes('freq=') && condition.includes('freq=')) {
      return "Test duplicate FREQ: 'FREQ=DAILY;FREQ=WEEKLY' should raise error";
    }
    if (condition.includes('count=-')) {
      return "Test negative COUNT: 'FREQ=DAILY;COUNT=-5' should raise error";
    }
    if (condition.includes('interval=-')) {
      return "Test negative INTERVAL: 'FREQ=DAILY;INTERVAL=-1' should raise error";
    }
    if (condition.includes('dup_param')) {
      return "Test duplicate parameter: 'FREQ=DAILY;COUNT=5;COUNT=10' should raise error";
    }
    if (condition.includes('bysecond') && condition.includes('60')) {
      return "Test BYSECOND=60 (leap second): 'FREQ=DAILY;BYSECOND=60' should normalize to 59";
    }
    if (condition.includes('bymonthday') && condition.includes('0')) {
      return "Test BYMONTHDAY=0: 'FREQ=MONTHLY;BYMONTHDAY=0' should raise error";
    }
    if (condition.includes('byyearday') && condition.includes('0')) {
      return "Test BYYEARDAY=0: 'FREQ=YEARLY;BYYEARDAY=0' should raise error";
    }
    if (condition.includes('byweekno') && condition.includes('0')) {
      return "Test BYWEEKNO=0: 'FREQ=YEARLY;BYWEEKNO=0' should raise error";
    }
    if (condition.includes('bysetpos') && condition.includes('0')) {
      return "Test BYSETPOS=0: 'FREQ=MONTHLY;BYDAY=MO;BYSETPOS=0' should raise error";
    }
    if (condition.includes('byhour') && condition.includes('freq')) {
      return "Test BYHOUR with WEEKLY: 'FREQ=WEEKLY;BYHOUR=9' should raise error";
    }
    return `Test validation error for condition: ${branch.condition}`;
  }

  // SKIP logic suggestions
  if (functionName === '_advance_monthly' || functionName === '_advance_yearly') {
    if (condition.includes('skip') && condition.includes('omit')) {
      return `Test SKIP=OMIT with invalid date: 'FREQ=${functionName.includes('monthly') ? 'MONTHLY' : 'YEARLY'};BYMONTHDAY=31;SKIP=OMIT'`;
    }
    if (condition.includes('skip') && condition.includes('forward')) {
      return `Test SKIP=FORWARD: 'FREQ=${functionName.includes('monthly') ? 'MONTHLY' : 'YEARLY'};BYMONTHDAY=31;SKIP=FORWARD'`;
    }
    if (condition.includes('period_limit')) {
      return "Test period limit termination (DoS protection)";
    }
    if (condition.includes('maxdate')) {
      return "Test maxdate termination (10-year window)";
    }
    if (condition.includes('until')) {
      return "Test UNTIL termination within SKIP loop";
    }
    return `Test SKIP state machine: ${branch.condition}`;
  }

  // Set function suggestions
  if (functionName.endsWith('_set')) {
    if (condition.includes('bymonth') && condition.includes('null')) {
      return "Test with and without BYMONTH filter";
    }
    if (condition.includes('byday') && condition.includes('null')) {
      return "Test with and without BYDAY filter";
    }
    if (condition.includes('bysetpos') && condition.includes('null')) {
      return "Test with and without BYSETPOS filter";
    }
    if (condition.includes('byweekno')) {
      return "Test with BYWEEKNO filter";
    }
    if (condition.includes('byyearday')) {
      return "Test with BYYEARDAY filter";
    }
    return `Test ${functionName} with filter: ${branch.condition}`;
  }

  // Main loop suggestions
  if (functionName.includes('rrule_event_instances_range')) {
    if (condition.includes("freq = 'daily'")) {
      return "Test FREQ=DAILY dispatch";
    }
    if (condition.includes("freq = 'weekly'")) {
      return "Test FREQ=WEEKLY dispatch";
    }
    if (condition.includes("freq = 'monthly'")) {
      return "Test FREQ=MONTHLY dispatch";
    }
    if (condition.includes("freq = 'yearly'")) {
      return "Test FREQ=YEARLY dispatch";
    }
    if (condition.includes('output_limit')) {
      return "Test 1000 result cap";
    }
    if (condition.includes('mindate')) {
      return "Test mindate filtering (range query)";
    }
    if (condition.includes('maxdate')) {
      return "Test maxdate termination";
    }
    return `Test main loop: ${branch.condition}`;
  }

  return `Add test for: ${branch.condition}`;
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
      const branch = {
        type: 'IF',
        function: currentFunction,
        line: lineNum,
        branch: branchCount,
        condition: condition,
        conditionShort: condition.substring(0, 80) + (condition.length > 80 ? '...' : ''),
      };
      branch.risk = classifyRisk(condition, 'IF', currentFunction);
      branch.suggestedTest = suggestTest(branch, currentFunction);
      branches.push(branch);
    }

    // Detect ELSIF statements
    if (line.match(/^\s*ELSIF\s+.+\s+THEN\s*$/i)) {
      branchCount++;
      const condition = line.replace(/^\s*ELSIF\s+/i, '').replace(/\s+THEN\s*$/i, '').trim();
      const branch = {
        type: 'ELSIF',
        function: currentFunction,
        line: lineNum,
        branch: branchCount,
        condition: condition,
        conditionShort: condition.substring(0, 80) + (condition.length > 80 ? '...' : ''),
      };
      branch.risk = classifyRisk(condition, 'ELSIF', currentFunction);
      branch.suggestedTest = suggestTest(branch, currentFunction);
      branches.push(branch);
    }

    // Detect ELSE statements
    if (line.match(/^\s*ELSE\s*$/i)) {
      branchCount++;
      const branch = {
        type: 'ELSE',
        function: currentFunction,
        line: lineNum,
        branch: branchCount,
        condition: '(else)',
        conditionShort: '(else)',
      };
      branch.risk = classifyRisk('else', 'ELSE', currentFunction);
      branch.suggestedTest = suggestTest(branch, currentFunction);
      branches.push(branch);
    }

    // Detect CASE WHEN statements
    if (line.match(/WHEN\s+.+\s+THEN/i) && !line.match(/EXCEPTION\s+WHEN/i)) {
      branchCount++;
      const condition = line.match(/WHEN\s+(.+?)\s+THEN/i)?.[1] || '';
      const branch = {
        type: 'WHEN',
        function: currentFunction,
        line: lineNum,
        branch: branchCount,
        condition: condition,
        conditionShort: condition.substring(0, 80) + (condition.length > 80 ? '...' : ''),
      };
      branch.risk = classifyRisk(condition, 'WHEN', currentFunction);
      branch.suggestedTest = suggestTest(branch, currentFunction);
      branches.push(branch);
    }

    // Detect EXCEPTION WHEN statements
    if (line.match(/WHEN\s+OTHERS\s+THEN/i)) {
      branchCount++;
      const branch = {
        type: 'EXCEPTION',
        function: currentFunction,
        line: lineNum,
        branch: branchCount,
        condition: 'WHEN OTHERS (exception handler)',
        conditionShort: 'WHEN OTHERS (exception handler)',
      };
      branch.risk = 'critical'; // Exception handlers are always critical
      branch.suggestedTest = 'Test invalid input that triggers exception handler';
      branches.push(branch);
    }
  }

  return branches;
}

// Map shortened test names to full function names
const FUNCTION_ALIASES = {
  'parse': 'parse_rrule_parts',
  'daily': 'daily_set',
  'weekly': 'weekly_set',
  'monthly': 'monthly_set',
  'yearly': 'yearly_set',
  'main': 'rrule_event_instances_range',
  'tz': 'rrule_event_instances_range_tz',
  'helper': 'helper_functions', // Generic
  'bysetpos': 'rrule_bysetpos_filter',
  'advance_monthly': '_advance_monthly',
  'advance_yearly': '_advance_yearly',
};

function extractTestCoverage(content) {
  const covered = new Map();
  const lines = content.split('\n');

  for (const line of lines) {
    // Look for test comments that reference branches
    // Format: -- BRANCH-function-N: description
    const match = line.match(/--\s*BRANCH-(\w+)-(\d+)/i);
    if (match) {
      let funcName = match[1].toLowerCase();
      // Try to map alias to full function name
      funcName = FUNCTION_ALIASES[funcName] || funcName;
      const key = `${funcName}-${match[2]}`.toLowerCase();
      covered.set(key, { comment: line.trim() });
    }

    // Also look for test names in assert calls
    const assertMatch = line.match(/assert_\w+\s*\(\s*'BRANCH-(\w+)-(\d+)/i);
    if (assertMatch) {
      let funcName = assertMatch[1].toLowerCase();
      // Try to map alias to full function name
      funcName = FUNCTION_ALIASES[funcName] || funcName;
      const key = `${funcName}-${assertMatch[2]}`.toLowerCase();
      if (!covered.has(key)) {
        covered.set(key, { assert: line.trim() });
      }
    }
  }

  return covered;
}

function generateReport(branches, covered) {
  const report = {
    generated: new Date().toISOString(),
    summary: {
      totalBranches: branches.length,
      testedBranches: 0,
      untestedBranches: 0,
      coverageRatio: 0,
      byRisk: {
        critical: { total: 0, tested: 0, untested: 0 },
        high: { total: 0, tested: 0, untested: 0 },
        medium: { total: 0, tested: 0, untested: 0 },
        low: { total: 0, tested: 0, untested: 0 },
      },
    },
    functions: {},
    untestedBranches: [],
  };

  // Process each branch
  for (const branch of branches) {
    const key = `${branch.function}-${branch.branch}`.toLowerCase();
    const isTested = covered.has(key);
    branch.tested = isTested;

    // Update summary
    if (isTested) {
      report.summary.testedBranches++;
    } else {
      report.summary.untestedBranches++;
      report.untestedBranches.push({
        function: branch.function,
        line: branch.line,
        branch: branch.branch,
        type: branch.type,
        condition: branch.conditionShort,
        risk: branch.risk,
        suggestedTest: branch.suggestedTest,
      });
    }

    // Update risk counts
    const risk = branch.risk || 'medium';
    report.summary.byRisk[risk].total++;
    if (isTested) {
      report.summary.byRisk[risk].tested++;
    } else {
      report.summary.byRisk[risk].untested++;
    }

    // Update function-level stats
    if (!report.functions[branch.function]) {
      report.functions[branch.function] = {
        total: 0,
        tested: 0,
        untested: [],
        branches: [],
      };
    }
    report.functions[branch.function].total++;
    if (isTested) {
      report.functions[branch.function].tested++;
    } else {
      report.functions[branch.function].untested.push({
        line: branch.line,
        branch: branch.branch,
        type: branch.type,
        condition: branch.conditionShort,
        risk: branch.risk,
        suggestedTest: branch.suggestedTest,
      });
    }
    report.functions[branch.function].branches.push({
      line: branch.line,
      branch: branch.branch,
      type: branch.type,
      condition: branch.conditionShort,
      risk: branch.risk,
      tested: isTested,
    });
  }

  // Calculate coverage ratio
  report.summary.coverageRatio = report.summary.totalBranches > 0
    ? (report.summary.testedBranches / report.summary.totalBranches * 100).toFixed(1)
    : 0;

  // Sort untested branches by risk (critical first)
  const riskOrder = { critical: 0, high: 1, medium: 2, low: 3 };
  report.untestedBranches.sort((a, b) => {
    const riskDiff = riskOrder[a.risk] - riskOrder[b.risk];
    if (riskDiff !== 0) return riskDiff;
    return a.line - b.line;
  });

  return report;
}

function main() {
  const jsonOnly = process.argv.includes('--json');

  // Read files
  const rruleSql = fs.readFileSync(RRULE_SQL, 'utf8');
  const branchTests = fs.readFileSync(BRANCH_TESTS, 'utf8');

  // Extract branches and coverage
  const branches = extractBranches(rruleSql);
  const covered = extractTestCoverage(branchTests);

  // Generate report
  const report = generateReport(branches, covered);

  // Write JSON report
  fs.writeFileSync(OUTPUT_JSON, JSON.stringify(report, null, 2));

  if (jsonOnly) {
    console.log(JSON.stringify(report, null, 2));
    return;
  }

  // Print summary
  console.log('='.repeat(70));
  console.log('BRANCH COVERAGE REPORT');
  console.log('='.repeat(70));
  console.log('');
  console.log(`Total branches:     ${report.summary.totalBranches}`);
  console.log(`Tested branches:    ${report.summary.testedBranches}`);
  console.log(`Untested branches:  ${report.summary.untestedBranches}`);
  console.log(`Coverage ratio:     ${report.summary.coverageRatio}%`);
  console.log('');
  console.log('By Risk Level:');
  console.log(`  Critical: ${report.summary.byRisk.critical.tested}/${report.summary.byRisk.critical.total} tested (${report.summary.byRisk.critical.untested} untested)`);
  console.log(`  High:     ${report.summary.byRisk.high.tested}/${report.summary.byRisk.high.total} tested (${report.summary.byRisk.high.untested} untested)`);
  console.log(`  Medium:   ${report.summary.byRisk.medium.tested}/${report.summary.byRisk.medium.total} tested (${report.summary.byRisk.medium.untested} untested)`);
  console.log(`  Low:      ${report.summary.byRisk.low.tested}/${report.summary.byRisk.low.total} tested (${report.summary.byRisk.low.untested} untested)`);
  console.log('');
  console.log('By Function:');
  for (const [func, stats] of Object.entries(report.functions)) {
    const pct = stats.total > 0 ? ((stats.tested / stats.total) * 100).toFixed(0) : 0;
    console.log(`  ${func}: ${stats.tested}/${stats.total} (${pct}%)`);
  }
  console.log('');
  console.log('-'.repeat(70));
  console.log('UNTESTED CRITICAL BRANCHES (Must test):');
  console.log('-'.repeat(70));
  for (const branch of report.untestedBranches.filter(b => b.risk === 'critical')) {
    console.log(`  Line ${branch.line}: ${branch.function} - ${branch.condition}`);
    console.log(`    Suggested: ${branch.suggestedTest}`);
  }
  console.log('');
  console.log('-'.repeat(70));
  console.log('UNTESTED HIGH-RISK BRANCHES (Should test):');
  console.log('-'.repeat(70));
  for (const branch of report.untestedBranches.filter(b => b.risk === 'high').slice(0, 20)) {
    console.log(`  Line ${branch.line}: ${branch.function} - ${branch.condition}`);
  }
  if (report.untestedBranches.filter(b => b.risk === 'high').length > 20) {
    console.log(`  ... and ${report.untestedBranches.filter(b => b.risk === 'high').length - 20} more`);
  }
  console.log('');
  console.log(`Report written to: ${OUTPUT_JSON}`);
}

main();
