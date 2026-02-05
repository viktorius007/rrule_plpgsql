"""Differential tests comparing PL/pgSQL implementation against python-dateutil.

These tests verify that the PL/pgSQL RRULE implementation produces identical results
to the python-dateutil reference implementation for all generated test cases.

Any failures indicate either:
1. A bug in the PL/pgSQL implementation (fix the implementation)
2. A known intentional difference (document in known_differences.py)
3. An edge case in python-dateutil (handle gracefully with assume())

Reference: https://dateutil.readthedocs.io/en/stable/rrule.html

Implementation Notes:
- Uses simple_rrule_for_differential strategy to avoid 10-year window cap differences
- Uses dtstart_no_microseconds because dateutil truncates microseconds
- Compares rrule."all"() results (which include dtstart) with dateutil results
"""

from datetime import datetime

from dateutil.rrule import rrulestr
from hypothesis import given, settings, assume

from .known_differences import is_known_difference, get_difference_reason
from .strategies import simple_rrule_for_differential, dtstart_no_microseconds


@given(rrule=simple_rrule_for_differential(), dtstart=dtstart_no_microseconds)
@settings(max_examples=500)
def test_matches_dateutil(db, rrule, dtstart):
    """Results should match python-dateutil reference implementation.

    This test generates random RRULE strings and verifies that the PL/pgSQL
    implementation produces the exact same occurrences as python-dateutil.

    The comparison:
    1. Strips timezone info from dateutil results (dateutil may return tz-aware)
    2. Applies the same 1000-result cap that the PL/pgSQL implementation uses
    3. Compares count and each individual occurrence

    A failure here means the implementations diverge, which needs investigation.
    """
    # Skip known intentional differences
    if is_known_difference(rrule):
        reason = get_difference_reason(rrule)
        assume(False)  # Skip with Hypothesis tracking

    # Get PL/pgSQL results
    cur = db.cursor()
    cur.execute(
        'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
        (rrule, dtstart)
    )
    pg_results = cur.fetchone()[0] or []

    # Get python-dateutil results
    try:
        # dateutil expects dtstart as a datetime, not a string
        # The rrulestr function parses the RRULE and applies it to the dtstart
        rule = rrulestr(f'RRULE:{rrule}', dtstart=dtstart)
        # Match the 1000-result cap that PL/pgSQL uses
        du_results = list(rule[:1000])
    except ValueError as e:
        # dateutil rejected this RRULE - skip if it's invalid input
        # (Hypothesis will track this as an assumption failure)
        assume(False)

    # Compare result counts
    assert len(pg_results) == len(du_results), (
        f"Count mismatch for RRULE '{rrule}' with dtstart={dtstart}: "
        f"PL/pgSQL returned {len(pg_results)}, dateutil returned {len(du_results)}"
    )

    # Compare each occurrence
    for i, (pg, du) in enumerate(zip(pg_results, du_results)):
        # dateutil may return timezone-aware datetime, strip for comparison
        du_naive = du.replace(tzinfo=None) if du.tzinfo else du
        assert pg == du_naive, (
            f"Mismatch at index {i} for RRULE '{rrule}' with dtstart={dtstart}: "
            f"PL/pgSQL={pg} vs dateutil={du_naive}"
        )


@given(rrule=simple_rrule_for_differential(), dtstart=dtstart_no_microseconds)
@settings(max_examples=100)
def test_first_occurrence_matches(db, rrule, dtstart):
    """First occurrence should match between implementations.

    A simpler test that just verifies the first occurrence matches.
    This catches basic parsing or interval calculation errors.

    Note: Uses array_agg with LIMIT 1 instead of rrule."next"() because
    next() returns the occurrence AFTER dtstart, while dateutil includes
    dtstart as the first occurrence.
    """
    if is_known_difference(rrule):
        assume(False)

    # Get PL/pgSQL first result via rrule."all"() with limit
    cur = db.cursor()
    cur.execute(
        'SELECT (SELECT r FROM rrule."all"(%s, %s) r LIMIT 1)',
        (rrule, dtstart)
    )
    pg_first = cur.fetchone()[0]

    # Get dateutil first result
    try:
        rule = rrulestr(f'RRULE:{rrule}', dtstart=dtstart)
        du_first = rule[0] if rule else None
    except (ValueError, IndexError):
        assume(False)

    if du_first:
        du_first_naive = du_first.replace(tzinfo=None) if du_first.tzinfo else du_first
        assert pg_first == du_first_naive, (
            f"First occurrence mismatch for RRULE '{rrule}' with dtstart={dtstart}: "
            f"PL/pgSQL={pg_first} vs dateutil={du_first_naive}"
        )


@given(rrule=simple_rrule_for_differential(), dtstart=dtstart_no_microseconds)
@settings(max_examples=100)
def test_count_matches(db, rrule, dtstart):
    """Total count should match between implementations.

    Verifies that both implementations agree on the total number of occurrences.
    This is a cheaper check than comparing all values.
    """
    if is_known_difference(rrule):
        assume(False)

    # Get PL/pgSQL count
    cur = db.cursor()
    cur.execute(
        'SELECT rrule."count"(%s, %s)',
        (rrule, dtstart)
    )
    pg_count = cur.fetchone()[0] or 0

    # Get dateutil count
    try:
        rule = rrulestr(f'RRULE:{rrule}', dtstart=dtstart)
        # Use count() if available, otherwise len(list())
        du_count = rule.count()
    except (ValueError, AttributeError):
        try:
            rule = rrulestr(f'RRULE:{rrule}', dtstart=dtstart)
            du_count = len(list(rule[:1000]))  # Cap at 1000 like PL/pgSQL
        except ValueError:
            assume(False)

    assert pg_count == du_count, (
        f"Count mismatch for RRULE '{rrule}' with dtstart={dtstart}: "
        f"PL/pgSQL={pg_count} vs dateutil={du_count}"
    )
