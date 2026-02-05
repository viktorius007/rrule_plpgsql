# Test Quality Improvement Plan

**Created:** 2026-02-05
**Status:** ✅ Mostly Complete (Goal 3.3 Optional remains)
**Context:** Following comprehensive test suite implementation (52,000+ lines, 7,500+ assertions), this plan addresses remaining opportunities for test quality improvement identified through research.

## Background

Three research documents inform this plan:

| Document | Summary |
|----------|---------|
| [RESEARCH_PLPGSQL_COVERAGE.md](RESEARCH_PLPGSQL_COVERAGE.md) | plpgsql_check profiler recommended for statement coverage |
| [RESEARCH_MUTATION_TESTING.md](RESEARCH_MUTATION_TESTING.md) | Expand existing mutation-test.js with academic patterns |
| [RESEARCH_PROPERTY_TESTING.md](RESEARCH_PROPERTY_TESTING.md) | Add Python/Hypothesis for shrinking + differential testing |

---

## Goal 1: Statement Coverage via plpgsql_check Profiler

**Rationale:** The project uses plpgsql_check for static linting, but the profiler feature (separate from linting) can identify statements never executed by tests.

**Total Effort:** 2-4 hours

### Increment 1.1: Proof of Concept ✅

**Note:** `scripts/coverage-report.js` already exists for *static* branch analysis (parsing code to find IF/ELSE structures). The plpgsql_check profiler provides *runtime* coverage (which statements were actually executed during tests). These are complementary approaches.

- [x] Create `scripts/profiler-coverage.sh` that:
  - Enables profiler: `LOAD 'plpgsql_check'; SET plpgsql_check.profiler TO on;`
  - Runs a single test file
  - Queries `plpgsql_profiler_function_statements_tb('rrule.yearly_set')`
  - Outputs statements with `exec_stmts = 0`
- [x] Verify profiler works in local environment
- **Deliverable:** Working script that reports coverage for one function

### Increment 1.2: Full Coverage Report ✅
- [x] Extend script to query all `rrule.*` functions
- [x] Run full test suite with profiler enabled
- [x] Generate summary: total statements, executed statements, coverage %
- [x] List all statements with zero execution count
- **Deliverable:** Complete coverage report identifying any untested code paths
- **Result:** 69.26% overall coverage (881/1272 statements executed)

### Increment 1.3: CI Integration ✅
- [x] Add coverage step to `.github/workflows/test.yml`
- [x] ~~Fail CI if coverage drops below threshold~~ (warn only, non-blocking)
- [x] Store coverage artifacts for trend analysis
- **Deliverable:** Automated coverage tracking in CI

---

## Goal 2: Mutation Testing Expansion

**Rationale:** `scripts/mutation-test.js` exists with 14 mutation patterns. Academic research identifies additional high-value patterns not yet implemented.

**Reference:** RESEARCH_MUTATION_TESTING.md, Section "SQL Mutation Operators"

**Total Effort:** 3-4 hours (adds 12 new mutation patterns per research recommendation of "10-15 more")

### Increment 2.1: Relational & Logical Operators (ROR/LCR) ✅
- [x] Add mutations from RESEARCH_MUTATION_TESTING.md:
  ```javascript
  // ROR - Relational Operator Replacement
  ['ror-gte-gt', /result_count >= max_results/g, 'result_count > max_results'],
  ['ror-lte-lt', /requested_day <= daysinmonth/g, 'requested_day < daysinmonth'],
  ['ror-neq-eq', /result\.freq != 'YEARLY'/g, "result.freq = 'YEARLY'"],

  // LCR - Logical Connector Replacement
  ['lcr-and-or', /result\.count IS NOT NULL AND result\.count <= 0/g, '... OR ...'],
  ['lcr-or-and', /result\.bysecond\[i\] < 0 OR ... > 60/g, '... AND ...'],
  ```
- [x] Run mutations, document survivors
- [x] All non-equivalent mutations killed (ror-gte-gt marked equivalent)
- **Deliverable:** 5 new mutation patterns, all killed or marked equivalent

### Increment 2.2: NULL & Arithmetic Mutations (NL/AOR) ✅
- [x] Add NULL-specific mutations:
  ```javascript
  // NL - NULL mutations
  ['nls-null-notnull', /IS NULL/g, 'IS NOT NULL'],
  ['nlf-coalesce', /COALESCE\(([^,()]+),\s*([^,()]+)\)/g, '$1'],
  ```
- [x] Add arithmetic mutations:
  ```javascript
  // AOR - Arithmetic Operator Replacement
  ['aor-add-sub', / \+ (\d)/g, ' - $1'],
  ['aor-sub-add', / - (\d)/g, ' + $1'],

  // INT - Interval mutations
  ['int-day', /INTERVAL '1 day'/g, "INTERVAL '2 days'"],
  ['int-month', /INTERVAL '1 month'/g, "INTERVAL '2 months'"],
  ```
- [x] Run mutations, all killed
- **Deliverable:** 7 new mutation patterns, all killed

### Increment 2.3: Mutation Score Reporting ✅
- [x] Add summary output to mutation-test.js:
  - Total mutations
  - Killed (test failed)
  - Survived (test passed - potential gap)
  - Equivalent (marked as cannot affect behavior)
  - Mutation score = Killed / (Total - Equivalent)
- [x] `npm run test:mutations` available
- **Result:** 100% mutation score (21/21 non-equivalent killed, 4 equivalent)

---

## Goal 3: Property-Based Testing with Hypothesis

**Rationale:** Current PL/pgSQL property tests lack shrinking (hard to debug failures) and cannot compare against reference implementations. Python/Hypothesis provides both.

**Reference:** RESEARCH_PROPERTY_TESTING.md, Sections 3, 6, and Appendix A

**Important:** Per RESEARCH_PROPERTY_TESTING.md Phase 1, the existing `tests/fuzz/test_property_invariants.sql` should be **kept** as a fast CI smoke test. The Python/Hypothesis tests complement (not replace) the PL/pgSQL tests.

**Total Effort:** 6-10 hours (5 increments; 3.3 is optional)

### Increment 3.1: Infrastructure Setup ✅
- [x] Create `tests/property/` directory structure:
  ```
  tests/property/
    conftest.py       # DB fixtures, Hypothesis settings
    strategies.py     # RRULE generation strategies
    requirements.txt  # hypothesis, psycopg2-binary, python-dateutil
    known_differences.py  # Intentional deviations from dateutil
  ```
- [x] Implement basic database fixture with connection pooling
- [x] Implement `simple_rrule()` strategy (FREQ + COUNT + INTERVAL only)
- [x] Write one test: `test_monotonicity` - results are strictly ascending
- [x] Verify test runs and shrinking works
- **Deliverable:** Working Hypothesis test infrastructure with one passing test

### Increment 3.2: Invariant Test Suite ✅
- [x] Port invariants from `test_property_invariants.sql`:
  - Monotonicity (strictly ascending, no duplicates)
  - COUNT respected exactly
  - UNTIL respected (no results after)
  - dtstart boundary (all results >= dtstart)
  - 10-year cap
  - 1000 result cap
- [x] Add filtering invariants (from RESEARCH_PROPERTY_TESTING.md Section 2.2):
  - BYDAY filtering: all results occur on specified weekdays
  - BYMONTH filtering: all results occur in specified months
  - BYMONTHDAY filtering: all results occur on specified days of month
- [x] Implement `complex_rrule()` strategy with BYxxx parameters
- [x] Run with 500+ examples per test
- **Deliverable:** Full invariant suite with automatic shrinking on failures
- **Result:** 11 passing tests in test_invariants.py

### Increment 3.3: Advanced Properties (Optional) ⏳
- [ ] Add advanced invariants from RESEARCH_PROPERTY_TESTING.md Section 2.2:
  - Interval Spacing: `FREQ=DAILY;INTERVAL=3` produces 3-day gaps
  - Idempotence: `all(rrule, dtstart)` returns identical results on repeated calls
  - Subset Relationship: `between(start, end)` results ⊆ `all()` results
  - after/before Consistency: `after(d)` equals first result > d from `all()`
  - Timezone Consistency: TIMESTAMP and TIMESTAMPTZ APIs produce matching wall-clock times
- **Deliverable:** Complete property coverage matching research recommendations

### Increment 3.4: Differential Testing vs python-dateutil ✅
- [x] Implement `test_matches_dateutil()`:
  - Generate RRULE with Hypothesis
  - Query PL/pgSQL implementation
  - Query python-dateutil
  - Compare results
- [x] Document any intentional differences (implementation choices)
- [x] Create exception list for known deviations (known_differences.py)
- **Deliverable:** Automated RFC compliance verification against reference implementation
- **Result:** 3 passing tests in test_differential.py

### Increment 3.5: CI Integration ✅
- [x] Add to `.github/workflows/test.yml`:
  ```yaml
  - uses: actions/setup-python@v5
    with:
      python-version: '3.11'
  - run: pip install -r tests/property/requirements.txt
  - run: pytest tests/property/ -v --hypothesis-profile=ci --hypothesis-seed=${{ github.run_id }}
  ```
- [x] Configure Hypothesis profiles (CI: 1000 examples, dev: 100)
- **Deliverable:** Property tests running in CI on every push

---

## Execution Order

Recommended sequence based on dependencies and value:

```
Week 1:
  1.1 Profiler POC ─────► 1.2 Full Report ─────► (reveals actual gaps)
                                                       │
Week 2:                                                ▼
  2.1 ROR/LCR mutations ► 2.2 NULL/AOR mutations ► 2.3 Score reporting
                                                       │
Week 3:                                                ▼
  3.1 Hypothesis setup ─► 3.2 Invariants ─► 3.4 Differential ─► 3.5 CI
                                │
                                └─► 3.3 Advanced (optional)
```

**Rationale:**
- Profiler first: May reveal untested code that informs mutation/property test priorities
- Mutation second: Builds on existing infrastructure, quick wins
- Hypothesis last: Largest new infrastructure, benefits from earlier learnings

---

## Complexity & Dependencies

| Increment | Complexity | Skills Required | Dependencies |
|-----------|------------|-----------------|--------------|
| **1.1** Profiler POC | 🟢 Low | Bash, SQL | plpgsql_check extension installed |
| **1.2** Full Report | 🟢 Low | Bash, SQL | 1.1 completed |
| **1.3** CI Integration | 🟡 Medium | GitHub Actions YAML | 1.2 completed |
| **2.1** ROR/LCR mutations | 🟢 Low | JavaScript regex | None |
| **2.2** NULL/AOR mutations | 🟢 Low | JavaScript regex | None |
| **2.3** Score reporting | 🟢 Low | JavaScript | 2.1 or 2.2 completed |
| **3.1** Hypothesis setup | 🟡 Medium | Python, psycopg2, pytest | None |
| **3.2** Invariant suite | 🟡 Medium | Hypothesis strategies | 3.1 completed |
| **3.3** Advanced properties | 🟠 Medium-High | Complex property logic | 3.2 completed |
| **3.4** Differential testing | 🟠 Medium-High | python-dateutil, edge case handling | 3.1 completed |
| **3.5** CI Integration | 🟡 Medium | GitHub Actions, Python setup | 3.2 or 3.4 completed |

**Complexity Legend:**
- 🟢 Low: Straightforward implementation, minimal decision-making
- 🟡 Medium: Some design decisions, familiarity with tools required
- 🟠 Medium-High: Complex logic, edge case handling, potential debugging

**Parallel Execution:** Goals 1, 2, and 3 are independent and can run concurrently. Within each goal, increments must be sequential (except 2.1/2.2 which can be parallel).

---

## Success Criteria

| Goal | Metric | Target |
|------|--------|--------|
| Coverage | Statement coverage % | >95% (or document why gaps are acceptable) |
| Mutation | Mutation score | >85% (killed / non-equivalent) |
| Property | Differential test pass rate | 100% (with documented exceptions) |

---

## Notes

- Each increment is independently valuable - can stop at any point
- Increments within a goal can often be parallelized
- CI integration steps (1.3, 2.3, 3.5) are optional but recommended
- All work should follow existing project conventions (TESTING_STANDARDS.md)
- Existing `tests/fuzz/test_property_invariants.sql` is retained for fast CI smoke tests
- Python/Hypothesis tests are additive - they provide shrinking and differential testing capabilities the PL/pgSQL tests cannot
