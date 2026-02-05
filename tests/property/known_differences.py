"""
Known differences between PL/pgSQL implementation and python-dateutil.

These are intentional implementation choices documented in SPEC_COMPLIANCE.md
and CLAUDE.md. Each entry explains the difference and why it exists.

IMPLEMENTATION DIFFERENCES (not listed as KNOWN_DIFFERENCES because they are
handled by test strategy constraints rather than individual RRULE patterns):

1. **10-Year Window Cap**
   - PL/pgSQL: Caps results at 10 years from dtstart
   - python-dateutil: No such limit
   - Reason: Prevents infinite queries for RRULEs without COUNT/UNTIL
   - Reference: CLAUDE.md "API Limits" section

2. **1000-Result Cap**
   - PL/pgSQL: Returns at most 1000 occurrences
   - python-dateutil: No such limit
   - Reason: Prevents DoS attacks from large result sets
   - Reference: CLAUDE.md "API Limits" section

3. **Microsecond Precision**
   - PL/pgSQL: Preserves microseconds in timestamps
   - python-dateutil: Truncates microseconds in some operations
   - Workaround: Test strategy uses dtstart_no_microseconds

These differences are intentional design choices and are avoided in testing
by using constrained strategies (simple_rrule_for_differential, dtstart_no_microseconds).
"""

KNOWN_DIFFERENCES = [
    # Currently no per-RRULE differences needed.
    # The systematic differences above are handled via test strategy constraints.
    #
    # This list is for specific RRULE patterns that have documented intentional
    # behavioral differences. Example entry format:
    # {
    #     'rrule': 'FREQ=MONTHLY;BYMONTHDAY=31;COUNT=5',
    #     'reason': 'SKIP behavior differs - PL/pgSQL defaults to OMIT per RFC 7529',
    #     'reference': 'SPEC_COMPLIANCE.md#month-end-handling',
    # }
]


def is_known_difference(rrule: str) -> bool:
    """Check if an RRULE is a known difference case.

    Args:
        rrule: The RRULE string without the 'RRULE:' prefix.

    Returns:
        True if this RRULE has a documented known difference from python-dateutil.
    """
    return any(d['rrule'] == rrule for d in KNOWN_DIFFERENCES)


def get_difference_reason(rrule: str) -> str | None:
    """Get the documented reason for a known difference.

    Args:
        rrule: The RRULE string without the 'RRULE:' prefix.

    Returns:
        The reason string if this is a known difference, None otherwise.
    """
    for d in KNOWN_DIFFERENCES:
        if d['rrule'] == rrule:
            return d.get('reason', 'No reason documented')
    return None
