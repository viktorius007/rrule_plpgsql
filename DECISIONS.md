# Design Decisions

Prescriptive patterns for this codebase. Each entry states what to do, why, and where it was verified.

---

## 1. Pin timezone with SET clause, not session state

Use `SET timezone = 'UTC'` on function definitions for the TIMESTAMP API. Use `set_config('TimeZone', tz, true)` inside TIMESTAMPTZ API functions to expand in the target timezone.

The function-level SET clause restores the caller's timezone on exit. The `set_config(..., true)` call (SET LOCAL) is sandboxed by the SET clause and does not leak into the caller's session.

This avoids non-deterministic recurrence expansion when different sessions have different timezone settings.

**Consequence:** Functions with SET or `set_config` must be marked VOLATILE. See decision #2.

**Verified:**
- [PostgreSQL CREATE FUNCTION — SET clause](https://www.postgresql.org/docs/current/sql-createfunction.html): "the specified configuration parameter is set when the function is entered, and restored to its prior value when the function exits"
- [PostgreSQL CREATE FUNCTION — SET LOCAL interaction](https://www.postgresql.org/docs/current/sql-createfunction.html): "effects of a SET LOCAL command executed inside the function for the same variable are restricted to the function"

---

## 2. Use correct volatility: VOLATILE, STABLE, or IMMUTABLE

Use VOLATILE for functions that use cursors (BYSETPOS), SET timezone, or `set_config`. Use STABLE for internal functions that read database state or call other STABLE/VOLATILE functions. Use IMMUTABLE only for pure-computation helpers that take scalar/array inputs and return deterministic results with no side effects, no timezone dependency, and no calls to STABLE/VOLATILE functions.

IMMUTABLE is incorrect for any function that depends on timezone settings, calls STABLE/VOLATILE functions, or uses cursor state. Mislabeling as IMMUTABLE lets the planner constant-fold the function at plan time, returning stale results.

**Exception:** Pure-computation functions like `weekday_to_number`, `byweekno_matches`, and `calculate_safe_iteration_limit` are correctly marked IMMUTABLE — they are deterministic mappings with no external dependencies.

In practice, VOLATILE vs STABLE has negligible performance impact for this library: rrule arguments typically come from table columns (per-row evaluation regardless), and set-returning functions are called once in FROM clauses.

**Verified:**
- [PostgreSQL Function Volatility Categories](https://www.postgresql.org/docs/current/xfunc-volatility.html): "IMMUTABLE allows the optimizer to pre-evaluate the function when a query calls it with constant arguments"
- [PostgreSQL Function Volatility Categories](https://www.postgresql.org/docs/current/xfunc-volatility.html): "A VOLATILE function... re-evaluate the function at every row"
- [AWS — Volatility Classification](https://aws.amazon.com/blogs/database/volatility-classification-in-postgresql/): "IMMUTABLE PostgreSQL functions must not invoke non-IMMUTABLE functions"

---

## 3. Default `inc` to FALSE on boundary queries

`between`, `after`, and `before` accept `inc BOOLEAN DEFAULT FALSE`. When TRUE, boundary dates are included in results. Default FALSE means exclusive boundaries.

This matches the default behavior of both reference implementations. Changing the default to TRUE would silently alter query results for existing callers.

**Verified:**
- [rrule.js README](https://github.com/jakubroztocil/rrule): `rule.between(after, before, inc=false)`
- [python-dateutil rrule](https://dateutil.readthedocs.io/en/stable/rrule.html): `rruleset.between(after, before, inc=False)`

---

## 4. Require UNTIL as UTC DATE-TIME with Z suffix

Reject date-only UNTIL (e.g., `UNTIL=20251231`) and non-UTC UNTIL (e.g., `UNTIL=20251231T235959`). Only accept `UNTIL=20251231T235959Z`.

This API uses DATE-TIME DTSTART. RFC 5545 requires UNTIL to match the DTSTART value type. When DTSTART is DATE-TIME with timezone, UNTIL must be UTC.

Accepting date-only UNTIL creates ambiguity (end of which day, in which timezone?) that the RFC explicitly avoids.

**Verified:**
- [RFC 5545 Section 3.3.10](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10): "the UNTIL rule part MUST be specified as a date with UTC time" (when DTSTART is DATE-TIME)
- [iCalendar.org — Recurrence Rule](https://icalendar.org/iCalendar-RFC-5545/3-3-10-recurrence-rule.html)

---

## 5. Allow BYMONTH + BYYEARDAY together (intersection)

When both BYMONTH and BYYEARDAY are present with FREQ=YEARLY, one generates the candidate set and the other filters it. The result is their intersection.

If the intersection is empty (e.g., `BYMONTH=2;BYYEARDAY=100` — day 100 is in April, not February), that year yields no occurrences. This is correct behavior, not an error.

**Verified:**
- [RFC 5545 Section 3.3.10 expand/limit table](https://icalendar.org/iCalendar-RFC-5545/3-3-10-recurrence-rule.html): both BYMONTH and BYYEARDAY have "Expand" behavior with YEARLY
- [RFC 5545 Section 3.3.10](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10): "BYxxx rule parts are applied to the current set of evaluated occurrences in the following order: BYMONTH, BYWEEKNO, BYYEARDAY..."

---

## 6. Normalize BYSECOND=60 to 59

Accept BYSECOND=60 (leap second) and silently normalize to 59. PostgreSQL TIMESTAMP cannot represent second 60.

RFC 5545 allows BYSECOND=60. Rejecting it would break valid RRULE strings. Normalizing matches the pragmatic behavior documented in SPEC_COMPLIANCE.md.

**Verified:**
- [RFC 5545 Section 3.3.10](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10): BYSECOND range is 0-60
- [PostgreSQL Date/Time Types](https://www.postgresql.org/docs/current/datatype-datetime.html): seconds field range 0-59

---

## 7. Apply YEARLY BYDAY ordinals across the whole year

When FREQ=YEARLY with BYDAY ordinals (e.g., `2MO` = second Monday) and no BYMONTH or BYWEEKNO, compute the ordinal across the entire year, not within the DTSTART month.

Scoping ordinals to the DTSTART month would produce different results depending on when the rule started, violating the RFC's frequency-level semantics.

**Verified:**
- [RFC 5545 Section 3.3.10](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10): BYDAY with YEARLY expands across the year (Note 2 in expand/limit table)
- [rrule.js](https://github.com/jakubroztocil/rrule): `FREQ=YEARLY;BYDAY=20MO` returns 20th Monday of the year

---

## 8. Use ISO 8601 week numbering for BYWEEKNO

Week 1 is the week containing January 4th. WKST sets the week start day (default MO).

Some BYWEEKNO rules yield no occurrences in certain years. This is expected ISO behavior, not a bug.

**Verified:**
- [RFC 5545 Section 3.3.10](https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10): BYWEEKNO aligns with ISO 8601 week definition
- [ISO 8601 Week Date](https://en.wikipedia.org/wiki/ISO_week_date): "the week containing the year's first Thursday"

---

## 9. Anchor recurrence on DTSTART, use DTEND only for duration

Recurrence expansion always starts from DTSTART. DTEND is only used by `overlaps()` to compute event duration for conflict detection.

Anchoring on DTEND would shift the recurrence pattern relative to the event start, producing incorrect overlap results.

**Verified:**
- [RFC 5545 Section 3.8.5.3](https://datatracker.ietf.org/doc/html/rfc5545#section-3.8.5.3): "The recurrence rule... is relative to the DTSTART"

---

## 10. Use LATERAL joins for SETOF results, scalar subqueries for single values

Use `FROM rrule."all"(...) AS occurrence` or `CROSS JOIN LATERAL` for multi-row results. Use `(SELECT ... FROM rrule."after"(...) LIMIT 1)` for single values. Never call set-returning functions directly in `UPDATE ... SET`.

PostgreSQL does not allow (or behaves unexpectedly with) set-returning functions in UPDATE target expressions. LATERAL joins make the row-multiplying behavior explicit.

**Verified:**
- [PostgreSQL SRF in SELECT](https://www.postgresql.org/docs/current/xfunc-sql.html#XFUNC-SQL-FUNCTIONS-RETURNING-SET): set-returning functions in SELECT can cause implicit cross-joins
- Documented in EXAMPLE_USAGE.md and API_REFERENCE.md with working examples

---

## 11. Fail safe on schema reinstall

`DROP SCHEMA rrule CASCADE` only when no external dependencies (views, indexes, foreign keys) reference rrule functions. Otherwise fail with a migration guide pointing to [MIGRATION.md](docs/MIGRATION.md).

This prevents silent deletion of production objects that depend on rrule functions.

---

## 12. Schema-qualify all function calls in tests

Tests use `rrule."all"(...)`, never unqualified `"all"(...)`, and reset `search_path` to `public`. This catches regressions where schema qualification is accidentally omitted from function bodies.

---

## 13. `overlaps()` is TIMESTAMPTZ-only (no TIMESTAMP variant)

All other public API functions (`all`, `between`, `after`, `before`, `next`, `most_recent`, `count`) have both TIMESTAMP and TIMESTAMPTZ overloads. `overlaps()` intentionally has only a TIMESTAMPTZ variant.

**Why no TIMESTAMP variant:**
- `overlaps()` was designed directly in the TIMESTAMPTZ API. Its parameter shape `(dtstart, dtend, rrule, mindate, maxdate, timezone)` doesn't map cleanly to the TIMESTAMP API convention.
- `overlaps()` returns BOOLEAN, not dates — so the TIMESTAMP vs TIMESTAMPTZ distinction doesn't affect downstream consumption.
- PostgreSQL implicitly casts TIMESTAMP → TIMESTAMPTZ, so passing TIMESTAMP values works without errors.
- Adding a TIMESTAMP variant would increase maintenance surface across all 4 generators for negligible benefit.

**Edge case:** If a developer mixes the TIMESTAMP API (for `all()`, `between()`, etc.) with auto-cast TIMESTAMP→TIMESTAMPTZ for `overlaps()`, and the session timezone ≠ UTC, the implicit cast uses session timezone rather than UTC. This is unlikely in practice for anyone following the documentation.

**See also:** [POTENTIAL_ISSUES.md (archived)](docs/archived/POTENTIAL_ISSUES.md) — assessed and closed as "Design Decision".
