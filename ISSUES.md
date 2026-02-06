# Testing Issues

Issues identified through critical evaluation of the testing framework. Prioritized by risk and production impact.

**Generated:** 2026-02-06
**Statement Coverage:** 71.62% (911/1272)
**Branch Coverage:** 95.2% (200/210)
**Mutation Score:** 100% (21/21)

---

## Status Legend

| Status | Meaning |
|--------|---------|
| `OPEN` | Not started |
| `IN_PROGRESS` | Work underway |
| `REQUIRES VERIFICATION` | Needs independent verification that the issue doesn't exist |
| `DEFERRED` | Intentionally postponed |

---

## Deferred

### ISSUE-013: Sub-day frequency coverage

**Status:** DEFERRED
**Risk:** LOW (feature disabled by default)
**Coverage Impact:** ~200 statements

Sub-day frequencies (HOURLY, MINUTELY, SECONDLY) are intentionally disabled by default for security reasons (DoS risk: SECONDLY can generate 31M+ occurrences/year).

The following have low coverage because sub-day code paths aren't exercised in standard tests:
- `hourly_set()`: 56.25%
- `minutely_set()`: 56.25%
- `secondly_set()`: 56.25%
- TZ generator sub-day branches: 0%

**Deferral Reason:**
1. Feature is disabled by default for security
2. Requires `install_with_subday.sql` which has explicit security warnings
3. Testing would require separate test mode with security implications
4. Existing `test_subday_correctness.sql` covers the feature when enabled

**Revisit Condition:** If sub-day frequencies become enabled by default (requires security review).

**Reference:** CLAUDE.md "Security" section, docs/SUBDAY_OPERATIONS.md

---

## Notes

### Running Coverage Analysis

```bash
# Full profiler coverage report
./scripts/profiler-coverage.sh

# Branch coverage analysis
node scripts/verify-branch-coverage.js

# Mutation testing
npm run test:mutations
```

### Adding New Issues

Use the format:
```markdown
### ISSUE-NNN: Brief description

**Status:** OPEN
**Risk:** CRITICAL | HIGH | MEDIUM | LOW
**Coverage Impact:** N statements/branches

Description of the issue.

**Test Strategy:**
- Specific test approach
- Files to modify

**Files:** `tests/relevant_file.sql`
```
