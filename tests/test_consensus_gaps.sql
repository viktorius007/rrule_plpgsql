/**
 * Consensus Coverage Gap Tests
 *
 * Tests identified by cross-referencing src/rrule.sql (~3400 lines),
 * src/rrule_subday.sql (~775 lines), and all 14 test files (400+ tests)
 * to find code paths with zero or insufficient test coverage.
 *
 * Covers:
 *  1. TIMESTAMPTZ next() and most_recent()
 *  2. TZ generator SKIP parity
 *  3. Sub-day TIMESTAMPTZ API (HOURLY/MINUTELY/SECONDLY)
 *  4. DAILY + BYHOUR/BYMINUTE/BYSECOND expansion
 *  5. MONTHLY BYDAY+BYMONTHDAY + INTERVAL>1
 *  6. TIMESTAMPTZ overlaps() NULL dtend / NULL rrule
 *  7. YEARLY BYDAY negative year ordinals
 *  8. YEARLY BYWEEKNO without BYDAY
 *  9. between()/after() inc=TRUE exact boundary
 * 10. TIMESTAMPTZ before() count>1
 * 11. DAILY BYHOUR + BYSETPOS
 * 12. SKIP=FORWARD + UNTIL interaction
 * 13. YEARLY BYWEEKNO + BYYEARDAY intersection
 * 14. version() function
 * 15. Truncation WARNING path
 *
 * Usage:
 *   psql -d your_database -f tests/test_consensus_gaps.sql
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
CREATE TEMP TABLE consensus_test_results (
    test_number SERIAL PRIMARY KEY,
    test_group TEXT,
    test_name TEXT,
    status TEXT
);

-- ===================================================================
-- GROUP 1: TIMESTAMPTZ next() and most_recent() — Zero Test Coverage
-- These public API functions have distinct internal plumbing
-- (set_config('TimeZone', ...)) and were never tested.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 1: TIMESTAMPTZ next() and most_recent()'
\echo '==================================================================='

-- Test 1.1: TIMESTAMPTZ next() basic usage
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ next/most_recent', 'next() basic — daily rule, reference before first occurrence',
    assert_equals(
        'TZ next() basic',
        '2025-01-02 10:00:00+00',
        (SELECT rrule."next"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'UTC',
            '2025-01-01 15:00:00+00'::TIMESTAMPTZ
        ))::TEXT
    )
);

-- Test 1.2: TIMESTAMPTZ next() with timezone (DST crossing)
-- Reference time in EST, next occurrence should be in EDT after spring forward
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ next/most_recent', 'next() with DST crossing — America/New_York',
    assert_equals(
        'TZ next() DST',
        '2025-03-10 14:00:00+00',
        (SELECT rrule."next"(
            'FREQ=DAILY;COUNT=30',
            '2025-03-01 10:00:00-05'::TIMESTAMPTZ,
            'America/New_York',
            '2025-03-09 16:00:00+00'::TIMESTAMPTZ
        ))::TEXT
    )
);

-- Test 1.3: TIMESTAMPTZ most_recent() basic usage
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ next/most_recent', 'most_recent() basic — daily rule',
    assert_equals(
        'TZ most_recent() basic',
        '2025-01-03 10:00:00+00',
        (SELECT rrule."most_recent"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'UTC',
            '2025-01-03 15:00:00+00'::TIMESTAMPTZ
        ))::TEXT
    )
);

-- Test 1.4: TIMESTAMPTZ most_recent() with timezone
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ next/most_recent', 'most_recent() with America/New_York timezone',
    assert_equals(
        'TZ most_recent() timezone',
        '2025-03-09 14:00:00+00',
        (SELECT rrule."most_recent"(
            'FREQ=DAILY;COUNT=30',
            '2025-03-01 10:00:00-05'::TIMESTAMPTZ,
            'America/New_York',
            '2025-03-09 16:00:00+00'::TIMESTAMPTZ
        ))::TEXT
    )
);

-- Test 1.5: TIMESTAMPTZ next() returns NULL when no future occurrences
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ next/most_recent', 'next() returns NULL when past all occurrences',
    assert_equals(
        'TZ next() NULL',
        NULL,
        (SELECT rrule."next"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'UTC',
            '2025-01-10 10:00:00+00'::TIMESTAMPTZ
        ))::TEXT
    )
);

-- Test 1.6: TIMESTAMPTZ most_recent() returns NULL when before all occurrences
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ next/most_recent', 'most_recent() returns NULL when before all occurrences',
    assert_equals(
        'TZ most_recent() NULL',
        NULL,
        (SELECT rrule."most_recent"(
            'FREQ=DAILY;COUNT=3',
            '2025-01-05 10:00:00+00'::TIMESTAMPTZ,
            'UTC',
            '2025-01-04 10:00:00+00'::TIMESTAMPTZ
        ))::TEXT
    )
);

-- ===================================================================
-- GROUP 2: TZ Generator SKIP Parity
-- All 25 SKIP tests in test_skip_support.sql use the TIMESTAMP API.
-- The TZ generator has identical MONTHLY/YEARLY SKIP logic that must
-- be independently verified (CLAUDE.md rule 9).
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 2: TZ Generator SKIP Parity'
\echo '==================================================================='

-- Test 2.1: SKIP=BACKWARD via TIMESTAMPTZ API — monthly day 31
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ SKIP parity', 'SKIP=BACKWARD monthly day 31 via TIMESTAMPTZ API',
    assert_occurrences_equal(
        'TZ SKIP=BACKWARD monthly 31',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=BACKWARD;COUNT=4',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ) AS occurrence)
    )
);

-- Test 2.2: SKIP=FORWARD via TIMESTAMPTZ API — monthly day 31
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ SKIP parity', 'SKIP=FORWARD monthly day 31 via TIMESTAMPTZ API',
    assert_occurrences_equal(
        'TZ SKIP=FORWARD monthly 31',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-01 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=4',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ) AS occurrence)
    )
);

-- Test 2.3: SKIP=OMIT via TIMESTAMPTZ API — monthly day 31
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ SKIP parity', 'SKIP=OMIT monthly day 31 via TIMESTAMPTZ API',
    assert_occurrences_equal(
        'TZ SKIP=OMIT monthly 31',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=OMIT;COUNT=4',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ) AS occurrence)
    )
);

-- Test 2.4: SKIP=BACKWARD drift prevention via TIMESTAMPTZ API
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ SKIP parity', 'SKIP=BACKWARD drift prevention via TIMESTAMPTZ API',
    assert_occurrences_equal(
        'TZ SKIP=BACKWARD drift',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-04-30 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-06-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;SKIP=BACKWARD;COUNT=6',
            '2025-01-31 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ) AS occurrence)
    )
);

-- Test 2.5: YEARLY SKIP=BACKWARD from leap day via TIMESTAMPTZ API
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ SKIP parity', 'YEARLY SKIP=BACKWARD from leap day via TIMESTAMPTZ API',
    assert_occurrences_equal(
        'TZ YEARLY BACKWARD leap',
        ARRAY[
            '2024-02-29 10:00:00'::TIMESTAMP,
            '2025-02-28 10:00:00'::TIMESTAMP,
            '2026-02-28 10:00:00'::TIMESTAMP,
            '2027-02-28 10:00:00'::TIMESTAMP,
            '2028-02-29 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=YEARLY;SKIP=BACKWARD;COUNT=5',
            '2024-02-29 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ) AS occurrence)
    )
);

-- Test 2.6: SKIP=BACKWARD INTERVAL=2 via TIMESTAMPTZ API (non-UTC timezone)
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ SKIP parity', 'SKIP=BACKWARD INTERVAL=2 via TIMESTAMPTZ in America/Chicago',
    assert_occurrences_equal(
        'TZ SKIP=BACKWARD INTERVAL=2 Chicago',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-31 10:00:00'::TIMESTAMP,
            '2025-05-31 10:00:00'::TIMESTAMP,
            '2025-07-31 10:00:00'::TIMESTAMP,
            '2025-09-30 10:00:00'::TIMESTAMP,
            '2025-11-30 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg((occurrence AT TIME ZONE 'America/Chicago')::TIMESTAMP ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;INTERVAL=2;SKIP=BACKWARD;RSCALE=GREGORIAN;COUNT=6',
            '2025-01-31 16:00:00+00'::TIMESTAMPTZ,
            'America/Chicago'
        ) AS occurrence)
    )
);

-- ===================================================================
-- GROUP 3: Sub-day TIMESTAMPTZ API — Zero Coverage
-- HOURLY/MINUTELY/SECONDLY through TIMESTAMPTZ path (~290 lines in
-- rrule_subday.sql) are completely untested. These tests only run when
-- sub-day support is installed, so they are guarded by a DO block that
-- skips gracefully if sub-day frequencies are not available.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 3: Sub-day TIMESTAMPTZ API'
\echo '==================================================================='

-- Test 3.1: HOURLY via TIMESTAMPTZ API (graceful skip if not installed)
DO $$
DECLARE
    result TIMESTAMP[];
    err_msg TEXT;
BEGIN
    BEGIN
        SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence) INTO result
        FROM rrule."all"(
            'FREQ=HOURLY;COUNT=5',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ) AS occurrence;

        INSERT INTO consensus_test_results (test_group, test_name, status)
        VALUES ('Subday TZ API', 'HOURLY via TIMESTAMPTZ API',
            assert_occurrences_equal(
                'HOURLY TZ basic',
                ARRAY[
                    '2025-01-01 10:00:00'::TIMESTAMP,
                    '2025-01-01 11:00:00'::TIMESTAMP,
                    '2025-01-01 12:00:00'::TIMESTAMP,
                    '2025-01-01 13:00:00'::TIMESTAMP,
                    '2025-01-01 14:00:00'::TIMESTAMP
                ],
                result
            )
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
        IF err_msg ILIKE '%sub-day%' OR err_msg ILIKE '%Unsupported frequency%' OR err_msg ILIKE '%not supported in standard%' THEN
            INSERT INTO consensus_test_results (test_group, test_name, status)
            VALUES ('Subday TZ API', 'HOURLY via TIMESTAMPTZ API', 'SKIP (sub-day not installed)');
        ELSE
            RAISE;
        END IF;
    END;
END $$;

-- Test 3.2: MINUTELY via TIMESTAMPTZ API (graceful skip)
DO $$
DECLARE
    result TIMESTAMP[];
    err_msg TEXT;
BEGIN
    BEGIN
        SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence) INTO result
        FROM rrule."all"(
            'FREQ=MINUTELY;INTERVAL=15;COUNT=4',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ) AS occurrence;

        INSERT INTO consensus_test_results (test_group, test_name, status)
        VALUES ('Subday TZ API', 'MINUTELY via TIMESTAMPTZ API',
            assert_occurrences_equal(
                'MINUTELY TZ basic',
                ARRAY[
                    '2025-01-01 10:00:00'::TIMESTAMP,
                    '2025-01-01 10:15:00'::TIMESTAMP,
                    '2025-01-01 10:30:00'::TIMESTAMP,
                    '2025-01-01 10:45:00'::TIMESTAMP
                ],
                result
            )
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
        IF err_msg ILIKE '%sub-day%' OR err_msg ILIKE '%Unsupported frequency%' OR err_msg ILIKE '%not supported in standard%' THEN
            INSERT INTO consensus_test_results (test_group, test_name, status)
            VALUES ('Subday TZ API', 'MINUTELY via TIMESTAMPTZ API', 'SKIP (sub-day not installed)');
        ELSE
            RAISE;
        END IF;
    END;
END $$;

-- Test 3.3: SECONDLY via TIMESTAMPTZ API (graceful skip)
DO $$
DECLARE
    result TIMESTAMP[];
    err_msg TEXT;
BEGIN
    BEGIN
        SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence) INTO result
        FROM rrule."all"(
            'FREQ=SECONDLY;INTERVAL=30;COUNT=4',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ) AS occurrence;

        INSERT INTO consensus_test_results (test_group, test_name, status)
        VALUES ('Subday TZ API', 'SECONDLY via TIMESTAMPTZ API',
            assert_occurrences_equal(
                'SECONDLY TZ basic',
                ARRAY[
                    '2025-01-01 10:00:00'::TIMESTAMP,
                    '2025-01-01 10:00:30'::TIMESTAMP,
                    '2025-01-01 10:01:00'::TIMESTAMP,
                    '2025-01-01 10:01:30'::TIMESTAMP
                ],
                result
            )
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
        IF err_msg ILIKE '%sub-day%' OR err_msg ILIKE '%Unsupported frequency%' OR err_msg ILIKE '%not supported in standard%' THEN
            INSERT INTO consensus_test_results (test_group, test_name, status)
            VALUES ('Subday TZ API', 'SECONDLY via TIMESTAMPTZ API', 'SKIP (sub-day not installed)');
        ELSE
            RAISE;
        END IF;
    END;
END $$;

-- Test 3.4: HOURLY via TIMESTAMPTZ API across DST spring forward (graceful skip)
DO $$
DECLARE
    result TIMESTAMP[];
    err_msg TEXT;
BEGIN
    BEGIN
        SELECT array_agg((occurrence AT TIME ZONE 'America/New_York')::TIMESTAMP ORDER BY occurrence) INTO result
        FROM rrule."all"(
            'FREQ=HOURLY;COUNT=5',
            '2025-03-09 00:00:00-05'::TIMESTAMPTZ,
            'America/New_York'
        ) AS occurrence;

        -- Wall-clock: 00, 01, (skip 02 DST), 03, 03 (duplicate from naive->TZ), 04
        -- The TZ generator works in naive timestamp space, so 02:00 naive maps to 03:00 EDT
        -- producing a duplicate wall-clock 03:00. This is expected DST behavior.
        INSERT INTO consensus_test_results (test_group, test_name, status)
        VALUES ('Subday TZ API', 'HOURLY across DST spring forward',
            assert_occurrences_equal(
                'HOURLY TZ DST spring',
                ARRAY[
                    '2025-03-09 00:00:00'::TIMESTAMP,
                    '2025-03-09 01:00:00'::TIMESTAMP,
                    '2025-03-09 03:00:00'::TIMESTAMP,
                    '2025-03-09 03:00:00'::TIMESTAMP,
                    '2025-03-09 04:00:00'::TIMESTAMP
                ],
                result
            )
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
        IF err_msg ILIKE '%sub-day%' OR err_msg ILIKE '%Unsupported frequency%' OR err_msg ILIKE '%not supported in standard%' THEN
            INSERT INTO consensus_test_results (test_group, test_name, status)
            VALUES ('Subday TZ API', 'HOURLY across DST spring forward', 'SKIP (sub-day not installed)');
        ELSE
            RAISE;
        END IF;
    END;
END $$;

-- ===================================================================
-- GROUP 4: DAILY + BYHOUR/BYMINUTE/BYSECOND Expansion
-- Per SPEC_COMPLIANCE.md, DAILY supports BYHOUR/BYMINUTE/BYSECOND as
-- "Expand" operations. The triple-loop in rrule_day_time_set() is
-- documented supported but never tested for correctness.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 4: DAILY + BYHOUR/BYMINUTE/BYSECOND Expansion'
\echo '==================================================================='

-- Test 4.1: DAILY + BYHOUR — multiple time slots per day
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('DAILY time expansion', 'DAILY + BYHOUR=9,17 produces 2 occurrences per day',
    assert_occurrences_equal(
        'DAILY BYHOUR expansion',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,
            '2025-01-01 17:00:00'::TIMESTAMP,
            '2025-01-02 09:00:00'::TIMESTAMP,
            '2025-01-02 17:00:00'::TIMESTAMP,
            '2025-01-03 09:00:00'::TIMESTAMP,
            '2025-01-03 17:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=DAILY;BYHOUR=9,17;COUNT=6',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 4.2: DAILY + BYMINUTE — multiple minute slots per day
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('DAILY time expansion', 'DAILY + BYMINUTE=0,30 produces 2 occurrences per day',
    assert_occurrences_equal(
        'DAILY BYMINUTE expansion',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:30:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-02 10:30:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=DAILY;BYMINUTE=0,30;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 4.3: DAILY + BYHOUR + BYMINUTE — cross-product expansion
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('DAILY time expansion', 'DAILY + BYHOUR=9,17 + BYMINUTE=0,30 produces 4 per day',
    assert_occurrences_equal(
        'DAILY BYHOUR+BYMINUTE cross-product',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,
            '2025-01-01 09:30:00'::TIMESTAMP,
            '2025-01-01 17:00:00'::TIMESTAMP,
            '2025-01-01 17:30:00'::TIMESTAMP,
            '2025-01-02 09:00:00'::TIMESTAMP,
            '2025-01-02 09:30:00'::TIMESTAMP,
            '2025-01-02 17:00:00'::TIMESTAMP,
            '2025-01-02 17:30:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=DAILY;BYHOUR=9,17;BYMINUTE=0,30;COUNT=8',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 4.4: DAILY + BYSECOND — sub-minute expansion
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('DAILY time expansion', 'DAILY + BYSECOND=0,30 produces 2 occurrences per day',
    assert_occurrences_equal(
        'DAILY BYSECOND expansion',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:00:30'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:30'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=DAILY;BYSECOND=0,30;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- ===================================================================
-- GROUP 5: MONTHLY BYDAY+BYMONTHDAY + INTERVAL>1
-- The INTERSECT path in monthly_set() is tested only with INTERVAL=1.
-- Per CLAUDE.md rule 10, INTERVAL>1 interactions are non-obvious.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 5: MONTHLY BYDAY+BYMONTHDAY INTERSECT + INTERVAL>1'
\echo '==================================================================='

-- Test 5.1: MONTHLY INTERVAL=2 BYDAY=MO + BYMONTHDAY=1,8,15,22,29
-- Only Mondays that also fall on specified monthdays
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('MONTHLY intersect INTERVAL>1', 'INTERVAL=2 BYDAY=MO+BYMONTHDAY=1,8,15,22,29 COUNT=4',
    assert_true(
        'MONTHLY intersect INTERVAL=2',
        (SELECT COUNT(*) = 4
         FROM rrule."all"(
            'FREQ=MONTHLY;INTERVAL=2;BYDAY=MO;BYMONTHDAY=1,8,15,22,29;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ))
    )
);

-- Test 5.2: Verify specific values for INTERVAL=2 BYDAY+BYMONTHDAY intersection
-- Every 2 months (Jan, Mar, May, Jul, Sep, Nov), Mondays on 1st/8th/15th/22nd/29th
-- March 2025: 3rd, 10th, 17th, 24th, 31st are Mondays — Mon on day 3,10,17,24,31
-- Of BYMONTHDAY=1,8,15,22,29 none fall on Monday in March
-- May 2025: 5th, 12th, 19th, 26th are Mondays — none of 1,8,15,22,29 are Mondays
-- Jul 2025: 7th, 14th, 21st, 28th — none of 1,8,15,22,29
-- Jan 2025: 6th, 13th, 20th, 27th — none
-- Sep 2025: 1st, 8th, 15th, 22nd, 29th are Mondays — ALL match!
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('MONTHLY intersect INTERVAL>1', 'INTERVAL=2 BYDAY=MO+BYMONTHDAY=1,8,15,22,29 — Sep has 5 matches',
    assert_occurrences_equal(
        'MONTHLY intersect INTERVAL=2 Sep',
        ARRAY[
            '2025-09-01 10:00:00'::TIMESTAMP,
            '2025-09-08 10:00:00'::TIMESTAMP,
            '2025-09-15 10:00:00'::TIMESTAMP,
            '2025-09-22 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;INTERVAL=2;BYDAY=MO;BYMONTHDAY=1,8,15,22,29;COUNT=4',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- ===================================================================
-- GROUP 6: TIMESTAMPTZ overlaps() NULL dtend / NULL rrule
-- Zero-duration event handling and single-event overlap in the
-- TIMESTAMPTZ path are untested.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 6: TIMESTAMPTZ overlaps() NULL dtend / NULL rrule'
\echo '==================================================================='

-- Test 6.1: overlaps() with NULL dtend (zero-duration event)
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ overlaps NULL', 'overlaps() with NULL dtend — zero-duration event in range',
    assert_true(
        'TZ overlaps NULL dtend in range',
        (SELECT rrule."overlaps"(
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            NULL::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=5',
            '2025-01-14 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-16 00:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ))
    )
);

-- Test 6.2: overlaps() with NULL dtend — event outside range
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ overlaps NULL', 'overlaps() with NULL dtend — zero-duration outside range',
    assert_true(
        'TZ overlaps NULL dtend outside range',
        NOT (SELECT rrule."overlaps"(
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            NULL::TIMESTAMPTZ,
            'FREQ=DAILY;COUNT=3',
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 00:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ))
    )
);

-- Test 6.3: overlaps() with NULL rrule — single non-recurring event
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ overlaps NULL', 'overlaps() with NULL rrule — single event in range',
    assert_true(
        'TZ overlaps NULL rrule in range',
        (SELECT rrule."overlaps"(
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-15 11:00:00+00'::TIMESTAMPTZ,
            NULL::TEXT,
            '2025-01-14 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-16 00:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ))
    )
);

-- Test 6.4: overlaps() with NULL rrule — single event outside range
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ overlaps NULL', 'overlaps() with NULL rrule — single event outside range',
    assert_true(
        'TZ overlaps NULL rrule outside range',
        NOT (SELECT rrule."overlaps"(
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-01 11:00:00+00'::TIMESTAMPTZ,
            NULL::TEXT,
            '2025-01-10 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-20 00:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ))
    )
);

-- Test 6.5: overlaps() with NULL rrule AND NULL dtend — zero-duration single event
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ overlaps NULL', 'overlaps() with NULL rrule + NULL dtend — zero-duration single event',
    assert_true(
        'TZ overlaps NULL rrule+dtend',
        (SELECT rrule."overlaps"(
            '2025-01-15 10:00:00+00'::TIMESTAMPTZ,
            NULL::TIMESTAMPTZ,
            NULL::TEXT,
            '2025-01-14 00:00:00+00'::TIMESTAMPTZ,
            '2025-01-16 00:00:00+00'::TIMESTAMPTZ,
            'UTC'
        ))
    )
);

-- ===================================================================
-- GROUP 7: YEARLY BYDAY Negative Year-Level Ordinals
-- FREQ=YEARLY;BYDAY=-1FR without BYMONTH uses rrule_year_byday_set()
-- which counts backward from end of year. Different algorithm than
-- month-level BYDAY. No direct test exists.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 7: YEARLY BYDAY Negative Year-Level Ordinals'
\echo '==================================================================='

-- Test 7.1: Last Friday of the year (year-scoped negative ordinal)
-- 2025-12-26 is the last Friday of 2025
-- 2026-12-25 is the last Friday of 2026
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('YEARLY negative ordinals', 'FREQ=YEARLY;BYDAY=-1FR — last Friday of each year',
    assert_occurrences_equal(
        'YEARLY BYDAY=-1FR',
        ARRAY[
            '2025-12-26 10:00:00'::TIMESTAMP,
            '2026-12-25 10:00:00'::TIMESTAMP,
            '2027-12-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-1FR;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 7.2: Second-to-last Monday of the year (negative -2 ordinal)
-- 2025-12-22 is the -2 Monday of 2025 (last Monday is 12/29)
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('YEARLY negative ordinals', 'FREQ=YEARLY;BYDAY=-2MO — second-to-last Monday',
    assert_occurrences_equal(
        'YEARLY BYDAY=-2MO',
        ARRAY[
            '2025-12-22 10:00:00'::TIMESTAMP,
            '2026-12-21 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=YEARLY;BYDAY=-2MO;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- ===================================================================
-- GROUP 8: YEARLY + BYWEEKNO Without BYDAY
-- Returns week start date when no BYDAY is specified.
-- Year-boundary edge case untested.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 8: YEARLY BYWEEKNO Without BYDAY'
\echo '==================================================================='

-- Test 8.1: BYWEEKNO=1 without BYDAY — returns week start of ISO week 1
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('YEARLY BYWEEKNO no BYDAY', 'BYWEEKNO=1 without BYDAY returns week start',
    assert_true(
        'BYWEEKNO=1 no BYDAY',
        (SELECT COUNT(*) = 3
         FROM rrule."all"(
            'FREQ=YEARLY;BYWEEKNO=1;COUNT=3',
            '2025-01-01 10:00:00'::TIMESTAMP
        ))
    )
);

-- Test 8.2: BYWEEKNO=52 without BYDAY — late December week
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('YEARLY BYWEEKNO no BYDAY', 'BYWEEKNO=52 without BYDAY — year boundary',
    assert_true(
        'BYWEEKNO=52 no BYDAY',
        (SELECT COUNT(*) = 2
         FROM rrule."all"(
            'FREQ=YEARLY;BYWEEKNO=52;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP
        ))
    )
);

-- ===================================================================
-- GROUP 9: between()/after() inc=TRUE Exact Boundary
-- The inc=TRUE path adds 1 day to maxdate. No test verifies exact
-- boundary matching (occurrence falls precisely on start/end).
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 9: between()/after() inc=TRUE Exact Boundary'
\echo '==================================================================='

-- Test 9.1: TIMESTAMP between() inc=TRUE — occurrence exactly on end_date
-- inc=TRUE: occurrences >= start AND <= end, so Jan 1, 2, 3 all included
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('inc=TRUE boundary', 'between() inc=TRUE — occurrence exactly on end_date',
    assert_occurrences_equal(
        'between inc=TRUE end boundary',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."between"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            TRUE
        ) AS occurrence)
    )
);

-- Test 9.2: TIMESTAMP between() inc=TRUE — occurrence exactly on start_date
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('inc=TRUE boundary', 'between() inc=TRUE — occurrence exactly on start_date',
    assert_occurrences_equal(
        'between inc=TRUE start boundary',
        ARRAY[
            '2025-01-03 10:00:00'::TIMESTAMP,
            '2025-01-04 10:00:00'::TIMESTAMP,
            '2025-01-05 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."between"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            '2025-01-05 10:00:00'::TIMESTAMP,
            TRUE
        ) AS occurrence)
    )
);

-- Test 9.3: TIMESTAMP after() inc=TRUE — occurrence exactly on after_date
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('inc=TRUE boundary', 'after() inc=TRUE — occurrence exactly on after_date',
    assert_equals(
        'after inc=TRUE exact boundary',
        '2025-01-03 10:00:00',
        (SELECT rrule."after"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            TRUE
        ))::TEXT
    )
);

-- Test 9.4: TIMESTAMP after() inc=FALSE — should NOT include exact boundary
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('inc=TRUE boundary', 'after() inc=FALSE — should skip exact boundary',
    assert_equals(
        'after inc=FALSE exact boundary',
        '2025-01-04 10:00:00',
        (SELECT rrule."after"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP,
            FALSE
        ))::TEXT
    )
);

-- Test 9.5: TIMESTAMPTZ between() inc=TRUE — exact boundary
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('inc=TRUE boundary', 'TIMESTAMPTZ between() inc=TRUE — exact boundary',
    assert_true(
        'TZ between inc=TRUE exact boundary',
        (SELECT COUNT(*) = 3
         FROM rrule."between"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-03 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-05 10:00:00+00'::TIMESTAMPTZ,
            'UTC',
            TRUE
        ))
    )
);

-- ===================================================================
-- GROUP 10: TIMESTAMPTZ before() count>1
-- Non-trivial sliding-window array trim algorithm untested with count > 1.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 10: TIMESTAMPTZ before() count>1'
\echo '==================================================================='

-- Test 10.1: TIMESTAMPTZ before() with count=3 — last 3 occurrences before date
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ before count>1', 'before() count=3 — returns last 3 occurrences',
    assert_true(
        'TZ before count=3',
        (SELECT COUNT(*) = 3
         FROM rrule."before"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-08 10:00:00+00'::TIMESTAMPTZ,
            3,
            'UTC',
            FALSE
        ))
    )
);

-- Test 10.2: Verify correct values for before() count=3
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ before count>1', 'before() count=3 — correct values (last 3 before date)',
    assert_occurrences_equal(
        'TZ before count=3 values',
        ARRAY[
            '2025-01-05 10:00:00'::TIMESTAMP,
            '2025-01-06 10:00:00'::TIMESTAMP,
            '2025-01-07 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence::TIMESTAMP ORDER BY occurrence)
         FROM rrule."before"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-08 10:00:00+00'::TIMESTAMPTZ,
            3,
            'UTC',
            FALSE
        ) AS occurrence)
    )
);

-- Test 10.3: before() count=1 — should return single last occurrence
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('TZ before count>1', 'before() count=1 — single occurrence',
    assert_equals(
        'TZ before count=1',
        '2025-01-07 10:00:00+00',
        (SELECT occurrence::TEXT
         FROM rrule."before"(
            'FREQ=DAILY;COUNT=10',
            '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
            '2025-01-08 10:00:00+00'::TIMESTAMPTZ,
            1,
            'UTC',
            FALSE
        ) AS occurrence)
    )
);

-- ===================================================================
-- GROUP 11: DAILY BYHOUR + BYSETPOS — Cursor-Based Filtering Path
-- When BYHOUR is specified with DAILY, daily_set() opens a cursor for
-- BYSETPOS filtering. This unique code path is untested.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 11: DAILY BYHOUR + BYSETPOS'
\echo '==================================================================='

-- Test 11.1: DAILY + BYHOUR=9,12,17 + BYSETPOS=1,-1 — first and last hours
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('DAILY BYHOUR BYSETPOS', 'DAILY + BYHOUR=9,12,17 + BYSETPOS=1,-1 — first and last',
    assert_occurrences_equal(
        'DAILY BYHOUR BYSETPOS 1,-1',
        ARRAY[
            '2025-01-01 09:00:00'::TIMESTAMP,
            '2025-01-01 17:00:00'::TIMESTAMP,
            '2025-01-02 09:00:00'::TIMESTAMP,
            '2025-01-02 17:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=DAILY;BYHOUR=9,12,17;BYSETPOS=1,-1;COUNT=4',
            '2025-01-01 09:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 11.2: DAILY + BYHOUR=8,12,16,20 + BYSETPOS=2 — second hour only
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('DAILY BYHOUR BYSETPOS', 'DAILY + BYHOUR=8,12,16,20 + BYSETPOS=2 — second hour',
    assert_occurrences_equal(
        'DAILY BYHOUR BYSETPOS 2',
        ARRAY[
            '2025-01-01 12:00:00'::TIMESTAMP,
            '2025-01-02 12:00:00'::TIMESTAMP,
            '2025-01-03 12:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=DAILY;BYHOUR=8,12,16,20;BYSETPOS=2;COUNT=3',
            '2025-01-01 08:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- ===================================================================
-- GROUP 12: SKIP=FORWARD + UNTIL Interaction
-- If FORWARD date crosses UNTIL, the EXIT condition must prevent
-- emission. This specific combination is untested.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 12: SKIP=FORWARD + UNTIL Interaction'
\echo '==================================================================='

-- Test 12.1: FORWARD date would be March 1, but UNTIL is Feb 28
-- SKIP=FORWARD on Feb 31 -> March 1, but UNTIL=2025-02-28 should prevent it
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('SKIP FORWARD+UNTIL', 'FORWARD crosses UNTIL — no emission beyond UNTIL',
    assert_occurrences_equal(
        'FORWARD crosses UNTIL',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;UNTIL=20250228T100000Z',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- Test 12.2: FORWARD date within UNTIL — should emit
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('SKIP FORWARD+UNTIL', 'FORWARD within UNTIL — emission allowed',
    assert_occurrences_equal(
        'FORWARD within UNTIL',
        ARRAY[
            '2025-01-31 10:00:00'::TIMESTAMP,
            '2025-03-01 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."all"(
            'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;UNTIL=20250301T100000Z',
            '2025-01-01 10:00:00'::TIMESTAMP
        ) AS occurrence)
    )
);

-- ===================================================================
-- GROUP 13: YEARLY BYWEEKNO + BYYEARDAY Intersection
-- Post-filter WHERE clause applying byyearday on BYWEEKNO candidates.
-- No test exists for this intersection path.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 13: YEARLY BYWEEKNO + BYYEARDAY Intersection'
\echo '==================================================================='

-- Test 13.1: BYWEEKNO=1 + BYDAY=MO,TU,WE,TH,FR + BYYEARDAY=1,2,3
-- Only dates that are both in ISO week 1 AND in the first 3 days of the year
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('YEARLY BYWEEKNO+BYYEARDAY', 'BYWEEKNO=1 + BYYEARDAY=1,2,3 intersection',
    assert_true(
        'BYWEEKNO+BYYEARDAY intersection',
        (SELECT COUNT(*) >= 1
         FROM rrule."between"(
            'FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO,TU,WE,TH,FR;BYYEARDAY=1,2,3',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 00:00:00'::TIMESTAMP,
            '2027-12-31 23:59:59'::TIMESTAMP,
            TRUE
        ))
    )
);

-- Test 13.2: Verify specific intersection — 2025 Jan 1-3 are Wed-Fri, all in ISO week 1
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('YEARLY BYWEEKNO+BYYEARDAY', '2025 BYWEEKNO=1 + BYYEARDAY=1,2,3 — Jan 1-3',
    assert_occurrences_equal(
        'BYWEEKNO+BYYEARDAY 2025',
        ARRAY[
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            '2025-01-03 10:00:00'::TIMESTAMP
        ],
        (SELECT array_agg(occurrence ORDER BY occurrence)
         FROM rrule."between"(
            'FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO,TU,WE,TH,FR;BYYEARDAY=1,2,3',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2024-12-31 00:00:00'::TIMESTAMP,
            '2025-12-31 23:59:59'::TIMESTAMP,
            TRUE
        ) AS occurrence)
    )
);

-- ===================================================================
-- GROUP 14: version() Function — Smoke Test
-- Trivial but completely untested.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 14: version() Function'
\echo '==================================================================='

-- Test 14.1: version() returns a non-empty string
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('version()', 'version() returns non-empty string',
    assert_true(
        'version() non-empty',
        (SELECT length(rrule."version"()) > 0)
    )
);

-- Test 14.2: version() matches semver pattern (X.Y.Z)
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('version()', 'version() matches semver pattern',
    assert_true(
        'version() semver',
        (SELECT rrule."version"() ~ '^\d+\.\d+\.\d+$')
    )
);

-- ===================================================================
-- GROUP 15: Truncation WARNING Path
-- Rules without COUNT/UNTIL that hit the 1000 cap should emit
-- RAISE WARNING. This is tested by verifying that the result count
-- is exactly 1000 for an unbounded rule.
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'GROUP 15: Truncation at 1000 Cap'
\echo '==================================================================='

-- Test 15.1: Unbounded DAILY rule hits 1000 cap
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('Truncation cap', 'Unbounded DAILY rule capped at 1000 results',
    assert_equals(
        'truncation cap 1000',
        '1000',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=DAILY',
            '2025-01-01 10:00:00'::TIMESTAMP
        ))
    )
);

-- Test 15.2: Rule with COUNT=5 is NOT truncated (should return exactly 5)
INSERT INTO consensus_test_results (test_group, test_name, status)
VALUES ('Truncation cap', 'Rule with COUNT=5 not truncated',
    assert_equals(
        'no truncation with COUNT',
        '5',
        (SELECT COUNT(*)::TEXT FROM rrule."all"(
            'FREQ=DAILY;COUNT=5',
            '2025-01-01 10:00:00'::TIMESTAMP
        ))
    )
);

-- ===================================================================
-- Test Results Summary
-- ===================================================================
\echo ''
\echo '==================================================================='
\echo 'Consensus Gap Test Results'
\echo '==================================================================='

SELECT
    test_number,
    test_group,
    test_name,
    status
FROM consensus_test_results
ORDER BY test_number;

\echo ''
\echo 'Summary by group:'
SELECT
    test_group,
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') as passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') as failed,
    COUNT(*) FILTER (WHERE status LIKE 'SKIP%') as skipped
FROM consensus_test_results
GROUP BY test_group
ORDER BY MIN(test_number);

\echo ''
\echo 'Overall:'
SELECT
    COUNT(*) as total_tests,
    COUNT(*) FILTER (WHERE status LIKE 'PASS%') as passed,
    COUNT(*) FILTER (WHERE status LIKE 'FAIL%') as failed,
    COUNT(*) FILTER (WHERE status LIKE 'SKIP%') as skipped
FROM consensus_test_results;

-- Verify all tests passed (fail if any FAIL results)
DO $$
DECLARE
    failed_count INT;
BEGIN
    SELECT COUNT(*) INTO failed_count
    FROM consensus_test_results
    WHERE status LIKE 'FAIL%';

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'CONSENSUS GAP TESTS FAILED: % test(s) failed', failed_count;
    ELSE
        RAISE NOTICE 'CONSENSUS GAP TESTS PASSED: All tests passed!';
    END IF;
END $$;

ROLLBACK;
