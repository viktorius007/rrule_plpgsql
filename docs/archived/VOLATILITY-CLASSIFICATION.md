# PostgreSQL Volatility Classification: Research & Codebase Analysis

## How Volatility Classification Works

PostgreSQL classifies every function into one of three categories, each giving the query planner different optimization permissions:

| Category | Promise to Planner | Planner Can... |
|----------|-------------------|----------------|
| **IMMUTABLE** | Same inputs → same output *forever* | Pre-evaluate at plan time with constant args; cache results; use in index expressions |
| **STABLE** | Same inputs → same output *within one statement* | Collapse multiple calls to one per statement; use in index scan conditions |
| **VOLATILE** (default) | No guarantees | Nothing — must re-evaluate at every row |

The key optimization leverage points:
1. **IMMUTABLE** functions with constant arguments get folded into constants at *planning time* — they run once, not once-per-row
2. **IMMUTABLE** functions can be used in expression indexes (`CREATE INDEX ... ON t (my_immutable_func(col))`)
3. **STABLE** functions can be used in index scan WHERE clauses (evaluated once, then used for index lookup)
4. **VOLATILE** functions force sequential scans and per-row evaluation

## Can Big Functions Be Decomposed?

Yes, this is a valid optimization pattern. The idea: if a large VOLATILE function contains a pure-computation section, extract that section into an IMMUTABLE helper. The planner can then optimize calls to the helper independently.

**However**, the benefit depends entirely on *how the function is called*:
- If called with **constant arguments** in a query → IMMUTABLE enables plan-time folding (big win)
- If called with **column references** → must evaluate per-row regardless of volatility
- If called in a **FROM clause** (set-returning) → called once regardless

## This Codebase's Current State

The codebase has **40 functions** across all three categories:

| Category | Count | Examples |
|----------|-------|---------|
| IMMUTABLE | 3 | `weekday_to_number`, `byweekno_matches`, `calculate_safe_iteration_limit` |
| STABLE | ~15 | `parse_rrule_parts`, `test_byday_rule`, `get_week_start`, filter functions |
| VOLATILE | ~22 | All public API functions, frequency set functions, BYSETPOS filter |

**Why most functions are VOLATILE:** The public API functions use `SET timezone = 'UTC'` (which forces VOLATILE). The frequency set functions (`daily_set`, `weekly_set`, etc.) use cursors for BYSETPOS handling (also forces VOLATILE).

**Why helper functions are STABLE, not IMMUTABLE:** Functions like `test_byday_rule(TIMESTAMPTZ, TEXT[])` use `date_part('dow', timestamptz_value)`. Extracting the day-of-week from a `TIMESTAMPTZ` depends on the *session timezone* — the same absolute instant yields different weekdays in different timezones. PostgreSQL's docs explicitly say timezone-dependent functions must not be IMMUTABLE. So STABLE is the correct classification even though these are "pure computation" — their output depends on session state.

## What Could Theoretically Be Improved

### 1. The TIMESTAMP Overload Strategy (Biggest Opportunity)

If filter functions had `TIMESTAMP` (naive, no timezone) overloads, those overloads could be IMMUTABLE:

```sql
-- Current: STABLE because date_part('dow', TIMESTAMPTZ) depends on session timezone
CREATE FUNCTION test_byday_rule(testme TIMESTAMPTZ, byday TEXT[]) RETURNS BOOLEAN
  LANGUAGE plpgsql STABLE;

-- Hypothetical: IMMUTABLE because date_part('dow', TIMESTAMP) is deterministic
CREATE FUNCTION test_byday_rule(testme TIMESTAMP, byday TEXT[]) RETURNS BOOLEAN
  LANGUAGE plpgsql IMMUTABLE;
```

This could cascade through: `test_byday_rule`, `test_bymonth_rule`, `test_bymonthday_rule`, `test_byyearday_rule`, `get_week_start`, `get_week_info`, `weeks_in_year`, `get_week_number`, `byweekno_matches_for_year` — potentially **9 functions** moving from STABLE to IMMUTABLE.

**But:** The callers (`rrule_event_instances_range` and the freq set functions) are already VOLATILE due to `SET timezone` and cursor usage. So the planner can't optimize them regardless. The IMMUTABLE helpers would only matter if called independently in queries with constant args.

### 2. Conditional Cursor Extraction (Minor)

The frequency set functions (`daily_set`, etc.) are VOLATILE because they *always* open cursors for BYSETPOS. When BYSETPOS is not used (common case), the cursor path isn't needed. Extracting the non-cursor path into a STABLE helper could avoid VOLATILE for those calls.

**But:** These functions are only called from the main dispatcher which is itself VOLATILE.

### 3. `parse_rrule_parts` Could Arguably Be IMMUTABLE

This ~360-line function is pure string parsing and validation. The only potentially non-deterministic operation is `until_str::TIMESTAMPTZ` casting — but the function enforces that UNTIL strings end with `Z` (UTC), making the cast deterministic. This could safely be IMMUTABLE.

**Practical impact:** Marginal — it's called once per API invocation, not per-row.

## The Honest Assessment

The codebase's DECISIONS.md already documents this analysis well:

> "In practice, VOLATILE vs STABLE has negligible performance impact for this library."

This is correct for this specific codebase because:

1. **RRULE functions are set-returning** — called once in `FROM` clauses, not per-row in `WHERE` clauses
2. **Arguments come from table columns** — not constant args, so IMMUTABLE plan-time folding doesn't apply
3. **The entire call chain terminates at VOLATILE public APIs** — any inner IMMUTABLE classification is invisible to the planner when it reaches the caller
4. **No index expressions** — nobody creates `CREATE INDEX ... ON events (rrule."all"(rule, dtstart))` because these return sets

The one scenario where volatility *would* matter: if users call filter functions like `test_byday_rule` directly in WHERE clauses with constant BYDAY arrays against large tables. That's not the intended usage pattern.

## Recommendations

| Action | Effort | Impact | Verdict |
|--------|--------|--------|---------|
| Add TIMESTAMP overloads for filter functions (IMMUTABLE) | Medium | Negligible for typical usage | **Not worth it** unless users request direct filter access |
| Promote `parse_rrule_parts` to IMMUTABLE | Low | Negligible — called once per invocation | **Debatable** — safe but gains nothing measurable |
| Extract non-cursor paths from freq set functions | High | Negligible — callers are VOLATILE | **Not worth it** |
| Add `PARALLEL SAFE` annotations | Low | Could enable parallel query plans | **Worth investigating** — separate topic |

**Bottom line:** The current classifications are conservative and correct. The architecture — where all public APIs need `SET timezone` (forcing VOLATILE) and the frequency sets use cursors (also forcing VOLATILE) — means that making inner helpers IMMUTABLE doesn't propagate any benefit to the query planner. The decomposition strategy is theoretically sound but doesn't yield practical gains for this codebase's calling patterns.

The most impactful optimization avenue is likely **PARALLEL SAFE** annotations rather than volatility reclassification, but that's a separate investigation.

## Sources

- [PostgreSQL 18: Function Volatility Categories](https://www.postgresql.org/docs/current/xfunc-volatility.html)
- [AWS Blog: Volatility Classification in PostgreSQL](https://aws.amazon.com/blogs/database/volatility-classification-in-postgresql/)
- [Microsoft: PostgreSQL Query Performance Function Optimization Guide](https://techcommunity.microsoft.com/blog/adforpostgresql/postgresql-query-performance-a-guide-to-function-optimization/4386349)
- [DEV Community: Optimizing with Function Volatility](https://dev.to/bhanufyi/optimizing-postgresql-queries-with-function-volatility-volatile-stable-and-immutable-5cl8)
- [PostgreSQL 18: Function Optimization Information](https://www.postgresql.org/docs/current/xfunc-optimization.html)
