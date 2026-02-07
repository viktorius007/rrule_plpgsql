#!/usr/bin/env node

const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { SQL } = require('../../index');

const CONN_ENV = {
  ...process.env,
  PGHOST: process.env.PGHOST || 'localhost',
  PGPORT: process.env.PGPORT || '54322',
  PGUSER: process.env.PGUSER || 'postgres',
  PGPASSWORD: process.env.PGPASSWORD || 'postgres',
};

function runPsql({ db, sql, expectFailure = false }) {
  const child = spawnSync(
    'psql',
    ['-X', '-v', 'ON_ERROR_STOP=1', '-d', db],
    {
      input: sql,
      env: CONN_ENV,
      encoding: 'utf8',
    }
  );

  if (!expectFailure && child.status !== 0) {
    throw new Error(
      `psql failed (db=${db})\nSTDOUT:\n${child.stdout}\nSTDERR:\n${child.stderr}`
    );
  }

  if (expectFailure && child.status === 0) {
    throw new Error(`Expected psql failure, but command succeeded (db=${db})`);
  }

  return child;
}

function queryValue(db, sql) {
  const child = spawnSync(
    'psql',
    ['-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-d', db, '-c', sql],
    { env: CONN_ENV, encoding: 'utf8' }
  );

  if (child.status !== 0) {
    throw new Error(
      `Query failed (db=${db})\nSQL: ${sql}\nSTDOUT:\n${child.stdout}\nSTDERR:\n${child.stderr}`
    );
  }

  return child.stdout.trim();
}

function createDatabase(db) {
  runPsql({ db: 'postgres', sql: `DROP DATABASE IF EXISTS ${db};` });
  runPsql({ db: 'postgres', sql: `CREATE DATABASE ${db};` });
}

function dropDatabase(db) {
  runPsql({ db: 'postgres', sql: `DROP DATABASE IF EXISTS ${db};` });
}

function assertNoUnresolvedPsqlMetaCommands(name, sql) {
  assert.ok(typeof sql === 'string' && sql.length > 0, `${name} should be non-empty SQL`);

  const knownMeta = /(^|\n)\s*\\(set|echo|i|ir|dt|df)\b/i;
  assert.ok(!knownMeta.test(sql), `${name} contains unresolved known psql meta-command`);

  const anyMeta = /(^|\n)\s*\\[A-Za-z]/;
  assert.ok(!anyMeta.test(sql), `${name} contains unresolved psql backslash command`);
}

function assertPg17(db) {
  const versionNum = Number(queryValue(db, "SELECT current_setting('server_version_num');"));
  assert.ok(versionNum >= 170000 && versionNum < 180000, `Expected PostgreSQL 17.x, got ${versionNum}`);
}

function assertSessionStateNotLeaked(db, expectedTimezone, expectedSearchPath) {
  const timezoneAfter = queryValue(db, 'SHOW TimeZone;');
  const searchPathAfter = queryValue(db, 'SHOW search_path;');

  assert.equal(timezoneAfter, expectedTimezone, 'TimeZone changed after SQL export execution');
  assert.equal(searchPathAfter, expectedSearchPath, 'search_path changed after SQL export execution');
}

function testInstallExport() {
  const db = 'rrule_pkg_contract_install';
  createDatabase(db);

  try {
    assertPg17(db);

    const timezoneBefore = queryValue(db, 'SHOW TimeZone;');
    const searchPathBefore = queryValue(db, 'SHOW search_path;');

    runPsql({ db, sql: SQL.install });

    assert.equal(queryValue(db, "SELECT to_regnamespace('rrule') IS NOT NULL;"), 't');
    assert.equal(
      queryValue(db, "SELECT COUNT(*) FROM rrule.\"all\"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP);"),
      '3'
    );

    const hourlyFailure = runPsql({
      db,
      sql: "SELECT COUNT(*) FROM rrule.\"all\"('FREQ=HOURLY;COUNT=2', '2025-01-01 10:00:00'::TIMESTAMP);",
      expectFailure: true,
    });

    const errorText = `${hourlyFailure.stdout}\n${hourlyFailure.stderr}`;
    assert.ok(
      errorText.includes('install_with_subday.sql'),
      'Standard install HOURLY error must guide user to install_with_subday.sql'
    );

    assertSessionStateNotLeaked(db, timezoneBefore, searchPathBefore);
  } finally {
    dropDatabase(db);
  }
}

function testInstallWithSubdayExport() {
  const db = 'rrule_pkg_contract_subday';
  createDatabase(db);

  try {
    assertPg17(db);

    const timezoneBefore = queryValue(db, 'SHOW TimeZone;');
    const searchPathBefore = queryValue(db, 'SHOW search_path;');

    runPsql({ db, sql: SQL.installWithSubday });

    assert.equal(
      queryValue(db, "SELECT COUNT(*) FROM rrule.\"all\"('FREQ=HOURLY;COUNT=2', '2025-01-01 10:00:00'::TIMESTAMP);"),
      '2'
    );
    assert.equal(
      queryValue(db, "SELECT COUNT(*) FROM rrule.\"all\"('FREQ=MINUTELY;COUNT=2', '2025-01-01 10:00:00'::TIMESTAMP);"),
      '2'
    );

    assertSessionStateNotLeaked(db, timezoneBefore, searchPathBefore);
  } finally {
    dropDatabase(db);
  }
}

function testCoreExport() {
  const db = 'rrule_pkg_contract_core';
  createDatabase(db);

  try {
    assertPg17(db);

    const timezoneBefore = queryValue(db, 'SHOW TimeZone;');
    const searchPathBefore = queryValue(db, 'SHOW search_path;');

    runPsql({
      db,
      sql: `
DROP SCHEMA IF EXISTS rrule CASCADE;
CREATE SCHEMA rrule;
SET search_path = rrule, public;
${SQL.core}
RESET search_path;
`,
    });

    assert.equal(
      queryValue(db, "SELECT COUNT(*) FROM rrule.\"all\"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP);"),
      '3'
    );

    const hourlyFailure = runPsql({
      db,
      sql: "SELECT COUNT(*) FROM rrule.\"all\"('FREQ=HOURLY;COUNT=2', '2025-01-01 10:00:00'::TIMESTAMP);",
      expectFailure: true,
    });

    const errorText = `${hourlyFailure.stdout}\n${hourlyFailure.stderr}`;
    assert.ok(
      errorText.includes('install_with_subday.sql'),
      'Core export should keep standard-install HOURLY rejection behavior'
    );

    assertSessionStateNotLeaked(db, timezoneBefore, searchPathBefore);
  } finally {
    dropDatabase(db);
  }
}

function main() {
  console.log('Running SQL export contract tests...');

  assertNoUnresolvedPsqlMetaCommands('SQL.install', SQL.install);
  assertNoUnresolvedPsqlMetaCommands('SQL.installWithSubday', SQL.installWithSubday);
  assertNoUnresolvedPsqlMetaCommands('SQL.core', SQL.core);

  testInstallExport();
  testInstallWithSubdayExport();
  testCoreExport();

  console.log('All SQL export contract tests passed.');
}

try {
  main();
} catch (error) {
  console.error(error.message || error);
  process.exit(1);
}
