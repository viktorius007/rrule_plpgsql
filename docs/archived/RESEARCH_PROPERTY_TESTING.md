# Property-Based Testing for SQL/PL/pgSQL: Research Report

## Executive Summary

**Best Approach: Hybrid Python/Hypothesis + Differential Testing against python-dateutil**

The most effective strategy for property-based testing of the PL/pgSQL RRULE implementation combines:
1. **Python Hypothesis** for sophisticated input generation, shrinking, and test orchestration
2. **Differential testing** against `python-dateutil` (the reference RRULE implementation)
3. **Retain current PL/pgSQL property tests** for quick CI smoke tests

This hybrid approach provides automatic shrinking (which PL/pgSQL cannot do), access to a mature reference implementation for oracle-based testing, and comprehensive coverage of edge cases that pure random testing misses.

---

## 1. Tools and Frameworks

### 1.1 Python Hypothesis (Recommended Primary Tool)

**URL:** https://hypothesis.readthedocs.io/

Hypothesis is the gold standard for property-based testing in Python. It provides:

- **Sophisticated shrinking**: When a test fails, Hypothesis automatically minimizes the failing input to the smallest case that reproduces the bug
- **Built-in datetime strategies**: `hypothesis.strategies.datetimes()`, `hypothesis.strategies.timedeltas()`
- **Stateful testing**: Can model sequences of operations
- **Database for reproducibility**: Saves failing examples to replay later
- **Third-party extension**: `hypothesis-sqlalchemy` for SQLAlchemy integration

**PostgreSQL Integration Pattern:**
```python
import psycopg2
from hypothesis import given, strategies as st, settings
from dateutil.rrule import rrulestr
from datetime import datetime

@given(
    freq=st.sampled_from(['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY']),
    count=st.integers(min_value=1, max_value=100),
    interval=st.integers(min_value=1, max_value=10),
    dtstart=st.datetimes(min_value=datetime(2020, 1, 1), max_value=datetime(2030, 1, 1))
)
@settings(max_examples=500)
def test_rrule_monotonic(freq, count, interval, dtstart):
    rrule_str = f"FREQ={freq};COUNT={count};INTERVAL={interval}"

    conn = psycopg2.connect(...)
    cur = conn.cursor()
    cur.execute(
        "SELECT array_agg(r ORDER BY r) FROM rrule.\"all\"(%s, %s) r",
        (rrule_str, dtstart)
    )
    results = cur.fetchone()[0]

    # Verify monotonicity
    if results:
        for i in range(1, len(results)):
            assert results[i] > results[i-1], f"Non-monotonic at {i}"
```

### 1.2 python-dateutil (Reference Oracle)

**URL:** https://dateutil.readthedocs.io/en/stable/rrule.html

The `python-dateutil` library is the canonical Python implementation of RFC 5545 RRULE. It serves as an excellent **test oracle** for differential testing:

```python
from dateutil.rrule import rrulestr
from dateutil.parser import parse

def get_dateutil_results(rrule_str, dtstart, count_limit=1000):
    """Get results from python-dateutil as reference."""
    rule = rrulestr(f"RRULE:{rrule_str}", dtstart=dtstart)
    return list(rule[:count_limit])

def get_plpgsql_results(conn, rrule_str, dtstart):
    """Get results from PL/pgSQL implementation."""
    cur = conn.cursor()
    cur.execute(
        "SELECT array_agg(r ORDER BY r) FROM rrule.\"all\"(%s, %s) r",
        (rrule_str, dtstart)
    )
    return cur.fetchone()[0] or []
```

### 1.3 SQLancer (Database Fuzzing Framework)

**URL:** https://github.com/sqlancer/sqlancer

SQLancer is a specialized tool for finding logic bugs in database systems. It supports PostgreSQL and uses techniques like:

- **Pivoted Query Synthesis (PQS)**: Generates queries guaranteed to return specific rows
- **Ternary Logic Partitioning (TLP)**: Splits queries to verify consistency
- **Differential Query Execution (DQE)**: Compares results across implementations

**Relevance:** SQLancer is designed for testing DBMS implementations, not application-level functions. It's overkill for testing a single extension but demonstrates useful oracle patterns.

### 1.4 pgTAP (PostgreSQL Unit Testing)

**URL:** https://pgtap.org/

pgTAP provides TAP-compliant unit testing within PostgreSQL. It's useful for:
- Schema validation
- Function signature testing
- Result comparison with `results_eq()` and `set_eq()`

**Limitation:** pgTAP is for unit testing, not property-based testing. It doesn't provide input generation or shrinking.

### 1.5 QuickCheck Variants

**Haskell QuickCheck:** https://github.com/nick8325/quickcheck
**Rust quickcheck:** https://github.com/BurntSushi/quickcheck

These are mature PBT frameworks but require their respective language ecosystems. Not directly applicable to PostgreSQL testing unless wrapping SQL calls.

---

## 2. Useful Properties for RRULE Testing

### 2.1 Fundamental Invariants (Currently Tested)

| Property | Description | Implementation |
|----------|-------------|----------------|
| **Monotonicity** | Results are strictly ascending, no duplicates | `results[i] > results[i-1]` for all i |
| **COUNT Respect** | Exactly COUNT results (or fewer if bounded) | `len(results) <= count` |
| **UNTIL Respect** | No results after UNTIL date | `max(results) <= until` |
| **dtstart Boundary** | All results >= dtstart | `min(results) >= dtstart` |
| **10-Year Cap** | No results beyond safety window | `max(results) <= dtstart + 10 years` |
| **1000 Cap** | Maximum result count enforced | `len(results) <= 1000` |

### 2.2 Advanced Properties (Recommended Additions)

| Property | Description | Example Test |
|----------|-------------|--------------|
| **Interval Spacing** | Simple RRULEs have predictable gaps | `FREQ=DAILY;INTERVAL=3` has 3-day gaps |
| **BYDAY Filtering** | Results only on specified weekdays | All results match BYDAY days |
| **BYMONTH Filtering** | Results only in specified months | All results in BYMONTH months |
| **BYMONTHDAY Filtering** | Results only on specified days | All results on BYMONTHDAY days |
| **Idempotence** | Multiple calls return same results | `all(r1, d) == all(r1, d)` |
| **Subset Relationship** | `between(start, end)` is subset of `all()` | `set(between) <= set(all)` |
| **after/before Consistency** | `after(d)` equals first result > d from `all()` | Single-element agreement |
| **Timezone Consistency** | TIMESTAMP and TIMESTAMPTZ APIs agree | Wall-clock times match |

### 2.3 Differential Properties (Oracle-Based)

| Property | Description | Oracle |
|----------|-------------|--------|
| **Reference Match** | Results match python-dateutil | `plpgsql_results == dateutil_results` |
| **rrule.js Match** | Results match JavaScript implementation | For TZID= rules specifically |
| **RFC Examples** | RFC 5545 examples produce expected output | Hardcoded RFC examples |

### 2.4 Property Patterns from Literature

From "Choosing properties for property-based testing" (F# for Fun and Profit):

1. **Round-trip / Inverse**: If you serialize then deserialize, you get the original
   - For RRULE: Parse then stringify produces equivalent rule

2. **Idempotence**: Applying operation twice equals applying once
   - For RRULE: Calling `all()` twice returns identical results

3. **Invariants**: Properties that don't change
   - For RRULE: Result count never exceeds COUNT parameter

4. **Commutativity**: Order doesn't matter
   - For RRULE: `BYDAY=MO,TU` equals `BYDAY=TU,MO`

5. **Test Oracle**: Compare with reference implementation
   - For RRULE: Compare with python-dateutil

---

## 3. Integration Approaches

### 3.1 Approach A: Python Hypothesis + psycopg2 (Recommended)

**Architecture:**
```
pytest + hypothesis
        |
        v
   psycopg2 connection
        |
        v
   PostgreSQL with rrule schema
```

**Pros:**
- Full shrinking support
- Sophisticated strategies for datetime generation
- Can run differential tests against python-dateutil
- Easy CI integration with pytest

**Cons:**
- Requires Python environment alongside PostgreSQL
- Network overhead for each test case
- Connection pooling needed for performance

**Implementation Sketch:**
```python
# tests/property/test_rrule_properties.py
import pytest
import psycopg2
from hypothesis import given, strategies as st, settings, Phase
from dateutil.rrule import rrulestr, DAILY, WEEKLY, MONTHLY, YEARLY
from datetime import datetime, timedelta

# Custom strategy for valid RRULE strings
@st.composite
def rrule_strategy(draw):
    freq = draw(st.sampled_from(['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY']))
    parts = [f'FREQ={freq}']

    if draw(st.booleans()):
        parts.append(f'COUNT={draw(st.integers(1, 100))}')

    if draw(st.booleans()):
        parts.append(f'INTERVAL={draw(st.integers(1, 10))}')

    if freq != 'WEEKLY' and draw(st.booleans()):
        day = draw(st.integers(1, 28))
        parts.append(f'BYMONTHDAY={day}')

    return ';'.join(parts)

@pytest.fixture(scope='module')
def db_connection():
    conn = psycopg2.connect(
        host='localhost', port=54322,
        user='postgres', password='postgres',
        dbname='rrule_test'
    )
    yield conn
    conn.close()

@given(
    rrule=rrule_strategy(),
    dtstart=st.datetimes(
        min_value=datetime(2020, 1, 1),
        max_value=datetime(2025, 1, 1)
    )
)
@settings(max_examples=1000, phases=[Phase.generate, Phase.shrink])
def test_differential_vs_dateutil(db_connection, rrule, dtstart):
    """Results should match python-dateutil reference implementation."""
    # Get PL/pgSQL results
    cur = db_connection.cursor()
    cur.execute(
        "SELECT array_agg(r ORDER BY r) FROM rrule.\"all\"(%s, %s) r",
        (rrule, dtstart)
    )
    pg_results = cur.fetchone()[0] or []

    # Get python-dateutil results
    try:
        rule = rrulestr(f'RRULE:{rrule}', dtstart=dtstart)
        du_results = list(rule[:1000])  # Match 1000 cap
    except ValueError:
        # Invalid RRULE for dateutil - skip
        return

    # Compare (allowing for minor implementation differences)
    assert len(pg_results) == len(du_results), \
        f"Count mismatch: PG={len(pg_results)}, dateutil={len(du_results)}"

    for i, (pg, du) in enumerate(zip(pg_results, du_results)):
        assert pg == du, f"Mismatch at {i}: PG={pg}, dateutil={du}"
```

### 3.2 Approach B: Pure PL/pgSQL (Current Approach)

**Architecture:**
```
psql script
     |
     v
PL/pgSQL random generators
     |
     v
PL/pgSQL verification functions
```

**Pros:**
- No external dependencies
- Runs entirely in database
- Fast execution (no network)
- Simple CI integration

**Cons:**
- **No shrinking** - when a test fails, you see the full random input
- Limited random generation capabilities
- No access to reference implementations
- Hard to debug failures

**Current Implementation:** See `tests/fuzz/test_property_invariants.sql`

### 3.3 Approach C: Hybrid (Recommended)

**Use both approaches:**

1. **PL/pgSQL property tests** for CI smoke testing (fast, self-contained)
2. **Python/Hypothesis tests** for deep property testing with shrinking
3. **Differential tests** against python-dateutil for correctness verification

**CI Pipeline:**
```yaml
test:
  steps:
    - name: Quick PL/pgSQL property tests
      run: psql -f tests/fuzz/test_property_invariants.sql

    - name: Python property tests with shrinking
      run: pytest tests/property/ --hypothesis-seed=$RANDOM

    - name: Differential tests vs dateutil
      run: pytest tests/property/test_differential.py
```

---

## 4. Shrinking Strategies

### 4.1 What is Shrinking?

When a property-based test fails, **shrinking** automatically reduces the failing input to the smallest case that still fails. This is critical for debugging.

**Example without shrinking (PL/pgSQL current behavior):**
```
FAIL: FREQ=MONTHLY;COUNT=47;INTERVAL=3;BYDAY=MO,WE,FR;BYMONTH=2,7,11
      dtstart=2023-07-15 14:32:17
```

**Example with shrinking (Hypothesis):**
```
FAIL: FREQ=MONTHLY;COUNT=1;BYMONTH=2
      dtstart=2023-02-01 00:00:00

Shrinking: 47 -> 1 (count), removed INTERVAL, removed BYDAY,
           simplified BYMONTH, simplified dtstart
```

### 4.2 Hypothesis Shrinking for RRULE

Hypothesis automatically shrinks based on the strategies used:

```python
# Strategy composition enables smart shrinking
@st.composite
def rrule_strategy(draw):
    # Hypothesis will try removing optional parts first
    freq = draw(st.sampled_from(['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY']))
    count = draw(st.integers(1, 100))  # Will shrink toward 1

    # Optional parts - Hypothesis tries removing these
    interval = draw(st.one_of(st.none(), st.integers(2, 10)))
    byday = draw(st.one_of(st.none(), byday_strategy()))

    # Build RRULE
    parts = [f'FREQ={freq}', f'COUNT={count}']
    if interval:
        parts.append(f'INTERVAL={interval}')
    if byday:
        parts.append(f'BYDAY={byday}')

    return ';'.join(parts)
```

### 4.3 Manual Shrinking in PL/pgSQL (Limited)

If you must stay in PL/pgSQL, implement basic shrinking manually:

```sql
-- Pseudo-code for manual shrinking
CREATE OR REPLACE FUNCTION shrink_rrule(failing_rrule TEXT)
RETURNS TEXT AS $$
DECLARE
    parts TEXT[];
    simplified TEXT;
    i INT;
BEGIN
    parts := string_to_array(failing_rrule, ';');

    -- Try removing each optional part
    FOR i IN 1..array_length(parts, 1) LOOP
        IF parts[i] NOT LIKE 'FREQ=%' THEN
            simplified := array_to_string(
                array_remove(parts, parts[i]), ';'
            );
            -- Test if still fails
            IF still_fails(simplified) THEN
                RETURN shrink_rrule(simplified);  -- Recurse
            END IF;
        END IF;
    END LOOP;

    RETURN failing_rrule;  -- Can't shrink further
END;
$$ LANGUAGE plpgsql;
```

**Recommendation:** Don't implement shrinking in PL/pgSQL. Use Hypothesis instead.

---

## 5. Comparison: External Tools vs Native PL/pgSQL

| Aspect | PL/pgSQL Native | Python/Hypothesis |
|--------|-----------------|-------------------|
| **Setup Complexity** | None | Moderate (Python env, psycopg2) |
| **Execution Speed** | Fast (in-process) | Slower (network + Python) |
| **Shrinking** | None | Automatic, sophisticated |
| **Input Generation** | Basic (random()) | Rich strategies, composable |
| **Reference Oracle** | Not available | python-dateutil integration |
| **Debugging** | Hard (full random input) | Easy (minimized failing case) |
| **CI Integration** | Simple (psql script) | Requires Python in CI |
| **Reproducibility** | Seed-based | Database + seed-based |
| **Coverage** | Random sampling | Guided by shrinking |

### Recommendation Matrix

| Scenario | Recommended Approach |
|----------|---------------------|
| Quick CI smoke test | PL/pgSQL native |
| Finding edge cases | Python/Hypothesis |
| Verifying RFC compliance | Differential vs dateutil |
| Debugging failures | Python/Hypothesis (shrinking) |
| Performance testing | PL/pgSQL native |
| New feature development | Python/Hypothesis + differential |

---

## 6. Practical Implementation Plan

### Phase 1: Keep Current PL/pgSQL Tests (Week 1)
- Current `test_property_invariants.sql` provides value
- Fast, no dependencies, good CI smoke test
- Add more invariants (BYDAY filtering, timezone consistency)

### Phase 2: Add Python/Hypothesis Framework (Week 2)
```
tests/
  property/
    conftest.py          # DB fixtures, strategies
    test_invariants.py   # Port PL/pgSQL invariants
    test_differential.py # vs python-dateutil
    strategies.py        # Custom RRULE strategies
```

### Phase 3: Differential Testing (Week 3)
- Compare every generated RRULE against python-dateutil
- Document known differences (implementation choices)
- Create exception list for intentional deviations

### Phase 4: CI Integration (Week 4)
```yaml
# .github/workflows/test.yml
jobs:
  test:
    steps:
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install Python dependencies
        run: pip install hypothesis psycopg2-binary python-dateutil pytest

      - name: Run property tests
        run: pytest tests/property/ -v --hypothesis-seed=${{ github.run_id }}
```

---

## 7. References

### Primary Sources

1. **Hypothesis Documentation**
   - Main docs: https://hypothesis.readthedocs.io/
   - Strategies reference: https://hypothesis.readthedocs.io/en/latest/data.html
   - Stateful testing: https://hypothesis.works/articles/rule-based-stateful-testing/

2. **python-dateutil rrule**
   - Documentation: https://dateutil.readthedocs.io/en/stable/rrule.html
   - Source code: https://github.com/dateutil/dateutil
   - Test suite: https://sources.debian.org/src/python-dateutil/2.9.0-4/tests/test_rrule.py

3. **pgTAP**
   - Main site: https://pgtap.org/
   - Documentation: https://pgtap.org/documentation.html

4. **SQLancer**
   - Repository: https://github.com/sqlancer/sqlancer
   - Paper: "Testing Database Engines via Pivoted Query Synthesis" (USENIX OSDI 2020)

### Academic Papers

5. **Property-based Testing in Database Context**
   - "Property-Based Testing in the Context of Database Applications" - Thesis
   - URL: https://www.michaelhanus.de/lehre/abschlussarbeiten/msc/Juergensen_Lars.pdf

6. **Differential Testing**
   - "Randomized Differential Testing as a Prelude to Formal Verification"
   - URL: https://agroce.github.io/icse07.pdf

7. **Test-Case Reduction**
   - "Everything You Ever Wanted To Know About Test-Case Reduction"
   - URL: https://blog.trailofbits.com/2019/11/11/test-case-reduction/
   - "Notes on Test-Case Reduction" by David R. MacIver
   - URL: https://www.drmaciver.com/2019/01/notes-on-test-case-reduction/

### Blog Posts and Tutorials

8. **Property-Based Testing Patterns**
   - "Choosing properties for property-based testing"
   - URL: https://fsharpforfunandprofit.com/posts/property-based-testing-2/

9. **Hypothesis for System Checks**
   - URL: https://incognitjoe.github.io/hypothesis-for-system-checks.html

10. **Property-Based Testing from Scratch (Date Logic)**
    - URL: https://www.russellduhon.com/post/property-based-testing-from-scratch/

11. **Lobsters Discussion: RRULE and PBT**
    - "Time Travelling and Fixing Bugs with Property-Based Testing"
    - URL: https://lobste.rs/s/twojgq/time_travelling_fixing_bugs_with

### Tools and Libraries

12. **hypothesis-sqlalchemy** (SQLAlchemy strategies)
    - PyPI: https://pypi.org/project/hypothesis-sqlalchemy/
    - Docs: https://hypothesis.readthedocs.io/en/latest/extensions.html

13. **pytest-postgresql** (PostgreSQL fixtures for pytest)
    - PyPI: https://pypi.org/project/pytest-postgresql/

14. **rrule.js** (JavaScript reference implementation)
    - Repository: https://github.com/jkbrzt/rrule
    - Test suite: https://github.com/jakubroztocil/rrule/blob/master/test/rrule.test.ts

---

## Appendix A: Example Hypothesis Test Suite

```python
# tests/property/conftest.py
import pytest
import psycopg2
from hypothesis import settings, Verbosity

settings.register_profile("ci", max_examples=1000)
settings.register_profile("dev", max_examples=100)
settings.register_profile("debug", max_examples=10, verbosity=Verbosity.verbose)

@pytest.fixture(scope="session")
def db():
    conn = psycopg2.connect(
        host="localhost",
        port=54322,
        user="postgres",
        password="postgres",
        dbname="rrule_test"
    )
    yield conn
    conn.close()
```

```python
# tests/property/strategies.py
from hypothesis import strategies as st
from datetime import datetime

FREQUENCIES = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY']
WEEKDAYS = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU']

@st.composite
def byday_strategy(draw):
    """Generate valid BYDAY values."""
    num_days = draw(st.integers(1, 4))
    days = draw(st.lists(
        st.sampled_from(WEEKDAYS),
        min_size=num_days,
        max_size=num_days,
        unique=True
    ))
    return ','.join(days)

@st.composite
def bymonth_strategy(draw):
    """Generate valid BYMONTH values."""
    num_months = draw(st.integers(1, 4))
    months = draw(st.lists(
        st.integers(1, 12),
        min_size=num_months,
        max_size=num_months,
        unique=True
    ))
    return ','.join(str(m) for m in sorted(months))

@st.composite
def simple_rrule(draw):
    """Generate simple RRULE without complex BYxxx."""
    freq = draw(st.sampled_from(FREQUENCIES))
    count = draw(st.integers(1, 50))
    interval = draw(st.integers(1, 5))

    return f'FREQ={freq};COUNT={count};INTERVAL={interval}'

@st.composite
def complex_rrule(draw):
    """Generate RRULE with BYxxx parameters."""
    freq = draw(st.sampled_from(FREQUENCIES))
    parts = [f'FREQ={freq}']

    # Always bound with COUNT for safety
    parts.append(f'COUNT={draw(st.integers(1, 100))}')

    if draw(st.booleans()):
        parts.append(f'INTERVAL={draw(st.integers(1, 5))}')

    if draw(st.booleans()):
        parts.append(f'BYDAY={draw(byday_strategy())}')

    if draw(st.booleans()):
        parts.append(f'BYMONTH={draw(bymonth_strategy())}')

    if freq != 'WEEKLY' and draw(st.booleans()):
        parts.append(f'BYMONTHDAY={draw(st.integers(1, 28))}')

    return ';'.join(parts)

dtstart_strategy = st.datetimes(
    min_value=datetime(2020, 1, 1),
    max_value=datetime(2028, 1, 1)
)
```

```python
# tests/property/test_invariants.py
from hypothesis import given, settings
from .strategies import simple_rrule, complex_rrule, dtstart_strategy

@given(rrule=simple_rrule(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_monotonicity(db, rrule, dtstart):
    """Results must be strictly ascending."""
    cur = db.cursor()
    cur.execute(
        "SELECT array_agg(r ORDER BY r) FROM rrule.\"all\"(%s, %s) r",
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if results and len(results) > 1:
        for i in range(1, len(results)):
            assert results[i] > results[i-1], \
                f"Non-monotonic: {results[i-1]} >= {results[i]}"

@given(rrule=complex_rrule(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_dtstart_boundary(db, rrule, dtstart):
    """All results must be >= dtstart."""
    cur = db.cursor()
    try:
        cur.execute(
            "SELECT array_agg(r ORDER BY r) FROM rrule.\"all\"(%s, %s) r",
            (rrule, dtstart)
        )
        results = cur.fetchone()[0]
    except Exception:
        return  # Invalid RRULE combination

    if results:
        assert all(r >= dtstart for r in results), \
            f"Result before dtstart: min={min(results)}, dtstart={dtstart}"
```

```python
# tests/property/test_differential.py
from hypothesis import given, settings, assume
from dateutil.rrule import rrulestr
from .strategies import simple_rrule, dtstart_strategy

@given(rrule=simple_rrule(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_matches_dateutil(db, rrule, dtstart):
    """Results should match python-dateutil reference."""
    # Get PL/pgSQL results
    cur = db.cursor()
    cur.execute(
        "SELECT array_agg(r ORDER BY r) FROM rrule.\"all\"(%s, %s) r",
        (rrule, dtstart)
    )
    pg_results = cur.fetchone()[0] or []

    # Get dateutil results
    try:
        rule = rrulestr(f'RRULE:{rrule}', dtstart=dtstart)
        du_results = list(rule[:1000])
    except ValueError:
        assume(False)  # Skip invalid RRULEs

    # Compare
    assert len(pg_results) == len(du_results), \
        f"Count: PG={len(pg_results)} vs dateutil={len(du_results)}"

    for i, (pg, du) in enumerate(zip(pg_results, du_results)):
        # dateutil returns datetime with tzinfo, strip for comparison
        du_naive = du.replace(tzinfo=None) if du.tzinfo else du
        assert pg == du_naive, \
            f"Mismatch at {i}: PG={pg} vs dateutil={du_naive}"
```

---

## Appendix B: Decision Matrix

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Keep PL/pgSQL tests? | Yes | Fast CI smoke tests, no dependencies |
| Add Hypothesis? | Yes | Shrinking, better strategies, differential testing |
| Primary oracle? | python-dateutil | Reference implementation, same RFC basis |
| Secondary oracle? | rrule.js | For TZID= timezone rules specifically |
| CI approach? | Hybrid | PL/pgSQL for speed, Python for depth |
| Shrinking in PL/pgSQL? | No | Not worth the complexity vs Hypothesis |

---

*Document generated: 2026-02-05*
*For: rrule_plpgsql project*
