# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pure PL/pgSQL implementation of RFC 5545 iCalendar RRULE for PostgreSQL. No C extensions - works on managed services (AlloyDB, RDS, Azure, Cloud SQL). Packaged as npm module that exports raw SQL strings.

## Commands

```bash
# Run all tests (187 tests across 12 suites)
npm test
./test.sh

# Run specific test modes
./test.sh --standard    # DAILY/WEEKLY/MONTHLY/YEARLY only
./test.sh --subday      # Include HOURLY/MINUTELY/SECONDLY
./test.sh --both        # Full CI mode

# Lint PL/pgSQL code (must pass with 0 errors, 0 warnings)
npm run lint
./lint.sh

# Fresh reinstall after changes
psql -d your_db -c "DROP SCHEMA IF EXISTS rrule CASCADE"
psql -d your_db -f src/install.sql
```

**Test database:** Requires PostgreSQL 12+. Default connection `localhost:54322`. Override with `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, or `DATABASE_URL`.

## Architecture

**SQL-as-NPM-Package:** This is database code, not application code. Changes go in `/src/rrule.sql`. The npm package exports SQL strings for any PostgreSQL client to execute.

**Schema Namespacing:** All functions live in `rrule` PostgreSQL schema. Always use schema-qualified names: `rrule.all()`, `rrule.between()`, etc.

**Public API Functions:**
- `rrule.all(rrule, dtstart)` - All occurrences (SETOF TIMESTAMP)
- `rrule.between(rrule, dtstart, start, end)` - Range query
- `rrule.after(rrule, dtstart, date)` / `rrule.before(rrule, dtstart, date)` - Single occurrence
- `rrule.next(rrule, dtstart)` / `rrule.most_recent(rrule, dtstart)` - Relative to dtstart
- `rrule.count(rrule, dtstart)` - Total count
- `rrule.overlaps(dtstart, dtend, rrule, min, max)` - Conflict detection

**Two Timezone APIs:**
- TIMESTAMP API: Uses `TZID=` in RRULE string (rrule.js compatible)
- TIMESTAMPTZ API: Explicit timezone parameter (PostgreSQL-native)

**Frequencies:**
- Enabled by default: DAILY, WEEKLY, MONTHLY, YEARLY
- Disabled by default: HOURLY, MINUTELY, SECONDLY (use `install_with_subday.sql` to enable)

## Key Files

- `/src/rrule.sql` - Core implementation (~2400 lines)
- `/src/install.sql` - Standard installation
- `/src/install_with_subday.sql` - Installation with sub-day frequencies
- `/tests/*.sql` - 12 test suites covering validation, frequencies, timezone, RFC compliance

## Development Rules

1. **RFC Compliance:** All features must comply with RFC 5545 (RRULE) or RFC 7529 (SKIP/RSCALE). Invalid combinations must be rejected with descriptive errors.

2. **Schema Qualification:** Every function reference must use `rrule.` prefix. Internal functions use `rrule._` naming convention.

3. **Testing Required:** 187 tests must pass. No human code review - tests are the quality gate. Run full suite after any change.

4. **Linting Required:** `plpgsql_check` must report 0 errors and 0 warnings.

5. **Type Safety:** Use explicit parameter types, proper NULL handling with `IS DISTINCT FROM`, and mark pure functions as `IMMUTABLE`.

6. **Security:** Sub-day frequencies are disabled by default to prevent DoS (31M+ occurrences/year for SECONDLY). Changes to this require explicit justification.

## RRULE Parameters Supported

FREQ, COUNT, UNTIL, INTERVAL, BYDAY (with ordinals like 2MO/-1FR), BYMONTHDAY, BYMONTH, BYYEARDAY, BYWEEKNO, BYSETPOS, WKST, TZID, SKIP (OMIT/BACKWARD/FORWARD), RSCALE (GREGORIAN only)

## RFC Compliance Gap Analysis

**Overall: ~98% RFC 5545 compliant, production-ready for Gregorian calendars**

### Fully Compliant
- All 7 FREQ types (sub-day implemented but disabled by default for security)
- All BYxxx parameters with negative index support
- All 16 RFC 5545 Section 3.3.10 validation rules
- WKST, BYWEEKNO (ISO 8601), leap year handling
- RFC 7529 SKIP parameter (OMIT/BACKWARD/FORWARD) - 14 tests verify implementation
- Automatic RSCALE=GREGORIAN when SKIP is used

### Intentional Limitations (Documented in SPEC_COMPLIANCE.md)

| Gap | Severity | Reason |
|-----|----------|--------|
| **Time filters (BYHOUR/BYMINUTE/BYSECOND) with WEEKLY/MONTHLY/YEARLY** | Low | Semantically ambiguous per RFC 5545. **Workaround:** Use `FREQ=DAILY;BYDAY=MO,WE,FR;BYHOUR=9,17` |
| **Sub-day frequencies disabled** | Low | Security design - DoS risk (31M+ occurrences/year). Enable via `install_with_subday.sql` |
| **Non-Gregorian calendars** | Medium | HEBREW, ISLAMIC, CHINESE not supported - requires ICU library integration |
| **Leap second (BYSECOND=60)** | Negligible | PostgreSQL TIMESTAMP limitation. RFC allows treating 60 as 59 |

### Invalid Combinations (Raise Exceptions)
- `FREQ=YEARLY` with both `BYMONTH` and `BYYEARDAY` - semantically contradictory
- `BYMONTHDAY` with `FREQ=WEEKLY` - RFC 5545 prohibition
- `BYDAY` ordinals with `FREQ=YEARLY` + `BYWEEKNO` - RFC 5545 prohibition
- `BYSETPOS` with HOURLY/MINUTELY/SECONDLY - redundant (use INTERVAL instead)
