# Development Guide

Testing, architecture, and contribution guidelines for rrule_plpgsql.

---

## Testing

### Running the Test Suite

Run the same commands used by CI:

```bash
# Full CI path: standard + sub-day installs
./test.sh --both

# Standard install only
./test.sh --standard

# SQL semantic lint (plpgsql_check)
./lint.sh

# Static SQL test lint (assertion/style rules)
./lint-tests.sh

# Install/migration contract suites only
./scripts/test-install-contract.sh

# SQL export contract tests (npm package output)
./scripts/test-package-contract.sh

# Session isolation tests
python3 -m pytest tests/property/test_session_isolation.py -v

# Property tests (CI split)
python3 -m pytest tests/property/ -v -k "not stateful_model" --hypothesis-profile=ci --hypothesis-seed=424242
python3 -m pytest tests/property/test_stateful_model.py -v --hypothesis-profile=stateful_ci --hypothesis-seed=424242
python3 -m pytest tests/property/test_stateful_model.py -v --hypothesis-profile=stateful_ci --hypothesis-seed=424243

# Coverage gates (branch + profiler statement thresholds)
npm run test:coverage:gates

# Mutation suite (also used by nightly non-PR-blocking workflow)
npm run test:mutations

# Manual performance regression check (PG17)
./scripts/perf-regression.sh

# Single suite run (requires DB + installed schema)
PGHOST=localhost PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres \
  psql -d rrule_test -f tests/test_validation.sql
```

**Current CI test inventory:**
- `./test.sh --both` runs 66 SQL suites total (32 standard + 34 sub-day)
- Standard and sub-day installations are both exercised
- Property tests are split by profile:
  - Non-stateful: `pytest tests/property/ -k "not stateful_model" --hypothesis-profile=ci`
  - Stateful model: `pytest tests/property/test_stateful_model.py --hypothesis-profile=stateful_ci`
- CI quality gates: `./test.sh --both`, `npm run test:package-contract`, `./lint.sh`, `./lint-tests.sh`, property tests, and `npm run test:coverage:gates`
- Coverage gate policy:
  - Branch coverage: blocking at `100.0%` with `0` untested branches
  - Statement coverage (standard install): blocking at `>= 80.00%`
  - Statement coverage (subday install): warning if `< 80.00%`, hard fail if `< 50.00%`
- Mutation testing runs in a scheduled nightly gate workflow that is non-blocking for PR CI: `.github/workflows/mutation-nightly.yml`

---

## Test Coverage Details

Coverage is organized as SQL suites under:
- `tests/test_*.sql` (core API, validation, timezone, RFC, integration)
- `tests/install/*.sql` (install + migration contracts)
- `tests/matrix/*.sql` (parameter and behavior matrix coverage)
- `tests/branches/*.sql` (branch-focused coverage)
- `tests/security/*.sql` (budget/DoS protections)
- `tests/parity/*.sql` (standard vs sub-day / generator parity)
- `tests/mutation/*.sql` and `tests/fuzz/*.sql` (mutation and invariant checks)

`./lint-tests.sh` enforces test SQL quality rules across these suites (transaction wrappers, assertion hygiene, ordering in `array_agg`, etc.).

See [TESTING_STANDARDS.md](TESTING_STANDARDS.md) for prescriptive testing rules (assertion quality, transaction handling, deterministic assertions).

### Manual Performance Regression Workflow (PG17)

Performance regression checks are intentionally manual (not CI-gated) to avoid
host-variance flakiness in pull requests.

```bash
# Run benchmark comparison against baseline (fails on >20% regressions)
npm run test:perf

# Refresh baseline medians after intentional performance changes
npm run test:perf -- --update-baseline
```

Baseline file:
- `tests/performance/perf_baseline_pg17.json`

---

## Architecture

### Components

1. **rrule.sql**
   - Core RRULE parsing and generation logic
   - Comprehensive RFC 5545 & RFC 7529 implementation with full validation
   - Public API layer (rrule.js/python-dateutil compatible)
   - Standard methods: `all()`, `after()`, `before()`, `between()`, `count()`
   - Convenience methods: `next()`, `most_recent()`
   - Advanced: `overlaps()`
   - TZID validation and timezone handling
   - Enforces 18 RFC 5545 constraint validations
   - All functions created in `rrule` schema

2. **install.sql**
   - Master installation script
   - Creates `rrule` schema for namespace isolation
   - Loads core functions and API
   - Safe reinstall with dependency checking (see [MIGRATION.md](docs/MIGRATION.md) if needed)

3. **install_with_subday.sql**
   - Optional installation with sub-day frequencies
   - Includes HOURLY, MINUTELY, SECONDLY support
   - Displays security warnings during installation
   - See [SUBDAY_OPERATIONS.md](docs/SUBDAY_OPERATIONS.md)

4. **tests/**/*.sql** (66 suites in CI dual-mode run)
   - Core API/validation/timezone/integration suites
   - Matrix, branch, security, parity, mutation, and fuzz suites
   - Executed via `./test.sh` and validated by `./lint-tests.sh`

---

## Design Decisions

### Schema-Based Namespacing

**All functions live in `rrule` PostgreSQL schema**

**Benefits:**
- Prevents naming conflicts with user functions
- Safe reinstall with dependency checking
- Professional PostgreSQL convention (like `pg_catalog`, `information_schema`)
- Standard names inside schema match rrule.js/python-dateutil

**Usage:**
```sql
-- Schema-qualified (recommended)
SELECT * FROM rrule."all"('FREQ=DAILY;COUNT=5', '2025-01-01'::TIMESTAMP);

-- With search_path
SET search_path = rrule, public;
SELECT * FROM "all"('FREQ=DAILY;COUNT=5', '2025-01-01'::TIMESTAMP);
```

---

### Timezone Handling

**Two APIs for different use cases (both DST-aware):**

1. **TIMESTAMP API**
   - Uses `TIMESTAMP` type (naive timestamp representation)
   - Timezone specified via `TZID=` in RRULE string
   - Automatic DST handling when TZID is provided
   - Wall-clock time semantics preserved across DST boundaries
   - Compatible with rrule.js/python-dateutil

2. **TIMESTAMPTZ API**
   - Uses `TIMESTAMPTZ` type (timestamp with timezone)
   - Timezone specified via explicit function parameter
   - Automatic DST handling
   - Preserves wall-clock time across DST boundaries
   - Timezone parameter can override TZID in RRULE string

**DST Handling Example:**
```sql
-- Meeting stays at 10 AM wall-clock time even across DST spring-forward
SELECT * FROM rrule."all"(
    'FREQ=DAILY;COUNT=3',
    '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
    'America/New_York'
);
-- Results: 10 AM EST, 10 AM EDT, 10 AM EDT (wall-clock time preserved)
```

---

### SETOF vs Arrays

**Core API returns `SETOF TIMESTAMP` for memory efficiency**

**Benefits:**
- Streaming results (memory-efficient for large sets)
- Works with PostgreSQL's row processing
- No array size limits
- Efficient for large result sets

**Converting to Arrays:**
```sql
-- Use array_agg() when you need materialized arrays
SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
    'FREQ=DAILY;COUNT=5',
    '2025-01-01'::TIMESTAMP
) AS occurrence;
```

**When to use each:**
- **SETOF (default):** For iteration, streaming, large result sets
- **Arrays:** When you need to store results, pass to other functions, or work with array operations

---

### Performance

**Benchmarks:**
- **PL/pgSQL is ~50-75x faster than Node.js rrule.js**
- Handles batches of 100+ schedules efficiently
- Uses PostgreSQL's native date/time handling
- Early-exit optimizations for COUNT limits
- Array-based BYSETPOS filtering

**Optimization highlights:**
- FOREACH loops for sparse arrays (2-3x faster validation)
- O(1) weekday conversion helpers
- make_interval() usage (type-safe, efficient)
- Early-exit parameter propagation (30-80% reduction in date generation)
- Array-based BYSETPOS filtering (5x faster for multiple positions)
- date_part() instead of to_char() (20-30% faster weekday checks)

---

## Code Quality

### Validation First

All RRULEs are validated **before** processing:
- 18 RFC 5545 constraint validations
- Descriptive error messages with RFC citations
- Suggested fixes for common mistakes

### Type Safety

- Explicit parameter types
- Proper NULL handling
- IMMUTABLE functions where appropriate
- No SQL injection vectors

### Maintainability

- Clear function naming
- Comprehensive inline documentation
- Separated concerns (parsing, validation, generation)
- Well-organized test suites

---

## Contributing Code

### Before Submitting

1. **Run all quality gates** - `./test.sh --both`, `./lint.sh`, and `./lint-tests.sh` must pass
2. **Add test coverage** - Include tests for new features
3. **Document changes** - Update relevant .md files
4. **Follow conventions** - Match existing code style

### Pull Request Checklist

- [ ] `./test.sh --both` passes
- [ ] `./lint.sh` passes
- [ ] `./lint-tests.sh` passes
- [ ] New features have test coverage
- [ ] Documentation updated (README.md, API_REFERENCE.md, etc.)
- [ ] No breaking changes (or clearly documented if necessary)
- [ ] RFC 5545/7529 compliance maintained
- [ ] Performance regressions addressed

### Adding New Features

1. **Study RFC 5545/7529** - Ensure feature is spec-compliant
2. **Write tests first** - TDD approach recommended
3. **Implement feature** - Follow existing patterns
4. **Validate against spec** - Cross-reference RFC sections
5. **Document thoroughly** - Update all relevant docs

---

## Development Setup

### Prerequisites

- PostgreSQL 17.x
- psql command-line client
- Git (for version control)

### Local Development

```bash
# Clone repository
git clone https://github.com/sirrodgepodge/rrule_plpgsql.git
cd rrule_plpgsql

# Run full CI-equivalent quality gates
./test.sh --both
./lint.sh
./lint-tests.sh

# Optional: run a single suite (requires DB + installed schema)
PGHOST=localhost PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres \
  psql -d rrule_test -f tests/test_validation.sql
```

### Making Changes

```bash
# 1. Make changes to src/rrule.sql

# 2. Reinstall
psql -d rrule_test -c "DROP SCHEMA IF EXISTS rrule CASCADE;"
psql -d rrule_test -f src/install.sql

# 3. Run quality gates
./test.sh --both
./lint.sh
./lint-tests.sh

# 4. Iterate until all three pass
```

---

## Debugging Tips

### Enable Debug Output

```sql
-- See validation notices
\set VERBOSITY verbose

-- See function execution
SET client_min_messages TO DEBUG;
```

### Common Issues

**Tests failing?**
- Ensure fresh install (`DROP SCHEMA rrule CASCADE`)
- Check PostgreSQL version (17.x required)
- Verify timezone data is up to date

**Performance issues?**
- Check for missing early-exit optimization
- Profile with `EXPLAIN ANALYZE`
- Consider COUNT limits

**Timezone issues?**
- Verify timezone names: `SELECT * FROM pg_timezone_names;`
- Check DST handling with test_tzid_support.sql
- Ensure dtstart has correct timezone offset

---

## Release Process

1. **Version bump** - Update version in documentation
2. **Run all quality gates** - Ensure `./test.sh --both`, `./lint.sh`, and `./lint-tests.sh` all pass
3. **Update CHANGELOG** - Document changes
4. **Tag release** - Git tag with version
5. **Publish** - Push to GitHub

---

## See Also

- [API_REFERENCE.md](docs/API_REFERENCE.md) - Function reference
- [SPEC_COMPLIANCE.md](docs/SPEC_COMPLIANCE.md) - RFC 5545/7529 feature support
- [VALIDATION.md](docs/VALIDATION.md) - RRULE validation rules
- [README.md](README.md) - Main documentation
- [SECURITY.md](docs/SECURITY.md) - Security practices
