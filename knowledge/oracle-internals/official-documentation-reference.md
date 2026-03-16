---
verified_version: "23ai, 26ai"
last_verified: "2026-03-09"
oracle_doc_urls: []  # This file IS the URL reference
next_review: "quarterly"
confidence: "high"
---

# Official Oracle Documentation Reference — SQL/PGQ

Synthesized knowledge from official Oracle documentation for the Graph DBA Advisor. This file provides version-specific feature matrices, confirmed internal behavior, performance models, and verified documentation URLs.

## Contents
- [1. SQL/PGQ Feature Matrix by Version](#1-sqlpgq-feature-matrix-by-version)
- [2. GRAPH_TABLE Internal Translation Rules](#2-graph_table-internal-translation-rules)
- [3. Variable Length Path Performance Model](#3-variable-length-path-performance-model)
- [4. ONE ROW PER Clause Performance Implications](#4-one-row-per-clause-performance-implications)
- [5. Oracle Documentation URLs](#5-oracle-documentation-urls)
- [6. JSON Properties in Graphs](#6-json-properties-in-graphs)
- [7. SCN/Timestamp Queries (AS OF)](#7-scntimestamp-queries-as-of)

---

## 1. SQL/PGQ Feature Matrix by Version

### Oracle 23ai (Base — No Graph Server Required)

| Feature | Status | Notes |
|---------|--------|-------|
| `GRAPH_TABLE` operator | Supported | Core SQL/PGQ entry point |
| `MATCH` clause with vertex/edge patterns | Supported | `(a)-[e]->(b)` syntax |
| Fixed-length patterns | Supported | `(a)-[e1]->(b)-[e2]->(c)` — any number of hops |
| Bounded quantifiers `{n,m}` | Supported | Max upper bound = 10 (e.g., `{1,10}`) |
| `WHERE` clause inside `GRAPH_TABLE` | Supported | Predicates on vertex/edge properties |
| `COLUMNS` clause | Supported | Projects vertex/edge properties into relational columns |
| Aggregate functions in `COLUMNS` | Supported | `COUNT`, `SUM`, `LISTAGG`, etc. |
| `AS OF SCN` / `AS OF TIMESTAMP` | Supported | Flashback queries on graph — uses undo segments |
| `VERTEX_ID()` / `EDGE_ID()` | Supported | Unique identifiers for graph elements |
| `VERTEX_EQUAL()` / `EDGE_EQUAL()` | Supported | Identity comparison predicates |
| Label expressions (`IS label`) | Supported | Single label, disjunction (`IS person\|place`), conjunction |
| Anonymous vertices `()` and edges `[]` | Supported | Unnamed pattern elements |
| Inline `WHERE` on elements | Supported | `(a IS person WHERE a.name = 'John')` |
| Edge directionality | Supported | Right `->`, left `<-`, any `-` |
| `ALL PROPERTIES (*)` reference | Supported | `n.*` expands all properties |
| Bind variables in `WHERE` | Supported | `:bind_var` syntax works |
| PL/SQL functions in `WHERE`/`COLUMNS` | Supported | User-defined functions callable |
| SQL hints | Supported | `/*+ PARALLEL(4) */` etc. — placed in outer SELECT |
| JSON dot-notation on properties | Supported | `vertex.json_col.address.zip_code` |
| Cross-schema graph queries | Supported | With proper privileges |
| Multiple path patterns (comma-separated) | Supported | Implicit INNER JOIN on shared variables |
| Cyclic patterns (self-loops) | Supported | Same variable at start and end: `(a)-[e]->(a)` |
| `ONE ROW PER MATCH` | Supported | Default — one row per pattern match |

### Oracle 23ai + Graph Server 25.1+ (Additional Features)

| Feature | Status | Notes |
|---------|--------|-------|
| Path variables | Supported | `MATCH p = (a)-[e]->(b)` |
| `ONE ROW PER VERTEX (v)` | Supported | One row per vertex along a path |
| `ONE ROW PER STEP (v1, e, v2)` | Supported | One row per edge (source, edge, destination triple) |
| `IN paths_clause` | Supported | Specify which path variables to iterate |
| `MATCHNUM()` | Supported | Unique identifier per match |
| `PATH_NAME()` | Supported | Name of the path being iterated |
| `ELEMENT_NUMBER()` | Supported | Sequential element number of iterator vertex/edge |
| `binding_count()` | Supported | Number of times a variable binds in a match |
| `IS [NOT] LABELED` predicate | Supported | Check if element satisfies a label expression |
| `PROPERTY_EXISTS()` predicate | Supported | Check if element has a specific property |
| `SOURCE` / `DESTINATION` predicates | Supported | Direct access to edge endpoint properties |
| `LISTAGG` with path iteration | Supported | Aggregate across path steps |

### NOT Supported in Oracle 23ai/26ai

| Feature | Status | Alternative |
|---------|--------|-------------|
| `ANY` / `ALL` / `ALL SHORTEST` / `ANY CHEAPEST` goals | Not supported | Fixed-length patterns + application logic |
| `COST` / `TOTAL_COST` clauses | Not supported | Compute cost in `COLUMNS` as expression |
| Inline subqueries inside `GRAPH_TABLE` | Not supported | Use outer query joins or CTEs |
| `LATERAL` views inside `GRAPH_TABLE` | Not supported | Use outer LATERAL if needed |
| SQL Macros inside `GRAPH_TABLE` | Not supported | Expand macro logic manually |
| Unbounded quantifiers `{1,}` or `*` / `+` | Not supported | Use bounded `{1,10}` (max 10) |
| Variable-length path goals (shortest/cheapest) | Not supported | Application-level BFS/Dijkstra |

---

## 2. GRAPH_TABLE Internal Translation Rules

### Confirmed Behavior (EXPLAIN PLAN Evidence)

The `GRAPH_TABLE` operator is expanded during the **query transformation phase** — before cost estimation. By the time the CBO evaluates join orders and access paths, the query is pure relational SQL.

**1-hop pattern** `(a IS person) -[e IS friends]-> (b IS person)`:
```
Plan without indexes:
  HASH JOIN           ← e.dst = b.pk
    HASH JOIN         ← e.src = a.pk
      TABLE ACCESS STORAGE FULL — edge_table (e)
      TABLE ACCESS STORAGE FULL — vertex_table (a)
    TABLE ACCESS BY INDEX ROWID — vertex_table (b)
      INDEX UNIQUE SCAN — vertex_pk

Plan with FK indexes on edge table:
  NESTED LOOPS
    NESTED LOOPS
      TABLE ACCESS BY INDEX ROWID — vertex_table (a)    ← anchor vertex
        INDEX UNIQUE SCAN — vertex_pk                    ← WHERE a.id = :id
      TABLE ACCESS BY INDEX ROWID — edge_table (e)
        INDEX RANGE SCAN — idx_edge_src                  ← e.src = a.pk
    TABLE ACCESS BY INDEX ROWID — vertex_table (b)
      INDEX UNIQUE SCAN — vertex_pk                      ← e.dst = b.pk
```

**With `PARALLEL(N)` hint**: The optimizer may switch from HASH JOIN to NESTED LOOPS and add PX COORDINATOR/SEND operations. Parallel execution distributes the work across N processes.

### Hint Placement

Hints go in the **outer SELECT**, not inside the `GRAPH_TABLE` expression:
```sql
SELECT /*+ PARALLEL(4) */ *
FROM GRAPH_TABLE(g
  MATCH (a)-[e]->(b)
  COLUMNS (...)
);
```

For targeted hints using query block names:
```sql
SELECT /*+ LEADING(@"SEL$213F43E5" e a b) */ *
FROM GRAPH_TABLE(g
  MATCH (a)-[e]->(b)
  COLUMNS (...)
);
```

### Query Block Naming Convention

After transformation, each alias in the MATCH clause gets a query block reference:
- Edge alias `e` → `"E"@"SEL$<hex_id>"`
- Vertex alias `a` → `"A"@"SEL$<hex_id>"`
- Vertex alias `b` → `"B"@"SEL$<hex_id>"`

The hex ID (e.g., `SEL$213F43E5`) is assigned by the optimizer and visible in `DBMS_XPLAN.DISPLAY` output with `format => 'ALL'`. Use these for targeted hints:
```sql
/*+ INDEX(@"SEL$213F43E5" "E" idx_edge_src) */
/*+ LEADING(@"SEL$213F43E5" "E" "A" "B") */
/*+ USE_NL(@"SEL$213F43E5" "B") */
```

### 10046 Trace Confirmation

Oracle's SQL trace (event 10046) confirms that `GRAPH_TABLE` is fully transformed into standard joins before execution. The traced SQL shows regular `SELECT ... FROM edge_table e JOIN vertex_table a ON ... JOIN vertex_table b ON ...` with no graph-specific operators.

---

## 3. Variable Length Path Performance Model

### How Quantifiers Expand

A bounded quantifier `{n,m}` generates a **UNION ALL** of fixed-length patterns from `n` to `m`:

```sql
-- This:
MATCH (a) -[e IS friends]-> {1,5} (b)

-- Expands internally to approximately:
MATCH (a) -[e1]->(b)                              -- 1 hop
UNION ALL
MATCH (a) -[e1]->(x1) -[e2]->(b)                  -- 2 hops
UNION ALL
MATCH (a) -[e1]->(x1) -[e2]->(x2) -[e3]->(b)     -- 3 hops
UNION ALL
MATCH (a) -[e1]->(x1) -[e2]->(x2) -[e3]->(x3) -[e4]->(b)          -- 4 hops
UNION ALL
MATCH (a) -[e1]->(x1) -[e2]->(x2) -[e3]->(x3) -[e4]->(x4) -[e5]->(b) -- 5 hops
```

### Quantifier Types

| Quantifier | Meaning | Sub-plans generated |
|------------|---------|---------------------|
| `{3}` | Exactly 3 hops | 1 sub-plan (3 edge joins) |
| `{1,5}` | 1 to 5 hops | 5 sub-plans UNION'd |
| `{0,5}` | 0 to 5 hops | 6 sub-plans (includes zero-hop = just the vertex) |
| `{,5}` | 0 to 5 hops | Same as `{0,5}` |
| `{1,10}` | 1 to 10 hops (maximum) | 10 sub-plans |

### Constraints

- **Lower bound**: Must be >= 0
- **Upper bound**: Must be >= 1, and >= lower bound
- **Maximum upper bound**: **10** — Oracle does not support quantifiers beyond `{n,10}`
- Unbounded quantifiers (`*`, `+`, `{1,}`) are **not supported**

### Performance Implications

**Index impact is multiplied by the quantifier range**:
- `{1,5}` with FK index on edge table → 5 index range scans (fast)
- `{1,5}` without FK index → **5 full table scans** (catastrophic on large edge tables)
- `{1,10}` without FK index → **10 full table scans**

**Cost estimation**:
- Each sub-plan (hop count) is costed independently by the CBO
- The UNION ALL combines results — duplicates are possible across hop levels
- For a `{1,10}` pattern on an edge table with 1M rows and no FK index:
  - Worst case: 10 × full scan of 1M rows = 10M row accesses per execution
  - With FK index: 10 × index range scan (selectivity-dependent) — typically 1000x faster

**For traversals deeper than 10 hops**, use recursive CTEs:
```sql
WITH RECURSIVE paths (vertex_id, depth) AS (
  SELECT :start_id, 0 FROM DUAL
  UNION ALL
  SELECT e.dst, p.depth + 1
  FROM paths p
  JOIN edge_table e ON e.src = p.vertex_id
  WHERE p.depth < :max_depth
    AND e.end_date IS NULL
)
SELECT * FROM paths;
```

Or `CONNECT BY` as a fallback (less flexible but compatible with older Oracle versions).

---

## 4. ONE ROW PER Clause Performance Implications

### Cardinality Multiplier

| Clause | Rows per match | Formula |
|--------|---------------|---------|
| `ONE ROW PER MATCH` (default) | 1 | 1 row per pattern match |
| `ONE ROW PER VERTEX (v)` | N + 1 | Where N = number of edges (hops) in the path |
| `ONE ROW PER STEP (v1, e, v2)` | N | Where N = number of edges in the path |

### Example: 3-hop Path

For a path `v1 -[e1]-> v2 -[e2]-> v3 -[e3]-> v4`:

| Clause | Rows produced | Content |
|--------|--------------|---------|
| `ONE ROW PER MATCH` | 1 | Full match as single row |
| `ONE ROW PER VERTEX (v)` | 4 | v=v1, v=v2, v=v3, v=v4 |
| `ONE ROW PER STEP (s, e, d)` | 3 | (v1,e1,v2), (v2,e2,v3), (v3,e3,v4) |

### Special Cases

- **Zero-hop path** (quantifier `{0,N}` matching at 0): `ONE ROW PER VERTEX` produces 1 row (the single vertex); `ONE ROW PER STEP` produces 1 row with only the source bound (edge and destination are NULL).
- **Empty result**: No rows produced regardless of clause.

### Performance Impact

1. **V$SQL.ROWS_PROCESSED interpretation**: A query returning 1M rows with `ONE ROW PER VERTEX` on a `{1,5}` quantifier might represent only ~200K actual path matches, each expanded by ~5 vertices. The advisor must account for this multiplier when estimating workload impact.

2. **Downstream operations**: `GROUP BY`, `ORDER BY`, and `DISTINCT` after `ONE ROW PER VERTEX/STEP` operate on the expanded row set. A query that finds 100K matches with 5-hop paths produces ~500K rows for sorting/grouping.

3. **Memory and temp space**: The row multiplication directly impacts PGA usage (sort area, hash area) and temp tablespace usage for large result sets.

4. **Aggregation with iteration**: `LISTAGG` and other aggregates in the `COLUMNS` clause aggregate across the full match (all steps/vertices), which can produce very wide rows for long paths.

### Iterator Variable Restrictions

- Iterator variables (`v`, `v1`, `e`, `v2`) can **only** be referenced in the `COLUMNS` clause
- They **cannot** appear in the `WHERE` clause or graph pattern
- They must have unique names distinct from all pattern variables

---

## 5. Oracle Documentation URLs

### Primary Reference — Graph Developer's Guide (25.3)

| Topic | URL |
|-------|-----|
| Guide Home | https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/ |
| SQL Graph Queries | https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/sql-graph-queries.html |
| Graph Pattern Syntax | https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/graph-pattern.html |
| Variable Length Patterns | https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/variable-length-path-patterns.html |
| Complex Path Patterns | https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/complex-path-patterns.html |
| ONE ROW PER Clause | https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/using-one-row-clause-sql-graph-query.html |
| Features & Limitations | https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/supported-feature-and-limitations-querying-sql-property-graph.html |
| Tuning SQL Graph Queries | https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/tuning-sql-property-graph-queries.html |

### SQL Language Reference — GRAPH_TABLE (26ai)

| Topic | URL |
|-------|-----|
| GRAPH_TABLE Shape | https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/graph-table-shape.html |

### PGX / Graph Server Documentation

| Topic | URL |
|-------|-----|
| Performance Considerations for PGQL | https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/performance-considerations-pgql-queries-executed-sql.html |
| Load Graph to Memory (PGX) | https://docs.oracle.com/en/database/oracle/property-graph/23.1/spgdg/load-graph-memory-and-run-graph-analytics.html |
| API: Loading Graphs into PGX | https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/loading-graph-pgx-server.html |
| Two-Tier vs Three-Tier Architecture | https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/overview-oracle-property-graph.html |

### SQL/PGQ Compliance & Standards

| Topic | URL |
|-------|-----|
| SQL/PGQ ISO Compliance | https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/sql-property-graph-query-pgq-compliance.html |
| Graph Developer's Guide PDF (25.1) | https://docs.oracle.com/en/database/oracle/property-graph/25.1/spgdg/property-graph-developer-guide.pdf |

### Community & Blog References

| Topic | URL |
|-------|-----|
| ORACLE-BASE Tutorial | https://oracle-base.com/articles/23/sql-property-graphs-and-sql-pgq-23 |
| Oracle Blog: SQL/PGQ Standard | https://blogs.oracle.com/database/post/property-graphs-in-oracle-database-23ai-the-sql-pgq-standard |

### Industry References

| Topic | URL |
|-------|-----|
| Neo4j Graph Data Modeling Principles | https://neo4j.com/docs/getting-started/data-modeling/guide-data-modeling/ |

---

## 6. JSON Properties in Graphs

### Dot-Notation Access

SQL/PGQ supports JSON typed vertex and edge properties with dot-notation syntax:

```sql
SELECT * FROM GRAPH_TABLE(g
  MATCH (p IS person)
  WHERE p.json_data.address.zip_code.number() = 94065
  COLUMNS (p.name, p.json_data.address.city.string() AS city)
);
```

The `json_data.address.zip_code` path navigates into a JSON column on the underlying vertex table. Type accessors (`.string()`, `.number()`) cast the JSON value to SQL types.

### Equivalent JSON_VALUE Syntax

```sql
-- Dot notation:
p.json_data.gender.string()

-- Equivalent:
JSON_VALUE(p.json_data, '$.gender' RETURNING VARCHAR2)
```

### JSON Schema Validation

JSON columns support JSON Schema validation constraints, ensuring data quality at the table level.

### Performance Implications

- **B-tree indexes do NOT work** on JSON path expressions — `CREATE INDEX idx ON table(json_col.path)` is not valid
- **Function-based index**: Create on the `JSON_VALUE` expression:
  ```sql
  CREATE INDEX idx_person_zip ON person_table(
    JSON_VALUE(json_data, '$.address.zip_code' RETURNING NUMBER)
  );
  ```
- **JSON search index**: For flexible querying across multiple JSON paths:
  ```sql
  CREATE SEARCH INDEX idx_person_json ON person_table(json_data)
    FOR JSON;
  ```
- **Advisor action**: Flag any JSON property predicate in a `GRAPH_TABLE WHERE` clause as a potential performance risk. Recommend either a function-based index on the specific path or a JSON search index for multi-path queries.
- **Selectivity**: The CBO has limited ability to estimate selectivity for JSON path expressions. Consider gathering extended statistics on the `JSON_VALUE` expression.

---

## 7. SCN/Timestamp Queries (AS OF)

### Syntax

`GRAPH_TABLE` supports flashback queries using `AS OF`:

```sql
SELECT * FROM GRAPH_TABLE(my_graph AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR)
  MATCH (a)-[e]->(b)
  COLUMNS (a.name, b.name)
);

SELECT * FROM GRAPH_TABLE(my_graph AS OF SCN 123456789
  MATCH (a)-[e]->(b)
  COLUMNS (a.name, b.name)
);
```

The `AS OF` clause applies to the graph as a whole — all underlying vertex and edge tables are queried at the specified SCN or timestamp.

### Performance Implications

- **Undo segment access**: AS OF queries reconstruct past row versions from undo segments. For large graphs with high DML rates, this can be significantly slower than current-state queries due to undo block reads.
- **No special index considerations**: The same indexes used for current-state queries apply to flashback queries. The optimizer uses the same plans — the difference is in the data access layer (undo reconstruction).
- **Undo retention**: Verify that `UNDO_RETENTION` is sufficient for the flashback window. If undo has been overwritten, the query fails with `ORA-01555: snapshot too old`.
- **Use cases**: Point-in-time graph analysis ("show me the network state before the fraud event"), audit trails, comparing graph evolution over time.
- **Advisor action**: If `AS OF` is used in graph queries, note the undo retention requirement and warn if the flashback window exceeds the configured retention period. No index changes needed specifically for AS OF.
