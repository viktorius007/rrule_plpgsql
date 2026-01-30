/**
 * Comprehensive WKST (Week Start Day) Support Tests
 *
 * These tests verify that WKST parameter handling works correctly,
 * including all 7 week start values, year boundaries, and BYWEEKNO interactions.
 *
 * Test categories:
 * 1. Basic WEEKLY frequency with different WKST values
 * 2. WEEKLY with BYDAY and different WKST values
 * 3. BYWEEKNO with different WKST values (YEARLY frequency)
 * 4. Year boundary edge cases
 * 5. All 7 WKST values systematically
 * 6. Complex patterns with WKST
 * 7. Edge cases and regression tests
 *
 * Usage:
 *   psql -d your_database -f test_wkst_support.sql
 *
 * Expected output: All tests should pass with "PASS" status
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

CREATE TEMP TABLE wkst_test_results (
    test_number SERIAL PRIMARY KEY,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 1: Basic WEEKLY frequency with different WKST values'
\echo '==================================================================='

-- Test 1: WEEKLY with default WKST=MO (Monday start)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY with WKST=MO (default Monday start)',
    assert_occurrences_equal(
        'WEEKLY with WKST=MO',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-13 10:00:00'::TIMESTAMP,
            '2025-01-20 10:00:00'::TIMESTAMP,
            '2025-01-27 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=4;WKST=MO',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 2: WEEKLY with WKST=SU (Sunday start)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY with WKST=SU (Sunday start)',
    assert_occurrences_equal(
        'WEEKLY with WKST=SU',
        ARRAY[
            '2025-01-05 10:00:00'::TIMESTAMP,
            '2025-01-12 10:00:00'::TIMESTAMP,
            '2025-01-19 10:00:00'::TIMESTAMP,
            '2025-01-26 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=4;WKST=SU',
            '2025-01-05 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 3: WEEKLY with WKST=SA (Saturday start)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY with WKST=SA (Saturday start)',
    assert_occurrences_equal(
        'WEEKLY with WKST=SA',
        ARRAY[
            '2025-01-04 10:00:00'::TIMESTAMP,
            '2025-01-11 10:00:00'::TIMESTAMP,
            '2025-01-18 10:00:00'::TIMESTAMP,
            '2025-01-25 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=4;WKST=SA',
            '2025-01-04 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 4: WEEKLY;INTERVAL=2 with WKST=TU (Tuesday start, biweekly)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY;INTERVAL=2 with WKST=TU (biweekly)',
    assert_occurrences_equal(
        'WEEKLY;INTERVAL=2 with WKST=TU',
        ARRAY[
            '2025-01-07 10:00:00'::TIMESTAMP,
            '2025-01-21 10:00:00'::TIMESTAMP,
            '2025-02-04 10:00:00'::TIMESTAMP,
            '2025-02-18 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;COUNT=4;WKST=TU',
            '2025-01-07 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 2: WEEKLY with BYDAY and different WKST values'
\echo '==================================================================='

-- Test 5: WEEKLY;BYDAY=MO,WE,FR with WKST=MO
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY;BYDAY=MO,WE,FR with WKST=MO',
    assert_occurrences_equal(
        'WEEKLY;BYDAY=MO,WE,FR with WKST=MO',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-08 10:00:00'::TIMESTAMP,
            '2025-01-10 10:00:00'::TIMESTAMP,
            '2025-01-13 10:00:00'::TIMESTAMP,
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-01-17 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=6;BYDAY=MO,WE,FR;WKST=MO',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 6: WEEKLY;BYDAY=MO,WE,FR with WKST=SU (week starts Sunday)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY;BYDAY=MO,WE,FR with WKST=SU',
    assert_occurrences_equal(
        'WEEKLY;BYDAY=MO,WE,FR with WKST=SU',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-08 10:00:00'::TIMESTAMP,
            '2025-01-10 10:00:00'::TIMESTAMP,
            '2025-01-13 10:00:00'::TIMESTAMP,
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-01-17 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=6;BYDAY=MO,WE,FR;WKST=SU',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 3: MONTHLY frequency with WKST'
\echo '==================================================================='

-- Test 7: MONTHLY with WKST=MO (week start doesn't affect monthly much)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('MONTHLY with WKST=MO',
    assert_occurrences_equal(
        'MONTHLY with WKST=MO',
        ARRAY[
            '2025-02-15 10:00:00'::TIMESTAMP,
            '2025-03-15 10:00:00'::TIMESTAMP,
            '2025-04-15 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;COUNT=3;WKST=MO',
            '2025-02-15 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 8: MONTHLY;BYDAY=MO with WKST=SU
INSERT INTO wkst_test_results (test_name, status)
VALUES ('MONTHLY;BYDAY=MO with WKST=SU',
    assert_occurrences_equal(
        'MONTHLY;BYDAY=MO with WKST=SU',
        ARRAY[
            '2025-02-03 10:00:00'::TIMESTAMP,
            '2025-02-10 10:00:00'::TIMESTAMP,
            '2025-02-17 10:00:00'::TIMESTAMP,
            '2025-02-24 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;COUNT=4;BYDAY=MO;WKST=SU',
            '2025-02-03 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 9: YEARLY;BYWEEKNO=2;BYDAY=MO with WKST=MO (ISO week 2 is fully within year)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('YEARLY;BYWEEKNO=2;BYDAY=MO with WKST=MO',
    assert_occurrences_equal(
        'YEARLY;BYWEEKNO=2;BYDAY=MO with WKST=MO',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2026-01-05 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;COUNT=2;BYWEEKNO=2;BYDAY=MO;WKST=MO',
            '2025-01-06 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 10: YEARLY;BYWEEKNO=2;BYDAY=SU with WKST=SU
INSERT INTO wkst_test_results (test_name, status)
VALUES ('YEARLY;BYWEEKNO=2;BYDAY=SU with WKST=SU',
    assert_occurrences_equal(
        'YEARLY;BYWEEKNO=2;BYDAY=SU with WKST=SU',
        ARRAY[
            '2025-01-05 10:00:00'::TIMESTAMP,
            '2026-01-11 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;COUNT=2;BYWEEKNO=2;BYDAY=SU;WKST=SU',
            '2025-01-05 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 11: YEARLY;BYWEEKNO=1;BYDAY=MO,TU,WE,TH,FR with WKST=WE (mid-week start)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('YEARLY;BYWEEKNO=1;BYDAY=MO,TU,WE,TH,FR with WKST=WE',
    assert_occurrences_equal(
        'YEARLY;BYWEEKNO=1;BYDAY=MO,TU,WE,TH,FR with WKST=WE',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,  -- Wed, week 1
            '2025-01-02 10:00:00'::TIMESTAMP,  -- Thu, week 1
            '2025-01-03 10:00:00'::TIMESTAMP,  -- Fri, week 1
            '2025-01-06 10:00:00'::TIMESTAMP,  -- Mon, week 1
            '2025-01-07 10:00:00'::TIMESTAMP   -- Tue, week 1
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;COUNT=5;BYWEEKNO=1;BYDAY=MO,TU,WE,TH,FR;WKST=WE',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 12: YEARLY;BYWEEKNO with multiple weeks and days (ISO week 2 + week 52)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('YEARLY;BYWEEKNO=2,52;BYDAY=MO,FR with WKST=MO',
    assert_occurrences_equal(
        'YEARLY;BYWEEKNO=2,52;BYDAY=MO,FR',
        ARRAY[
            '2025-01-06 10:00:00'::TIMESTAMP,  -- Mon, week 2
            '2025-01-10 10:00:00'::TIMESTAMP,  -- Fri, week 2
            '2025-12-22 10:00:00'::TIMESTAMP   -- Mon, week 52
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;COUNT=3;BYWEEKNO=2,52;BYDAY=MO,FR;WKST=MO',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 4: Year boundary edge cases'
\echo '==================================================================='

-- Test 13: DAILY in first partial week with WKST=MO
INSERT INTO wkst_test_results (test_name, status)
VALUES ('DAILY in first partial week with WKST=MO',
    assert_occurrences_equal(
        'DAILY in first partial week with WKST=MO',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            '2025-01-04 10:00:00'::TIMESTAMP,
            '2025-01-05 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=5;WKST=MO',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 14: DAILY in last partial week with WKST=SU
INSERT INTO wkst_test_results (test_name, status)
VALUES ('DAILY in last partial week with WKST=SU',
    assert_occurrences_equal(
        'DAILY in last partial week with WKST=SU',
        ARRAY[
            '2025-12-28 10:00:00'::TIMESTAMP,
            '2025-12-29 10:00:00'::TIMESTAMP,
            '2025-12-30 10:00:00'::TIMESTAMP,
            '2025-12-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=4;WKST=SU',
            '2025-12-28 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 15: New Year's transition with WKST=TH (Thursday week start)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('New Year transition with WKST=TH',
    assert_occurrences_equal(
        'New Year transition with WKST=TH',
        ARRAY[
            '2025-12-25 10:00:00'::TIMESTAMP,
            '2026-01-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=2;BYDAY=TH;WKST=TH',
            '2025-12-25 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 5: All 7 WKST values systematically'
\echo '==================================================================='

-- Test 16: WKST=SU (Sunday = 0)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY with WKST=SU (Sunday)',
    assert_occurrences_equal(
        'WEEKLY with WKST=SU',
        ARRAY[
            '2025-02-02 10:00:00'::TIMESTAMP,
            '2025-02-09 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=2;WKST=SU',
            '2025-02-02 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 17: WKST=MO (Monday = 1)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY with WKST=MO (Monday)',
    assert_occurrences_equal(
        'WEEKLY with WKST=MO',
        ARRAY[
            '2025-02-03 10:00:00'::TIMESTAMP,
            '2025-02-10 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=2;WKST=MO',
            '2025-02-03 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 18: WKST=TU (Tuesday = 2)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY with WKST=TU (Tuesday)',
    assert_occurrences_equal(
        'WEEKLY with WKST=TU',
        ARRAY[
            '2025-02-04 10:00:00'::TIMESTAMP,
            '2025-02-11 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=2;WKST=TU',
            '2025-02-04 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 19: WKST=WE (Wednesday = 3)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY with WKST=WE (Wednesday)',
    assert_occurrences_equal(
        'WEEKLY with WKST=WE',
        ARRAY[
            '2025-02-05 10:00:00'::TIMESTAMP,
            '2025-02-12 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=2;WKST=WE',
            '2025-02-05 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 20: WKST=TH (Thursday = 4)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY with WKST=TH (Thursday)',
    assert_occurrences_equal(
        'WEEKLY with WKST=TH',
        ARRAY[
            '2025-02-06 10:00:00'::TIMESTAMP,
            '2025-02-13 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=2;WKST=TH',
            '2025-02-06 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 21: WKST=FR (Friday = 5)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY with WKST=FR (Friday)',
    assert_occurrences_equal(
        'WEEKLY with WKST=FR',
        ARRAY[
            '2025-02-07 10:00:00'::TIMESTAMP,
            '2025-02-14 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=2;WKST=FR',
            '2025-02-07 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 22: WKST=SA (Saturday = 6)
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY with WKST=SA (Saturday)',
    assert_occurrences_equal(
        'WEEKLY with WKST=SA',
        ARRAY[
            '2025-02-08 10:00:00'::TIMESTAMP,
            '2025-02-15 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=2;WKST=SA',
            '2025-02-08 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 6: Edge cases and regression tests'
\echo '==================================================================='

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 7: RFC 5545 Canonical WKST Example (INTERVAL=2)'
\echo '==================================================================='

-- RFC 5545 Section 3.3.10 canonical example: WKST affects which weeks are counted
-- when INTERVAL>1. dtstart=Sunday Jan 5 2025.
-- With WKST=SU: Week 1 = Jan 5-11, Week 2 (skipped) = Jan 12-18, Week 3 = Jan 19-25
-- With WKST=MO: Week containing Jan 5 starts Dec 30; next counted week = Jan 13-19
INSERT INTO wkst_test_results (test_name, status)
VALUES ('RFC 5545 canonical: WKST=SU INTERVAL=2 BYDAY=TU,TH',
    assert_occurrences_equal(
        'WKST=SU biweekly canonical',
        ARRAY[
            '2025-01-07 10:00:00'::TIMESTAMP,
            '2025-01-09 10:00:00'::TIMESTAMP,
            '2025-01-21 10:00:00'::TIMESTAMP,
            '2025-01-23 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;WKST=SU;COUNT=4',
            '2025-01-05 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

INSERT INTO wkst_test_results (test_name, status)
VALUES ('RFC 5545 canonical: WKST=MO INTERVAL=2 BYDAY=TU,TH',
    assert_occurrences_equal(
        'WKST=MO biweekly canonical',
        ARRAY[
            '2025-01-14 10:00:00'::TIMESTAMP,
            '2025-01-16 10:00:00'::TIMESTAMP,
            '2025-01-28 10:00:00'::TIMESTAMP,
            '2025-01-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;WKST=MO;COUNT=4',
            '2025-01-05 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 23: Missing WKST defaults to MO
INSERT INTO wkst_test_results (test_name, status)
VALUES ('WEEKLY without WKST (defaults to MO)',
    assert_occurrences_equal(
        'WEEKLY without WKST',
        ARRAY[
            '2025-01-20 10:00:00'::TIMESTAMP,
            '2025-01-27 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;COUNT=2',
            '2025-01-20 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

\echo ''
\echo '==================================================================='
\echo 'TEST GROUP 8: BYWEEKNO Week 53 Functional Tests'
\echo '==================================================================='

-- ISO 8601 week 53 years (with WKST=MO):
-- 2015 has 53 ISO weeks (Jan 1 is Thursday → Dec 31 is Thursday → week 53)
-- 2020 has 53 ISO weeks (Jan 1 is Wednesday → Dec 31 is Thursday → week 53)
-- 2026 has 53 ISO weeks (Jan 1 is Thursday)

-- Test: BYWEEKNO=53 produces results for years that have 53 ISO weeks
-- 2015 and 2020 both have 53 ISO weeks. Using COUNT=2 within 10-year default window.
INSERT INTO wkst_test_results (test_name, status)
VALUES ('BYWEEKNO=53 finds weeks in 53-week years',
    assert_occurrences_equal(
        'BYWEEKNO=53 with BYDAY=MO',
        ARRAY[
            '2015-12-28 10:00:00'::TIMESTAMP,  -- Monday of ISO week 53 of 2015
            '2020-12-28 10:00:00'::TIMESTAMP    -- Monday of ISO week 53 of 2020
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYWEEKNO=53;BYDAY=MO;COUNT=2',
            '2015-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test: BYWEEKNO=53 with BYDAY=TH (Thursday of week 53)
-- 2015 week 53: Thu Dec 31, 2015
-- 2020 week 53: Thu Dec 31, 2020
INSERT INTO wkst_test_results (test_name, status)
VALUES ('BYWEEKNO=53 with BYDAY=TH',
    assert_occurrences_equal(
        'BYWEEKNO=53 BYDAY=TH',
        ARRAY[
            '2015-12-31 10:00:00'::TIMESTAMP,  -- Thursday of ISO week 53 of 2015
            '2020-12-31 10:00:00'::TIMESTAMP    -- Thursday of ISO week 53 of 2020
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYWEEKNO=53;BYDAY=TH;COUNT=2',
            '2015-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test: Negative BYWEEKNO=-1 should find the last week of each year
-- For 2025 (52-week year), week -1 = week 52 → Monday = 2025-12-22
-- For 2026 (53-week year), week -1 = week 53 → Monday = 2026-12-28
INSERT INTO wkst_test_results (test_name, status)
VALUES ('BYWEEKNO=-1 finds last week of year',
    assert_occurrences_equal(
        'BYWEEKNO=-1 last week of year',
        ARRAY[
            '2025-12-22 10:00:00'::TIMESTAMP,
            '2026-12-28 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYWEEKNO=-1;BYDAY=MO;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- ============================================================================
-- SECTION 9: WKST Differentiation with INTERVAL=2 (Saturday dtstart)
-- These tests verify WKST produces different results when INTERVAL>1
-- ============================================================================
\echo ''
\echo '--- Section 9: WKST Differentiation with INTERVAL=2 ---'

-- Test: WKST=SU vs WKST=SA with INTERVAL=2 on Saturday dtstart
-- dtstart = Saturday Jan 4, 2025 at 10:00
-- BYDAY=WE; INTERVAL=2
--
-- WKST=SU: Jan 4 in week Sun Dec 29-Sat Jan 4 (active). WE=Jan 1 (before dtstart).
--   Skip Sun Jan 5-Sat Jan 11. Active Sun Jan 12-Sat Jan 18: WE=Jan 15.
--   Skip Jan 19-25. Active Jan 26-Feb 1: WE=Jan 29.
--   Skip Feb 2-8. Active Feb 9-15: WE=Feb 12.
INSERT INTO wkst_test_results (test_name, status)
SELECT
    'Test 9.1: WKST=SU INTERVAL=2 BYDAY=WE (Saturday dtstart)',
    assert_occurrences_equal(
        'WKST=SU biweekly WE sat-dtstart',
        ARRAY[
            '2025-01-15 10:00:00'::TIMESTAMP,
            '2025-01-29 10:00:00'::TIMESTAMP,
            '2025-02-12 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=WE;WKST=SU;COUNT=3',
            '2025-01-04 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 9.2: Same rule with WKST=SA — different results
-- WKST=SA: Jan 4 starts a new week Sat Jan 4-Fri Jan 10 (active). WE=Jan 8.
--   Skip Sat Jan 11-Fri Jan 17. Active Sat Jan 18-Fri Jan 24: WE=Jan 22.
--   Skip Jan 25-31. Active Sat Feb 1-Fri Feb 7: WE=Feb 5.
INSERT INTO wkst_test_results (test_name, status)
SELECT
    'Test 9.2: WKST=SA INTERVAL=2 BYDAY=WE (Saturday dtstart)',
    assert_occurrences_equal(
        'WKST=SA biweekly WE sat-dtstart',
        ARRAY[
            '2025-01-08 10:00:00'::TIMESTAMP,
            '2025-01-22 10:00:00'::TIMESTAMP,
            '2025-02-05 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=WE;WKST=SA;COUNT=3',
            '2025-01-04 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 9.3: Verify WKST=SU and WKST=SA produce DIFFERENT date sets
-- This is the critical assertion: same RRULE params except WKST yields different results
INSERT INTO wkst_test_results (test_name, status)
SELECT
    'Test 9.3: WKST=SU vs WKST=SA produce different results',
    assert_true(
        'WKST differentiation',
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=WE;WKST=SU;COUNT=3',
            '2025-01-04 10:00:00'::TIMESTAMP
        ) d)
        IS DISTINCT FROM
        (SELECT array_agg(d ORDER BY d) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=WE;WKST=SA;COUNT=3',
            '2025-01-04 10:00:00'::TIMESTAMP
        ) d)
    );

\echo ''
\echo '==================================================================='
\echo 'Test Results Summary'
\echo '==================================================================='

-- Display all test results
SELECT
    test_number,
    test_name,
    status
FROM wkst_test_results
ORDER BY test_number;

-- Summary statistics
\echo ''
\echo 'Summary:'
SELECT
    COUNT(*) as total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') as passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') as failed
FROM wkst_test_results;

-- Check if all tests passed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM wkst_test_results
    WHERE status LIKE 'FAIL%';

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'WKST TEST SUITE FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'WKST TEST SUITE PASSED: All tests passed successfully!';
    END IF;
END $$;

ROLLBACK;
