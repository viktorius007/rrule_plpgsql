"""Session isolation tests for concurrent RRULE usage.

These tests verify that per-session database settings (TimeZone/search_path)
do not leak across concurrent sessions and that schema-qualified API calls remain
deterministic under parallel load.
"""

from concurrent.futures import ThreadPoolExecutor
import os

import psycopg2


def _connect():
    return psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=int(os.environ.get("PGPORT", "54322")),
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ.get("PGPASSWORD", "postgres"),
        dbname=os.environ.get("PGDATABASE", "rrule_test"),
    )


def _assert_schema_available():
    with _connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT to_regnamespace('rrule') IS NOT NULL")
            has_schema = cur.fetchone()[0]

    if not has_schema:
        raise AssertionError(
            "rrule schema is not installed in test database. "
            "Run ./test.sh --both (or install src/install.sql) before property tests."
        )


def _session_timezone_signature(timezone_name):
    with _connect() as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(f"SET TIME ZONE '{timezone_name}'")
            cur.execute("SELECT current_setting('TimeZone')")
            timezone_seen = cur.fetchone()[0]

            cur.execute(
                """
                SELECT array_agg((r AT TIME ZONE 'UTC')::TIMESTAMP ORDER BY r)
                FROM rrule."all"(
                    'FREQ=DAILY;COUNT=4',
                    '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
                    'America/New_York'
                ) r
                """
            )
            signature = tuple(cur.fetchone()[0] or [])

    return timezone_seen, signature


def _session_search_path_signature(search_path):
    with _connect() as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(f"SET search_path = {search_path}")
            cur.execute("SELECT current_setting('search_path')")
            active_path = cur.fetchone()[0]

            cur.execute(
                """
                SELECT array_agg(r ORDER BY r)
                FROM rrule."all"('FREQ=DAILY;COUNT=3', '2025-01-01 10:00:00'::TIMESTAMP) r
                """
            )
            signature = tuple(cur.fetchone()[0] or [])

    return active_path, signature


def _deterministic_signature():
    with _connect() as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("SET TIME ZONE 'UTC'")
            cur.execute("SET search_path = public")

            cur.execute(
                """
                SELECT array_agg(r ORDER BY r)
                FROM rrule."all"(
                    'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=8',
                    '2025-01-15 09:30:00'::TIMESTAMP
                ) r
                """
            )
            ts_signature = tuple(cur.fetchone()[0] or [])

            cur.execute(
                """
                SELECT array_agg((r AT TIME ZONE 'UTC')::TIMESTAMP ORDER BY r)
                FROM rrule."all"(
                    'FREQ=DAILY;COUNT=5',
                    '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
                    'America/New_York'
                ) r
                """
            )
            tz_signature = tuple(cur.fetchone()[0] or [])

    return ts_signature, tz_signature


def test_timezone_session_isolation_concurrent():
    """Concurrent sessions keep independent TimeZone values and deterministic results."""
    _assert_schema_available()

    with ThreadPoolExecutor(max_workers=2) as pool:
        future_utc = pool.submit(_session_timezone_signature, 'UTC')
        future_ny = pool.submit(_session_timezone_signature, 'America/New_York')

        timezone_utc, sig_utc = future_utc.result()
        timezone_ny, sig_ny = future_ny.result()

    assert timezone_utc == 'UTC'
    assert timezone_ny == 'America/New_York'

    # Explicit timezone parameter should keep output stable across session timezone.
    assert sig_utc == sig_ny


def test_search_path_session_isolation_concurrent():
    """Concurrent sessions keep independent search_path values."""
    _assert_schema_available()

    with ThreadPoolExecutor(max_workers=2) as pool:
        future_public = pool.submit(_session_search_path_signature, 'public')
        future_catalog = pool.submit(_session_search_path_signature, 'pg_catalog, public')

        path_public, sig_public = future_public.result()
        path_catalog, sig_catalog = future_catalog.result()

    assert path_public == 'public'
    assert path_catalog.startswith('pg_catalog')

    # Schema-qualified calls remain correct regardless of search_path.
    assert sig_public == sig_catalog


def test_parallel_determinism_no_cross_session_drift():
    """Parallel execution yields identical signatures across repeated rounds."""
    _assert_schema_available()

    baseline = _deterministic_signature()

    for _ in range(3):
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = [f.result() for f in [pool.submit(_deterministic_signature) for _ in range(8)]]

        for signature in results:
            assert signature == baseline
