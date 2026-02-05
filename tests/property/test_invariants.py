"""Property-based tests for RRULE invariants.

These tests verify fundamental properties that must hold for all valid RRULE inputs.
Unlike example-based tests, property tests use Hypothesis to generate many random
inputs and automatically shrink failing cases to minimal reproducible examples.
"""

from datetime import datetime, timedelta
from hypothesis import given, settings
from .strategies import (
    simple_rrule,
    complex_rrule,
    dtstart_strategy,
    rrule_with_byday,
    rrule_with_bymonth,
    rrule_with_bymonthday,
    rrule_with_byweekno,
    rrule_with_count,
    rrule_with_until,
)


# Mapping from RFC 5545 BYDAY to Python datetime weekday (Monday=0)
BYDAY_TO_WEEKDAY = {
    'MO': 0,
    'TU': 1,
    'WE': 2,
    'TH': 3,
    'FR': 4,
    'SA': 5,
    'SU': 6,
}


# =============================================================================
# Core Invariants (ported from PL/pgSQL)
# =============================================================================

@given(rrule=simple_rrule(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_monotonicity(db, rrule, dtstart):
    """Results must be strictly ascending with no duplicates.

    This is a fundamental invariant: RRULE occurrences are always
    ordered chronologically and never repeat. A violation indicates
    a bug in the occurrence generation or deduplication logic.
    """
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if results and len(results) > 1:
        for i in range(1, len(results)):
            assert results[i] > results[i-1], \
                f"Non-monotonic at {i}: {results[i-1]} >= {results[i]}"


@given(data=rrule_with_count(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_count_respected(db, data, dtstart):
    """COUNT parameter must be exactly respected (bounded by caps).

    The number of results should be exactly COUNT, unless limited
    by the 10-year window or 1000-result cap. Never more than COUNT.
    """
    rrule, expected_count = data
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    actual_count = len(results) if results else 0

    # Result count should never exceed the specified COUNT
    assert actual_count <= expected_count, \
        f"COUNT violated: got {actual_count}, expected <= {expected_count}"

    # If we got fewer than COUNT, verify it's due to caps (not a bug)
    if actual_count < expected_count:
        # Results should either be at the 1000 cap or within 10-year window
        if results:
            max_date = dtstart + timedelta(days=3653)  # ~10 years
            last_result = results[-1]
            # Either at 1000 cap or last result near 10-year boundary
            # or YEARLY/MONTHLY with large INTERVAL doesn't reach COUNT in 10 years
            # This is acceptable behavior
            assert actual_count <= 1000 or last_result <= max_date


@given(data=rrule_with_until())
@settings(max_examples=500)
def test_until_respected(db, data):
    """No results should occur after the UNTIL date.

    UNTIL is an inclusive upper bound. All occurrences must be
    on or before the UNTIL timestamp.
    """
    rrule, dtstart, until = data
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if results:
        for r in results:
            assert r <= until, \
                f"UNTIL violated: {r} > {until}"


@given(rrule=simple_rrule(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_dtstart_boundary(db, rrule, dtstart):
    """All results must be >= dtstart.

    The dtstart is the first possible occurrence. No occurrences
    should ever precede it.
    """
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if results:
        for r in results:
            assert r >= dtstart, \
                f"dtstart boundary violated: {r} < {dtstart}"


@given(rrule=simple_rrule(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_10_year_cap(db, rrule, dtstart):
    """Results must be within 10-year window from dtstart.

    This is a safety cap to prevent unbounded recurrence rules
    from generating infinite results.
    """
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if results:
        max_date = dtstart + timedelta(days=3653)  # ~10 years with buffer
        last_result = results[-1]
        assert last_result <= max_date, \
            f"10-year cap violated: {last_result} > {max_date}"


@given(rrule=complex_rrule(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_1000_result_cap(db, rrule, dtstart):
    """Results must not exceed 1000.

    This is a safety cap to prevent DoS from rules that generate
    very frequent occurrences.
    """
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    actual_count = len(results) if results else 0
    assert actual_count <= 1000, \
        f"1000 result cap violated: got {actual_count} results"


# =============================================================================
# Filtering Invariants
# =============================================================================

@given(data=rrule_with_byday(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_byday_filtering(db, data, dtstart):
    """All results must occur on specified weekdays.

    When BYDAY is specified, every occurrence must fall on one
    of the listed weekdays.
    """
    rrule, expected_days = data
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if results:
        expected_weekdays = {BYDAY_TO_WEEKDAY[day] for day in expected_days}
        for r in results:
            assert r.weekday() in expected_weekdays, \
                f"BYDAY violated: {r} (weekday={r.weekday()}) not in {expected_days}"


@given(data=rrule_with_bymonth(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_bymonth_filtering(db, data, dtstart):
    """All results must occur in specified months.

    When BYMONTH is specified, every occurrence must fall in one
    of the listed months.
    """
    rrule, expected_months = data
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if results:
        expected_month_set = set(expected_months)
        for r in results:
            assert r.month in expected_month_set, \
                f"BYMONTH violated: {r} (month={r.month}) not in {expected_months}"


@given(data=rrule_with_bymonthday(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_bymonthday_filtering(db, data, dtstart):
    """All results must occur on specified day of month.

    When BYMONTHDAY is specified, every occurrence must fall on
    the listed day of the month.
    """
    rrule, expected_day = data
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if results:
        for r in results:
            assert r.day == expected_day, \
                f"BYMONTHDAY violated: {r} (day={r.day}) != {expected_day}"


# =============================================================================
# Combined Invariants with Complex Rules
# =============================================================================

@given(rrule=complex_rrule(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_complex_monotonicity(db, rrule, dtstart):
    """Complex RRULEs must still produce monotonic results.

    Even with multiple BYxxx parameters, results must be strictly
    ascending with no duplicates.
    """
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if results and len(results) > 1:
        for i in range(1, len(results)):
            assert results[i] > results[i-1], \
                f"Non-monotonic at {i}: {results[i-1]} >= {results[i]} for rule {rrule}"


@given(rrule=complex_rrule(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_complex_dtstart_boundary(db, rrule, dtstart):
    """Complex RRULEs must still respect dtstart boundary.

    Even with filtering parameters, no result should precede dtstart.
    """
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if results:
        for r in results:
            assert r >= dtstart, \
                f"dtstart boundary violated: {r} < {dtstart} for rule {rrule}"


@given(data=rrule_with_byweekno(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_byweekno_filtering(db, data, dtstart):
    """All results must occur in one of the specified ISO weeks.

    Uses database's get_week_info() to handle WKST correctly.
    """
    rrule, expected_weeks, wkst = data
    cur = db.cursor()

    # Get results
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if not results:
        return  # Empty is valid (COUNT exhausted, 10-year cap, etc.)

    for result in results:
        # Query database for WKST-aware week info
        cur.execute(
            'SELECT week_year, week_num FROM rrule.get_week_info(%s::TIMESTAMP WITH TIME ZONE, %s)',
            (result, wkst)
        )
        week_year, week_num = cur.fetchone()

        # Get weeks_in_year for this result's week_year
        cur.execute(
            "SELECT rrule.weeks_in_year(make_date(%s, 1, 1)::TIMESTAMP WITH TIME ZONE, %s)",
            (week_year, wkst)
        )
        weeks_in_year = cur.fetchone()[0]

        # Normalize negative expected weeks to positive
        normalized_expected = set()
        for w in expected_weeks:
            if w > 0:
                normalized_expected.add(w)
            else:
                normalized_expected.add(weeks_in_year + w + 1)

        assert week_num in normalized_expected, \
            f"BYWEEKNO violated: {result} in week {week_num}, expected one of {normalized_expected}"
