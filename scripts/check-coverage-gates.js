#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const BRANCH_THRESHOLD = Number(process.env.BRANCH_COVERAGE_THRESHOLD || '100.0');
const STANDARD_THRESHOLD = Number(process.env.STATEMENT_THRESHOLD_STANDARD || '80.0');
const SUBDAY_WARN_THRESHOLD = Number(process.env.STATEMENT_THRESHOLD_SUBDAY_WARN || '80.0');
const SUBDAY_FLOOR_THRESHOLD = Number(process.env.STATEMENT_THRESHOLD_SUBDAY_FLOOR || '50.0');

const repoRoot = path.resolve(__dirname, '..');
const branchReportPath = path.join(repoRoot, process.env.BRANCH_REPORT_PATH || 'coverage-report.json');
const standardStatementReportPath = path.join(
  repoRoot,
  process.env.STATEMENT_REPORT_STANDARD || 'coverage-report-standard.txt',
);
const subdayStatementReportPath = path.join(
  repoRoot,
  process.env.STATEMENT_REPORT_SUBDAY || 'coverage-report-subday.txt',
);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function readStatementCoverage(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const match = content.match(/Overall Coverage:\s*([0-9]+(?:\.[0-9]+)?)%/);
  if (!match) {
    throw new Error(`Could not find "Overall Coverage" in ${filePath}`);
  }
  return Number(match[1]);
}

function ensureThreshold(name, value) {
  if (Number.isNaN(value)) {
    throw new Error(`Invalid numeric threshold for ${name}`);
  }
}

function main() {
  ensureThreshold('BRANCH_COVERAGE_THRESHOLD', BRANCH_THRESHOLD);
  ensureThreshold('STATEMENT_THRESHOLD_STANDARD', STANDARD_THRESHOLD);
  ensureThreshold('STATEMENT_THRESHOLD_SUBDAY_WARN', SUBDAY_WARN_THRESHOLD);
  ensureThreshold('STATEMENT_THRESHOLD_SUBDAY_FLOOR', SUBDAY_FLOOR_THRESHOLD);

  const branchReport = readJson(branchReportPath);
  const branchPct = Number(branchReport.summary.coverageRatio);
  const untestedBranches = Number(branchReport.summary.untestedBranches);

  const standardStatementPct = readStatementCoverage(standardStatementReportPath);
  const subdayStatementPct = readStatementCoverage(subdayStatementReportPath);

  const failures = [];
  const warnings = [];

  if (Number.isNaN(branchPct)) {
    failures.push('Branch coverage ratio is not a valid number.');
  } else if (branchPct < BRANCH_THRESHOLD) {
    failures.push(
      `Branch coverage ${branchPct.toFixed(1)}% is below threshold ${BRANCH_THRESHOLD.toFixed(1)}%.`,
    );
  }

  if (untestedBranches !== 0) {
    failures.push(`Branch report still has ${untestedBranches} untested branches.`);
  }

  if (Number.isNaN(standardStatementPct)) {
    failures.push('Standard statement coverage is not a valid number.');
  } else if (standardStatementPct < STANDARD_THRESHOLD) {
    failures.push(
      `Standard statement coverage ${standardStatementPct.toFixed(2)}% is below threshold ${STANDARD_THRESHOLD.toFixed(2)}%.`,
    );
  }

  if (Number.isNaN(subdayStatementPct)) {
    failures.push('Subday statement coverage is not a valid number.');
  } else if (subdayStatementPct < SUBDAY_FLOOR_THRESHOLD) {
    failures.push(
      `Subday statement coverage ${subdayStatementPct.toFixed(2)}% is below floor ${SUBDAY_FLOOR_THRESHOLD.toFixed(2)}%.`,
    );
  } else if (subdayStatementPct < SUBDAY_WARN_THRESHOLD) {
    warnings.push(
      `Subday statement coverage ${subdayStatementPct.toFixed(2)}% is below warning threshold ${SUBDAY_WARN_THRESHOLD.toFixed(2)}% (non-blocking).`,
    );
  }

  const subdayStatus = Number.isNaN(subdayStatementPct)
    ? 'INVALID'
    : subdayStatementPct < SUBDAY_FLOOR_THRESHOLD
      ? 'FAIL'
      : subdayStatementPct < SUBDAY_WARN_THRESHOLD
        ? 'WARN'
        : 'PASS';

  console.log('Coverage gates');
  console.log(`- Branch coverage:             ${branchPct.toFixed(1)}% (untested: ${untestedBranches})`);
  console.log(`- Statement coverage (standard): ${standardStatementPct.toFixed(2)}%`);
  console.log(`- Statement coverage (subday):   ${subdayStatementPct.toFixed(2)}% [${subdayStatus}]`);
  console.log(
    `- Thresholds: branch >= ${BRANCH_THRESHOLD.toFixed(1)}%, standard >= ${STANDARD_THRESHOLD.toFixed(2)}%, subday warn < ${SUBDAY_WARN_THRESHOLD.toFixed(2)}%, subday floor >= ${SUBDAY_FLOOR_THRESHOLD.toFixed(2)}%`,
  );

  if (warnings.length > 0) {
    console.warn('\nCoverage warnings:');
    for (const warning of warnings) {
      console.warn(`- ${warning}`);
    }
  }

  if (failures.length > 0) {
    console.error('\nCoverage gate failures:');
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exit(1);
  }

  console.log('\nCoverage gates passed.');
}

main();
