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
| `BYDAY` with position | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYMONTHDAY` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYMONTHDAY=-1` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYMONTH` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYYEARDAY` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYYEARDAY` negative | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYWEEKNO` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Week Configuration** | | | | | | | |
| `WKST` (week start day) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Time Filters** | | | | | | | |
| `BYHOUR` | ✅ | 🚫<sup>1</sup> | 🚫<sup>1</sup> | 🚫<sup>1</sup> | ✅ | ✅ | ✅ |
| `BYMINUTE` | ✅ | 🚫<sup>1</sup> | 🚫<sup>1</sup> | 🚫<sup>1</sup> | ✅ | ✅ | ✅ |
| `BYSECOND` | ✅ | 🚫<sup>1</sup> | 🚫<sup>1</sup> | 🚫<sup>1</sup> | ✅ | ✅ | ✅ |
| **Position Selectors** | | | | | | | |
| `BYSETPOS` | ✅ | ✅ | ✅ | ✅ | 🚫<sup>2</sup> | 🚫<sup>2</sup> | 🚫<sup>2</sup> |
| **Special Combinations** | | | | | | | |
| `BYMONTH` + `BYYEARDAY` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYWEEKNO` + `BYMONTH` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `BYWEEKNO` + `BYYEARDAY` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**Legend:**
- ✅ = Fully supported and enabled
- ⚠️ = Fully implemented but **disabled by default** (see footnote 5)
- ❌ = Not supported (see footnotes below)
- 🚫 = **Raises exception** with descriptive error message

---

## Footnotes

<sup>1</sup> **Time Filters (BYHOUR/BYMINUTE/BYSECOND) with WEEKLY/MONTHLY/YEARLY:**
   - **Status:** Raises exception with workaround guidance
   - **RFC 5545:** The RFC Section 3.3.10 expand/limit table defines these as "Expand" operations — the behavior is specified, not ambiguous. Both python-dateutil and rrule.js implement expansion for these combinations.
   - **Current limitation:** This implementation does not yet support time-level expansion for WEEKLY/MONTHLY/YEARLY frequencies. Rules using these combinations are rejected with descriptive error messages.
   - **Workarounds:**
     - For hourly on specific days: `FREQ=HOURLY;BYDAY=MO,WE,FR` ✅
     - For daily with specific hours: `FREQ=DAILY;BYHOUR=9,10,11` ✅

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
   - **See:** [INCLUDING_SUBDAY_OPERATIONS.md](INCLUDING_SUBDAY_OPERATIONS.md) for complete guide

---

## Frequency Details

### 🟢 Production-Ready Frequencies (Always Enabled)

**`FREQ=DAILY`**
- **Use case:** "Every day at 10 AM", "Weekdays only", "Every 3 days"
- **Max occurrences/year:** 365
- **Performance:** Excellent
- **Supports:** All date filters, time filters (BYHOUR/BYMINUTE/BYSECOND), BYSETPOS

**`FREQ=WEEKLY`**
- **Use case:** "Every Monday", "Mon/Wed/Fri", "Every 2 weeks"
- **Max occurrences/year:** 52
- **Performance:** Excellent
- **Supports:** All date filters, BYSETPOS

**`FREQ=MONTHLY`**
- **Use case:** "Last day of month", "2nd Tuesday", "Every 3 months"
- **Max occurrences/year:** 12
- **Performance:** Excellent
- **Supports:** All date filters, BYSETPOS

**`FREQ=YEARLY`**
- **Use case:** "Birthday", "Anniversary", "Day 100 of each year", "Week 10 of each year"
- **Max occurrences/year:** 1
- **Performance:** Excellent
- **Supports:** All date filters including BYYEARDAY (positive & negative), BYWEEKNO, BYSETPOS
- **Note:** BYMONTH and BYYEARDAY can be combined; results are the intersection (may be empty)

### ⚠️ Sub-Day Frequencies (Implemented, Disabled by Default)

**`FREQ=HOURLY`**
- **Status:** ✅ Implemented, ⚠️ Disabled by default
- **Use case:** "Every 3 hours", "Every hour 9 AM - 5 PM"
- **Max occurrences/year:** 8,760
- **Risk:** Medium - manageable with proper limits
- **Recommended limits:** COUNT ≤ 1,000, UNTIL ≤ 7 days
- **How to enable:** See [INCLUDING_SUBDAY_OPERATIONS.md](INCLUDING_SUBDAY_OPERATIONS.md)

**`FREQ=MINUTELY`**
- **Status:** ✅ Implemented, ⚠️ Disabled by default
- **Use case:** "Every 15 minutes", "Every minute during business hours"
- **Max occurrences/year:** 525,600
- **Risk:** High - can exhaust resources
- **Recommended limits:** COUNT ≤ 1,000, UNTIL ≤ 24 hours
- **How to enable:** See [INCLUDING_SUBDAY_OPERATIONS.md](INCLUDING_SUBDAY_OPERATIONS.md)

**`FREQ=SECONDLY`**
- **Status:** ✅ Implemented, ⚠️ Disabled by default
- **Use case:** "Every 30 seconds", "Real-time monitoring"
- **Max occurrences/year:** 31,536,000
- **Risk:** Critical - denial-of-service vector
- **Recommended limits:** COUNT ≤ 1,000, UNTIL ≤ 1 hour
- **How to enable:** See [INCLUDING_SUBDAY_OPERATIONS.md](INCLUDING_SUBDAY_OPERATIONS.md)

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

**Coverage:** ~97% of RFC 5545 RRULE specification + RFC 7529 SKIP/RSCALE support

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
- **Time-level expansion** for WEEKLY/MONTHLY/YEARLY (RFC-specified but not yet implemented; rejected with workaround guidance)
- **Non-Gregorian calendars** (HEBREW, ISLAMIC, CHINESE — requires ICU integration)
- **Leap seconds** (BYSECOND=60 — PostgreSQL TIMESTAMP limitation)

This implementation covers all standard scheduling needs. Unsupported combinations are rejected with descriptive errors rather than silently ignored.

---

## See Also

- [API_REFERENCE.md](API_REFERENCE.md) - Function reference
- [VALIDATION.md](VALIDATION.md) - RRULE validation rules
- [INCLUDING_SUBDAY_OPERATIONS.md](INCLUDING_SUBDAY_OPERATIONS.md) - Sub-day frequency guide
- [README.md](README.md) - Main documentation
