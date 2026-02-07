"""Stateful model-based tests for RRULE API consistency."""

from datetime import timedelta, timezone
import os

import psycopg2
from hypothesis import assume
from hypothesis import strategies as st
from hypothesis.stateful import RuleBasedStateMachine, initialize, precondition, rule

from .strategies import stateful_case


def _connect():
    return psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=int(os.environ.get("PGPORT", "54322")),
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ.get("PGPASSWORD", "postgres"),
        dbname=os.environ.get("PGDATABASE", "rrule_test"),
    )


def _normalize_array(values):
    if not values:
        return []
    normalized = []
    for value in values:
        if getattr(value, "tzinfo", None) is not None:
            normalized.append(value.replace(tzinfo=None))
        else:
            normalized.append(value)
    return normalized


class RRuleStateMachine(RuleBasedStateMachine):
    """Model API relationships against the canonical all() result set."""

    def __init__(self):
        super().__init__()
        self.conn = _connect()
        self.conn.autocommit = True
        self.cur = self.conn.cursor()
        self.rrule = None
        self.dtstart = None
        self.dtstart_tz = None
        self.all_results = []

    def teardown(self):
        self.cur.close()
        self.conn.close()

    def _query_array(self, sql, params):
        self.cur.execute(sql, params)
        return _normalize_array(self.cur.fetchone()[0] or [])

    @initialize(case=stateful_case())
    def init_model(self, case):
        rrule, dtstart = case
        self.rrule = rrule
        self.dtstart = dtstart
        self.dtstart_tz = dtstart.replace(tzinfo=timezone.utc)
        self.all_results = self._query_array(
            'SELECT array_agg(r ORDER BY r) FROM rrule."all"(%s, %s) r',
            (self.rrule, self.dtstart),
        )
        assume(len(self.all_results) > 0)

    @rule(i=st.integers(min_value=0, max_value=50), j=st.integers(min_value=0, max_value=50), inc=st.booleans())
    @precondition(lambda self: len(self.all_results) > 0)
    def between_matches_baseline(self, i, j, inc):
        left_occ = self.all_results[min(i % len(self.all_results), j % len(self.all_results))]
        right_occ = self.all_results[max(i % len(self.all_results), j % len(self.all_results))]
        left = left_occ - timedelta(seconds=1)
        right = right_occ + timedelta(seconds=1)

        actual = self._query_array(
            'SELECT array_agg(r ORDER BY r) FROM rrule."between"(%s, %s, %s, %s, %s) r',
            (self.rrule, self.dtstart, left, right, inc),
        )

        if inc:
            expected = [x for x in self.all_results if left <= x <= right]
        else:
            expected = [x for x in self.all_results if left < x < right]

        assert actual == expected

    @rule(i=st.integers(min_value=0, max_value=50), inc=st.booleans())
    @precondition(lambda self: len(self.all_results) > 1)
    def after_matches_baseline(self, i, inc):
        pivot = self.all_results[1 + (i % (len(self.all_results) - 1))] + timedelta(seconds=1)
        rows = self._query_array(
            'SELECT array_agg(r ORDER BY r) FROM rrule."after"(%s, %s, %s, %s) r',
            (self.rrule, self.dtstart, pivot, inc),
        )
        actual = rows[0] if rows else None

        candidates = [value for value in self.all_results if ((value >= pivot) if inc else (value > pivot))]
        expected = min(candidates) if candidates else None
        assert actual == expected

    @rule(i=st.integers(min_value=0, max_value=50), inc=st.booleans())
    @precondition(lambda self: len(self.all_results) > 1)
    def before_matches_baseline(self, i, inc):
        pivot = self.all_results[1 + (i % (len(self.all_results) - 1))] + timedelta(seconds=1)
        rows = self._query_array(
            'SELECT array_agg(r ORDER BY r) FROM rrule."before"(%s, %s, %s, %s) r',
            (self.rrule, self.dtstart, pivot, inc),
        )
        actual = rows[-1] if rows else None

        candidates = [value for value in self.all_results if ((value <= pivot) if inc else (value < pivot))]
        expected = max(candidates) if candidates else None
        assert actual == expected

    @rule(i=st.integers(min_value=0, max_value=60))
    @precondition(lambda self: len(self.all_results) > 0)
    def next_and_most_recent_consistency(self, i):
        base = self.all_results[i % len(self.all_results)]
        reference = base + timedelta(minutes=1)

        self.cur.execute('SELECT rrule."next"(%s, %s, %s)', (self.rrule, self.dtstart, reference))
        nxt = self.cur.fetchone()[0]

        self.cur.execute('SELECT rrule."most_recent"(%s, %s, %s)', (self.rrule, self.dtstart, reference))
        prev = self.cur.fetchone()[0]

        self.cur.execute('SELECT rrule."after"(%s, %s, %s)', (self.rrule, self.dtstart, reference))
        expected_next = self.cur.fetchone()[0]

        self.cur.execute('SELECT rrule."before"(%s, %s, %s)', (self.rrule, self.dtstart, reference))
        expected_prev = self.cur.fetchone()[0]

        assert nxt == expected_next
        assert prev == expected_prev

    @rule()
    @precondition(lambda self: len(self.all_results) > 0)
    def count_matches_all(self):
        self.cur.execute('SELECT rrule."count"(%s, %s)', (self.rrule, self.dtstart))
        count_value = self.cur.fetchone()[0] or 0
        assert count_value == len(self.all_results)

    @rule(session_tz_a=st.sampled_from(["UTC", "America/New_York", "Asia/Tokyo"]),
          session_tz_b=st.sampled_from(["UTC", "America/Los_Angeles", "Europe/London"]))
    @precondition(lambda self: len(self.all_results) > 0)
    def explicit_timezone_is_session_invariant(self, session_tz_a, session_tz_b):
        target_tz = "America/New_York"

        self.cur.execute("SET TIME ZONE %s", (session_tz_a,))
        self.cur.execute(
            """
            SELECT array_agg((r AT TIME ZONE 'UTC')::TIMESTAMP ORDER BY r)
            FROM rrule."all"(%s::TEXT, %s::TIMESTAMPTZ, %s::TEXT) r
            """,
            (self.rrule, self.dtstart_tz, target_tz),
        )
        a = self.cur.fetchone()[0] or []

        self.cur.execute("SET TIME ZONE %s", (session_tz_b,))
        self.cur.execute(
            """
            SELECT array_agg((r AT TIME ZONE 'UTC')::TIMESTAMP ORDER BY r)
            FROM rrule."all"(%s::TEXT, %s::TIMESTAMPTZ, %s::TEXT) r
            """,
            (self.rrule, self.dtstart_tz, target_tz),
        )
        b = self.cur.fetchone()[0] or []

        assert a == b


TestRRuleStateMachine = RRuleStateMachine.TestCase
