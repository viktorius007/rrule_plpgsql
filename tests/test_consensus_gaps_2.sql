/**
 * Consensus Coverage Gap Tests (Round 2)
 *
 * Tests identified by 5-agent consensus analysis cross-referencing
 * src/rrule.sql (~3400 lines), src/rrule_subday.sql (~775 lines),
 * and all 15 test files to find remaining code paths with zero or
 * insufficient test coverage.
 *
 * Covers:
 *  1. TIMESTAMPTZ API overlaps() tests (6-parameter signature)
 *  2. SKIP=FORWARD/BACKWARD + INTERVAL>1 (MONTHLY and YEARLY)
 *  3. get_week_info() next-year branch
 *  4. byweekno_matches_for_year() cross-year ISO week
 *  5. TIMESTAMP before() with >1000 occurrences
 *  6. TIMESTAMPTZ after() with count>1
 *  7. TIMESTAMPTZ before() sliding window trimming
 *  8. TIMESTAMPTZ after()/before() count<=0 boundary
 *  9. TIMESTAMP API next() and most_recent()
 * 10. test_bymonthday_rule() / test_byyearday_rule() negative indices
 * 11. MONTHLY SKIP through TIMESTAMPTZ API
 * 12. YEARLY BYMONTH mixed overflow/non-overflow months
 * 13. BYMONTHDAY FORWARD deduplication
 *
 * Usage:
 *   psql -d your_database -f tests/test_consensus_gaps_2.sql
 *
 * Expected output: All tests pass
 */

\set ON_ERROR_STOP on
\set ECHO all

-- Ensure we're testing in UTC timezone for consistency
SET timezone = 'UTC';

-- Install RRULE functions (allow override via -v rrule_install=...)
\if :{?rrule_install}
\i :rrule_install
\else
DROP SCHEMA IF EXISTS rrule CASCADE;
CREATE SCHEMA IF NOT EXISTS rrule;
\i src/rrule.sql
\endif

-- Ensure tests do not rely on search_path
SET search_path = public;

BEGIN;

\i tests/helpers.sql

-- Test results tracking
CREATE TEMP TABLE consensus2_test_results (
    test_number SERIAL PRIMARY KEY,
    test_group TEXT,
    test_name TEXT,
    status TEXT
);

-- ===================================================================
-- GROUP 1: TIMESTAMPTZ API overlaps() tests
-- The overlaps() function detects if a recurring event has any
-- occurrences within a given date range. This tests the 6-parameter
-- TIMESTAMPTZ API (the only callable overlaps() signature).
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 1: TIMESTAMPTZ API overlaps()'
\echo '==================================================================='

-- Test 1.1: Basic overlap TRUE — recurring event has occurrence in range
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ overlaps', 'overlaps() TRUE — daily rule in range',
    assert_true(
        'TZ overlaps TRUE basic',
        (SELECT rrule."overlaps"(
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=10',
            '2025-01-05 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-06 00:00:00+00'::TIMESTAMPTZ,
            NULL
        ))
    )
);

-- Test 1.2: Basic overlap FALSE — no occurrence in range
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ overlaps', 'overlaps() FALSE — no occurrence in range',
    assert_true(
        'TZ overlaps FALSE basic',
        NOT (SELECT rrule."overlaps"(
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=3',
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 00:00:00+00'::TIMESTAMPTZ,
            NULL
        ))
    )
);

-- Test 1.3: NULL rrule — single event in range
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ overlaps', 'overlaps() NULL rrule — single event in range',
    assert_true(
        'TZ overlaps NULL rrule in range',
        (SELECT rrule."overlaps"(
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-15 12:00:00+00'::TIMESTAMPTZ,
            NULL,
            '2025-01-15 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-16 00:00:00+00'::TIMESTAMPTZ,
            NULL
        ))
    )
);

-- Test 1.4: NULL rrule — single event outside range
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ overlaps', 'overlaps() NULL rrule — outside range',
    assert_true(
        'TZ overlaps NULL rrule outside',
        NOT (SELECT rrule."overlaps"(
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
            NULL,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 00:00:00+00'::TIMESTAMPTZ,
            NULL
        ))
    )
);

-- Test 1.5: Duration-adjusted mindate — event duration extends into range
-- Event at 10:00 lasts 3h. Range starts at 12:00. Duration adjustment
-- pulls mindate back by 3h so the 10:00 occurrence is found.
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ overlaps', 'overlaps() duration-adjusted mindate',
    assert_true(
        'TZ overlaps duration adjusted',
        (SELECT rrule."overlaps"(
            '2025-01-05 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-05 13:00:00+00'::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=10',
            '2025-01-05 12:00:00+00'::TIMESTAMPTZ,
            '2025-01-05 23:59:59+00'::TIMESTAMPTZ,
            NULL
        ))
    )
);

-- Test 1.6: NULL dtend — zero-duration event
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ overlaps', 'overlaps() NULL dtend — zero-duration',
    assert_true(
        'TZ overlaps NULL dtend',
        (SELECT rrule."overlaps"(
            '2025-01-05 10:00:00+00'::TIMESTAMPTZ,
            NULL::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=10',
            '2025-01-05 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-06 00:00:00+00'::TIMESTAMPTZ,
            NULL
        ))
    )
);

-- Test 1.7: Weekly rule — sparse occurrences, verify correct overlap detection
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ overlaps', 'overlaps() weekly — sparse occurrences',
    assert_true(
        'TZ overlaps weekly sparse',
        (SELECT rrule."overlaps"(
            '2025-01-06 09:00:00+00'::TIMESTAMPTZ,
            '2025-01-06 10:00:00+00'::TIMESTAMPTZ,
            'FREQ=WEEKLY;BYDAY=MO;COUNT=10',
            '2025-02-03 00:00:00+00'::TIMESTAMPTZ,
            '2025-02-04 00:00:00+00'::TIMESTAMPTZ,
            NULL
        ))
    )
);

-- ===================================================================
-- GROUP 2: SKIP=FORWARD/BACKWARD + INTERVAL>1
-- CLAUDE.md rule #10 warns: "SKIP and drift prevention interact with
-- INTERVAL in non-obvious ways." FORWARD+INTERVAL>1 and
-- BACKWARD+INTERVAL>1 have zero coverage.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 2: SKIP=FORWARD/BACKWARD + INTERVAL>1'
\echo '==================================================================='

-- Test 2.1: MONTHLY SKIP=FORWARD INTERVAL=2 from Jan 31
-- Jan 31 -> +2=Mar 31 -> +2=May 31 -> +2=Jul 31 -> +2=Sep 31->Oct 1 -> +2=Nov 31->Dec 1
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('SKIP+INTERVAL>1', 'MONTHLY SKIP=FORWARD INTERVAL=2 from Jan 31',
    assert_occurrences_equal(
        'MONTHLY FORWARD INTERVAL=2',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP,
            '2025-10-01 10:00:00'::TIMESTAMP,
            '2025-12-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;INTERVAL=2;COUNT=6',
            '2025-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 2.2: MONTHLY SKIP=BACKWARD INTERVAL=2 from Jan 31
-- Jan 31 -> Mar 31 -> May 31 -> Jul 31 -> Sep 30 (backward) -> Nov 30 (backward)
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('SKIP+INTERVAL>1', 'MONTHLY SKIP=BACKWARD INTERVAL=2 from Jan 31',
    assert_occurrences_equal(
        'MONTHLY BACKWARD INTERVAL=2',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP,
            '2025-09-30 10:00:00'::TIMESTAMP,
            '2025-11-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;INTERVAL=2;COUNT=6',
            '2025-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 2.3: MONTHLY SKIP=FORWARD INTERVAL=3 from Jan 31
-- Jan 31 -> Apr has 30 -> May 1 -> Jul 31 -> Oct 31 -> Jan 31
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('SKIP+INTERVAL>1', 'MONTHLY SKIP=FORWARD INTERVAL=3 from Jan 31',
    assert_occurrences_equal(
        'MONTHLY FORWARD INTERVAL=3',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-05-01 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP,
            '2025-10-31 10:00:00'::TIMESTAMP,
            '2026-01-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;INTERVAL=3;COUNT=5',
            '2025-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 2.4: YEARLY SKIP=FORWARD INTERVAL=2 from Feb 29 (leap year)
-- 2024 Feb 29 -> 2026 Feb 28 has no 29 -> Mar 1 -> 2028 Feb 29 (leap) -> 2030 Mar 1
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('SKIP+INTERVAL>1', 'YEARLY SKIP=FORWARD INTERVAL=2 from Feb 29 leap year',
    assert_occurrences_equal(
        'YEARLY FORWARD INTERVAL=2 leap',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2026-03-01 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP,
            '2030-03-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=FORWARD;INTERVAL=2;COUNT=4',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 2.5: YEARLY SKIP=BACKWARD INTERVAL=2 from Feb 29 (leap year)
-- 2024 Feb 29 -> 2026 Feb 28 (backward) -> 2028 Feb 29 -> 2030 Feb 28
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('SKIP+INTERVAL>1', 'YEARLY SKIP=BACKWARD INTERVAL=2 from Feb 29 leap year',
    assert_occurrences_equal(
        'YEARLY BACKWARD INTERVAL=2 leap',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2026-02-28 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP,
            '2030-02-28 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=BACKWARD;INTERVAL=2;COUNT=4',
            '2024-02-29 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 2.6: MONTHLY SKIP=FORWARD INTERVAL=2 via TIMESTAMPTZ API (TZ generator)
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('SKIP+INTERVAL>1', 'MONTHLY SKIP=FORWARD INTERVAL=2 via TIMESTAMPTZ API',
    assert_true(
        'TZ MONTHLY FORWARD INTERVAL=2',
        (SELECT COUNT(*) = 6
         FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;INTERVAL=2;COUNT=6',
            '2025-01-31 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ))
    )
);

-- ===================================================================
-- GROUP 3: get_week_info() next-year branch
-- Three branches: normal, previous-year, next-year. The next-year
-- branch (week_start >= next_week1_start) handles late December dates
-- belonging to week 1 of the following year. Never tested.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 3: get_week_info() next-year branch'
\echo '==================================================================='

-- Test 3.1: Dec 29, 2025 is a Monday. ISO week 1 of 2026 starts on Dec 29.
-- get_week_info should return week_year=2026, week_num=1
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('get_week_info next-year', 'Dec 29 2025 (Mon) -> ISO week 1 of 2026',
    assert_equals(
        'get_week_info 2025-12-29 year',
        '2026',
        (SELECT week_year::TEXT FROM rrule.get_week_info('2025-12-29 10:00:00+00'::TIMESTAMPTZ, 'MO'))
    )
);

INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('get_week_info next-year', 'Dec 29 2025 (Mon) -> week_num=1',
    assert_equals(
        'get_week_info 2025-12-29 week',
        '1',
        (SELECT week_num::TEXT FROM rrule.get_week_info('2025-12-29 10:00:00+00'::TIMESTAMPTZ, 'MO'))
    )
);

-- Test 3.2: Dec 31, 2025 is a Wednesday. Also in ISO week 1 of 2026.
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('get_week_info next-year', 'Dec 31 2025 (Wed) -> ISO week 1 of 2026',
    assert_equals(
        'get_week_info 2025-12-31 year',
        '2026',
        (SELECT week_year::TEXT FROM rrule.get_week_info('2025-12-31 10:00:00+00'::TIMESTAMPTZ, 'MO'))
    )
);

-- ===================================================================
-- GROUP 4: byweekno_matches_for_year() cross-year ISO week
-- Tests the weekyear != date_part('year', year_start) early return.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 4: byweekno_matches_for_year() cross-year'
\echo '==================================================================='

-- Test 4.1: Dec 29 2025 belongs to ISO week 1 of 2026, not 2025
-- Should return FALSE when checking against year 2025
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('byweekno cross-year', 'Dec 29 2025 in ISO wk1 of 2026 — FALSE for year 2025',
    assert_true(
        'byweekno cross-year FALSE',
        NOT (SELECT rrule.byweekno_matches_for_year(
            '2025-12-29 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-01 00:00:00+00'::TIMESTAMPTZ,
            'MO',
            ARRAY[1]
        ))
    )
);

-- Test 4.2: Same date should return TRUE when checking against year 2026
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('byweekno cross-year', 'Dec 29 2025 in ISO wk1 of 2026 — TRUE for year 2026',
    assert_true(
        'byweekno cross-year TRUE',
        (SELECT rrule.byweekno_matches_for_year(
            '2025-12-29 10:00:00+00'::TIMESTAMPTZ,
            '2026-01-01 00:00:00+00'::TIMESTAMPTZ,
            'MO',
            ARRAY[1]
        ))
    )
);

-- Test 4.3: Jan 1 2025 (Wednesday) is in ISO week 1 of 2025 — TRUE for year 2025
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('byweekno cross-year', 'Jan 1 2025 in ISO wk1 of 2025 — TRUE for year 2025',
    assert_true(
        'byweekno same-year TRUE',
        (SELECT rrule.byweekno_matches_for_year(
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-01 00:00:00+00'::TIMESTAMPTZ,
            'MO',
            ARRAY[1]
        ))
    )
);

-- ===================================================================
-- GROUP 5: TIMESTAMP before() with >1000 occurrences
-- before() passes max_count=50000000 to bypass the 1000-result cap.
-- No test verifies correctness for rules producing >1000 occurrences.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 5: TIMESTAMP before() with >1000 occurrences'
\echo '==================================================================='

-- Test 5.1: DAILY rule, find last occurrence before a date >1000 days out
-- FREQ=DAILY with dtstart 2020-01-01, before_date 2025-01-01 = ~1827 days
-- The last occurrence before 2025-01-01 should be 2024-12-31
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('before >1000', 'before() finds correct occurrence beyond 1000-cap',
    assert_equals(
        'before >1000 occurrences',
        '2024-12-31 10:00:00',
        (SELECT rrule."before"(
            'FREQ=DAILY;UNTIL=20251231T100000Z',
            '2020-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:00:00'::TIMESTAMP,
            FALSE
        ))::TEXT
    )
);

-- Test 5.2: before() with inc=TRUE on exact match beyond 1000
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('before >1000', 'before() inc=TRUE exact match beyond 1000-cap',
    assert_equals(
        'before >1000 inc=TRUE',
        '2025-01-01 10:00:00',
        (SELECT rrule."before"(
            'FREQ=DAILY;UNTIL=20251231T100000Z',
            '2020-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:00:00'::TIMESTAMP,
            TRUE
        ))::TEXT
    )
);

-- ===================================================================
-- GROUP 6: TIMESTAMPTZ after() with count>1
-- The TIMESTAMPTZ after() returns SETOF TIMESTAMPTZ with a count
-- parameter. All existing tests use count=1 via next().
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 6: TIMESTAMPTZ after() with count>1'
\echo '==================================================================='

-- Test 6.1: after() with count=3 — should return 3 occurrences
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ after count>1', 'after() count=3 returns 3 occurrences',
    assert_true(
        'TZ after count=3',
        (SELECT COUNT(*) = 3
         FROM rrule."after"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-03 10:00:00+00'::TIMESTAMPTZ,
            3,
            'UTC',
            FALSE
        ))
    )
);

-- Test 6.2: after() count=3 — verify correct values
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ after count>1', 'after() count=3 correct values',
    assert_occurrences_equal(
        'TZ after count=3 values',
        ARRAY[
            '2025-01-04 10:00:00'::TIMESTAMP,
            '2025-01-05 10:00:00'::TIMESTAMP,
            '2025-01-06 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence)
         FROM rrule."after"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-03 10:00:00+00'::TIMESTAMPTZ,
            3,
            'UTC',
            FALSE
        ) AS occurrence)
    )
);

-- ===================================================================
-- GROUP 7: TIMESTAMPTZ before() sliding window trimming
-- Array slicing results[len-count+1 : len] keeps last N results.
-- Never exercised with actual trimming (many occurrences, small count).
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 7: TIMESTAMPTZ before() sliding window'
\echo '==================================================================='

-- Test 7.1: before() count=2 on rule producing 50+ results — verify trim
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ before sliding', 'before() count=2 — sliding window trims correctly',
    assert_occurrences_equal(
        'TZ before sliding trim',
        ARRAY[
            '2025-02-27 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence)
         FROM rrule."before"(
            'FREQ=DAILY;COUNT=100',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-03-01 10:00:00+00'::TIMESTAMPTZ,
            2,
            'UTC',
            FALSE
        ) AS occurrence)
    )
);

-- Test 7.2: before() count=3 on rule producing 100+ results
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ before sliding', 'before() count=3 — sliding window on 100+ results',
    assert_true(
        'TZ before sliding count=3',
        (SELECT COUNT(*) = 3
         FROM rrule."before"(
            'FREQ=DAILY;COUNT=200',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-06-01 10:00:00+00'::TIMESTAMPTZ,
            3,
            'UTC',
            FALSE
        ))
    )
);

-- ===================================================================
-- GROUP 8: TIMESTAMPTZ after()/before() count<=0 boundary
-- Both silently return empty set when count <= 0.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 8: TIMESTAMPTZ after()/before() count<=0'
\echo '==================================================================='

-- Test 8.1: after() with count=0 returns empty set
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('count<=0 boundary', 'after() count=0 returns empty set',
    assert_true(
        'TZ after count=0',
        (SELECT COUNT(*) = 0
         FROM rrule."after"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-03 10:00:00+00'::TIMESTAMPTZ,
            0,
            'UTC',
            FALSE
        ))
    )
);

-- Test 8.2: after() with count=-1 returns empty set
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('count<=0 boundary', 'after() count=-1 returns empty set',
    assert_true(
        'TZ after count=-1',
        (SELECT COUNT(*) = 0
         FROM rrule."after"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-03 10:00:00+00'::TIMESTAMPTZ,
            -1,
            'UTC',
            FALSE
        ))
    )
);

-- Test 8.3: before() with count=0 returns empty set
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('count<=0 boundary', 'before() count=0 returns empty set',
    assert_true(
        'TZ before count=0',
        (SELECT COUNT(*) = 0
         FROM rrule."before"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-08 10:00:00+00'::TIMESTAMPTZ,
            0,
            'UTC',
            FALSE
        ))
    )
);

-- Test 8.4: before() with count=-1 returns empty set
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('count<=0 boundary', 'before() count=-1 returns empty set',
    assert_true(
        'TZ before count=-1',
        (SELECT COUNT(*) = 0
         FROM rrule."before"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-08 10:00:00+00'::TIMESTAMPTZ,
            -1,
            'UTC',
            FALSE
        ))
    )
);

-- ===================================================================
-- GROUP 9: TIMESTAMP API next() and most_recent()
-- These functions use NOW()::TIMESTAMP as default and delegate to
-- after()/before(). No test calls the TIMESTAMP signature directly.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 9: TIMESTAMP API next() and most_recent()'
\echo '==================================================================='

-- Test 9.1: TIMESTAMP next() with explicit reference time
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TS next/most_recent', 'next() — returns first occurrence after reference_time',
    assert_equals(
        'TS next basic',
        '2025-01-06 10:00:00',
        (SELECT rrule."next"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-05 10:00:00'::TIMESTAMP
        ))::TEXT
    )
);

-- Test 9.2: TIMESTAMP most_recent() with explicit reference time
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TS next/most_recent', 'most_recent() — returns last occurrence before reference_time',
    assert_equals(
        'TS most_recent basic',
        '2025-01-04 10:00:00',
        (SELECT rrule."most_recent"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-05 10:00:00'::TIMESTAMP
        ))::TEXT
    )
);

-- Test 9.3: TIMESTAMP next() returns NULL when past all occurrences
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TS next/most_recent', 'next() returns NULL when past all occurrences',
    assert_equals(
        'TS next NULL past end',
        NULL,
        (SELECT rrule."next"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-10 10:00:00'::TIMESTAMP
        ))::TEXT
    )
);

-- Test 9.4: TIMESTAMP most_recent() returns NULL when before all occurrences
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TS next/most_recent', 'most_recent() returns NULL when before all occurrences',
    assert_equals(
        'TS most_recent NULL',
        NULL,
        (SELECT rrule."most_recent"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-05 10:00:00'::TIMESTAMP,
            '2025-01-04 10:00:00'::TIMESTAMP
        ))::TEXT
    )
);

-- ===================================================================
-- GROUP 10: test_bymonthday_rule() and test_byyearday_rule() negative indices
-- The negative index formulas (days_in_month + md + 1) and
-- (days_in_year + yd + 1) are never verified directly.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 10: Negative index filter functions'
\echo '==================================================================='

-- Test 10.1: test_bymonthday_rule() negative — BYMONTHDAY=-2 matches day 30 in Jan (31 days)
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('negative indices', 'test_bymonthday_rule -2 matches Jan 30 (31 days)',
    assert_true(
        'bymonthday -2 match',
        (SELECT rrule.test_bymonthday_rule('2025-01-30 10:00:00+00'::TIMESTAMPTZ, ARRAY[-2]))
    )
);

-- Test 10.2: test_bymonthday_rule() negative — BYMONTHDAY=-2 does NOT match Jan 29
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('negative indices', 'test_bymonthday_rule -2 does NOT match Jan 29',
    assert_true(
        'bymonthday -2 no match',
        NOT (SELECT rrule.test_bymonthday_rule('2025-01-29 10:00:00+00'::TIMESTAMPTZ, ARRAY[-2]))
    )
);

-- Test 10.3: test_bymonthday_rule() BYMONTHDAY=-1 matches last day of Feb (28 in non-leap)
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('negative indices', 'test_bymonthday_rule -1 matches Feb 28 (non-leap)',
    assert_true(
        'bymonthday -1 feb',
        (SELECT rrule.test_bymonthday_rule('2025-02-28 10:00:00+00'::TIMESTAMPTZ, ARRAY[-1]))
    )
);

-- Test 10.4: test_byyearday_rule() negative — BYYEARDAY=-1 matches Dec 31
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('negative indices', 'test_byyearday_rule -1 matches Dec 31',
    assert_true(
        'byyearday -1 match',
        (SELECT rrule.test_byyearday_rule('2025-12-31 10:00:00+00'::TIMESTAMPTZ, ARRAY[-1]))
    )
);

-- Test 10.5: test_byyearday_rule() negative — BYYEARDAY=-1 does NOT match Dec 30
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('negative indices', 'test_byyearday_rule -1 does NOT match Dec 30',
    assert_true(
        'byyearday -1 no match',
        NOT (SELECT rrule.test_byyearday_rule('2025-12-30 10:00:00+00'::TIMESTAMPTZ, ARRAY[-1]))
    )
);

-- Test 10.6: test_byyearday_rule() BYYEARDAY=-365 matches Jan 1 (non-leap year, 365 days)
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('negative indices', 'test_byyearday_rule -365 matches Jan 1 (365-day year)',
    assert_true(
        'byyearday -365 match',
        (SELECT rrule.test_byyearday_rule('2025-01-01 10:00:00+00'::TIMESTAMPTZ, ARRAY[-365]))
    )
);

-- ===================================================================
-- GROUP 11: MONTHLY SKIP through TIMESTAMPTZ API
-- SKIP=BACKWARD for MONTHLY is only tested via TIMESTAMP API.
-- TZ generator has its own copy that could diverge.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 11: MONTHLY SKIP via TIMESTAMPTZ API'
\echo '==================================================================='

-- Test 11.1: MONTHLY SKIP=BACKWARD via TIMESTAMPTZ API
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ MONTHLY SKIP', 'MONTHLY SKIP=BACKWARD via TIMESTAMPTZ — Jan 31 bimonthly',
    assert_occurrences_equal(
        'TZ MONTHLY BACKWARD',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=4',
            '2025-01-31 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ) AS occurrence)
    )
);

-- Test 11.2: MONTHLY SKIP=FORWARD via TIMESTAMPTZ API
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('TZ MONTHLY SKIP', 'MONTHLY SKIP=FORWARD via TIMESTAMPTZ — Jan 31 monthly',
    assert_occurrences_equal(
        'TZ MONTHLY FORWARD',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=4',
            '2025-01-31 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ) AS occurrence)
    )
);

-- ===================================================================
-- GROUP 12: YEARLY BYMONTH mixed overflow/non-overflow months
-- BYMONTH=2,3 with dtstart day 31 — Feb overflows, Mar keeps day 31.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 12: YEARLY BYMONTH mixed overflow'
\echo '==================================================================='

-- Test 12.1: YEARLY BYMONTH=2,3 SKIP=FORWARD from Jan 31
-- Feb 31 -> Mar 1 (forward), Mar 31 -> Mar 31 (no overflow)
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('YEARLY BYMONTH mixed', 'BYMONTH=2,3 SKIP=FORWARD from Jan 31 — mixed overflow',
    assert_occurrences_equal(
        'YEARLY BYMONTH mixed FORWARD',
        ARRAY[
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2026-03-01 10:00:00'::TIMESTAMP,
            '2026-03-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=2,3;BYMONTHDAY=31;SKIP=FORWARD;COUNT=4',
            '2025-01-31 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- ===================================================================
-- GROUP 13: BYMONTHDAY FORWARD deduplication
-- BYMONTHDAY=30,31 with SKIP=FORWARD in February — both forward to
-- March 1. The seen_dates dedup should prevent returning March 1 twice.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 13: BYMONTHDAY FORWARD deduplication'
\echo '==================================================================='

-- Test 13.1: BYMONTHDAY=30,31 SKIP=FORWARD — Feb produces one Mar 1, not two
INSERT INTO consensus2_test_results (test_group, test_name, status)
VALUES ('BYMONTHDAY dedup', 'BYMONTHDAY=30,31 SKIP=FORWARD — Feb dedup to one Mar 1',
    assert_occurrences_equal(
        'BYMONTHDAY FORWARD dedup',
        ARRAY[
            '2025-01-30 10:00:00'::TIMESTAMP,
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2025-03-30 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=30,31;SKIP=FORWARD;COUNT=5',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- ===================================================================
-- Test Results Summary
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'Consensus Gap Test Results (Round 2)'
\echo '==================================================================='

SELECT
    test_number,
    test_group,
    test_name,
    status
FROM consensus2_test_results
ORDER BY test_number;

\echo ''
\echo 'Summary by group:'
SELECT
    test_group,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') AS passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') AS failed,
    COUNT(*) FILTER (WHERE status LIKE 'SKIP%') AS skipped
FROM consensus2_test_results
GROUP BY test_group
ORDER BY MIN(test_number);

\echo ''
\echo 'Overall:'
SELECT
    COUNT(*) AS total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') AS passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') AS failed,
    COUNT(*) FILTER (WHERE status LIKE 'SKIP%') AS skipped
FROM consensus2_test_results;

-- Verify all tests passed (fail if any FAIL results)
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM consensus2_test_results
    WHERE status LIKE 'FAIL%';

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'CONSENSUS GAP TESTS (ROUND 2) FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'CONSENSUS GAP TESTS (ROUND 2) PASSED: All tests passed!';
    END IF;
END $$;

ROLLBACK;
