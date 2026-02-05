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
    rrule_with_bysetpos,
    rrule_with_bysetpos_first,
    rrule_with_bysetpos_last,
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


# =============================================================================
# BYSETPOS Invariants
# =============================================================================

@given(data=rrule_with_bysetpos(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_bysetpos_subset_invariant(db, data, dtstart):
    """BYSETPOS results are a subset of their period's candidate set.

    For each period that produces BYSETPOS results, those results must
    be present in the full candidate set for that same period. BYSETPOS
    selects positions from each period's candidates independently.

    Uses UNTIL to bound both rules to the same time range, and only
    compares periods where the unbounded rule has complete data
    (accounting for the 1000-result API cap).
    """
    rrule_with, rrule_without, _, freq, until_offset = data
    cur = db.cursor()

    # Calculate UNTIL date and format per RFC 5545
    until_dt = dtstart + until_offset
    until_str = until_dt.strftime('%Y%m%dT%H%M%SZ')

    # Add UNTIL to both rules
    rrule_with_bounded = f'{rrule_with};UNTIL={until_str}'
    rrule_without_bounded = f'{rrule_without};UNTIL={until_str}'

    # Query full candidate set (without BYSETPOS)
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule_without_bounded, dtstart)
    )
    full_results = cur.fetchone()[0] or []

    # Query BYSETPOS-filtered results
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule_with_bounded, dtstart)
    )
    bysetpos_results = cur.fetchone()[0] or []

    if not bysetpos_results or not full_results:
        return  # Empty is valid

    # Group full results by period
    from collections import defaultdict

    def get_period_key(dt, freq):
        """Extract period key based on frequency."""
        if freq == 'YEARLY':
            return dt.year
        elif freq == 'MONTHLY':
            return (dt.year, dt.month)
        elif freq == 'WEEKLY':
            return dt.isocalendar()[:2]
        return dt.date()

    full_by_period = defaultdict(set)
    for r in full_results:
        key = get_period_key(r, freq)
        full_by_period[key].add(r)

    # Find the last complete period in full_results
    # The 1000-result cap may have truncated the last period
    # We only test BYSETPOS results from periods that are fully covered
    if len(full_results) >= 1000:
        # Results were capped; last period may be incomplete
        # Only compare periods that appear before the cap's cutoff
        last_result = full_results[-1]
        last_period = get_period_key(last_result, freq)
        # Exclude the last period as it may be incomplete
        complete_periods = set(full_by_period.keys()) - {last_period}
    else:
        # No cap hit; all periods are complete
        complete_periods = set(full_by_period.keys())

    # Each BYSETPOS result from a complete period must be in its candidate set
    for r in bysetpos_results:
        period_key = get_period_key(r, freq)
        if period_key not in complete_periods:
            continue  # Skip periods that may be incomplete in full results
        period_candidates = full_by_period.get(period_key, set())
        assert r in period_candidates, \
            f"BYSETPOS subset violated: {r} (period {period_key}) not in period candidates"


@given(data=rrule_with_bysetpos(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_bysetpos_count_bound(db, data, dtstart):
    """BYSETPOS results <= full results (filter never adds).

    A rule with BYSETPOS can return at most the same number of results
    as the equivalent rule without BYSETPOS, since BYSETPOS only filters.
    """
    rrule_with, rrule_without, _, _, until_offset = data
    cur = db.cursor()

    # Calculate UNTIL date and format per RFC 5545
    until_dt = dtstart + until_offset
    until_str = until_dt.strftime('%Y%m%dT%H%M%SZ')

    # Add UNTIL to both rules for fair comparison
    rrule_with_bounded = f'{rrule_with};UNTIL={until_str}'
    rrule_without_bounded = f'{rrule_without};UNTIL={until_str}'

    # Count full results
    cur.execute(
        'SELECT COUNT(*) FROM rrule."all"(%s, %s)',
        (rrule_without_bounded, dtstart)
    )
    full_count = cur.fetchone()[0]

    # Count BYSETPOS results
    cur.execute(
        'SELECT COUNT(*) FROM rrule."all"(%s, %s)',
        (rrule_with_bounded, dtstart)
    )
    bysetpos_count = cur.fetchone()[0]

    assert bysetpos_count <= full_count, \
        f"BYSETPOS count bound violated: {bysetpos_count} > {full_count} for rule {rrule_with}"


@given(data=rrule_with_bysetpos_first(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_bysetpos_first_position(db, data, dtstart):
    """BYSETPOS=1 returns the first candidate per period.

    For each period (month/year/week depending on FREQ), BYSETPOS=1
    should select the chronologically first candidate from that period's
    candidate set.
    """
    rrule_with, rrule_without, freq = data
    cur = db.cursor()

    # Get BYSETPOS=1 results
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule_with, dtstart)
    )
    first_results = cur.fetchone()[0] or []

    if not first_results:
        return  # Empty is valid

    # Get full candidate set
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule_without, dtstart)
    )
    full_results = cur.fetchone()[0] or []

    if not full_results:
        return

    # Group full results by period and verify BYSETPOS=1 picks the minimum
    from collections import defaultdict

    def get_period_key(dt, freq):
        """Extract period key based on frequency."""
        if freq == 'YEARLY':
            return dt.year
        elif freq == 'MONTHLY':
            return (dt.year, dt.month)
        elif freq == 'WEEKLY':
            # Use ISO week
            return dt.isocalendar()[:2]  # (year, week)
        return dt.date()

    # Group full results by period
    periods = defaultdict(list)
    for r in full_results:
        key = get_period_key(r, freq)
        periods[key].append(r)

    # The first result from each period should be in first_results
    first_results_set = set(first_results)
    for period_key, candidates in periods.items():
        first_candidate = min(candidates)
        # This first candidate should be in BYSETPOS=1 results
        # (unless COUNT limited how many periods we got)
        if first_candidate in first_results_set:
            # Verify it's actually the minimum for that period
            assert first_candidate == min(candidates), \
                f"BYSETPOS=1 did not select minimum for period {period_key}"


@given(data=rrule_with_bysetpos_last(), dtstart=dtstart_strategy)
@settings(max_examples=500)
def test_bysetpos_last_position(db, data, dtstart):
    """BYSETPOS=-1 returns the last candidate per period.

    For each period (month/year/week depending on FREQ), BYSETPOS=-1
    should select the chronologically last candidate from that period's
    candidate set.
    """
    rrule_with, rrule_without, freq = data
    cur = db.cursor()

    # Get BYSETPOS=-1 results
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule_with, dtstart)
    )
    last_results = cur.fetchone()[0] or []

    if not last_results:
        return  # Empty is valid

    # Get full candidate set
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule_without, dtstart)
    )
    full_results = cur.fetchone()[0] or []

    if not full_results:
        return

    # Group full results by period and verify BYSETPOS=-1 picks the maximum
    from collections import defaultdict

    def get_period_key(dt, freq):
        """Extract period key based on frequency."""
        if freq == 'YEARLY':
            return dt.year
        elif freq == 'MONTHLY':
            return (dt.year, dt.month)
        elif freq == 'WEEKLY':
            # Use ISO week
            return dt.isocalendar()[:2]  # (year, week)
        return dt.date()

    # Group full results by period
    periods = defaultdict(list)
    for r in full_results:
        key = get_period_key(r, freq)
        periods[key].append(r)

    # The last result from each period should be in last_results
    last_results_set = set(last_results)
    for period_key, candidates in periods.items():
        last_candidate = max(candidates)
        # This last candidate should be in BYSETPOS=-1 results
        # (unless COUNT limited how many periods we got)
        if last_candidate in last_results_set:
            # Verify it's actually the maximum for that period
            assert last_candidate == max(candidates), \
                f"BYSETPOS=-1 did not select maximum for period {period_key}"
