# Research: Mutation Testing for SQL/PL/pgSQL

## Executive Summary

**Automated mutation testing tools for PL/pgSQL specifically do not exist.** The closest tools target Oracle's PL/SQL (muPLSQL) or Hive SQL (Mutant Swarm), neither of which is compatible with PostgreSQL. However, a practical DIY approach using text-based mutation (regex substitution) is viable and the project already implements this in `scripts/mutation-test.js`. Academic research defines well-established SQL mutation operators that can guide expansion of the existing approach.

## Tools Found

### 1. muPLSQL (Oracle PL/SQL Only)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/arzutr/MuPLSQL |
| **Database** | Oracle PL/SQL only |
| **Maturity** | Academic prototype (8 stars, last updated 2022) |
| **License** | MIT |
| **Language** | Java |

**Description:** A mutation testing tool specifically for Oracle PL/SQL programs. Uses the plsql-parser library for AST manipulation. Supports dozens of mutation operators and automates both mutant generation and test execution.

**Applicability to PL/pgSQL:** None directly. Oracle PL/SQL and PostgreSQL PL/pgSQL have different syntax (e.g., `%TYPE` vs explicit types, `EXCEPTION WHEN` differences, package structures). The parser would not work on PL/pgSQL code.

**Paper:** Turan et al., "Mutation testing of PL/SQL programs" (Journal of Systems and Software, 2022)

---

### 2. Mutant Swarm (Hive SQL Only)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/HiveRunner/mutant-swarm |
| **Database** | Apache Hive SQL only |
| **Maturity** | Production quality (24 stars, Expedia origin) |
| **License** | Apache 2.0 |
| **Language** | Java |

**Description:** Mutation testing framework for Hive SQL built on HiveRunner. Works by instrumenting HiveRunner test suites and generating mutants at the AST level using Hive's parser.

**Applicability to PL/pgSQL:** None. Hive SQL is semantically different from PostgreSQL SQL, and the tool is tightly coupled to the HiveRunner testing framework.

---

### 3. SQLMutation (SELECT Queries Only)

| Attribute | Value |
|-----------|-------|
| **URL** | No public repository; described in academic papers |
| **Database** | Generic SQL SELECT queries |
| **Maturity** | Academic prototype (2006-2007) |
| **License** | Unknown |

**Description:** A tool developed by Tuya et al. at University of Oviedo for mutating SQL SELECT queries. It implements the foundational SQL mutation operators used in most subsequent research.

**Applicability to PL/pgSQL:** The mutation operators are applicable conceptually, but the tool itself appears to be unavailable publicly and targets only SELECT queries, not procedural code.

**Paper:** Tuya et al., "Mutating database queries" (Information and Software Technology, 2007) - 210+ citations

---

### 4. universalmutator (Language-Agnostic Text Mutation)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/agroce/universalmutator |
| **Database** | Any language (text-based regex) |
| **Maturity** | Active development (150 stars, updated 2026) |
| **License** | Apache 2.0 |
| **Language** | Python |

**Description:** A regexp-based tool for mutating source code across numerous languages. Uses simple text substitution rules. Supports C, C++, Java, Python, Swift, Rust, Go, Solidity, and more. Does NOT have built-in SQL support but is extensible.

**Applicability to PL/pgSQL:** **Potentially usable.** Could define custom mutation rules for PL/pgSQL syntax. This is essentially the same approach as the project's existing `mutation-test.js` but with more infrastructure for managing mutants.

**Paper:** Groce et al., "Simple Testing Can Prevent Most Critical Failures" (FSE 2024, ICSE 2018)

---

### 5. domohuhn/mutation-test (Language-Agnostic via XML Rules)

| Attribute | Value |
|-----------|-------|
| **URL** | https://github.com/domohuhn/mutation-test |
| **Database** | Any language (XML-defined regex rules) |
| **Maturity** | Active (22 stars, updated 2026) |
| **License** | BSD-3-Clause |
| **Language** | Dart |

**Description:** Automated mutation testing using regex-based rules defined in XML documents. Generates HTML reports. Designed for any programming language.

**Applicability to PL/pgSQL:** **Directly usable.** XML rules could define PL/pgSQL-specific mutations. Provides reporting infrastructure the project currently lacks.

---

## SQL Mutation Operators

Based on Tuya et al. (2007) and subsequent research, these are the established SQL mutation operator categories:

### SC - SQL Clause Mutation Operators

| Operator | Description | Example |
|----------|-------------|---------|
| **SEL** | Replace SELECT list | `SELECT a, b` -> `SELECT a` |
| **JOI** | Change JOIN type | `INNER JOIN` -> `LEFT JOIN` |
| **GOR** | Modify GROUP BY | Remove/add columns |
| **HAV** | Modify HAVING clause | Change aggregation |
| **ORD** | Modify ORDER BY | Remove or change sort |
| **UNI** | Change UNION/INTERSECT/EXCEPT | `UNION` -> `INTERSECT` |
| **SUB** | Modify subquery usage | Subquery -> constant |
| **ABS** | Aggregate function swap | `SUM` -> `AVG`, `COUNT` -> `MAX` |

### OR - Operator Replacement Mutation Operators

| Operator | Description | Example |
|----------|-------------|---------|
| **ROR** | Relational Operator Replacement | `=` -> `<>`, `>` -> `>=` |
| **LCR** | Logical Connector Replacement | `AND` -> `OR` |
| **AOR** | Arithmetic Operator Replacement | `+` -> `-`, `*` -> `/` |
| **UOR** | Unary Operator Replacement | Remove `-` sign |
| **ABS** | Absolute Value Insertion | `x` -> `ABS(x)` |

### NL - NULL Mutation Operators

| Operator | Description | Example |
|----------|-------------|---------|
| **NLI** | NULL Literal Insertion | `x = 5` -> `x = NULL` |
| **NLS** | NULL condition swap | `IS NULL` -> `IS NOT NULL` |
| **NLF** | NULL function modification | `COALESCE(x, 0)` -> `x` |

### IR - Identifier Replacement Mutation Operators

| Operator | Description | Example |
|----------|-------------|---------|
| **IRC** | Column replacement | `col_a` -> `col_b` |
| **IRT** | Table replacement | `table_a` -> `table_b` |
| **IRV** | Constant/variable swap | `5` -> `10`, `'A'` -> `'B'` |

### PL/pgSQL-Specific Operators (Proposed)

These are not from literature but would be meaningful for PL/pgSQL procedural code:

| Operator | Description | Example |
|----------|-------------|---------|
| **LBR** | Loop Boundary Replacement | `< limit` -> `<= limit` |
| **RCT** | RETURN type change | `RETURN NULL` -> `RETURN 0` |
| **EXC** | Exception handling removal | Remove `EXCEPTION WHEN` block |
| **IFC** | IF condition mutation | `IF x THEN` -> `IF NOT x THEN` |
| **EXT** | EXIT condition change | `EXIT WHEN x` -> `EXIT WHEN NOT x` |
| **INC** | Increment change | `:= x + 1` -> `:= x + 2` |
| **INT** | Interval mutation | `'1 day'` -> `'2 days'` |
| **TYP** | Type boundary | `INTEGER` -> `SMALLINT` overflow |

## DIY Implementation Approach

Since no suitable automated tool exists for PL/pgSQL, the project should continue with its manual/scripted approach. Here's a refined strategy:

### Current State

The project already has:
- `scripts/mutation-test.js` - Text-based mutation via regex
- `tests/mutation/test_mutation_catching.sql` - Tests designed to catch specific mutations
- 14 mutation patterns defined covering boundaries, off-by-one, logic, filters, and constants

### Recommended Enhancements

#### 1. Expand Mutation Operator Coverage

Add these high-value mutations based on academic research:

```javascript
// Relational Operator Replacement (ROR)
['ror-1', /(\w+)\s*=\s*(\w+)(?!_)/g, '$1 <> $2', 'Equal to not-equal'],
['ror-2', />=/g, '>', 'Greater-or-equal to greater'],
['ror-3', /<=/g, '<', 'Less-or-equal to less'],

// Logical Connector Replacement (LCR)
['lcr-1', / AND (?!result)/g, ' OR ', 'AND to OR'],
['lcr-2', / OR (?!test_)/g, ' AND ', 'OR to AND'],

// NULL mutations (NL)
['nls-1', /IS NULL/g, 'IS NOT NULL', 'NULL check inversion'],
['nls-2', /IS NOT NULL/g, 'IS NULL', 'NOT NULL check inversion'],

// Arithmetic mutations (AOR)
['aor-1', / \+ (?=\d)/g, ' - ', 'Addition to subtraction'],
['aor-2', / - (?=\d)/g, ' + ', 'Subtraction to addition'],

// Interval mutations
['int-1', /INTERVAL '1 day'/g, "INTERVAL '2 days'", 'Day interval change'],
['int-2', /INTERVAL '1 month'/g, "INTERVAL '2 months'", 'Month interval change'],
```

#### 2. Adopt universalmutator or mutation-test

These tools provide:
- Systematic mutant generation and tracking
- HTML/XML reports for mutation score
- Ability to resume partial runs
- Better handling of equivalent mutants

Example with universalmutator:
```bash
pip install universalmutator
# Create custom rules file for PL/pgSQL
mutate src/rrule.sql --rules plpgsql.rules --noCheck
analyze_mutants src/rrule.sql "npm test" --mutantDir mutants
```

#### 3. Mutation Score Tracking

Track these metrics over time:
- **Mutation Score** = Killed / (Total - Equivalent)
- **Equivalent Mutation Rate** = Equivalent / Total
- Per-function mutation scores to identify weak areas

### Implementation Effort Estimate

| Task | Effort | Value |
|------|--------|-------|
| Expand mutation operators in existing script | 2-4 hours | High |
| Add mutation score reporting | 2-3 hours | Medium |
| Integrate universalmutator | 4-8 hours | Medium |
| Write tests to catch surviving mutants | Ongoing | High |
| AST-based mutation (building a parser) | 40+ hours | Low (not recommended) |

## Effort Estimate: Is This Worth Pursuing?

### Verdict: Continue with Manual/Scripted Approach

**Reasons:**
1. **No suitable automated tool exists** for PL/pgSQL
2. **The existing approach works** - the project already has mutation testing infrastructure
3. **Diminishing returns** - Catching 80%+ of meaningful mutations is achievable with text-based approaches; the remaining require deep semantic understanding
4. **Equivalent mutation problem** - Even sophisticated tools struggle to identify equivalent mutants (mutations that don't change behavior)

### Recommended Investment

| Priority | Action | Time |
|----------|--------|------|
| High | Add 10-15 more mutation patterns from OR/NL categories | 3-4 hours |
| High | Write tests for any surviving non-equivalent mutants | 2-4 hours |
| Medium | Add mutation score reporting to CI | 2-3 hours |
| Low | Evaluate universalmutator integration | 4-6 hours |
| Not recommended | Build custom AST-based tool | 40+ hours |

## References

### Academic Papers

1. **Tuya, J., Suarez-Cabal, M.J., de la Riva, C.** (2007). "Mutating database queries." *Information and Software Technology*, 49(4):398-417. DOI: 10.1016/j.infsof.2006.06.001. [210+ citations]
   - Foundational paper defining SQL mutation operators (SC, OR, NL, IR categories)

2. **Tuya, J., Suarez-Cabal, M.J., de la Riva, C.** (2006). "SQLMutation: A tool to generate mutants of SQL database queries." *Proceedings of the Second Workshop on Mutation Analysis (Mutation 2006)*.
   - Tool paper for SQLMutation

3. **Derezinska, A., & Kowalski, K.** (2009). "An experimental case study to applying mutation analysis for SQL queries." *International Conference on Dependable Computer Systems*.
   - Evaluation of SQL mutation operators

4. **Pan, K., Wu, X., Xie, T.** (2013). "Automatic Test Generation for Mutation Testing on Database Applications." *AST Workshop*.
   - MutaGen approach combining program and SQL query mutations
   - URL: https://taoxie.cs.illinois.edu/publications/ast13-dbtest.pdf

5. **Turan, A.M. et al.** (2022). "Mutation testing of PL/SQL programs." *Journal of Systems and Software*, 191:111399.
   - muPLSQL tool for Oracle PL/SQL

6. **Groce, A. et al.** (2024). "Simple Testing Can Prevent Most Critical Failures." *FSE 2024*.
   - Universal Mutator approach
   - URL: https://agroce.github.io/fse24.pdf

### Tools and Resources

- **universalmutator**: https://github.com/agroce/universalmutator
- **mutation-test (Dart)**: https://github.com/domohuhn/mutation-test
- **muPLSQL**: https://github.com/arzutr/MuPLSQL
- **Mutant Swarm**: https://github.com/HiveRunner/mutant-swarm
- **Awesome Mutation Testing**: https://github.com/theofidry/awesome-mutation-testing

### Related Project Documentation

- Mutation Testing Analysis: https://web.eecs.umich.edu/~weimerw/2022-481F/readings/mutation-testing.pdf
- SQL Full Predicate Coverage: https://giis.uniovi.es/testing/papers/stvr-2010-sqlfpc.pdf

---

*Research conducted: February 2026*
*Status: No suitable automated tool exists for PL/pgSQL; manual/scripted approach recommended*
