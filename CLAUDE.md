# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pure PL/pgSQL implementation of RFC 5545 iCalendar RRULE for PostgreSQL. No C extensions - works on managed services (AlloyDB, RDS, Azure, Cloud SQL). Packaged as npm module that exports raw SQL strings.

## Commands

```bash
# Run all tests (62 test suites total)
npm test
./test.sh

# Run specific test modes
./test.sh --standard    # DAILY/WEEKLY/MONTHLY/YEARLY only
./test.sh --subday      # Include HOURLY/MINUTELY/SECONDLY
./test.sh --both        # Full CI mode

# Run a single test file (must set up DB connection env vars)
PGHOST=localhost PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres \
  psql -d rrule_test -f tests/test_validation.sql

# Lint PL/pgSQL code (must pass with 0 errors, 0 warnings)
npm run lint
./lint.sh

# Lint SQL files for coding standards (no database required)
npm run lint:tests
./lint-tests.sh

# Fresh reinstall after changes
psql -d your_db -c "DROP SCHEMA IF EXISTS rrule CASCADE"
psql -d your_db -f src/install.sql
```

**Test database:** Requires PostgreSQL 12+. Default connection `localhost:54322` with user/password `postgres/postgres`. Override with `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, or `DATABASE_URL`. The test runner creates and drops `rrule_test` automatically; running a single test file requires the database to already exist with rrule functions installed.

## Architecture

**SQL-as-NPM-Package:** This is database code, not application code. Changes go in `/src/rrule.sql`. The npm package (`index.js`) strips psql meta-commands (`\set`, `\echo`) and inlines `\ir` file references to produce driver-safe SQL strings. Exports: `SQL.install`, `SQL.installWithSubday`, `SQL.core`. Works with pg, TypeORM, Prisma, Knex, Sequelize.

**Schema Namespacing:** All functions live in `rrule` PostgreSQL schema. Always use schema-qualified names: `rrule."all"()`, `rrule."between"()`, etc.

**Public API Functions:**
- `rrule."all"(rrule, dtstart)` - All occurrences (SETOF TIMESTAMP), capped at 1000 results / 10-year window
- `rrule."between"(rrule, dtstart, start, end, inc DEFAULT false)` - Range query, capped at 1000 results
- `rrule."after"(rrule, dtstart, date, inc DEFAULT false)` / `rrule."before"(rrule, dtstart, date, inc DEFAULT false)` - Single occurrence
- `rrule."next"(rrule, dtstart)` / `rrule."most_recent"(rrule, dtstart)` - Relative to dtstart
- `rrule."count"(rrule, dtstart)` - Total count (inherits caps from `all()`)
- `rrule."overlaps"(dtstart, dtend, rrule, min, max, timezone DEFAULT NULL)` - Conflict detection

**API Limits:** `all()` and `between()` cap results at 1000 occurrences and a 10-year window from dtstart. Rules without COUNT or UNTIL that hit the cap emit a `RAISE WARNING`. `count()` delegates to `all()` and inherits these caps. These limits exist because RFC 5545 rules without COUNT/UNTIL recur infinitely.

**Two Timezone APIs:**
- TIMESTAMP API: Uses `TZID=` in RRULE string (rrule.js compatible)
- TIMESTAMPTZ API: Explicit timezone parameter (PostgreSQL-native)

**Frequencies:**
- Enabled by default: DAILY, WEEKLY, MONTHLY, YEARLY
- Disabled by default: HOURLY, MINUTELY, SECONDLY (use `install_with_subday.sql` to enable)

## Key Files

- `/src/rrule.sql` - Core implementation (~3900 lines)
- `/src/rrule_subday.sql` - Sub-day frequency overrides (~774 lines)
- `/src/install.sql` - Standard installation
- `/src/install_with_subday.sql` - Installation with sub-day frequencies
- `/tests/*.sql` and subdirectories - 33 test files covering validation, frequencies, timezone, RFC compliance, branch coverage, security, parity
- `/tests/helpers.sql` - Shared test assertion functions (`assert_occurrences_equal`, `assert_equals`, `assert_true`)
- `DECISIONS.md` - Prescriptive architectural decisions with verification links
- `TESTING_STANDARDS.md` - Required test patterns (ROLLBACK, fixed timestamps, exact assertions)
- `docs/SPEC_COMPLIANCE.md` - RFC 5545/7529 compliance status and documented gaps

## Documentation

### User Documentation (docs/)

| Document | Description |
|----------|-------------|
| [INSTALLATION.md](docs/INSTALLATION.md) | TypeScript/ORM integration (node-postgres, Prisma, Knex, TypeORM, Sequelize, Drizzle) |
| [EXAMPLE_USAGE.md](docs/EXAMPLE_USAGE.md) | Real-world patterns: subscription billing, batch operations, conflict detection |
| [API_REFERENCE.md](docs/API_REFERENCE.md) | Complete function reference with parameters and examples |
| [SPEC_COMPLIANCE.md](docs/SPEC_COMPLIANCE.md) | RFC 5545/7529 feature support matrix and limitations |
| [VALIDATION.md](docs/VALIDATION.md) | RRULE validation rules and error messages |
| [SECURITY.md](docs/SECURITY.md) | SQL injection prevention, supply chain security, best practices |
| [PERFORMANCE.md](docs/PERFORMANCE.md) | Indexes, query patterns, monitoring, scaling recommendations |
| [SUBDAY_OPERATIONS.md](docs/SUBDAY_OPERATIONS.md) | HOURLY/MINUTELY/SECONDLY guide (disabled by default) |
| [MIGRATION.md](docs/MIGRATION.md) | Upgrading with dependent database objects |

### Developer Documentation (root)

| Document | Description |
|----------|-------------|
| [DEVELOPMENT.md](DEVELOPMENT.md) | Testing, architecture, contribution guidelines |
| [TESTING_STANDARDS.md](TESTING_STANDARDS.md) | Prescriptive test patterns |
| [DECISIONS.md](DECISIONS.md) | Design decisions with verification links |

### Archived Documentation (docs/archived/)

Historical documents (completed research, plans) are in [docs/archived/](docs/archived/).

## CI/CD Pipeline

GitHub Actions (`.github/workflows/test.yml`) runs on push/PR to main:
1. `./test.sh --both` — full test suite (standard + sub-day)
2. `./lint.sh` — plpgsql_check semantic linting (requires PostgreSQL + plpgsql_check extension)
3. `./lint-tests.sh` — static SQL coding standards (bash-based, no database required)

All three must pass. Uses PostgreSQL 14 and Node.js 20.

## Internal Architecture

The call chain from public API to occurrence generation:

1. **Public API** (`rrule."all"`, `"between"`, `"after"`, etc.) → calls `rrule_event_instances_range()` or `rrule_event_instances_range_tz()`
2. **Dispatcher** (`rrule_event_instances_range`) → parses RRULE via `parse_rrule_parts()`, then dispatches to the appropriate frequency set function
3. **Frequency Sets** (`daily_set`, `weekly_set`, `monthly_set`, `yearly_set`) → generate candidate occurrences by advancing the base date by INTERVAL, applying BYxxx expansion/filtering
4. **BYxxx Helpers** (`rrule_month_byday_set`, `rrule_month_bymonthday_set`, `rrule_week_byday_set`, etc.) → expand candidates for specific BYxxx rules
5. **Filter Functions** (`test_byday_rule`, `test_bymonth_rule`, `test_bymonthday_rule`, `test_byyearday_rule`, `byweekno_matches`) → filter candidates that don't match BYxxx constraints
6. **BYSETPOS** (`rrule_bysetpos_filter`) → cursor-based post-filter that selects specific positions from the candidate set
7. **Time Expansion** (`rrule_expand_dates_with_times`) → expands date candidates with BYHOUR/BYMINUTE/BYSECOND time slots for WEEKLY/MONTHLY/YEARLY frequencies

**Two parallel generators exist:** `rrule_event_instances_range()` (TIMESTAMP, used by TIMESTAMP API) and `rrule_event_instances_range_tz()` (TIMESTAMP, used by TIMESTAMPTZ API). Both have identical structure with 4 frequency branches each. Changes to the main loop logic (caps, boundary checks, EXIT conditions) must be applied to both generators.

The TIMESTAMPTZ API wraps the TIMESTAMP API by converting to/from a target timezone using `AT TIME ZONE`, preserving wall-clock semantics across DST transitions.

**Four parallel generators total:** TIMESTAMP and TIMESTAMPTZ variants exist in both `rrule.sql` and `rrule_subday.sql`. Any fix to loop logic must be applied to all 4.

**Generator Loop Structure:**
- WHILE loop (`current_base <= maxdate`) controls **period iteration** — when to stop generating new periods
- Inner EXIT (`current > maxdate`) controls **candidate filtering** — skip candidates exceeding the boundary
- These are different variables serving different purposes; both conditions are necessary

**Iteration Limit Multipliers** (`calculate_safe_iteration_limit`):
| Frequency | Multiplier | Rationale |
|-----------|------------|-----------|
| DAILY | 62x | Worst case: BYMONTHDAY=31 from Feb 1 → Mar 31 = 58 days gap |
| WEEKLY | 8x | Standard week gaps |
| MONTHLY | 13x | Month variations |
| YEARLY | 2x | Leap year handling |

**Boundary Workarounds:** The `+ INTERVAL '1 day'` patterns at lines 2808, 2933, 3493, 3670 handle `inc=true` for between/before/after functions — a different scenario from the WHILE loop boundary.

## Development Rules

1. **RFC Compliance:** All features must comply with RFC 5545 (RRULE) or RFC 7529 (SKIP/RSCALE). Invalid combinations must be rejected with descriptive errors.

2. **Schema Qualification:** Every function reference must use `rrule.` prefix. Internal functions use `rrule._` naming convention. Tests must use schema-qualified API calls (`rrule."all"(...)`, never unqualified `"all"(...)`).

3. **Testing Required:** All tests must pass. No human code review - tests are the quality gate. Run full suite after any change.

4. **Linting Required:** `plpgsql_check` must report 0 errors and 0 warnings. `lint-tests.sh` must also pass (static SQL coding standards).

5. **Type Safety:** Use explicit parameter types, proper NULL handling with `IS DISTINCT FROM` (never `= NULL` / `<> NULL` / `!= NULL`). Mark functions VOLATILE (cursors, SET timezone, set_config), STABLE (internal computation calling other STABLE/VOLATILE functions), or IMMUTABLE (pure-computation helpers only: `weekday_to_number`, `byweekno_matches`, `calculate_safe_iteration_limit`, `version`, `_restore_monthly_base`, `_restore_yearly_base`).

6. **Security:** Sub-day frequencies are disabled by default to prevent DoS (31M+ occurrences/year for SECONDLY). Changes to this require explicit justification.

7. **API Defaults:** `between`, `after`, and `before` accept `inc BOOLEAN DEFAULT FALSE`. Do not change the default to TRUE -- it matches rrule.js and python-dateutil reference implementations.

8. **Testing Standards:** Follow rules in [TESTING_STANDARDS.md](TESTING_STANDARDS.md) -- key rules: ROLLBACK not COMMIT, fixed timestamps not NOW(), exact assertions not loose comparisons, ORDER BY in array_agg, test boundary/invalid inputs, test DST gap times, test BYxxx deduplication.

9. **SKIP/Drift Helper Functions:** The MONTHLY/YEARLY SKIP and drift prevention logic is centralized in shared helpers: `_restore_monthly_base()`, `_restore_yearly_base()`, `_advance_monthly()`, and `_advance_yearly()`. All four generators (TIMESTAMP and TZ variants in both `rrule.sql` and `rrule_subday.sql`) call these helpers. Fix SKIP/drift issues in the helper functions, not in the generators themselves.

10. **Test with INTERVAL > 1:** When modifying period advancement logic (MONTHLY/YEARLY branches), always test with `INTERVAL=2` or higher. SKIP and drift prevention interact with INTERVAL in non-obvious ways — a fix that works for `INTERVAL=1` can silently break for `INTERVAL=2` because the forwarded/skipped date may land across a different period boundary.

11. **Never limit candidate generation before post-filters:** When set functions (e.g., `yearly_set`) pass `max_results` to inner generators but then apply WHERE-clause post-filters, the limit must be passed as NULL. Otherwise the post-filter rejects candidates the generator already counted against the limit, producing fewer results than requested. General principle: limit at the outermost consumer, not at the generator.

12. **Run manual spot-checks from plans:** When a plan specifies manual verification queries, run them as a final step even if the test suite passes. Tests validate expected values set during development — spot-checks validate against the original specification.

13. **Parallel Agent Git Isolation:** When launching multiple agents that edit files in parallel, each agent MUST use `git worktree add /tmp/{branch-name} -b {branch-name}` to get its own isolated working directory. Agents sharing a single checkout will clobber each other's uncommitted changes, switch branches out from under each other, and commit to wrong branches. After agents complete, merge worktree branches sequentially onto main from the primary checkout. Clean up worktrees with `git worktree remove`.

14. **Update all 4 generators:** When fixing loop logic (boundary checks, EXIT conditions, caps), apply changes to all 4 generators: `rrule_event_instances_range()` and `rrule_event_instances_range_tz()` in both `rrule.sql` and `rrule_subday.sql`.

15. **Search for outdated references after fixes:** After fixing an issue, search the codebase for comments, documentation, and test strategies that reference the old behavior. Common locations: ISSUES.md findings sections, `strategies.py` docstrings, `known_differences.py`.

16. **Reinstall schema before manual spot-checks:** After `./test.sh`, the rrule schema may be dropped during cleanup. Run `psql -d rrule_test -f src/install.sql` before manual verification queries.

17. **Verify property test strategies generate expected values:** When extending Hypothesis strategies (e.g., adding negative BYWEEKNO), verify the strategy actually generates the new values by sampling with a quick script.

18. **Profiler 0% coverage means the function was never called:** The `plpgsql_check` profiler accurately counts all PL/pgSQL executions. If a function shows 0%, it wasn't called during the profiler run — not a measurement limitation. The profiler script has its own test workload separate from the test suite; ensure it exercises all code paths. Example: `byweekno_matches()` showed 0% because the profiler workload only had pure BYWEEKNO rules (which use a generator path), not BYMONTH+BYWEEKNO rules (which use `byweekno_matches` as a filter).

## RRULE Parameters Supported

FREQ, COUNT, UNTIL, INTERVAL, BYDAY (with ordinals like 2MO/-1FR), BYMONTHDAY, BYMONTH, BYYEARDAY, BYWEEKNO, BYSETPOS, WKST, TZID, SKIP (OMIT/BACKWARD/FORWARD), RSCALE (GREGORIAN only)

## RFC Compliance Gap Analysis

**Overall: ~97% RFC 5545 compliant, production-ready for Gregorian calendars**

### Fully Compliant
- All 7 FREQ types (sub-day implemented but disabled by default for security)
- All BYxxx parameters with negative index support
- All 18 RFC 5545 Section 3.3.10 validation rules
- WKST, BYWEEKNO (ISO 8601), leap year handling
- RFC 7529 SKIP parameter (OMIT/BACKWARD/FORWARD) including YEARLY+BYMONTH path
- Automatic RSCALE=GREGORIAN when SKIP is used

### Intentional Limitations (Documented in SPEC_COMPLIANCE.md)

| Gap | Severity | Reason |
|-----|----------|--------|
| **Sub-day frequencies disabled** | Low | Security design - DoS risk (31M+ occurrences/year). Enable via `install_with_subday.sql` |
| **Leap second (BYSECOND=60)** | Negligible | PostgreSQL TIMESTAMP limitation. RFC allows treating 60 as 59 |

### Design Decisions (Will Not Implement)

| Feature | Reason |
|---------|--------|
| **Non-Gregorian calendars** | HEBREW, ISLAMIC, CHINESE calendars require ICU library integration which would add C extension dependencies, defeating the project's core value proposition (pure PL/pgSQL, works on managed PostgreSQL services). Users needing non-Gregorian calendars should use application-layer libraries like Luxon or date-fns with calendar plugins. |

### Invalid Combinations (Raise Exceptions)
- `BYMONTHDAY` with `FREQ=WEEKLY` - RFC 5545 prohibition
- `BYDAY` ordinals with `FREQ=YEARLY` + `BYWEEKNO` - RFC 5545 prohibition
- `BYSETPOS` with HOURLY/MINUTELY/SECONDLY - redundant (use INTERVAL instead)
