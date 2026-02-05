# Plan: Increment 3.3 - Advanced Property Tests

**Status:** ✅ Complete
**Parent:** [PLAN.md](PLAN.md) - Test Quality Improvement Plan
**Created:** 2026-02-05

## Overview

Implement the 5 advanced property tests identified in RESEARCH_PROPERTY_TESTING.md Section 2.2 that were marked as optional in the original plan.

## Properties to Implement

| # | Property | Description | Complexity |
|---|----------|-------------|------------|
| 1 | Interval Spacing | `FREQ=DAILY;INTERVAL=3` produces exactly 3-day gaps | Low |
| 2 | Idempotence | `all(rrule, dtstart)` returns identical results on repeated calls | Low |
| 3 | Subset Relationship | `between(start, end)` results are a subset of `all()` results | Medium |
| 4 | after/before Consistency | `after(d)` equals first result > d from `all()` | Medium |
| 5 | Timezone Consistency | `TZID=` in RRULE produces same results as explicit `timezone` param | Medium |

---

## Increment 3.3.1: Interval Spacing Property

**File:** `tests/property/test_advanced.py` (new file)

**Strategy Needed:** `rrule_with_interval()` - generates RRULEs with known FREQ and INTERVAL

**Property:**
```python
For FREQ=DAILY;INTERVAL=N, consecutive results differ by exactly N days
For FREQ=WEEKLY;INTERVAL=N, consecutive results differ by exactly N*7 days
For FREQ=MONTHLY;INTERVAL=N, months differ by exactly N (with day adjustments)
For FREQ=YEARLY;INTERVAL=N, years differ by exactly N (with leap year handling)
```

**Implementation Notes:**
- Only test simple RRULEs without BYxxx filters (filters can cause skips)
- MONTHLY/YEARLY need special handling for month-end dates and SKIP behavior
- Focus on DAILY/WEEKLY initially which have deterministic intervals
- Use bounded COUNT to ensure termination

**Expected Challenges:**
- MONTHLY with dates > 28 may skip months (SKIP=OMIT default)
- YEARLY on Feb 29 skips non-leap years
- Solution: Test DAILY/WEEKLY exhaustively, MONTHLY/YEARLY only with safe dates (1-28)

---

## Increment 3.3.2: Idempotence Property

**File:** `tests/property/test_advanced.py`

**Property:**
```python
all(rrule, dtstart) called twice returns identical results
```

**Implementation:**
```python
@given(rrule=simple_rrule(), dtstart=dtstart_strategy)
def test_idempotence(db, rrule, dtstart):
    """Multiple calls to all() return identical results."""
    cur = db.cursor()

    # First call
    cur.execute('SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r', (rrule, dtstart))
    results1 = cur.fetchone()[0] or []

    # Second call
    cur.execute('SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r', (rrule, dtstart))
    results2 = cur.fetchone()[0] or []

    assert results1 == results2
```

**Complexity:** Low - straightforward implementation

**Notes:**
- This verifies no side effects or non-deterministic behavior
- Tests both simple and complex RRULEs
- Should always pass unless there's a serious bug

---

## Increment 3.3.3: Subset Relationship Property

**File:** `tests/property/test_advanced.py`

**Strategy Needed:** `rrule_with_date_range()` - generates RRULE with compatible start/end range

**Property:**
```python
set(between(rrule, dtstart, range_start, range_end)) ⊆ set(all(rrule, dtstart))
```

**Implementation:**
```python
@st.composite
def rrule_with_date_range(draw):
    """Generate RRULE with a date range for between() testing."""
    rrule = draw(simple_rrule())
    dtstart = draw(dtstart_strategy)

    # Range start: 0-365 days after dtstart
    offset_start = draw(st.integers(0, 365))
    range_start = dtstart + timedelta(days=offset_start)

    # Range end: 1-365 days after range_start
    offset_end = draw(st.integers(1, 365))
    range_end = range_start + timedelta(days=offset_end)

    return rrule, dtstart, range_start, range_end

@given(data=rrule_with_date_range())
def test_between_is_subset_of_all(db, data):
    """Results from between() must be a subset of all()."""
    rrule, dtstart, range_start, range_end = data
    cur = db.cursor()

    # Get all results
    cur.execute('SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r', (rrule, dtstart))
    all_results = set(cur.fetchone()[0] or [])

    # Get between results
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."between"(%s, %s, %s, %s) r',
        (rrule, dtstart, range_start, range_end)
    )
    between_results = set(cur.fetchone()[0] or [])

    # Subset check
    assert between_results <= all_results
```

**Complexity:** Medium - requires careful range generation

**Edge Cases:**
- `inc=FALSE` (default) excludes boundaries - handle this
- Range entirely before dtstart should return empty
- Range entirely after 10-year cap should return empty

---

## Increment 3.3.4: after/before Consistency Property

**File:** `tests/property/test_advanced.py`

**Strategy Needed:** `rrule_with_reference_date()` - generates RRULE + a date to query after/before

**API Signatures (verified from source):**
```sql
rrule."after"(rrule_string TEXT, dtstart TIMESTAMPTZ, after_date TIMESTAMPTZ, count INT, timezone TEXT DEFAULT NULL, inc BOOLEAN DEFAULT FALSE)
rrule."before"(rrule_string TEXT, dtstart TIMESTAMPTZ, before_date TIMESTAMPTZ, count INT, timezone TEXT DEFAULT NULL, inc BOOLEAN DEFAULT FALSE)
```

**Note:** Both functions require a `count` parameter. Use `count=1` to get a single result.

**Property:**
```python
after(rrule, dtstart, date, count=1) == first result from all() where result > date
before(rrule, dtstart, date, count=1) == last result from all() where result < date
```

**Implementation:**
```python
@st.composite
def rrule_with_reference_date(draw):
    """Generate RRULE with a reference date for after/before testing."""
    rrule = draw(simple_rrule())
    dtstart = draw(dtstart_strategy)

    # Reference date: within reasonable range of dtstart
    offset = draw(st.integers(-30, 365))
    ref_date = dtstart + timedelta(days=offset)

    return rrule, dtstart, ref_date

@given(data=rrule_with_reference_date())
def test_after_consistency(db, data):
    """after(date, count=1) should equal first result > date from all()."""
    rrule, dtstart, ref_date = data
    cur = db.cursor()

    # Get after() result (count=1 for single result)
    cur.execute(
        'SELECT r FROM rrule."after"(%s, %s, %s, 1) r',
        (rrule, dtstart, ref_date)
    )
    row = cur.fetchone()
    after_result = row[0] if row else None

    # Get all() and find first > ref_date
    cur.execute('SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r', (rrule, dtstart))
    all_results = cur.fetchone()[0] or []

    expected = None
    for r in all_results:
        if r > ref_date:
            expected = r
            break

    assert after_result == expected, \
        f"after() returned {after_result}, expected {expected} (first > {ref_date})"

@given(data=rrule_with_reference_date())
def test_before_consistency(db, data):
    """before(date, count=1) should equal last result < date from all()."""
    rrule, dtstart, ref_date = data
    cur = db.cursor()

    # Get before() result (count=1 for single result)
    cur.execute(
        'SELECT r FROM rrule."before"(%s, %s, %s, 1) r',
        (rrule, dtstart, ref_date)
    )
    row = cur.fetchone()
    before_result = row[0] if row else None

    # Get all() and find last < ref_date
    cur.execute('SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r', (rrule, dtstart))
    all_results = cur.fetchone()[0] or []

    expected = None
    for r in reversed(all_results):
        if r < ref_date:
            expected = r
            break

    assert before_result == expected, \
        f"before() returned {before_result}, expected {expected} (last < {ref_date})"
```

**Complexity:** Medium - straightforward but needs careful edge case handling

**Edge Cases:**
- `inc=TRUE` variant (include boundary) - add separate tests
- ref_date before dtstart - should return None for before(), first result for after()
- ref_date after all results - should return last result for before(), None for after()
- Empty result set - both should return None

---

## Increment 3.3.5: Timezone Consistency Property

**File:** `tests/property/test_advanced.py`

**Property:**
```python
TZID= in RRULE string produces identical results to explicit timezone parameter
```

**API Signatures (verified from source):**
```sql
-- All public API functions accept timezone via either method:
rrule."all"(rrule_string TEXT, dtstart TIMESTAMPTZ, timezone TEXT DEFAULT NULL)
rrule."between"(rrule_string TEXT, dtstart TIMESTAMPTZ, range_start TIMESTAMPTZ, range_end TIMESTAMPTZ, timezone TEXT DEFAULT NULL, inc BOOLEAN DEFAULT FALSE)
rrule."after"(rrule_string TEXT, dtstart TIMESTAMPTZ, after_date TIMESTAMPTZ, count INT, timezone TEXT DEFAULT NULL, inc BOOLEAN DEFAULT FALSE)
rrule."before"(rrule_string TEXT, dtstart TIMESTAMPTZ, before_date TIMESTAMPTZ, count INT, timezone TEXT DEFAULT NULL, inc BOOLEAN DEFAULT FALSE)
```

**Timezone Resolution (from code):**
```sql
tz_name := COALESCE(
    timezone,                                           -- 1. Explicit parameter
    substring(rrule_string from 'TZID=([^;]+)(;|$)'),  -- 2. TZID in RRULE
    'UTC'                                               -- 3. Default
);
```

**Implementation:**
```python
@st.composite
def rrule_with_timezone(draw):
    """Generate RRULE for timezone consistency testing."""
    freq = draw(st.sampled_from(['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY']))
    count = draw(st.integers(1, 20))
    interval = draw(st.integers(1, 3))

    # Use timezones with DST transitions for thorough testing
    tz = draw(st.sampled_from(['America/New_York', 'Europe/London', 'America/Los_Angeles']))

    # Build RRULE with TZID embedded
    rrule_with_tzid = f'FREQ={freq};COUNT={count};INTERVAL={interval};TZID={tz}'

    # RRULE without TZID (tz passed as explicit parameter)
    rrule_without_tzid = f'FREQ={freq};COUNT={count};INTERVAL={interval}'

    return rrule_with_tzid, rrule_without_tzid, tz

@given(data=rrule_with_timezone(), dtstart=dtstart_no_microseconds)
def test_timezone_consistency(db, data, dtstart):
    """TZID= in RRULE should produce identical results to explicit timezone parameter."""
    rrule_with_tzid, rrule_without_tzid, tz = data
    cur = db.cursor()

    # Method 1: TZID= embedded in RRULE string
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule_with_tzid, dtstart)
    )
    tzid_results = cur.fetchone()[0] or []

    # Method 2: Explicit timezone parameter
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s, %s) r',
        (rrule_without_tzid, dtstart, tz)
    )
    explicit_tz_results = cur.fetchone()[0] or []

    # Both methods should produce identical TIMESTAMPTZ results
    assert len(tzid_results) == len(explicit_tz_results), \
        f"Count mismatch: TZID={len(tzid_results)} vs explicit={len(explicit_tz_results)}"

    for tzid_r, explicit_r in zip(tzid_results, explicit_tz_results):
        assert tzid_r == explicit_r, f"Mismatch: TZID={tzid_r} vs explicit={explicit_r}"
```

**Complexity:** Medium (downgraded from High - API is simpler than expected)

**Expected Behavior:**
- Both methods use identical internal processing (same COALESCE resolution)
- Results should be byte-for-byte identical TIMESTAMPTZ values
- DST transitions handled identically since same internal generator is used

**What This Test Validates:**
1. TZID= parsing extracts timezone correctly from RRULE string
2. Explicit parameter and embedded TZID produce identical behavior
3. No subtle differences in timezone handling between the two methods

---

## Implementation Order

1. **3.3.2 Idempotence** (Low complexity, foundational)
2. **3.3.1 Interval Spacing** (Low complexity, valuable for correctness)
3. **3.3.3 Subset Relationship** (Medium complexity, tests API consistency)
4. **3.3.4 after/before Consistency** (Medium complexity, tests API consistency)
5. **3.3.5 Timezone Consistency** (High complexity, requires API investigation)

## File Structure

```
tests/property/
├── conftest.py              # Existing - no changes needed
├── strategies.py            # ADD: new strategies for advanced tests
├── known_differences.py     # Existing - may need additions for TZ
├── test_invariants.py       # Existing - no changes needed
├── test_differential.py     # Existing - no changes needed
└── test_advanced.py         # NEW: all 5 advanced property tests
```

## New Strategies Required

Add to `strategies.py`:

1. `rrule_with_interval()` - for interval spacing tests
2. `rrule_with_date_range()` - for subset relationship tests
3. `rrule_with_reference_date()` - for after/before consistency tests
4. `rrule_with_timezone()` - for timezone consistency tests

## Success Criteria

| Test | Pass Condition |
|------|----------------|
| Interval Spacing | 500 examples pass, or documented exceptions |
| Idempotence | 500 examples pass, 100% |
| Subset Relationship | 500 examples pass, or documented edge cases |
| after/before Consistency | 500 examples pass, with inc variants |
| Timezone Consistency | 500 examples pass, or documented TZ differences |

## CI Integration

The new tests will automatically run with existing CI configuration since they're in `tests/property/` directory.

## Estimated Effort

| Increment | Effort |
|-----------|--------|
| 3.3.2 Idempotence | 30 min |
| 3.3.1 Interval Spacing | 1 hour |
| 3.3.3 Subset Relationship | 1 hour |
| 3.3.4 after/before Consistency | 1-2 hours |
| 3.3.5 Timezone Consistency | 1 hour |
| **Total** | **4-6 hours** |

---

## Pre-Implementation Checklist

- [x] Verify public API function signatures (all use TIMESTAMPTZ, optional timezone param)
- [x] Review timezone resolution order (explicit param > TZID > UTC)
- [x] Confirm `after()`/`before()` require `count` parameter
- [x] Run existing property tests to ensure baseline is passing

## Notes

- All tests should use `@settings(max_examples=500)` for consistency with existing tests
- Any intentional differences discovered should be documented in `known_differences.py`
- Focus on catching real bugs, not implementation details

---

## Implementation Results

**Completed:** 2026-02-05

All 5 advanced property tests implemented and passing:

| Test | Status | File/Function |
|------|--------|---------------|
| Idempotence | ✅ Pass | `test_advanced.py::test_idempotence` |
| Interval Spacing | ✅ Pass | `test_advanced.py::test_interval_spacing` |
| Subset Relationship | ✅ Pass | `test_advanced.py::test_between_subset_of_all` |
| after/before Consistency | ✅ Pass | `test_advanced.py::test_after_consistency`, `test_after_with_inc_consistency`, `test_before_consistency` |
| Timezone Consistency | ✅ Pass | `test_advanced.py::test_timezone_consistency` |

**New strategies added to `strategies.py`:**
- `simple_rrule_no_byxxx()` - RRULEs without BYxxx modifiers
- `dtstart_safe_for_monthly()` - dtstart with day ≤ 28
- `rrule_with_tzid()` - RRULEs with embedded TZID
- `COMMON_TIMEZONES` - List of test timezones
- `timezone_strategy` - Timezone selection strategy

**Total property tests:** 21 (7 advanced + 3 differential + 11 invariant)
