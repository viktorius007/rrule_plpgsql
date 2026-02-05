"""Advanced property-based tests for RRULE API consistency.

These tests verify semantic properties and API consistency across different
query methods. Unlike invariant tests that verify single-function properties,
these tests verify relationships between multiple API functions.

Test Coverage:
1. Idempotence - all() called twice returns identical results
2. Interval Spacing - consecutive results differ by expected FREQ*INTERVAL
3. Subset Relationship - between() results ⊆ all() results
4. after/before Consistency - after(d,1) = first result > d from all()
5. Timezone Consistency - TZID=X in RRULE = explicit timezone=X param
"""

from datetime import timedelta
from dateutil.relativedelta import relativedelta
from hypothesis import given, settings, assume

from .strategies import (
    simple_rrule,
    simple_rrule_no_byxxx,
    dtstart_strategy,
    dtstart_no_microseconds,
    dtstart_safe_for_monthly,
    rrule_with_tzid,
)


def normalize_timestamp(ts):
    """Normalize timestamp to naive (without timezone) for comparison.

    psycopg2 may return timestamps with or without timezone info depending
    on the column type and connection settings. Normalize to naive timestamps
    so comparisons work reliably.
    """
    if ts is None:
        return None
    if hasattr(ts, 'tzinfo') and ts.tzinfo is not None:
        # Convert to naive UTC
        return ts.replace(tzinfo=None)
    return ts


def normalize_results(results):
    """Normalize a list of results to naive timestamps."""
    if not results:
        return []
    return [normalize_timestamp(r) for r in results]


# =============================================================================
# Test 1: Idempotence
# =============================================================================

@given(rrule=simple_rrule(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_idempotence(db, rrule, dtstart):
    """all() called twice returns identical results.

    This verifies that the function is deterministic - calling it multiple
    times with the same inputs produces the exact same output. A failure
    here would indicate non-determinism (e.g., uninitialized variables,
    random behavior, or race conditions).
    """
    cur = db.cursor()

    # First call
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results1 = cur.fetchone()[0] or []

    # Second call with same parameters
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results2 = cur.fetchone()[0] or []

    assert results1 == results2, (
        f"Idempotence violation for RRULE '{rrule}' with dtstart={dtstart}: "
        f"First call returned {len(results1)} results, second returned {len(results2)}"
    )


# =============================================================================
# Test 2: Interval Spacing
# =============================================================================

@given(data=simple_rrule_no_byxxx(), dtstart=dtstart_safe_for_monthly())
@settings(max_examples=500)
def test_interval_spacing(db, data, dtstart):
    """Consecutive results differ by expected FREQ*INTERVAL.

    For simple RRULEs without BYxxx modifiers, the difference between
    consecutive occurrences should be exactly INTERVAL units of the
    frequency period (days, weeks, months, or years).

    Uses dtstart with day <= 28 to avoid SKIP=OMIT edge cases that
    would cause months to be skipped on day 29-31.
    """
    rrule, freq, interval = data

    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if not results or len(results) < 2:
        assume(False)  # Need at least 2 results to check spacing

    # Check spacing between consecutive results
    for i in range(1, len(results)):
        prev = results[i - 1]
        curr = results[i]

        if freq == 'DAILY':
            expected_delta = timedelta(days=interval)
            actual_delta = curr - prev
            assert actual_delta == expected_delta, (
                f"DAILY interval spacing violated at index {i}: "
                f"expected {expected_delta}, got {actual_delta} "
                f"(prev={prev}, curr={curr}, rrule={rrule})"
            )

        elif freq == 'WEEKLY':
            expected_delta = timedelta(weeks=interval)
            actual_delta = curr - prev
            assert actual_delta == expected_delta, (
                f"WEEKLY interval spacing violated at index {i}: "
                f"expected {expected_delta}, got {actual_delta} "
                f"(prev={prev}, curr={curr}, rrule={rrule})"
            )

        elif freq == 'MONTHLY':
            # Use relativedelta for month arithmetic
            expected = prev + relativedelta(months=interval)
            assert curr == expected, (
                f"MONTHLY interval spacing violated at index {i}: "
                f"expected {expected}, got {curr} "
                f"(prev={prev}, interval={interval}, rrule={rrule})"
            )

        elif freq == 'YEARLY':
            # Use relativedelta for year arithmetic
            expected = prev + relativedelta(years=interval)
            assert curr == expected, (
                f"YEARLY interval spacing violated at index {i}: "
                f"expected {expected}, got {curr} "
                f"(prev={prev}, interval={interval}, rrule={rrule})"
            )


# =============================================================================
# Test 3: Subset Relationship
# =============================================================================

@given(rrule=simple_rrule(), dtstart=dtstart_no_microseconds)
@settings(max_examples=500)
def test_between_subset_of_all(db, rrule, dtstart):
    """between() results are a subset of all() results.

    When querying with between() for a range, every result should also
    appear in the full all() result set. This verifies that between()
    is filtering all() results correctly, not generating different dates.
    """
    cur = db.cursor()

    # Get all results
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    all_results = normalize_results(cur.fetchone()[0] or [])

    if len(all_results) < 2:
        assume(False)  # Need results to define a meaningful range

    # Define a range within the all() results
    # Use the second result as start and second-to-last as end
    # This ensures the range is within the result set
    range_start = all_results[0]  # First result
    range_end = all_results[-1]   # Last result

    # Get between() results with inc=True to include boundaries
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."between"(%s, %s, %s, %s, NULL, TRUE) r',
        (rrule, dtstart, range_start, range_end)
    )
    between_results = normalize_results(cur.fetchone()[0] or [])

    # Every between() result must be in all() results
    all_set = set(all_results)
    for r in between_results:
        assert r in all_set, (
            f"between() returned {r} which is not in all() results. "
            f"RRULE='{rrule}', dtstart={dtstart}, "
            f"range=[{range_start}, {range_end}]"
        )

    # Also verify the results are within the range (inc=True means inclusive)
    for r in between_results:
        assert range_start <= r <= range_end, (
            f"between() returned {r} outside range [{range_start}, {range_end}]. "
            f"RRULE='{rrule}', dtstart={dtstart}"
        )


# =============================================================================
# Test 4: after/before Consistency
# =============================================================================

@given(rrule=simple_rrule(), dtstart=dtstart_no_microseconds)
@settings(max_examples=500)
def test_after_consistency(db, rrule, dtstart):
    """after(d, 1, inc=False) returns first result > d from all().

    The after() function should return the same result as manually
    filtering all() results for the first one after the given date.
    """
    cur = db.cursor()

    # Get all results
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    all_results = normalize_results(cur.fetchone()[0] or [])

    if len(all_results) < 2:
        assume(False)  # Need at least 2 results for a meaningful test

    # Use a date between first and last occurrence
    # This ensures there's at least one result after it
    after_date = all_results[0]  # Use first result as the boundary

    # Get after() result with inc=False (strictly after)
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."after"(%s, %s, %s, 1, NULL, FALSE) r',
        (rrule, dtstart, after_date)
    )
    after_result = normalize_results(cur.fetchone()[0] or [])
    after_result = after_result[0] if after_result else None

    # Find first result from all() that is strictly greater than after_date
    expected = None
    for r in all_results:
        if r > after_date:
            expected = r
            break

    assert after_result == expected, (
        f"after() inconsistency: expected {expected}, got {after_result}. "
        f"RRULE='{rrule}', dtstart={dtstart}, after_date={after_date}"
    )


@given(rrule=simple_rrule(), dtstart=dtstart_no_microseconds)
@settings(max_examples=500)
def test_after_with_inc_consistency(db, rrule, dtstart):
    """after(d, 1, inc=True) returns first result >= d from all().

    When inc=True, the boundary date itself should be included if it's
    an occurrence.
    """
    cur = db.cursor()

    # Get all results
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    all_results = normalize_results(cur.fetchone()[0] or [])

    if len(all_results) < 1:
        assume(False)

    # Use the first result as the boundary - with inc=True, it should return itself
    after_date = all_results[0]

    # Get after() result with inc=True (inclusive)
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."after"(%s, %s, %s, 1, NULL, TRUE) r',
        (rrule, dtstart, after_date)
    )
    after_result = normalize_results(cur.fetchone()[0] or [])
    after_result = after_result[0] if after_result else None

    # Find first result from all() that is >= after_date
    expected = None
    for r in all_results:
        if r >= after_date:
            expected = r
            break

    assert after_result == expected, (
        f"after(inc=True) inconsistency: expected {expected}, got {after_result}. "
        f"RRULE='{rrule}', dtstart={dtstart}, after_date={after_date}"
    )


@given(rrule=simple_rrule(), dtstart=dtstart_no_microseconds)
@settings(max_examples=500)
def test_before_consistency(db, rrule, dtstart):
    """before(d, 1, inc=False) returns last result < d from all().

    The before() function should return the same result as manually
    filtering all() results for the last one before the given date.
    """
    cur = db.cursor()

    # Get all results
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    all_results = normalize_results(cur.fetchone()[0] or [])

    if len(all_results) < 2:
        assume(False)

    # Use the last result as the boundary
    before_date = all_results[-1]

    # Get before() result with inc=False (strictly before)
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."before"(%s, %s, %s, 1, NULL, FALSE) r',
        (rrule, dtstart, before_date)
    )
    before_result = normalize_results(cur.fetchone()[0] or [])
    before_result = before_result[0] if before_result else None

    # Find last result from all() that is strictly less than before_date
    expected = None
    for r in reversed(all_results):
        if r < before_date:
            expected = r
            break

    assert before_result == expected, (
        f"before() inconsistency: expected {expected}, got {before_result}. "
        f"RRULE='{rrule}', dtstart={dtstart}, before_date={before_date}"
    )


# =============================================================================
# Test 5: Timezone Consistency
# =============================================================================

@given(data=rrule_with_tzid(), dtstart=dtstart_no_microseconds)
@settings(max_examples=500)
def test_timezone_consistency(db, data, dtstart):
    """TZID=X in RRULE produces same results as explicit timezone=X parameter.

    The two timezone APIs should produce identical results:
    1. RRULE with TZID embedded: rrule."all"('FREQ=DAILY;TZID=America/New_York', dtstart)
    2. Explicit timezone parameter: rrule."all"('FREQ=DAILY', dtstart, 'America/New_York')

    This verifies that timezone handling is consistent regardless of how
    the timezone is specified.

    Note: We cast dtstart explicitly to timestamptz in the target timezone
    to ensure consistent interpretation regardless of psycopg2's handling
    of naive Python datetimes.
    """
    rrule_with_tz, tzid = data

    # Remove TZID from the RRULE string for the explicit timezone call
    # Split by semicolon, filter out TZID part, rejoin
    parts = rrule_with_tz.split(';')
    parts_without_tz = [p for p in parts if not p.startswith('TZID=')]
    rrule_without_tz = ';'.join(parts_without_tz)

    # Format dtstart as ISO string for consistent handling
    dtstart_str = dtstart.strftime('%Y-%m-%d %H:%M:%S')

    cur = db.cursor()

    # Get results using TZID in RRULE
    # Cast the dtstart to timestamptz explicitly in the target timezone
    # so that "2020-02-01 00:00:00" is interpreted as "2020-02-01 00:00:00 America/New_York"
    cur.execute(
        """SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s,
           (%s::timestamp AT TIME ZONE %s)::timestamptz) r""",
        (rrule_with_tz, dtstart_str, tzid)
    )
    results_with_tzid = normalize_results(cur.fetchone()[0] or [])

    # Get results using explicit timezone parameter
    # Same cast to ensure identical dtstart interpretation
    cur.execute(
        """SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s,
           (%s::timestamp AT TIME ZONE %s)::timestamptz, %s) r""",
        (rrule_without_tz, dtstart_str, tzid, tzid)
    )
    results_explicit_tz = normalize_results(cur.fetchone()[0] or [])

    # Compare lengths
    assert len(results_with_tzid) == len(results_explicit_tz), (
        f"Timezone consistency violation: TZID in RRULE returned {len(results_with_tzid)} results, "
        f"explicit timezone param returned {len(results_explicit_tz)} results. "
        f"RRULE='{rrule_with_tz}', dtstart={dtstart}, tzid={tzid}"
    )

    # Compare each occurrence
    for i, (r1, r2) in enumerate(zip(results_with_tzid, results_explicit_tz)):
        assert r1 == r2, (
            f"Timezone consistency mismatch at index {i}: "
            f"TZID in RRULE={r1}, explicit timezone={r2}. "
            f"RRULE='{rrule_with_tz}', dtstart={dtstart}, tzid={tzid}"
        )
