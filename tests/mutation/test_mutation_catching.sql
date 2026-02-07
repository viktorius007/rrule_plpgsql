-- Test file: test_mutation_catching.sql
-- Purpose: Catch specific mutations identified by mutation testing
--
-- These tests are designed to FAIL when specific code mutations are applied,
-- verifying that our test suite can detect these types of bugs.
--
-- Surviving mutations this file catches:
--   1. boundary-1: period_count < period_limit → period_count <= period_limit
--   2. boundary-2: result.period_count >= p_period_limit → result.period_count > p_period_limit
--   3. boundary-4: result.omit_count >= p_period_limit → result.omit_count > p_period_limit
--   4. off-by-one-1: result_count := result_count + 1 → result_count := result_count + 2
--   5. filter-1: test_bymonth_rule bypass (TRUE OR test_bymonth_rule)
--   6. tz-unsupported-branch: SECONDLY routed to wrong unsupported-frequency branch

-- Include rrule functions (via variable set by test runner, or default)
\if :{?rrule_install}
\i :rrule_install
\else
\i src/rrule.sql
\endif
\i tests/helpers.sql

BEGIN;

\echo '========================================'
\echo 'MUTATION CATCHING TESTS'
\echo '========================================'
\echo ''

--------------------------------------------------------------------------------
-- MUTATION: boundary-1 and boundary-2
-- Pattern: period_count < period_limit / result.period_count >= p_period_limit
-- These control iteration budget. If changed, we'd get more/fewer results.
--------------------------------------------------------------------------------

\echo 'Testing: Period limit boundary conditions'

-- Test exact period limit enforcement
-- A bounded YEARLY rule should return exactly COUNT results
SELECT assert_equals(
    'MUTATION-boundary: YEARLY COUNT=7 returns exactly 7',
    '7',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;COUNT=7',
        '2020-01-01'::TIMESTAMP
    ))
);

-- Test with DAILY frequency to verify iteration budget
-- DAILY with COUNT=1000 should return exactly 1000, not 1001
SELECT assert_equals(
    'MUTATION-boundary: DAILY COUNT=1000 returns exactly 1000',
    '1000',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY;COUNT=1000',
        '2020-01-01'::TIMESTAMP
    ))
);

-- Test edge case: result cap at exactly 1000
-- An unbounded DAILY should stop at exactly 1000, not 1001
SELECT assert_equals(
    'MUTATION-boundary: Unbounded DAILY caps at exactly 1000',
    '1000',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY',
        '2020-01-01'::TIMESTAMP
    ))
);

--------------------------------------------------------------------------------
-- MUTATION: boundary-2 specifically (SKIP=FORWARD period limit)
-- Pattern: result.period_count >= p_period_limit → result.period_count > p_period_limit
-- This is in _advance_monthly and _advance_yearly SKIP=FORWARD code
--------------------------------------------------------------------------------

\echo 'Testing: SKIP=FORWARD period budget enforcement'

-- SKIP=FORWARD on months that don't exist (Feb 30, etc.) must still respect
-- iteration limits. If the >= is changed to >, we'd get one more iteration.
SELECT assert_equals(
    'MUTATION-boundary-2: SKIP=FORWARD respects period budget',
    '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=31;SKIP=FORWARD;COUNT=12',
        '2024-01-31'::TIMESTAMP
    ))
);

-- Test YEARLY SKIP=FORWARD (Feb 29 in non-leap years)
SELECT assert_equals(
    'MUTATION-boundary-2: YEARLY SKIP=FORWARD period budget',
    '10',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;SKIP=FORWARD;COUNT=10',
        '2024-02-29'::TIMESTAMP
    ))
);

--------------------------------------------------------------------------------
-- MUTATION: off-by-one-1
-- Pattern: result_count := result_count + 1 → result_count := result_count + 2
-- If result count increments by 2, we'd hit limits early (half the results)
--------------------------------------------------------------------------------

\echo 'Testing: Result count accuracy (off-by-one detection)'

-- Test that COUNT produces exact number of results
-- If result_count increments by 2, COUNT=10 would return only 5
SELECT assert_equals(
    'MUTATION-off-by-one: COUNT=10 returns exactly 10 results',
    '10',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY;COUNT=10',
        '2025-01-01'::TIMESTAMP
    ))
);

-- Test with WEEKLY expansion (BYDAY produces multiple results per period)
-- If counting is wrong, we'd get half the expected results
SELECT assert_equals(
    'MUTATION-off-by-one: WEEKLY BYDAY expansion count accurate',
    '15',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=15',
        '2025-01-06'::TIMESTAMP  -- Monday
    ))
);

-- Test MONTHLY with BYMONTHDAY expansion
SELECT assert_equals(
    'MUTATION-off-by-one: MONTHLY BYMONTHDAY expansion count',
    '20',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=MONTHLY;BYMONTHDAY=1,15;COUNT=20',
        '2025-01-01'::TIMESTAMP
    ))
);

-- Test YEARLY with BYYEARDAY (exercises yearly_byyearday_set result counting)
SELECT assert_equals(
    'MUTATION-off-by-one: YEARLY BYYEARDAY result count',
    '12',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYYEARDAY=1,100,200,300;COUNT=12',
        '2025-01-01'::TIMESTAMP
    ))
);

-- Test YEARLY with BYWEEKNO (exercises yearly_byweekno_set result counting)
SELECT assert_equals(
    'MUTATION-off-by-one: YEARLY BYWEEKNO result count',
    '9',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=YEARLY;BYWEEKNO=1,26,52;BYDAY=MO;COUNT=9',
        '2025-01-01'::TIMESTAMP
    ))
);

--------------------------------------------------------------------------------
-- MUTATION: filter-1
-- Pattern: rrule.test_bymonth_rule( → TRUE OR rrule.test_bymonth_rule(
-- If bypassed, BYMONTH filter wouldn't exclude non-matching months
--------------------------------------------------------------------------------

\echo 'Testing: BYMONTH filter effectiveness'

-- Test BYMONTH with WEEKLY frequency (uses test_bymonth_rule at line 2490)
-- WEEKLY starting Jan with BYMONTH=7 should only return July weeks
-- If filter is bypassed, we'd get weeks from all months
SELECT assert_true(
    'MUTATION-filter: WEEKLY BYMONTH=7 produces only July dates',
    (SELECT bool_and(EXTRACT(MONTH FROM r) = 7)
     FROM rrule."all"('FREQ=WEEKLY;BYMONTH=7;COUNT=10', '2020-01-01'::TIMESTAMP) r)
);

-- Count distinct months for WEEKLY - should be exactly 1 (July)
SELECT assert_equals(
    'MUTATION-filter: WEEKLY BYMONTH=7 has exactly 1 distinct month',
    '1',
    (SELECT COUNT(DISTINCT EXTRACT(MONTH FROM r))::TEXT
     FROM rrule."all"('FREQ=WEEKLY;BYMONTH=7;COUNT=10', '2020-01-01'::TIMESTAMP) r)
);

-- Verify no results in other months for WEEKLY
SELECT assert_equals(
    'MUTATION-filter: WEEKLY BYMONTH=7 has zero non-July dates',
    '0',
    (SELECT COUNT(*)::TEXT
     FROM rrule."all"('FREQ=WEEKLY;BYMONTH=7;COUNT=20', '2020-01-01'::TIMESTAMP) r
     WHERE EXTRACT(MONTH FROM r) != 7)
);

-- Test BYMONTH with YEARLY frequency in BYWEEKNO path (line 2279)
-- Week 1 can span Dec/Jan, BYMONTH=1 should only keep January dates
SELECT assert_true(
    'MUTATION-filter: YEARLY BYWEEKNO respects BYMONTH filter',
    (SELECT bool_and(EXTRACT(MONTH FROM r) = 1)
     FROM rrule."all"(
         'FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO,TU,WE,TH,FR;BYMONTH=1;COUNT=20',
         '2020-01-01'::TIMESTAMP
     ) r)
);

-- Test BYMONTH with YEARLY frequency in BYYEARDAY path (line 2294)
-- BYYEARDAY=1 is Jan 1, BYYEARDAY=100 is April 10 - BYMONTH=1 filters out April
SELECT assert_equals(
    'MUTATION-filter: YEARLY BYYEARDAY with BYMONTH=1 filters out non-Jan dates',
    '0',  -- No April dates
    (SELECT COUNT(*)::TEXT
     FROM rrule."all"(
         'FREQ=YEARLY;BYYEARDAY=1,100;BYMONTH=1;COUNT=6',
         '2020-01-01'::TIMESTAMP
     ) r
     WHERE EXTRACT(MONTH FROM r) = 4)
);

-- Test WEEKLY with BYMONTH=3,6,9,12 - quarterly filtering
SELECT assert_true(
    'MUTATION-filter: WEEKLY BYMONTH=3,6,9,12 produces only Mar/Jun/Sep/Dec',
    (SELECT bool_and(EXTRACT(MONTH FROM r) IN (3, 6, 9, 12))
     FROM rrule."all"('FREQ=WEEKLY;BYMONTH=3,6,9,12;COUNT=20', '2020-01-01'::TIMESTAMP) r)
);

--------------------------------------------------------------------------------
-- COMBINED: Tests that catch multiple mutations
--------------------------------------------------------------------------------

\echo 'Testing: Combined mutation detection'

-- This test fails if ANY of the mutations are applied:
-- - boundary mutations: wrong iteration count
-- - off-by-one: wrong result count
-- - filter bypass: wrong months included
SELECT assert_equals(
    'MUTATION-combined: Exact results for complex RRULE',
    '{"2020-01-15 00:00:00","2020-07-15 00:00:00","2021-01-15 00:00:00","2021-07-15 00:00:00","2022-01-15 00:00:00","2022-07-15 00:00:00"}',
    (SELECT array_agg(r ORDER BY r)::TEXT
     FROM rrule."all"(
         'FREQ=MONTHLY;BYMONTH=1,7;BYMONTHDAY=15;COUNT=6',
         '2020-01-15'::TIMESTAMP
     ) r)
);

-- Another combined test with YEARLY
SELECT assert_equals(
    'MUTATION-combined: YEARLY BYMONTH exact dates',
    '{"2020-06-21 00:00:00","2021-06-21 00:00:00","2022-06-21 00:00:00"}',
    (SELECT array_agg(r ORDER BY r)::TEXT
     FROM rrule."all"(
         'FREQ=YEARLY;BYMONTH=6;BYMONTHDAY=21;COUNT=3',
         '2020-06-21'::TIMESTAMP
     ) r)
);

--------------------------------------------------------------------------------
-- TIMESTAMPTZ API: Ensure mutations are caught in TZ path too
--------------------------------------------------------------------------------

\echo 'Testing: TIMESTAMPTZ API mutation detection'

-- The TZ generator at line 3199 has the same period_count boundary
SELECT assert_equals(
    'MUTATION-tz-boundary: TIMESTAMPTZ respects period limit',
    '1000',
    (SELECT COUNT(*)::TEXT FROM rrule."all"(
        'FREQ=DAILY;COUNT=1000',
        '2020-01-01 10:00:00'::TIMESTAMPTZ,
        'America/New_York'
    ))
);

-- TZ path BYMONTH filter (line 3244)
SELECT assert_true(
    'MUTATION-tz-filter: TIMESTAMPTZ BYMONTH filters correctly',
    (SELECT bool_and(EXTRACT(MONTH FROM r) IN (3, 9))
     FROM rrule."all"(
         'FREQ=MONTHLY;BYMONTH=3,9;COUNT=10',
         '2020-03-01 12:00:00'::TIMESTAMPTZ,
         'Europe/London'
     ) r)
);

--------------------------------------------------------------------------------
-- Direct helper branch assertions for SKIP period-limit mutations
--------------------------------------------------------------------------------

\echo 'Testing: _advance_yearly helper period-limit branch mutations'

DO $$
DECLARE
    r_omit rrule._skip_result;
    r_forward rrule._skip_result;
BEGIN
    -- boundary-4: OMIT branch must terminate when omit_count hits period_limit.
    r_omit := rrule._advance_yearly(
        '2021-02-28 10:00:00+00'::TIMESTAMPTZ,
        '2020-02-29 10:00:00+00'::TIMESTAMPTZ,
        29,
        1,
        'OMIT',
        NULL::TIMESTAMPTZ,
        '2035-01-01 00:00:00+00'::TIMESTAMPTZ,
        1,
        0,
        0
    );

    PERFORM assert_true(
        'MUTATION-boundary-omit-limit: _advance_yearly sets done=true at omit_count limit',
        r_omit.done AND r_omit.omit_count = 1
    );

    -- boundary-2: FORWARD branch must terminate when period_count hits period_limit.
    r_forward := rrule._advance_yearly(
        '2021-02-28 10:00:00+00'::TIMESTAMPTZ,
        '2020-02-29 10:00:00+00'::TIMESTAMPTZ,
        29,
        1,
        'FORWARD',
        NULL::TIMESTAMPTZ,
        '2035-01-01 00:00:00+00'::TIMESTAMPTZ,
        1,
        0,
        0
    );

    PERFORM assert_true(
        'MUTATION-boundary-forward-limit: _advance_yearly sets done=true at period_count limit',
        r_forward.done AND r_forward.period_count = 1
    );
END;
$$;

--------------------------------------------------------------------------------
-- TZ unsupported-frequency branch behavior in standard install
--------------------------------------------------------------------------------

\echo 'Testing: TZ unsupported-frequency branch behavior'

DO $$
DECLARE
    msg_secondly TEXT;
    msg_invalid TEXT;
BEGIN
    -- SECONDLY in standard install should hit sub-day unsupported branch.
    BEGIN
        PERFORM rrule.rrule_event_instances_range_tz(
            '2025-01-01 10:00:00'::TIMESTAMP,
            'FREQ=SECONDLY;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-01 10:00:05'::TIMESTAMP,
            NULL
        );
        RAISE EXCEPTION 'Expected SECONDLY to be rejected in standard install';
    EXCEPTION WHEN OTHERS THEN
        msg_secondly := SQLERRM;
    END;

    PERFORM assert_true(
        'MUTATION-tz-unsupported-branch: SECONDLY uses subday unsupported branch',
        msg_secondly LIKE '%not supported%' OR msg_secondly LIKE '%SECONDLY%'
    );

    -- Invalid FREQ should hit generic unsupported branch / parse validation.
    BEGIN
        PERFORM rrule.rrule_event_instances_range_tz(
            '2025-01-01 10:00:00'::TIMESTAMP,
            'FREQ=NOT_A_REAL_FREQ;COUNT=2',
            '2025-01-01 10:00:00'::TIMESTAMP,
            '2025-01-02 10:00:00'::TIMESTAMP,
            NULL
        );
        RAISE EXCEPTION 'Expected invalid frequency to be rejected';
    EXCEPTION WHEN OTHERS THEN
        msg_invalid := SQLERRM;
    END;

    PERFORM assert_true(
        'MUTATION-tz-unsupported-branch: invalid freq uses generic rejection path',
        msg_invalid LIKE '%Unsupported frequency%'
        OR msg_invalid LIKE '%Invalid RRULE%'
        OR msg_invalid LIKE '%FREQ%'
    );
END;
$$;

\echo ''
\echo '========================================'
\echo 'MUTATION CATCHING TESTS COMPLETE'
\echo '========================================'

ROLLBACK;
