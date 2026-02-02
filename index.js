/**
 * rrule-plpgsql - Pure PL/pgSQL RFC 5545 RRULE implementation
 *
 * This package exports SQL as strings, making it compatible with
 * any PostgreSQL client (pg, TypeORM, Prisma, Knex, Sequelize, etc.)
 *
 * Philosophy: Export SQL strings, not opinions.
 * Users call their client's method directly - no magic, no auto-detection.
 *
 * @license MIT
 */

const fs = require('fs');
const path = require('path');

/**
 * Strip SET/RESET timezone commands from SQL content.
 * Used for both inlined files and the core export.
 *
 * Removes SET timezone and RESET timezone commands that would leak into
 * connection pool sessions after installation completes.
 *
 * Preserves SET search_path and RESET search_path because these are
 * required for CREATE FUNCTION statements to target the rrule schema.
 * Without search_path, functions are created in the caller's default
 * schema (typically public), breaking all schema-qualified internal calls.
 *
 * @param {string} sql - Raw SQL content
 * @returns {string} SQL with timezone session state commands removed
 */
function stripSessionState(sql) {
  return sql
    .split('\n')
    .map(line => {
      const trimmed = line.trim();
      if (/^SET\s+timezone\s*/i.test(trimmed)) {
        return '';
      }
      if (/^RESET\s+timezone\s*/i.test(trimmed)) {
        return '';
      }
      return line;
    })
    .join('\n');
}

/**
 * Build driver-safe SQL from a psql install file by stripping psql
 * meta-commands (\set, \echo, \ir, etc.) and inlining \ir file references.
 *
 * The original install files use psql-specific commands for CLI users.
 * This function produces SQL that any PostgreSQL driver can execute directly.
 *
 * Retains BEGIN/COMMIT to keep installation atomic. Strips SET/RESET session
 * state commands to prevent leaking into connection pool sessions.
 *
 * @param {string} installFile - Filename of the install script (e.g. 'install.sql')
 * @param {string} baseDir - Directory containing the SQL files
 * @returns {string} Driver-safe SQL with all \ir references inlined
 */
function buildDriverSafeSQL(installFile, baseDir) {
  const content = fs.readFileSync(path.join(baseDir, installFile), 'utf8');
  return content
    .split('\n')
    .map(line => {
      const trimmed = line.trim();
      // Replace \ir with inlined file contents (also strip SET/RESET timezone from inlined files)
      if (trimmed.startsWith('\\ir ')) {
        const includeFile = trimmed.substring(4).trim();
        const inlined = fs.readFileSync(path.join(baseDir, includeFile), 'utf8');
        return stripSessionState(inlined);
      }
      // Strip other psql meta-commands (lines starting with backslash)
      if (trimmed.startsWith('\\')) {
        return '';
      }
      // Strip SET/RESET timezone commands that leak into connection pool
      // sessions after installation completes. These are only needed for
      // psql CLI context; drivers should not modify session state as a
      // side effect of installing functions.
      // Preserves SET/RESET search_path which is required for CREATE
      // FUNCTION statements to target the rrule schema.
      if (/^SET\s+timezone\s*/i.test(trimmed)) {
        return '';
      }
      if (/^RESET\s+timezone\s*/i.test(trimmed)) {
        return '';
      }
      return line;
    })
    .join('\n');
}

/**
 * Raw SQL strings for all components
 *
 * Driver-safe: all psql meta-commands are stripped and file includes are
 * inlined, so these strings work with any PostgreSQL client's query method:
 * - pg: await client.query(SQL.install)
 * - TypeORM: await queryRunner.query(SQL.install)
 * - Prisma: await prisma.$executeRawUnsafe(SQL.install)
 * - Knex: await knex.raw(SQL.install)
 * - Sequelize: await sequelize.query(SQL.install)
 */
const srcDir = path.join(__dirname, 'src');
const SQL = {
  /** Complete installation SQL (includes all RRULE functions) */
  install: buildDriverSafeSQL('install.sql', srcDir),

  /** Installation with sub-day frequency support (HOURLY, MINUTELY, SECONDLY) */
  installWithSubday: buildDriverSafeSQL('install_with_subday.sql', srcDir),

  /** Core RRULE functions only (no schema setup - for advanced use cases) */
  core: stripSessionState(fs.readFileSync(path.join(srcDir, 'rrule.sql'), 'utf8')),
};

module.exports = { SQL };

// ES Module support
module.exports.default = { SQL };
