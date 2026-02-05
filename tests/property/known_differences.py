"""
Known differences between PL/pgSQL implementation and python-dateutil.

These are intentional implementation choices documented in SPEC_COMPLIANCE.md
and CLAUDE.md. Each entry explains the difference and why it exists.

SYSTEMATIC DIFFERENCES (handled via test strategy constraints):

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

EXTENSION DIFFERENCES (PL/pgSQL features not in dateutil):

4. **SKIP=BACKWARD/FORWARD** (RFC 7529)
   - PL/pgSQL: Full RFC 7529 support (OMIT, BACKWARD, FORWARD)
   - python-dateutil: Only implicit OMIT behavior
   - Note: SKIP=OMIT (default) matches dateutil behavior exactly

5. **RSCALE Parameter**
   - PL/pgSQL: Supports RSCALE=GREGORIAN (required with SKIP)
   - python-dateutil: Limited/no support

These differences are intentional design choices. Systematic differences
are avoided in testing by using constrained strategies
(simple_rrule_for_differential, dtstart_no_microseconds).

COMPATIBLE BEHAVIORS (verified via edge_case_rrule_for_differential):

- BYMONTHDAY with default SKIP=OMIT matches dateutil exactly:
  - BYMONTHDAY=31 on Feb: Both skip February
  - BYMONTHDAY=30 on Feb: Both skip February
  - BYMONTHDAY=-1: Both return last day of month
  - BYMONTHDAY=-2: Both return second-to-last day

KNOWN LIMITATIONS (PL/pgSQL implementation):

6. **Leap day dtstart with YEARLY frequency**
   - Issue: Feb 29 dtstart with YEARLY frequency hits 10-year cap before COUNT
     is satisfied because leap years only occur every 4 years.
   - Example: YEARLY;COUNT=4 from 2024-02-29 can only get 3 results in 10 years
     (2024, 2028, 2032 - the 4th occurrence in 2036 exceeds the cap)
   - python-dateutil: No 10-year cap, returns all COUNT occurrences.
   - Reference: See "10-Year Window Cap" above for cap rationale.

NOTE: ISSUE-014 (FREQ=DAILY + BYMONTHDAY iteration limit) was fixed by
increasing the DAILY multiplier from 40 to 62 in calculate_safe_iteration_limit().
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

    This function checks both explicit patterns in KNOWN_DIFFERENCES
    and pattern-based detection for features not supported by python-dateutil.

    Args:
        rrule: The RRULE string without the 'RRULE:' prefix.

    Returns:
        True if this RRULE has a documented known difference from python-dateutil.
    """
    # Check explicit patterns first
    if any(d['rrule'] == rrule for d in KNOWN_DIFFERENCES):
        return True

    # Pattern-based detection for dateutil-incompatible features
    rrule_upper = rrule.upper()

    # SKIP parameter (except implicit OMIT) is a PL/pgSQL extension
    # python-dateutil has implicit OMIT behavior, but doesn't accept SKIP= syntax
    if 'SKIP=' in rrule_upper:
        # SKIP=BACKWARD and SKIP=FORWARD are PL/pgSQL extensions
        if 'SKIP=BACKWARD' in rrule_upper or 'SKIP=FORWARD' in rrule_upper:
            return True
        # SKIP=OMIT is also not recognized by dateutil syntax-wise
        if 'SKIP=OMIT' in rrule_upper:
            return True

    # RSCALE is only partially supported by dateutil
    if 'RSCALE=' in rrule_upper:
        return True

    # NOTE: ISSUE-014 (FREQ=DAILY + BYMONTHDAY iteration limit) was fixed by
    # increasing the DAILY multiplier from 40 to 62 in calculate_safe_iteration_limit().
    # The workaround that was here has been removed.

    return False


def get_difference_reason(rrule: str):  # -> str | None:
    """Get the documented reason for a known difference.

    Args:
        rrule: The RRULE string without the 'RRULE:' prefix.

    Returns:
        The reason string if this is a known difference, None otherwise.
    """
    # Check explicit patterns
    for d in KNOWN_DIFFERENCES:
        if d['rrule'] == rrule:
            return d.get('reason', 'No reason documented')

    # Pattern-based reasons
    rrule_upper = rrule.upper()

    if 'SKIP=BACKWARD' in rrule_upper or 'SKIP=FORWARD' in rrule_upper:
        return 'SKIP=BACKWARD/FORWARD is RFC 7529 extension not supported by python-dateutil'

    if 'SKIP=OMIT' in rrule_upper:
        return 'SKIP=OMIT syntax is RFC 7529 extension; dateutil has implicit OMIT but rejects the syntax'

    if 'RSCALE=' in rrule_upper:
        return 'RSCALE parameter has limited/no support in python-dateutil'

    # NOTE: ISSUE-014 (FREQ=DAILY + BYMONTHDAY iteration limit) was fixed by
    # increasing the DAILY multiplier from 40 to 62 in calculate_safe_iteration_limit().
    # The pattern check that was here has been removed.

    return None
