/**
 * RFC 5545 Time-Level Expansion Tests
 *
 * Tests BYHOUR/BYMINUTE/BYSECOND expansion for WEEKLY, MONTHLY, and YEARLY frequencies
 * as defined in RFC 5545 Section 3.3.10. These combinations act as "Expand" operations.
 *
 * Example: FREQ=WEEKLY;BYDAY=MO,WE,FR;BYHOUR=9,17 generates 6 occurrences per week
 * (3 days × 2 times = Mon 9:00, Mon 17:00, Wed 9:00, Wed 17:00, Fri 9:00, Fri 17:00)
 *
 * Usage:
 *   psql -d your_database -f tests/test_time_expansion.sql
 *
 * Expected output: All tests pass with PASS markers
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
CREATE TEMP TABLE time_expansion_test_results (
    test_number SERIAL PRIMARY KEY,
    test_category TEXT,
    test_name TEXT,
    status TEXT
);

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 1: WEEKLY + Time Expansion'
\echo '====================================================================='

-- Test 1.1: WEEKLY + BYHOUR basic expansion
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'WEEKLY + BYHOUR', 'Basic WEEKLY;BYDAY=MO;BYHOUR=9,17',
    assert_occurrences_equal(
        'WEEKLY + BYHOUR basic',
        ARRAY[
            '2025-01-06 09:00:00'::TIMESTAMP,  -- Mon 9:00
            '2025-01-06 17:00:00'::TIMESTAMP,  -- Mon 17:00
            '2025-01-13 09:00:00'::TIMESTAMP,  -- Mon 9:00
            '2025-01-13 17:00:00'::TIMESTAMP   -- Mon 17:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;BYHOUR=9,17;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 1.2: WEEKLY + multiple days + BYHOUR (cross-product)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'WEEKLY + BYHOUR', 'Cross-product WEEKLY;BYDAY=MO,WE,FR;BYHOUR=9,17',
    assert_occurrences_equal(
        'WEEKLY cross-product 3x2',
        ARRAY[
            '2025-01-06 09:00:00'::TIMESTAMP,  -- Mon 9:00
            '2025-01-06 17:00:00'::TIMESTAMP,  -- Mon 17:00
            '2025-01-08 09:00:00'::TIMESTAMP,  -- Wed 9:00
            '2025-01-08 17:00:00'::TIMESTAMP,  -- Wed 17:00
            '2025-01-10 09:00:00'::TIMESTAMP,  -- Fri 9:00
            '2025-01-10 17:00:00'::TIMESTAMP   -- Fri 17:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO,WE,FR;BYHOUR=9,17;COUNT=6',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 1.3: WEEKLY + BYMINUTE
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'WEEKLY + BYMINUTE', 'Basic WEEKLY;BYDAY=MO;BYMINUTE=0,30',
    assert_occurrences_equal(
        'WEEKLY + BYMINUTE basic',
        ARRAY[
            '2025-01-06 09:00:00'::TIMESTAMP,  -- Mon 09:00
            '2025-01-06 09:30:00'::TIMESTAMP,  -- Mon 09:30
            '2025-01-13 09:00:00'::TIMESTAMP,  -- Mon 09:00
            '2025-01-13 09:30:00'::TIMESTAMP   -- Mon 09:30
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;BYMINUTE=0,30;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 1.4: WEEKLY + BYSECOND
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'WEEKLY + BYSECOND', 'Basic WEEKLY;BYDAY=MO;BYSECOND=0,30',
    assert_occurrences_equal(
        'WEEKLY + BYSECOND basic',
        ARRAY[
            '2025-01-06 09:00:00'::TIMESTAMP,  -- Mon 09:00:00
            '2025-01-06 09:00:30'::TIMESTAMP,  -- Mon 09:00:30
            '2025-01-13 09:00:00'::TIMESTAMP,  -- Mon 09:00:00
            '2025-01-13 09:00:30'::TIMESTAMP   -- Mon 09:00:30
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;BYSECOND=0,30;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 1.5: WEEKLY + BYHOUR + BYMINUTE combined
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'WEEKLY + BYHOUR+BYMINUTE', 'Combined WEEKLY;BYDAY=MO;BYHOUR=9,10;BYMINUTE=0,30',
    assert_occurrences_equal(
        'WEEKLY + BYHOUR + BYMINUTE combined',
        ARRAY[
            '2025-01-06 09:00:00'::TIMESTAMP,  -- Mon 09:00
            '2025-01-06 09:30:00'::TIMESTAMP,  -- Mon 09:30
            '2025-01-06 10:00:00'::TIMESTAMP,  -- Mon 10:00
            '2025-01-06 10:30:00'::TIMESTAMP   -- Mon 10:30
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;BYHOUR=9,10;BYMINUTE=0,30;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 2: MONTHLY + Time Expansion'
\echo '====================================================================='

-- Test 2.1: MONTHLY + BYMONTHDAY + BYHOUR
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'MONTHLY + BYHOUR', 'MONTHLY;BYMONTHDAY=15;BYHOUR=9,17',
    assert_occurrences_equal(
        'MONTHLY + BYMONTHDAY + BYHOUR',
        ARRAY[
            '2025-01-15 09:00:00'::TIMESTAMP,  -- Jan 15 9:00
            '2025-01-15 17:00:00'::TIMESTAMP,  -- Jan 15 17:00
            '2025-02-15 09:00:00'::TIMESTAMP,  -- Feb 15 9:00
            '2025-02-15 17:00:00'::TIMESTAMP   -- Feb 15 17:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=15;BYHOUR=9,17;COUNT=4',
            '2025-01-15 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 2.2: MONTHLY + BYDAY + BYHOUR
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'MONTHLY + BYDAY + BYHOUR', 'MONTHLY;BYDAY=1MO;BYHOUR=9,17',
    assert_occurrences_equal(
        'MONTHLY + BYDAY ordinal + BYHOUR',
        ARRAY[
            '2025-01-06 09:00:00'::TIMESTAMP,  -- 1st Mon Jan 9:00
            '2025-01-06 17:00:00'::TIMESTAMP,  -- 1st Mon Jan 17:00
            '2025-02-03 09:00:00'::TIMESTAMP,  -- 1st Mon Feb 9:00
            '2025-02-03 17:00:00'::TIMESTAMP   -- 1st Mon Feb 17:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYDAY=1MO;BYHOUR=9,17;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 2.3: MONTHLY + BYMINUTE
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'MONTHLY + BYMINUTE', 'MONTHLY;BYMONTHDAY=1;BYMINUTE=0,15,30,45',
    assert_occurrences_equal(
        'MONTHLY + BYMINUTE quarter-hour',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,  -- Jan 1 10:00
            '2025-01-01 10:15:00'::TIMESTAMP,  -- Jan 1 10:15
            '2025-01-01 10:30:00'::TIMESTAMP,  -- Jan 1 10:30
            '2025-01-01 10:45:00'::TIMESTAMP   -- Jan 1 10:45
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=1;BYMINUTE=0,15,30,45;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 2.4: MONTHLY + multiple BYMONTHDAY + BYHOUR (cross-product)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'MONTHLY cross-product', 'MONTHLY;BYMONTHDAY=1,15;BYHOUR=9,17',
    assert_occurrences_equal(
        'MONTHLY cross-product 2x2',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,  -- Jan 1 9:00
            '2025-01-01 17:00:00'::TIMESTAMP,  -- Jan 1 17:00
            '2025-01-15 09:00:00'::TIMESTAMP,  -- Jan 15 9:00
            '2025-01-15 17:00:00'::TIMESTAMP   -- Jan 15 17:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=1,15;BYHOUR=9,17;COUNT=4',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 3: YEARLY + Time Expansion'
\echo '====================================================================='

-- Test 3.1: YEARLY + BYMONTH + BYHOUR
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'YEARLY + BYHOUR', 'YEARLY;BYMONTH=6,12;BYHOUR=10,14',
    assert_occurrences_equal(
        'YEARLY + BYMONTH + BYHOUR',
        ARRAY[
            '2025-06-01 10:00:00'::TIMESTAMP,  -- Jun 10:00
            '2025-06-01 14:00:00'::TIMESTAMP,  -- Jun 14:00
            '2025-12-01 10:00:00'::TIMESTAMP,  -- Dec 10:00
            '2025-12-01 14:00:00'::TIMESTAMP   -- Dec 14:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=6,12;BYHOUR=10,14;COUNT=4',
            '2025-06-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 3.2: YEARLY + BYYEARDAY + BYHOUR
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'YEARLY + BYYEARDAY + BYHOUR', 'YEARLY;BYYEARDAY=1,100;BYHOUR=9,17',
    assert_occurrences_equal(
        'YEARLY + BYYEARDAY + BYHOUR',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,  -- Day 1 9:00 (Jan 1)
            '2025-01-01 17:00:00'::TIMESTAMP,  -- Day 1 17:00
            '2025-04-10 09:00:00'::TIMESTAMP,  -- Day 100 9:00 (Apr 10)
            '2025-04-10 17:00:00'::TIMESTAMP   -- Day 100 17:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYYEARDAY=1,100;BYHOUR=9,17;COUNT=4',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 3.3: YEARLY + BYMONTH + BYMONTHDAY + BYHOUR
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'YEARLY + BYMONTH + BYMONTHDAY + BYHOUR', 'YEARLY;BYMONTH=1;BYMONTHDAY=15;BYHOUR=8,12,18',
    assert_occurrences_equal(
        'YEARLY + BYMONTH + BYMONTHDAY + BYHOUR',
        ARRAY[
            '2025-01-15 08:00:00'::TIMESTAMP,  -- Jan 15 8:00
            '2025-01-15 12:00:00'::TIMESTAMP,  -- Jan 15 12:00
            '2025-01-15 18:00:00'::TIMESTAMP,  -- Jan 15 18:00
            '2026-01-15 08:00:00'::TIMESTAMP   -- Jan 15 next year 8:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=1;BYMONTHDAY=15;BYHOUR=8,12,18;COUNT=4',
            '2025-01-15 08:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 3.4: YEARLY anniversary (no BYxxx) + BYHOUR
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'YEARLY anniversary + BYHOUR', 'YEARLY;BYHOUR=9,17',
    assert_occurrences_equal(
        'YEARLY anniversary + BYHOUR',
        ARRAY[
            '2025-03-15 09:00:00'::TIMESTAMP,  -- Mar 15 9:00
            '2025-03-15 17:00:00'::TIMESTAMP,  -- Mar 15 17:00
            '2026-03-15 09:00:00'::TIMESTAMP,  -- Mar 15 next year 9:00
            '2026-03-15 17:00:00'::TIMESTAMP   -- Mar 15 next year 17:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYHOUR=9,17;COUNT=4',
            '2025-03-15 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 4: BYSETPOS Interaction with Time Expansion'
\echo '====================================================================='

-- Test 4.1: WEEKLY + BYHOUR + BYSETPOS (first and last of expanded set)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'BYSETPOS + time expansion', 'WEEKLY;BYDAY=MO,TU;BYHOUR=9,17;BYSETPOS=1,-1',
    assert_occurrences_equal(
        'WEEKLY + BYHOUR + BYSETPOS=1,-1',
        ARRAY[
            '2025-01-06 09:00:00'::TIMESTAMP,  -- First (Mon 9:00)
            '2025-01-07 17:00:00'::TIMESTAMP,  -- Last (Tue 17:00)
            '2025-01-13 09:00:00'::TIMESTAMP,  -- First (Mon 9:00)
            '2025-01-14 17:00:00'::TIMESTAMP   -- Last (Tue 17:00)
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO,TU;BYHOUR=9,17;BYSETPOS=1,-1;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 4.2: MONTHLY + BYHOUR + BYSETPOS
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'MONTHLY + BYHOUR + BYSETPOS', 'MONTHLY;BYMONTHDAY=1,15;BYHOUR=9,17;BYSETPOS=1',
    assert_occurrences_equal(
        'MONTHLY + BYHOUR + BYSETPOS=1 (first only)',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,  -- First (Jan 1 9:00)
            '2025-02-01 09:00:00'::TIMESTAMP,  -- First (Feb 1 9:00)
            '2025-03-01 09:00:00'::TIMESTAMP,  -- First (Mar 1 9:00)
            '2025-04-01 09:00:00'::TIMESTAMP   -- First (Apr 1 9:00)
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=1,15;BYHOUR=9,17;BYSETPOS=1;COUNT=4',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 4.3: YEARLY + BYHOUR + BYSETPOS
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'YEARLY + BYHOUR + BYSETPOS', 'YEARLY;BYMONTH=1,7;BYHOUR=9,17;BYSETPOS=-1',
    assert_occurrences_equal(
        'YEARLY + BYHOUR + BYSETPOS=-1 (last only)',
        ARRAY[
            '2025-07-01 17:00:00'::TIMESTAMP,  -- Last (Jul 17:00)
            '2026-07-01 17:00:00'::TIMESTAMP,  -- Last (Jul 17:00)
            '2027-07-01 17:00:00'::TIMESTAMP,  -- Last (Jul 17:00)
            '2028-07-01 17:00:00'::TIMESTAMP   -- Last (Jul 17:00)
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=1,7;BYHOUR=9,17;BYSETPOS=-1;COUNT=4',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 4.4: WEEKLY + BYHOUR + BYSETPOS=2 (second slot)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'BYSETPOS=2', 'WEEKLY;BYDAY=MO,TU;BYHOUR=9,17;BYSETPOS=2',
    assert_occurrences_equal(
        'WEEKLY + BYHOUR + BYSETPOS=2 (second only)',
        ARRAY[
            '2025-01-06 17:00:00'::TIMESTAMP,  -- Second (Mon 17:00)
            '2025-01-13 17:00:00'::TIMESTAMP,  -- Second (Mon 17:00)
            '2025-01-20 17:00:00'::TIMESTAMP,  -- Second (Mon 17:00)
            '2025-01-27 17:00:00'::TIMESTAMP   -- Second (Mon 17:00)
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO,TU;BYHOUR=9,17;BYSETPOS=2;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 5: INTERVAL Interaction with Time Expansion'
\echo '====================================================================='

-- Test 5.1: WEEKLY + INTERVAL=2 + BYHOUR (skip every other week)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'WEEKLY + INTERVAL=2 + BYHOUR', 'WEEKLY;INTERVAL=2;BYDAY=MO;BYHOUR=9,17',
    assert_occurrences_equal(
        'WEEKLY + INTERVAL=2 + BYHOUR',
        ARRAY[
            '2025-01-06 09:00:00'::TIMESTAMP,  -- Week 1 Mon 9:00
            '2025-01-06 17:00:00'::TIMESTAMP,  -- Week 1 Mon 17:00
            '2025-01-20 09:00:00'::TIMESTAMP,  -- Week 3 Mon 9:00 (skip week 2)
            '2025-01-20 17:00:00'::TIMESTAMP   -- Week 3 Mon 17:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO;BYHOUR=9,17;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 5.2: MONTHLY + INTERVAL=3 + BYHOUR
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'MONTHLY + INTERVAL=3 + BYHOUR', 'MONTHLY;INTERVAL=3;BYMONTHDAY=15;BYHOUR=9,17',
    assert_occurrences_equal(
        'MONTHLY + INTERVAL=3 + BYHOUR (quarterly)',
        ARRAY[
            '2025-01-15 09:00:00'::TIMESTAMP,  -- Jan 15 9:00
            '2025-01-15 17:00:00'::TIMESTAMP,  -- Jan 15 17:00
            '2025-04-15 09:00:00'::TIMESTAMP,  -- Apr 15 9:00 (skip Feb, Mar)
            '2025-04-15 17:00:00'::TIMESTAMP   -- Apr 15 17:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=15;BYHOUR=9,17;COUNT=4',
            '2025-01-15 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 5.3: YEARLY + INTERVAL=2 + BYHOUR
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'YEARLY + INTERVAL=2 + BYHOUR', 'YEARLY;INTERVAL=2;BYMONTH=6;BYHOUR=10,14',
    assert_occurrences_equal(
        'YEARLY + INTERVAL=2 + BYHOUR (biennial)',
        ARRAY[
            '2025-06-01 10:00:00'::TIMESTAMP,  -- 2025 Jun 10:00
            '2025-06-01 14:00:00'::TIMESTAMP,  -- 2025 Jun 14:00
            '2027-06-01 10:00:00'::TIMESTAMP,  -- 2027 Jun 10:00 (skip 2026)
            '2027-06-01 14:00:00'::TIMESTAMP   -- 2027 Jun 14:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;INTERVAL=2;BYMONTH=6;BYHOUR=10,14;COUNT=4',
            '2025-06-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 6: Edge Cases'
\echo '====================================================================='

-- Test 6.1: Deduplication (duplicate BYHOUR values)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Deduplication', 'WEEKLY;BYDAY=MO;BYHOUR=9,9,10 (deduplicated)',
    assert_occurrences_equal(
        'BYHOUR deduplication',
        ARRAY[
            '2025-01-06 09:00:00'::TIMESTAMP,  -- Mon 9:00 (only once!)
            '2025-01-06 10:00:00'::TIMESTAMP   -- Mon 10:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;BYHOUR=9,9,10;COUNT=2',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 6.2: Midnight expansion (BYHOUR=0)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Midnight', 'WEEKLY;BYDAY=MO;BYHOUR=0,12',
    assert_occurrences_equal(
        'BYHOUR=0 (midnight)',
        ARRAY[
            '2025-01-06 00:00:00'::TIMESTAMP,  -- Mon midnight
            '2025-01-06 12:00:00'::TIMESTAMP,  -- Mon noon
            '2025-01-13 00:00:00'::TIMESTAMP,  -- Mon midnight
            '2025-01-13 12:00:00'::TIMESTAMP   -- Mon noon
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;BYHOUR=0,12;COUNT=4',
            '2025-01-06 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 6.3: Single time filter preserves time
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Single BYHOUR', 'WEEKLY;BYDAY=MO;BYHOUR=14',
    assert_occurrences_equal(
        'Single BYHOUR=14',
        ARRAY[
            '2025-01-06 14:00:00'::TIMESTAMP,  -- Mon 14:00
            '2025-01-13 14:00:00'::TIMESTAMP,  -- Mon 14:00
            '2025-01-20 14:00:00'::TIMESTAMP,  -- Mon 14:00
            '2025-01-27 14:00:00'::TIMESTAMP   -- Mon 14:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;BYHOUR=14;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 6.4: Empty expansion (BYHOUR outside valid range is ignored gracefully)
-- BYHOUR values are validated 0-23, so this tests reasonable expansion
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Full day range', 'WEEKLY;BYDAY=MO;BYHOUR=0,23',
    assert_occurrences_equal(
        'BYHOUR=0,23 (boundary hours)',
        ARRAY[
            '2025-01-06 00:00:00'::TIMESTAMP,  -- Mon 00:00
            '2025-01-06 23:00:00'::TIMESTAMP,  -- Mon 23:00
            '2025-01-13 00:00:00'::TIMESTAMP,  -- Mon 00:00
            '2025-01-13 23:00:00'::TIMESTAMP   -- Mon 23:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;BYHOUR=0,23;COUNT=4',
            '2025-01-06 00:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 6.5: Large cross-product (3 days × 3 hours = 9 slots)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Large cross-product', 'WEEKLY;BYDAY=MO,TU,WE;BYHOUR=9,12,15 (9 slots)',
    assert_true(
        'WEEKLY 3x3 cross-product = 9 results',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO,TU,WE;BYHOUR=9,12,15;COUNT=9',
            '2025-01-06 09:00:00'::TIMESTAMP
        )) = 9
    );

-- Test 6.6: No time filters preserves dtstart time
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'No time filters', 'WEEKLY;BYDAY=MO (no time expansion)',
    assert_occurrences_equal(
        'No BYHOUR preserves dtstart time',
        ARRAY[
            '2025-01-06 14:30:00'::TIMESTAMP,  -- Mon at dtstart time
            '2025-01-13 14:30:00'::TIMESTAMP,  -- Mon at dtstart time
            '2025-01-20 14:30:00'::TIMESTAMP,  -- Mon at dtstart time
            '2025-01-27 14:30:00'::TIMESTAMP   -- Mon at dtstart time
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;COUNT=4',
            '2025-01-06 14:30:00'::TIMESTAMP
        ) AS occurrence)
    );

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 7: Regression Tests (DAILY + time filters still works)'
\echo '====================================================================='

-- Test 7.1: DAILY + BYHOUR still works
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'DAILY regression', 'DAILY;BYHOUR=9,17 (existing functionality)',
    assert_occurrences_equal(
        'DAILY + BYHOUR regression',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,  -- Jan 1 9:00
            '2025-01-01 17:00:00'::TIMESTAMP,  -- Jan 1 17:00
            '2025-01-02 09:00:00'::TIMESTAMP,  -- Jan 2 9:00
            '2025-01-02 17:00:00'::TIMESTAMP   -- Jan 2 17:00
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;BYHOUR=9,17;COUNT=4',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 7.2: DAILY + BYDAY + BYHOUR still works
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'DAILY + BYDAY regression', 'DAILY;BYDAY=MO,WE,FR;BYHOUR=9',
    assert_occurrences_equal(
        'DAILY + BYDAY + BYHOUR regression',
        ARRAY[
            '2025-01-06 09:00:00'::TIMESTAMP,  -- Mon
            '2025-01-08 09:00:00'::TIMESTAMP,  -- Wed
            '2025-01-10 09:00:00'::TIMESTAMP,  -- Fri
            '2025-01-13 09:00:00'::TIMESTAMP   -- Mon
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;BYDAY=MO,WE,FR;BYHOUR=9;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 7.3: DAILY + BYSETPOS still works
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'DAILY + BYSETPOS regression', 'DAILY;BYHOUR=9,12,17;BYSETPOS=1,-1',
    assert_occurrences_equal(
        'DAILY + BYSETPOS regression',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,  -- First (9:00)
            '2025-01-01 17:00:00'::TIMESTAMP,  -- Last (17:00)
            '2025-01-02 09:00:00'::TIMESTAMP,  -- First (9:00)
            '2025-01-02 17:00:00'::TIMESTAMP   -- Last (17:00)
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;BYHOUR=9,12,17;BYSETPOS=1,-1;COUNT=4',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 7.4: DAILY without time filters still works
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'DAILY no time filters', 'DAILY (no time filters)',
    assert_occurrences_equal(
        'DAILY without BYHOUR regression',
        ARRAY[
            '2025-01-01 10:30:00'::TIMESTAMP,  -- Jan 1 at dtstart time
            '2025-01-02 10:30:00'::TIMESTAMP,  -- Jan 2 at dtstart time
            '2025-01-03 10:30:00'::TIMESTAMP,  -- Jan 3 at dtstart time
            '2025-01-04 10:30:00'::TIMESTAMP   -- Jan 4 at dtstart time
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=DAILY;COUNT=4',
            '2025-01-01 10:30:00'::TIMESTAMP
        ) AS occurrence)
    );

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 8: TIMESTAMPTZ API Parity'
\echo '====================================================================='

-- Test 8.1: TIMESTAMPTZ API with WEEKLY + BYHOUR
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'TIMESTAMPTZ API', 'WEEKLY;BYDAY=MO;BYHOUR=9,17 with timezone param',
    assert_true(
        'TIMESTAMPTZ API returns 4 results',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;BYHOUR=9,17;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMPTZ,
            'America/New_York'
        )) = 4
    );

-- Test 8.2: TIMESTAMPTZ API with MONTHLY + BYHOUR
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'TIMESTAMPTZ API MONTHLY', 'MONTHLY;BYMONTHDAY=15;BYHOUR=9,17 with timezone',
    assert_true(
        'TIMESTAMPTZ MONTHLY + BYHOUR returns 4 results',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=15;BYHOUR=9,17;COUNT=4',
            '2025-01-15 09:00:00'::TIMESTAMPTZ,
            'Europe/London'
        )) = 4
    );

-- Test 8.3: TIMESTAMPTZ API with YEARLY + BYHOUR
-- Note: dtstart must be early enough in target timezone to catch expansion times
-- '2025-06-01 00:00:00 Asia/Tokyo' = '2025-05-31 15:00:00 UTC'
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'TIMESTAMPTZ API YEARLY', 'YEARLY;BYMONTH=6;BYHOUR=10,14 with timezone',
    assert_true(
        'TIMESTAMPTZ YEARLY + BYHOUR returns 4 results',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=6;BYHOUR=10,14;COUNT=4',
            '2025-05-31 15:00:00'::TIMESTAMPTZ,  -- midnight JST on June 1
            'Asia/Tokyo'
        )) = 4
    );

-- Test 8.4: TIMESTAMP and TIMESTAMPTZ produce same wall-clock times
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'API parity', 'TIMESTAMP vs TIMESTAMPTZ same wall-clock times',
    assert_true(
        'TIMESTAMP and TIMESTAMPTZ APIs produce matching results',
        (SELECT array_agg(occurrence::TIME ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;BYHOUR=9,17;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence) =
        (SELECT array_agg((occurrence AT TIME ZONE 'UTC')::TIME ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO;BYHOUR=9,17;COUNT=4',
            '2025-01-06 09:00:00'::TIMESTAMPTZ,
            'UTC'
        ) AS occurrence)
    );

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 9: Previously Rejected Rules Now Work'
\echo '====================================================================='

-- Test 9.1: BYHOUR with WEEKLY now works (was rejected)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Validation removed', 'BYHOUR with WEEKLY now accepted',
    assert_true(
        'BYHOUR + WEEKLY no longer raises exception',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=WEEKLY;BYHOUR=9;COUNT=3',
            '2025-01-06 09:00:00'::TIMESTAMP
        )) = 3
    );

-- Test 9.2: BYHOUR with MONTHLY now works (was rejected)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Validation removed', 'BYHOUR with MONTHLY now accepted',
    assert_true(
        'BYHOUR + MONTHLY no longer raises exception',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=MONTHLY;BYHOUR=9;COUNT=3',
            '2025-01-01 09:00:00'::TIMESTAMP
        )) = 3
    );

-- Test 9.3: BYHOUR with YEARLY now works (was rejected)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Validation removed', 'BYHOUR with YEARLY now accepted',
    assert_true(
        'BYHOUR + YEARLY no longer raises exception',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=YEARLY;BYHOUR=9;COUNT=3',
            '2025-01-01 09:00:00'::TIMESTAMP
        )) = 3
    );

-- Test 9.4: BYMINUTE with MONTHLY now works (was rejected)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Validation removed', 'BYMINUTE with MONTHLY now accepted',
    assert_true(
        'BYMINUTE + MONTHLY no longer raises exception',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=MONTHLY;BYMINUTE=30;COUNT=3',
            '2025-01-01 10:30:00'::TIMESTAMP
        )) = 3
    );

-- Test 9.5: BYSECOND with YEARLY now works (was rejected)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Validation removed', 'BYSECOND with YEARLY now accepted',
    assert_true(
        'BYSECOND + YEARLY no longer raises exception',
        (SELECT COUNT(*) FROM rrule."all"(
            'FREQ=YEARLY;BYSECOND=0;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        )) = 3
    );

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 10: Complex Combined Scenarios'
\echo '====================================================================='

-- Test 10.1: Workday morning standup (WEEKLY + BYDAY + BYHOUR)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Real-world scenario', 'Workday 9am standup',
    assert_occurrences_equal(
        'Workday standup MWF 9am',
        ARRAY[
            '2025-01-06 09:00:00'::TIMESTAMP,  -- Mon
            '2025-01-08 09:00:00'::TIMESTAMP,  -- Wed
            '2025-01-10 09:00:00'::TIMESTAMP,  -- Fri
            '2025-01-13 09:00:00'::TIMESTAMP,  -- Mon
            '2025-01-15 09:00:00'::TIMESTAMP   -- Wed
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=WEEKLY;BYDAY=MO,WE,FR;BYHOUR=9;COUNT=5',
            '2025-01-06 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 10.2: Monthly billing reminders (MONTHLY + BYMONTHDAY + BYHOUR)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Real-world scenario', 'Monthly billing 1st and 15th at 9am and 5pm',
    assert_occurrences_equal(
        'Monthly billing reminders',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,  -- Jan 1 9am
            '2025-01-01 17:00:00'::TIMESTAMP,  -- Jan 1 5pm
            '2025-01-15 09:00:00'::TIMESTAMP,  -- Jan 15 9am
            '2025-01-15 17:00:00'::TIMESTAMP,  -- Jan 15 5pm
            '2025-02-01 09:00:00'::TIMESTAMP,  -- Feb 1 9am
            '2025-02-01 17:00:00'::TIMESTAMP   -- Feb 1 5pm
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=1,15;BYHOUR=9,17;COUNT=6',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    );

-- Test 10.3: Annual review meetings (YEARLY + BYMONTH + BYHOUR)
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Real-world scenario', 'Annual Q2/Q4 reviews at 10am and 2pm',
    assert_occurrences_equal(
        'Annual review meetings',
        ARRAY[
            '2025-06-15 10:00:00'::TIMESTAMP,  -- Q2 10am
            '2025-06-15 14:00:00'::TIMESTAMP,  -- Q2 2pm
            '2025-12-15 10:00:00'::TIMESTAMP,  -- Q4 10am
            '2025-12-15 14:00:00'::TIMESTAMP   -- Q4 2pm
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
            'FREQ=YEARLY;BYMONTH=6,12;BYMONTHDAY=15;BYHOUR=10,14;COUNT=4',
            '2025-06-15 10:00:00'::TIMESTAMP
        ) AS occurrence)
    );

\echo ''
\echo '====================================================================='
\echo 'TEST GROUP 11: Internal Expansion Helper Coverage'
\echo '====================================================================='

-- Test 11.1: rrule_expand_dates_with_times no-time path honors max_results
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Internal helper', 'No-time path with max_results=1 returns first date only',
    assert_occurrences_equal(
        'expand_dates_with_times no-time + limit',
        ARRAY['2025-01-06 10:00:00'::TIMESTAMP],
        (
            SELECT array_agg(x::TIMESTAMP ORDER BY x)
            FROM rrule.rrule_expand_dates_with_times(
                ARRAY['2025-01-06 10:00:00+00'::TIMESTAMPTZ, '2025-01-08 10:00:00+00'::TIMESTAMPTZ],
                rrule.parse_rrule_parts('2025-01-06 10:00:00+00'::TIMESTAMPTZ, 'FREQ=DAILY;COUNT=5'),
                1
            ) x
        )
    );

-- Test 11.2: rrule_expand_dates_with_times no-time + BYSETPOS cursor path
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Internal helper', 'No-time + BYSETPOS path selects first sorted date',
    assert_occurrences_equal(
        'expand_dates_with_times no-time + bysetpos',
        ARRAY['2025-01-06 10:00:00'::TIMESTAMP],
        (
            SELECT array_agg(x::TIMESTAMP ORDER BY x)
            FROM rrule.rrule_expand_dates_with_times(
                ARRAY['2025-01-06 10:00:00+00'::TIMESTAMPTZ, '2025-01-08 10:00:00+00'::TIMESTAMPTZ],
                rrule.parse_rrule_parts('2025-01-06 10:00:00+00'::TIMESTAMPTZ, 'FREQ=DAILY;BYDAY=MO;BYSETPOS=1;COUNT=5'),
                NULL
            ) x
        )
    );

-- Test 11.3: rrule_expand_dates_with_times time-expansion path
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Internal helper', 'Time-expansion path returns BYHOUR cross-product',
    assert_occurrences_equal(
        'expand_dates_with_times time expansion',
        ARRAY[
            '2025-01-06 09:00:00'::TIMESTAMP,
            '2025-01-06 17:00:00'::TIMESTAMP
        ],
        (
            SELECT array_agg(x::TIMESTAMP ORDER BY x)
            FROM rrule.rrule_expand_dates_with_times(
                ARRAY['2025-01-06 10:00:00+00'::TIMESTAMPTZ],
                rrule.parse_rrule_parts('2025-01-06 10:00:00+00'::TIMESTAMPTZ, 'FREQ=DAILY;BYHOUR=9,17;COUNT=5'),
                NULL
            ) x
        )
    );

-- Test 11.4: rrule_expand_dates_with_times time-expansion + BYSETPOS path
INSERT INTO time_expansion_test_results (test_category, test_name, status)
SELECT 'Internal helper', 'Time-expansion + BYSETPOS keeps last slot',
    assert_occurrences_equal(
        'expand_dates_with_times time + bysetpos',
        ARRAY['2025-01-06 17:00:00'::TIMESTAMP],
        (
            SELECT array_agg(x::TIMESTAMP ORDER BY x)
            FROM rrule.rrule_expand_dates_with_times(
                ARRAY['2025-01-06 10:00:00+00'::TIMESTAMPTZ],
                rrule.parse_rrule_parts('2025-01-06 10:00:00+00'::TIMESTAMPTZ, 'FREQ=DAILY;BYHOUR=9,17;BYSETPOS=-1;COUNT=5'),
                NULL
            ) x
        )
    );

\echo ''
\echo '====================================================================='
\echo 'Test Results Summary'
\echo '====================================================================='

-- Display all results
SELECT test_number, test_category, test_name, status
FROM time_expansion_test_results
ORDER BY test_number;

-- Final summary
SELECT
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') AS passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') AS failed,
    COUNT(*) AS total
FROM time_expansion_test_results;

-- Fail if any tests failed
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM time_expansion_test_results
    WHERE status LIKE 'FAIL%';

    IF failed_count > 0 THEN
        RAISE EXCEPTION '% test(s) failed', failed_count;
    END IF;
END $$;

ROLLBACK;
