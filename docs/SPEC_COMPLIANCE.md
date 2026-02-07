# RFC 5545 & RFC 7529 Compliance

Complete feature support matrix and compliance details for rrule_plpgsql.

---

## RFC 5545 Support Matrix

### Comprehensive Feature Support Grid

| Feature | DAILY | WEEKLY | MONTHLY | YEARLY | ⚠️ HOURLY<sup>3</sup> | ⚠️ MINUTELY<sup>3</sup> | ⚠️ SECONDLY<sup>3</sup> |
|---------|-------|--------|---------|--------|----------|------------|------------|
| **Core Modifiers** | | | | | | | |
| `COUNT` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `UNTIL` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `INTERVAL` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Date Filters** | | | | | | | |
| `BYDAY` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYDAY` with ordinal (2MO) | 🚫<sup>4</sup> | 🚫<sup>4</sup> | ✅ | ✅ | 🚫<sup>4</sup> | 🚫<sup>4</sup> | 🚫<sup>4</sup> |
| `BYMONTHDAY` | ✅ | 🚫<sup>5</sup> | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYMONTHDAY=-1` | ✅ | 🚫<sup>5</sup> | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYMONTH` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYYEARDAY` | 🚫<sup>6</sup> | 🚫<sup>6</sup> | 🚫<sup>6</sup> | ✅ | ✅ | ✅ | ✅ |
| `BYYEARDAY` negative | 🚫<sup>6</sup> | 🚫<sup>6</sup> | 🚫<sup>6</sup> | ✅ | ✅ | ✅ | ✅ |
| `BYWEEKNO` | 🚫<sup>7</sup> | 🚫<sup>7</sup> | 🚫<sup>7</sup> | ✅ | 🚫<sup>7</sup> | 🚫<sup>7</sup> | 🚫<sup>7</sup> |
| **Week Configuration** | | | | | | | |
| `WKST` (week start day) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Time Filters** | | | | | | | |
| `BYHOUR` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYMINUTE` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYSECOND` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Position Selectors** | | | | | | | |
| `BYSETPOS` | ✅ | ✅ | ✅ | ✅ | 🚫<sup>2</sup> | 🚫<sup>2</sup> | 🚫<sup>2</sup> |
| **Special Combinations** | | | | | | | |
| `BYMONTH` + `BYYEARDAY` | 🚫<sup>6</sup> | 🚫<sup>6</sup> | 🚫<sup>6</sup> | ✅ | ✅ | ✅ | ✅ |
| `BYWEEKNO` + `BYMONTH` | 🚫<sup>7</sup> | 🚫<sup>7</sup> | 🚫<sup>7</sup> | ✅ | 🚫<sup>7</sup> | 🚫<sup>7</sup> | 🚫<sup>7</sup> |
| `BYWEEKNO` + `BYYEARDAY` | 🚫<sup>7</sup> | 🚫<sup>7</sup> | 🚫<sup>7</sup> | ✅ | 🚫<sup>7</sup> | 🚫<sup>7</sup> | 🚫<sup>7</sup> |

**Legend:**
- ✅ = Fully supported and enabled
- ⚠️ = Fully implemented but **disabled by default** (see footnote 3)
- ❌ = Not supported (see footnotes below)
- 🚫 = **Raises exception** with descriptive error message

---

## Footnotes

<sup>1</sup> **Time Filters (BYHOUR/BYMINUTE/BYSECOND) with all frequencies:**
   - **Status:** ✅ Fully supported
   - **RFC 5545:** Section 3.3.10 defines these as "Expand" operations for WEEKLY/MONTHLY/YEARLY frequencies
   - **Behavior:** Time filters expand each date candidate with the specified time slots
   - **Example:** `FREQ=WEEKLY;BYDAY=MO,WE,FR;BYHOUR=9,17` generates 6 occurrences per week (3 days × 2 times)
   - **BYSETPOS interaction:** Applied after time expansion (e.g., BYSETPOS=-1 selects the last time slot)

<sup>2</sup> **BYSETPOS with HOURLY/MINUTELY/SECONDLY:**
   - **Status:** Raises exception with guidance
   - **Why not supported?** These frequencies are already position-based
   - **What BYSETPOS does:** Selects positions within a generated set (e.g., "2nd Monday of month")
   - **Why not needed:** With `FREQ=HOURLY`, each hour is atomic - there's no "set" to select from
   - **What to use instead:** Use INTERVAL
     - Want every 3rd hour? Use `FREQ=HOURLY;INTERVAL=3` ✅
     - Want every 15 minutes? Use `FREQ=MINUTELY;INTERVAL=15` ✅
   - **Technical note:** Sub-day frequencies generate single occurrences, not sets

<sup>3</sup> **⚠️ Sub-Day Frequencies (HOURLY/MINUTELY/SECONDLY) - Disabled by Default:**
   - **Status:** ✅ Fully implemented and tested, ⚠️ but disabled by default for security
   - **Why?** Can generate millions of occurrences (SECONDLY: 31M/year), posing DoS risk in multi-tenant environments
   - **When safe to enable:** Single-tenant deployments with application-level validation and query timeouts
   - **See:** [SUBDAY_OPERATIONS.md](SUBDAY_OPERATIONS.md) for complete guide

<sup>4</sup> **BYDAY with Ordinal (2MO, -1FR) Restrictions:**
   - **Status:** Raises exception for non-MONTHLY/YEARLY frequencies
   - **RFC 5545:** Section 3.3.10 states "BYDAY MUST NOT be specified with a numeric value when the FREQ rule part is not set to MONTHLY or YEARLY"
   - **Why?** Ordinals like "2nd Monday" or "last Friday" are only meaningful within a month or year context
   - **Valid usage:** `FREQ=MONTHLY;BYDAY=2MO` ✅ or `FREQ=YEARLY;BYMONTH=11;BYDAY=4TH` ✅
   - **Invalid usage:** `FREQ=DAILY;BYDAY=2MO` 🚫 or `FREQ=WEEKLY;BYDAY=-1FR` 🚫

<sup>5</sup> **BYMONTHDAY with WEEKLY Frequency:**
   - **Status:** Raises exception
   - **RFC 5545:** Section 3.3.10 states "BYMONTHDAY MUST NOT be specified when the FREQ rule part is set to WEEKLY"
   - **Why?** Day-of-month filters are not applicable to weekly recurrence patterns
   - **Workaround:** Use `FREQ=DAILY;BYMONTHDAY=15` or `FREQ=MONTHLY;BYMONTHDAY=15` instead

<sup>6</sup> **BYYEARDAY with DAILY/WEEKLY/MONTHLY Frequencies:**
   - **Status:** Raises exception
   - **RFC 5545:** Section 3.3.10 states "BYYEARDAY MUST NOT be specified when the FREQ rule part is set to DAILY, WEEKLY, or MONTHLY"
   - **Why?** Year-day filters are only meaningful with YEARLY frequency (or sub-day frequencies where they act as a filter)
   - **Valid usage:** `FREQ=YEARLY;BYYEARDAY=100` ✅ (day 100 of each year)
   - **Invalid usage:** `FREQ=DAILY;BYYEARDAY=100` 🚫

<sup>7</sup> **BYWEEKNO Restrictions:**
   - **Status:** Raises exception for non-YEARLY frequencies
   - **RFC 5545:** Section 3.3.10 states "BYWEEKNO MUST NOT be specified when the FREQ rule part is set to anything other than YEARLY"
   - **Why?** ISO week numbers are only meaningful in the context of a year
   - **Valid usage:** `FREQ=YEARLY;BYWEEKNO=10;BYDAY=MO` ✅ (Monday of week 10 each year)
   - **Invalid usage:** `FREQ=MONTHLY;BYWEEKNO=10` 🚫

---

## Frequency Details

### 🟢 Production-Ready Frequencies (Always Enabled)

**`FREQ=DAILY`**
- **Use case:** "Every day at 10 AM", "Weekdays only", "Every 3 days"
- **Max occurrences/year:** 365
- **Performance:** Excellent
- **Supports:** BYDAY, BYMONTH, BYMONTHDAY, BYHOUR/BYMINUTE/BYSECOND, BYSETPOS
- **Not supported:** BYDAY ordinals (2MO), BYYEARDAY, BYWEEKNO

**`FREQ=WEEKLY`**
- **Use case:** "Every Monday", "Mon/Wed/Fri", "Every 2 weeks", "MWF at 9am and 5pm"
- **Max occurrences/year:** 52 (more with time expansion)
- **Performance:** Excellent
- **Supports:** BYDAY, BYMONTH, BYSETPOS, WKST, BYHOUR/BYMINUTE/BYSECOND
- **Not supported:** BYDAY ordinals, BYMONTHDAY, BYYEARDAY, BYWEEKNO

**`FREQ=MONTHLY`**
- **Use case:** "Last day of month", "2nd Tuesday", "Every 3 months", "1st and 15th at 9am and 5pm"
- **Max occurrences/year:** 12 (more with time expansion)
- **Performance:** Excellent
- **Supports:** BYDAY (with ordinals), BYMONTH, BYMONTHDAY, BYSETPOS, BYHOUR/BYMINUTE/BYSECOND
- **Not supported:** BYYEARDAY, BYWEEKNO

**`FREQ=YEARLY`**
- **Use case:** "Birthday", "Anniversary", "Day 100 of each year", "Week 10 of each year", "June and December at 10am and 2pm"
- **Max occurrences/year:** 1 (base), expandable with BYMONTH/BYDAY/time filters
- **Performance:** Excellent
- **Supports:** BYDAY (with ordinals), BYMONTH, BYMONTHDAY, BYYEARDAY, BYWEEKNO, BYSETPOS, BYHOUR/BYMINUTE/BYSECOND
- **Note:** BYMONTH and BYYEARDAY can be combined; results are the intersection (may be empty)
- **Note:** BYDAY ordinals cannot be used when BYWEEKNO is specified (RFC 5545 prohibition)

### ⚠️ Sub-Day Frequencies (Implemented, Disabled by Default)

**`FREQ=HOURLY`**
- **Status:** ✅ Implemented, ⚠️ Disabled by default
- **Use case:** "Every 3 hours", "Every hour 9 AM - 5 PM"
- **Max occurrences/year:** 8,760
- **Risk:** Medium - manageable with proper limits
- **Recommended limits:** COUNT ≤ 1,000, UNTIL ≤ 7 days
- **Supports:** BYDAY, BYMONTH, BYMONTHDAY, BYYEARDAY, BYHOUR/BYMINUTE/BYSECOND
- **Not supported:** BYDAY ordinals, BYWEEKNO, BYSETPOS
- **How to enable:** See [SUBDAY_OPERATIONS.md](SUBDAY_OPERATIONS.md)

**`FREQ=MINUTELY`**
- **Status:** ✅ Implemented, ⚠️ Disabled by default
- **Use case:** "Every 15 minutes", "Every minute during business hours"
- **Max occurrences/year:** 525,600
- **Risk:** High - can exhaust resources
- **Recommended limits:** COUNT ≤ 1,000, UNTIL ≤ 24 hours
- **Supports:** BYDAY, BYMONTH, BYMONTHDAY, BYYEARDAY, BYHOUR/BYMINUTE/BYSECOND
- **Not supported:** BYDAY ordinals, BYWEEKNO, BYSETPOS
- **How to enable:** See [SUBDAY_OPERATIONS.md](SUBDAY_OPERATIONS.md)

**`FREQ=SECONDLY`**
- **Status:** ✅ Implemented, ⚠️ Disabled by default
- **Use case:** "Every 30 seconds", "Real-time monitoring"
- **Max occurrences/year:** 31,536,000
- **Risk:** Critical - denial-of-service vector
- **Recommended limits:** COUNT ≤ 1,000, UNTIL ≤ 1 hour
- **Supports:** BYDAY, BYMONTH, BYMONTHDAY, BYYEARDAY, BYHOUR/BYMINUTE/BYSECOND
- **Not supported:** BYDAY ordinals, BYWEEKNO, BYSETPOS
- **How to enable:** See [SUBDAY_OPERATIONS.md](SUBDAY_OPERATIONS.md)

---

## Special Feature Notes

### Month-End Handling (RFC 7529 SKIP parameter)

- `SKIP=OMIT` (default): Skip invalid dates (e.g., Feb 31 → skip Feb entirely)
- `SKIP=BACKWARD`: Use last valid day (e.g., Feb 31 → Feb 28/29)
- `SKIP=FORWARD`: Use first of next month (e.g., Feb 31 → Mar 1)
- `BYMONTHDAY=-1` always works: Last day of every month (handles 28, 29, 30, 31)
- **RFC 7529 Compliance:** When using SKIP (other than OMIT), RSCALE=GREGORIAN is automatically added for RFC compliance
- Explicit RFC-compliant format: `RSCALE=GREGORIAN;SKIP=BACKWARD`

### Leap Year Support

- `BYYEARDAY=366` only generates in leap years (2024, 2028, etc.)
- `BYYEARDAY=-1` always generates (Dec 31)
- Negative BYYEARDAY indices work correctly in both leap and non-leap years

### BYMONTH + BYYEARDAY Intersections

- Supported for YEARLY rules; both filters are applied as an intersection
- If the intersection is empty (e.g., BYMONTH=2 with BYYEARDAY=100), that year yields no occurrences

### ISO Week Numbering (BYWEEKNO)

- Week 1 is the week containing January 4th (ISO 8601)
- `WKST` defines the week start day used for week boundaries

### Sub-Day Scheduling

- `BYHOUR`, `BYMINUTE`, `BYSECOND` work with DAILY frequency
- Generates all combinations: `BYHOUR=9,10,11;BYMINUTE=0,30` → 6 times per day
- `BYSETPOS` can select specific positions: `BYSETPOS=1,-1` → first and last time

---

## Common Use Cases

```sql
-- Every weekday at 10 AM
FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR

-- 2nd Tuesday of each month
FREQ=MONTHLY;BYDAY=2TU

-- Last day of each month at 11:59 PM
FREQ=MONTHLY;BYMONTHDAY=-1

-- Every Monday, Wednesday, Friday
FREQ=WEEKLY;BYDAY=MO,WE,FR

-- Day 100 of each year (April 9/10)
FREQ=YEARLY;BYYEARDAY=100

-- Last day of each year
FREQ=YEARLY;BYYEARDAY=-1

-- Once per year during week 10
FREQ=YEARLY;BYWEEKNO=10

-- Once per year during week 10 in March (combined filters)
FREQ=YEARLY;BYWEEKNO=10;BYMONTH=3

-- Daily at 9 AM, 12 PM, and 5 PM
FREQ=DAILY;BYHOUR=9,12,17

-- Daily, first and last hour only (with BYSETPOS)
FREQ=DAILY;BYHOUR=9,10,11,12,13,14,15,16,17;BYSETPOS=1,-1

-- Every 3 hours (requires HOURLY to be enabled)
-- FREQ=HOURLY;INTERVAL=3
```

---

## RFC 5545 & RFC 7529 Compliance Summary

**Coverage:** ~99% of RFC 5545 RRULE specification + RFC 7529 SKIP/RSCALE support (effectively complete for Gregorian calendars)

### RFC 5545 Supported Features

- ✅ All standard frequencies (DAILY, WEEKLY, MONTHLY, YEARLY)
- ✅ All sub-day frequencies (HOURLY, MINUTELY, SECONDLY) - implemented, disabled by default
- ✅ All date/time modifiers
- ✅ Complex combinations (BYDAY + BYMONTHDAY + BYSETPOS)
- ✅ Negative indices for month-end/year-end handling
- ✅ Leap year edge cases
- ✅ **TZID (Timezone) support** - Full RFC 5545 timezone support with automatic DST handling

### RFC 7529 Supported Features

- ✅ **SKIP parameter** (OMIT, BACKWARD, FORWARD) - Handles invalid dates in recurrence rules
- ✅ **RSCALE parameter** - Calendar system specification (GREGORIAN supported)
- ✅ **Auto-compliance** - Automatically adds RSCALE=GREGORIAN when SKIP is used (RFC 7529 requirement)
- ⚠️ **Non-Gregorian calendars** - Not yet supported (HEBREW, ISLAMIC, CHINESE, etc.)
  - Leap month syntax (e.g., "5L") is also not supported as it only applies to non-Gregorian calendars

---

## Operational Safety Limits

These are implementation safeguards (not RFC requirements):

- `rrule."all"` and `rrule."between"` cap output at 1,000 occurrences.
- `rrule."all"` and `rrule."between"` cap search horizon at 10 years from `dtstart`.
- `rrule."after"` uses a 50-year lookahead window from `GREATEST(dtstart, after_date)` and adaptive search budget (`1000..10000`) for far-future lookups.
- `rrule."overlaps"` defaults null bounds to `dtstart ± 10 years` and uses adaptive search budget (`1000..10000`).
- `rrule."count"` delegates to `rrule."all"` and inherits its caps.

These bounds prevent unbounded scans on infinite or sparse recurrence rules.

---

## Not Supported (Will Raise Exception)

### ❌ BYMONTHDAY with WEEKLY Frequency

- BYMONTHDAY cannot be used with FREQ=WEEKLY per RFC 5545
- *Why:* Day-of-month filters are not applicable to weekly recurrence patterns
- *Error:* Attempting this will raise: `Invalid RRULE: BYMONTHDAY cannot be used with FREQ=WEEKLY`
- *Valid alternatives:*
  - ✅ `FREQ=DAILY;BYDAY=MO,WE,FR` (specific weekdays)
  - ✅ `FREQ=WEEKLY;BYDAY=MO,WE,FR` (without BYMONTHDAY)
  - ✅ `FREQ=MONTHLY;BYMONTHDAY=15` (15th of every month)

### ❌ BYDAY with Ordinals when BYWEEKNO is Specified in YEARLY

- Ordinals like "2MO" (2nd Monday) cannot be used with BYWEEKNO in YEARLY rules
- *Why:* RFC 5545 explicitly prohibits this combination as semantically ambiguous
- *Example invalid:* `FREQ=YEARLY;BYWEEKNO=10;BYDAY=2MO`
- *Error:* Attempting this will raise: `Invalid RRULE: BYDAY with ordinal cannot be used when FREQ=YEARLY and BYWEEKNO is specified`
- *Valid alternatives:*
  - ✅ `FREQ=YEARLY;BYWEEKNO=10;BYDAY=MO` (without ordinal - all Mondays in week 10)
  - ✅ `FREQ=YEARLY;BYMONTH=3;BYDAY=2MO` (2nd Monday in March, without BYWEEKNO)
  - ✅ `FREQ=MONTHLY;BYDAY=2MO` (2nd Monday of every month)

---

## WKST (Week Start Day) Support

✅ **Fully supported!**

- *What:* Defines which day starts the week (SU, MO, TU, WE, TH, FR, SA)
- *Default:* Monday (MO) - RFC 5545 default
- *Use cases:*
  - US calendars: `WKST=SU` (week starts Sunday)
  - ISO 8601: `WKST=MO` (week starts Monday - default)
  - Custom schedules: Any day of week
- *Affects:* Week numbering for BYWEEKNO, week boundaries for WEEKLY;INTERVAL, BYDAY week calculations
- *Examples:*
  - `FREQ=WEEKLY;WKST=SU` - Weekly occurrences with Sunday week start
  - `FREQ=WEEKLY;INTERVAL=2;WKST=SU` - Biweekly with Sunday-Saturday weeks
  - `FREQ=YEARLY;BYWEEKNO=1;WKST=SU` - First week of year (Sunday-based)

---

## Why Not 100%?

The remaining gaps are:
- **Non-Gregorian calendars** (HEBREW, ISLAMIC, CHINESE — requires ICU integration, intentionally not implemented)
- **Leap seconds** (BYSECOND=60 — PostgreSQL TIMESTAMP limitation)

This implementation covers all standard scheduling needs. Unsupported combinations are rejected with descriptive errors rather than silently ignored.

---

## See Also

- [API_REFERENCE.md](API_REFERENCE.md) - Function reference
- [VALIDATION.md](VALIDATION.md) - RRULE validation rules
- [SUBDAY_OPERATIONS.md](SUBDAY_OPERATIONS.md) - Sub-day frequency guide
- [README.md](../README.md) - Main documentation
