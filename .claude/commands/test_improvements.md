# ORCHESTRATOR ROLE

You are an ORCHESTRATOR. You coordinate and dispatch subagents, track their results, and make delegation decisions. You MAY read project reference docs (CLAUDE.md, TESTING_FRAMEWORK.md, TESTING_STANDARDS.md, POTENTIAL_ISSUES.md) directly. You MUST delegate all code analysis, fix implementation, and test writing to subagents.

**POTENTIAL_ISSUES.md is the single source of truth.** Reports accumulate across runs. An issue qualifies for fixing when its report count meets the severity threshold:

| Severity | Reports needed |
|----------|---------------|
| Critical | 1             |
| High     | 1             |
| Medium   | 2             |
| Low      | 3             |

---

## PHASE 1: Parallel Analysis

Read TESTING_FRAMEWORK.md for the full category list (10 categories). Deploy 2 PARALLEL subagents per category (20 total), each with this instruction:

> **Read** CLAUDE.md, TESTING_STANDARDS.md, POTENTIAL_ISSUES.md, and the test files in `tests/`.
>
> **Analyze** `src/rrule.sql` and `src/rrule_subday.sql` for issues in the **{{$category}}** category. Report all severities. Focus on genuine bugs — wrong output, missing validation, unsafe behavior, or untested code paths that could plausibly be wrong. Not style issues.
>
> **Do NOT write to any files.**
>
> **Report** each finding as:
> - Severity: [Low/Medium/High/Critical]
> - Location: [file:line]
> - Description: [1-2 sentences]
> - Explanation: [why this is a true issue, not a false positive]
> - Existing issue: [POTENTIAL_ISSUES.md issue number, or "New"]
> - Confidence: [Low/Medium/High]

---

## PHASE 2: Update POTENTIAL_ISSUES.md

After all 20 agents complete, YOU (orchestrator) update the file:

1. Collect and deduplicate all findings (group by root cause, even if worded differently)
2. For each unique finding:
   - **Existing unresolved entry:** increment `**Reports:**` by the number of agents that found it
   - **New:** add an entry with `**Reports:**` set to the agent count
   - **Already resolved:** skip
3. **Severity disagreements:** record the **highest** reported severity. Note the range if agents differ, e.g., `**Severity Assessment:** High (range: Medium–High from 3 reports)`. The highest value determines the qualification threshold.
4. Commit: `git add POTENTIAL_ISSUES.md && git commit -m "docs: update potential issues from analysis run"`

---

## PHASE 3: Fix Deployment

1. Read POTENTIAL_ISSUES.md. Identify all **unresolved** issues meeting their severity threshold (see table above).
2. If none qualify, skip to Phase 5.
3. **Create worktrees** sequentially before launching agents:
   ```bash
   git worktree add /tmp/fix-issue-{N} -b fix/issue-{N}
   ```
   Database isolation is automatic — test.sh and lint.sh derive unique DB names from the branch.
4. Deploy a BACKGROUND fix agent per qualifying issue:

> **Your issue:** [paste full POTENTIAL_ISSUES.md entry]
>
> **Your worktree:** `/tmp/fix-issue-{N}` — created by orchestrator, do NOT create it yourself. Run ALL commands from this directory. DB isolation is automatic.
>
> **Read** CLAUDE.md (especially Development Rules) and TESTING_STANDARDS.md. Key rules:
> - ROLLBACK not COMMIT, fixed timestamps, exact assertions, ORDER BY in array_agg
> - All functions use `rrule.` prefix
> - Rule #9: generator loop changes must be applied to all 4 copies
> - Rule #10: test with INTERVAL > 1 when modifying period advancement
>
> **Steps:**
> 1. `cd /tmp/fix-issue-{N}`
> 2. Research and apply the fix
> 3. Create/update tests per TESTING_STANDARDS.md
> 4. Run `npm test`, `npm run lint`, `npm run lint:tests` — fix until all pass
> 5. Commit: `fix(rrule): {description}`
>
> **Report:**
> - Issue: [number] | Fix applied: [Yes/No] | Branch: [name]
> - Files modified: [list] | Tests: [Passed/Failed - count] | Commit: [hash or N/A]

---

## PHASE 4: Merge & Verify

1. Return to primary checkout: `cd /Users/viktor/Documents/Projects/github/rrule_plpgsql && git checkout main`
2. Merge each branch sequentially (least likely to conflict first): `git merge --no-ff fix/issue-{N}`
3. Resolve any merge conflicts
4. Run full verification: `npm test` + `npm run lint` + `npm run lint:tests` — fix until clean
5. Mark fixed issues in POTENTIAL_ISSUES.md: `**Status:** Resolved in commit {hash}`
6. Commit: `git add POTENTIAL_ISSUES.md && git commit -m "docs: mark resolved issues from fix run"`
7. Clean up:
   ```bash
   git worktree remove /tmp/fix-issue-{N}
   dropdb --if-exists rrule_test_fix_issue_{N}
   dropdb --if-exists rrule_lint_fix_issue_{N}
   ```

---

## PHASE 5: Summary

```
## Test Improvement Run Summary

### Categories Analyzed: All 10 (TESTING_FRAMEWORK.md), 2 agents each

### Issues Recorded This Run
| Issue # | Action | Severity | Reports | Description |
|---------|--------|----------|---------|-------------|
| ...     | New/+N | ...      | ...     | ...         |

### Fixed (met severity threshold): {count}
| Issue # | Severity | Reports | Threshold | Branch | Tests | Commit |
|---------|----------|---------|-----------|--------|-------|--------|
| ...     | ...      | ...     | ...       | ...    | ...   | ...    |

### Backlog (below threshold): {count}
| Issue # | Severity | Reports | Threshold | Description |
|---------|----------|---------|-----------|-------------|
| ...     | ...      | ...     | ...       | ...         |

### Verification
- Tests: {pass/fail count}
- Lint: {status}
- Lint:tests: {status}
```

---

## CONSTRAINTS

- Orchestrator delegates ALL code analysis and fixes — never write code yourself
- All subagents return SUCCINCT SUMMARIES ONLY
- Track all dispatched agents before proceeding to the next phase
- POTENTIAL_ISSUES.md is the single source of truth — never bypass it
