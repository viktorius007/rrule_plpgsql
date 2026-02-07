# API Reference

Complete function reference for rrule_plpgsql.

---

## Namespacing & Usage

All functions live in the `rrule` PostgreSQL schema for namespace isolation and conflict prevention.

**Two usage patterns:**

1. **Schema-qualified (recommended for production):**
   ```sql
   SELECT * FROM rrule."all"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);
   ```

2. **With search_path (convenient for development):**
   ```sql
   SET search_path = rrule, public;
   SELECT * FROM "all"('FREQ=DAILY;COUNT=5', '2025-01-01 10:00:00'::TIMESTAMP);
   ```

**Benefits of schema-based namespace:**
- ✅ No conflicts with user-defined functions
- ✅ Clean reinstallation with dependency safety
- ✅ Professional PostgreSQL convention (like `pg_catalog`, `information_schema`)
- ✅ Standard names inside schema match rrule.js/python-dateutil

---

## Standard API (rrule.js/python-dateutil compatible)

### `rrule."all"(rrule, dtstart) -> SETOF TIMESTAMP`

Returns all occurrences matching the RRULE (streaming via SETOF for memory efficiency).

**Matches:** rrule.js `.all()` and python-dateutil iteration

**Parameters:**
- `rrule`: `VARCHAR` - RRULE string (e.g., `'FREQ=DAILY;COUNT=10'`)
- `dtstart`: `TIMESTAMP` - Start date/time (wall-clock time)

**Returns:** `SETOF TIMESTAMP` - Streamed occurrences (memory-efficient)

**Limits:**
- Up to 1,000 occurrences
- Up to 10 years from dtstart

**Examples:**
```sql
-- Schema-qualified (recommended)
SELECT * FROM rrule."all"(
    'FREQ=DAILY;COUNT=5',
    '2025-01-01 10:00:00'::TIMESTAMP
);

-- With search_path
SET search_path = rrule, public;
SELECT * FROM "all"(
    'FREQ=DAILY;COUNT=5',
    '2025-01-01 10:00:00'::TIMESTAMP
);

-- With TZID (timezone support)
SELECT * FROM rrule."all"(
    'FREQ=DAILY;COUNT=5;TZID=America/New_York',
    '2025-03-08 10:00:00'::TIMESTAMP
);
-- Result: 10 AM EST, 10 AM EST, 10 AM EDT (after DST)... stays at 10 AM wall-clock time
```

---

### `rrule."between"(rrule, dtstart, start_date, end_date, inc DEFAULT false) -> SETOF TIMESTAMP`

Returns occurrences between two dates (streaming via SETOF).

**Matches:** rrule.js `.between()` and python-dateutil `.between()`

**Parameters:**
- `rrule`: `VARCHAR` - RRULE string
- `dtstart`: `TIMESTAMP` - Start date/time
- `start_date`: `TIMESTAMP` - Range start
- `end_date`: `TIMESTAMP` - Range end
- `inc`: `BOOLEAN` - Include boundaries when true (default: false)

**Returns:** `SETOF TIMESTAMP` - Occurrences in range

**Limits:**
- Up to 1,000 occurrences
- Search range is clamped to `dtstart + INTERVAL '10 years'`

**Example:**
```sql
SELECT * FROM rrule."between"(
    'FREQ=DAILY;INTERVAL=1',
    '2025-01-01 10:00:00'::TIMESTAMP,
    '2025-01-01'::TIMESTAMP,
    '2025-01-10'::TIMESTAMP
);
```

---

### `rrule."after"(rrule, dtstart, after_date, inc DEFAULT false) -> TIMESTAMP`

Returns the first occurrence after a specific date.

**Matches:** python-dateutil `.after()`

**Parameters:**
- `rrule`: `VARCHAR` - RRULE string
- `dtstart`: `TIMESTAMP` - Start date/time
- `after_date`: `TIMESTAMP` - Find occurrence after this date
- `inc`: `BOOLEAN` - Include boundary when true (default: false)

**Returns:** `TIMESTAMP` - Next occurrence, or `NULL` if none

**Search behavior:**
- Uses a lookahead window of `GREATEST(dtstart, after_date) + INTERVAL '50 years'`
- Uses adaptive internal search budget (`1000..10000`) for far-future lookups

**Example:**
```sql
SELECT rrule."after"(
    'FREQ=WEEKLY;BYDAY=MO,WE,FR',
    '2025-01-01 10:00:00'::TIMESTAMP,
    '2025-06-01'::TIMESTAMP
) AS next_occurrence;
-- Returns: 2025-06-02 10:00:00 (next Monday)
```

---

### `rrule."before"(rrule, dtstart, before_date, inc DEFAULT false) -> TIMESTAMP`

Returns the last occurrence before a specific date.

**Matches:** python-dateutil `.before()`

**Parameters:**
- `rrule`: `VARCHAR` - RRULE string
- `dtstart`: `TIMESTAMP` - Start date/time
- `before_date`: `TIMESTAMP` - Find occurrence before this date
- `inc`: `BOOLEAN` - Include boundary when true (default: false)

**Returns:** `TIMESTAMP` - Previous occurrence, or `NULL` if none

**Search behavior:**
- Scans occurrences up to `before_date` (or inclusive boundary when `inc=true`)
- For unbounded rules (no `COUNT` and no `UNTIL`), emits a warning when large scans are required

**Example:**
```sql
SELECT rrule."before"(
    'FREQ=MONTHLY;BYMONTHDAY=15',
    '2025-01-15 10:00:00'::TIMESTAMP,
    '2025-07-01'::TIMESTAMP
) AS last_occurrence;
-- Returns: 2025-06-15 10:00:00 (last 15th before July)
```

---

### `rrule."count"(rrule, dtstart) -> INTEGER`

Returns the total number of occurrences.

**Matches:** python-dateutil `.count()`

**Parameters:**
- `rrule`: `VARCHAR` - RRULE string
- `dtstart`: `TIMESTAMP` - Start date/time

**Returns:** `INTEGER` - Total occurrence count

**Limit behavior:** `count()` delegates to `rrule."all"()` and inherits its 1,000-occurrence / 10-year cap.

**Example:**
```sql
SELECT rrule."count"(
    'FREQ=DAILY;COUNT=10',
    '2025-01-01 10:00:00'::TIMESTAMP
) AS total;
-- Returns: 10
```

---

## TIMESTAMPTZ API

These functions accept `TIMESTAMPTZ` (timestamp with timezone) and properly handle Daylight Saving Time (DST) transitions by preserving wall-clock times.

**Key Difference from TIMESTAMP API:**
- TIMESTAMP API: Uses `TIMESTAMP` type with timezone specified via `TZID=` in RRULE string (also DST-aware)
- TIMESTAMPTZ API: Uses `TIMESTAMPTZ` type with timezone specified via explicit function parameter (can override TZID)
- Both APIs preserve wall-clock time across DST boundaries

**DST Handling Example:**
```sql
-- Daily meeting at 10 AM across DST spring-forward (March 9, 2025)
SELECT * FROM rrule."all"(
    'FREQ=DAILY;COUNT=3',
    '2025-03-08 10:00:00-05'::TIMESTAMPTZ,  -- 10 AM EST
    'America/New_York'
);

-- Results (wall-clock time stays at 10 AM):
--   2025-03-08 10:00:00-05  (Saturday, EST)
--   2025-03-09 10:00:00-04  (Sunday, EDT - DST spring forward!)
--   2025-03-10 10:00:00-04  (Monday, EDT)
```

### `rrule."all"(rrule, dtstart, timezone) -> SETOF TIMESTAMPTZ`

Returns all occurrences matching the RRULE with proper DST handling.

**Parameters:**
- `rrule`: `TEXT` - RRULE string (e.g., `'FREQ=DAILY;COUNT=10'`)
- `dtstart`: `TIMESTAMPTZ` - Start date/time with timezone
- `timezone`: `TEXT` (optional) - Timezone name (e.g., `'America/New_York'`). If NULL, uses TZID from RRULE or UTC.

**Timezone Priority:**
1. Explicit `timezone` parameter
2. `TZID` in RRULE string (e.g., `'TZID=America/New_York;FREQ=DAILY'`)
3. UTC fallback

**Returns:** `SETOF TIMESTAMPTZ` - Streamed occurrences with timezone

**Limits:**
- Up to 1,000 occurrences
- Up to 10 years from `dtstart` (in target wall-clock timezone)

**Examples:**
```sql
-- Explicit timezone parameter (highest priority)
SELECT * FROM rrule."all"(
    'FREQ=DAILY;COUNT=5',
    '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
    'America/New_York'
);

-- TZID in RRULE string
SELECT * FROM rrule."all"(
    'TZID=America/Los_Angeles;FREQ=DAILY;COUNT=5',
    '2025-03-08 10:00:00-08'::TIMESTAMPTZ,
    NULL  -- Will use TZID from RRULE
);

-- UTC fallback
SELECT * FROM rrule."all"(
    'FREQ=DAILY;COUNT=5',
    '2025-03-08 10:00:00+00'::TIMESTAMPTZ,
    NULL  -- No timezone specified, uses UTC
);
```

---

### `rrule."between"(rrule, dtstart, start_date, end_date, timezone, inc DEFAULT false) -> SETOF TIMESTAMPTZ`

Returns occurrences between two dates with DST handling.

**Parameters:**
- `rrule`: `TEXT` - RRULE string
- `dtstart`: `TIMESTAMPTZ` - Start date/time
- `start_date`: `TIMESTAMPTZ` - Range start
- `end_date`: `TIMESTAMPTZ` - Range end
- `timezone`: `TEXT` (optional) - Timezone name
- `inc`: `BOOLEAN` - Include boundaries when true (default: false)

**Limits:**
- Up to 1,000 occurrences
- Search range is clamped to `dtstart + INTERVAL '10 years'` (in target wall-clock timezone)

**Example:**
```sql
SELECT * FROM rrule."between"(
    'FREQ=DAILY',
    '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
    '2025-03-09 00:00:00-04'::TIMESTAMPTZ,
    '2025-03-11 00:00:00-04'::TIMESTAMPTZ,
    'America/New_York'
);
-- Returns only occurrences on March 9-10 (across DST boundary)
```

---

### `rrule."after"(rrule, dtstart, after_date, count, timezone, inc DEFAULT false) -> SETOF TIMESTAMPTZ`

> **API Difference:** The TIMESTAMPTZ `after()` differs from the TIMESTAMP version: it accepts a `count INT` parameter and returns `SETOF TIMESTAMPTZ` (multiple results), whereas the TIMESTAMP version returns a single `TIMESTAMP`. The same applies to `before()` below.

Returns N occurrences after a specific date with DST handling.

**Parameters:**
- `rrule`: `TEXT` - RRULE string
- `dtstart`: `TIMESTAMPTZ` - Start date/time
- `after_date`: `TIMESTAMPTZ` - Find occurrences after this date
- `count`: `INT` - Number of occurrences to return
- `timezone`: `TEXT` (optional) - Timezone name
- `inc`: `BOOLEAN` - Include boundary when true (default: false)

**Search behavior:**
- Uses a lookahead window of `GREATEST(dtstart, after_date) + INTERVAL '50 years'` (in target wall-clock timezone)
- Uses adaptive internal search budget (`1000..10000`) for far-future lookups

**Example:**
```sql
SELECT * FROM rrule."after"(
    'FREQ=DAILY;COUNT=100',
    '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
    '2025-03-09 00:00:00-04'::TIMESTAMPTZ,
    3,  -- Get 3 occurrences
    'America/New_York'
);
-- Returns March 9, 10, 11 (preserving 10 AM wall-clock time)
```

---

### `rrule."before"(rrule, dtstart, before_date, count, timezone, inc DEFAULT false) -> SETOF TIMESTAMPTZ`

Returns N occurrences before a specific date with DST handling.

**Parameters:**
- `rrule`: `TEXT` - RRULE string
- `dtstart`: `TIMESTAMPTZ` - Start date/time
- `before_date`: `TIMESTAMPTZ` - Find occurrences before this date
- `count`: `INT` - Number of occurrences to return
- `timezone`: `TEXT` (optional) - Timezone name
- `inc`: `BOOLEAN` - Include boundary when true (default: false)

**Search behavior:**
- Scans occurrences up to `before_date` (or inclusive boundary when `inc=true`) and returns the last `count`
- For unbounded rules (no `COUNT` and no `UNTIL`), emits a warning when large scans are required

**Example:**
```sql
SELECT * FROM rrule."before"(
    'FREQ=DAILY;COUNT=100',
    '2025-03-08 10:00:00-05'::TIMESTAMPTZ,
    '2025-03-10 00:00:00-04'::TIMESTAMPTZ,
    2,  -- Get last 2 occurrences before March 10
    'America/New_York'
);
-- Returns March 8 (EST) and March 9 (EDT)
```

---

### `rrule."count"(rrule, dtstart, timezone DEFAULT NULL) -> INTEGER`

Returns the total number of occurrences using the TIMESTAMPTZ API.

**Parameters:**
- `rrule`: `TEXT` - RRULE string
- `dtstart`: `TIMESTAMPTZ` - Start date/time
- `timezone`: `TEXT` (optional) - Timezone name

**Returns:** `INTEGER` - Total occurrence count

**Limit behavior:** Delegates to TIMESTAMPTZ `rrule."all"()` and inherits its 1,000-occurrence / 10-year cap.

---

### `rrule.next(rrule, dtstart, timezone DEFAULT NULL, reference_time DEFAULT NULL) -> TIMESTAMPTZ`

Returns the next occurrence from `reference_time` (or `NOW()` when NULL), preserving wall-clock semantics.

**Parameters:**
- `rrule`: `TEXT` - RRULE string
- `dtstart`: `TIMESTAMPTZ` - Start date/time
- `timezone`: `TEXT` (optional) - Timezone override
- `reference_time`: `TIMESTAMPTZ` (optional) - Reference timestamp

---

### `rrule.most_recent(rrule, dtstart, timezone DEFAULT NULL, reference_time DEFAULT NULL) -> TIMESTAMPTZ`

Returns the most recent occurrence before `reference_time` (or `NOW()` when NULL), preserving wall-clock semantics.

**Parameters:**
- `rrule`: `TEXT` - RRULE string
- `dtstart`: `TIMESTAMPTZ` - Start date/time
- `timezone`: `TEXT` (optional) - Timezone override
- `reference_time`: `TIMESTAMPTZ` (optional) - Reference timestamp

---

## Convenience Methods

### `rrule."next"(rrule, dtstart, reference_time DEFAULT NULL) -> TIMESTAMP`

Get the next occurrence from NOW (current timestamp) or a provided reference timestamp.

**Common use case:** "When does this event occur next?"

**Parameters:**
- `rrule`: `VARCHAR` - RRULE string
- `dtstart`: `TIMESTAMP` - Start date/time
- `reference_time`: `TIMESTAMP` (optional) - Reference time. Defaults to `NOW()::TIMESTAMP` when NULL.

**Returns:** `TIMESTAMP` - Next occurrence from `reference_time` (or NOW when NULL)

**Example:**
```sql
SELECT rrule."next"(
    'FREQ=WEEKLY;BYDAY=MO',
    '2025-01-01 10:00:00'::TIMESTAMP
) AS next_monday;
```

**Note:** Equivalent to `rrule."after"(rrule, dtstart, COALESCE(reference_time, NOW()::TIMESTAMP), inc DEFAULT false)`

---

### `rrule."most_recent"(rrule, dtstart, reference_time DEFAULT NULL) -> TIMESTAMP`

Get the most recent occurrence before NOW or a provided reference timestamp.

**Common use case:** "When did this event last occur?"

**Parameters:**
- `rrule`: `VARCHAR` - RRULE string
- `dtstart`: `TIMESTAMP` - Start date/time
- `reference_time`: `TIMESTAMP` (optional) - Reference time. Defaults to `NOW()::TIMESTAMP` when NULL.

**Returns:** `TIMESTAMP` - Most recent occurrence before `reference_time` (or NOW when NULL)

**Example:**
```sql
SELECT rrule."most_recent"(
    'FREQ=DAILY;COUNT=100',
    '2025-01-01 10:00:00'::TIMESTAMP
) AS last_occurrence;
```

**Note:** Equivalent to `rrule."before"(rrule, dtstart, COALESCE(reference_time, NOW()::TIMESTAMP), inc DEFAULT false)`

---

## Array Output

The SETOF functions are memory-efficient (streaming), but sometimes you need materialized arrays. Use PostgreSQL's `array_agg()` aggregate function with the SETOF functions:

### Converting SETOF to Arrays

**Pattern:** Wrap SETOF functions with `array_agg(... ORDER BY ...)` and alias with `AS occurrence` for deterministic output ordering.

**Examples:**
```sql
-- Get array of all occurrences
SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(
    'FREQ=DAILY;COUNT=5',
    '2025-01-01 10:00:00'::TIMESTAMP
) AS occurrence;
-- Returns: {"2025-01-01 10:00:00", "2025-01-02 10:00:00", ...}

-- Get array of occurrences in range
SELECT array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(
    'FREQ=DAILY;INTERVAL=1',
    '2025-01-01 10:00:00'::TIMESTAMP,
    '2025-01-01'::TIMESTAMP,
    '2025-01-05'::TIMESTAMP
) AS occurrence;

-- Use with unnest for iteration
SELECT unnest(array_agg(occurrence ORDER BY occurrence)) AS occurrence FROM rrule."all"(
    'FREQ=DAILY;COUNT=5',
    '2025-01-01 10:00:00'::TIMESTAMP
) AS occurrence;
```

**Note:** For simple iteration, you can use the SETOF functions directly without `array_agg()`:
```sql
-- Direct iteration (more efficient)
SELECT * FROM rrule."all"(
    'FREQ=DAILY;COUNT=5',
    '2025-01-01 10:00:00'::TIMESTAMP
);
```

---

## Advanced Functions

### `rrule."overlaps"(dtstart, dtend, rrule, mindate, maxdate, timezone DEFAULT NULL) -> BOOLEAN`

Check if a recurring event has ANY occurrences overlapping a date range. Optimized to stop at first match.

**Use case:** Calendar conflict detection

**Parameters:**
- `dtstart`: `TIMESTAMPTZ` - Event start
- `dtend`: `TIMESTAMPTZ` - Event end
- `rrule`: `TEXT` - RRULE string (can be NULL for single events)
- `mindate`: `TIMESTAMPTZ` - Range start
- `maxdate`: `TIMESTAMPTZ` - Range end
- `timezone`: `TEXT` (optional) - Timezone name. If NULL, uses TZID from RRULE or UTC.

**Returns:** `BOOLEAN` - True if any overlap found

**Behavior notes:**
- Stops at first matching occurrence (`LIMIT 1`).
- If `mindate` or `maxdate` are NULL, defaults to `dtstart ± INTERVAL '10 years'`.
- Uses adaptive internal search budget (`1000..10000`) for far-future windows.
- If `rrule` is NULL, performs single-event overlap check using `dtstart`/`dtend`.

**Example:**
```sql
-- Does this meeting conflict with vacation dates?
SELECT rrule."overlaps"(
    '2025-01-01 09:00:00+00'::TIMESTAMPTZ,
    '2025-01-01 10:00:00+00'::TIMESTAMPTZ,
    'FREQ=WEEKLY;BYDAY=MO,WE,FR',
    '2025-06-01 00:00:00+00'::TIMESTAMPTZ,
    '2025-06-30 23:59:59+00'::TIMESTAMPTZ,
    NULL  -- Uses UTC or TZID from RRULE
) AS has_conflict;

-- With explicit timezone
SELECT rrule."overlaps"(
    '2025-01-01 09:00:00-05'::TIMESTAMPTZ,
    '2025-01-01 10:00:00-05'::TIMESTAMPTZ,
    'FREQ=WEEKLY;BYDAY=MO,WE,FR',
    '2025-06-01 00:00:00-04'::TIMESTAMPTZ,
    '2025-06-30 23:59:59-04'::TIMESTAMPTZ,
    'America/New_York'
) AS has_conflict;
```

---

## Standard API Compatibility

Our API aligns with de facto standards from popular RRULE libraries:

| Function | rrule.js | python-dateutil | Our Implementation |
|----------|----------|-----------------|-------------------|
| Get all occurrences | `.all()` | `list(rule)` | `rrule."all"(rrule, dtstart)` returns SETOF |
| Get all as array | `.all()` | `list(rule)` | `array_agg(occurrence ORDER BY occurrence) FROM rrule."all"(...) AS occurrence` |
| Get in range | `.between(s,e)` | `.between(s,e)` | `rrule."between"(rrule, dtstart, start, end, inc DEFAULT false)` returns SETOF |
| Get range as array | `.between(s,e)` | `.between(s,e)` | `array_agg(occurrence ORDER BY occurrence) FROM rrule."between"(...) AS occurrence` |
| After specific date | `.after(date)` | `.after(date)` | `rrule."after"(rrule, dtstart, date, inc DEFAULT false)` |
| Before specific date | `.before(date)` | `.before(date)` | `rrule."before"(rrule, dtstart, date, inc DEFAULT false)` |
| **Next from now** | `.after(new Date())` | `.after(now())` | `rrule."next"(rrule, dtstart, reference_time DEFAULT NULL)` ⭐ |
| **Most recent** | `.before(new Date())` | `.before(now())` | `rrule."most_recent"(rrule, dtstart, reference_time DEFAULT NULL)` ⭐ |
| Count | - | - | `rrule."count"(rrule, dtstart)` |

⭐ = Convenience functions that simplify common use cases (not in standard libraries)

---

## Required Parameter Validation

Public API functions explicitly validate required parameters and raise exceptions for NULL inputs.

**Examples:**
```sql
-- Raises: Invalid RRULE: FREQ parameter is required.
SELECT rrule."all"(NULL, '2025-01-01 10:00:00'::TIMESTAMP);

-- Raises: dtstart is required and cannot be NULL
SELECT rrule."all"('FREQ=DAILY;COUNT=5', NULL);

-- Raises: after_date is required and cannot be NULL
SELECT rrule."after"('FREQ=DAILY', '2025-01-01 10:00:00'::TIMESTAMP, NULL);
```

**Optional NULLs:**
- `timezone` is optional in TIMESTAMPTZ APIs (falls back to `TZID` in RRULE, then `UTC`).
- `rrule` may be NULL only for `rrule."overlaps"` single-event checks.

---

## See Also

- [SPEC_COMPLIANCE.md](SPEC_COMPLIANCE.md) - RFC 5545/7529 feature support
- [VALIDATION.md](VALIDATION.md) - RRULE validation rules
- [README.md](../README.md) - Main documentation
