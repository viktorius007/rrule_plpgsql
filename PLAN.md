# Test Quality Improvement Plan

**Created:** 2026-02-05
**Status:** Planning
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

### Increment 1.1: Proof of Concept

**Note:** `scripts/coverage-report.js` already exists for *static* branch analysis (parsing code to find IF/ELSE structures). The plpgsql_check profiler provides *runtime* coverage (which statements were actually executed during tests). These are complementary approaches.

- [ ] Create `scripts/profiler-coverage.sh` that:
  - Enables profiler: `LOAD 'plpgsql_check'; SET plpgsql_check.profiler TO on;`
  - Runs a single test file
  - Queries `plpgsql_profiler_function_statements_tb('rrule.yearly_set')`
  - Outputs statements with `exec_stmts = 0`
- [ ] Verify profiler works in local environment
- **Deliverable:** Working script that reports coverage for one function

### Increment 1.2: Full Coverage Report
- [ ] Extend script to query all `rrule.*` functions
- [ ] Run full test suite with profiler enabled
- [ ] Generate summary: total statements, executed statements, coverage %
- [ ] List all statements with zero execution count
- **Deliverable:** Complete coverage report identifying any untested code paths

### Increment 1.3: CI Integration (Optional)
- [ ] Add coverage step to `.github/workflows/test.yml`
- [ ] Fail CI if coverage drops below threshold (or warn only)
- [ ] Store coverage artifacts for trend analysis
- **Deliverable:** Automated coverage tracking in CI

---

## Goal 2: Mutation Testing Expansion

**Rationale:** `scripts/mutation-test.js` exists with 14 mutation patterns. Academic research identifies additional high-value patterns not yet implemented.

**Reference:** RESEARCH_MUTATION_TESTING.md, Section "SQL Mutation Operators"

**Total Effort:** 3-4 hours (adds 12 new mutation patterns per research recommendation of "10-15 more")

### Increment 2.1: Relational & Logical Operators (ROR/LCR)
- [ ] Add mutations from RESEARCH_MUTATION_TESTING.md:
  ```javascript
  // ROR - Relational Operator Replacement
  ['ror-eq-neq', /(\w+)\s*=\s*(\w+)(?!_)/g, '$1 <> $2'],
  ['ror-gte-gt', />=/g, '>'],
  ['ror-lte-lt', /<=/g, '<'],

  // LCR - Logical Connector Replacement
  ['lcr-and-or', / AND (?!result)/g, ' OR '],
  ['lcr-or-and', / OR (?!test_)/g, ' AND '],
  ```
- [ ] Run mutations, document survivors
- [ ] Write tests to catch any non-equivalent survivors
- **Deliverable:** 5 new mutation patterns, all killed or marked equivalent

### Increment 2.2: NULL & Arithmetic Mutations (NL/AOR)
- [ ] Add NULL-specific mutations:
  ```javascript
  // NL - NULL mutations
  ['nls-null-notnull', /IS NULL/g, 'IS NOT NULL'],
  ['nls-notnull-null', /IS NOT NULL/g, 'IS NULL'],
  ['nlf-coalesce', /COALESCE\(([^,]+),\s*([^)]+)\)/g, '$1'],
  ```
- [ ] Add arithmetic mutations:
  ```javascript
  // AOR - Arithmetic Operator Replacement
  ['aor-add-sub', / \+ (?=\d)/g, ' - '],
  ['aor-sub-add', / - (?=\d)/g, ' + '],

  // INT - Interval mutations
  ['int-day', /INTERVAL '1 day'/g, "INTERVAL '2 days'"],
  ['int-month', /INTERVAL '1 month'/g, "INTERVAL '2 months'"],
  ```
- [ ] Run mutations, document survivors
- [ ] Write tests to catch any non-equivalent survivors
- **Deliverable:** 7 new mutation patterns (NULL + arithmetic + interval), all killed or marked equivalent

### Increment 2.3: Mutation Score Reporting
- [ ] Add summary output to mutation-test.js:
  - Total mutations
  - Killed (test failed)
  - Survived (test passed - potential gap)
  - Equivalent (marked as cannot affect behavior)
  - Mutation score = Killed / (Total - Equivalent)
- [ ] Add `npm run test:mutations` to CI (non-blocking initially)
- **Deliverable:** Mutation score metric tracked over time

---

## Goal 3: Property-Based Testing with Hypothesis

**Rationale:** Current PL/pgSQL property tests lack shrinking (hard to debug failures) and cannot compare against reference implementations. Python/Hypothesis provides both.

**Reference:** RESEARCH_PROPERTY_TESTING.md, Sections 3, 6, and Appendix A

**Important:** Per RESEARCH_PROPERTY_TESTING.md Phase 1, the existing `tests/fuzz/test_property_invariants.sql` should be **kept** as a fast CI smoke test. The Python/Hypothesis tests complement (not replace) the PL/pgSQL tests.

**Total Effort:** 6-10 hours (5 increments; 3.3 is optional)

### Increment 3.1: Infrastructure Setup
- [ ] Create `tests/property/` directory structure:
  ```
  tests/property/
    conftest.py       # DB fixtures, Hypothesis settings
    strategies.py     # RRULE generation strategies
    requirements.txt  # hypothesis, psycopg2-binary, python-dateutil
  ```
- [ ] Implement basic database fixture with connection pooling
- [ ] Implement `simple_rrule()` strategy (FREQ + COUNT + INTERVAL only)
- [ ] Write one test: `test_monotonicity` - results are strictly ascending
- [ ] Verify test runs and shrinking works
- **Deliverable:** Working Hypothesis test infrastructure with one passing test

### Increment 3.2: Invariant Test Suite
- [ ] Port invariants from `test_property_invariants.sql`:
  - Monotonicity (strictly ascending, no duplicates)
  - COUNT respected exactly
  - UNTIL respected (no results after)
  - dtstart boundary (all results >= dtstart)
  - 10-year cap
  - 1000 result cap
- [ ] Add filtering invariants (from RESEARCH_PROPERTY_TESTING.md Section 2.2):
  - BYDAY filtering: all results occur on specified weekdays
  - BYMONTH filtering: all results occur in specified months
  - BYMONTHDAY filtering: all results occur on specified days of month
- [ ] Implement `complex_rrule()` strategy with BYxxx parameters
- [ ] Run with 500+ examples per test
- **Deliverable:** Full invariant suite with automatic shrinking on failures

### Increment 3.3: Advanced Properties (Optional)
- [ ] Add advanced invariants from RESEARCH_PROPERTY_TESTING.md Section 2.2:
  - Interval Spacing: `FREQ=DAILY;INTERVAL=3` produces 3-day gaps
  - Idempotence: `all(rrule, dtstart)` returns identical results on repeated calls
  - Subset Relationship: `between(start, end)` results ⊆ `all()` results
  - after/before Consistency: `after(d)` equals first result > d from `all()`
  - Timezone Consistency: TIMESTAMP and TIMESTAMPTZ APIs produce matching wall-clock times
- **Deliverable:** Complete property coverage matching research recommendations

### Increment 3.4: Differential Testing vs python-dateutil
- [ ] Implement `test_matches_dateutil()`:
  - Generate RRULE with Hypothesis
  - Query PL/pgSQL implementation
  - Query python-dateutil
  - Compare results
- [ ] Document any intentional differences (implementation choices)
- [ ] Create exception list for known deviations
- **Deliverable:** Automated RFC compliance verification against reference implementation

### Increment 3.5: CI Integration
- [ ] Add to `.github/workflows/test.yml`:
  ```yaml
  - uses: actions/setup-python@v4
    with:
      python-version: '3.11'
  - run: pip install -r tests/property/requirements.txt
  - run: pytest tests/property/ -v --hypothesis-seed=${{ github.run_id }}
  ```
- [ ] Configure Hypothesis profiles (CI: 1000 examples, dev: 100)
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
