/**
* PostgreSQL Functions for RRULE handling
*
* @license MIT License
*
* COMPREHENSIVE RFC 5545 RRULE IMPLEMENTATION
* ==========================================
*
* ✅ FULLY SUPPORTED FREQUENCIES:
*  - DAILY frequency, including:
*    BYDAY, BYMONTH, BYMONTHDAY, BYWEEKNO, BYYEARDAY, BYHOUR, BYMINUTE, BYSECOND, BYSETPOS
*  - WEEKLY frequency, including:
*    BYDAY, BYMONTH, BYMONTHDAY, BYWEEKNO, BYYEARDAY, BYSETPOS
*  - MONTHLY frequency, including:
*    BYDAY, BYMONTH, BYMONTHDAY, BYWEEKNO, BYYEARDAY, BYSETPOS
*  - YEARLY frequency, including:
*    BYMONTH, BYMONTHDAY, BYYEARDAY (positive & negative indices), BYWEEKNO, BYDAY, BYSETPOS
*
* ✅ UNIVERSAL MODIFIERS:
*  - COUNT & UNTIL limits
*  - INTERVAL (every N days/weeks/months/years)
*
* ⚠️ SUB-DAY FREQUENCIES (Implemented but Commented Out by Default):
*  - HOURLY   - Fully implemented with safety limits (see line ~697)
*  - MINUTELY - Fully implemented with safety limits (see line ~742)
*  - SECONDLY - Fully implemented with safety limits (see line ~787)
*
* WHY COMMENTED OUT?
*  Sub-day frequencies can generate millions of occurrences, causing denial-of-service
*  in multi-tenant environments. They are production-ready but disabled by default.
*  See main event loop (line ~928) for detailed security documentation and instructions
*  on how to enable them safely with proper validation and limits.
*
* RFC 5545 COMPLIANCE (~97%):
*  This implementation supports all major RRULE features from RFC 5545.
*  All parameter combinations work, including YEARLY + BYMONTH + BYYEARDAY
*  (BYMONTH generates candidates, BYYEARDAY filters as intersection).
*  See SPEC_COMPLIANCE.md for documented limitations.
*
*/

-- Set search path to rrule schema so all functions are created there
SET search_path = rrule, public;

-- Create a composite type for the parts of the RRULE.
-- Note: This file is designed to be loaded via install.sql which drops/recreates
-- the entire schema. For updates, reinstall using install.sql.
-- Idempotent: only create if the type does not already exist.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_type t
        JOIN pg_namespace n ON t.typnamespace = n.oid
        WHERE t.typname = 'rrule_parts' AND n.nspname = 'rrule'
    ) THEN
        CREATE TYPE rrule_parts AS (
          base TIMESTAMP WITH TIME ZONE,
          until TIMESTAMP WITH TIME ZONE,
          freq TEXT,
          count INT,
          interval INT,
          bysecond INT[],
          byminute INT[],
          byhour INT[],
          bymonthday INT[],
          byyearday INT[],
          byweekno INT[],
          byday TEXT[],
          bymonth INT[],
          bysetpos INT[],
          wkst TEXT,
          tzid TEXT,
          rscale TEXT,  -- RFC 7529: Calendar system ('GREGORIAN', etc.)
          skip TEXT     -- RFC 7529: 'OMIT', 'BACKWARD', 'FORWARD' (default: 'OMIT')
        );
    END IF;
END $$;


-- Create a composite type for SKIP advancement results.
-- Used by _advance_monthly and _advance_yearly helpers to return multiple values
-- without SELECT INTO overhead.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_type t
        JOIN pg_namespace n ON t.typnamespace = n.oid
        WHERE t.typname = '_skip_result' AND n.nspname = 'rrule'
    ) THEN
        CREATE TYPE _skip_result AS (
          current_base   TIMESTAMPTZ,  -- Updated base timestamp for next iteration
          forward_ts     TIMESTAMPTZ,  -- Non-NULL only when SKIP=FORWARD produced a date to emit
          done           BOOLEAN,      -- TRUE = exit the SKIP inner loop
          omit_count     INT,          -- Running count of OMIT iterations
          period_count   INT           -- Running count of periods (for DoS protection)
        );
    END IF;
END $$;


-- Create a function to parse the RRULE into its composite type
CREATE OR REPLACE FUNCTION parse_rrule_parts(
  basedate TIMESTAMP WITH TIME ZONE,
  repeatrule TEXT
) RETURNS rrule.rrule_parts AS $$
DECLARE
  result rrule.rrule_parts%ROWTYPE;
  until_str TEXT;
  original_tzid TEXT;
BEGIN
  -- Preserve TZID case before normalizing (timezone names are case-sensitive)
  original_tzid := substring(repeatrule from '[Tt][Zz][Ii][Dd]=([^;]+)(;|$)');
  -- Normalize input to uppercase for case-insensitive matching
  -- RFC 5545 uses uppercase, but we accept lowercase for user convenience
  repeatrule := UPPER(repeatrule);

  result.base       := basedate;
  until_str         := substring(repeatrule from 'UNTIL=([0-9TZ]+)(;|$)');

  -- Validate and assign UNTIL with helpful error message
  -- Design decision: DECISIONS.md #4 — UNTIL must be UTC DATE-TIME with Z suffix.
  -- RFC 5545 §3.3.10 requires UNTIL to match DTSTART value type (DATE-TIME here).
  IF until_str IS NOT NULL THEN
    -- Require UTC DATE-TIME (YYYYMMDDTHHMMSSZ). Date-only UNTIL is not allowed here.
    -- These checks are OUTSIDE the exception block so they aren't caught by WHEN OTHERS.
    IF until_str ~ '^[0-9]{8}$' THEN
      RAISE EXCEPTION 'Invalid RRULE: UNTIL=% is a date-only value. This API uses DATE-TIME DTSTART, so UNTIL must be a UTC DATE-TIME (YYYYMMDDTHHMMSSZ).  RFC 5545 Section 3.3.10: UNTIL MUST be the same value type as DTSTART.', until_str;
    END IF;
    IF until_str !~ 'Z$' THEN
      RAISE EXCEPTION 'Invalid RRULE: UNTIL=% must be specified in UTC and end with "Z" (e.g., UNTIL=20251231T235959Z).  RFC 5545 Section 3.3.10: DATE-TIME UNTIL MUST be UTC when DTSTART is DATE-TIME with timezone.', until_str;
    END IF;
    -- Only the cast is inside the exception block
    BEGIN
      result.until := until_str::TIMESTAMPTZ;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE EXCEPTION 'Invalid RRULE: UNTIL=% is not a valid timestamp. RFC 5545 requires UTC DATE-TIME format YYYYMMDDTHHMMSSZ (e.g., UNTIL=20251231T235959Z). Error: %',
          until_str,
          SQLERRM;
    END;
  END IF;

  result.freq       := substring(repeatrule from 'FREQ=([A-Z]+)(;|$)');

  -- Reject duplicate FREQ parameters (e.g., "FREQ=DAILY;FREQ=WEEKLY")
  IF repeatrule ~ 'FREQ=[A-Z]+.*;.*FREQ=' THEN
    RAISE EXCEPTION 'Invalid RRULE: Duplicate FREQ parameter. Only one FREQ is allowed per RRULE.  RFC 5545 Section 3.3.10: Each rule part MUST only be specified once.';
  END IF;

  -- Reject duplicate parameters per RFC 5545 Section 3.3.10:
  -- "Each rule part MUST only be specified once."
  DECLARE
    _dup_params TEXT[] := ARRAY['COUNT', 'UNTIL', 'INTERVAL', 'WKST', 'TZID', 'RSCALE', 'SKIP',
                                'BYDAY', 'BYMONTH', 'BYMONTHDAY', 'BYYEARDAY', 'BYWEEKNO', 'BYSETPOS',
                                'BYHOUR', 'BYMINUTE', 'BYSECOND'];
    _dup_param TEXT;
  BEGIN
    FOREACH _dup_param IN ARRAY _dup_params LOOP
      IF (SELECT COUNT(*) FROM regexp_matches(repeatrule, '(^|;)' || _dup_param || '=', 'g')) > 1 THEN
        RAISE EXCEPTION 'Invalid RRULE: Duplicate % parameter. RFC 5545 Section 3.3.10: Each rule part MUST only be specified once.', _dup_param;
      END IF;
    END LOOP;
  END;

  -- Check for negative COUNT value in raw RRULE string before parsing
  IF repeatrule ~* 'COUNT=-' THEN
    RAISE EXCEPTION 'Invalid RRULE: COUNT must be a positive integer';
  END IF;
  -- Only the cast is inside the exception block
  BEGIN
    result.count      := substring(repeatrule from 'COUNT=([0-9]+)(;|$)')::INT;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Invalid RRULE: COUNT value out of range: must be a valid integer. Error: %',
        SQLERRM;
  END;

  -- Check for negative INTERVAL value in raw RRULE string before parsing
  IF repeatrule ~* 'INTERVAL=-' THEN
    RAISE EXCEPTION 'Invalid RRULE: INTERVAL must be a positive integer';
  END IF;
  -- Only the cast is inside the exception block
  BEGIN
    result.interval   := COALESCE(substring(repeatrule from 'INTERVAL=([0-9]+)(;|$)')::INT, 1);
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Invalid RRULE: INTERVAL value out of range: must be a valid integer. Error: %',
        SQLERRM;
  END;

  result.wkst       := substring(repeatrule from 'WKST=(MO|TU|WE|TH|FR|SA|SU)(;|$)');
  -- Validate WKST: if WKST= was specified but didn't match a valid day, reject it
  IF result.wkst IS NULL AND repeatrule ~ 'WKST=' THEN
    RAISE EXCEPTION 'Invalid WKST value. WKST must be one of: MO, TU, WE, TH, FR, SA, SU';
  END IF;
  result.tzid       := original_tzid;  -- Use preserved case from before uppercase normalization

  -- RFC 7529: RSCALE parameter (calendar system)
  result.rscale     := UPPER(substring(repeatrule from 'RSCALE=([A-Za-z]+)(;|$)'));

  -- RFC 7529: SKIP parameter
  result.skip       := COALESCE(UPPER(substring(repeatrule from 'SKIP=([A-Za-z]+)(;|$)')), 'OMIT');

  -- Validate SKIP: if SKIP= was specified but didn't match a valid value, reject it
  IF result.skip NOT IN ('OMIT', 'BACKWARD', 'FORWARD') AND repeatrule ~* 'SKIP=' THEN
    RAISE EXCEPTION 'Invalid SKIP value. SKIP must be one of: OMIT, BACKWARD, FORWARD';
  END IF;

  -- Validate RSCALE: if RSCALE= was specified but didn't match a valid value, reject it
  IF result.rscale IS NULL AND repeatrule ~ 'RSCALE=' THEN
    RAISE EXCEPTION 'Invalid RRULE: RSCALE value could not be parsed. RSCALE requires an alphabetic calendar name (e.g., RSCALE=GREGORIAN).';
  END IF;

  -- RFC 7529 Compliance: SKIP requires RSCALE
  -- If SKIP is specified (and not default OMIT) but RSCALE is missing,
  -- auto-add RSCALE=GREGORIAN for RFC 7529 compliance
  IF result.skip IS NOT NULL AND result.skip != 'OMIT' AND result.rscale IS NULL THEN
    result.rscale := 'GREGORIAN';
  END IF;

  -- Validate RSCALE if present (only GREGORIAN supported)
  IF result.rscale IS NOT NULL AND result.rscale != 'GREGORIAN' THEN
    RAISE EXCEPTION 'Unsupported RSCALE value: "%". Only GREGORIAN calendar is currently supported.  RFC 7529 defines other calendar systems (HEBREW, ISLAMIC, CHINESE, etc.),  but this implementation only supports the Gregorian calendar.', result.rscale;
  END IF;

  result.byday      := array_remove(
                         string_to_array( substring(repeatrule from 'BYDAY=(([+-]?[0-9]{0,2}(MO|TU|WE|TH|FR|SA|SU),?)+)(;|$)'), ','),
                         '');

  BEGIN
    result.byyearday  := array_remove(
                           string_to_array(substring(repeatrule from 'BYYEARDAY=([0-9,+-]+)(;|$)'), ','),
                           '');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Invalid RRULE: BYYEARDAY value out of range: must be valid integers. Error: %',
        SQLERRM;
  END;
  BEGIN
    result.byweekno   := array_remove(
                           string_to_array(substring(repeatrule from 'BYWEEKNO=([0-9,+-]+)(;|$)'), ','),
                           '');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Invalid RRULE: BYWEEKNO value out of range: must be valid integers. Error: %',
        SQLERRM;
  END;
  BEGIN
    result.bymonthday := array_remove(
                           string_to_array(substring(repeatrule from 'BYMONTHDAY=([0-9,+-]+)(;|$)'), ','),
                           '');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Invalid RRULE: BYMONTHDAY value out of range: must be valid integers. Error: %',
        SQLERRM;
  END;
  result.bymonth    := array_remove(
                         string_to_array(substring(repeatrule from 'BYMONTH=(([+-]?[0-1]?[0-9],?)+)(;|$)'), ','),
                         '');
  result.bysetpos   := array_remove(
                         string_to_array(substring(repeatrule from 'BYSETPOS=(([+-]?[0-9]{1,3},?)+)(;|$)'), ','),
                         '');

  -- Deduplicate BYYEARDAY and BYWEEKNO arrays to prevent duplicate occurrence generation
  -- (e.g., BYYEARDAY=100,100 or BYWEEKNO=1,1 would otherwise produce duplicates)
  IF result.byyearday IS NOT NULL THEN
    SELECT array_agg(val ORDER BY idx) INTO result.byyearday
    FROM (SELECT DISTINCT ON (val) val, idx
          FROM unnest(result.byyearday) WITH ORDINALITY AS t(val, idx)
          ORDER BY val, idx) sub;
  END IF;
  IF result.byweekno IS NOT NULL THEN
    SELECT array_agg(val ORDER BY idx) INTO result.byweekno
    FROM (SELECT DISTINCT ON (val) val, idx
          FROM unnest(result.byweekno) WITH ORDINALITY AS t(val, idx)
          ORDER BY val, idx) sub;
  END IF;

  result.bysecond   := array_remove(
                         string_to_array(substring(repeatrule from 'BYSECOND=([0-9,+-]+)(;|$)'), ','),
                         '');
  result.byminute   := array_remove(
                         string_to_array(substring(repeatrule from 'BYMINUTE=([0-9,+-]+)(;|$)'), ','),
                         '');
  result.byhour     := array_remove(
                         string_to_array(substring(repeatrule from 'BYHOUR=([0-9,+-]+)(;|$)'), ','),
                         '');

  -- Deduplicate BYHOUR, BYMINUTE, BYSECOND arrays to prevent duplicate timestamp generation
  -- (e.g., BYHOUR=9,9,10 should not emit hour 9 twice in rrule_day_time_set)
  IF result.byhour IS NOT NULL THEN
    SELECT array_agg(val ORDER BY idx) INTO result.byhour
    FROM (SELECT DISTINCT ON (val) val, idx
          FROM unnest(result.byhour) WITH ORDINALITY AS t(val, idx)
          ORDER BY val, idx) sub;
  END IF;
  IF result.byminute IS NOT NULL THEN
    SELECT array_agg(val ORDER BY idx) INTO result.byminute
    FROM (SELECT DISTINCT ON (val) val, idx
          FROM unnest(result.byminute) WITH ORDINALITY AS t(val, idx)
          ORDER BY val, idx) sub;
  END IF;
  IF result.bysecond IS NOT NULL THEN
    SELECT array_agg(val ORDER BY idx) INTO result.bysecond
    FROM (SELECT DISTINCT ON (val) val, idx
          FROM unnest(result.bysecond) WITH ORDINALITY AS t(val, idx)
          ORDER BY val, idx) sub;
  END IF;

  -- ========================================================================
  -- BYxxx PARSE-FAILURE DETECTION
  -- ========================================================================
  -- Detect when a BYxxx keyword is present in the RRULE string but the regex
  -- failed to extract a value (e.g., BYMONTH=FOO, BYDAY=XY). Without these
  -- checks, malformed values silently become NULL and skip all validation.
  -- Pattern matches WKST (line 109) and SKIP (line 121) validation style.

  IF result.byday IS NULL AND repeatrule ~ 'BYDAY=' THEN
    RAISE EXCEPTION 'Invalid RRULE: BYDAY value could not be parsed. BYDAY requires comma-separated day codes (MO,TU,WE,TH,FR,SA,SU) with optional ordinals (e.g., BYDAY=MO,WE,FR or BYDAY=2MO,-1FR).';
  END IF;

  IF result.byyearday IS NULL AND repeatrule ~ 'BYYEARDAY=' THEN
    RAISE EXCEPTION 'Invalid RRULE: BYYEARDAY value could not be parsed. BYYEARDAY requires comma-separated integers ±1-366 (e.g., BYYEARDAY=1,100,-1).';
  END IF;

  IF result.byweekno IS NULL AND repeatrule ~ 'BYWEEKNO=' THEN
    RAISE EXCEPTION 'Invalid RRULE: BYWEEKNO value could not be parsed. BYWEEKNO requires comma-separated integers ±1-53 (e.g., BYWEEKNO=1,20).';
  END IF;

  IF result.bymonthday IS NULL AND repeatrule ~ 'BYMONTHDAY=' THEN
    RAISE EXCEPTION 'Invalid RRULE: BYMONTHDAY value could not be parsed. BYMONTHDAY requires comma-separated integers ±1-31 (e.g., BYMONTHDAY=1,15,-1).';
  END IF;

  IF result.bymonth IS NULL AND repeatrule ~ 'BYMONTH=' THEN
    RAISE EXCEPTION 'Invalid RRULE: BYMONTH value could not be parsed. BYMONTH requires comma-separated integers 1-12 (e.g., BYMONTH=1,6,12).';
  END IF;

  IF result.bysetpos IS NULL AND repeatrule ~ 'BYSETPOS=' THEN
    RAISE EXCEPTION 'Invalid RRULE: BYSETPOS value could not be parsed. BYSETPOS requires comma-separated integers ±1-366 (e.g., BYSETPOS=1,-1).';
  END IF;

  IF result.bysecond IS NULL AND repeatrule ~ 'BYSECOND=' THEN
    RAISE EXCEPTION 'Invalid RRULE: BYSECOND value could not be parsed. BYSECOND requires comma-separated integers 0-60 (e.g., BYSECOND=0,30).';
  END IF;

  IF result.byminute IS NULL AND repeatrule ~ 'BYMINUTE=' THEN
    RAISE EXCEPTION 'Invalid RRULE: BYMINUTE value could not be parsed. BYMINUTE requires comma-separated integers 0-59 (e.g., BYMINUTE=0,15,30,45).';
  END IF;

  IF result.byhour IS NULL AND repeatrule ~ 'BYHOUR=' THEN
    RAISE EXCEPTION 'Invalid RRULE: BYHOUR value could not be parsed. BYHOUR requires comma-separated integers 0-23 (e.g., BYHOUR=9,17).';
  END IF;

  -- ========================================================================
  -- RFC 5545 CONSTRAINT VALIDATIONS
  -- ========================================================================
  -- The following validations enforce RFC 5545 Section 3.3.10 requirements
  -- to ensure only valid RRULEs are accepted.

  -- Validation 1: FREQ is REQUIRED
  IF result.freq IS NULL THEN
    RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required. Specify one of: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, or YEARLY.  RFC 5545 Section 3.3.10: "FREQ rule part is REQUIRED"';
  END IF;

  -- Validation 2: COUNT and UNTIL are mutually exclusive
  IF result.count IS NOT NULL AND result.until IS NOT NULL THEN
    RAISE EXCEPTION 'Invalid RRULE: COUNT and UNTIL are mutually exclusive. Specify either COUNT (number of occurrences) OR UNTIL (end date), not both. Current RRULE has COUNT=% and UNTIL=%.  RFC 5545 Section 3.3.10: "they MUST NOT occur in the same recur"', result.count, result.until;
  END IF;

  -- Validation 2b: INTERVAL must be positive (RFC 5545)
  IF result.interval IS NULL OR result.interval < 1 THEN
    RAISE EXCEPTION 'Invalid RRULE: INTERVAL must be a positive integer (>= 1). Current INTERVAL=%.  RFC 5545 Section 3.3.10: "INTERVAL rule part contains a positive integer"', result.interval;
  END IF;

  -- Validation 2b2: INTERVAL upper bound to prevent make_interval() overflow
  IF result.interval > 10000 THEN
    RAISE EXCEPTION 'Invalid RRULE: INTERVAL must not exceed 10000. Current INTERVAL=%. Large INTERVAL values risk overflow in date arithmetic.', result.interval;
  END IF;

  -- Validation 2c: COUNT must be a positive integer (RFC 5545)
  IF result.count IS NOT NULL AND result.count <= 0 THEN
    RAISE EXCEPTION 'Invalid RRULE: COUNT must be a positive integer, got %', result.count;
  END IF;

  -- Validation 3: BYWEEKNO only valid with YEARLY frequency
  IF result.byweekno IS NOT NULL AND result.freq != 'YEARLY' THEN
    RAISE EXCEPTION 'Invalid RRULE: BYWEEKNO can only be used with FREQ=YEARLY. Current FREQ=%. BYWEEKNO specifies ISO 8601 week numbers within a year. Use FREQ=YEARLY or remove BYWEEKNO.  RFC 5545 Section 3.3.10: "BYWEEKNO MUST NOT be used when FREQ is not YEARLY"', result.freq;
  END IF;

  -- Validation 4: BYYEARDAY not valid with DAILY, WEEKLY, or MONTHLY
  IF result.byyearday IS NOT NULL AND
     result.freq IN ('DAILY', 'WEEKLY', 'MONTHLY') THEN
    RAISE EXCEPTION 'Invalid RRULE: BYYEARDAY cannot be used with FREQ=%. BYYEARDAY is only valid with FREQ=YEARLY (and sub-day frequencies). Use FREQ=YEARLY or use BYMONTHDAY instead.  RFC 5545 Section 3.3.10: "BYYEARDAY MUST NOT be specified when FREQ is DAILY, WEEKLY, or MONTHLY"', result.freq;
  END IF;

  -- Validation 5: BYMONTHDAY not valid with WEEKLY frequency
  IF result.bymonthday IS NOT NULL AND result.freq = 'WEEKLY' THEN
    RAISE EXCEPTION 'Invalid RRULE: BYMONTHDAY cannot be used with FREQ=WEEKLY. BYMONTHDAY specifies day-of-month filters which are not applicable to weekly recurrence. Use FREQ=DAILY with BYDAY filter instead. Example: FREQ=DAILY;BYDAY=MO,WE,FR for specific weekdays.  RFC 5545 Section 3.3.10: "BYMONTHDAY MUST NOT be specified when the FREQ rule part is set to WEEKLY"';
  END IF;

  -- Validation 6: BYDAY with ordinals only valid with MONTHLY or YEARLY
  IF result.byday IS NOT NULL AND result.freq NOT IN ('MONTHLY', 'YEARLY') THEN
    FOR i IN 1..array_length(result.byday, 1) LOOP
      EXIT WHEN result.byday[i] IS NULL;
      -- Check if BYDAY has numeric prefix (ordinal like "2MO" or "-1FR")
      IF result.byday[i] ~ '^[+-]?[0-9]+' THEN
        RAISE EXCEPTION 'Invalid RRULE: BYDAY with ordinal (%) can only be used with FREQ=MONTHLY or FREQ=YEARLY. Current FREQ=%. Ordinals (like 2MO for "2nd Monday" or -1FR for "last Friday") are only meaningful within a month or year. Either change FREQ to MONTHLY/YEARLY or remove the ordinal prefix (use MO instead of 2MO).  RFC 5545 Section 3.3.10: "BYDAY MUST NOT be specified with numeric value when FREQ is not MONTHLY/YEARLY"', result.byday[i], result.freq;
      END IF;
    END LOOP;
  END IF;

  -- Validation 7: BYDAY with ordinals cannot be used with YEARLY + BYWEEKNO
  IF result.freq = 'YEARLY' AND result.byweekno IS NOT NULL AND result.byday IS NOT NULL THEN
    FOR i IN 1..array_length(result.byday, 1) LOOP
      EXIT WHEN result.byday[i] IS NULL;
      -- Check if BYDAY has numeric prefix (ordinal like "2MO" or "-1FR")
      IF result.byday[i] ~ '^[+-]?[0-9]+' THEN
        RAISE EXCEPTION 'Invalid RRULE: BYDAY with ordinal (%) cannot be used when FREQ=YEARLY and BYWEEKNO is specified. Ordinals are ambiguous when combined with week numbers. Use BYDAY without ordinals (e.g., MO instead of 2MO) or remove BYWEEKNO. Example valid: FREQ=YEARLY;BYWEEKNO=10;BYDAY=MO.  RFC 5545 Section 3.3.10: "BYDAY MUST NOT be specified with a numeric value with the FREQ rule part set to YEARLY when the BYWEEKNO rule part is specified"', result.byday[i];
      END IF;
    END LOOP;
  END IF;

  -- Validation 7b: BYDAY ordinals cannot be zero
  IF result.byday IS NOT NULL THEN
    FOR i IN 1..array_length(result.byday, 1) LOOP
      EXIT WHEN result.byday[i] IS NULL;
      -- Check if BYDAY has zero ordinal (0MO, +0MO, -0MO, 00MO, etc.)
      IF result.byday[i] ~ '^[+-]?0+(MO|TU|WE|TH|FR|SA|SU)$' THEN
        RAISE EXCEPTION 'Invalid RRULE: BYDAY ordinal cannot be zero (%). Valid ordinals are 1-53 or -1 to -53. Use BYDAY=% instead of BYDAY=%.  RFC 5545 Section 3.3.10: "ordwk = 1*2DIGIT ;1 to 53"',
          result.byday[i],
          substring(result.byday[i] from '(MO|TU|WE|TH|FR|SA|SU)$'),
          result.byday[i];
      END IF;
      -- Enforce ordinal bounds (±53)
      IF result.byday[i] ~ '^[+-]?[0-9]+' THEN
        IF abs((substring(result.byday[i] from '^[+-]?[0-9]+'))::INT) > 53 THEN
          RAISE EXCEPTION 'Invalid RRULE: BYDAY ordinal (%) is out of valid range. Valid ordinals are 1-53 or -1 to -53.  RFC 5545 Section 3.3.10: "ordwk = 1*2DIGIT ;1 to 53"', result.byday[i];
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- Validation 8: BYSETPOS requires at least one other BYxxx parameter
  IF result.bysetpos IS NOT NULL THEN
    IF result.bysecond IS NULL AND
       result.byminute IS NULL AND
       result.byhour IS NULL AND
       result.byday IS NULL AND
       result.bymonthday IS NULL AND
       result.bymonth IS NULL AND
       result.byyearday IS NULL AND
       result.byweekno IS NULL THEN
      RAISE EXCEPTION 'Invalid RRULE: BYSETPOS requires at least one other BYxxx parameter. BYSETPOS selects specific positions from a set of occurrences, but you must specify which set using BYDAY, BYMONTHDAY, BYHOUR, etc. Example: FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1 (last workday of month).  RFC 5545 Section 3.3.10: "BYSETPOS MUST only be used in conjunction with another BYxxx rule part"';
    END IF;
  END IF;

  -- Validation 9-12: Parameter range validations
  -- BYSECOND: 0-60 (60 for leap seconds)
  IF result.bysecond IS NOT NULL THEN
    FOR i IN 1..array_length(result.bysecond, 1) LOOP
      EXIT WHEN result.bysecond[i] IS NULL;
      IF result.bysecond[i] < 0 OR result.bysecond[i] > 60 THEN
        RAISE EXCEPTION 'Invalid RRULE: BYSECOND=% is out of valid range. Valid values are 0-60 (60 for leap seconds).  RFC 5545 Section 3.3.10: "Valid values are 0 to 60"', result.bysecond[i];
      END IF;
      -- PostgreSQL TIMESTAMP does not support leap seconds; normalize 60 -> 59.
      IF result.bysecond[i] = 60 THEN
        result.bysecond[i] := 59;
      END IF;
    END LOOP;
  END IF;

  -- BYMINUTE: 0-59
  IF result.byminute IS NOT NULL THEN
    FOR i IN 1..array_length(result.byminute, 1) LOOP
      EXIT WHEN result.byminute[i] IS NULL;
      IF result.byminute[i] < 0 OR result.byminute[i] > 59 THEN
        RAISE EXCEPTION 'Invalid RRULE: BYMINUTE=% is out of valid range. Valid values are 0-59.  RFC 5545 Section 3.3.10: "Valid values are 0 to 59"', result.byminute[i];
      END IF;
    END LOOP;
  END IF;

  -- BYHOUR: 0-23
  IF result.byhour IS NOT NULL THEN
    FOR i IN 1..array_length(result.byhour, 1) LOOP
      EXIT WHEN result.byhour[i] IS NULL;
      IF result.byhour[i] < 0 OR result.byhour[i] > 23 THEN
        RAISE EXCEPTION 'Invalid RRULE: BYHOUR=% is out of valid range. Valid values are 0-23 (0 = midnight, 23 = 11 PM).  RFC 5545 Section 3.3.10: "Valid values are 0 to 23"', result.byhour[i];
      END IF;
    END LOOP;
  END IF;

  -- BYMONTH: 1-12 (for Gregorian calendar)
  IF result.bymonth IS NOT NULL THEN
    FOR i IN 1..array_length(result.bymonth, 1) LOOP
      EXIT WHEN result.bymonth[i] IS NULL;
      IF result.bymonth[i] < 1 OR result.bymonth[i] > 12 THEN
        RAISE EXCEPTION 'Invalid RRULE: BYMONTH=% is out of valid range. Valid values are 1-12 for Gregorian calendar (1=January, 12=December).  RFC 5545 Section 3.3.10: Valid month numbers are 1-12', result.bymonth[i];
      END IF;
    END LOOP;
  END IF;

  -- BYMONTHDAY: Must not be zero
  IF result.bymonthday IS NOT NULL THEN
    FOR i IN 1..array_length(result.bymonthday, 1) LOOP
      EXIT WHEN result.bymonthday[i] IS NULL;
      IF result.bymonthday[i] = 0 THEN
        RAISE EXCEPTION 'Invalid RRULE: BYMONTHDAY=0 is not valid. Valid values are 1-31 or -31 to -1 (negative values count from month end). Use BYMONTHDAY=1 for first day or BYMONTHDAY=-1 for last day.  RFC 5545 Section 3.3.10: Zero is not a valid BYMONTHDAY value';
      END IF;
      IF result.bymonthday[i] > 31 OR result.bymonthday[i] < -31 THEN
        RAISE EXCEPTION 'Invalid RRULE: BYMONTHDAY=% is out of valid range. Valid values are 1-31 or -31 to -1.  RFC 5545 Section 3.3.10: Valid range is ±1-31', result.bymonthday[i];
      END IF;
    END LOOP;
  END IF;

  -- BYYEARDAY: Must not be zero
  IF result.byyearday IS NOT NULL THEN
    FOR i IN 1..array_length(result.byyearday, 1) LOOP
      EXIT WHEN result.byyearday[i] IS NULL;
      IF result.byyearday[i] = 0 THEN
        RAISE EXCEPTION 'Invalid RRULE: BYYEARDAY=0 is not valid. Valid values are 1-366 or -366 to -1 (negative values count from year end). Use BYYEARDAY=1 for January 1st or BYYEARDAY=-1 for December 31st.  RFC 5545 Section 3.3.10: Zero is not a valid BYYEARDAY value';
      END IF;
      IF result.byyearday[i] > 366 OR result.byyearday[i] < -366 THEN
        RAISE EXCEPTION 'Invalid RRULE: BYYEARDAY=% is out of valid range. Valid values are 1-366 or -366 to -1 (366 for leap years).  RFC 5545 Section 3.3.10: Valid range is ±1-366', result.byyearday[i];
      END IF;
    END LOOP;
  END IF;

  -- BYWEEKNO: Valid range ±1-53
  IF result.byweekno IS NOT NULL THEN
    FOR i IN 1..array_length(result.byweekno, 1) LOOP
      EXIT WHEN result.byweekno[i] IS NULL;
      IF result.byweekno[i] = 0 THEN
        RAISE EXCEPTION 'Invalid RRULE: BYWEEKNO=0 is not valid. Valid values are 1-53 or -53 to -1 (ISO 8601 week numbers).  RFC 5545 Section 3.3.10: Zero is not a valid BYWEEKNO value';
      END IF;
      IF result.byweekno[i] > 53 OR result.byweekno[i] < -53 THEN
        RAISE EXCEPTION 'Invalid RRULE: BYWEEKNO=% is out of valid range. Valid values are 1-53 or -53 to -1 (ISO 8601 week numbers).  RFC 5545 Section 3.3.10: Valid range is ±1-53', result.byweekno[i];
      END IF;
    END LOOP;
  END IF;

  -- BYSETPOS: Valid range ±1-366
  IF result.bysetpos IS NOT NULL THEN
    FOR i IN 1..array_length(result.bysetpos, 1) LOOP
      EXIT WHEN result.bysetpos[i] IS NULL;
      IF result.bysetpos[i] = 0 THEN
        RAISE EXCEPTION 'Invalid RRULE: BYSETPOS=0 is not valid. Valid values are 1-366 or -366 to -1 for position selection. Use BYSETPOS=1 for first occurrence or BYSETPOS=-1 for last occurrence.  RFC 5545 Section 3.3.10: Zero is not a valid BYSETPOS value';
      END IF;
      IF result.bysetpos[i] > 366 OR result.bysetpos[i] < -366 THEN
        RAISE EXCEPTION 'Invalid RRULE: BYSETPOS=% is out of valid range. Valid values are 1-366 or -366 to -1.  RFC 5545 Section 3.3.10: Valid range is ±1-366', result.bysetpos[i];
      END IF;
    END LOOP;
  END IF;

  -- Validation: BYHOUR/BYMINUTE/BYSECOND not supported with WEEKLY/MONTHLY/YEARLY
  -- RFC 5545 defines these as "Expand" operations, but this implementation does not yet
  -- support time-level expansion for these frequencies. Reject explicitly rather than
  -- silently ignoring. See SPEC_COMPLIANCE.md for workarounds.
  IF result.freq IN ('WEEKLY', 'MONTHLY', 'YEARLY') THEN
    IF result.byhour IS NOT NULL THEN
      RAISE EXCEPTION 'Invalid RRULE: BYHOUR is not supported with FREQ=%. Use FREQ=DAILY;BYDAY=... with BYHOUR instead, or use sub-day frequencies (FREQ=HOURLY;BYDAY=...).  Note: RFC 5545 defines this as an "Expand" operation but this implementation does not yet support it.', result.freq;
    END IF;
    IF result.byminute IS NOT NULL THEN
      RAISE EXCEPTION 'Invalid RRULE: BYMINUTE is not supported with FREQ=%. Use FREQ=DAILY with BYMINUTE instead, or use sub-day frequencies.  Note: RFC 5545 defines this as an "Expand" operation but this implementation does not yet support it.', result.freq;
    END IF;
    IF result.bysecond IS NOT NULL THEN
      RAISE EXCEPTION 'Invalid RRULE: BYSECOND is not supported with FREQ=%. Use FREQ=DAILY with BYSECOND instead, or use sub-day frequencies.  Note: RFC 5545 defines this as an "Expand" operation but this implementation does not yet support it.', result.freq;
    END IF;
  END IF;

  -- Validation: BYSETPOS not supported with HOURLY/MINUTELY/SECONDLY
  -- Sub-day frequencies generate single occurrences per interval; BYSETPOS is meaningless.
  IF result.bysetpos IS NOT NULL AND result.freq IN ('HOURLY', 'MINUTELY', 'SECONDLY') THEN
    RAISE EXCEPTION 'Invalid RRULE: BYSETPOS is not supported with FREQ=%. Sub-day frequencies generate single occurrences per interval — use INTERVAL instead. Example: FREQ=HOURLY;INTERVAL=3', result.freq;
  END IF;

  RETURN result;
END;
$$ LANGUAGE plpgsql STABLE STRICT;


------------------------------------------------------------------------------------------------------
-- VOLATILITY RATIONALE (applies to all internal and public functions below)
--
-- Functions are classified STABLE or VOLATILE per PostgreSQL rules:
--   STABLE:   Pure computation, no cursors, no SET — safe to optimize within a statement.
--   VOLATILE: Uses cursors (BYSETPOS filter), SET timezone, or set_config() — must re-evaluate per call.
--
-- SET timezone = 'UTC' on function definitions pins timezone during execution and restores
-- the caller's timezone on exit (PostgreSQL §38.7). No session leakage.
-- set_config('TimeZone', ..., true) inside TIMESTAMPTZ API functions is sandboxed by the
-- function-level SET clause (PostgreSQL §CREATE FUNCTION, SET clause).
--
-- See DECISIONS.md #1 for full rationale.
------------------------------------------------------------------------------------------------------


-- Return a SETOF dates within the month of a particular date which match a string of BYDAY rule specifications
CREATE OR REPLACE FUNCTION rrule_month_byday_set(
  in_time TIMESTAMP WITH TIME ZONE,
  byday TEXT[],
  max_results INT DEFAULT NULL  -- NULL = unlimited, otherwise stop after N results
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  dayrule TEXT;
  dow INT;
  index INT;
  first_dow INT;
  each_day TIMESTAMP WITH TIME ZONE;
  this_month INT;
  results TIMESTAMP WITH TIME ZONE[];
  result_count INT := 0;
BEGIN
  -- Maintain STRICT semantics for required parameters
  IF in_time IS NULL THEN
    RETURN;
  END IF;

  IF byday IS NULL THEN
    -- We still return the single date as a SET
    RETURN NEXT in_time;
    RETURN;
  END IF;

  -- Iterate through each BYDAY rule (e.g., MO, 2TU, -1FR)
  FOREACH dayrule IN ARRAY byday LOOP
    dow := rrule.weekday_to_number(substring(dayrule from '..$'));
    each_day := date_trunc( 'month', in_time ) + (in_time::time)::interval;
    this_month := date_part( 'month', in_time );
    first_dow := date_part( 'dow', each_day );

    -- Coerce each_day to be the first 'dow' of the month
    each_day := each_day - make_interval(days => first_dow)
                        + make_interval(days => dow)
                        + CASE WHEN dow < first_dow THEN '1 week'::interval ELSE '0s'::interval END;

    IF length(dayrule) > 2 THEN
      index := (substring(dayrule from '^[+-]?[0-9]+'))::int;

      IF index > 0 THEN
        -- The simplest case, such as 2MO for the second monday
        each_day := each_day + make_interval(weeks => index - 1);
      ELSE
        each_day := each_day + '5 weeks'::interval;
        WHILE date_part('month', each_day) != this_month LOOP
          each_day := each_day - '1 week'::interval;
        END LOOP;
        -- Note that since index is negative, (-2 + 1) == -1, for example
        index := index + 1;
        IF index < 0 THEN
          each_day := each_day + make_interval(weeks => index);
        END IF;
      END IF;

      -- Sometimes (e.g. 5TU or -5WE) there might be no such date in some months
      IF date_part('month', each_day) = this_month THEN
        results[date_part('day',each_day)] := each_day;
      END IF;

    ELSE
      -- Return all such days that are within the given month
      WHILE date_part('month', each_day) = this_month LOOP
        results[date_part('day',each_day)] := each_day;
        each_day := each_day + '1 week'::interval;
      END LOOP;
    END IF;
  END LOOP;

  FOR i IN 1..31 LOOP
    IF results[i] IS NOT NULL THEN
      RETURN NEXT results[i];
      result_count := result_count + 1;

      -- Early exit: stop once we've generated enough results
      EXIT WHEN max_results IS NOT NULL AND result_count >= max_results;
    END IF;
  END LOOP;

  RETURN;

END;
$$ LANGUAGE plpgsql STABLE;  -- No STRICT (was never STRICT)


------------------------------------------------------------------------------------------------------
-- Return a SETOF dates within the year of a particular date which match a string of BYDAY rule specifications
-- Supports YEARLY BYDAY ordinals (e.g., 2MO = second Monday of year, -1FR = last Friday of year)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rrule_year_byday_set(
  in_time TIMESTAMP WITH TIME ZONE,
  byday TEXT[],
  max_results INT DEFAULT NULL  -- NULL = unlimited, otherwise stop after N results
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  dayrule TEXT;
  dow INT;
  index INT;
  first_dow INT;
  each_day TIMESTAMP WITH TIME ZONE;
  year_start TIMESTAMP WITH TIME ZONE;
  year_end TIMESTAMP WITH TIME ZONE;
  results TIMESTAMP WITH TIME ZONE[];
  result_count INT := 0;
BEGIN
  -- Maintain STRICT semantics for required parameters
  IF in_time IS NULL THEN
    RETURN;
  END IF;

  IF byday IS NULL THEN
    RETURN NEXT in_time;
    RETURN;
  END IF;

  year_start := date_trunc('year', in_time) + (in_time::time)::interval;
  year_end := year_start + INTERVAL '1 year' - INTERVAL '1 day';

  -- Iterate through each BYDAY rule (e.g., MO, 2TU, -1FR)
  FOREACH dayrule IN ARRAY byday LOOP
    dow := rrule.weekday_to_number(substring(dayrule from '..$'));
    each_day := year_start;
    first_dow := date_part('dow', each_day);

    -- Coerce each_day to be the first 'dow' of the year
    each_day := each_day - make_interval(days => first_dow)
                        + make_interval(days => dow)
                        + CASE WHEN dow < first_dow THEN '1 week'::interval ELSE '0s'::interval END;

    IF length(dayrule) > 2 THEN
      index := (substring(dayrule from '^[+-]?[0-9]+'))::int;

      IF index > 0 THEN
        -- Nth weekday of year
        each_day := each_day + make_interval(weeks => index - 1);
      ELSE
        -- Negative ordinals: count from end of year
        -- Find last occurrence of this weekday
        WHILE (each_day + '1 week'::interval) <= year_end LOOP
          each_day := each_day + '1 week'::interval;
        END LOOP;
        -- Note: index is negative, so (-2 + 1) == -1
        index := index + 1;
        IF index < 0 THEN
          each_day := each_day + make_interval(weeks => index);
        END IF;
      END IF;

      IF each_day >= year_start AND each_day <= year_end THEN
        results[date_part('doy', each_day)] := each_day;
      END IF;
    ELSE
      -- Return all matching weekdays in the year
      WHILE each_day <= year_end LOOP
        results[date_part('doy', each_day)] := each_day;
        each_day := each_day + '1 week'::interval;
      END LOOP;
    END IF;
  END LOOP;

  FOR i IN 1..366 LOOP
    IF results[i] IS NOT NULL THEN
      RETURN NEXT results[i];
      result_count := result_count + 1;
      EXIT WHEN max_results IS NOT NULL AND result_count >= max_results;
    END IF;
  END LOOP;

  RETURN;
END;
$$ LANGUAGE plpgsql STABLE;  -- No STRICT (was never STRICT)


------------------------------------------------------------------------------------------------------
-- RFC 7529 SKIP: Generate dates for BYMONTHDAY with SKIP support
-- SKIP=OMIT (default): Skip invalid dates (e.g., Feb 31, Apr 31)
-- SKIP=BACKWARD: Use last valid day of month (e.g., Feb 31 → Feb 28/29)
-- SKIP=FORWARD: Use first day of next month (e.g., Feb 31 → Mar 1)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rrule_month_bymonthday_set(
  in_time TIMESTAMP WITH TIME ZONE,
  bymonthday INT[],
  skip_mode TEXT,  -- 'OMIT', 'BACKWARD', 'FORWARD'
  max_results INT DEFAULT NULL  -- NULL = unlimited, otherwise stop after N results
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  month_start TIMESTAMP WITH TIME ZONE;
  daysinmonth INT;
  requested_day INT;
  adjusted_date TIMESTAMP WITH TIME ZONE;
  time_component TIME;
  seen_dates TIMESTAMP WITH TIME ZONE[];  -- Track to avoid duplicates
  result_count INT := 0;
BEGIN
  -- Maintain STRICT semantics for required parameters
  IF in_time IS NULL THEN
    RETURN;
  END IF;

  month_start := DATE_TRUNC('month', in_time);
  time_component := in_time::TIME;

  -- Calculate days in this month
  daysinmonth := EXTRACT(DAY FROM (
    month_start + INTERVAL '1 month' - INTERVAL '1 day'
  ))::INT;

  -- Initialize seen_dates array
  seen_dates := ARRAY[]::TIMESTAMP WITH TIME ZONE[];

  -- Iterate through each day in BYMONTHDAY array (e.g., 1, 15, -1)
  FOREACH requested_day IN ARRAY bymonthday LOOP
    -- Handle negative indices (count from end of month)
    -- Negative indices are always valid (RFC 5545), no SKIP needed
    IF requested_day < 0 THEN
      -- Ensure it's within valid range
      CONTINUE WHEN requested_day < (-1 * daysinmonth);
      adjusted_date := month_start +
        ((daysinmonth + requested_day)::TEXT || ' days')::INTERVAL +
        time_component::INTERVAL;

      -- Check for duplicates before returning
      IF NOT (adjusted_date = ANY(seen_dates)) THEN
        seen_dates := array_append(seen_dates, adjusted_date);
        RETURN NEXT adjusted_date;
        result_count := result_count + 1;
        EXIT WHEN max_results IS NOT NULL AND result_count >= max_results;
      END IF;
      CONTINUE;
    END IF;

    -- Positive indices: Apply RFC 7529 SKIP logic if day doesn't exist
    IF requested_day <= daysinmonth THEN
      -- Day exists in this month, use it
      adjusted_date := month_start +
        ((requested_day - 1)::TEXT || ' days')::INTERVAL +
        time_component::INTERVAL;

      -- Check for duplicates before returning
      IF NOT (adjusted_date = ANY(seen_dates)) THEN
        seen_dates := array_append(seen_dates, adjusted_date);
        RETURN NEXT adjusted_date;
        result_count := result_count + 1;
        EXIT WHEN max_results IS NOT NULL AND result_count >= max_results;
      END IF;
    ELSE
      -- Day doesn't exist (e.g., Feb 31, Apr 31)
      -- Apply RFC 7529 SKIP logic
      CASE skip_mode
        WHEN 'OMIT' THEN
          -- Skip this occurrence (default RFC 7529 behavior)
          CONTINUE;

        WHEN 'BACKWARD' THEN
          -- Use last day of month
          adjusted_date := month_start +
            ((daysinmonth - 1)::TEXT || ' days')::INTERVAL +
            time_component::INTERVAL;

          -- Check for duplicates before returning
          IF NOT (adjusted_date = ANY(seen_dates)) THEN
            seen_dates := array_append(seen_dates, adjusted_date);
            RETURN NEXT adjusted_date;
            result_count := result_count + 1;
            EXIT WHEN max_results IS NOT NULL AND result_count >= max_results;
          END IF;

        WHEN 'FORWARD' THEN
          -- Use first day of next month
          adjusted_date := month_start +
            INTERVAL '1 month' +
            time_component::INTERVAL;

          -- Check for duplicates before returning
          IF NOT (adjusted_date = ANY(seen_dates)) THEN
            seen_dates := array_append(seen_dates, adjusted_date);
            RETURN NEXT adjusted_date;
            result_count := result_count + 1;
            EXIT WHEN max_results IS NOT NULL AND result_count >= max_results;
          END IF;

        ELSE
          -- Unknown SKIP mode, default to OMIT
          CONTINUE;
      END CASE;
    END IF;
  END LOOP;

  RETURN;
END;
$$ LANGUAGE plpgsql STABLE;  -- STRICT removed to allow NULL max_results


-- Return a SETOF dates within the week of a particular date which match a single BYDAY rule specification
-- Now supports WKST (week start day) parameter
CREATE OR REPLACE FUNCTION rrule_week_byday_set(
  in_time TIMESTAMP WITH TIME ZONE,
  byday TEXT[],
  wkst TEXT,
  max_results INT DEFAULT NULL  -- NULL = unlimited, otherwise stop after N results
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  dayrule TEXT;
  dow INT;
  wkst_dow INT;
  day_offset INT;
  our_day TIMESTAMP WITH TIME ZONE;
  i INT;
  result_count INT := 0;
  seen_offsets INT[] := ARRAY[]::INT[];  -- Track emitted day offsets to prevent duplicates
BEGIN
  -- Maintain STRICT semantics for required parameters
  IF in_time IS NULL THEN
    RETURN;
  END IF;

  IF byday IS NULL THEN
    -- We still return the single date as a SET
    RETURN NEXT in_time;
    RETURN;
  END IF;

  -- Get the WKST day number (0=SU, 1=MO, etc.)
  wkst_dow := rrule.weekday_to_number(wkst);

  -- Use WKST-aware week start instead of hardcoded Monday
  our_day := rrule.get_week_start(in_time, wkst) + (in_time::time)::interval;

  i := 1;
  dayrule := byday[i];
  WHILE dayrule IS NOT NULL LOOP
    dow := rrule.weekday_to_number(dayrule);
    -- Calculate day_offset from week start (WKST day)
    -- Example: if WKST=SU (0) and we want MO (1), day_offset = (1-0+7)%7 = 1
    -- Example: if WKST=MO (1) and we want SU (0), day_offset = (0-1+7)%7 = 6
    day_offset := (dow - wkst_dow + 7) % 7;
    -- Guard: skip if this day_offset was already emitted (e.g. BYDAY=MO,MO)
    IF NOT (day_offset = ANY(seen_offsets)) THEN
      seen_offsets := array_append(seen_offsets, day_offset);
      RETURN NEXT our_day + make_interval(days => day_offset);
      result_count := result_count + 1;

      -- Early exit: stop once we've generated enough results
      EXIT WHEN max_results IS NOT NULL AND result_count >= max_results;
    END IF;

    i := i + 1;
    dayrule := byday[i];
  END LOOP;

  RETURN;

END;
$$ LANGUAGE plpgsql STABLE;  -- No STRICT (was never STRICT)


------------------------------------------------------------------------------------------------------
-- WKST (Week Start) Support Functions
--
-- These functions implement RFC 5545 WKST parameter support for custom week start days.
-- Default is Monday (ISO 8601), but US convention uses Sunday, and RFC allows any day.
------------------------------------------------------------------------------------------------------

-- Convert weekday abbreviation to number (0=SU, 1=MO, 2=TU, 3=WE, 4=TH, 5=FR, 6=SA)
-- Matches PostgreSQL's date_part('dow', ...) convention
CREATE OR REPLACE FUNCTION weekday_to_number(wkst TEXT) RETURNS INT AS $$
DECLARE
    result INT;
BEGIN
    result := CASE COALESCE(wkst, 'MO')
        WHEN 'SU' THEN 0
        WHEN 'MO' THEN 1
        WHEN 'TU' THEN 2
        WHEN 'WE' THEN 3
        WHEN 'TH' THEN 4
        WHEN 'FR' THEN 5
        WHEN 'SA' THEN 6
    END;
    IF result IS NULL THEN
        RAISE EXCEPTION 'Invalid weekday code: "%". Valid values are: SU, MO, TU, WE, TH, FR, SA', wkst;
    END IF;
    RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Get the start of the week containing the given date, respecting WKST
-- Example: get_week_start('2025-01-15', 'SU') returns '2025-01-12' (Sunday)
--          get_week_start('2025-01-15', 'MO') returns '2025-01-13' (Monday)
CREATE OR REPLACE FUNCTION get_week_start(d TIMESTAMP WITH TIME ZONE, wkst TEXT)
RETURNS TIMESTAMP WITH TIME ZONE AS $$
DECLARE
    wkst_num INT;
    dow INT;
    days_back INT;
BEGIN
    wkst_num := rrule.weekday_to_number(wkst);
    dow := date_part('dow', d);

    -- Calculate how many days back to go to reach WKST
    -- Example: If today is Wednesday (3) and WKST is Sunday (0): (3 - 0) = 3 days back
    -- Example: If today is Monday (1) and WKST is Wednesday (3): (1 - 3 + 7) % 7 = 5 days back
    days_back := (dow - wkst_num + 7) % 7;

    -- Return start of day, N days back
    RETURN date_trunc('day', d) - (days_back::TEXT || ' days')::INTERVAL;
END;
$$ LANGUAGE plpgsql STABLE;

-- Get week number (1-53) for a date, respecting WKST
-- ISO 8601 week numbering (RFC 5545), with WKST defining the week start day.
-- Week 1 is the week that contains January 4th (equivalently, the first week with >= 4 days in the year).
CREATE OR REPLACE FUNCTION get_week_info(
  d TIMESTAMP WITH TIME ZONE,
  wkst TEXT
) RETURNS TABLE(week_year INT, week_num INT) AS $$
DECLARE
  year_start TIMESTAMP WITH TIME ZONE;
  week_start TIMESTAMP WITH TIME ZONE;
  week1_start TIMESTAMP WITH TIME ZONE;
  next_week1_start TIMESTAMP WITH TIME ZONE;
  prev_year_start TIMESTAMP WITH TIME ZONE;
  prev_week1_start TIMESTAMP WITH TIME ZONE;
BEGIN
  year_start := date_trunc('year', d);
  week_start := rrule.get_week_start(d, wkst);

  -- Week 1 start is the week containing Jan 4
  week1_start := rrule.get_week_start(year_start + INTERVAL '3 days', wkst);
  next_week1_start := rrule.get_week_start((year_start + INTERVAL '1 year') + INTERVAL '3 days', wkst);

  IF week_start < week1_start THEN
    prev_year_start := year_start - INTERVAL '1 year';
    prev_week1_start := rrule.get_week_start(prev_year_start + INTERVAL '3 days', wkst);
    week_year := date_part('year', prev_year_start)::INT;
    week_num := ((week_start::DATE - prev_week1_start::DATE) / 7) + 1;
  ELSIF week_start >= next_week1_start THEN
    week_year := date_part('year', year_start + INTERVAL '1 year')::INT;
    week_num := ((week_start::DATE - next_week1_start::DATE) / 7) + 1;
  ELSE
    week_year := date_part('year', year_start)::INT;
    week_num := ((week_start::DATE - week1_start::DATE) / 7) + 1;
  END IF;

  RETURN NEXT;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION weeks_in_year(
  year_start TIMESTAMP WITH TIME ZONE,
  wkst TEXT
) RETURNS INT AS $$
DECLARE
  week1_start TIMESTAMP WITH TIME ZONE;
  next_week1_start TIMESTAMP WITH TIME ZONE;
BEGIN
  week1_start := rrule.get_week_start(year_start + INTERVAL '3 days', wkst);
  next_week1_start := rrule.get_week_start((year_start + INTERVAL '1 year') + INTERVAL '3 days', wkst);
  RETURN ((next_week1_start::DATE - week1_start::DATE) / 7);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION get_week_number(d TIMESTAMP WITH TIME ZONE, wkst TEXT)
RETURNS INT AS $$
DECLARE
  info RECORD;
BEGIN
  SELECT * INTO info FROM rrule.get_week_info(d, wkst);
  RETURN info.week_num;
END;
$$ LANGUAGE plpgsql STABLE;


------------------------------------------------------------------------------------------------------
-- Timezone Validation Helper
------------------------------------------------------------------------------------------------------
--
-- Validates that a timezone string is a valid IANA timezone identifier.
-- Raises an exception if the timezone is invalid.
-- Does nothing if timezone is NULL (allowing optional timezone parameters).
--
-- This function centralizes timezone validation logic that was previously duplicated
-- across multiple public API functions.
--
-- Parameters:
--   tz - Timezone string (e.g., 'America/New_York', 'Europe/London', 'UTC')
--
-- Returns: VOID (raises exception on invalid timezone)
--
-- Example:
--   PERFORM rrule.validate_timezone('America/New_York');  -- Success
--   PERFORM rrule.validate_timezone('Invalid/Zone');      -- Raises exception
--   PERFORM rrule.validate_timezone(NULL);                -- Success (NULL is allowed)
--
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION validate_timezone(tz TEXT)
RETURNS VOID AS $$
BEGIN
  -- NULL is allowed (indicates optional timezone parameter)
  IF tz IS NULL THEN
    RETURN;
  END IF;

  -- Validate timezone by attempting to use it; this avoids scanning pg_timezone_names
  BEGIN
    PERFORM '2000-01-01'::TIMESTAMP AT TIME ZONE tz;
  EXCEPTION
    WHEN invalid_parameter_value THEN
      RAISE EXCEPTION 'Invalid timezone: "%". Must be a valid IANA timezone identifier (e.g., America/New_York, Europe/London, Asia/Tokyo, UTC). Use: SELECT name FROM pg_timezone_names ORDER BY name; to see all valid timezones.', tz;
  END;
END;
$$ LANGUAGE plpgsql STABLE;


------------------------------------------------------------------------------------------------------
-- Test the weekday of this date against the array of weekdays from the BYDAY rule (FREQ=WEEKLY or less)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION test_byday_rule(
  testme TIMESTAMP WITH TIME ZONE,
  byday TEXT[]
) RETURNS BOOLEAN AS $$
DECLARE
  test_dow INT;
  dayrule TEXT;
BEGIN
  -- Note that this doesn't work for MONTHLY/YEARLY BYDAY clauses which might have numbers prepended
  -- so don't call it that way...
  IF byday IS NOT NULL THEN
    test_dow := date_part('dow', testme);
    FOREACH dayrule IN ARRAY byday LOOP
      IF rrule.weekday_to_number(substring(dayrule from '..$')) = test_dow THEN
        RETURN TRUE;
      END IF;
    END LOOP;
    RETURN FALSE;
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql STABLE;


------------------------------------------------------------------------------------------------------
-- Test the month of this date against the array of months from the rule
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION test_bymonth_rule(
  testme TIMESTAMP WITH TIME ZONE,
  bymonth INT[]
) RETURNS BOOLEAN AS $$
BEGIN
  IF bymonth IS NOT NULL THEN
    RETURN ( date_part( 'month', testme) = ANY (bymonth) );
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql STABLE;


------------------------------------------------------------------------------------------------------
-- Test the day in month of this date against the array of monthdays from the rule
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION test_bymonthday_rule(
  testme TIMESTAMP WITH TIME ZONE,
  bymonthday INT[]
) RETURNS BOOLEAN AS $$
DECLARE
  dom INT;
  days_in_month INT;
  md INT;
BEGIN
  IF bymonthday IS NOT NULL THEN
    dom := date_part('day', testme);
    days_in_month := date_part('day',
      (date_trunc('month', testme) + INTERVAL '1 month' - INTERVAL '1 day'))::INT;
    FOREACH md IN ARRAY bymonthday LOOP
      IF md > 0 AND md = dom THEN RETURN TRUE; END IF;
      IF md < 0 AND (days_in_month + md + 1) = dom THEN RETURN TRUE; END IF;
    END LOOP;
    RETURN FALSE;
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql STABLE;


------------------------------------------------------------------------------------------------------
-- Test the day in year of this date against the array of yeardays from the rule
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION test_byyearday_rule(
  testme TIMESTAMP WITH TIME ZONE,
  byyearday INT[]
) RETURNS BOOLEAN AS $$
DECLARE
  doy INT;
  days_in_year INT;
  yd INT;
BEGIN
  IF byyearday IS NOT NULL THEN
    doy := date_part('doy', testme);
    days_in_year := date_part('doy',
      (date_trunc('year', testme) + INTERVAL '1 year' - INTERVAL '1 day'))::INT;
    FOREACH yd IN ARRAY byyearday LOOP
      IF yd > 0 AND yd = doy THEN RETURN TRUE; END IF;
      IF yd < 0 AND (days_in_year + yd + 1) = doy THEN RETURN TRUE; END IF;
    END LOOP;
    RETURN FALSE;
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql STABLE;


------------------------------------------------------------------------------------------------------
-- Match BYWEEKNO values (supports negative indices)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION byweekno_matches(
  week_num INT,
  weeks_in_year INT,
  byweekno INT[]
) RETURNS BOOLEAN AS $$
DECLARE
  wn INT;
  normalized INT;
BEGIN
  IF byweekno IS NULL THEN
    RETURN TRUE;
  END IF;
  FOREACH wn IN ARRAY byweekno LOOP
    normalized := wn;
    IF wn < 0 THEN
      normalized := weeks_in_year + wn + 1;
    END IF;
    IF normalized = week_num THEN
      RETURN TRUE;
    END IF;
  END LOOP;
  RETURN FALSE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION byweekno_matches_for_year(
  d TIMESTAMP WITH TIME ZONE,
  year_start TIMESTAMP WITH TIME ZONE,
  wkst TEXT,
  byweekno INT[]
) RETURNS BOOLEAN AS $$
DECLARE
  weekyear INT;
  weeknum INT;
  weeks_in_year INT;
BEGIN
  IF byweekno IS NULL THEN
    RETURN TRUE;
  END IF;
  SELECT week_year, week_num INTO weekyear, weeknum
  FROM rrule.get_week_info(d, wkst);
  IF weekyear != date_part('year', year_start) THEN
    RETURN FALSE;
  END IF;
  weeks_in_year := rrule.weeks_in_year(year_start, wkst);
  RETURN rrule.byweekno_matches(weeknum, weeks_in_year, byweekno);
END;
$$ LANGUAGE plpgsql STABLE;


------------------------------------------------------------------------------------------------------
-- Calculate safe iteration limit to prevent infinite loops with sparse BYxxx filters
--
-- SECURITY-CRITICAL: These multipliers prevent denial-of-service attacks when RRULEs
-- contain sparse filters like BYDAY=MO (matches 1/7 days) combined with BYSETPOS.
-- Without proper limits, the database could iterate millions of times searching for
-- occurrences that rarely match.
--
-- MULTIPLIER RATIONALE (based on mathematical worst-case analysis):
--
--   DAILY × 20:   FREQ=DAILY;BYDAY=MO;BYSETPOS=-1 requires ~4 weeks (28 days)
--                 to find 1 occurrence (last Monday of month). With monthly-sparse
--                 filters, we need 20x headroom to guarantee finding matches.
--
--   WEEKLY × 15:  FREQ=WEEKLY;BYMONTH=12 requires ~13 weeks to find 1 occurrence
--                 (only weeks in December match). Monthly filters on weekly frequency
--                 create extreme sparsity.
--
--   HOURLY × 2:   FREQ=HOURLY;BYHOUR=9,17 matches 2/24 hours, requiring ~12 hours
--                 per match. Factor of 2x provides adequate headroom.
--
--   MINUTELY cap: Hard limit at 1440 (1 day) regardless of requested_max.
--                 DoS protection: prevents generating millions of minute-level occurrences.
--
--   SECONDLY cap: Hard limit at 3600 (1 hour) regardless of requested_max.
--                 DoS protection: prevents generating tens of millions of second-level occurrences.
--
-- SECURITY: DO NOT increase these multipliers without thorough security review and testing.
-- Increasing limits could enable resource exhaustion attacks in multi-tenant environments.
--
-- PRECEDENCE: Iteration limits are derived from the effective output cap
-- (min of API max and RRULE COUNT when present). COUNT still caps emitted
-- occurrences separately during generation.
--
-- Parameters:
--   frequency      - FREQ value from RRULE (DAILY, WEEKLY, MONTHLY, YEARLY, HOURLY, MINUTELY, SECONDLY)
--   rrule_count    - COUNT parameter from RRULE, or NULL if not specified (used as fallback)
--   requested_max  - Maximum occurrences requested by API caller
--   interval_val   - INTERVAL parameter from RRULE (used to scale sub-day DoS caps; DEFAULT 1)
--   has_sparse_calendar_filter - TRUE if BYMONTH or BYYEARDAY is present (requires larger multipliers for sub-day frequencies)
--
-- Returns:
--   Safe iteration limit that balances:
--     1. Finding enough matches even with sparse filters (multipliers)
--     2. Preventing resource exhaustion (DoS caps)
--
-- Examples:
--   calculate_safe_iteration_limit('DAILY', NULL, 100)    → 4000  (100 × 40)
--   calculate_safe_iteration_limit('WEEKLY', NULL, 50)    → 750   (50 × 15)
--   calculate_safe_iteration_limit('MINUTELY', NULL, 5000) → 1440  (DoS cap, INTERVAL=1)
--   calculate_safe_iteration_limit('SECONDLY', NULL, 5000, 60) -> 60  (3600/60, INTERVAL-aware)
--   calculate_safe_iteration_limit('DAILY', 75, 75)       → 3000  (COUNT caps output_limit; multipliers still apply)
--   calculate_safe_iteration_limit('HOURLY', 3, 3, 1, TRUE) → 30000 (sparse calendar filter: BYMONTH can span years)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calculate_safe_iteration_limit(
  frequency TEXT,
  rrule_count INT,
  requested_max INT,
  interval_val INT DEFAULT 1,
  has_sparse_calendar_filter BOOLEAN DEFAULT FALSE
) RETURNS INT AS $$
DECLARE
  effective_max INT;
BEGIN
  -- Use requested_max when provided; fall back to COUNT only when no API limit exists.
  effective_max := COALESCE(requested_max, rrule_count);
  IF effective_max IS NULL THEN
    RETURN NULL;
  END IF;

  -- Apply frequency-specific safety multipliers for sparse filter protection
  -- LEAST(..., 2147483647) guards against INT4 overflow when effective_max is large
  RETURN CASE frequency
    WHEN 'DAILY'    THEN LEAST(effective_max::BIGINT * 40, 2147483647)::INT   -- Sparse: BYMONTHDAY filters (1/31 days match)
    WHEN 'WEEKLY'   THEN LEAST(effective_max::BIGINT * 15, 2147483647)::INT   -- Sparse: BYMONTH filters (~4/52 weeks match = 13x needed)
    WHEN 'HOURLY'   THEN
      CASE WHEN has_sparse_calendar_filter
        THEN LEAST(effective_max::BIGINT * 10000, 2147483647)::INT  -- Sparse: BYMONTH/BYYEARDAY can span years (8760 hours/year)
        ELSE LEAST(effective_max::BIGINT * 2, 2147483647)::INT      -- Moderate: time-of-day filters (BYHOUR, etc.)
      END
    WHEN 'MINUTELY' THEN LEAST(effective_max, FLOOR(1440.0 / GREATEST(interval_val, 1))::INT)  -- DoS protection: max 1 day of real time
    WHEN 'SECONDLY' THEN LEAST(effective_max, FLOOR(3600.0 / GREATEST(interval_val, 1))::INT)  -- DoS protection: max 1 hour of real time
    WHEN 'MONTHLY'  THEN GREATEST(LEAST(effective_max::BIGINT * 20, 2147483647)::INT, 1200)  -- Sparse: BYMONTH+BYDAY can be very sparse; min 100 years
    WHEN 'YEARLY'   THEN LEAST(effective_max::BIGINT * 10, 2147483647)::INT   -- Sparse: BYYEARDAY/BYWEEKNO/BYDAY filters
    ELSE effective_max                         -- Fallback: no multiplier
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- PostgreSQL metadata: Documents this function's purpose for introspection
COMMENT ON FUNCTION calculate_safe_iteration_limit IS
'Security-critical function: Calculates safe iteration limits for RRULE generation accounting for sparse BYxxx filters and DoS protection. See function header for detailed security rationale and multiplier derivation.';


------------------------------------------------------------------------------------------------------
-- SKIP DRIFT PREVENTION HELPERS
--
-- These helpers encapsulate the MONTHLY/YEARLY SKIP+drift logic that was previously duplicated
-- across 4 generator functions (Generator 1: rrule_event_instances_range in rrule.sql,
-- Generator 2: rrule_event_instances_range_tz in rrule.sql, Generators 3+4 in rrule_subday.sql).
--
-- The advance helpers (_advance_monthly, _advance_yearly) handle one iteration of the SKIP inner
-- loop, returning a composite type with all relevant state. The caller handles RETURN NEXT since
-- helpers cannot emit SRF rows.
--
-- DESIGN DECISIONS:
-- - TIMESTAMPTZ parameters: Both generator variants can call them; TIMESTAMP variants cast at boundaries
-- - Named composite TYPE: Zero-overhead field access via := and dot notation (no SELECT INTO per call)
-- - RETURN NEXT stays in caller: Helpers return forward_ts for the caller to emit
-- - Separate monthly/yearly helpers: Different set functions and drift formulas; no branching overhead
-- - DAILY/WEEKLY left inline: No SKIP/drift logic, no duplication problem
------------------------------------------------------------------------------------------------------


------------------------------------------------------------------------------------------------------
-- _restore_monthly_base: Restore dtstart day-of-month after period advancement
--
-- PostgreSQL coerces invalid dates (e.g., Jan 31 + 1 month = Feb 28). This function restores
-- the original dtstart day-of-month (clamped to month's max days) to prevent cumulative drift.
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _restore_monthly_base(
    p_current_base TIMESTAMPTZ,
    p_dtstart_day INT,
    p_base_time INTERVAL
) RETURNS TIMESTAMPTZ AS $$
DECLARE
    month_end_day INT;
BEGIN
    -- Get the last day of the current month
    month_end_day := date_part('day', (date_trunc('month', p_current_base) + INTERVAL '1 month - 1 day'))::INT;

    -- Return first of month + (dtstart_day or month_end, whichever is smaller) - 1 + base time
    RETURN date_trunc('month', p_current_base)
        + make_interval(days => LEAST(p_dtstart_day, month_end_day) - 1)
        + p_base_time;
END;
$$ LANGUAGE plpgsql IMMUTABLE;


------------------------------------------------------------------------------------------------------
-- _restore_yearly_base: Restore dtstart month+day-of-month after year advancement
--
-- Similar to _restore_monthly_base but also restores the month component for yearly rules.
-- The target day is clamped to the max days in the target month within the new year.
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _restore_yearly_base(
    p_current_base TIMESTAMPTZ,
    p_basedate TIMESTAMPTZ,
    p_dtstart_day INT,
    p_base_time INTERVAL
) RETURNS TIMESTAMPTZ AS $$
DECLARE
    target_month INT;
    month_end_day INT;
BEGIN
    target_month := date_part('month', p_basedate)::INT;

    -- Get the last day of the target month in the current year
    month_end_day := date_part('day', (date_trunc('year', p_current_base)
        + make_interval(months => target_month)
        - INTERVAL '1 day'))::INT;

    -- Return year start + (target_month - 1) months + (dtstart_day or month_end, whichever is smaller) - 1 days + base time
    RETURN date_trunc('year', p_current_base)
        + make_interval(months => target_month - 1)
        + make_interval(days => LEAST(p_dtstart_day, month_end_day) - 1)
        + p_base_time;
END;
$$ LANGUAGE plpgsql IMMUTABLE;


------------------------------------------------------------------------------------------------------
-- _advance_monthly: Handle one iteration of the MONTHLY SKIP inner loop
--
-- This function handles the core SKIP logic for MONTHLY frequency when the target day doesn't
-- exist in the current month (e.g., Jan 31 in February).
--
-- Parameters:
--   p_current_base  - Current base timestamp (already restored to dtstart day-of-month)
--   p_basedate      - Original dtstart
--   p_dtstart_day   - Day-of-month from dtstart
--   p_interval      - INTERVAL parameter from RRULE
--   p_skip          - SKIP mode: 'OMIT', 'FORWARD', or 'BACKWARD'
--   p_until         - UNTIL bound (can be NULL)
--   p_maxdate       - Maximum date bound
--   p_period_limit  - DoS protection limit
--   p_omit_count    - Running count of OMIT iterations
--   p_period_count  - Running count of periods
--
-- Returns: _skip_result with updated state
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _advance_monthly(
    p_current_base TIMESTAMPTZ,
    p_basedate TIMESTAMPTZ,
    p_dtstart_day INT,
    p_interval INT,
    p_skip TEXT,
    p_until TIMESTAMPTZ,
    p_maxdate TIMESTAMPTZ,
    p_period_limit INT,
    p_omit_count INT,
    p_period_count INT
) RETURNS rrule._skip_result AS $$
DECLARE
    result rrule._skip_result;
    base_time INTERVAL;
    new_base TIMESTAMPTZ;
BEGIN
    base_time := (p_basedate::time)::interval;
    result.current_base := p_current_base;
    result.forward_ts := NULL;
    result.done := FALSE;
    result.omit_count := p_omit_count;
    result.period_count := p_period_count;

    -- Check if day matches - if so, we're done
    IF date_part('day', p_current_base)::INT = p_dtstart_day THEN
        result.done := TRUE;
        RETURN result;
    END IF;

    -- Target day doesn't exist in this month — apply SKIP rule
    IF p_skip = 'OMIT' THEN
        -- Skip this month entirely and advance to the next
        new_base := p_current_base + make_interval(months => p_interval);
        new_base := rrule._restore_monthly_base(new_base, p_dtstart_day, base_time);

        result.current_base := new_base;

        -- Check termination conditions
        IF new_base > p_maxdate THEN
            result.done := TRUE;
            RETURN result;
        END IF;
        IF p_until IS NOT NULL AND new_base > p_until THEN
            result.done := TRUE;
            RETURN result;
        END IF;

        result.omit_count := result.omit_count + 1;
        IF result.omit_count >= p_period_limit THEN
            result.done := TRUE;
        END IF;

    ELSIF p_skip = 'FORWARD' THEN
        -- Emit the FORWARD date (1st of next month) inline
        result.forward_ts := date_trunc('month', p_current_base) + INTERVAL '1 month' + base_time;

        -- Check termination conditions for the emitted date
        IF p_until IS NOT NULL AND result.forward_ts > p_until THEN
            result.forward_ts := NULL;
            result.done := TRUE;
            RETURN result;
        END IF;
        IF result.forward_ts > p_maxdate THEN
            result.forward_ts := NULL;
            result.done := TRUE;
            RETURN result;
        END IF;

        -- Count this FORWARD iteration against the period budget (DoS protection)
        result.period_count := result.period_count + 1;
        IF result.period_count >= p_period_limit THEN
            result.done := TRUE;
            RETURN result;
        END IF;

        -- Advance from current month by interval, restore dtstart_day
        new_base := p_current_base + make_interval(months => p_interval);
        new_base := rrule._restore_monthly_base(new_base, p_dtstart_day, base_time);
        result.current_base := new_base;

    ELSE
        -- BACKWARD (default): keep the coerced date (last day of month)
        result.done := TRUE;
    END IF;

    RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;


------------------------------------------------------------------------------------------------------
-- _advance_yearly: Handle one iteration of the YEARLY SKIP inner loop
--
-- Similar to _advance_monthly but for YEARLY frequency (e.g., Feb 29 in non-leap years).
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _advance_yearly(
    p_current_base TIMESTAMPTZ,
    p_basedate TIMESTAMPTZ,
    p_dtstart_day INT,
    p_interval INT,
    p_skip TEXT,
    p_until TIMESTAMPTZ,
    p_maxdate TIMESTAMPTZ,
    p_period_limit INT,
    p_omit_count INT,
    p_period_count INT
) RETURNS rrule._skip_result AS $$
DECLARE
    result rrule._skip_result;
    base_time INTERVAL;
    new_base TIMESTAMPTZ;
BEGIN
    base_time := (p_basedate::time)::interval;
    result.current_base := p_current_base;
    result.forward_ts := NULL;
    result.done := FALSE;
    result.omit_count := p_omit_count;
    result.period_count := p_period_count;

    -- Check if day matches - if so, we're done
    IF date_part('day', p_current_base)::INT = p_dtstart_day THEN
        result.done := TRUE;
        RETURN result;
    END IF;

    -- Target day doesn't exist in this month/year — apply SKIP rule
    IF p_skip = 'OMIT' THEN
        -- Skip this year entirely and advance to the next
        new_base := p_current_base + make_interval(years => p_interval);
        new_base := rrule._restore_yearly_base(new_base, p_basedate, p_dtstart_day, base_time);

        result.current_base := new_base;

        -- Check termination conditions
        IF new_base > p_maxdate THEN
            result.done := TRUE;
            RETURN result;
        END IF;
        IF p_until IS NOT NULL AND new_base > p_until THEN
            result.done := TRUE;
            RETURN result;
        END IF;

        result.omit_count := result.omit_count + 1;
        IF result.omit_count >= p_period_limit THEN
            result.done := TRUE;
        END IF;

    ELSIF p_skip = 'FORWARD' THEN
        -- Emit the FORWARD date (1st of next month) inline
        result.forward_ts := date_trunc('month', p_current_base) + INTERVAL '1 month' + base_time;

        -- Check termination conditions for the emitted date
        IF p_until IS NOT NULL AND result.forward_ts > p_until THEN
            result.forward_ts := NULL;
            result.done := TRUE;
            RETURN result;
        END IF;
        IF result.forward_ts > p_maxdate THEN
            result.forward_ts := NULL;
            result.done := TRUE;
            RETURN result;
        END IF;

        -- Count this FORWARD iteration against the period budget (DoS protection)
        result.period_count := result.period_count + 1;
        IF result.period_count >= p_period_limit THEN
            result.done := TRUE;
            RETURN result;
        END IF;

        -- Advance to next year at dtstart month+day (clamped)
        new_base := p_current_base + make_interval(years => p_interval);
        new_base := rrule._restore_yearly_base(new_base, p_basedate, p_dtstart_day, base_time);
        result.current_base := new_base;

    ELSE
        -- BACKWARD (default): keep the coerced date
        result.done := TRUE;
    END IF;

    RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;


------------------------------------------------------------------------------------------------------
-- Given a cursor into a set, process the set returning the subset matching the BYSETPOS
--
-- Requires: PostgreSQL 12+ for cursor handling syntax and other modern SQL features.
-- (Cursors with SCROLL support have been stable since PostgreSQL 8.3, but this implementation
-- uses additional features requiring PostgreSQL 12 or later.)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rrule_bysetpos_filter(
  curse REFCURSOR,
  bysetpos INT[]
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  valid_date TIMESTAMP WITH TIME ZONE;
BEGIN

  IF bysetpos IS NULL THEN
    LOOP
      FETCH curse INTO valid_date;
      EXIT WHEN NOT FOUND;
      RETURN NEXT valid_date;
    END LOOP;
  ELSE
    DECLARE
      collected TIMESTAMP WITH TIME ZONE[];
      sorted_date TIMESTAMP WITH TIME ZONE;
    BEGIN
      collected := ARRAY[]::TIMESTAMP WITH TIME ZONE[];
      FOR i IN 1..366 LOOP
        EXIT WHEN bysetpos[i] IS NULL;
        IF bysetpos[i] > 0 THEN
          FETCH ABSOLUTE bysetpos[i] FROM curse INTO valid_date;
        ELSE
          MOVE LAST IN curse;
          FETCH RELATIVE (bysetpos[i] + 1) FROM curse INTO valid_date;
        END IF;
        IF valid_date IS NOT NULL THEN
          collected := array_append(collected, valid_date);
        END IF;
      END LOOP;
      -- Return sorted, deduplicated results
      FOR sorted_date IN SELECT DISTINCT unnest(collected) ORDER BY 1 LOOP
        RETURN NEXT sorted_date;
      END LOOP;
    END;
  END IF;
  CLOSE curse;
END;
$$ LANGUAGE plpgsql VOLATILE;


------------------------------------------------------------------------------------------------------
-- Helper function: Generate times within a day based on BYHOUR/BYMINUTE/BYSECOND
-- If no time filters specified, returns the input time
-- If time filters specified, generates all matching times within the same day
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rrule_day_time_set(
  base_time TIMESTAMP WITH TIME ZONE,
  rule rrule.rrule_parts,
  max_results INT DEFAULT NULL  -- NULL = unlimited, otherwise stop after N results
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  day_start TIMESTAMP WITH TIME ZONE;
  occurrence TIMESTAMP WITH TIME ZONE;
  hour INT;
  minute INT;
  second INT;
  hour_idx INT;
  minute_idx INT;
  second_idx INT;
  result_count INT := 0;
BEGIN
  -- Maintain STRICT semantics for required parameters
  IF base_time IS NULL OR rule IS NULL THEN
    RETURN;
  END IF;

  -- If no time-based filters, return the input time
  IF rule.byhour IS NULL AND rule.byminute IS NULL AND rule.bysecond IS NULL THEN
    RETURN NEXT base_time;
    RETURN;
  END IF;

  day_start := date_trunc('day', base_time);

  -- Generate all combinations of hour/minute/second
  hour_idx := 1;
  LOOP
    EXIT WHEN rule.byhour IS NULL AND hour_idx > 1;
    EXIT WHEN rule.byhour IS NOT NULL AND rule.byhour[hour_idx] IS NULL;

    hour := COALESCE(rule.byhour[hour_idx], date_part('hour', base_time)::INT);
    IF hour < 0 OR hour > 23 THEN
      hour_idx := hour_idx + 1;
      CONTINUE;
    END IF;

    minute_idx := 1;
    LOOP
      EXIT WHEN rule.byminute IS NULL AND minute_idx > 1;
      EXIT WHEN rule.byminute IS NOT NULL AND rule.byminute[minute_idx] IS NULL;

      minute := COALESCE(rule.byminute[minute_idx], date_part('minute', base_time)::INT);
      IF minute < 0 OR minute > 59 THEN
        minute_idx := minute_idx + 1;
        CONTINUE;
      END IF;

      second_idx := 1;
      LOOP
        EXIT WHEN rule.bysecond IS NULL AND second_idx > 1;
        EXIT WHEN rule.bysecond IS NOT NULL AND rule.bysecond[second_idx] IS NULL;

        second := COALESCE(rule.bysecond[second_idx], date_part('second', base_time)::INT);
        IF second < 0 OR second > 59 THEN
          second_idx := second_idx + 1;
          CONTINUE;
        END IF;

        -- Build occurrence timestamp
        occurrence := day_start + make_interval(hours => hour, mins => minute, secs => second);

        RETURN NEXT occurrence;
        result_count := result_count + 1;

        -- Early exit: stop once we've generated enough results
        -- Critical for performance: 24×60×60 = 86,400 possible time slots per day!
        IF max_results IS NOT NULL AND result_count >= max_results THEN
          RETURN;
        END IF;

        second_idx := second_idx + 1;
        EXIT WHEN rule.bysecond IS NULL;
      END LOOP;

      minute_idx := minute_idx + 1;
      EXIT WHEN rule.byminute IS NULL;
    END LOOP;

    hour_idx := hour_idx + 1;
    EXIT WHEN rule.byhour IS NULL;
  END LOOP;

END;
$$ LANGUAGE plpgsql STABLE;  -- STRICT removed to allow NULL max_results


------------------------------------------------------------------------------------------------------
-- Return another day's worth of events
-- Now supports BYHOUR, BYMINUTE, BYSECOND, and BYSETPOS for sub-day scheduling
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION daily_set(
  after_ts TIMESTAMP WITH TIME ZONE,
  rule rrule.rrule_parts,
  max_results INT DEFAULT NULL  -- NULL = unlimited, otherwise stop after N results
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  curse REFCURSOR;
BEGIN
  -- Maintain STRICT semantics for required parameters
  IF after_ts IS NULL OR rule IS NULL THEN
    RETURN;
  END IF;

  IF rule.bymonth IS NOT NULL AND NOT date_part('month',after_ts) = ANY ( rule.bymonth ) THEN
    RETURN;
  END IF;

  IF rule.byweekno IS NOT NULL AND NOT rrule.byweekno_matches_for_year(after_ts, date_trunc('year', after_ts), rule.wkst, rule.byweekno) THEN
    RETURN;
  END IF;

  IF rule.byyearday IS NOT NULL AND NOT rrule.test_byyearday_rule(after_ts, rule.byyearday) THEN
    RETURN;
  END IF;

  IF rule.bymonthday IS NOT NULL AND NOT rrule.test_bymonthday_rule(after_ts, rule.bymonthday) THEN
    RETURN;
  END IF;

  IF rule.byday IS NOT NULL AND NOT rrule.test_byday_rule(after_ts, rule.byday) THEN
    RETURN;
  END IF;

  -- Now handle BYHOUR, BYMINUTE, BYSECOND, and BYSETPOS
  IF rule.byhour IS NOT NULL OR rule.byminute IS NOT NULL OR rule.bysecond IS NOT NULL OR rule.bysetpos IS NOT NULL THEN
    -- Performance optimization: bypass cursor when bysetpos IS NULL
    IF rule.bysetpos IS NOT NULL THEN
      -- Generate times within the day and apply BYSETPOS filter
      -- Pass max_results down (NULL = unlimited, for BYSETPOS which needs full set)
      OPEN curse SCROLL FOR SELECT r FROM rrule.rrule_day_time_set(after_ts, rule, max_results) r ORDER BY 1;
      RETURN QUERY SELECT d FROM rrule.rrule_bysetpos_filter(curse, rule.bysetpos) d;
    ELSE
      -- Direct query without cursor overhead
      RETURN QUERY SELECT r FROM rrule.rrule_day_time_set(after_ts, rule, max_results) r ORDER BY 1;
    END IF;
  ELSE
    -- No sub-day scheduling - return the input time
    RETURN NEXT after_ts;
  END IF;

END;
$$ LANGUAGE plpgsql VOLATILE;  -- VOLATILE: uses cursors/BYSETPOS filter; STRICT removed to allow NULL max_results


------------------------------------------------------------------------------------------------------
-- Return another week's worth of events
--
-- Doesn't handle truly obscure and unlikely stuff like BYWEEKNO=5;BYMONTH=1;BYDAY=WE,TH,FR;BYSETPOS=-2
-- Imagine that.
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION weekly_set(
  after_ts TIMESTAMP WITH TIME ZONE,
  rule rrule.rrule_parts,
  max_results INT DEFAULT NULL  -- NULL = unlimited, otherwise stop after N results
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  curse REFCURSOR;
  weekno INT;
  weekyear INT;
  weeks_in_year INT;
BEGIN
  -- Maintain STRICT semantics for required parameters
  IF after_ts IS NULL OR rule IS NULL THEN
    RETURN;
  END IF;

  IF rule.byweekno IS NOT NULL THEN
    -- ISO 8601 week numbering with WKST; only match weeks within the calendar year
    SELECT week_year, week_num INTO weekyear, weekno
    FROM rrule.get_week_info(after_ts, rule.wkst);
    IF weekyear IS NULL OR weekno IS NULL THEN
      RETURN;
    END IF;
    IF weekyear != date_part('year', after_ts) THEN
      RETURN;
    END IF;
    weeks_in_year := rrule.weeks_in_year(date_trunc('year', after_ts), rule.wkst);
    IF NOT rrule.byweekno_matches(weekno, weeks_in_year, rule.byweekno) THEN
      RETURN;
    END IF;
  END IF;

  -- BYYEARDAY filter: Rare but valid use case
  -- Example: FREQ=WEEKLY;BYYEARDAY=100 = "Every week, but only on day 100 of year"
  IF rule.byyearday IS NOT NULL THEN
    IF NOT rrule.test_byyearday_rule(after_ts, rule.byyearday) THEN
      RETURN;
    END IF;
  END IF;

  -- Performance optimization: bypass cursor when bysetpos IS NULL
  IF rule.bysetpos IS NOT NULL THEN
    -- Pass WKST and max_results to rrule_week_byday_set for proper week boundary calculation
    OPEN curse SCROLL FOR SELECT r FROM rrule.rrule_week_byday_set(after_ts, rule.byday, rule.wkst, max_results) r ORDER BY 1;
    RETURN QUERY SELECT d FROM rrule.rrule_bysetpos_filter(curse, rule.bysetpos) d;
  ELSE
    RETURN QUERY SELECT r FROM rrule.rrule_week_byday_set(after_ts, rule.byday, rule.wkst, max_results) r ORDER BY 1;
  END IF;

END;
$$ LANGUAGE plpgsql VOLATILE;  -- VOLATILE: uses cursors/BYSETPOS filter; STRICT removed to allow NULL max_results


------------------------------------------------------------------------------------------------------
-- Return another month's worth of events
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION monthly_set(
  after_ts TIMESTAMP WITH TIME ZONE,
  rule rrule.rrule_parts,
  max_results INT DEFAULT NULL  -- NULL = unlimited, otherwise stop after N results
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  curse REFCURSOR;
BEGIN
  -- Maintain STRICT semantics for required parameters
  IF after_ts IS NULL OR rule IS NULL THEN
    RETURN;
  END IF;

  /**
  * Need to investigate whether it is legal to set both of these, and whether
  * we are correct to UNION the results, or whether we should INTERSECT them.
  * So at this point, we refer to the specification, which grants us this
  * wonderfully enlightening vision:
  *
  *     If multiple BYxxx rule parts are specified, then after evaluating the
  *     specified FREQ and INTERVAL rule parts, the BYxxx rule parts are
  *     applied to the current set of evaluated occurrences in the following
  *     order: BYMONTH, BYWEEKNO, BYYEARDAY, BYMONTHDAY, BYDAY, BYHOUR,
  *     BYMINUTE, BYSECOND and BYSETPOS; then COUNT and UNTIL are evaluated.
  *
  * My guess is that this means 'INTERSECT'
  */

  -- BYMONTH filter: Limits which months are considered
  -- Example: FREQ=MONTHLY;BYMONTH=1,2,3 = "Every month, but only in Jan/Feb/Mar"
  IF rule.bymonth IS NOT NULL AND NOT date_part('month', after_ts) = ANY ( rule.bymonth ) THEN
    RETURN;
  END IF;

  -- BYWEEKNO filter: Rare but valid use case
  -- Example: FREQ=MONTHLY;BYWEEKNO=10 = "Every month, but only in week 10 of year"
  IF rule.byweekno IS NOT NULL THEN
    -- Use WKST-aware week numbering
    IF NOT rrule.get_week_number(after_ts, rule.wkst) = ANY ( rule.byweekno ) THEN
      RETURN;
    END IF;
  END IF;

  -- BYYEARDAY filter: Rare but valid use case
  -- Example: FREQ=MONTHLY;BYYEARDAY=100 = "Every month, but only on day 100 of year"
  IF rule.byyearday IS NOT NULL THEN
    IF NOT rrule.test_byyearday_rule(after_ts, rule.byyearday) THEN
      RETURN;
    END IF;
  END IF;

  -- Performance optimization: bypass cursor when bysetpos IS NULL
  IF rule.bysetpos IS NOT NULL THEN
    -- Pass NULL to inner generators when INTERSECT post-filter may reject candidates
    -- (CLAUDE.md rule 11: never limit candidate generation before post-filters)
    IF rule.byday IS NOT NULL AND rule.bymonthday IS NOT NULL THEN
      OPEN curse SCROLL FOR SELECT r FROM rrule.rrule_month_byday_set(after_ts, rule.byday, NULL) r
                  INTERSECT SELECT r FROM rrule.rrule_month_bymonthday_set(after_ts, rule.bymonthday, rule.skip, NULL) r
                      ORDER BY 1;
    ELSIF rule.bymonthday IS NOT NULL THEN
      OPEN curse SCROLL FOR SELECT r FROM rrule.rrule_month_bymonthday_set(after_ts, rule.bymonthday, rule.skip, max_results) r ORDER BY 1;
    ELSE
      OPEN curse SCROLL FOR SELECT r FROM rrule.rrule_month_byday_set(after_ts, rule.byday, max_results) r ORDER BY 1;
    END IF;

    RETURN QUERY SELECT d FROM rrule.rrule_bysetpos_filter(curse, rule.bysetpos) d;
  ELSE
    -- Direct query without cursor overhead
    IF rule.byday IS NOT NULL AND rule.bymonthday IS NOT NULL THEN
      RETURN QUERY SELECT r FROM rrule.rrule_month_byday_set(after_ts, rule.byday, NULL) r
                  INTERSECT SELECT r FROM rrule.rrule_month_bymonthday_set(after_ts, rule.bymonthday, rule.skip, NULL) r
                      ORDER BY 1;
    ELSIF rule.bymonthday IS NOT NULL THEN
      RETURN QUERY SELECT r FROM rrule.rrule_month_bymonthday_set(after_ts, rule.bymonthday, rule.skip, max_results) r ORDER BY 1;
    ELSE
      RETURN QUERY SELECT r FROM rrule.rrule_month_byday_set(after_ts, rule.byday, max_results) r ORDER BY 1;
    END IF;
  END IF;

END;
$$ LANGUAGE plpgsql VOLATILE;  -- VOLATILE: uses cursors/BYSETPOS filter; STRICT removed to allow NULL max_results


------------------------------------------------------------------------------------------------------
-- If this is YEARLY;BYMONTH, abuse MONTHLY;BYMONTH for everything except the BYSETPOS
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rrule_yearly_bymonth_set(
  after_ts TIMESTAMP WITH TIME ZONE,
  rule rrule.rrule_parts,
  max_results INT DEFAULT NULL  -- NULL = unlimited, otherwise stop after N results
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  current_base TIMESTAMP WITH TIME ZONE;
  rr rrule.rrule_parts;
  seen_months INT[] := ARRAY[]::INT[];  -- Track emitted months to prevent duplicates from BYMONTH=1,1
BEGIN
  -- Maintain STRICT semantics for required parameters
  IF after_ts IS NULL OR rule IS NULL THEN
    RETURN;
  END IF;

  IF rule.bymonth IS NOT NULL THEN
    -- Ensure we don't pass BYSETPOS down
    rr := rule;
    rr.bysetpos := NULL;
    -- Apply BYWEEKNO/BYYEARDAY at YEARLY level, not per-month
    rr.byweekno := NULL;
    rr.byyearday := NULL;
    FOR i IN 1..12 LOOP
      EXIT WHEN rr.bymonth[i] IS NULL;
      -- Guard: skip if this month was already processed (e.g. BYMONTH=1,1)
      CONTINUE WHEN rr.bymonth[i] = ANY(seen_months);
      seen_months := array_append(seen_months, rr.bymonth[i]);
      IF rr.bymonthday IS NULL AND rr.byday IS NULL THEN
        -- No month-level filters: keep DTSTART day-of-month/time
        current_base := date_trunc('year', after_ts)
                        + make_interval(months => rr.bymonth[i] - 1)
                        + make_interval(days => date_part('day', after_ts)::INT - 1)
                        + (after_ts::time)::interval;
        IF date_part('month', current_base) = rr.bymonth[i] THEN
          -- Day exists in the target month — emit directly
          RETURN NEXT current_base;
        ELSE
          -- Day overflowed (e.g., day 30 in February) — apply SKIP rule (RFC 7529)
          IF rr.skip = 'BACKWARD' THEN
            -- Use last day of the target month
            current_base := date_trunc('year', after_ts)
                            + make_interval(months => rr.bymonth[i])
                            - INTERVAL '1 day'
                            + (after_ts::time)::interval;
            RETURN NEXT current_base;
          ELSIF rr.skip = 'FORWARD' THEN
            -- Use first day of the next month
            current_base := date_trunc('year', after_ts)
                            + make_interval(months => rr.bymonth[i])
                            + (after_ts::time)::interval;
            RETURN NEXT current_base;
          END IF;
          -- OMIT (default) or NULL: skip this month — no RETURN NEXT
        END IF;
      ELSE
        -- Month-level filters present: generate within the month (day-of-month comes from filters)
        current_base := date_trunc('year', after_ts)
                        + make_interval(months => rr.bymonth[i] - 1)
                        + (after_ts::time)::interval;
        RETURN QUERY SELECT r FROM rrule.monthly_set(current_base, rr, max_results) r;
      END IF;
    END LOOP;
  ELSE
    RETURN NEXT after_ts;
  END IF;

END;
$$ LANGUAGE plpgsql VOLATILE;  -- VOLATILE: calls monthly_set which uses cursors; STRICT removed to allow NULL max_results


------------------------------------------------------------------------------------------------------
-- Helper function for YEARLY + BYYEARDAY
-- Generates occurrences for specific days of the year
-- Example: FREQ=YEARLY;BYYEARDAY=100 = April 9/10 (day 100 of each year)
-- Supports negative indices: BYYEARDAY=-1 = December 31
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rrule_yearly_byyearday_set(
  after_ts TIMESTAMP WITH TIME ZONE,
  rule rrule.rrule_parts,
  max_results INT DEFAULT NULL  -- NULL = unlimited, otherwise stop after N results
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  year_start TIMESTAMP WITH TIME ZONE;
  year_end TIMESTAMP WITH TIME ZONE;
  occurrence TIMESTAMP WITH TIME ZONE;
  days_in_year INT;
  yearday INT;
  result_count INT := 0;
BEGIN
  -- Maintain STRICT semantics for required parameters
  IF after_ts IS NULL OR rule IS NULL THEN
    RETURN;
  END IF;

  IF rule.byyearday IS NULL THEN
    RETURN NEXT after_ts;
    RETURN;
  END IF;

  year_start := date_trunc('year', after_ts) + (after_ts::time)::interval;
  year_end := year_start + '1 year'::interval - '1 day'::interval;
  days_in_year := date_part('doy', year_end)::INT;

  -- Process each yearday in the array
  FOR i IN 1..366 LOOP
    EXIT WHEN rule.byyearday[i] IS NULL;

    yearday := rule.byyearday[i];

    IF yearday > 0 THEN
      -- Positive index: 1 = Jan 1, 100 = April 9/10, 365/366 = Dec 31
      IF yearday <= days_in_year THEN
        occurrence := year_start + make_interval(days => yearday - 1);
        RETURN NEXT occurrence;
        result_count := result_count + 1;
        EXIT WHEN max_results IS NOT NULL AND result_count >= max_results;
      END IF;
      -- If yearday > days_in_year (e.g., day 366 in non-leap year), skip it

    ELSIF yearday < 0 THEN
      -- Negative index: -1 = Dec 31, -2 = Dec 30, etc.
      -- Convert to positive: -1 in 365-day year = day 365
      IF abs(yearday) <= days_in_year THEN
        occurrence := year_end + make_interval(days => yearday + 1);
        RETURN NEXT occurrence;
        result_count := result_count + 1;
        EXIT WHEN max_results IS NOT NULL AND result_count >= max_results;
      END IF;
      -- If abs(yearday) > days_in_year, skip it
    END IF;
  END LOOP;

END;
$$ LANGUAGE plpgsql STABLE;  -- STRICT removed to allow NULL max_results


------------------------------------------------------------------------------------------------------
-- YEARLY frequency helper: Generate dates for specified week numbers
-- Used when BYWEEKNO is the primary generator (not just a filter)
-- Example: FREQ=YEARLY;BYWEEKNO=1,10 generates all dates in weeks 1 and 10
-- Example: FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO,FR generates Mondays and Fridays of week 1
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rrule_yearly_byweekno_set(
  after_ts TIMESTAMP WITH TIME ZONE,
  rule rrule_parts,
  max_results INT DEFAULT NULL  -- NULL = unlimited, otherwise stop after N results
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  year_start TIMESTAMP WITH TIME ZONE;
  week_start TIMESTAMP WITH TIME ZONE;
  week1_start TIMESTAMP WITH TIME ZONE;
  weeks_in_year INT;
  week_num INT;
  normalized_week INT;
  occurrence TIMESTAMP WITH TIME ZONE;
  result_count INT := 0;
  remaining INT;
BEGIN
  -- Maintain STRICT semantics for required parameters
  IF after_ts IS NULL OR rule IS NULL THEN
    RETURN;
  END IF;

  year_start := date_trunc('year', after_ts);
  -- ISO week 1 start: week containing Jan 4
  week1_start := rrule.get_week_start(year_start + INTERVAL '3 days', rule.wkst);
  weeks_in_year := rrule.weeks_in_year(year_start, rule.wkst);

  -- For each specified week number
  FOREACH week_num IN ARRAY rule.byweekno LOOP
    normalized_week := week_num;
    IF week_num < 0 THEN
      normalized_week := weeks_in_year + week_num + 1;
    END IF;
    -- Skip invalid week numbers (must be 1..weeks_in_year)
    IF normalized_week < 1 OR normalized_week > weeks_in_year THEN
      CONTINUE;
    END IF;

    -- Calculate start of this week
    -- Week 1 starts at first_wkst, week 2 starts 7 days later, etc.
    week_start := week1_start + (INTERVAL '1 day' * ((normalized_week - 1) * 7));

    -- Add time component from 'after' to maintain time-of-day
    week_start := date_trunc('day', week_start) + (after_ts::time)::INTERVAL;

    IF rule.byday IS NOT NULL THEN
      remaining := CASE
        WHEN max_results IS NULL THEN NULL
        ELSE GREATEST(max_results - result_count, 0)
      END;
      EXIT WHEN max_results IS NOT NULL AND remaining = 0;
      -- Generate all BYDAY occurrences in this week
      FOR occurrence IN
        SELECT r FROM rrule.rrule_week_byday_set(week_start, rule.byday, rule.wkst, remaining) r ORDER BY 1
      LOOP
        -- Only return occurrences that belong to the target ISO year.
        -- Use isoyear on occurrences but calendar year on after_ts, because
        -- ISO weeks at year boundaries can span two calendar years (e.g.,
        -- ISO week 1 of 2026 starts on 2025-12-29).
        IF date_part('isoyear', occurrence) = date_part('year', after_ts) THEN
          RETURN NEXT occurrence;
          result_count := result_count + 1;
          EXIT WHEN max_results IS NOT NULL AND result_count >= max_results;
        END IF;
      END LOOP;
      EXIT WHEN max_results IS NOT NULL AND result_count >= max_results;
    ELSE
      -- No BYDAY specified - return the week start date
      IF date_part('isoyear', week_start) = date_part('year', after_ts) THEN
        RETURN NEXT week_start;
        result_count := result_count + 1;
        EXIT WHEN max_results IS NOT NULL AND result_count >= max_results;
      END IF;
    END IF;
  END LOOP;

  RETURN;
END;
$$ LANGUAGE plpgsql STABLE;  -- STRICT removed to allow NULL max_results


------------------------------------------------------------------------------------------------------
-- Return another year's worth of events
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION yearly_set(
  after_ts TIMESTAMP WITH TIME ZONE,
  rule rrule.rrule_parts,
  max_results INT DEFAULT NULL,  -- NULL = unlimited, otherwise stop after N results
  min_in_period TIMESTAMP WITH TIME ZONE DEFAULT NULL  -- Filter: only return dates >= this value
) RETURNS SETOF TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  curse REFCURSOR;
  rr rrule.rrule_parts;
  year_start TIMESTAMP WITH TIME ZONE;
  has_yearly_ordinals BOOLEAN := FALSE;
BEGIN
  -- Maintain STRICT semantics for required parameters
  IF after_ts IS NULL OR rule IS NULL THEN
    RETURN;
  END IF;

  year_start := date_trunc('year', after_ts);
  rr := rule;
  rr.bysetpos := NULL;  -- apply BYSETPOS at the end (RFC 5545 order)
  -- Apply BYWEEKNO/BYYEARDAY at YEARLY level, not per-month
  rr.byweekno := NULL;
  rr.byyearday := NULL;

  -- Detect YEARLY BYDAY ordinals without BYMONTH/BYWEEKNO (ordinals apply within the year)
  IF rule.byday IS NOT NULL AND rule.bymonth IS NULL AND rule.byweekno IS NULL THEN
    FOR i IN 1..array_length(rule.byday, 1) LOOP
      EXIT WHEN rule.byday[i] IS NULL;
      IF rule.byday[i] ~ '^[+-]?[0-9]+' THEN
        has_yearly_ordinals := TRUE;
        EXIT;
      END IF;
    END LOOP;
  END IF;

  -- Build candidate set according to RFC 5545 order, then apply BYSETPOS last.
  -- BYMONTH and BYYEARDAY are both "Expand" with YEARLY (RFC 5545 §3.3.10 table).
  -- When both are present, one generates candidates and the other filters (intersection).
  -- See DECISIONS.md #5.
  IF rule.bymonth IS NOT NULL THEN
    -- BYMONTH primary
    -- Pass NULL max_results when post-filters may reject candidates
    -- Use DISTINCT to deduplicate when SKIP=FORWARD overflows into adjacent BYMONTH months
    OPEN curse SCROLL FOR
      SELECT DISTINCT r
      FROM rrule.rrule_yearly_bymonth_set(after_ts, rr,
        CASE WHEN rule.byweekno IS NOT NULL OR rule.byyearday IS NOT NULL
             THEN NULL ELSE max_results END) r
      WHERE (min_in_period IS NULL OR r >= min_in_period)
        AND (rule.byweekno IS NULL OR rrule.byweekno_matches_for_year(r, year_start, rule.wkst, rule.byweekno))
        AND (rule.byyearday IS NULL OR rrule.test_byyearday_rule(r, rule.byyearday))
      ORDER BY 1;

  ELSIF rule.byweekno IS NOT NULL THEN
    -- BYWEEKNO primary
    -- Pass NULL max_results when post-filters may reject candidates
    OPEN curse SCROLL FOR
      SELECT r
      FROM rrule.rrule_yearly_byweekno_set(after_ts, rule,
        CASE WHEN rule.bymonth IS NOT NULL OR rule.byyearday IS NOT NULL OR rule.bymonthday IS NOT NULL OR rule.byday IS NOT NULL
             THEN NULL ELSE max_results END) r
      WHERE (min_in_period IS NULL OR r >= min_in_period)
        AND (rule.bymonth IS NULL OR rrule.test_bymonth_rule(r, rule.bymonth))
        AND (rule.byyearday IS NULL OR rrule.test_byyearday_rule(r, rule.byyearday))
        AND (rule.bymonthday IS NULL OR rrule.test_bymonthday_rule(r, rule.bymonthday))
        AND (rule.byday IS NULL OR rrule.test_byday_rule(r, rule.byday))
      ORDER BY 1;

  ELSIF rule.byyearday IS NOT NULL THEN
    -- BYYEARDAY primary (pass rule, not rr, because rr has byyearday nulled out)
    -- Pass NULL max_results when post-filters may reject candidates
    OPEN curse SCROLL FOR
      SELECT r
      FROM rrule.rrule_yearly_byyearday_set(after_ts, rule,
        CASE WHEN rule.bymonth IS NOT NULL OR rule.bymonthday IS NOT NULL OR rule.byday IS NOT NULL
             THEN NULL ELSE max_results END) r
      WHERE (min_in_period IS NULL OR r >= min_in_period)
        AND (rule.bymonth IS NULL OR rrule.test_bymonth_rule(r, rule.bymonth))
        AND (rule.bymonthday IS NULL OR rrule.test_bymonthday_rule(r, rule.bymonthday))
        AND (rule.byday IS NULL OR rrule.test_byday_rule(r, rule.byday))
      ORDER BY 1;

  ELSIF has_yearly_ordinals THEN
    -- YEARLY BYDAY ordinals (no BYMONTH/BYWEEKNO): ordinals apply across the year
    OPEN curse SCROLL FOR
      SELECT r
      FROM rrule.rrule_year_byday_set(after_ts, rule.byday, CASE WHEN rule.bymonthday IS NULL THEN max_results ELSE NULL END) r
      WHERE (min_in_period IS NULL OR r >= min_in_period)
        AND (rule.bymonthday IS NULL OR rrule.test_bymonthday_rule(r, rule.bymonthday))
      ORDER BY 1;

  ELSIF rule.bymonthday IS NOT NULL OR rule.byday IS NOT NULL THEN
    -- Month/day filters without BYMONTH
    IF rule.bysetpos IS NOT NULL THEN
      -- BYSETPOS needs full candidate set - use cursor for bysetpos_filter
      OPEN curse SCROLL FOR
        SELECT r
        FROM generate_series(1, 12) m
        CROSS JOIN LATERAL rrule.monthly_set(
          date_trunc('year', after_ts) + make_interval(months => m - 1) + (after_ts::time)::interval,
          rr,
          NULL  -- No limit when BYSETPOS active
        ) r
        WHERE (min_in_period IS NULL OR r >= min_in_period)
        ORDER BY 1;
    ELSE
      -- No BYSETPOS: iterate months with early exit optimization (Issue 51)
      DECLARE
        result_count INT := 0;
        month_ts TIMESTAMP WITH TIME ZONE;
        y TIMESTAMP WITH TIME ZONE;
      BEGIN
        FOR m IN 1..12 LOOP
          month_ts := date_trunc('year', after_ts) + make_interval(months => m - 1) + (after_ts::time)::interval;
          FOR y IN SELECT r FROM rrule.monthly_set(month_ts, rr,
                      CASE WHEN max_results IS NULL THEN NULL
                           ELSE max_results - result_count END) r
                    WHERE (min_in_period IS NULL OR r >= min_in_period)
                    ORDER BY 1 LOOP
            RETURN NEXT y;
            result_count := result_count + 1;
            IF max_results IS NOT NULL AND result_count >= max_results THEN
              RETURN;
            END IF;
          END LOOP;
        END LOOP;
        RETURN;
      END;
    END IF;

  ELSE
    -- No BYMONTH/BYWEEKNO/BYYEARDAY/BYMONTHDAY/BYDAY - return anniversary of dtstart
    RETURN NEXT after_ts;
    RETURN;
  END IF;

  -- Performance optimization: bypass cursor when bysetpos IS NULL
  IF rule.bysetpos IS NOT NULL THEN
    RETURN QUERY SELECT d FROM rrule.rrule_bysetpos_filter(curse, rule.bysetpos) d;
  ELSE
    -- Fetch all from cursor directly
    DECLARE
      valid_date TIMESTAMP WITH TIME ZONE;
    BEGIN
      LOOP
        FETCH curse INTO valid_date;
        EXIT WHEN NOT FOUND;
        RETURN NEXT valid_date;
      END LOOP;
      CLOSE curse;
    END;
  END IF;
END;
$$ LANGUAGE plpgsql VOLATILE;  -- VOLATILE: uses cursors/BYSETPOS filter; STRICT removed to allow NULL max_results


------------------------------------------------------------------------------------------------------
-- SUB-DAY FREQUENCY FUNCTIONS (HOURLY, MINUTELY, SECONDLY)
------------------------------------------------------------------------------------------------------
--
-- These frequencies are DISABLED in the standard installation for security reasons.
--
-- WHY DISABLED?
-- - HOURLY: Can generate 8,760 occurrences per year
-- - MINUTELY: Can generate 525,600 occurrences per year
-- - SECONDLY: Can generate 31,536,000 occurrences per year
-- - Risk of denial-of-service in multi-tenant environments
-- - Can exhaust CPU, memory, and database connection pools
--
-- HOW TO ENABLE:
-- Use the alternative installation script which includes sub-day frequency support:
--   cd src
--   psql -d your_database -f install_with_subday.sql
--
-- This will load rrule_subday.sql which defines:
--   - hourly_set() function
--   - minutely_set() function
--   - secondly_set() function
--   - Modified event loop that enables sub-day frequencies
--
-- SECURITY REQUIREMENTS:
-- Before enabling, you MUST:
-- 1. Review security implications in INCLUDING_SUBDAY_OPERATIONS.md
-- 2. Implement application-level validation (COUNT/UNTIL limits)
-- 3. Configure statement_timeout to prevent runaway queries
-- 4. Set up monitoring for long-running queries
-- 5. Test thoroughly in staging environment
--
-- See src/rrule_subday.sql for the complete implementation.
--
------------------------------------------------------------------------------------------------------


------------------------------------------------------------------------------------------------------
-- Combine all of that into something which we can use to generate a series from an arbitrary DTSTART/RRULE
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
  omit_count INT;
  rule rrule.rrule_parts%ROWTYPE;
  skip_r rrule._skip_result;  -- Result from SKIP helper functions
BEGIN
  SELECT * INTO rule FROM rrule.parse_rrule_parts(basedate, repeatrule);

  -- Output cap: respect both API limit and RRULE COUNT
  output_limit := max_count;
  IF rule.count IS NOT NULL THEN
    output_limit := COALESCE(output_limit, rule.count);
    output_limit := LEAST(output_limit, rule.count);
  END IF;

  -- Security: Calculate safe period scan limit accounting for sparse BYxxx filters
  -- (e.g., FREQ=DAILY;BYDAY=MO only matches 1/7 days, requiring 20x headroom)
  -- See calculate_safe_iteration_limit() for detailed security rationale.
  period_limit := COALESCE(rrule.calculate_safe_iteration_limit(rule.freq, rule.count, output_limit, rule.interval), 1000);

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
      FOR current IN SELECT d FROM rrule.daily_set(current_base, rule,
                                                     CASE WHEN rule.bysetpos IS NULL AND rule.bymonthday IS NULL AND rule.bymonth IS NULL
                                                          THEN (CASE WHEN output_limit IS NULL THEN NULL ELSE GREATEST(output_limit - emitted_count, 0) END)
                                                          ELSE NULL END) d WHERE d >= min_in_period LOOP
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
      FOR current IN SELECT w FROM rrule.weekly_set(current_base, rule,
                                                      CASE WHEN rule.bysetpos IS NULL AND rule.bymonthday IS NULL AND rule.bymonth IS NULL
                                                           THEN (CASE WHEN output_limit IS NULL THEN NULL ELSE GREATEST(output_limit - emitted_count, 0) END)
                                                           ELSE NULL END) w WHERE w >= min_in_period LOOP
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
      FOR current IN SELECT m FROM rrule.monthly_set(current_base, rule,
                                                       CASE WHEN rule.bysetpos IS NULL AND rule.bymonthday IS NULL AND rule.bymonth IS NULL
                                                            THEN (CASE WHEN output_limit IS NULL THEN NULL ELSE GREATEST(output_limit - emitted_count, 0) END)
                                                            ELSE NULL END) m WHERE m >= min_in_period LOOP
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
      -- Handle implicit SKIP and drift prevention for month advancement without BYMONTHDAY/BYDAY.
      -- PostgreSQL coerces invalid dates (e.g., Jan 31 + 1 month = Feb 28). We restore dtstart_day
      -- before entering the drift prevention loop to prevent cumulative drift from FORWARD.
      IF rule.bymonthday IS NULL AND rule.byday IS NULL THEN
        -- Restore dtstart day-of-month to prevent cumulative drift from FORWARD
        current_base := rrule._restore_monthly_base(current_base, dtstart_day, (basedate::time)::interval);
        omit_count := 0;
        LOOP
          skip_r := rrule._advance_monthly(
              current_base, basedate, dtstart_day, rule.interval, rule.skip,
              rule.until, maxdate, period_limit, omit_count, period_count
          );
          current_base := skip_r.current_base;
          omit_count := skip_r.omit_count;
          period_count := skip_r.period_count;
          -- Handle FORWARD emission (skip_r.forward_ts is non-NULL when SKIP=FORWARD produced a date)
          IF skip_r.forward_ts IS NOT NULL THEN
            occurrence_count := occurrence_count + 1;
            IF rule.count IS NOT NULL AND occurrence_count > rule.count THEN
              EXIT;
            END IF;
            IF skip_r.forward_ts >= mindate THEN
              RETURN NEXT skip_r.forward_ts;
              emitted_count := emitted_count + 1;
              EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
            END IF;
          END IF;
          EXIT WHEN skip_r.done;
        END LOOP;
      END IF;
    ELSIF rule.freq = 'YEARLY' THEN
      period_start := date_trunc('year', current_base) + (current_base::time)::interval;
      min_in_period := CASE WHEN current_base = basedate THEN basedate ELSE period_start END;
      FOR current IN SELECT y FROM rrule.yearly_set(current_base, rule,
                                                      CASE WHEN rule.bysetpos IS NULL AND rule.bymonthday IS NULL AND rule.bymonth IS NULL
                                                           THEN (CASE WHEN output_limit IS NULL THEN NULL ELSE GREATEST(output_limit - emitted_count, 0) END)
                                                           ELSE NULL END,
                                                      min_in_period) y LOOP
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
      -- Handle implicit SKIP and drift prevention for year advancement without BYMONTHDAY/BYDAY.
      -- Restore dtstart month+day to prevent cumulative drift from FORWARD.
      IF rule.bymonthday IS NULL AND rule.byday IS NULL THEN
        -- Restore dtstart month and day-of-month within the new year
        current_base := rrule._restore_yearly_base(current_base, basedate, dtstart_day, (basedate::time)::interval);
        omit_count := 0;
        LOOP
          skip_r := rrule._advance_yearly(
              current_base, basedate, dtstart_day, rule.interval, rule.skip,
              rule.until, maxdate, period_limit, omit_count, period_count
          );
          current_base := skip_r.current_base;
          omit_count := skip_r.omit_count;
          period_count := skip_r.period_count;
          -- Handle FORWARD emission (skip_r.forward_ts is non-NULL when SKIP=FORWARD produced a date)
          IF skip_r.forward_ts IS NOT NULL THEN
            occurrence_count := occurrence_count + 1;
            IF rule.count IS NOT NULL AND occurrence_count > rule.count THEN
              EXIT;
            END IF;
            IF skip_r.forward_ts >= mindate THEN
              RETURN NEXT skip_r.forward_ts;
              emitted_count := emitted_count + 1;
              EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
            END IF;
          END IF;
          EXIT WHEN skip_r.done;
        END LOOP;
      END IF;

    -- ⚠️ SUB-DAY FREQUENCIES NOT AVAILABLE IN STANDARD INSTALLATION
    --
    -- HOURLY, MINUTELY, and SECONDLY frequencies are disabled by default due to
    -- security and performance concerns (can generate millions of occurrences).
    --
    -- To enable sub-day frequencies, use the alternative installation:
    --   psql -d your_database -f src/install_with_subday.sql
    --
    -- SECURITY WARNING: Sub-day frequencies pose DoS risks in multi-tenant environments.
    -- See INCLUDING_SUBDAY_OPERATIONS.md for:
    --   - Risk assessment and mitigation strategies
    --   - Required application-level validation (COUNT/UNTIL limits)
    --   - Performance implications and monitoring requirements
    --
    ELSE
      -- Provide helpful error message for sub-day frequencies
      IF rule.freq IN ('HOURLY', 'MINUTELY', 'SECONDLY') THEN
        RAISE EXCEPTION 'Frequency "%" is not supported in standard installation. Sub-day frequencies (HOURLY, MINUTELY, SECONDLY) are disabled by default for security. To enable them, use: psql -d your_database -f src/install_with_subday.sql (or SQL.installWithSubday for npm users). See INCLUDING_SUBDAY_OPERATIONS.md for security considerations.', rule.freq;
      ELSE
        RAISE EXCEPTION 'Unsupported frequency: %. Valid values are: DAILY, WEEKLY, MONTHLY, YEARLY. For sub-day frequencies, see INCLUDING_SUBDAY_OPERATIONS.md', rule.freq;
      END IF;
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
-- PUBLIC API FUNCTIONS (TIMESTAMP API)
--
-- The following functions provide a standard API compatible with rrule.js and python-dateutil.
--
-- inc parameter (DECISIONS.md #3): between/after/before accept inc BOOLEAN DEFAULT FALSE.
-- When TRUE, boundary dates are included. Default FALSE matches rrule.js and python-dateutil.
--
-- All functions use SET timezone = 'UTC' (DECISIONS.md #1) for deterministic expansion.
-- The SET clause restores the caller's timezone on function exit — no session side effects.
------------------------------------------------------------------------------------------------------

-- Create 'rrule' type as a domain over VARCHAR
DO $$
BEGIN
    -- Check if rrule type exists
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'rrule' AND typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'rrule')) THEN
        -- Create domain if type doesn't exist
        CREATE DOMAIN rrule AS VARCHAR;
    END IF;
END $$;


------------------------------------------------------------------------------------------------------
-- CORE API: rrule."all"()
--
-- Returns all occurrences matching the RRULE (streaming via SETOF)
-- Matches: rrule.js .all() and python-dateutil iteration
--
-- Parameters:
--   rrule_string: RRULE string (e.g., 'FREQ=DAILY;COUNT=10' or 'FREQ=DAILY;COUNT=10;TZID=America/New_York')
--   dtstart: Start date as naive TIMESTAMP (wall-clock time in the timezone specified by TZID, or UTC if no TZID)
--
-- Returns: SETOF naive TIMESTAMPs (wall-clock times in the same timezone as dtstart)
--
-- TZID Support:
-- - If TZID is specified in rrule_string, dtstart is interpreted as wall-clock time in that timezone
-- - Returned timestamps are wall-clock times in that same timezone
-- - DST transitions are handled automatically by PostgreSQL
-- - If no TZID is specified, treats dtstart as UTC (legacy behavior)
--
-- Implementation notes:
-- - Generates occurrences up to 10 years from dtstart
-- - Returns up to 1000 occurrences by default
-- - Uses SETOF for streaming (memory efficient)
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "all"(
    rrule_string VARCHAR,
    dtstart TIMESTAMP
)
RETURNS SETOF TIMESTAMP AS $$
DECLARE
    max_count INT;
    dtstart_utc TIMESTAMPTZ;
    maxdate_utc TIMESTAMPTZ;
    tzid TEXT;
BEGIN
    -- Reject NULL RRULE early (STRICT on internal functions would silently return empty)
    IF rrule_string IS NULL THEN
        RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required. Specify one of: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, or YEARLY.  RFC 5545 Section 3.3.10: "FREQ rule part is REQUIRED"';
    END IF;

    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    max_count := 1000;

    -- Extract TZID from rrule string
    tzid := substring(rrule_string from 'TZID=([^;]+)(;|$)');

    -- Validate TZID if provided (using centralized validation helper)
    PERFORM rrule.validate_timezone(tzid);

    -- CRITICAL: For TZID support, we generate occurrences in naive TIMESTAMP space
    -- treating it as UTC, then the naive timestamps are interpreted as wall-clock times
    -- in the target timezone. This ensures "10 AM" stays "10 AM" across DST transitions.
    --
    -- Example: FREQ=DAILY with TZID=America/New_York
    --   - Generate: 2025-03-08 10:00, 2025-03-09 10:00, 2025-03-10 10:00 (naive)
    --   - Interpret as: 10 AM EST, 10 AM EDT, 10 AM EDT (wall-clock times)
    --   - NOT: 10 AM EST (15:00 UTC), 11 AM EDT (15:00 UTC) ← wrong!

    dtstart_utc := dtstart AT TIME ZONE 'UTC';
    maxdate_utc := dtstart_utc + INTERVAL '10 years';

    -- Generate occurrences in UTC space (naive timestamps treated as UTC)
    -- Return as SETOF for streaming (memory efficient)
    RETURN QUERY
        SELECT (d AT TIME ZONE 'UTC')::TIMESTAMP
        FROM rrule.rrule_event_instances_range(
            dtstart_utc,
            rrule_string,
            dtstart_utc,
            maxdate_utc,
            max_count
        ) d;
END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';


------------------------------------------------------------------------------------------------------
-- CORE API: rrule.between()
--
-- Returns occurrences between two dates (streaming via SETOF)
-- Matches: rrule.js .between() and python-dateutil .between()
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "between"(
    rrule_string VARCHAR,
    dtstart TIMESTAMP,
    start_date TIMESTAMP,
    end_date TIMESTAMP,
    inc BOOLEAN DEFAULT FALSE
)
RETURNS SETOF TIMESTAMP AS $$
DECLARE
    max_count INT;
    dtstart_utc TIMESTAMPTZ;
    start_utc TIMESTAMPTZ;
    end_utc TIMESTAMPTZ;
    tzid TEXT;
BEGIN
    -- Reject NULL RRULE early (STRICT on internal functions would silently return empty)
    IF rrule_string IS NULL THEN
        RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required. Specify one of: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, or YEARLY.  RFC 5545 Section 3.3.10: "FREQ rule part is REQUIRED"';
    END IF;

    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    IF start_date IS NULL THEN
        RAISE EXCEPTION 'start_date is required and cannot be NULL';
    END IF;

    IF end_date IS NULL THEN
        RAISE EXCEPTION 'end_date is required and cannot be NULL';
    END IF;

    max_count := 1000;

    -- Extract TZID from rrule string
    tzid := substring(rrule_string from 'TZID=([^;]+)(;|$)');

    -- Validate TZID if provided (using centralized validation helper)
    PERFORM rrule.validate_timezone(tzid);

    -- Generate in naive TIMESTAMP space (see all() function for explanation)
    dtstart_utc := dtstart AT TIME ZONE 'UTC';
    start_utc := start_date AT TIME ZONE 'UTC';
    end_utc := end_date AT TIME ZONE 'UTC';
    -- Clamp end_utc to dtstart + 10 years (matching all()'s behavior) to prevent DoS on sparse rules
    end_utc := LEAST(end_utc, dtstart_utc + INTERVAL '10 years');

    -- Generate occurrences in UTC space (naive timestamps treated as UTC)
    -- When inc=true, extend maxdate by 1 day so the range function generates the boundary period
    RETURN QUERY
        SELECT (d AT TIME ZONE 'UTC')::TIMESTAMP
        FROM rrule.rrule_event_instances_range(
            dtstart_utc,
            rrule_string,
            start_utc,
            end_utc + CASE WHEN inc THEN INTERVAL '1 day' ELSE INTERVAL '0' END,
            max_count
        ) d
        WHERE CASE
            WHEN inc THEN d >= start_utc AND d <= end_utc
            ELSE d > start_utc AND d < end_utc
        END;
END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';


------------------------------------------------------------------------------------------------------
-- CORE API: rrule.after()
--
-- Returns the first occurrence after a specific date
-- Matches: python-dateutil .after()
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "after"(
    rrule_string VARCHAR,
    dtstart TIMESTAMP,
    after_date TIMESTAMP,
    inc BOOLEAN DEFAULT FALSE
)
RETURNS TIMESTAMP AS $$
DECLARE
    next_occurrence TIMESTAMP;
    dtstart_utc TIMESTAMPTZ;
    after_utc TIMESTAMPTZ;
    maxdate_utc TIMESTAMPTZ;
    tzid TEXT;
BEGIN
    -- Reject NULL RRULE early (STRICT on internal functions would silently return empty)
    IF rrule_string IS NULL THEN
        RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required. Specify one of: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, or YEARLY.  RFC 5545 Section 3.3.10: "FREQ rule part is REQUIRED"';
    END IF;

    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    IF after_date IS NULL THEN
        RAISE EXCEPTION 'after_date is required and cannot be NULL';
    END IF;

    -- Extract TZID from rrule string
    tzid := substring(rrule_string from 'TZID=([^;]+)(;|$)');

    -- Validate TZID if provided (using centralized validation helper)
    PERFORM rrule.validate_timezone(tzid);

    -- Optimized: call range function directly with after_date as mindate
    -- This skips generating all occurrences before after_date (O(1) vs O(N))
    dtstart_utc := dtstart AT TIME ZONE 'UTC';
    after_utc := after_date AT TIME ZONE 'UTC';
    maxdate_utc := GREATEST(dtstart_utc, after_utc) + INTERVAL '10 years';

    -- max_count=1000: sparse rules may need many periods before finding occurrence after after_date
    SELECT (d AT TIME ZONE 'UTC')::TIMESTAMP INTO next_occurrence
    FROM rrule.rrule_event_instances_range(
        dtstart_utc,
        rrule_string,
        after_utc,
        maxdate_utc,
        1000
    ) d
    WHERE CASE
        WHEN inc THEN (d AT TIME ZONE 'UTC')::TIMESTAMP >= after_date
        ELSE (d AT TIME ZONE 'UTC')::TIMESTAMP > after_date
    END
    LIMIT 1;

    RETURN next_occurrence;
END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';


------------------------------------------------------------------------------------------------------
-- CORE API: rrule.before()
--
-- Returns the last occurrence before a specific date
-- Matches: python-dateutil .before()
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "before"(
    rrule_string VARCHAR,
    dtstart TIMESTAMP,
    before_date TIMESTAMP,
    inc BOOLEAN DEFAULT FALSE
)
RETURNS TIMESTAMP AS $$
DECLARE
    previous_occurrence TIMESTAMP;
    dtstart_utc TIMESTAMPTZ;
    before_utc TIMESTAMPTZ;
    maxdate_utc TIMESTAMPTZ;
    tzid TEXT;
    scan_count BIGINT;
    has_bound BOOLEAN;
BEGIN
    -- Reject NULL RRULE early (STRICT on internal functions would silently return empty)
    IF rrule_string IS NULL THEN
        RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required. Specify one of: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, or YEARLY.  RFC 5545 Section 3.3.10: "FREQ rule part is REQUIRED"';
    END IF;

    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    IF before_date IS NULL THEN
        RAISE EXCEPTION 'before_date is required and cannot be NULL';
    END IF;

    -- Extract TZID from rrule string
    tzid := substring(rrule_string from 'TZID=([^;]+)(;|$)');

    -- Validate TZID if provided (using centralized validation helper)
    PERFORM rrule.validate_timezone(tzid);

    -- Check if the rule has a natural bound (COUNT or UNTIL)
    has_bound := (rrule_string ~* '(^|;)COUNT=' OR rrule_string ~* '(^|;)UNTIL=');

    -- Optimized: call range function with before_date as maxdate
    -- This avoids scanning beyond the boundary (up to 10 years)
    dtstart_utc := dtstart AT TIME ZONE 'UTC';
    before_utc := before_date AT TIME ZONE 'UTC';
    -- Add 1 day buffer when inc=true so the range function generates the boundary period
    maxdate_utc := before_utc + CASE WHEN inc THEN INTERVAL '1 day' ELSE INTERVAL '0' END;

    -- before() must scan all occurrences up to before_date to find the last one,
    -- so we pass a large output_limit to avoid truncation by the generator.
    -- Note: rrule_event_instances_range is STRICT (NULL returns no rows), so we
    -- pass 1000000 which is large enough for scanning within the maxdate window yet safe from integer
    -- overflow in calculate_safe_iteration_limit (max multiplier 40x = 2B < INT_MAX).
    SELECT occurrence INTO previous_occurrence
    FROM (
        SELECT (d AT TIME ZONE 'UTC')::TIMESTAMP AS occurrence
        FROM rrule.rrule_event_instances_range(
            dtstart_utc,
            rrule_string,
            dtstart_utc,
            maxdate_utc,
            1000000
        ) d
    ) sub
    WHERE CASE
        WHEN inc THEN occurrence <= before_date
        ELSE occurrence < before_date
    END
    ORDER BY occurrence DESC
    LIMIT 1;

    -- Only compute scan_count for the warning when rule is unbounded.
    -- This is a separate query to avoid COUNT(*) OVER() in the main query,
    -- which would force PostgreSQL to materialize all rows before LIMIT 1.
    IF NOT has_bound THEN
        SELECT COUNT(*)::BIGINT INTO scan_count
        FROM (
            SELECT (d AT TIME ZONE 'UTC')::TIMESTAMP AS occurrence
            FROM rrule.rrule_event_instances_range(
                dtstart_utc,
                rrule_string,
                dtstart_utc,
                maxdate_utc,
                1000000
            ) d
        ) sub;
    END IF;

    -- Warn when before() scanned many occurrences on an unbounded rule,
    -- matching the safety warning that all() and between() emit at 1000.
    IF NOT has_bound AND scan_count IS NOT NULL AND scan_count > 1000 THEN
        RAISE WARNING 'rrule: before() scanned % occurrences to find the last match. The recurrence rule has no COUNT or UNTIL and produced many results. Consider adding bounds to the rule.', scan_count;
    END IF;

    RETURN previous_occurrence;
END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';


------------------------------------------------------------------------------------------------------
-- CORE API: rrule."count"()
--
-- Returns the total number of occurrences
-- Matches: python-dateutil .count()
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "count"(
    rrule_string VARCHAR,
    dtstart TIMESTAMP
)
RETURNS INTEGER AS $$
DECLARE
    occurrence_count INTEGER;
BEGIN
    IF rrule_string IS NULL THEN
        RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required. Specify one of: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, or YEARLY.  RFC 5545 Section 3.3.10: "FREQ rule part is REQUIRED"';
    END IF;

    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    SELECT COUNT(*)::INTEGER INTO occurrence_count
    FROM rrule."all"(rrule_string, dtstart);

    RETURN occurrence_count;
END;
$$ LANGUAGE plpgsql VOLATILE;


------------------------------------------------------------------------------------------------------
-- CONVENIENCE: rrule.next()
--
-- Get the next occurrence from NOW (current timestamp) or a given reference time
-- Common use case: "When does this event occur next?"
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "next"(
    rrule_string VARCHAR,
    dtstart TIMESTAMP,
    reference_time TIMESTAMP DEFAULT NULL
)
RETURNS TIMESTAMP AS $$
BEGIN
    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    RETURN rrule."after"(rrule_string, dtstart, COALESCE(reference_time, NOW()::TIMESTAMP));
END;
$$ LANGUAGE plpgsql VOLATILE;


------------------------------------------------------------------------------------------------------
-- CONVENIENCE: rrule.most_recent()
--
-- Get the most recent occurrence before NOW (current timestamp) or a given reference time
-- Common use case: "When did this event last occur?"
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "most_recent"(
    rrule_string VARCHAR,
    dtstart TIMESTAMP,
    reference_time TIMESTAMP DEFAULT NULL
)
RETURNS TIMESTAMP AS $$
BEGIN
    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    RETURN rrule."before"(rrule_string, dtstart, COALESCE(reference_time, NOW()::TIMESTAMP));
END;
$$ LANGUAGE plpgsql VOLATILE;


------------------------------------------------------------------------------------------------------
-- ADVANCED: rrule."overlaps"()
--
-- Check if a recurring event has ANY occurrences overlapping a date range
-- Useful for calendar queries: "Does this meeting conflict with this date range?"
--
-- This is an optimized version that stops at the first occurrence found
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "overlaps"(
    dtstart TIMESTAMP WITH TIME ZONE,
    dtend TIMESTAMP WITH TIME ZONE,
    rrule_string TEXT,
    mindate TIMESTAMP WITH TIME ZONE,
    maxdate TIMESTAMP WITH TIME ZONE
)
RETURNS BOOLEAN AS $$
DECLARE
    base_date TIMESTAMP WITH TIME ZONE;
    duration INTERVAL;
    adjusted_mindate TIMESTAMP WITH TIME ZONE;
    adjusted_maxdate TIMESTAMP WITH TIME ZONE;
BEGIN
    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    base_date := dtstart;
    duration := COALESCE(dtend, dtstart) - dtstart;

    adjusted_maxdate := COALESCE(maxdate, dtstart + '10 years'::interval);
    adjusted_mindate := COALESCE(mindate, dtstart - '10 years'::interval);

    -- If no RRULE, check single event overlap using original (non-duration-expanded) bounds.
    -- A single event [dtstart, dtend] overlaps [mindate, maxdate] iff dtstart < maxdate AND dtend >= mindate.
    -- Duration expansion is only needed for recurring events (to catch occurrences starting before the window).
    IF rrule_string IS NULL THEN
        RETURN (dtstart < adjusted_maxdate AND (dtstart + duration) >= adjusted_mindate);
    END IF;

    -- Expand search window to account for event duration (recurring events only)
    IF duration > INTERVAL '0' THEN
        adjusted_mindate := adjusted_mindate - duration;
    END IF;

    -- Check if there's at least one occurrence in the range
    -- max_count=1000 provides sufficient iteration budget for sparse rules (e.g., FREQ=DAILY;INTERVAL=100;BYMONTHDAY=31).
    -- LIMIT 1 stops at the first match, so memory usage is bounded regardless of max_count.
    PERFORM d
    FROM rrule.rrule_event_instances_range(base_date, rrule_string, adjusted_mindate, adjusted_maxdate, 1000) d
    LIMIT 1;

    RETURN FOUND;

END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';

-- ================================================================================================================
-- TIMEZONE-AWARE RRULE API
-- ================================================================================================================
--
-- This file implements a timezone-aware API for generating recurrence rule occurrences.
-- Unlike the base API which works with TIMESTAMP WITH TIME ZONE and can drift across DST boundaries,
-- this API properly preserves wall-clock times during Daylight Saving Time transitions.
--
-- KEY DESIGN:
-- - Public API accepts TIMESTAMPTZ + optional timezone parameter
-- - Internally converts to naive TIMESTAMP in the target timezone
-- - Generates occurrences using naive timestamp arithmetic (preserves wall-clock time)
-- - Converts results back to TIMESTAMPTZ in the target timezone
--
-- DST HANDLING:
-- When adding "1 day" to a TIMESTAMP (naive), PostgreSQL adds calendar days, preserving wall-clock time.
-- When adding "1 day" to TIMESTAMPTZ, PostgreSQL adds 24 hours in UTC, causing drift across DST.
--
-- Example:
--   TIMESTAMP:    '2025-03-08 10:00:00' + '1 day' = '2025-03-09 10:00:00' ✓ Preserves 10 AM
--   TIMESTAMPTZ:  '2025-03-08 10:00 EST' + '1 day' = '2025-03-09 09:00 EDT' ✗ Drifts to 9 AM
--
-- TIMEZONE PRIORITY:
-- 1. Explicit timezone parameter
-- 2. TZID in RRULE string (e.g., "TZID=America/New_York;FREQ=DAILY")
-- 3. UTC fallback
--
-- ================================================================================================================


-- ================================================================================================================
-- INTERNAL FUNCTION: Timezone-aware event instance generation
-- ================================================================================================================
--
-- This is the core generation function that works with naive TIMESTAMP values to preserve wall-clock times.
-- It is almost identical to rrule_event_instances_range() but uses TIMESTAMP instead of TIMESTAMPTZ.
--
-- This function should NOT be called directly by users - use the public API functions below instead.
-- ================================================================================================================

CREATE OR REPLACE FUNCTION rrule.rrule_event_instances_range_tz(
    basedate TIMESTAMP,              -- Naive timestamp (wall-clock time in target timezone)
    repeatrule TEXT,                 -- RRULE string
    mindate TIMESTAMP,               -- Naive timestamp (range start)
    maxdate TIMESTAMP,               -- Naive timestamp (range end)
    max_count INT                    -- Maximum iterations
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
    prev_period_max_ts TIMESTAMP := NULL;
    omit_count INT;
    rule rrule.rrule_parts%ROWTYPE;
    skip_r rrule._skip_result;  -- Result from SKIP helper functions
BEGIN
    -- Parse the RRULE (note: basedate is converted to TIMESTAMPTZ for parsing, but only for date extraction)
    SELECT * INTO rule FROM rrule.parse_rrule_parts( basedate::TIMESTAMPTZ, repeatrule );

    -- Output cap: respect both API limit and RRULE COUNT
    output_limit := max_count;
    IF rule.count IS NOT NULL THEN
        output_limit := COALESCE(output_limit, rule.count);
        output_limit := LEAST(output_limit, rule.count);
    END IF;

    -- Security: Calculate safe period scan limit accounting for sparse BYxxx filters
    -- (e.g., FREQ=DAILY;BYDAY=MO only matches 1/7 days, requiring 20x headroom)
    -- See calculate_safe_iteration_limit() for detailed security rationale.
    period_limit := COALESCE(rrule.calculate_safe_iteration_limit(rule.freq, rule.count, output_limit, rule.interval), 1000);

    -- Remember dtstart day-of-month for SKIP drift prevention
    dtstart_day := date_part('day', basedate)::INT;

    current_base := basedate;

    -- Early exit: UNTIL before dtstart means no occurrences possible
    IF rule.until IS NOT NULL AND rule.until < basedate::TIMESTAMPTZ THEN
        RETURN;
    END IF;

    WHILE period_count < period_limit AND current_base < maxdate LOOP
        IF rule.freq = 'DAILY' THEN
            -- Call the existing daily_set but convert to/from TIMESTAMPTZ for compatibility
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
            -- KEY FIX: Adding interval to naive TIMESTAMP preserves wall-clock time
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
                -- Apply filters
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
              -- Note: Cast to TIMESTAMPTZ for helper, cast back to TIMESTAMP for storage
              current_base := rrule._restore_monthly_base(current_base::TIMESTAMPTZ, dtstart_day, (basedate::time)::interval)::TIMESTAMP;
              omit_count := 0;
              LOOP
                skip_r := rrule._advance_monthly(
                    current_base::TIMESTAMPTZ, basedate::TIMESTAMPTZ, dtstart_day, rule.interval, rule.skip,
                    rule.until, maxdate::TIMESTAMPTZ, period_limit, omit_count, period_count
                );
                current_base := skip_r.current_base::TIMESTAMP;
                omit_count := skip_r.omit_count;
                period_count := skip_r.period_count;
                -- Handle FORWARD emission (skip_r.forward_ts is non-NULL when SKIP=FORWARD produced a date)
                IF skip_r.forward_ts IS NOT NULL THEN
                  occurrence_count := occurrence_count + 1;
                  IF rule.count IS NOT NULL AND occurrence_count > rule.count THEN
                    EXIT;
                  END IF;
                  IF skip_r.forward_ts::TIMESTAMP >= mindate THEN
                    RETURN NEXT skip_r.forward_ts::TIMESTAMP;
                    emitted_count := emitted_count + 1;
                    EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
                  END IF;
                END IF;
                EXIT WHEN skip_r.done;
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
                         ELSE NULL END,
                    min_in_period::TIMESTAMPTZ) y
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
              -- Note: Cast to TIMESTAMPTZ for helper, cast back to TIMESTAMP for storage
              current_base := rrule._restore_yearly_base(current_base::TIMESTAMPTZ, basedate::TIMESTAMPTZ, dtstart_day, (basedate::time)::interval)::TIMESTAMP;
              omit_count := 0;
              LOOP
                skip_r := rrule._advance_yearly(
                    current_base::TIMESTAMPTZ, basedate::TIMESTAMPTZ, dtstart_day, rule.interval, rule.skip,
                    rule.until, maxdate::TIMESTAMPTZ, period_limit, omit_count, period_count
                );
                current_base := skip_r.current_base::TIMESTAMP;
                omit_count := skip_r.omit_count;
                period_count := skip_r.period_count;
                -- Handle FORWARD emission (skip_r.forward_ts is non-NULL when SKIP=FORWARD produced a date)
                IF skip_r.forward_ts IS NOT NULL THEN
                  occurrence_count := occurrence_count + 1;
                  IF rule.count IS NOT NULL AND occurrence_count > rule.count THEN
                    EXIT;
                  END IF;
                  IF skip_r.forward_ts::TIMESTAMP >= mindate THEN
                    RETURN NEXT skip_r.forward_ts::TIMESTAMP;
                    emitted_count := emitted_count + 1;
                    EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
                  END IF;
                END IF;
                EXIT WHEN skip_r.done;
              END LOOP;
            END IF;

        ELSE
            -- Provide helpful error message for sub-day frequencies
            IF rule.freq IN ('HOURLY', 'MINUTELY', 'SECONDLY') THEN
              RAISE EXCEPTION 'Frequency "%" is not supported in standard installation. Sub-day frequencies (HOURLY, MINUTELY, SECONDLY) are disabled by default for security. To enable them, use: psql -d your_database -f src/install_with_subday.sql (or SQL.installWithSubday for npm users). See INCLUDING_SUBDAY_OPERATIONS.md for security considerations.', rule.freq;
            ELSE
              RAISE EXCEPTION 'Unsupported frequency: %. Valid values are: DAILY, WEEKLY, MONTHLY, YEARLY. For sub-day frequencies, see INCLUDING_SUBDAY_OPERATIONS.md', rule.freq;
            END IF;
        END IF;
        period_count := period_count + 1;
        EXIT WHEN output_limit IS NOT NULL AND emitted_count >= output_limit;
        EXIT WHEN rule.count IS NOT NULL AND occurrence_count >= rule.count;
        EXIT WHEN rule.until IS NOT NULL AND current_base::TIMESTAMPTZ > rule.until;
    END LOOP;

    -- Warn if result set was truncated by API limit (not by rule's natural COUNT/UNTIL termination)
    IF output_limit IS NOT NULL AND emitted_count >= output_limit THEN
      IF (rule.count IS NULL OR occurrence_count < rule.count)
         AND (rule.until IS NULL) THEN
        RAISE WARNING 'rrule: result set truncated at % occurrences (limit: %). The recurrence rule has no COUNT or UNTIL and may produce more results beyond this limit.', emitted_count, output_limit;
      END IF;
    END IF;
END;
$$ LANGUAGE plpgsql VOLATILE SET search_path = rrule, pg_catalog;


-- ================================================================================================================
-- PUBLIC API: TIMESTAMPTZ API
--
-- These functions use set_config('TimeZone', ..., true) to expand in the target timezone.
-- The function-level SET timezone = 'UTC' clause sandboxes this — caller's session is unaffected.
-- See DECISIONS.md #1.
-- ================================================================================================================


-- ================================================================================================================
-- PUBLIC API: all() - Generate all occurrences (with limits)
-- ================================================================================================================
--
-- Returns all occurrences of the recurrence rule, properly handling DST transitions.
--
-- Parameters:
--   rrule_string - The RRULE string (e.g., 'FREQ=DAILY;COUNT=10')
--   dtstart      - The start datetime as TIMESTAMPTZ
--   timezone     - Optional timezone name (e.g., 'America/New_York'). If NULL, uses TZID from RRULE or UTC.
--
-- Timezone Priority:
--   1. Explicit timezone parameter
--   2. TZID in RRULE string
--   3. UTC fallback
--
-- Example:
--   SELECT "all"('FREQ=DAILY;COUNT=3', '2025-03-08 10:00:00-05', 'America/New_York');
--   Returns:
--     2025-03-08 10:00:00-05  (Saturday, EST)
--     2025-03-09 10:00:00-04  (Sunday, EDT - DST spring forward, wall-clock preserved!)
--     2025-03-10 10:00:00-04  (Monday, EDT)
--
-- ================================================================================================================

CREATE OR REPLACE FUNCTION rrule."all"(
    rrule_string TEXT,
    dtstart TIMESTAMPTZ,
    timezone TEXT DEFAULT NULL
) RETURNS SETOF TIMESTAMPTZ AS $$
DECLARE
    tz_name TEXT;
    wall_clock_start TIMESTAMP;
    wall_clock_end TIMESTAMP;
    naive_occurrence TIMESTAMP;
BEGIN
    -- Reject NULL RRULE early (STRICT on internal functions would silently return empty)
    IF rrule_string IS NULL THEN
        RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required. Specify one of: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, or YEARLY.  RFC 5545 Section 3.3.10: "FREQ rule part is REQUIRED"';
    END IF;

    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    -- Determine timezone (priority: explicit param > TZID in RRULE > UTC)
    tz_name := COALESCE(
        timezone,
        substring(rrule_string from 'TZID=([^;]+)(;|$)'),
        'UTC'
    );

    -- Validate timezone (using centralized validation helper)
    PERFORM rrule.validate_timezone(tz_name);

    -- Ensure deterministic wall-clock calculations in target timezone
    PERFORM set_config('TimeZone', tz_name, true);

    -- Convert TIMESTAMPTZ to wall-clock time in target timezone
    wall_clock_start := dtstart AT TIME ZONE tz_name;

    -- Calculate reasonable end date (10 years from start)
    wall_clock_end := wall_clock_start + INTERVAL '10 years';

    -- Generate occurrences as naive timestamps (preserves wall-clock time)
    FOR naive_occurrence IN
        SELECT * FROM rrule.rrule_event_instances_range_tz(
            wall_clock_start,
            rrule_string,
            wall_clock_start,
            wall_clock_end,
            1000  -- max_count limit
        )
    LOOP
        -- Convert naive timestamp back to TIMESTAMPTZ in target timezone
        RETURN NEXT (naive_occurrence AT TIME ZONE tz_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';


-- ================================================================================================================
-- PUBLIC API: between() - Generate occurrences within a date range
-- ================================================================================================================

CREATE OR REPLACE FUNCTION rrule."between"(
    rrule_string TEXT,
    dtstart TIMESTAMPTZ,
    range_start TIMESTAMPTZ,
    range_end TIMESTAMPTZ,
    timezone TEXT DEFAULT NULL,
    inc BOOLEAN DEFAULT FALSE
) RETURNS SETOF TIMESTAMPTZ AS $$
DECLARE
    tz_name TEXT;
    wall_clock_start TIMESTAMP;
    wall_clock_range_start TIMESTAMP;
    wall_clock_range_end TIMESTAMP;
    naive_occurrence TIMESTAMP;
BEGIN
    -- Reject NULL RRULE early (STRICT on internal functions would silently return empty)
    IF rrule_string IS NULL THEN
        RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required. Specify one of: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, or YEARLY.  RFC 5545 Section 3.3.10: "FREQ rule part is REQUIRED"';
    END IF;

    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    IF range_start IS NULL THEN
        RAISE EXCEPTION 'range_start is required and cannot be NULL';
    END IF;

    IF range_end IS NULL THEN
        RAISE EXCEPTION 'range_end is required and cannot be NULL';
    END IF;

    -- Determine timezone
    tz_name := COALESCE(
        timezone,
        substring(rrule_string from 'TZID=([^;]+)(;|$)'),
        'UTC'
    );

    -- Validate timezone (using centralized validation helper)
    PERFORM rrule.validate_timezone(tz_name);

    -- Ensure deterministic wall-clock calculations in target timezone
    PERFORM set_config('TimeZone', tz_name, true);

    -- Convert all timestamps to wall-clock time in target timezone
    wall_clock_start := dtstart AT TIME ZONE tz_name;
    wall_clock_range_start := range_start AT TIME ZONE tz_name;
    wall_clock_range_end := range_end AT TIME ZONE tz_name;
    -- Clamp range end to dtstart + 10 years (matching all()'s behavior) to prevent DoS on sparse rules
    wall_clock_range_end := LEAST(wall_clock_range_end, wall_clock_start + INTERVAL '10 years');

    -- Generate occurrences
    -- When inc=true, extend maxdate by 1 day so the range function generates the boundary period
    -- (the range function uses current_base < maxdate, which would otherwise exclude it)
    FOR naive_occurrence IN
        SELECT * FROM rrule.rrule_event_instances_range_tz(
            wall_clock_start,
            rrule_string,
            wall_clock_range_start,
            wall_clock_range_end + CASE WHEN inc THEN INTERVAL '1 day' ELSE INTERVAL '0' END,
            1000
        )
    LOOP
        IF inc THEN
            IF naive_occurrence < wall_clock_range_start OR naive_occurrence > wall_clock_range_end THEN
                CONTINUE;
            END IF;
        ELSE
            IF naive_occurrence <= wall_clock_range_start OR naive_occurrence >= wall_clock_range_end THEN
                CONTINUE;
            END IF;
        END IF;
        RETURN NEXT (naive_occurrence AT TIME ZONE tz_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';


-- ================================================================================================================
-- PUBLIC API: after() - Generate N occurrences after a date
-- ================================================================================================================

CREATE OR REPLACE FUNCTION rrule."after"(
    rrule_string TEXT,
    dtstart TIMESTAMPTZ,
    after_date TIMESTAMPTZ,
    count INT,
    timezone TEXT DEFAULT NULL,
    inc BOOLEAN DEFAULT FALSE
) RETURNS SETOF TIMESTAMPTZ AS $$
DECLARE
    tz_name TEXT;
    wall_clock_start TIMESTAMP;
    wall_clock_after TIMESTAMP;
    wall_clock_end TIMESTAMP;
    naive_occurrence TIMESTAMP;
    occurrence_count INT := 0;
BEGIN
    -- Reject NULL RRULE early (STRICT on internal functions would silently return empty)
    IF rrule_string IS NULL THEN
        RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required. Specify one of: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, or YEARLY.  RFC 5545 Section 3.3.10: "FREQ rule part is REQUIRED"';
    END IF;

    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    IF after_date IS NULL THEN
        RAISE EXCEPTION 'after_date is required and cannot be NULL';
    END IF;

    -- Determine timezone
    tz_name := COALESCE(
        timezone,
        substring(rrule_string from 'TZID=([^;]+)(;|$)'),
        'UTC'
    );

    -- Validate timezone (using centralized validation helper)
    PERFORM rrule.validate_timezone(tz_name);

    -- Validate count
    IF count IS NULL THEN
      RAISE EXCEPTION 'count parameter is required and cannot be NULL';
    END IF;
    IF count <= 0 THEN
      RETURN;
    END IF;
    -- Ensure deterministic wall-clock calculations in target timezone
    PERFORM set_config('TimeZone', tz_name, true);

    -- Convert to wall-clock time
    wall_clock_start := dtstart AT TIME ZONE tz_name;
    wall_clock_after := after_date AT TIME ZONE tz_name;
    wall_clock_end := GREATEST(wall_clock_start, wall_clock_after) + INTERVAL '10 years';

    -- Generate occurrences
    FOR naive_occurrence IN
        SELECT * FROM rrule.rrule_event_instances_range_tz(
            wall_clock_start,
            rrule_string,
            wall_clock_after,
            wall_clock_end,
            1000
        )
    LOOP
        IF inc THEN
            IF naive_occurrence < wall_clock_after THEN
                CONTINUE;
            END IF;
        ELSE
            IF naive_occurrence <= wall_clock_after THEN
                CONTINUE;
            END IF;
        END IF;
        RETURN NEXT (naive_occurrence AT TIME ZONE tz_name);
        occurrence_count := occurrence_count + 1;
        EXIT WHEN occurrence_count >= count;
    END LOOP;
END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';


-- ================================================================================================================
-- PUBLIC API: before() - Generate N occurrences before a date
-- ================================================================================================================

CREATE OR REPLACE FUNCTION rrule."before"(
    rrule_string TEXT,
    dtstart TIMESTAMPTZ,
    before_date TIMESTAMPTZ,
    count INT,
    timezone TEXT DEFAULT NULL,
    inc BOOLEAN DEFAULT FALSE
) RETURNS SETOF TIMESTAMPTZ AS $$
DECLARE
    tz_name TEXT;
    wall_clock_start TIMESTAMP;
    wall_clock_before TIMESTAMP;
    results TIMESTAMP[];
    scan_count BIGINT := 0;
    has_bound BOOLEAN;
BEGIN
    -- Reject NULL RRULE early (STRICT on internal functions would silently return empty)
    IF rrule_string IS NULL THEN
        RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required. Specify one of: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, or YEARLY.  RFC 5545 Section 3.3.10: "FREQ rule part is REQUIRED"';
    END IF;

    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    IF before_date IS NULL THEN
        RAISE EXCEPTION 'before_date is required and cannot be NULL';
    END IF;

    -- Determine timezone
    tz_name := COALESCE(
        timezone,
        substring(rrule_string from 'TZID=([^;]+)(;|$)'),
        'UTC'
    );

    -- Validate timezone (using centralized validation helper)
    PERFORM rrule.validate_timezone(tz_name);

    -- Check if the rule has a natural bound (COUNT or UNTIL)
    has_bound := (rrule_string ~* '(^|;)COUNT=' OR rrule_string ~* '(^|;)UNTIL=');

    -- Validate count
    IF count IS NULL THEN
      RAISE EXCEPTION 'count parameter is required and cannot be NULL';
    END IF;
    IF count <= 0 THEN
      RETURN;
    END IF;
    -- Ensure deterministic wall-clock calculations in target timezone
    PERFORM set_config('TimeZone', tz_name, true);

    -- Convert to wall-clock time
    wall_clock_start := dtstart AT TIME ZONE tz_name;
    wall_clock_before := before_date AT TIME ZONE tz_name;

    -- Generate all occurrences up to before_date, then select the last N using ORDER BY DESC LIMIT.
    -- This avoids O(N) array append/slice operations by letting PostgreSQL use an efficient top-N sort.
    -- When inc=true, extend maxdate by 1 day so the range function generates the boundary period.
    -- before() must scan all occurrences to find the last N, so we pass a large output_limit.
    -- Use 1000000 to limit iteration budget while being large enough for scanning within the maxdate window.

    -- Collect filtered occurrences into array for counting + selection
    SELECT array_agg(d ORDER BY d), COUNT(*)
    INTO results, scan_count
    FROM rrule.rrule_event_instances_range_tz(
        wall_clock_start,
        rrule_string,
        wall_clock_start,
        wall_clock_before + CASE WHEN inc THEN INTERVAL '1 day' ELSE INTERVAL '0' END,
        1000000
    ) AS d
    WHERE CASE
        WHEN inc THEN d <= wall_clock_before
        ELSE d < wall_clock_before
    END;

    -- Warn when before() scanned many occurrences on an unbounded rule,
    -- matching the safety warning that all() and between() emit at 1000.
    IF NOT has_bound AND scan_count > 1000 THEN
        RAISE WARNING 'rrule: before() scanned % occurrences to find the last match. The recurrence rule has no COUNT or UNTIL and produced many results. Consider adding bounds to the rule.', scan_count;
    END IF;

    -- Return the last N occurrences using ORDER BY DESC LIMIT for efficiency
    RETURN QUERY
        SELECT (sub.occ AT TIME ZONE tz_name)
        FROM (
            SELECT unnest AS occ
            FROM unnest(results)
            ORDER BY unnest DESC
            LIMIT count
        ) sub
        ORDER BY sub.occ ASC;
END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';


-- ================================================================================================================
-- PUBLIC API: count() - Count total occurrences (TIMESTAMPTZ version with timezone support)
-- ================================================================================================================

CREATE OR REPLACE FUNCTION rrule.count(
    rrule_string TEXT,
    dtstart TIMESTAMPTZ,
    timezone TEXT DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    occurrence_count INTEGER;
BEGIN
    IF rrule_string IS NULL THEN
        RAISE EXCEPTION 'Invalid RRULE: FREQ parameter is required. Specify one of: SECONDLY, MINUTELY, HOURLY, DAILY, WEEKLY, MONTHLY, or YEARLY.  RFC 5545 Section 3.3.10: "FREQ rule part is REQUIRED"';
    END IF;

    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    -- Leverage the all() function which handles timezone resolution
    SELECT COUNT(*)::INTEGER INTO occurrence_count
    FROM rrule."all"(rrule_string, dtstart, timezone);

    RETURN occurrence_count;
END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';


-- ================================================================================================================
-- PUBLIC API: next() - Get next occurrence from NOW or reference_time (TIMESTAMPTZ version with timezone support)
-- ================================================================================================================

CREATE OR REPLACE FUNCTION rrule.next(
    rrule_string TEXT,
    dtstart TIMESTAMPTZ,
    timezone TEXT DEFAULT NULL,
    reference_time TIMESTAMPTZ DEFAULT NULL
) RETURNS TIMESTAMPTZ AS $$
DECLARE
    tz_name TEXT;
BEGIN
    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    -- Determine timezone (priority: explicit param > TZID in RRULE > UTC)
    tz_name := COALESCE(
        timezone,
        substring(rrule_string from 'TZID=([^;]+)(;|$)'),
        'UTC'
    );

    -- Validate timezone (using centralized validation helper)
    PERFORM rrule.validate_timezone(tz_name);

    -- Ensure deterministic wall-clock calculations in target timezone
    PERFORM set_config('TimeZone', tz_name, true);

    -- Use after() to find the next occurrence
    RETURN (
        SELECT * FROM rrule."after"(rrule_string, dtstart, COALESCE(reference_time, NOW()), 1, timezone)
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';


-- ================================================================================================================
-- PUBLIC API: most_recent() - Get most recent occurrence before NOW or reference_time (TIMESTAMPTZ version with timezone support)
-- ================================================================================================================

CREATE OR REPLACE FUNCTION rrule.most_recent(
    rrule_string TEXT,
    dtstart TIMESTAMPTZ,
    timezone TEXT DEFAULT NULL,
    reference_time TIMESTAMPTZ DEFAULT NULL
) RETURNS TIMESTAMPTZ AS $$
DECLARE
    tz_name TEXT;
BEGIN
    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    -- Determine timezone (priority: explicit param > TZID in RRULE > UTC)
    tz_name := COALESCE(
        timezone,
        substring(rrule_string from 'TZID=([^;]+)(;|$)'),
        'UTC'
    );

    -- Validate timezone (using centralized validation helper)
    PERFORM rrule.validate_timezone(tz_name);

    -- Ensure deterministic wall-clock calculations in target timezone
    PERFORM set_config('TimeZone', tz_name, true);

    -- Use before() to find the most recent occurrence
    RETURN (
        SELECT * FROM rrule."before"(rrule_string, dtstart, COALESCE(reference_time, NOW()), 1, timezone)
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';


-- ================================================================================================================
-- PUBLIC API: overlaps() - Check if recurring event overlaps date range (add timezone support)
-- ================================================================================================================

CREATE OR REPLACE FUNCTION rrule.overlaps(
    dtstart TIMESTAMPTZ,
    dtend TIMESTAMPTZ,
    rrule_string TEXT,
    mindate TIMESTAMPTZ,
    maxdate TIMESTAMPTZ,
    timezone TEXT DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    tz_name TEXT;
    base_date TIMESTAMPTZ;
    duration INTERVAL;
    adjusted_maxdate TIMESTAMPTZ;
    adjusted_mindate TIMESTAMPTZ;
BEGIN
    -- Handle NULL dtstart
    IF dtstart IS NULL THEN
        RAISE EXCEPTION 'dtstart is required and cannot be NULL';
    END IF;

    -- Determine timezone (priority: explicit param > TZID in RRULE > session timezone)
    tz_name := COALESCE(
        timezone,
        substring(rrule_string from 'TZID=([^;]+)(;|$)'),
        'UTC'
    );

    -- Validate timezone (using centralized validation helper)
    PERFORM rrule.validate_timezone(tz_name);

    -- Ensure deterministic wall-clock calculations in target timezone
    PERFORM set_config('TimeZone', tz_name, true);

    -- Determine base date (end time if available, otherwise start time)
    base_date := dtstart;
    duration := COALESCE(dtend, dtstart) - dtstart;

    -- Adjust date range to account for event duration
    adjusted_mindate := COALESCE(mindate, dtstart - INTERVAL '10 years');
    adjusted_maxdate := COALESCE(maxdate, dtstart + INTERVAL '10 years');

    -- If no RRULE, check single event overlap using original (non-duration-expanded) bounds.
    -- Duration expansion is only needed for recurring events (to catch occurrences starting before the window).
    IF rrule_string IS NULL THEN
        RETURN (dtstart < adjusted_maxdate AND (dtstart + duration) >= adjusted_mindate);
    END IF;

    -- Expand search window to account for event duration (recurring events only)
    IF duration > INTERVAL '0' THEN
        adjusted_mindate := adjusted_mindate - duration;
    END IF;

    -- Use generator directly with LIMIT 1 for streaming efficiency (avoids materializing between())
    PERFORM d
    FROM rrule.rrule_event_instances_range_tz(
        (base_date AT TIME ZONE tz_name)::TIMESTAMP,
        rrule_string,
        (adjusted_mindate AT TIME ZONE tz_name)::TIMESTAMP,
        (adjusted_maxdate AT TIME ZONE tz_name)::TIMESTAMP,
        1000
    ) d
    LIMIT 1;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql VOLATILE SET timezone = 'UTC';


------------------------------------------------------------------------------------------------------
-- VERSION TRACKING
------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "version"()
RETURNS TEXT AS $$
    SELECT '1.1.1'::TEXT;
$$ LANGUAGE SQL IMMUTABLE;
