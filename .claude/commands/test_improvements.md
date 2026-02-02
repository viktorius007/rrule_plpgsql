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

## CRITICAL: Context Window Management

**NEVER use `TaskOutput` to collect agent results.** `TaskOutput` returns the full raw JSONL transcript of the agent's entire session (every tool call, file read, hook event) — not just the final answer. Calling it for 20 agents WILL exhaust your context window and kill the session.

**Instead, wait for `<task-notification>` messages.** When a background agent completes, a `<task-notification>` is automatically delivered containing ONLY the agent's final result in the `<result>` tag. This is small and context-efficient.

**Workflow for collecting results:**
1. Launch all background agents with `run_in_background=true`
2. Do NOT call `TaskOutput`. Do NOT poll for results.
3. Simply wait — each agent will deliver a `<task-notification>` when done
4. Process notifications as they arrive
5. Proceed to the next phase only after all expected notifications have arrived

**This is the #1 cause of orchestrator failure. Do not use TaskOutput. Wait for notifications.**

---

## PHASE 1: Parallel Analysis

Read TESTING_FRAMEWORK.md for the full category list (10 categories). Deploy 2 PARALLEL subagents per category (20 total), each with the instruction template below.

### Analysis agent instruction template

> **Read** CLAUDE.md, TESTING_STANDARDS.md, POTENTIAL_ISSUES.md, and the test files in `tests/`.
>
> **Analyze** `src/rrule.sql` and `src/rrule_subday.sql` for issues in the **{{$category}}** category. Report all severities. Focus on genuine bugs — wrong output, missing validation, unsafe behavior, or untested code paths that could plausibly be wrong. Not style issues.
>
> **Do NOT write to any files.**
>
> ---
>
> ## OUTPUT FORMAT — follow exactly
>
> Your response has three sections in this order. No other content.
>
> ### Section 1: Scope
> A bullet list of what you examined. One bullet per area. No prose.
> ```
> SCOPE:
> - [area examined, e.g. "parse_rrule_parts() validation for all BYxxx ranges"]
> - [area examined]
> ```
>
> ### Section 2: Files read
> A bullet list of source and test files you actually opened.
> ```
> FILES:
> - src/rrule.sql (lines 1800-1900, 2300-2500)
> - tests/test_validation.sql
> ```
>
> ### Section 3: Findings
> If you found ZERO issues, write: `FINDINGS: None`
>
> If you found issues, list each one in this exact format:
> ```
> FINDING: [1-2 sentence description of the bug or gap]
> Severity: [Low|Medium|High|Critical]
> Confidence: [Low|Medium|High]
> Location: [file:line or file:function]
> Evidence: [1 sentence — why this is a true issue, not a false positive]
> Existing: [POTENTIAL_ISSUES.md issue number, or "New"]
> Fix scope: [files that would need modification to fix this, e.g. "src/rrule.sql (yearly_set only)" or "src/rrule.sql + src/rrule_subday.sql (all 4 generators)" or "tests/test_tz_api.sql (new section)"]
> Fix complexity: [Low|Medium|High]
> ```
>
> **Fix complexity scale:**
> - **Low**: 1-2 line change in 1-2 files, or appending tests to an existing file
> - **Medium**: Logic change in 1-3 locations, or creating a new test file
> - **High**: Changes across 4+ locations (e.g., all generators), structural refactor, or changes with subtle interaction effects (SKIP, BYSETPOS, drift prevention)
>
> Separate findings with a blank line.
>
> ---
>
> ## WHAT NOT TO INCLUDE
>
> - **No positive assessments** — do not praise the code, say it's "well-tested", "comprehensive", or "production-ready"
> - **No false-positive analysis** — if you investigated something and it's NOT a bug, don't mention it at all
> - **No explanations of how the code works** — the orchestrator has CLAUDE.md for that
> - **No recommendations or suggestions** — only report what IS wrong, not what COULD be improved
> - **No code blocks** — the Location field is sufficient for the orchestrator to find the code
> - **No summaries or conclusions** — the three sections above ARE the complete response

After launching all 20 agents, **WAIT for all 20 `<task-notification>` messages**. Do NOT call TaskOutput — it will flood your context with raw transcripts and crash the session.

---

## PHASE 2: Update POTENTIAL_ISSUES.md

After all 20 `<task-notification>` messages have arrived, YOU (orchestrator) update the file:

1. Collect and deduplicate all findings from the notification `<result>` tags (group by root cause, even if worded differently)
2. For each unique finding:
   - **Existing unresolved entry:** increment `**Reports:**` by the number of agents that found it. Update fix scope/complexity if new reports provide better information.
   - **New:** add an entry with `**Reports:**` set to the agent count. Include `**Fix Scope:**` and `**Fix Complexity:**` fields from the agent findings.
   - **Already resolved:** skip
3. **Severity disagreements:** record the **highest** reported severity. Note the range if agents differ, e.g., `**Severity Assessment:** High (range: Medium–High from 3 reports)`. The highest value determines the qualification threshold.
4. **Complexity disagreements:** record the **highest** reported fix complexity (conservative estimate). If agents disagree, note it, e.g., `**Fix Complexity:** High (range: Medium–High)`.
5. Commit: `git add POTENTIAL_ISSUES.md && git commit -m "docs: update potential issues from analysis run"`

---

## PHASE 3: Fix Deployment

1. Read POTENTIAL_ISSUES.md. Identify all **unresolved** issues meeting their severity threshold (see table above).
2. If none qualify, skip to Phase 5.
3. **Group qualifying issues into fix units** using the `Fix Scope` and `Fix Complexity` fields from POTENTIAL_ISSUES.md. Three constraints must be balanced:

   **Constraint A — Merge safety (combine overlapping code):**
   Issues whose fix scopes overlap (same file + nearby lines, or same generators) MUST be combined. Separate agents editing adjacent code will produce merge conflicts that are expensive to resolve.

   **Constraint B — Agent capacity (don't overload a single agent):**
   A single fix agent can handle roughly: 1 High-complexity fix, or 2 Medium-complexity fixes, or 3-4 Low-complexity fixes. Beyond this, the agent risks context exhaustion — it must read files, apply changes, write tests, and run verification. Two High-complexity fixes combined (e.g., both touching all 4 generators) will likely fail.

   **Constraint C — Parallelism (separate independent work):**
   Issues with non-overlapping fix scopes should be separate agents to maximize parallel execution.

   **When constraints conflict:** Merge safety (A) takes priority over parallelism (C). If two High-complexity issues overlap in scope, combine them but accept the context risk — it's better than guaranteed merge conflicts. If they don't overlap, always keep them separate.

   Name combined worktrees descriptively: `fix/issue-2-9` for combined, `fix/issue-11` for standalone.
4. **Create worktrees** sequentially before launching agents:
   ```bash
   git worktree add /tmp/fix-issue-{N} -b fix/issue-{N}
   ```
   Database isolation is automatic — test.sh and lint.sh derive unique DB names from the branch.
5. Deploy a BACKGROUND fix agent per fix unit (not necessarily per issue):

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
> **Report format — your response must use this structure:**
> ```
> Issue: [number] | Fix: [Yes/No] | Branch: [name] | Commit: [hash or N/A]
> Files: [list of modified files]
> Tests: [Passed/Failed - suite count] | Lint: [pass/fail] | Lint:tests: [pass/fail]
> ```
> If the fix FAILED or tests don't pass, add one line:
> ```
> Blocker: [1 sentence describing what went wrong]
> ```
> Do not explain your approach, reasoning, or what the code does. No narrative beyond the fields above.

After launching all fix agents, **WAIT for `<task-notification>` messages**. Do NOT call TaskOutput.

---

## PHASE 4: Merge & Verify

1. Return to primary checkout: `cd /Users/viktor/Documents/Projects/github/rrule_plpgsql && git checkout main`
2. Merge each branch sequentially (least likely to conflict first): `git merge --no-ff fix/issue-{N}`
3. Resolve any merge conflicts
4. Run full verification: `npm test` + `npm run lint` + `npm run lint:tests` — fix until clean
5. **Remove** fixed issues from POTENTIAL_ISSUES.md entirely (the fix commit serves as the record — no need to archive resolved entries in the file)
6. Commit: `git add POTENTIAL_ISSUES.md && git commit -m "docs: remove resolved issues from fix run"`
7. **Clean up all ephemeral artifacts** (worktrees and branches are disposable workspaces, not persistent records):
   ```bash
   # Remove worktrees
   git worktree remove /tmp/fix-issue-{N}
   # Delete merged fix branches
   git branch -d fix/issue-{N}
   # Drop isolated databases
   dropdb --if-exists rrule_test_fix_issue_{N}
   dropdb --if-exists rrule_lint_fix_issue_{N}
   ```
   Run cleanup for ALL fix branches from this run in a single step.

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
- Track all dispatched agents before proceeding to the next phase
- POTENTIAL_ISSUES.md is the single source of truth — never bypass it
- **NEVER use TaskOutput** — it returns full raw transcripts and will exhaust your context window. Wait for `<task-notification>` messages instead.
- **Analysis agents return: SCOPE (bullet list), FILES (bullet list), FINDINGS (structured blocks including Fix scope and Fix complexity).** No prose, no praise, no false-positive analysis, no code blocks. If an agent returns verbose narrative, the prompt needs tightening.
- **Fix agents return: 3-4 structured fields.** No narrative about approach or reasoning.
- **Fix grouping uses metadata, not guesswork.** The orchestrator MUST use Fix Scope and Fix Complexity from POTENTIAL_ISSUES.md to decide grouping. Do not read source files to determine fix scope — analysis agents already provided this information.
