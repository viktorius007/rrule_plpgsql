/**
 * RRULE Sub-Day Frequencies Extension
 *
 * ⚠️  WARNING: SECURITY-SENSITIVE CODE ⚠️
 *
 * This file extends the rrule_plpgsql implementation with HOURLY, MINUTELY,
 * and SECONDLY frequency support. These frequencies are DISABLED by default
 * due to security and performance concerns.
 *
 * DENIAL OF SERVICE RISKS:
 * - HOURLY: 8,760 occurrences per year
 * - MINUTELY: 525,600 occurrences per year
 * - SECONDLY: 31,536,000 occurrences per year
 *
 * RESOURCE EXHAUSTION RISKS:
 * - CPU: Computing millions of date increments
 * - Memory: Building large TIMESTAMP[] arrays
 * - Connections: Blocking connection pool in multi-tenant systems
 *
 * WHEN TO USE:
 * ✅ Single-tenant deployments where you control all RRULEs
 * ✅ With strict application-level validation (see below)
 * ✅ With query timeouts configured (statement_timeout)
 * ✅ With monitoring and alerting on long-running queries
 * ✅ Never in multi-tenant environments without strict limits
 *
 * REQUIRED VALIDATION:
 * Before installing this extension, implement application-level validation:
 * - HOURLY: COUNT <= 1000, UNTIL <= 7 days from dtstart
 * - MINUTELY: COUNT <= 1000, UNTIL <= 24 hours from dtstart
 * - SECONDLY: COUNT <= 1000, UNTIL <= 1 hour from dtstart
 *
 * EXAMPLE VALIDATION (TypeScript):
 * ```typescript
 * function validateSubDayRRule(rrule: string): void {
 *   const count = parseInt(rrule.match(/COUNT=(\d+)/)?.[1] || '0');
 *
 *   if (rrule.includes('FREQ=HOURLY') && count > 1000) {
 *     throw new Error('HOURLY limited to COUNT=1000');
 *   }
 *   if (rrule.includes('FREQ=MINUTELY') && count > 1000) {
 *     throw new Error('MINUTELY limited to COUNT=1000');
 *   }
 *   if (rrule.includes('FREQ=SECONDLY') && count > 1000) {
 *     throw new Error('SECONDLY limited to COUNT=1000');
 *   }
 * }
 * ```
 *
 * DATABASE CONFIGURATION:
 * Set statement timeout to prevent runaway queries:
 * ```sql
 * ALTER DATABASE your_db SET statement_timeout = '30s';
 * -- OR per-session:
 * SET statement_timeout = '30s';
 * ```
 *
 * INSTALLATION:
 * Use install_with_subday.sql instead of install.sql
 *
 * @package rrule_plpgsql
 * @license MIT
 * @security CRITICAL - Review security implications before use
 */

SET search_path = rrule, public;

------------------------------------------------------------------------------------------------------
-- HOURLY frequency handler
-- ⚠️  WARNING: This frequency can generate thousands of occurrences quickly
-- ⚠️  Recommended limits: COUNT <= 1000, UNTIL <= 7 days from dtstart
-- ⚠️  Use case: "Every 3 hours" (FREQ=HOURLY;INTERVAL=3;COUNT=8)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hourly_set(
  after_ts TIMESTAMP WITH TIME ZONE,
  rule rrule.rrule_parts
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
BEGIN
  -- Apply day-level filters first
  IF rule.bymonth IS NOT NULL AND NOT date_part('month', after_ts) = ANY (rule.bymonth) THEN
    RETURN;
  END IF;

  IF rule.bymonthday IS NOT NULL AND NOT rrule.test_bymonthday_rule(after_ts, rule.bymonthday) THEN
    RETURN;
  END IF;

  IF rule.byday IS NOT NULL AND NOT rrule.test_byday_rule(after_ts, rule.byday) THEN
    RETURN;
  END IF;

  -- Apply hour filter
  IF rule.byhour IS NOT NULL AND NOT date_part('hour', after_ts) = ANY (rule.byhour) THEN
    RETURN;
  END IF;

  -- Apply minute/second filters if specified
  IF rule.byminute IS NOT NULL AND NOT date_part('minute', after_ts) = ANY (rule.byminute) THEN
    RETURN;
  END IF;

  IF rule.bysecond IS NOT NULL AND NOT date_part('second', after_ts)::INT = ANY (rule.bysecond) THEN
    RETURN;
  END IF;

  RETURN NEXT after_ts;
END;
$$ LANGUAGE plpgsql STABLE STRICT;


------------------------------------------------------------------------------------------------------
-- MINUTELY frequency handler
-- ⚠️  WARNING: This frequency can generate 525,600 occurrences per year
-- ⚠️  SECURITY RISK: Can exhaust database resources in multi-tenant environments
-- ⚠️  Recommended limits: COUNT <= 1000, UNTIL <= 24 hours from dtstart
-- ⚠️  Use case: "Every 15 minutes" (FREQ=MINUTELY;INTERVAL=15;COUNT=96)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION minutely_set(
  after_ts TIMESTAMP WITH TIME ZONE,
  rule rrule.rrule_parts
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
BEGIN
  -- Apply all filters
  IF rule.bymonth IS NOT NULL AND NOT date_part('month', after_ts) = ANY (rule.bymonth) THEN
    RETURN;
  END IF;

  IF rule.bymonthday IS NOT NULL AND NOT rrule.test_bymonthday_rule(after_ts, rule.bymonthday) THEN
    RETURN;
  END IF;

  IF rule.byday IS NOT NULL AND NOT rrule.test_byday_rule(after_ts, rule.byday) THEN
    RETURN;
  END IF;

  IF rule.byhour IS NOT NULL AND NOT date_part('hour', after_ts) = ANY (rule.byhour) THEN
    RETURN;
  END IF;

  IF rule.byminute IS NOT NULL AND NOT date_part('minute', after_ts) = ANY (rule.byminute) THEN
    RETURN;
  END IF;

  IF rule.bysecond IS NOT NULL AND NOT date_part('second', after_ts)::INT = ANY (rule.bysecond) THEN
    RETURN;
  END IF;

  RETURN NEXT after_ts;
END;
$$ LANGUAGE plpgsql STABLE STRICT;


------------------------------------------------------------------------------------------------------
-- SECONDLY frequency handler
-- ⚠️  CRITICAL SECURITY WARNING: This frequency can generate 31,536,000 occurrences per year
-- ⚠️  DENIAL OF SERVICE RISK: Can exhaust CPU, memory, and connection pools
-- ⚠️  DO NOT USE in production multi-tenant environments without strict limits
-- ⚠️  Recommended limits: COUNT <= 1000, UNTIL <= 1 hour from dtstart
-- ⚠️  Use case: "Every 30 seconds for 5 minutes" (FREQ=SECONDLY;INTERVAL=30;COUNT=10)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION secondly_set(
  after_ts TIMESTAMP WITH TIME ZONE,
  rule rrule.rrule_parts
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
BEGIN
  -- Apply all filters
  IF rule.bymonth IS NOT NULL AND NOT date_part('month', after_ts) = ANY (rule.bymonth) THEN
    RETURN;
  END IF;

  IF rule.bymonthday IS NOT NULL AND NOT rrule.test_bymonthday_rule(after_ts, rule.bymonthday) THEN
    RETURN;
  END IF;

  IF rule.byday IS NOT NULL AND NOT rrule.test_byday_rule(after_ts, rule.byday) THEN
    RETURN;
  END IF;

  IF rule.byhour IS NOT NULL AND NOT date_part('hour', after_ts) = ANY (rule.byhour) THEN
    RETURN;
  END IF;

  IF rule.byminute IS NOT NULL AND NOT date_part('minute', after_ts) = ANY (rule.byminute) THEN
    RETURN;
  END IF;

  IF rule.bysecond IS NOT NULL AND NOT date_part('second', after_ts)::INT = ANY (rule.bysecond) THEN
    RETURN;
  END IF;

  RETURN NEXT after_ts;
END;
$$ LANGUAGE plpgsql STABLE STRICT;


------------------------------------------------------------------------------------------------------
-- Override rrule_event_instances_range to enable sub-day frequencies
-- This replaces the version from rrule.sql which rejects HOURLY/MINUTELY/SECONDLY with an error.
-- Also provides the actual implementations of hourly_set(), minutely_set(), and secondly_set()
-- which are not defined in the standard rrule.sql installation.
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rrule_event_instances_range(
  basedate TIMESTAMP WITH TIME ZONE,
  repeatrule TEXT,
  mindate TIMESTAMP WITH TIME ZONE,
  maxdate TIMESTAMP WITH TIME ZONE,
  max_count INT
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  period_limit INT;
  period_count INT := 0;
  occurrence_count INT := 0;
  emitted_count INT := 0;
  output_limit INT;
  dtstart_day INT;
  current_base TIMESTAMP WITH TIME ZONE;
  current TIMESTAMP WITH TIME ZONE;
  period_start TIMESTAMP WITH TIME ZONE;
  min_in_period TIMESTAMP WITH TIME ZONE;
  prev_period_max_ts TIMESTAMP WITH TIME ZONE := NULL;
  rule rrule.rrule_parts%ROWTYPE;
BEGIN
  SELECT * INTO rule FROM rrule.parse_rrule_parts(basedate, repeatrule);

  -- Output cap: respect both API limit and RRULE COUNT
  output_limit := max_count;
  IF rule.count IS NOT NULL THEN
    output_limit := COALESCE(output_limit, rule.count);
    output_limit := LEAST(output_limit, rule.count);
  END IF;

  -- Security: Calculate safe period scan limit accounting for sparse BYxxx filters
  period_limit := rrule.calculate_safe_iteration_limit(rule.freq, rule.count, output_limit, rule.interval);
  IF period_limit IS NULL THEN
    period_limit := 2147483647;  -- effectively unlimited
  END IF;

  IF rule.freq IS NULL THEN
    RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required';
  END IF;

  -- Remember dtstart day-of-month for SKIP drift prevention
  dtstart_day := date_part('day', basedate)::INT;

  current_base := basedate;

  -- Early exit: UNTIL before dtstart means no occurrences possible
  IF rule.until IS NOT NULL AND rule.until < basedate THEN
    RETURN;
  END IF;

  WHILE period_count < period_limit AND current_base < maxdate LOOP
    IF rule.freq = 'DAILY' THEN
      period_start := date_trunc('day', current_base) + (current_base::time)::interval;
      min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
      FOR current IN SELECT d FROM rrule.daily_set(current_base, rule, CASE WHEN rule.bysetpos IS NULL AND rule.bymonthday IS NULL AND rule.bymonth IS NULL THEN (CASE WHEN output_limit IS NULL THEN NULL ELSE GREATEST(output_limit - emitted_count, 0) END) ELSE NULL END) d WHERE d >= min_in_period LOOP
        EXIT WHEN rule.until IS NOT NULL AND current > rule.until;
        EXIT WHEN current > maxdate;
        occurrence_count := occurrence_count + 1;
        EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
        IF current >= mindate THEN
          RETURN NEXT current;
          emitted_count := emitted_count + 1;
          EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
        END IF;
      END LOOP;
      current_base := current_base + make_interval(days => rule.interval);

    ELSIF rule.freq = 'WEEKLY' THEN
      period_start := rrule.get_week_start(current_base, rule.wkst) + (current_base::time)::interval;
      min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
      FOR current IN SELECT w FROM rrule.weekly_set(current_base, rule, CASE WHEN rule.bysetpos IS NULL AND rule.bymonthday IS NULL AND rule.bymonth IS NULL THEN (CASE WHEN output_limit IS NULL THEN NULL ELSE GREATEST(output_limit - emitted_count, 0) END) ELSE NULL END) w WHERE w >= min_in_period LOOP
        -- Time boundary checks apply regardless of BYxxx filters
        EXIT WHEN rule.until IS NOT NULL AND current > rule.until;
        EXIT WHEN current > maxdate;
        IF rrule.test_byyearday_rule(current, rule.byyearday)
               AND rrule.test_bymonthday_rule(current, rule.bymonthday)
               AND rrule.test_bymonth_rule(current, rule.bymonth)
        THEN
          occurrence_count := occurrence_count + 1;
          EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
          IF current >= mindate THEN
            RETURN NEXT current;
            emitted_count := emitted_count + 1;
            EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
          END IF;
        END IF;
      END LOOP;
      current_base := current_base + make_interval(weeks => rule.interval);

    ELSIF rule.freq = 'MONTHLY' THEN
      period_start := date_trunc('month', current_base) + (current_base::time)::interval;
      min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
      FOR current IN SELECT m FROM rrule.monthly_set(current_base, rule, CASE WHEN rule.bysetpos IS NULL AND rule.bymonthday IS NULL AND rule.bymonth IS NULL THEN (CASE WHEN output_limit IS NULL THEN NULL ELSE GREATEST(output_limit - emitted_count, 0) END) ELSE NULL END) m WHERE m >= min_in_period LOOP
        EXIT WHEN rule.until IS NOT NULL AND current > rule.until;
        EXIT WHEN current > maxdate;
        -- Cross-period dedup: SKIP=FORWARD can push dates into the next period
        CONTINUE WHEN prev_period_max_ts IS NOT NULL AND current = prev_period_max_ts;
        occurrence_count := occurrence_count + 1;
        EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
        IF current >= mindate THEN
          RETURN NEXT current;
          emitted_count := emitted_count + 1;
          EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
        END IF;
        prev_period_max_ts := current;
      END LOOP;
      current_base := current_base + make_interval(months => rule.interval);
      IF rule.bymonthday IS NULL AND rule.byday IS NULL THEN
        -- Restore dtstart day-of-month to prevent cumulative drift from FORWARD
        current_base := date_trunc('month', current_base)
          + make_interval(days => LEAST(dtstart_day,
              date_part('day', (date_trunc('month', current_base) + INTERVAL '1 month - 1 day'))::INT) - 1)
          + (basedate::time)::interval;
        LOOP
          EXIT WHEN date_part('day', current_base)::INT = dtstart_day;
          IF rule.skip = 'OMIT' THEN
            -- Do NOT increment period_count here — the outer loop handles it.
            -- Skipped months should not count against the iteration budget.
            current_base := current_base + make_interval(months => rule.interval);
            current_base := date_trunc('month', current_base)
              + make_interval(days => LEAST(dtstart_day,
                  date_part('day', (date_trunc('month', current_base) + INTERVAL '1 month - 1 day'))::INT) - 1)
              + (basedate::time)::interval;
            EXIT WHEN current_base > maxdate;
            EXIT WHEN rule.until IS NOT NULL AND current_base > rule.until;
          ELSIF rule.skip = 'FORWARD' THEN
            current := date_trunc('month', current_base) + INTERVAL '1 month'
              + (basedate::time)::interval;
            EXIT WHEN rule.until IS NOT NULL AND current IS NOT NULL AND current > rule.until;
            EXIT WHEN current > maxdate;
            occurrence_count := occurrence_count + 1;
            IF rule.count IS NOT NULL AND occurrence_count > rule.count THEN
              EXIT;
            END IF;
            IF current >= mindate THEN
              RETURN NEXT current;
              emitted_count := emitted_count + 1;
              EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
            END IF;
            current_base := current_base + make_interval(months => rule.interval);
            current_base := date_trunc('month', current_base)
              + make_interval(days => LEAST(dtstart_day,
                  date_part('day', (date_trunc('month', current_base) + INTERVAL '1 month - 1 day'))::INT) - 1)
              + (basedate::time)::interval;
          ELSE
            EXIT;
          END IF;
        END LOOP;
      END IF;

    ELSIF rule.freq = 'YEARLY' THEN
      period_start := date_trunc('year', current_base) + (current_base::time)::interval;
      min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
      FOR current IN SELECT y FROM rrule.yearly_set(current_base, rule, CASE WHEN rule.bysetpos IS NULL AND rule.bymonthday IS NULL AND rule.bymonth IS NULL THEN (CASE WHEN output_limit IS NULL THEN NULL ELSE GREATEST(output_limit - emitted_count, 0) END) ELSE NULL END) y WHERE y >= min_in_period LOOP
        EXIT WHEN rule.until IS NOT NULL AND current > rule.until;
        EXIT WHEN current > maxdate;
        occurrence_count := occurrence_count + 1;
        EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
        IF current >= mindate THEN
          RETURN NEXT current;
          emitted_count := emitted_count + 1;
          EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
        END IF;
      END LOOP;
      current_base := current_base + make_interval(years => rule.interval);
      IF rule.bymonthday IS NULL AND rule.byday IS NULL THEN
        -- Restore dtstart month+day to prevent cumulative drift from FORWARD
        current_base := date_trunc('year', current_base)
          + make_interval(months => date_part('month', basedate)::INT - 1)
          + make_interval(days => LEAST(dtstart_day,
              date_part('day', (date_trunc('year', current_base)
                + make_interval(months => date_part('month', basedate)::INT)
                - INTERVAL '1 day'))::INT) - 1)
          + (basedate::time)::interval;
        LOOP
          EXIT WHEN date_part('day', current_base)::INT = dtstart_day;
          IF rule.skip = 'OMIT' THEN
            -- Do NOT increment period_count here — the outer loop handles it.
            -- Skipped years should not count against the iteration budget.
            current_base := current_base + make_interval(years => rule.interval);
            current_base := date_trunc('year', current_base)
              + make_interval(months => date_part('month', basedate)::INT - 1)
              + make_interval(days => LEAST(dtstart_day,
                  date_part('day', (date_trunc('year', current_base)
                    + make_interval(months => date_part('month', basedate)::INT)
                    - INTERVAL '1 day'))::INT) - 1)
              + (basedate::time)::interval;
            EXIT WHEN current_base > maxdate;
            EXIT WHEN rule.until IS NOT NULL AND current_base > rule.until;
          ELSIF rule.skip = 'FORWARD' THEN
            current := date_trunc('month', current_base) + INTERVAL '1 month'
              + (basedate::time)::interval;
            EXIT WHEN rule.until IS NOT NULL AND current IS NOT NULL AND current > rule.until;
            EXIT WHEN current > maxdate;
            occurrence_count := occurrence_count + 1;
            IF rule.count IS NOT NULL AND occurrence_count > rule.count THEN
              EXIT;
            END IF;
            IF current >= mindate THEN
              RETURN NEXT current;
              emitted_count := emitted_count + 1;
              EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
            END IF;
            current_base := current_base + make_interval(years => rule.interval);
            current_base := date_trunc('year', current_base)
              + make_interval(months => date_part('month', basedate)::INT - 1)
              + make_interval(days => LEAST(dtstart_day,
                  date_part('day', (date_trunc('year', current_base)
                    + make_interval(months => date_part('month', basedate)::INT)
                    - INTERVAL '1 day'))::INT) - 1)
              + (basedate::time)::interval;
          ELSE
            EXIT;
          END IF;
        END LOOP;
      END IF;

    -- ⚠️  SUB-DAY FREQUENCIES ENABLED ⚠️
    -- These are active in this file. See header comments for security implications.

    ELSIF rule.freq = 'HOURLY' THEN
      period_start := date_trunc('hour', current_base);
      min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
      FOR current IN SELECT h FROM rrule.hourly_set(current_base, rule) h WHERE h >= min_in_period LOOP
        EXIT WHEN rule.until IS NOT NULL AND current > rule.until;
        EXIT WHEN current > maxdate;
        occurrence_count := occurrence_count + 1;
        EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
        IF current >= mindate THEN
          RETURN NEXT current;
          emitted_count := emitted_count + 1;
          EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
        END IF;
      END LOOP;
      current_base := current_base + make_interval(hours => rule.interval);

    ELSIF rule.freq = 'MINUTELY' THEN
      period_start := date_trunc('minute', current_base);
      min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
      FOR current IN SELECT m FROM rrule.minutely_set(current_base, rule) m WHERE m >= min_in_period LOOP
        EXIT WHEN rule.until IS NOT NULL AND current > rule.until;
        EXIT WHEN current > maxdate;
        occurrence_count := occurrence_count + 1;
        EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
        IF current >= mindate THEN
          RETURN NEXT current;
          emitted_count := emitted_count + 1;
          EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
        END IF;
      END LOOP;
      current_base := current_base + make_interval(mins => rule.interval);

    ELSIF rule.freq = 'SECONDLY' THEN
      period_start := date_trunc('second', current_base);
      min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
      FOR current IN SELECT s FROM rrule.secondly_set(current_base, rule) s WHERE s >= min_in_period LOOP
        EXIT WHEN rule.until IS NOT NULL AND current > rule.until;
        EXIT WHEN current > maxdate;
        occurrence_count := occurrence_count + 1;
        EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
        IF current >= mindate THEN
          RETURN NEXT current;
          emitted_count := emitted_count + 1;
          EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
        END IF;
      END LOOP;
      current_base := current_base + make_interval(secs => rule.interval);

    ELSE
      RAISE EXCEPTION 'Unsupported frequency: %. Valid values are: DAILY, WEEKLY, MONTHLY, YEARLY, HOURLY, MINUTELY, SECONDLY', rule.freq;
    END IF;
    period_count := period_count + 1;
    EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
    EXIT WHEN rule.count IS NOT NULL AND occurrence_count >= rule.count;
    EXIT WHEN rule.until IS NOT NULL AND current_base > rule.until;
  END LOOP;

  -- Warn if result set was truncated by API limit (not by rule's natural COUNT/UNTIL termination)
  IF output_limit IS NOT NULL AND emitted_count >= output_limit THEN
    IF (rule.count IS NULL OR occurrence_count < rule.count)
       AND (rule.until IS NULL) THEN
      RAISE WARNING 'rrule: result set truncated at % occurrences (limit: %). The recurrence rule has no COUNT or UNTIL and may produce more results beyond this limit.', emitted_count, output_limit;
    END IF;
  END IF;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT SET timezone = 'UTC';


------------------------------------------------------------------------------------------------------
-- Override rrule_event_instances_range_tz to enable sub-day frequencies in TIMESTAMPTZ API
-- This replaces the version from rrule.sql which only supports DAILY/WEEKLY/MONTHLY/YEARLY.
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rrule_event_instances_range_tz(
    basedate TIMESTAMP,
    repeatrule TEXT,
    mindate TIMESTAMP,
    maxdate TIMESTAMP,
    max_count INT
) RETURNS SETOF TIMESTAMP AS $$
DECLARE
    period_limit INT;
    period_count INT := 0;
    occurrence_count INT := 0;
    emitted_count INT := 0;
    output_limit INT;
    dtstart_day INT;
    current_base TIMESTAMP;
    current TIMESTAMP;
    period_start TIMESTAMP;
    min_in_period TIMESTAMP;
    rule rrule.rrule_parts%ROWTYPE;
BEGIN
    SELECT * INTO rule FROM rrule.parse_rrule_parts( basedate::TIMESTAMPTZ, repeatrule );

    output_limit := max_count;
    IF rule.count IS NOT NULL THEN
        output_limit := COALESCE(output_limit, rule.count);
        output_limit := LEAST(output_limit, rule.count);
    END IF;

    period_limit := rrule.calculate_safe_iteration_limit(rule.freq, rule.count, output_limit, rule.interval);
    IF period_limit IS NULL THEN
        period_limit := 2147483647;
    END IF;

    dtstart_day := date_part('day', basedate)::INT;

    current_base := basedate;

    -- Early exit: UNTIL before dtstart means no occurrences possible
    IF rule.until IS NOT NULL AND rule.until < basedate::TIMESTAMPTZ THEN
        RETURN;
    END IF;

    WHILE period_count < period_limit AND current_base < maxdate LOOP
        IF rule.freq = 'DAILY' THEN
            period_start := date_trunc('day', current_base) + (current_base::time)::interval;
            min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
            FOR current IN
                SELECT d::TIMESTAMP
                FROM rrule.daily_set(current_base::TIMESTAMPTZ, rule,
                    CASE WHEN rule.bysetpos IS NULL AND rule.bymonthday IS NULL AND rule.bymonth IS NULL
                         THEN (CASE WHEN output_limit IS NULL THEN NULL
                               ELSE GREATEST(output_limit - emitted_count, 0) END)
                         ELSE NULL END) d
                WHERE d::TIMESTAMP >= min_in_period
            LOOP
                EXIT WHEN rule.until IS NOT NULL AND current::TIMESTAMPTZ > rule.until;
                EXIT WHEN current > maxdate;
                occurrence_count := occurrence_count + 1;
                EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
                IF current >= mindate THEN
                    RETURN NEXT current;
                    emitted_count := emitted_count + 1;
                    EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
                END IF;
            END LOOP;
            current_base := current_base + make_interval(days => rule.interval);

        ELSIF rule.freq = 'WEEKLY' THEN
            period_start := rrule.get_week_start(current_base::TIMESTAMPTZ, rule.wkst)::TIMESTAMP + (current_base::time)::interval;
            min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
            FOR current IN
                SELECT w::TIMESTAMP
                FROM rrule.weekly_set(current_base::TIMESTAMPTZ, rule,
                    CASE WHEN rule.bysetpos IS NULL AND rule.bymonthday IS NULL AND rule.bymonth IS NULL
                         THEN (CASE WHEN output_limit IS NULL THEN NULL
                               ELSE GREATEST(output_limit - emitted_count, 0) END)
                         ELSE NULL END) w
                WHERE w::TIMESTAMP >= min_in_period
            LOOP
                -- Time boundary checks apply regardless of BYxxx filters
                EXIT WHEN rule.until IS NOT NULL AND current::TIMESTAMPTZ > rule.until;
                EXIT WHEN current > maxdate;
                IF rrule.test_byyearday_rule(current::TIMESTAMPTZ, rule.byyearday)
                   AND rrule.test_bymonthday_rule(current::TIMESTAMPTZ, rule.bymonthday)
                   AND rrule.test_bymonth_rule(current::TIMESTAMPTZ, rule.bymonth)
                THEN
                    occurrence_count := occurrence_count + 1;
                    EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
                    IF current >= mindate THEN
                        RETURN NEXT current;
                        emitted_count := emitted_count + 1;
                        EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
                    END IF;
                END IF;
            END LOOP;
            current_base := current_base + make_interval(weeks => rule.interval);

        ELSIF rule.freq = 'MONTHLY' THEN
            period_start := date_trunc('month', current_base) + (current_base::time)::interval;
            min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
            FOR current IN
                SELECT m::TIMESTAMP
                FROM rrule.monthly_set(current_base::TIMESTAMPTZ, rule,
                    CASE WHEN rule.bysetpos IS NULL AND rule.bymonthday IS NULL AND rule.bymonth IS NULL
                         THEN (CASE WHEN output_limit IS NULL THEN NULL
                               ELSE GREATEST(output_limit - emitted_count, 0) END)
                         ELSE NULL END) m
                WHERE m::TIMESTAMP >= min_in_period
            LOOP
                EXIT WHEN rule.until IS NOT NULL AND current::TIMESTAMPTZ > rule.until;
                EXIT WHEN current > maxdate;
                -- Cross-period dedup: SKIP=FORWARD can push dates into the next period
                CONTINUE WHEN prev_period_max_ts IS NOT NULL AND current = prev_period_max_ts;
                occurrence_count := occurrence_count + 1;
                EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
                IF current >= mindate THEN
                    RETURN NEXT current;
                    emitted_count := emitted_count + 1;
                    EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
                END IF;
                prev_period_max_ts := current;
            END LOOP;
            current_base := current_base + make_interval(months => rule.interval);
            IF rule.bymonthday IS NULL AND rule.byday IS NULL THEN
              -- Restore dtstart day-of-month to prevent cumulative drift from FORWARD
              current_base := date_trunc('month', current_base)
                + make_interval(days => LEAST(dtstart_day,
                    date_part('day', (date_trunc('month', current_base) + INTERVAL '1 month - 1 day'))::INT) - 1)
                + (basedate::time)::interval;
              LOOP
                EXIT WHEN date_part('day', current_base)::INT = dtstart_day;
                IF rule.skip = 'OMIT' THEN
                  -- Do NOT increment period_count here — the outer loop handles it.
                  -- Skipped months should not count against the iteration budget.
                  current_base := current_base + make_interval(months => rule.interval);
                  current_base := date_trunc('month', current_base)
                    + make_interval(days => LEAST(dtstart_day,
                        date_part('day', (date_trunc('month', current_base) + INTERVAL '1 month - 1 day'))::INT) - 1)
                    + (basedate::time)::interval;
                  EXIT WHEN current_base > maxdate;
                  EXIT WHEN rule.until IS NOT NULL AND current_base::TIMESTAMPTZ > rule.until;
                ELSIF rule.skip = 'FORWARD' THEN
                  current := (date_trunc('month', current_base) + INTERVAL '1 month'
                    + (basedate::time)::interval)::TIMESTAMP;
                  EXIT WHEN rule.until IS NOT NULL AND current IS NOT NULL AND current::TIMESTAMPTZ > rule.until;
                  EXIT WHEN current > maxdate;
                  occurrence_count := occurrence_count + 1;
                  IF rule.count IS NOT NULL AND occurrence_count > rule.count THEN
                    EXIT;
                  END IF;
                  IF current >= mindate THEN
                    RETURN NEXT current;
                    emitted_count := emitted_count + 1;
                    EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
                  END IF;
                  current_base := current_base + make_interval(months => rule.interval);
                  current_base := date_trunc('month', current_base)
                    + make_interval(days => LEAST(dtstart_day,
                        date_part('day', (date_trunc('month', current_base) + INTERVAL '1 month - 1 day'))::INT) - 1)
                    + (basedate::time)::interval;
                ELSE
                  EXIT;
                END IF;
              END LOOP;
            END IF;

        ELSIF rule.freq = 'YEARLY' THEN
            period_start := date_trunc('year', current_base) + (current_base::time)::interval;
            min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
            FOR current IN
                SELECT y::TIMESTAMP
                FROM rrule.yearly_set(current_base::TIMESTAMPTZ, rule,
                    CASE WHEN rule.bysetpos IS NULL AND rule.bymonthday IS NULL AND rule.bymonth IS NULL
                         THEN (CASE WHEN output_limit IS NULL THEN NULL
                               ELSE GREATEST(output_limit - emitted_count, 0) END)
                         ELSE NULL END) y
                WHERE y::TIMESTAMP >= min_in_period
            LOOP
                EXIT WHEN rule.until IS NOT NULL AND current::TIMESTAMPTZ > rule.until;
                EXIT WHEN current > maxdate;
                occurrence_count := occurrence_count + 1;
                EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
                IF current >= mindate THEN
                    RETURN NEXT current;
                    emitted_count := emitted_count + 1;
                    EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
                END IF;
            END LOOP;
            current_base := current_base + make_interval(years => rule.interval);
            IF rule.bymonthday IS NULL AND rule.byday IS NULL THEN
              -- Restore dtstart month+day to prevent cumulative drift from FORWARD
              current_base := date_trunc('year', current_base)
                + make_interval(months => date_part('month', basedate)::INT - 1)
                + make_interval(days => LEAST(dtstart_day,
                    date_part('day', (date_trunc('year', current_base)
                      + make_interval(months => date_part('month', basedate)::INT)
                      - INTERVAL '1 day'))::INT) - 1)
                + (basedate::time)::interval;
              LOOP
                EXIT WHEN date_part('day', current_base)::INT = dtstart_day;
                IF rule.skip = 'OMIT' THEN
                  -- Do NOT increment period_count here — the outer loop handles it.
                  -- Skipped years should not count against the iteration budget.
                  current_base := current_base + make_interval(years => rule.interval);
                  current_base := date_trunc('year', current_base)
                    + make_interval(months => date_part('month', basedate)::INT - 1)
                    + make_interval(days => LEAST(dtstart_day,
                        date_part('day', (date_trunc('year', current_base)
                          + make_interval(months => date_part('month', basedate)::INT)
                          - INTERVAL '1 day'))::INT) - 1)
                    + (basedate::time)::interval;
                  EXIT WHEN current_base > maxdate;
                  EXIT WHEN rule.until IS NOT NULL AND current_base::TIMESTAMPTZ > rule.until;
                ELSIF rule.skip = 'FORWARD' THEN
                  current := (date_trunc('month', current_base) + INTERVAL '1 month'
                    + (basedate::time)::interval)::TIMESTAMP;
                  EXIT WHEN rule.until IS NOT NULL AND current IS NOT NULL AND current::TIMESTAMPTZ > rule.until;
                  EXIT WHEN current > maxdate;
                  occurrence_count := occurrence_count + 1;
                  IF rule.count IS NOT NULL AND occurrence_count > rule.count THEN
                    EXIT;
                  END IF;
                  IF current >= mindate THEN
                    RETURN NEXT current;
                    emitted_count := emitted_count + 1;
                    EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
                  END IF;
                  current_base := current_base + make_interval(years => rule.interval);
                  current_base := date_trunc('year', current_base)
                    + make_interval(months => date_part('month', basedate)::INT - 1)
                    + make_interval(days => LEAST(dtstart_day,
                        date_part('day', (date_trunc('year', current_base)
                          + make_interval(months => date_part('month', basedate)::INT)
                          - INTERVAL '1 day'))::INT) - 1)
                    + (basedate::time)::interval;
                ELSE
                  EXIT;
                END IF;
              END LOOP;
            END IF;

        -- Sub-day frequencies (TZ-aware)
        ELSIF rule.freq = 'HOURLY' THEN
            period_start := date_trunc('hour', current_base);
            min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
            FOR current IN SELECT h::TIMESTAMP FROM rrule.hourly_set(current_base::TIMESTAMPTZ, rule) h WHERE h::TIMESTAMP >= min_in_period LOOP
                EXIT WHEN rule.until IS NOT NULL AND current::TIMESTAMPTZ > rule.until;
                EXIT WHEN current > maxdate;
                occurrence_count := occurrence_count + 1;
                EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
                IF current >= mindate THEN
                    RETURN NEXT current;
                    emitted_count := emitted_count + 1;
                    EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
                END IF;
            END LOOP;
            current_base := current_base + make_interval(hours => rule.interval);

        ELSIF rule.freq = 'MINUTELY' THEN
            period_start := date_trunc('minute', current_base);
            min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
            FOR current IN SELECT m::TIMESTAMP FROM rrule.minutely_set(current_base::TIMESTAMPTZ, rule) m WHERE m::TIMESTAMP >= min_in_period LOOP
                EXIT WHEN rule.until IS NOT NULL AND current::TIMESTAMPTZ > rule.until;
                EXIT WHEN current > maxdate;
                occurrence_count := occurrence_count + 1;
                EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
                IF current >= mindate THEN
                    RETURN NEXT current;
                    emitted_count := emitted_count + 1;
                    EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
                END IF;
            END LOOP;
            current_base := current_base + make_interval(mins => rule.interval);

        ELSIF rule.freq = 'SECONDLY' THEN
            period_start := date_trunc('second', current_base);
            min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
            FOR current IN SELECT s::TIMESTAMP FROM rrule.secondly_set(current_base::TIMESTAMPTZ, rule) s WHERE s::TIMESTAMP >= min_in_period LOOP
                EXIT WHEN rule.until IS NOT NULL AND current::TIMESTAMPTZ > rule.until;
                EXIT WHEN current > maxdate;
                occurrence_count := occurrence_count + 1;
                EXIT WHEN rule.count IS NOT NULL AND occurrence_count > rule.count;
                IF current >= mindate THEN
                    RETURN NEXT current;
                    emitted_count := emitted_count + 1;
                    EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
                END IF;
            END LOOP;
            current_base := current_base + make_interval(secs => rule.interval);

        ELSE
            RAISE EXCEPTION 'Unsupported frequency: %', rule.freq;
        END IF;
        period_count := period_count + 1;
        EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
        EXIT WHEN rule.count IS NOT NULL AND occurrence_count >= rule.count;
        EXIT WHEN rule.until IS NOT NULL AND current_base::TIMESTAMPTZ > rule.until;
    END LOOP;

    IF output_limit IS NOT NULL AND emitted_count >= output_limit THEN
      IF (rule.count IS NULL OR occurrence_count < rule.count)
         AND (rule.until IS NULL) THEN
        RAISE WARNING 'rrule: result set truncated at % occurrences (limit: %). The recurrence rule has no COUNT or UNTIL and may produce more results beyond this limit.', emitted_count, output_limit;
      END IF;
    END IF;
END;
$$ LANGUAGE plpgsql VOLATILE SET search_path = rrule, pg_catalog;
