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

    The 10-year window from dtstart limits total occurrences. We use
    conservative limits to ensure all COUNT occurrences fit comfortably.

    IMPORTANT: dtstart can land on day 29/30/31 which causes month-skipping
    for MONTHLY frequency (e.g., dtstart=June 30 with INTERVAL=4 skips Feb).
    This effectively doubles the interval, requiring even more conservative
    limits. Also, the 10-year cap uses strict `< maxdate`, so occurrences
    exactly at the boundary are excluded.

    Max safe configurations (very conservative for edge cases):
    - YEARLY: 8 occurrences * 1 interval = 8 years (not 9, to avoid boundary)
    - MONTHLY: 18 occurrences * 3 interval = 4.5 years nominal, but with
               month-skipping can span up to 9 years safely
    - WEEKLY: 40 occurrences * 8 interval = ~6 years
    - DAILY: 40 occurrences * 40 interval = ~4.4 years
    """
    freq = draw(st.sampled_from(FREQUENCIES))

    # Constrain COUNT based on frequency to stay safely within 10-year window
    # Extra conservative to handle month-skipping and boundary conditions
    if freq == 'YEARLY':
        max_count = 8  # 8 years, not 9, to avoid 10-year boundary
        max_interval = 1
    elif freq == 'MONTHLY':
        # Very conservative: with dtstart on day 29-31 and INTERVAL=4,
        # months like Feb are skipped, effectively doubling the interval.
        # 18 * 3 = 54 months = 4.5 years nominal, but with skipping ~9 years
        max_count = 18
        max_interval = 3
    elif freq == 'WEEKLY':
        max_count = 40
        max_interval = 8
    else:  # DAILY
        max_count = 40
        max_interval = 40

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


# =============================================================================
# Edge Case Strategies for Differential Testing
# =============================================================================

@st.composite
def edge_case_rrule_for_differential(draw):
    """Generate RRULE with BYMONTHDAY edge cases for differential testing.

    Uses BYMONTHDAY=28-31 to test month-end behavior.
    Uses SKIP=OMIT (default) to match python-dateutil's behavior.
    Keeps COUNT conservative to stay within API caps and 10-year window.

    Note: python-dateutil does NOT support RFC 7529 SKIP parameter.
    Its implicit behavior for invalid dates (e.g., Feb 31) is OMIT.
    Since SKIP=OMIT is PL/pgSQL's default, these rules are compatible.

    IMPORTANT: Avoid FREQ=DAILY + BYMONTHDAY>=29 which has known iteration
    limit issues (see ISSUE-014). Use MONTHLY/YEARLY for sparse BYMONTHDAY.
    """
    # Exclude DAILY for BYMONTHDAY>=29 (iteration limit issue)
    # Exclude WEEKLY - BYMONTHDAY is invalid with WEEKLY per RFC 5545
    freq = draw(st.sampled_from(['MONTHLY', 'YEARLY']))

    # BYMONTHDAY values that trigger edge cases
    # 28: exists in all months
    # 29: missing in Feb (non-leap)
    # 30: missing in Feb
    # 31: missing in Feb, Apr, Jun, Sep, Nov
    # -1: last day (always valid)
    # -2: second to last (always valid)
    bymonthday = draw(st.sampled_from([28, 29, 30, 31, -1, -2]))

    # Conservative counts to stay within 10-year window (dtstart in 2020-2025)
    # With BYMONTH reducing occurrences, be extra conservative
    if freq == 'MONTHLY':
        # MONTHLY without BYMONTH: 12/year
        # MONTHLY with BYMONTH=1: 1/year (need 10 years max = 10 occurrences)
        # With INTERVAL, even fewer. Be conservative.
        count = draw(st.integers(1, 8))  # Safe for worst-case BYMONTH
        max_interval = 2
    else:  # YEARLY
        # YEARLY+BYMONTHDAY: 1/year max, so COUNT<=9 for 10-year window
        count = draw(st.integers(1, 8))
        max_interval = 1

    interval = draw(st.integers(1, max_interval))

    parts = [f'FREQ={freq}', f'BYMONTHDAY={bymonthday}', f'COUNT={count}']
    if interval > 1:
        parts.append(f'INTERVAL={interval}')

    # Optionally add BYMONTH to test intersection (reduce chance for 10-year hit)
    # Only add BYMONTH occasionally and with low COUNT
    # Avoid BYMONTH=2 with BYMONTHDAY=29 as Feb 29 only occurs in leap years
    # (every 4 years), which can easily exceed 10-year window
    if draw(st.booleans()) and count <= 5:
        # Avoid sparse leap year cases
        if bymonthday == 29:
            # BYMONTHDAY=29 + BYMONTH=2 = leap years only (4-year gap)
            # With COUNT=3, that's 2024, 2028, 2032 = 12 years
            # Exclude February for BYMONTHDAY=29
            months = draw(st.lists(st.sampled_from([1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]),
                                   min_size=1, max_size=3, unique=True))
        else:
            months = draw(st.lists(st.integers(1, 12), min_size=1, max_size=3, unique=True))
        parts.append(f'BYMONTH={",".join(str(m) for m in sorted(months))}')

    return ';'.join(parts)


@st.composite
def dtstart_edge_case_for_differential(draw):
    """Generate dtstart with day 28-31 to trigger BYMONTHDAY edge cases.

    Uses months that have 31 days to ensure valid starting dates.
    Removes microseconds for dateutil compatibility.
    Includes leap years (2020, 2024) to test Feb 29 scenarios.
    """
    year = draw(st.integers(2020, 2024))
    # 31-day months: Jan, Mar, May, Jul, Aug, Oct, Dec
    month = draw(st.sampled_from([1, 3, 5, 7, 8, 10, 12]))
    day = draw(st.sampled_from([28, 29, 30, 31]))
    hour = draw(st.integers(0, 23))
    minute = draw(st.integers(0, 59))
    return datetime(year, month, day, hour, minute, 0)
