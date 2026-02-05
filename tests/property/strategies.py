"""Hypothesis strategies for generating RRULE test data."""

from hypothesis import strategies as st
from datetime import datetime

# Standard frequencies (sub-day disabled by default for security)
FREQUENCIES = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY']

# Weekday abbreviations (RFC 5545)
WEEKDAYS = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU']


@st.composite
def simple_rrule(draw):
    """Generate simple RRULE with FREQ + COUNT + INTERVAL only.

    This is the most basic strategy that generates valid RRULEs
    without any BYxxx modifiers. Useful for testing core invariants.
    """
    freq = draw(st.sampled_from(FREQUENCIES))
    count = draw(st.integers(1, 50))
    interval = draw(st.integers(1, 5))
    return f'FREQ={freq};COUNT={count};INTERVAL={interval}'


@st.composite
def complex_rrule(draw):
    """Generate RRULE with BYxxx parameters.

    This strategy generates more complex RRULEs that include BYDAY,
    BYMONTH, and BYMONTHDAY parameters. All rules are bounded with
    COUNT for safety. Ensures valid combinations per RFC 5545.
    """
    freq = draw(st.sampled_from(FREQUENCIES))
    parts = [f'FREQ={freq}']

    # Always bound with COUNT for safety
    parts.append(f'COUNT={draw(st.integers(1, 100))}')

    # Optionally add INTERVAL
    if draw(st.booleans()):
        parts.append(f'INTERVAL={draw(st.integers(1, 5))}')

    # Optionally add BYDAY (weekday filtering)
    if draw(st.booleans()):
        days = draw(st.lists(
            st.sampled_from(WEEKDAYS),
            min_size=1,
            max_size=3,
            unique=True
        ))
        parts.append(f'BYDAY={",".join(days)}')

    # Optionally add BYMONTH (month filtering)
    if draw(st.booleans()):
        months = draw(st.lists(
            st.integers(1, 12),
            min_size=1,
            max_size=3,
            unique=True
        ))
        parts.append(f'BYMONTH={",".join(str(m) for m in sorted(months))}')

    # Optionally add BYMONTHDAY (day of month filtering)
    # BYMONTHDAY is invalid with WEEKLY per RFC 5545
    if freq != 'WEEKLY' and draw(st.booleans()):
        # Use 1-28 to avoid month-end edge cases
        parts.append(f'BYMONTHDAY={draw(st.integers(1, 28))}')

    return ';'.join(parts)


@st.composite
def rrule_with_byday(draw):
    """Generate RRULE that specifically includes BYDAY.

    Used for testing BYDAY filtering invariant.
    """
    freq = draw(st.sampled_from(FREQUENCIES))
    parts = [f'FREQ={freq}']

    # Always bound with COUNT
    parts.append(f'COUNT={draw(st.integers(1, 50))}')

    # Always include BYDAY
    days = draw(st.lists(
        st.sampled_from(WEEKDAYS),
        min_size=1,
        max_size=3,
        unique=True
    ))
    parts.append(f'BYDAY={",".join(days)}')

    return ';'.join(parts), days


@st.composite
def rrule_with_bymonth(draw):
    """Generate RRULE that specifically includes BYMONTH.

    Used for testing BYMONTH filtering invariant.
    """
    freq = draw(st.sampled_from(FREQUENCIES))
    parts = [f'FREQ={freq}']

    # Always bound with COUNT
    parts.append(f'COUNT={draw(st.integers(1, 50))}')

    # Always include BYMONTH
    months = draw(st.lists(
        st.integers(1, 12),
        min_size=1,
        max_size=3,
        unique=True
    ))
    parts.append(f'BYMONTH={",".join(str(m) for m in sorted(months))}')

    return ';'.join(parts), months


@st.composite
def rrule_with_bymonthday(draw):
    """Generate RRULE that specifically includes BYMONTHDAY.

    Used for testing BYMONTHDAY filtering invariant.
    BYMONTHDAY is invalid with WEEKLY, so we exclude that frequency.
    """
    # Exclude WEEKLY - BYMONTHDAY is invalid with it per RFC 5545
    freq = draw(st.sampled_from(['DAILY', 'MONTHLY', 'YEARLY']))
    parts = [f'FREQ={freq}']

    # Always bound with COUNT
    parts.append(f'COUNT={draw(st.integers(1, 50))}')

    # Always include BYMONTHDAY (1-28 to avoid month-end issues)
    monthday = draw(st.integers(1, 28))
    parts.append(f'BYMONTHDAY={monthday}')

    return ';'.join(parts), monthday


@st.composite
def rrule_with_count(draw):
    """Generate RRULE with specific COUNT for count invariant testing.

    Returns the RRULE string and the expected count.
    """
    freq = draw(st.sampled_from(FREQUENCIES))
    count = draw(st.integers(1, 50))
    interval = draw(st.integers(1, 3))

    rrule = f'FREQ={freq};COUNT={count};INTERVAL={interval}'
    return rrule, count


@st.composite
def rrule_with_until(draw):
    """Generate RRULE with UNTIL for until invariant testing.

    Returns the RRULE string, dtstart, and until date.
    """
    from datetime import timedelta

    freq = draw(st.sampled_from(FREQUENCIES))

    # Generate dtstart within test range
    dtstart = draw(st.datetimes(
        min_value=datetime(2020, 1, 1),
        max_value=datetime(2025, 1, 1)
    ))

    # UNTIL is 30-365 days after dtstart
    days_offset = draw(st.integers(30, 365))
    until = dtstart + timedelta(days=days_offset)

    # Format UNTIL per RFC 5545 (YYYYMMDDTHHMMSSZ)
    until_str = until.strftime('%Y%m%dT%H%M%SZ')

    rrule = f'FREQ={freq};UNTIL={until_str}'
    return rrule, dtstart, until


# Strategy for generating dtstart values within a reasonable range
dtstart_strategy = st.datetimes(
    min_value=datetime(2020, 1, 1),
    max_value=datetime(2028, 1, 1)
)


# Strategy for dtstart without microseconds (for differential testing)
# python-dateutil truncates microseconds, so we need clean datetimes
dtstart_no_microseconds = st.datetimes(
    min_value=datetime(2020, 1, 1),
    max_value=datetime(2025, 1, 1)  # Narrower range to stay within 10-year cap
).map(lambda dt: dt.replace(microsecond=0))


@st.composite
def simple_rrule_for_differential(draw):
    """Generate simple RRULE suitable for differential testing.

    Constrains COUNT and INTERVAL to ensure results stay within the
    PL/pgSQL 10-year window cap. This avoids false failures due to
    the intentional API limit difference.

    The 10-year window from dtstart limits total occurrences.
    We use conservative limits to ensure all COUNT occurrences fit.
    With MONTHLY + SKIP=OMIT (default), months without day 31 are
    skipped, which can cause fewer calendar months to produce
    occurrences, so we use conservative counts.

    Max safe configurations (with generous margin):
    - YEARLY: 9 occurrences * 1 interval = 9 years
    - MONTHLY: 24 occurrences * 4 interval = ~8 years (avoiding month-end issues)
    - WEEKLY: 50 occurrences * 8 interval = ~8 years
    - DAILY: 50 occurrences * 50 interval = ~7 years
    """
    freq = draw(st.sampled_from(FREQUENCIES))

    # Constrain COUNT based on frequency to stay safely within 10-year window
    if freq == 'YEARLY':
        max_count = 9
        max_interval = 1
    elif freq == 'MONTHLY':
        # Conservative: 24 months * 4 interval = 8 years max
        max_count = 24
        max_interval = 4
    elif freq == 'WEEKLY':
        max_count = 50
        max_interval = 8
    else:  # DAILY
        max_count = 50
        max_interval = 50

    count = draw(st.integers(1, max_count))
    interval = draw(st.integers(1, max_interval))
    return f'FREQ={freq};COUNT={count};INTERVAL={interval}'
