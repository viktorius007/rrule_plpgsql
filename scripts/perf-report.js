#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

function parseArgs(argv) {
  const args = {
    db: process.env.DATABASE_URL || process.env.PGDATABASE || 'rrule_perf_pg17',
    baseline: 'tests/performance/perf_baseline_pg17.json',
    runs: 7,
    threshold: 0.20,
    updateBaseline: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--db') args.db = argv[++i];
    else if (token === '--baseline') args.baseline = argv[++i];
    else if (token === '--runs') args.runs = Number(argv[++i]);
    else if (token === '--threshold') args.threshold = Number(argv[++i]);
    else if (token === '--update-baseline') args.updateBaseline = true;
    else throw new Error(`Unknown argument: ${token}`);
  }

  if (!Number.isFinite(args.runs) || args.runs < 3) {
    throw new Error('--runs must be a number >= 3');
  }

  if (!Number.isFinite(args.threshold) || args.threshold < 0) {
    throw new Error('--threshold must be a non-negative number');
  }

  return args;
}

function psqlEval(db, sql) {
  const env = {
    ...process.env,
    PGHOST: process.env.PGHOST || 'localhost',
    PGPORT: process.env.PGPORT || '54322',
    PGUSER: process.env.PGUSER || 'postgres',
    PGPASSWORD: process.env.PGPASSWORD || 'postgres',
  };

  const child = spawnSync(
    'psql',
    ['-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-d', db, '-c', sql],
    { env, encoding: 'utf8' }
  );

  if (child.status !== 0) {
    throw new Error(`psql failed\nSQL: ${sql}\nSTDOUT:\n${child.stdout}\nSTDERR:\n${child.stderr}`);
  }

  return child.stdout.trim();
}

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
}

function loadBaseline(file) {
  const content = fs.readFileSync(file, 'utf8');
  return JSON.parse(content);
}

function saveBaseline(file, baseline) {
  fs.writeFileSync(file, `${JSON.stringify(baseline, null, 2)}\n`, 'utf8');
}

const BENCHMARKS = [
  {
    id: 'daily_cap_1000',
    description: 'High-volume DAILY rule to 1000 cap',
    sql: `SELECT COUNT(*)
          FROM rrule."all"('FREQ=DAILY', '2025-01-01 10:00:00'::TIMESTAMP);`,
  },
  {
    id: 'complex_bysetpos',
    description: 'Complex YEARLY with BYSETPOS and multi-BY filters',
    sql: `SELECT COUNT(*)
          FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=1,3,5,7,9,11;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,2,-2,-1;COUNT=600',
            '2025-01-01 09:00:00'::TIMESTAMP
          );`,
  },
  {
    id: 'tz_dst_daily',
    description: 'TIMESTAMPTZ recurrence across DST boundary',
    sql: `SELECT COUNT(*)
          FROM rrule."all"(
            'FREQ=DAILY;COUNT=400',
            '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
            'America/New_York'
          );`,
  },
  {
    id: 'overlaps_table_style',
    description: 'Table-style overlaps workload',
    sql: `WITH events AS (
            SELECT
              ('2025-01-01 10:00:00+00'::TIMESTAMPTZ + make_interval(days => gs)) AS dtstart,
              ('2025-01-01 11:00:00+00'::TIMESTAMPTZ + make_interval(days => gs)) AS dtend,
              'FREQ=DAILY;COUNT=400'::TEXT AS rrule
            FROM generate_series(1, 150) AS gs
          )
          SELECT COUNT(*)
          FROM events e
          WHERE rrule."overlaps"(
            e.dtstart,
            e.dtend,
            e.rrule,
            '2025-02-01 00:00:00+00'::TIMESTAMPTZ,
            '2025-08-01 00:00:00+00'::TIMESTAMPTZ,
            NULL
          );`,
  },
];

function executionTimeFor(db, sql) {
  const explain = psqlEval(db, `EXPLAIN (ANALYZE, FORMAT JSON) ${sql}`);
  const parsed = JSON.parse(explain);
  const time = parsed[0]['Execution Time'];

  if (!Number.isFinite(time)) {
    throw new Error(`Unable to parse execution time from EXPLAIN output: ${explain}`);
  }

  return time;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const baselinePath = path.resolve(args.baseline);
  const baseline = loadBaseline(baselinePath);

  const serverVersion = Number(psqlEval(args.db, "SELECT current_setting('server_version_num');"));
  if (serverVersion < 170000 || serverVersion >= 180000) {
    throw new Error(`Expected PostgreSQL 17.x for perf run, got server_version_num=${serverVersion}`);
  }

  console.log(`Performance regression check on database: ${args.db}`);
  console.log(`Runs per benchmark: ${args.runs}`);
  console.log(`Regression threshold: ${(args.threshold * 100).toFixed(1)}%`);
  console.log('');

  const failures = [];
  const measured = {};

  for (const benchmark of BENCHMARKS) {
    const times = [];
    for (let i = 0; i < args.runs; i += 1) {
      times.push(executionTimeFor(args.db, benchmark.sql));
    }

    const currentMedian = median(times);
    measured[benchmark.id] = {
      description: benchmark.description,
      median_ms: Number(currentMedian.toFixed(3)),
      runs: args.runs,
      samples_ms: times.map((v) => Number(v.toFixed(3))),
    };

    const baselineEntry = baseline.benchmarks[benchmark.id];
    if (!baselineEntry) {
      failures.push(`${benchmark.id}: missing baseline entry`);
      continue;
    }

    const allowed = baselineEntry.median_ms * (1 + args.threshold);
    const status = currentMedian <= allowed ? 'PASS' : 'FAIL';

    console.log(
      `${status} ${benchmark.id} | baseline=${baselineEntry.median_ms.toFixed(3)} ms ` +
      `| current=${currentMedian.toFixed(3)} ms | allowed<=${allowed.toFixed(3)} ms`
    );

    if (status === 'FAIL') {
      failures.push(
        `${benchmark.id}: current ${currentMedian.toFixed(3)} ms exceeds allowed ${allowed.toFixed(3)} ms`
      );
    }
  }

  if (args.updateBaseline) {
    const updated = {
      postgres_major: 17,
      default_runs: args.runs,
      default_threshold_pct: Math.round(args.threshold * 100),
      generated_at_utc: new Date().toISOString(),
      benchmarks: {},
    };

    for (const benchmark of BENCHMARKS) {
      updated.benchmarks[benchmark.id] = {
        description: benchmark.description,
        median_ms: measured[benchmark.id].median_ms,
      };
    }

    saveBaseline(baselinePath, updated);
    console.log('');
    console.log(`Updated baseline file: ${baselinePath}`);

    if (failures.length > 0) {
      console.log('Baseline update mode: regression checks are informational only.');
      process.exit(0);
    }
  }

  if (failures.length > 0) {
    console.error('');
    console.error('Performance regression failures:');
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exit(1);
  }

  console.log('');
  console.log('All performance checks passed.');
}

try {
  main();
} catch (error) {
  console.error(error.message || error);
  process.exit(1);
}
