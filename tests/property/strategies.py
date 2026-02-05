"""Hypothesis strategies for generating RRULE test data."""

import calendar
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
    BYMONTH, BYMONTHDAY, and BYWEEKNO parameters. All rules are bounded
    with COUNT for safety. Ensures valid combinations per RFC 5545.
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

    # Optionally add BYWEEKNO (only valid with YEARLY per RFC 5545)
    if freq == 'YEARLY' and draw(st.booleans()):
        weeks = draw(st.lists(
            st.integers(1, 52),
            min_size=1, max_size=2, unique=True
        ))
        parts.append(f'BYWEEKNO={",".join(map(str, weeks))}')

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


# =============================================================================
# Strategies for Advanced Property Tests
# =============================================================================

# Common timezones for testing timezone consistency
COMMON_TIMEZONES = [
    'UTC',
    'America/New_York',
    'America/Los_Angeles',
    'Europe/London',
    'Europe/Berlin',
    'Asia/Tokyo',
    'Australia/Sydney',  # Southern hemisphere DST
]


@st.composite
def simple_rrule_no_byxxx(draw):
    """Generate simple RRULE without any BYxxx modifiers.

    This strategy generates RRULEs with only FREQ, COUNT, and INTERVAL.
    Used for testing interval spacing where BYxxx filters would
    interfere with the expected spacing pattern.

    For MONTHLY/YEARLY, we use conservative counts and dtstart with
    day <= 28 to avoid SKIP edge cases affecting the interval pattern.
    """
    freq = draw(st.sampled_from(FREQUENCIES))
    count = draw(st.integers(2, 20))  # Need at least 2 to test spacing
    interval = draw(st.integers(1, 3))
    return f'FREQ={freq};COUNT={count};INTERVAL={interval}', freq, interval


@st.composite
def dtstart_safe_for_monthly(draw):
    """Generate dtstart with day <= 28 to avoid SKIP edge cases.

    When testing interval spacing for MONTHLY/YEARLY rules, using
    day 29-31 can trigger SKIP=OMIT which skips months, breaking
    the expected interval spacing pattern.
    """
    year = draw(st.integers(2020, 2025))
    month = draw(st.integers(1, 12))
    day = draw(st.integers(1, 28))  # Safe day range
    hour = draw(st.integers(0, 23))
    minute = draw(st.integers(0, 59))
    return datetime(year, month, day, hour, minute, 0)


@st.composite
def rrule_with_tzid(draw):
    """Generate RRULE with embedded TZID parameter.

    Returns both the RRULE string (with TZID) and the timezone name
    separately for testing timezone consistency.
    """
    freq = draw(st.sampled_from(FREQUENCIES))
    count = draw(st.integers(1, 20))
    interval = draw(st.integers(1, 3))
    tzid = draw(st.sampled_from(COMMON_TIMEZONES))

    rrule = f'FREQ={freq};COUNT={count};INTERVAL={interval};TZID={tzid}'
    return rrule, tzid


# Strategy for selecting a timezone from the common list
timezone_strategy = st.sampled_from(COMMON_TIMEZONES)


@st.composite
def rrule_with_byweekno(draw):
    """Generate YEARLY RRULE with BYWEEKNO.

    Returns tuple of (rrule_string, expected_week_numbers, wkst)
    RFC 5545: BYWEEKNO only valid with FREQ=YEARLY
    """
    # Always FREQ=YEARLY (RFC requirement)
    count = draw(st.integers(min_value=1, max_value=10))
    interval = draw(st.integers(min_value=1, max_value=3))

    # Week numbers: 1-52 positive (safe range), -52 to -1 negative
    # Most years have 52 weeks, some have 53
    week_count = draw(st.integers(min_value=1, max_value=3))
    weeks = draw(st.lists(
        st.one_of(
            st.integers(min_value=1, max_value=52),   # Safe positive
            st.integers(min_value=-52, max_value=-1)  # Negative
        ),
        min_size=week_count, max_size=week_count, unique=True
    ))

    # Optional WKST (affects week numbering)
    # NOTE: Only MO matches Python's isocalendar()
    wkst = draw(st.sampled_from([None, 'MO', 'SU']))

    # Optional BYDAY (non-ordinal only - RFC prohibits ordinals with BYWEEKNO)
    add_byday = draw(st.booleans())
    byday = None
    if add_byday:
        byday = draw(st.lists(
            st.sampled_from(WEEKDAYS),
            min_size=1, max_size=3, unique=True
        ))

    # Build RRULE
    parts = ['FREQ=YEARLY', f'COUNT={count}']
    if interval > 1:
        parts.append(f'INTERVAL={interval}')
    parts.append(f'BYWEEKNO={",".join(map(str, weeks))}')
    if wkst:
        parts.append(f'WKST={wkst}')
    if byday:
        parts.append(f'BYDAY={",".join(byday)}')

    # Return WKST for use in invariant test (default MO if None)
    return ';'.join(parts), sorted(weeks), wkst or 'MO'


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


# =============================================================================
# BYSETPOS Strategies
# =============================================================================

@st.composite
def rrule_with_bysetpos(draw):
    """Generate RRULE with BYSETPOS for testing subset invariant.

    Returns tuple of (rrule_with_bysetpos, rrule_without_bysetpos, bysetpos_values,
    freq, until_offset). Paired rules allow comparing BYSETPOS results against
    full candidate set.

    Uses UNTIL for time-bounding to ensure both rules cover exactly the same
    time range. COUNT would apply differently (globally vs after BYSETPOS).

    BYSETPOS operates on candidate sets generated by other BYxxx rules,
    selecting specific positions (positive from start, negative from end).
    """
    from datetime import timedelta

    # MONTHLY/YEARLY produce meaningful candidate sets; WEEKLY is smaller but valid
    freq = draw(st.sampled_from(['MONTHLY', 'YEARLY', 'WEEKLY']))

    # Include BYDAY to create candidate sets with multiple items per period
    days = draw(st.lists(
        st.sampled_from(WEEKDAYS),
        min_size=2, max_size=5, unique=True
    ))

    # Generate BYSETPOS: single or multiple, positive or negative or mixed
    bysetpos_count = draw(st.integers(min_value=1, max_value=3))
    bysetpos = draw(st.lists(
        st.one_of(
            st.integers(min_value=1, max_value=5),   # Positive
            st.integers(min_value=-5, max_value=-1)  # Negative
        ),
        min_size=bysetpos_count, max_size=bysetpos_count, unique=True
    ))

    # Use UNTIL to bound time range (covers complete periods for comparison)
    # Duration varies by frequency to get meaningful test ranges
    if freq == 'YEARLY':
        # 3-5 years for YEARLY
        years = draw(st.integers(min_value=3, max_value=5))
        until_offset = timedelta(days=365 * years)
    elif freq == 'MONTHLY':
        # 6-18 months for MONTHLY
        months = draw(st.integers(min_value=6, max_value=18))
        until_offset = timedelta(days=30 * months)
    else:  # WEEKLY
        # 8-20 weeks for WEEKLY
        weeks = draw(st.integers(min_value=8, max_value=20))
        until_offset = timedelta(weeks=weeks)

    # Build base parts (shared) - UNTIL is relative, will be formatted in test
    base_parts = [f'FREQ={freq}', f'BYDAY={",".join(days)}']

    # Rule WITHOUT BYSETPOS (full candidate set)
    rrule_without = ';'.join(base_parts)

    # Rule WITH BYSETPOS
    rrule_with = ';'.join(base_parts + [f'BYSETPOS={",".join(map(str, bysetpos))}'])

    return rrule_with, rrule_without, sorted(bysetpos), freq, until_offset


@st.composite
def rrule_with_bysetpos_first(draw):
    """Generate RRULE pair: with BYSETPOS=1 and without BYSETPOS.

    Used for testing that BYSETPOS=1 returns the first (minimum)
    candidate from each period's candidate set.
    """
    freq = draw(st.sampled_from(['MONTHLY', 'YEARLY', 'WEEKLY']))
    count = draw(st.integers(min_value=3, max_value=15))

    # Include BYDAY to create candidate sets with multiple items per period
    days = draw(st.lists(
        st.sampled_from(WEEKDAYS),
        min_size=2, max_size=5, unique=True
    ))

    # Build base parts (shared)
    base_parts = [f'FREQ={freq}', f'COUNT={count}', f'BYDAY={",".join(days)}']

    # Rule WITHOUT BYSETPOS (full candidate set)
    rrule_without = ';'.join(base_parts)

    # Rule WITH BYSETPOS=1 (first position only)
    rrule_with = ';'.join(base_parts + ['BYSETPOS=1'])

    return rrule_with, rrule_without, freq


@st.composite
def rrule_with_bysetpos_last(draw):
    """Generate RRULE pair: with BYSETPOS=-1 and without BYSETPOS.

    Used for testing that BYSETPOS=-1 returns the last (maximum)
    candidate from each period's candidate set.
    """
    freq = draw(st.sampled_from(['MONTHLY', 'YEARLY', 'WEEKLY']))
    count = draw(st.integers(min_value=3, max_value=15))

    # Include BYDAY to create candidate sets with multiple items per period
    days = draw(st.lists(
        st.sampled_from(WEEKDAYS),
        min_size=2, max_size=5, unique=True
    ))

    # Build base parts (shared)
    base_parts = [f'FREQ={freq}', f'COUNT={count}', f'BYDAY={",".join(days)}']

    # Rule WITHOUT BYSETPOS (full candidate set)
    rrule_without = ';'.join(base_parts)

    # Rule WITH BYSETPOS=-1 (last position only)
    rrule_with = ';'.join(base_parts + ['BYSETPOS=-1'])

    return rrule_with, rrule_without, freq


# =============================================================================
# SKIP Parameter Strategies (RFC 7529)
# =============================================================================

@st.composite
def dtstart_for_skip(draw):
    """Generate dtstart with day 29-31 to trigger SKIP edge cases.

    These days trigger SKIP behavior in months with fewer days
    (e.g., February, April, June, September, November).
    """
    year = draw(st.integers(min_value=2020, max_value=2025))
    month = draw(st.integers(min_value=1, max_value=12))
    target_day = draw(st.sampled_from([29, 30, 31]))
    max_day = calendar.monthrange(year, month)[1]
    day = min(target_day, max_day)
    hour = draw(st.integers(min_value=0, max_value=23))
    minute = draw(st.integers(min_value=0, max_value=59))
    return datetime(year, month, day, hour, minute, 0)


@st.composite
def dtstart_leap_day(draw):
    """Generate Feb 29 dtstart from leap years for SKIP testing.

    Feb 29 triggers SKIP behavior in non-leap years with YEARLY frequency.
    """
    leap_years = [2020, 2024, 2028]
    year = draw(st.sampled_from(leap_years))
    hour = draw(st.integers(min_value=0, max_value=23))
    minute = draw(st.integers(min_value=0, max_value=59))
    return datetime(year, 2, 29, hour, minute, 0)


@st.composite
def rrule_with_skip(draw):
    """Generate MONTHLY/YEARLY RRULE with SKIP parameter.

    Returns tuple of (rrule_string, skip_mode, freq, bymonthday, interval).
    SKIP parameter (RFC 7529) controls handling of invalid dates:
    - OMIT: Skip invalid dates entirely
    - BACKWARD: Use last valid day of month
    - FORWARD: Use first day of next month
    """
    freq = draw(st.sampled_from(['MONTHLY', 'YEARLY']))
    skip_mode = draw(st.sampled_from(['OMIT', 'BACKWARD', 'FORWARD']))
    interval = draw(st.integers(min_value=1, max_value=4))

    if freq == 'MONTHLY':
        count = draw(st.integers(min_value=6, max_value=24))
    else:
        count = draw(st.integers(min_value=3, max_value=8))

    bymonthday = draw(st.sampled_from([29, 30, 31]))

    parts = [f'FREQ={freq}', f'COUNT={count}', 'RSCALE=GREGORIAN',
             f'SKIP={skip_mode}', f'BYMONTHDAY={bymonthday}']

    if interval > 1:
        parts.append(f'INTERVAL={interval}')

    # Optional BYMONTH for YEARLY (tests SKIP + BYMONTH interaction)
    if freq == 'YEARLY' and draw(st.booleans()):
        months = draw(st.lists(
            st.sampled_from([2, 4, 6, 9, 11]),  # Short months
            min_size=1, max_size=3, unique=True
        ))
        parts.append(f'BYMONTH={",".join(map(str, sorted(months)))}')

    return ';'.join(parts), skip_mode, freq, bymonthday, interval


@st.composite
def rrule_skip_comparison_pair(draw):
    """Generate paired RRULE strings for comparing SKIP=OMIT vs SKIP=BACKWARD.

    Returns (rrule_omit, rrule_backward, freq, bymonthday).
    OMIT skips invalid dates; BACKWARD uses last valid day.
    Every OMIT result should also appear in BACKWARD results.
    """
    freq = draw(st.sampled_from(['MONTHLY', 'YEARLY']))
    interval = draw(st.integers(min_value=1, max_value=3))
    count = draw(st.integers(min_value=10, max_value=30))
    bymonthday = draw(st.sampled_from([29, 30, 31]))

    base_parts = [f'FREQ={freq}', f'COUNT={count}', 'RSCALE=GREGORIAN',
                  f'BYMONTHDAY={bymonthday}']
    if interval > 1:
        base_parts.append(f'INTERVAL={interval}')

    rrule_omit = ';'.join(base_parts + ['SKIP=OMIT'])
    rrule_backward = ';'.join(base_parts + ['SKIP=BACKWARD'])

    return rrule_omit, rrule_backward, freq, bymonthday


# =============================================================================
# Ordinal BYDAY Strategies
# =============================================================================

@st.composite
def rrule_with_byday_ordinal(draw):
    """Generate RRULE with ordinal BYDAY pattern (e.g., 2MO, -1FR).

    Returns tuple of (rrule, freq, ordinal, day, has_bymonth).
    Ordinals only valid with MONTHLY/YEARLY per RFC 5545.
    """
    freq = draw(st.sampled_from(['MONTHLY', 'YEARLY']))
    parts = [f'FREQ={freq}']
    parts.append(f'COUNT={draw(st.integers(1, 30))}')

    # Ordinal range: use ±1 to ±5 (common range, avoids non-existent positions)
    ordinal = draw(st.one_of(
        st.integers(min_value=1, max_value=5),
        st.integers(min_value=-5, max_value=-1)
    ))

    day = draw(st.sampled_from(WEEKDAYS))
    ordinal_str = f'{ordinal:+d}' if ordinal < 0 else str(ordinal)
    parts.append(f'BYDAY={ordinal_str}{day}')

    # Optional BYMONTH for YEARLY (changes scope from year to month)
    has_bymonth = False
    if freq == 'YEARLY' and draw(st.booleans()):
        months = draw(st.lists(st.integers(1, 12), min_size=1, max_size=3, unique=True))
        parts.append(f'BYMONTH={",".join(str(m) for m in sorted(months))}')
        has_bymonth = True

    return ';'.join(parts), freq, ordinal, day, has_bymonth


@st.composite
def rrule_ordinal_comparison_pair(draw):
    """Generate paired RRULEs: with ordinal BYDAY and without.

    Returns (rrule_with_ordinal, rrule_without_ordinal, freq, ordinal, day, has_bymonth, until_offset).
    Used to verify ordinal results are subset of non-ordinal results.
    """
    from datetime import timedelta

    freq = draw(st.sampled_from(['MONTHLY', 'YEARLY']))
    ordinal = draw(st.one_of(
        st.integers(min_value=1, max_value=5),
        st.integers(min_value=-5, max_value=-1)
    ))
    day = draw(st.sampled_from(WEEKDAYS))

    ordinal_str = f'{ordinal:+d}' if ordinal < 0 else str(ordinal)

    # Time range for fair comparison
    if freq == 'YEARLY':
        until_offset = timedelta(days=365 * draw(st.integers(3, 5)))
    else:
        until_offset = timedelta(days=30 * draw(st.integers(6, 18)))

    base_parts = [f'FREQ={freq}']

    has_bymonth = False
    if freq == 'YEARLY' and draw(st.booleans()):
        months = draw(st.lists(st.integers(1, 12), min_size=1, max_size=3, unique=True))
        base_parts.append(f'BYMONTH={",".join(str(m) for m in sorted(months))}')
        has_bymonth = True

    rrule_with_ordinal = ';'.join(base_parts + [f'BYDAY={ordinal_str}{day}'])
    rrule_without_ordinal = ';'.join(base_parts + [f'BYDAY={day}'])

    return rrule_with_ordinal, rrule_without_ordinal, freq, ordinal, day, has_bymonth, until_offset
