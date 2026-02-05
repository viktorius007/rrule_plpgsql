# Testing Framework for Production Readiness

## 1. Functional Correctness
- **Happy path**: Every public API function with typical inputs
- **All parameter combinations**: Each supported parameter individually, then in meaningful combinations
- **Spec compliance**: Every MUST/MUST NOT/SHOULD from the governing spec (RFC 5545 in your case)
- **Reference implementation parity**: Compare output against known-good implementations (rrule.js, python-dateutil)

## 2. Input Validation & Error Handling
- **Invalid inputs**: Malformed strings, wrong types, NULL values, empty strings
- **Mutually exclusive parameters**: Combinations the spec forbids
- **Out-of-range values**: Boundary violations on every numeric parameter
- **Error message quality**: Are messages actionable? Do they identify the problem?

## 3. Edge Cases & Boundary Conditions
- **Calendar boundaries**: Leap years (Feb 29), month-end (28/29/30/31), year boundaries
- **Timezone transitions**: DST spring-forward gaps, fall-back ambiguity, UTC offset changes
- **Extreme values**: Very large intervals, max count, dates far in the past/future
- **Empty result sets**: Rules that match nothing in a given range
- **Single-element results**: COUNT=1, exact boundary matches

## 4. API Contract
- **Default parameter values**: Verify documented defaults behave correctly
- **`inc` (inclusive) flag**: Exact boundary inclusion/exclusion for range queries
- **Return types**: Correct types, correct ordering, no duplicates unless expected
- **Idempotency**: Same input always produces same output (IMMUTABLE/STABLE guarantees)

## 5. Safety & Security
- **DoS protection**: Rules that would generate millions of results (SECONDLY without bounds)
- **Resource caps**: Verify hard limits (1000 results, 10-year window) are enforced
- **Warning emission**: Truncation warnings fire when caps are hit
- **Iteration limits**: Rules that could cause infinite loops terminate safely

## 6. Performance
- **Early exit optimization**: Does the engine stop generating once it has enough results?
- **Large result sets**: Behavior at and beyond the cap
- **Complex rules**: Deeply nested BYxxx combinations don't degrade unreasonably
- **Regression baselines**: Not necessarily timing, but verifying that optimization paths are actually taken (e.g., result count verification)

## 7. Integration & Real-World Usage
- **Table operations**: Using the functions in SELECT, WHERE, JOIN, LATERAL contexts
- **Batch operations**: UPDATE with computed columns, bulk scheduling
- **Conflict detection**: `overlaps()` in realistic multi-event scenarios
- **Driver compatibility**: Verify the npm package output works with pg, Prisma, Knex, etc.

## 8. Dual-Path Consistency
- **TIMESTAMP vs TIMESTAMPTZ API**: Same rule produces equivalent results through both paths
- **TZID-in-string vs explicit timezone parameter**: Parity between the two timezone approaches
- **Standard vs sub-day install**: Features available in both don't diverge

## 9. Upgrade & Install
- **Clean install**: Fresh database gets working functions
- **Reinstall (DROP + CREATE)**: No orphaned objects
- **Schema isolation**: Nothing leaks outside the `rrule` schema
- **PostgreSQL version compatibility**: Works on 12, 14, 16+

## 10. Cross-Cutting Concerns
- **SKIP + INTERVAL > 1**: Interactions between orthogonal features
- **BYSETPOS + complex BYxxx**: Post-filters applied after expansion
- **WKST + BYWEEKNO + year boundaries**: ISO week edge cases
- **Deduplication**: SKIP=FORWARD/BACKWARD doesn't produce duplicate dates
