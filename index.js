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
 * Build driver-safe SQL from a psql install file by stripping psql
 * meta-commands (\set, \echo, \ir, etc.) and inlining \ir file references.
 *
 * The original install files use psql-specific commands for CLI users.
 * This function produces SQL that any PostgreSQL driver can execute directly.
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
      // Replace \ir with inlined file contents
      if (trimmed.startsWith('\\ir ')) {
        const includeFile = trimmed.substring(4).trim();
        return fs.readFileSync(path.join(baseDir, includeFile), 'utf8');
      }
      // Strip other psql meta-commands (lines starting with backslash)
      if (trimmed.startsWith('\\')) {
        return '';
      }
      // Strip transaction control statements (BEGIN/COMMIT) that break
      // outer transaction control when drivers wrap SQL in their own transaction.
      // Also strip RESET statements meant for psql post-transaction cleanup.
      if (/^(BEGIN|COMMIT)\s*;/i.test(trimmed)) {
        return '';
      }
      if (/^RESET\s+/i.test(trimmed)) {
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
  core: fs.readFileSync(path.join(srcDir, 'rrule.sql'), 'utf8'),
};

module.exports = { SQL };

// ES Module support
module.exports.default = { SQL };
