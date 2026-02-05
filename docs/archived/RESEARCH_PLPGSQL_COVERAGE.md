# Research: PL/pgSQL Code Coverage Tooling

**Date:** 2026-02-05
**Context:** rrule_plpgsql project (~4,700 lines PL/pgSQL, 52,000+ lines of tests)

## Executive Summary

PL/pgSQL code coverage is a niche area with limited but viable options. The best current solution is **plpgsql_check's built-in profiler**, which provides statement-level execution counts that can be used for coverage analysis. This project already uses plpgsql_check for **static linting** (via `plpgsql_check_function()`), but the **profiler is a separate feature** that requires explicit enablement. A newer tool, **pgcov** (January 2026), offers dedicated coverage with LCOV output but is very new. The older **Piggly** tool is mature but hasn't been updated since 2022 and requires Ruby.

## Tools Found

### 1. plpgsql_check Profiler (Recommended)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/okbob/plpgsql_check |
| **Author** | Pavel Stehule (PostgreSQL core contributor) |
| **Last Update** | Actively maintained (2025+) |
| **Maturity** | Production-ready (widely used for linting) |
| **Requirements** | PostgreSQL extension (already in project for linting; profiler needs enablement) |

**Current Project Status:** This project uses plpgsql_check for **static linting only** (`lint.sh` calls `plpgsql_check_function()`). The profiler and coverage functions are separate features of the same extension that require explicit enablement via `SET plpgsql_check.profiler TO on;`.

**Key Features:**
- **Statement-level profiling**: Tracks execution count per statement
- **Coverage metrics**: `plpgsql_profiler_function_statements_tb()` returns `exec_stmts` (execution count) per statement
- **Branch visibility**: Reports IF/THEN/ELSE branches separately with `parent_note` column
- **Low overhead**: Designed for production use
- **Tracing mode**: Can log every statement execution for debugging

**Coverage Query Example:**
```sql
-- Get statement execution counts for a function
SELECT stmtid, parent_stmtid, parent_note, lineno, exec_stmts, stmtname
FROM plpgsql_profiler_function_statements_tb('rrule.yearly_set');

-- Calculate coverage percentage
SELECT
    count(*) AS total_statements,
    count(*) FILTER (WHERE exec_stmts > 0) AS executed_statements,
    round(100.0 * count(*) FILTER (WHERE exec_stmts > 0) / count(*), 2) AS coverage_pct
FROM plpgsql_profiler_function_statements_tb('rrule.yearly_set');
```

**Setup Required:**
```sql
-- Enable profiler (add to postgresql.conf or set per-session)
-- shared_preload_libraries = 'plpgsql_check'  -- for persistent stats
-- OR use session-level profiling (no shared memory needed)

LOAD 'plpgsql_check';
SET plpgsql_check.profiler TO on;

-- Run tests, then query profiler tables
```

**Limitations:**
- Reports statement-level coverage, not line-level
- Requires explicit setup before test run
- Coverage data is session-scoped unless shared memory is configured

---

### 2. pgcov (New - January 2026)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/cybertec-postgresql/pgcov |
| **Author** | CYBERTEC PostgreSQL International |
| **Last Update** | January 2026 (very new) |
| **Maturity** | Early stage (38 commits, 0 stars as of research date) |
| **Requirements** | Go 1.21+, CGO, PostgreSQL 13+ |

**Key Features:**
- **Dedicated coverage tool**: Built specifically for PL/pgSQL coverage
- **LCOV output**: Standard format for CI/CD integration (Codecov, Coveralls)
- **Test isolation**: Each test runs in a temporary database
- **Source instrumentation**: Rewrites functions with coverage tracking
- **Parallel execution**: Optional concurrent test execution

**How It Works:**
1. Discovers `*_test.sql` files
2. Instruments PL/pgSQL source code with coverage markers
3. Runs tests in isolated temporary databases
4. Collects coverage via PostgreSQL LISTEN/NOTIFY
5. Generates HTML, JSON, or LCOV reports

**Usage:**
```bash
# Install
go install github.com/cybertec-postgresql/pgcov/cmd/pgcov@latest

# Run tests and collect coverage
pgcov run ./...

# Generate LCOV report
pgcov report --format=lcov -o coverage.lcov
```

**Limitations:**
- Very new (released January 2026) - limited real-world validation
- Requires Go build environment with CGO
- Test files must follow `*_test.sql` naming convention
- Would require adapting existing test structure

---

### 3. Piggly (Ruby)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/kputnam/piggly |
| **Website** | https://kputnam.github.io/piggly/ |
| **Last Update** | July 2022 (2.5+ years ago) |
| **Maturity** | Mature but dormant (76 stars, 289 commits) |
| **Requirements** | Ruby 2.2+, ActiveRecord, pg gem |

**Key Features:**
- **Branch coverage**: Tracks IF/ELSE branches, loops, blocks
- **Language agnostic tests**: Write tests in any language
- **HTML reports**: Visual coverage reports with tooltips
- **Source-to-source compiler**: Instruments PL/pgSQL with RAISE WARNING

**How It Works:**
1. `piggly trace` - Recompiles procedures with instrumentation (RAISE WARNING statements)
2. Run your tests (any language/framework)
3. Capture WARNING messages to a file
4. `piggly report < messages.txt` - Generate coverage report
5. `piggly untrace` - Restore original procedures

**Usage:**
```bash
gem install piggly

# Configure database in config/database.yml
piggly trace           # Instrument procedures
./run-tests 2> messages.txt
piggly report -f messages.txt
piggly untrace         # Restore originals
```

**Limitations:**
- **Not actively maintained** (last commit July 2022)
- **Ruby dependency**: Adds Ruby toolchain requirement
- **Grammar limitations**: "Not all PL/pgSQL grammar is currently supported"
- **Cannot parse nested dollar-quoted strings**
- **Modifies database**: Replaces functions during testing (risk if tests fail mid-run)

---

### 4. PostgreSQL Native Coverage (C-level only)

| Attribute | Value |
|-----------|-------|
| **URL** | https://wiki.postgresql.org/wiki/CodeCoverage |
| **Documentation** | https://www.postgresql.org/docs/current/regress-coverage.html |
| **Live Report** | https://coverage.postgresql.org/ |

This is coverage for PostgreSQL's C source code, **not** for PL/pgSQL functions. It requires building PostgreSQL from source with `--enable-coverage` and uses gcov/lcov.

**Not applicable** for PL/pgSQL function coverage - this only measures which lines of the PostgreSQL C executor were hit.

---

## DIY Approaches

### Approach 1: RAISE NOTICE Instrumentation (Manual Piggly)

Manually add RAISE NOTICE statements at branch points and parse the log.

```sql
-- Before
IF a > 10 THEN
    result := 'large';
ELSE
    result := 'small';
END IF;

-- After (instrumented)
IF a > 10 THEN
    RAISE NOTICE 'COVERAGE:func_name:branch_1:then';
    result := 'large';
ELSE
    RAISE NOTICE 'COVERAGE:func_name:branch_1:else';
    result := 'small';
END IF;
```

**Pros:** No external dependencies
**Cons:** Extremely labor-intensive for 4,700 lines; must maintain two versions of code

---

### Approach 2: Temporary Logging Table

Insert coverage markers into a table instead of using RAISE NOTICE.

```sql
-- Create coverage table
CREATE TABLE coverage_log (
    id SERIAL,
    function_name TEXT,
    marker TEXT,
    hit_count INTEGER DEFAULT 1,
    first_hit TIMESTAMP DEFAULT now()
);

-- Insert markers at branch points
INSERT INTO coverage_log (function_name, marker)
VALUES ('yearly_set', 'branch_bymonth_entered')
ON CONFLICT DO UPDATE SET hit_count = hit_count + 1;
```

**Pros:** Coverage persists across sessions; easy to query
**Cons:** Significant overhead; requires code modification; changes function behavior

---

### Approach 3: pg_stat_statements Analysis (Limited)

Use pg_stat_statements to see which SQL statements inside functions were executed.

```sql
SELECT query, calls, total_exec_time
FROM pg_stat_statements
WHERE query LIKE '%rrule%';
```

**Limitation:** Only tracks top-level SQL statements, not PL/pgSQL control flow (IF/LOOP branches). **Not useful for branch coverage.**

---

## Recommendations (Ranked by Effort vs Value)

### Rank 1: plpgsql_check Profiler (Low Effort, High Value)

**Why:** The extension is already installed for static linting (`lint.sh`). The profiler is a separate feature of the same extension - enabling it requires only configuration changes, not new dependencies.

**Implementation Steps:**
1. Add `LOAD 'plpgsql_check'; SET plpgsql_check.profiler TO on;` before test run
2. Run test suite
3. Query `plpgsql_profiler_function_statements_tb()` for all rrule functions
4. Generate report showing statements with `exec_stmts = 0`

**Estimated Effort:** 2-4 hours to integrate into test.sh

---

### Rank 2: pgcov (Medium Effort, High Value)

**Why:** Purpose-built for this exact use case with modern CI/CD integration.

**Concerns:** Very new (January 2026), may have bugs or missing features. Would require restructuring tests to match `*_test.sql` convention.

**Recommendation:** Monitor project for 6-12 months. If it gains traction and stability, consider adoption.

---

### Rank 3: Piggly (Medium Effort, Medium Value)

**Why:** Proven tool with branch-level coverage, but dormant development is a concern.

**When to Use:** If branch coverage (not just statement coverage) is critical and Ruby dependency is acceptable.

**Risk:** Grammar issues with modern PL/pgSQL syntax; no maintainer for bug fixes.

---

### Rank 4: DIY Instrumentation (High Effort, Variable Value)

**Why:** Maximum control, no dependencies.

**When to Use:** Only if no other option works for specific requirements.

**Not Recommended** for this project due to codebase size.

---

## References

1. **plpgsql_check GitHub**: https://github.com/okbob/plpgsql_check
2. **plpgsql_check Profiler Blog (2019)**: https://okbob.blogspot.com/2019/01/plpgsqlcheck-new-report-for-code.html
3. **plpgsql_check Tracing Blog (2020)**: https://okbob.blogspot.com/2020/08/plpgsqlcheck-now-supports-tracing.html
4. **pgcov GitHub**: https://github.com/cybertec-postgresql/pgcov
5. **Piggly GitHub**: https://github.com/kputnam/piggly
6. **Piggly Website**: https://kputnam.github.io/piggly/
7. **PostgreSQL Code Coverage Wiki**: https://wiki.postgresql.org/wiki/CodeCoverage
8. **PostgreSQL Mailing List - plpgsql coverage**: https://www.postgresql.org/message-id/CALyyT7TxENJQX4SDsZYgXaXhnt_6OuqENVw3Ap9d7P%3DX_new6Q%40mail.gmail.com
9. **pgTAP (no coverage, unit testing only)**: https://pgtap.org/
10. **Stack Overflow - PostgreSQL coverage**: https://stackoverflow.com/questions/43209789/postgres-sql-query-code-coverage

---

## Conclusion

For this project, **plpgsql_check's profiler is the clear winner** - the extension is already a dependency (used for static linting in `lint.sh`), actively maintained by a PostgreSQL core contributor, and provides statement-level execution counts that can identify dead code. Note that the profiler is a separate feature from the linting functionality currently in use - it requires enablement via `SET plpgsql_check.profiler TO on;`. The newer pgcov is promising but too new to rely on for a production codebase. Piggly would work but adds Ruby as a dependency and hasn't been maintained in over two years.

The recommended next step is to create a script that:
1. Enables plpgsql_check profiler
2. Runs the full test suite
3. Queries profiler data for all rrule.* functions
4. Reports statements with zero execution count (untested code paths)
