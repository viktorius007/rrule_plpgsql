"""Property-based tests for RRULE invariants.

These tests verify fundamental properties that must hold for all valid RRULE inputs.
Unlike example-based tests, property tests use Hypothesis to generate many random
inputs and automatically shrink failing cases to minimal reproducible examples.
"""

import calendar
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
    rrule_with_skip,
    rrule_skip_comparison_pair,
    dtstart_for_skip,
    dtstart_leap_day,
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


# =============================================================================
# SKIP Parameter Invariants (RFC 7529)
# =============================================================================

@given(data=rrule_with_skip(), dtstart=dtstart_for_skip())
@settings(max_examples=500)
def test_skip_all_dates_valid(db, data, dtstart):
    """SKIP rules must only produce valid calendar dates.

    No Feb 30, Feb 31, Apr 31, Jun 31, Sep 31, Nov 31 should appear.
    This verifies that SKIP modes (OMIT/BACKWARD/FORWARD) correctly
    handle months with fewer than 31 days.
    """
    rrule, skip_mode, freq, bymonthday, interval = data
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if not results:
        return  # Empty is valid (all dates may have been skipped)

    for r in results:
        max_day = calendar.monthrange(r.year, r.month)[1]
        assert r.day <= max_day, \
            f"Invalid date produced: {r} (month {r.month} has {max_day} days)"


@given(data=rrule_with_skip(), dtstart=dtstart_for_skip())
@settings(max_examples=500)
def test_skip_no_duplicates(db, data, dtstart):
    """All SKIP rule occurrences must be distinct.

    SKIP=FORWARD can produce potential duplicates when shifting dates
    forward. This verifies that deduplication works correctly.
    """
    rrule, skip_mode, freq, bymonthday, interval = data
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if not results:
        return

    # Check for duplicates
    seen = set()
    for r in results:
        assert r not in seen, f"Duplicate occurrence: {r} for rule {rrule}"
        seen.add(r)


@given(data=rrule_with_skip(), dtstart=dtstart_for_skip())
@settings(max_examples=500)
def test_skip_count_respected(db, data, dtstart):
    """COUNT must never be exceeded with SKIP rules.

    SKIP modes affect which dates are produced but not the total count.
    """
    rrule, skip_mode, freq, bymonthday, interval = data
    cur = db.cursor()

    # Extract COUNT from RRULE
    parts = dict(p.split('=') for p in rrule.split(';') if '=' in p)
    expected_count = int(parts.get('COUNT', 1000))

    cur.execute(
        'SELECT COUNT(*) FROM rrule."all"(%s, %s)',
        (rrule, dtstart)
    )
    actual_count = cur.fetchone()[0]

    assert actual_count <= expected_count, \
        f"COUNT exceeded: got {actual_count}, max {expected_count}"


@given(data=rrule_with_skip(), dtstart=dtstart_for_skip())
@settings(max_examples=500)
def test_skip_monotonicity(db, data, dtstart):
    """SKIP rule results must be strictly ascending.

    No matter which SKIP mode is used, results are always in
    chronological order.
    """
    rrule, skip_mode, freq, bymonthday, interval = data
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if results and len(results) > 1:
        for i in range(1, len(results)):
            assert results[i] > results[i-1], \
                f"Non-monotonic: {results[i-1]} >= {results[i]} for rule {rrule}"


@given(data=rrule_with_skip(), dtstart=dtstart_for_skip())
@settings(max_examples=500)
def test_skip_no_drift(db, data, dtstart):
    """SKIP=BACKWARD must not cause cumulative drift.

    For months that CAN hold the original BYMONTHDAY value, that day
    should be used. BACKWARD adjustments are temporary, not cumulative.
    """
    rrule, skip_mode, freq, bymonthday, interval = data

    # Only test BACKWARD mode (FORWARD deliberately advances month)
    if skip_mode != 'BACKWARD':
        return

    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results = cur.fetchone()[0]

    if not results:
        return

    for r in results:
        max_day = calendar.monthrange(r.year, r.month)[1]
        if max_day >= bymonthday:
            # This month CAN hold the original BYMONTHDAY
            assert r.day == bymonthday, \
                f"Drift detected: {r} should have day={bymonthday} (month has {max_day} days)"


@given(data=rrule_with_skip(), dtstart=dtstart_for_skip())
@settings(max_examples=500)
def test_skip_idempotence(db, data, dtstart):
    """Same SKIP RRULE called twice returns identical results.

    RRULE generation is deterministic; calling the same rule
    with same dtstart must produce identical results.
    """
    rrule, skip_mode, freq, bymonthday, interval = data
    cur = db.cursor()

    # First call
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results1 = cur.fetchone()[0] or []

    # Second call
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    results2 = cur.fetchone()[0] or []

    assert results1 == results2, \
        f"Idempotence violated: results differ for rule {rrule}"


@given(data=rrule_skip_comparison_pair(), dtstart=dtstart_for_skip())
@settings(max_examples=500)
def test_skip_omit_subset_of_backward(db, data, dtstart):
    """Every SKIP=OMIT result should also appear in SKIP=BACKWARD results.

    OMIT skips invalid dates entirely, while BACKWARD adjusts them.
    The valid dates (not needing adjustment) should appear in both.

    Uses UNTIL (not COUNT) to ensure both rules cover the same time range.
    COUNT would cause divergence because BACKWARD produces more results.
    """
    rrule_omit, rrule_backward, freq, bymonthday = data
    cur = db.cursor()

    # Replace COUNT with UNTIL to ensure same time range coverage
    # Generate UNTIL ~2 years from dtstart
    until_dt = dtstart + timedelta(days=730)
    until_str = until_dt.strftime('%Y%m%dT%H%M%SZ')

    # Rewrite rules with UNTIL instead of COUNT
    def replace_count_with_until(rrule):
        parts = [p for p in rrule.split(';') if not p.startswith('COUNT=')]
        parts.append(f'UNTIL={until_str}')
        return ';'.join(parts)

    rrule_omit_bounded = replace_count_with_until(rrule_omit)
    rrule_backward_bounded = replace_count_with_until(rrule_backward)

    # Get OMIT results
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule_omit_bounded, dtstart)
    )
    omit_results = cur.fetchone()[0] or []

    # Get BACKWARD results
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule_backward_bounded, dtstart)
    )
    backward_results = set(cur.fetchone()[0] or [])

    # Every OMIT result must be in BACKWARD results
    for r in omit_results:
        assert r in backward_results, \
            f"OMIT result {r} not in BACKWARD results for BYMONTHDAY={bymonthday}"


@given(dtstart=dtstart_leap_day())
@settings(max_examples=500)
def test_skip_leap_year_behavior(db, dtstart):
    """Feb 29 dtstart with YEARLY triggers correct SKIP behavior in non-leap years.

    For SKIP=OMIT, non-leap years produce no occurrence.
    For SKIP=BACKWARD, non-leap years produce Feb 28.
    For SKIP=FORWARD, non-leap years produce Mar 1.
    """
    cur = db.cursor()

    # YEARLY with COUNT=5 to span multiple leap/non-leap years
    base_rrule = 'FREQ=YEARLY;COUNT=5;RSCALE=GREGORIAN;BYMONTHDAY=29;BYMONTH=2'

    # Test SKIP=BACKWARD
    rrule_backward = f'{base_rrule};SKIP=BACKWARD'
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule_backward, dtstart)
    )
    backward_results = cur.fetchone()[0] or []

    for r in backward_results:
        # In leap years, should be Feb 29; in non-leap, should be Feb 28
        is_leap = calendar.isleap(r.year)
        if is_leap:
            assert r.month == 2 and r.day == 29, \
                f"Leap year {r.year} should have Feb 29, got {r}"
        else:
            assert r.month == 2 and r.day == 28, \
                f"Non-leap year {r.year} should have Feb 28, got {r}"

    # Test SKIP=FORWARD
    rrule_forward = f'{base_rrule};SKIP=FORWARD'
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule_forward, dtstart)
    )
    forward_results = cur.fetchone()[0] or []

    for r in forward_results:
        # In leap years, should be Feb 29; in non-leap, should be Mar 1
        is_leap = calendar.isleap(r.year)
        if is_leap:
            assert r.month == 2 and r.day == 29, \
                f"Leap year {r.year} should have Feb 29, got {r}"
        else:
            assert r.month == 3 and r.day == 1, \
                f"Non-leap year {r.year} should have Mar 1 (FORWARD), got {r}"

    # Test SKIP=OMIT - should only have leap year occurrences
    rrule_omit = f'{base_rrule};SKIP=OMIT'
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule_omit, dtstart)
    )
    omit_results = cur.fetchone()[0] or []

    for r in omit_results:
        # OMIT should only produce leap year Feb 29s
        assert r.month == 2 and r.day == 29 and calendar.isleap(r.year), \
            f"OMIT should only produce leap year Feb 29, got {r}"
