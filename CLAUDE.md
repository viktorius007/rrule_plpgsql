# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pure PL/pgSQL implementation of RFC 5545 iCalendar RRULE for PostgreSQL. No C extensions - works on managed services (AlloyDB, RDS, Azure, Cloud SQL). Packaged as npm module that exports raw SQL strings.

## Commands

```bash
# Run all tests (200+ tests across 13 suites)
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

**SQL-as-NPM-Package:** This is database code, not application code. Changes go in `/src/rrule.sql`. The npm package exports SQL strings for any PostgreSQL client to execute.

**Schema Namespacing:** All functions live in `rrule` PostgreSQL schema. Always use schema-qualified names: `rrule."all"()`, `rrule."between"()`, etc.

**Public API Functions:**
- `rrule."all"(rrule, dtstart)` - All occurrences (SETOF TIMESTAMP), capped at 1000 results / 10-year window
- `rrule."between"(rrule, dtstart, start, end, inc DEFAULT false)` - Range query, capped at 1000 results
- `rrule."after"(rrule, dtstart, date, inc DEFAULT false)` / `rrule."before"(rrule, dtstart, date, inc DEFAULT false)` - Single occurrence
- `rrule."next"(rrule, dtstart)` / `rrule."most_recent"(rrule, dtstart)` - Relative to dtstart
- `rrule."count"(rrule, dtstart)` - Total count (inherits caps from `all()`)
- `rrule."overlaps"(dtstart, dtend, rrule, min, max)` - Conflict detection

**API Limits:** `all()` and `between()` cap results at 1000 occurrences and a 10-year window from dtstart. Rules without COUNT or UNTIL that hit the cap emit a `RAISE WARNING`. `count()` delegates to `all()` and inherits these caps. These limits exist because RFC 5545 rules without COUNT/UNTIL recur infinitely.

**Two Timezone APIs:**
- TIMESTAMP API: Uses `TZID=` in RRULE string (rrule.js compatible)
- TIMESTAMPTZ API: Explicit timezone parameter (PostgreSQL-native)

**Frequencies:**
- Enabled by default: DAILY, WEEKLY, MONTHLY, YEARLY
- Disabled by default: HOURLY, MINUTELY, SECONDLY (use `install_with_subday.sql` to enable)

## Key Files

- `/src/rrule.sql` - Core implementation (~3100 lines)
- `/src/install.sql` - Standard installation
- `/src/install_with_subday.sql` - Installation with sub-day frequencies
- `/tests/*.sql` - 13 test suites covering validation, frequencies, timezone, RFC compliance
- `DECISIONS.md` - Prescriptive architectural decisions with verification links
- `TESTING_STANDARDS.md` - Required test patterns (ROLLBACK, fixed timestamps, exact assertions)
- `SPEC_COMPLIANCE.md` - RFC 5545/7529 compliance status and documented gaps

## Internal Architecture

The call chain from public API to occurrence generation:

1. **Public API** (`rrule."all"`, `"between"`, `"after"`, etc.) → calls `rrule_event_instances_range()` or `rrule_event_instances_range_tz()`
2. **Dispatcher** (`rrule_event_instances_range`) → parses RRULE via `parse_rrule_parts()`, then dispatches to the appropriate frequency set function
3. **Frequency Sets** (`daily_set`, `weekly_set`, `monthly_set`, `yearly_set`) → generate candidate occurrences by advancing the base date by INTERVAL, applying BYxxx expansion/filtering
4. **BYxxx Helpers** (`rrule_month_byday_set`, `rrule_month_bymonthday_set`, `rrule_week_byday_set`, etc.) → expand candidates for specific BYxxx rules
5. **Filter Functions** (`test_byday_rule`, `test_bymonth_rule`, `test_bymonthday_rule`, `test_byyearday_rule`, `byweekno_matches`) → filter candidates that don't match BYxxx constraints
6. **BYSETPOS** (`rrule_bysetpos_filter`) → cursor-based post-filter that selects specific positions from the candidate set

**Two parallel generators exist:** `rrule_event_instances_range()` (TIMESTAMP, used by TIMESTAMP API) and `rrule_event_instances_range_tz()` (TIMESTAMP, used by TIMESTAMPTZ API). Both have identical structure with 4 frequency branches each. Changes to the main loop logic (caps, boundary checks, EXIT conditions) must be applied to both generators.

The TIMESTAMPTZ API wraps the TIMESTAMP API by converting to/from a target timezone using `AT TIME ZONE`, preserving wall-clock semantics across DST transitions.

## Development Rules

1. **RFC Compliance:** All features must comply with RFC 5545 (RRULE) or RFC 7529 (SKIP/RSCALE). Invalid combinations must be rejected with descriptive errors.

2. **Schema Qualification:** Every function reference must use `rrule.` prefix. Internal functions use `rrule._` naming convention. Tests must use schema-qualified API calls (`rrule."all"(...)`, never unqualified `"all"(...)`).

3. **Testing Required:** All tests must pass. No human code review - tests are the quality gate. Run full suite after any change.

4. **Linting Required:** `plpgsql_check` must report 0 errors and 0 warnings. `lint-tests.sh` must also pass (static SQL coding standards).

5. **Type Safety:** Use explicit parameter types, proper NULL handling with `IS DISTINCT FROM` (never `= NULL` / `<> NULL` / `!= NULL`). Mark functions VOLATILE (cursors, SET timezone, set_config), STABLE (internal computation calling other STABLE/VOLATILE functions), or IMMUTABLE (pure-computation helpers only: `weekday_to_number`, `byweekno_matches`, `calculate_safe_iteration_limit`, `version`).

6. **Security:** Sub-day frequencies are disabled by default to prevent DoS (31M+ occurrences/year for SECONDLY). Changes to this require explicit justification.

7. **API Defaults:** `between`, `after`, and `before` accept `inc BOOLEAN DEFAULT FALSE`. Do not change the default to TRUE -- it matches rrule.js and python-dateutil reference implementations.

8. **Testing Standards:** Follow rules in [TESTING_STANDARDS.md](TESTING_STANDARDS.md) -- key rules: ROLLBACK not COMMIT, fixed timestamps not NOW(), exact assertions not loose comparisons, ORDER BY in array_agg, test boundary/invalid inputs, test DST gap times, test BYxxx deduplication.

9. **Quadruple Generator Maintenance:** Four copies of the main occurrence loop exist: (1) TIMESTAMP generator `rrule_event_instances_range()` in `src/rrule.sql`, (2) TZ generator `rrule_event_instances_range_tz()` in `src/rrule.sql`, (3) subday TIMESTAMP override in `src/rrule_subday.sql`, (4) subday TZ override in `src/rrule_subday.sql`. All four share identical MONTHLY/YEARLY loop structure. Any fix to one (boundary checks, EXIT conditions, SKIP handling, drift prevention) must be mirrored in all four. When fixing these, apply to one location first, verify with a targeted query, then replicate.

10. **Test with INTERVAL > 1:** When modifying period advancement logic (MONTHLY/YEARLY branches), always test with `INTERVAL=2` or higher. SKIP and drift prevention interact with INTERVAL in non-obvious ways — a fix that works for `INTERVAL=1` can silently break for `INTERVAL=2` because the forwarded/skipped date may land across a different period boundary.

11. **Never limit candidate generation before post-filters:** When set functions (e.g., `yearly_set`) pass `max_results` to inner generators but then apply WHERE-clause post-filters, the limit must be passed as NULL. Otherwise the post-filter rejects candidates the generator already counted against the limit, producing fewer results than requested. General principle: limit at the outermost consumer, not at the generator.

12. **Run manual spot-checks from plans:** When a plan specifies manual verification queries, run them as a final step even if the test suite passes. Tests validate expected values set during development — spot-checks validate against the original specification.

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
| **Time filters (BYHOUR/BYMINUTE/BYSECOND) with WEEKLY/MONTHLY/YEARLY** | Low | Semantically ambiguous per RFC 5545. **Workaround:** Use `FREQ=DAILY;BYDAY=MO,WE,FR;BYHOUR=9,17` |
| **Sub-day frequencies disabled** | Low | Security design - DoS risk (31M+ occurrences/year). Enable via `install_with_subday.sql` |
| **Non-Gregorian calendars** | Medium | HEBREW, ISLAMIC, CHINESE not supported - requires ICU library integration |
| **Leap second (BYSECOND=60)** | Negligible | PostgreSQL TIMESTAMP limitation. RFC allows treating 60 as 59 |

### Invalid Combinations (Raise Exceptions)
- `BYMONTHDAY` with `FREQ=WEEKLY` - RFC 5545 prohibition
- `BYDAY` ordinals with `FREQ=YEARLY` + `BYWEEKNO` - RFC 5545 prohibition
- `BYSETPOS` with HOURLY/MINUTELY/SECONDLY - redundant (use INTERVAL instead)
