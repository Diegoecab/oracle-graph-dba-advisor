# Oracle Property Graph — Recommendations Guide

**Last updated:** 2026-03-13
**Target platform:** Oracle Database 23ai / 26ai with SQL/PGQ (GRAPH_TABLE)
**Knowledge base version:** See `knowledge/FRESHNESS.md` for version tracking

---

## Table of Contents

1. [Graph Modeling Rules](#1-graph-modeling-rules)
2. [Physical Design](#2-physical-design)
3. [Query Best Practices](#3-query-best-practices)
4. [Index Strategy](#4-index-strategy)
5. [Advanced Indexing Strategies](#5-advanced-indexing-strategies)
6. [Anti-Patterns](#6-anti-patterns)
7. [Domain Patterns — Fraud Detection](#7-domain-patterns--fraud-detection)
8. [Domain Patterns — Social Network](#8-domain-patterns--social-network)
9. [Domain Patterns — Supply Chain](#9-domain-patterns--supply-chain)
10. [Graph vs Relational — Decision Criteria](#10-graph-vs-relational--decision-criteria)
11. [CBO Behavior with GRAPH_TABLE](#11-cbo-behavior-with-graph_table)
12. [PGX vs SQL/PGQ — When to Use Each](#12-pgx-vs-sqlpgq--when-to-use-each)
13. [Auto Indexing and Graph Workloads](#13-auto-indexing-and-graph-workloads)
14. [SQL/PGQ Feature Matrix](#14-sqlpgq-feature-matrix)

---

## 1. Graph Modeling Rules

*Source: `knowledge/graph-design/modeling-checklist.md`*

### Rule 1: Query-First Modeling
Design from traversal patterns backward to tables. Anchor vertex lookups must land on indexed columns. Start by listing the questions the graph must answer, then derive vertex/edge tables from those patterns.

### Rule 2: Supernode / Hub Isolation
Identify vertices with disproportionately many edges (popular merchants, system accounts, shared devices). A single supernode can turn a 2-hop traversal into a full table scan.

**Mitigations:**
- Ultra-selective edge filters (e.g., `end_date IS NULL` eliminates 80-90% of historical edges)
- Partitioning by `source_key`
- Relay vertices to break high-degree hubs into smaller groups
- Degree cap (application-level limit on edges per vertex)

Use selectivity analysis (template SELECTIVITY-04) to detect hub vertices by measuring edge degree distribution.

### Rule 3: Specific Relationship Types
Use descriptive labels (`TRANSFERRED`, `PURCHASED`, `FOLLOWS`) — never generic `RELATED_TO`.

**Separate tables per label (preferred):**
- CBO scans only the relevant table
- Independent optimizer statistics per edge type
- Cleaner CREATE PROPERTY GRAPH DDL

**Single table + label column:**
- Simpler schema
- Requires composite indexes `(label, source_key)`
- Statistics less accurate for individual relationship types

### Rule 4: Branching Factor Control
Multi-hop fan-out grows as N^K (N = average degree, K = hops). A vertex with 50 edges at hop 1 produces 2,500 intermediate rows at hop 2 and 125,000 at hop 3.

**Mitigations:**
- Introduce intermediate vertices to break high-fanout hops
- Example: User → (50 orders) → (5 products) = 250 rows, vs. User → (10K purchases) directly
- Apply `FETCH FIRST N ROWS ONLY` to cap result sets

### Rule 5: Separate Logical Graphs
Don't put everything in one massive graph if queries don't overlap. Smaller graphs produce:
- More stable optimizer statistics
- Faster discovery phase
- Fewer UNION ALL branches in generated SQL (when multiple labels exist)

### Rule 6: Lightweight Vertex / Edge Tables
Keep tables "thin" — core IDs, FKs, and frequently filtered properties only. Move JSON blobs, CLOBs, and long descriptions to a separate detail table joined on demand.

**Why:** Thin rows = more rows per Oracle block = faster full scans when they occur, and better buffer cache utilization.

### Rule 7: Compact, Consistent ID Types
Use `NUMBER` or `INTEGER` for primary keys (8 bytes) instead of `VARCHAR2` UUIDs (36+ bytes).

**Impact:**
- 4× smaller index entries
- Faster joins (numeric comparison vs. string comparison)
- Better buffer cache efficiency for FK columns (the most accessed columns in graph traversals)
- Alternative: `RAW(16)` for UUIDs (16 bytes vs 36)

### Rule 8: Consistent Edge Directionality
Establish and document a convention: source = actor/initiator, destination = target/recipient.

Inconsistent direction forces bidirectional traversals, which require 2× index storage and 2× DML overhead. Document the convention in a comment on the `CREATE PROPERTY GRAPH` statement.

---

## 2. Physical Design

*Source: `knowledge/graph-design/physical-design.md`*

### 2.1 Edge Table Partitioning

| Strategy | Best For | Pruning | Trade-off |
|----------|----------|---------|-----------|
| `HASH(source_key)` | Forward traversals from known vertices | Source vertex predicate | Reverse traversals scan all partitions |
| `RANGE(date) SUBPARTITION BY HASH(source_key)` | Temporal fraud detection | Double: date + source | Complex maintenance, careful boundary planning |
| `LIST(label)` | Multiple edge types in one table | Edge type filter | Skewed partition sizes if label distribution is uneven |

**Partition count:** Use powers of 2 for HASH partitioning to ensure uniform distribution.

### 2.2 Local vs Global Indexes

- **LOCAL indexes (preferred for graph FK columns):** One segment per partition. Enables partition-wise joins, online partition maintenance without index rebuild, and per-partition parallelism.
- **GLOBAL indexes:** Only when reverse traversals need global speed (rare for graph workloads).

### 2.3 Partition-Wise Joins

Requires matching partition semantics: same partition key, same partition count, same method on both edge and vertex tables.

Only worthwhile for graphs with 10M+ edges. Example: `edge.src HASH(16)` + `vertex.id HASH(16)`.

### 2.4 FK and CHECK Constraints

`CREATE PROPERTY GRAPH` references (`SOURCE KEY ... REFERENCES`) are **metadata only** — they do NOT enforce referential integrity at DML time. Always include:
- Physical `FOREIGN KEY` constraints in base table DDL
- `CHECK` constraints for domain values and structural rules (e.g., prevent self-loops with `CHECK (src <> dst)`)
- Post-creation validation to detect orphan edges

### 2.5 Index-Organized Tables (IOT) for Edge Tables

Organize on `(source_key, destination_key)` or `(source_key, destination_key, id)`.

| Aspect | Assessment |
|--------|-----------|
| **Pros** | Sequential I/O for forward traversals (40-60% physical read reduction), no separate index needed, `COMPRESS 1` saves storage |
| **Cons** | Poor random INSERT performance, secondary indexes slower, reverse traversals need secondary index |
| **Use for** | Read-heavy analytics, batch-loaded, OLAP-style traversals |
| **Avoid for** | Streaming ingestion, high-DML real-time graphs |

### 2.6 Vertex Table Partitioning

Usually unnecessary unless:
- Very large vertex tables (1M+ rows)
- Temporal access patterns that benefit from RANGE partitioning
- Partition-wise join with co-partitioned edge tables

---

## 3. Query Best Practices

*Source: `knowledge/graph-design/query-best-practices.md`*

### 3.1 Limit Variable-Length Path Depth
- Maximum upper bound in Oracle 23ai: 10 (e.g., `{1,10}`)
- `{1,3}` generates 3 UNION ALL sub-plans; `{1,10}` generates 10
- Each additional hop multiplies execution time
- For depths > 4, reconsider the graph design (shortcut edges, materialized views)
- For depths > 10, use recursive CTEs instead

### 3.2 Filter Before Traversal
Place the most selective predicate on the starting vertex. The CBO pushes predicates into the earliest plan operations when they are inside the GRAPH_TABLE WHERE clause.

Verify with EXPLAIN PLAN that the selective predicate appears as the first operation.

### 3.3 Use Bind Variables
Always use `:bind_var` syntax, never string literals. This avoids hard parsing and enables cursor sharing.

**PL/SQL requirement:** GRAPH_TABLE cannot reference PL/SQL variables directly (ORA-49028). Use `EXECUTE IMMEDIATE` with named bind variables:
```sql
EXECUTE IMMEDIATE '
  SELECT * FROM GRAPH_TABLE(my_graph
    MATCH (p IS PERSON) -[e IS KNOWS]-> (f IS PERSON)
    WHERE p.ID = :p_user_id
    COLUMNS (f.NAME AS friend_name)
  )' USING v_user_id;
```

### 3.4 Minimal Projection in COLUMNS
Only select the columns you need. Extra columns force table access even when a covering index would suffice.

Example: An index on `(src, end_date, dst)` covers a query that only needs `dst`. Adding `start_date` to COLUMNS forces a table access by rowid.

### 3.5 Avoid Multiple Variable-Length Expansions in One Query
`(a)-[e1]->{1,3}(b)-[e2]->{1,3}(c)` generates 3 × 3 = 9 sub-queries. If intermediate result sets are large, this causes combinatorial explosion.

**Solution:** Break into two queries with a CTE, or use staged processing.

### 3.6 Predicate Placement
- **Inside MATCH WHERE (preferred):** CBO pushes predicates down early, enabling index range scans on the filtered table.
- **Outside (enclosing SELECT WHERE):** May not push down, especially for complex expressions (subqueries, CASE, analytics). Always verify with EXPLAIN PLAN.

### 3.7 Hint Placement
- Hints in the COLUMNS clause are **ignored** by the optimizer.
- Place hints in the **outer SELECT**: `SELECT /*+ PARALLEL(4) */ * FROM GRAPH_TABLE(...)`.
- For targeted hints, use query block names from EXPLAIN PLAN: `/*+ INDEX(@"SEL$5ED53527" "E2" "IDX_NAME") */`.

### 3.8 Control Fan-Out with FETCH FIRST
Use `FETCH FIRST N ROWS ONLY` on any multi-hop pattern to prevent runaway result sets. Without this, high-degree vertices produce unbounded output.

### 3.9 Use DISTINCT to Eliminate Duplicate Paths
Variable-length paths (`{1,3}`) generate multiple routes to the same destination vertex. Without `DISTINCT`, duplicate rows accumulate massively — especially in dense graphs.

---

## 4. Index Strategy

*Source: `SYSTEM_PROMPT.md` §Index Strategy, `knowledge/optimization-rules/advanced-indexing.md` §1-2*

A property graph is just tables — indexing a graph means indexing FK and filter columns with the same relational fundamentals. **Stop at the lowest priority that solves the problem.**

| Priority | Type | When to Create | Typical Impact |
|----------|------|---------------|----------------|
| **P0** | PK indexes | Always present; verify they exist | Baseline |
| **P1** | Edge FK indexes on `(source_key)` and `(destination_key)` | Almost always needed | 80-99% reduction in buffer gets |
| **P2** | Single-column filter index | Only if EXPLAIN PLAN shows full table scan AND selectivity < 5% | 30-70% reduction |
| **P3** | Composite (filter + FK) | Only if P2 is insufficient AND both columns appear in same execution plan | 30-50% additional over P2 |
| **P4** | Advanced (partitioning, IOT, bitmap) | Rare; only at scale with measured problems | Variable |

**P1 detail — Bidirectional FK Coverage:**
- Forward traversals use `(source_key)` indexes; reverse traversals use `(destination_key)` indexes.
- A missing index in either direction forces a full table scan for that traversal direction.
- Trade-off: 2× write overhead on INSERTs (acceptable for append-only or low-DML graphs).

*Source: `knowledge/optimization-rules/advanced-indexing.md` §Strategy 1*

**P3 detail — Composite FK + Filter ("Graph Covering Index"):**
- Combine FK column with the most common filter predicate: e.g., `(source_key, end_date, destination_key)`.
- A single index range scan covers both the filter and the join.
- Create when the filter predicate appears in >50% of queries on that edge table.

*Source: `knowledge/optimization-rules/advanced-indexing.md` §Strategy 2*

---

## 5. Advanced Indexing Strategies

*Source: `knowledge/optimization-rules/advanced-indexing.md`*

### Strategy 1: Bidirectional FK Coverage
*(See §4 above for details.)*

### Strategy 2: Composite FK + Filter Index
*(See §4 above for details.)*

### Strategy 3: Function-Based Indexes
For expression predicates: `TRUNC(created_date)`, `UPPER(name)`, `amount * exchange_rate`.

```sql
CREATE INDEX idx_e_trunc_start ON e_uses_device(TRUNC(start_date));
```

**Create only when:**
- The expression has good selectivity (< 5%)
- The expression appears in multiple queries
- The function is deterministic

**Trade-off:** The function is evaluated on every DML operation.

### Strategy 4: Partial Indexes
Index only rows matching a specific condition to reduce index size by 80-95%.

**Oracle 23ai implementation:** Use partitioning with `INDEXING OFF` on non-target partitions, or an invisible function-based index with a CASE expression.

Only worthwhile for tables with > 100K rows.

### Strategy 5: Index-Organized Edge Tables (IOT)
*(See §2.5 above for full analysis.)*

### Strategy 6: Bitmap Indexes for Low-Cardinality Properties
For columns with 2-10 distinct values: `relationship_type`, `is_active`, `status`.

- Bitmap AND/OR operations are 10-100× faster than B-tree intersections for multi-predicate filtering.
- **NEVER use on OLTP tables:** Bitmap indexes cause row-level lock escalation on DML, creating severe contention.
- Only for read-mostly or data warehouse workloads.

### Strategy 7: Invisible Index Rotation for A/B Testing
1. Create all index candidates as `INVISIBLE`.
2. Enable with `ALTER SESSION SET OPTIMIZER_USE_INVISIBLE_INDEXES = TRUE`.
3. Test combinations by making subsets `VISIBLE`.
4. Measure elapsed time and CPU.
5. Keep the winner `VISIBLE`, `DROP` the losers.

**Important:** All invisible indexes still incur DML maintenance overhead — do not leave them permanently.

### Edge Case: JSON Properties
Standard B-tree indexes do not work on JSON path expressions. Options:
- Function-based index: `CREATE INDEX idx ON table(JSON_VALUE(properties, '$.risk_score' RETURNING NUMBER))`
- JSON search index: `CREATE SEARCH INDEX idx ON table(properties) FOR JSON`

Only investigate if TABLE ACCESS FULL appears on a table with JSON columns AND a filter on a JSON path AND the table has > 100K rows.

---

## 6. Anti-Patterns

*Source: `SYSTEM_PROMPT.md` §Anti-Patterns, `knowledge/graph-design/query-best-practices.md`, `knowledge/oracle-internals/pgq-optimizer-behavior.md`*

| # | Anti-Pattern | Consequence | Remediation | Source |
|---|-------------|-------------|-------------|--------|
| 1 | Missing `DBMS_STATS` after data load | Bad CBO plans due to missing/stale statistics | `DBMS_STATS.GATHER_TABLE_STATS` with `METHOD_OPT => 'FOR ALL COLUMNS SIZE AUTO'` | `pgq-optimizer-behavior.md` §4 |
| 2 | Over-indexing edge tables with heavy INSERT | Cumulative write overhead (5 indexes = 30-40% DML degradation) | Evaluate read improvement vs. write cost | `advanced-indexing.md` §Strategy 1 |
| 3 | PL/SQL variables inside GRAPH_TABLE | ORA-49028 at runtime | Use `EXECUTE IMMEDIATE` with named bind variables | `pgq-optimizer-behavior.md` §5 |
| 4 | Stale statistics (> 7 days, > 10% row change) | Cardinality misestimates on multi-hop patterns, wrong join orders | Regather with histograms on skewed FK columns | `pgq-optimizer-behavior.md` §4 |
| 5 | Missing histograms on skewed FK columns | Supernode degree underestimated by CBO | `METHOD_OPT => 'FOR COLUMNS SIZE AUTO column_name'` | `pgq-optimizer-behavior.md` §4 |
| 6 | Unbounded or large quantifiers (`{1,10}`) | 10 UNION ALL sub-plans, exponential intermediate rows | Reduce upper bound to minimum needed; redesign for > 4 hops | `query-best-practices.md` §1 |
| 7 | Predicates outside GRAPH_TABLE WHERE | Late filtering — optimizer cannot push down | Move predicates inside the MATCH WHERE clause | `query-best-practices.md` §6 |
| 8 | No FETCH FIRST on fan-out patterns | Runaway result sets from high-degree vertices | Add `FETCH FIRST N ROWS ONLY` | `query-best-practices.md` §(implied from patterns) |
| 9 | Bidirectional traversals without both FK indexes | 2× cost — one direction always does a full table scan | Create both `(src)` and `(dst)` indexes | `advanced-indexing.md` §Strategy 1 |
| 10 | Multiple variable-length expansions in one query | Multiplicative sub-plan explosion (e.g., 3×3 = 9) | Break into staged CTEs | `query-best-practices.md` §5 |
| 11 | Hints placed inside COLUMNS clause | Hints are silently ignored | Place hints in the outer SELECT statement | `query-best-practices.md` §7 |

---

## 7. Domain Patterns — Fraud Detection

*Source: `knowledge/graph-patterns/fraud-detection.md`*

### Pattern 1: Shared Device / Shared Card (1-hop)

**Structure:** `(u1)-[e1]->(device)<-[e2]-(u2)`

| Attribute | Value |
|-----------|-------|
| Hops | 1 |
| Joins | 2 edge + 3 vertex |
| Fan-out risk | HIGH (popular devices = 1,000+ edges) |
| Real-world frequency | HIGH (30-55% of fraud graph queries) |

**Index strategy:**
- Primary: `idx_src(source_key)`, `idx_dst(destination_key)` on each edge table
- Composite: `(source_key, end_date, destination_key)` — covers filter + both FK columns
- Key insight: `end_date IS NULL` eliminates 80-90% of historical edges

### Pattern 2: 2-Hop Device Chain (Friend of Friend)

**Structure:** `(u1)-[e1]->(d1)<-[e2]-(u2)-[e3]->(d2)<-[e4]-(u3)`

| Attribute | Value |
|-----------|-------|
| Hops | 2 |
| Joins | 4 edge + 5 vertex |
| Fan-out risk | VERY HIGH (multiplicative: avg_degree²) |
| Real-world frequency | LOW (3-5%) but HIGH DB time (11.93%) |

**Index strategy:** All FK indexes mandatory; composite `(src, end_date, dst)` on each edge table. `FETCH FIRST` required to prevent result explosion.

### Pattern 3: Triangle Detection (Circular 3-hop)

**Structure:** `(u1)-[e1]->(d)<-[e2]-(u2)-[e3]->(c)<-[e4]-(u3)-[e5]->(p)<-[e6]-(u1)`

| Attribute | Value |
|-----------|-------|
| Hops | 3 circular |
| Joins | 6 edge |
| Fan-out risk | EXTREME |
| Real-world frequency | RARE (1%) but highest cost per execution |

**Critical:** Without an anchor predicate this produces a cartesian product across all users. All FK indexes mandatory plus a highly selective anchor predicate on the starting vertex.

### Pattern 4: Temporal Change Detection (1-hop with time filter)

**Structure:** `(u1)-[e1]->(d)<-[e2]-(u2) WHERE e2.start_date > :since`

| Attribute | Value |
|-----------|-------|
| Hops | 1 |
| Fan-out risk | MEDIUM (temporal filter reduces result set) |
| Real-world frequency | MEDIUM (10% of executions) |

**Index strategy:** Composite `(destination_key, start_date)` or `(destination_key, end_date, start_date)`. Temporal predicates like `start_date > recent_date` typically filter 90-99% of rows.

### Pattern 5: High-Risk Neighbor Scoring (1-hop with vertex filter)

**Structure:** `(u1)-[e1]->(d)<-[e2]-(u2) WHERE u2.risk_score > 60`

| Attribute | Value |
|-----------|-------|
| Hops | 1 |
| Fan-out risk | LOW (risk_score filter reduces neighbors) |
| Real-world frequency | MEDIUM (5-8% of executions) |

**Index strategy:** Edge FK indexes are the primary need. Vertex index on `risk_score` only if selectivity < 5% (typically `risk_score > 60` matches 5-15% of rows).

---

## 8. Domain Patterns — Social Network

*Source: `knowledge/graph-patterns/social-network.md`*

### Pattern 1: Mutual Friends (Common Neighbors)

**Structure:** `(u1)-[e1]->(friend)<-[e2]-(u2)` (both endpoints bound)

- Fan-out risk: HIGH (popular users)
- Indexes: `follows(source_key)`, `follows(destination_key)`, composite `(source_key, is_active)`
- Core pattern for friend suggestions

### Pattern 2: Influence Propagation (N-hop Reach)

**Structure:** `(influencer)-[e1]->(f1)-[e2]->(f2)-[e3]->(f3)`

- Fan-out risk: EXTREME (1K followers × 1K followers = 1M paths at 2-hop)
- `FETCH FIRST 10000` mandatory for real-time use
- Better suited for batch pre-computation

### Pattern 3: Community Detection (Dense Subgraph / Triangles)

**Structure:** `(u1)-[e1]->(u2)-[e2]->(u3)-[e3]->(u1)` (circular 3-hop)

- Fan-out risk: EXTREME
- Key optimization: Inequality `u1.id < u2.id < u3.id` eliminates duplicate triangles (6× reduction)
- Typically batch/analytics, not real-time

### Pattern 4: Content Recommendation (Collaborative Filtering)

**Structure:** `(u1)-[e1]->(content)<-[e2]-(u2)-[e3]->(recommendation)`

- Fan-out risk: VERY HIGH (popular content × likers' content)
- Indexes: `(destination_key, source_key)` for reverse traversal efficiency
- Usually batch processing

### Pattern 5: Shortest Path Approximation

**Oracle 23ai limitation:** No `ANY SHORTEST` / `ALL SHORTEST` / `ANY CHEAPEST` path semantics.

- Must enumerate fixed hop lengths (1, 2, 3 as separate sub-plans)
- Alternative: Recursive CTEs for variable depth
- Use `FETCH FIRST 1` for existence checks (terminate early)

---

## 9. Domain Patterns — Supply Chain

*Source: `knowledge/graph-patterns/supply-chain.md`*

### Pattern 1: Supplier Dependency Chain (Multi-hop BOM)

**Structure:** `(product)-[requires]->(component)-[supplied_by]->(supplier)`

- Hops: 2, Fan-out: MEDIUM (50-200 components per product, 1-3 suppliers each)
- Indexes: `idx_requires(source_key)`, `idx_supplied_by(source_key)`, composite `(source_key, is_active)`
- Core ERP/MRP operation

### Pattern 2: Risk Propagation (Cascading Failure)

**Structure:** `(failed_supplier)<-[supplied_by]-(component)<-[requires]-(product)` — **REVERSE traversal**

- Hops: 2 reverse, Fan-out: HIGH (supplier → 500+ components → 10-50 products each)
- **KEY INSIGHT:** This is the opposite direction from Pattern 1. Requires **destination** FK indexes: `idx_supplied_by(destination_key)`, `idx_requires(destination_key)`
- Different patterns on the same graph require indexes in opposite directions

### Pattern 3: Logistics Route Optimization

**Structure:** `(origin)-[ships_to]->(warehouse)-[ships_to]->(destination)` — both endpoints bound

- Fan-out: LOW-MEDIUM (logistics networks are sparser than social/fraud)
- Both `(source_key)` and `(destination_key)` indexes equally important ("meeting in the middle")

### Pattern 4: Component Commonality Analysis

**Structure:** `(product1)-[requires]->(component)<-[requires]-(product2)`

- 1-hop via shared entity, with vertex predicate on `category`
- Vertex index on `category` only if selectivity < 5%
- Periodic analysis use case (not real-time)

---

## 10. Graph vs Relational — Decision Criteria

*Source: `knowledge/graph-patterns/use-case-assessment.md`*

### Strong Graph Indicators
- Path-dependent queries ("find all connected within N hops")
- Variable-depth traversal ("how is A connected to B?")
- Pattern matching across relationships (triangles, cycles, fan-out detection)
- Relationship-centric filtering (edge properties drive the query, not just vertex attributes)
- Multi-entity convergence ("connected to BOTH X and Y?")

### Weak Graph Indicators (keep relational)
- Primarily aggregation queries (SUM, COUNT, AVG)
- Simple key lookups in highly normalized tables
- 1:1 or 1:N relationships with no traversal
- Just "parent of X" (single-hop FK lookup)
- Write-heavy workloads with minimal read patterns

### SQL/PGQ and Aggregations
GRAPH_TABLE **does support** aggregate functions (COUNT, SUM, LISTAGG) in the COLUMNS clause, and the outer query supports GROUP BY, ORDER BY, and window functions. When recommending against graph for aggregation-heavy workloads, the correct framing is: "relational SQL is the more natural and efficient approach" — never "PGQ does not support aggregations."

### Design Steps for a New Graph
1. Identify vertices (nouns) and edges (verbs) from target queries
2. Map to existing relational tables
3. Define property graph DDL
4. Validate with a starter query + EXPLAIN PLAN
5. Apply the 8 modeling rules (§1 above)
6. Index based on execution plan analysis

---

## 11. CBO Behavior with GRAPH_TABLE

*Source: `knowledge/oracle-internals/pgq-optimizer-behavior.md`*

### 11.1 Rewrite Mechanism
- GRAPH_TABLE is expanded during the **query transformation phase** (before cost estimation).
- By execution time, it is pure relational SQL.
- V$SQL_PLAN shows standard operations: TABLE ACCESS, INDEX RANGE SCAN, HASH JOIN, NESTED LOOPS — never "graph traversal."
- `IS label` resolves to specific tables; multiple labels generate `UNION ALL`.

### 11.2 Join Order for Multi-Hop Patterns
- **With FK indexes:** CBO selects left-deep nested loops from the most selective vertex predicate (optimal).
- **Without edge FK indexes:** Falls back to hash joins — massive buffer gets and temp space consumption on large edge tables.
- **Cardinality estimation is critical:** If overestimated, CBO chooses hash joins (wasteful on selective patterns). If underestimated, nested loops on huge sets (even worse).
- Star transformation does NOT apply to GRAPH_TABLE expansions.

### 11.3 Predicate Pushdown
| Predicate Location | Pushdown Behavior |
|--------------------|-------------------|
| Anchor vertex property (inside WHERE) | Pushed to vertex table access reliably |
| Edge property (inside WHERE) | Pushed to edge table access; combined with index = dramatic reduction |
| Non-anchor vertex property | Applied AFTER join — cannot be pushed earlier |
| Cross-table predicate (e.g., `u1.id <> u2.id`) | Applied as join filter |
| Predicate OUTSIDE GRAPH_TABLE | May not push down — move inside WHERE when possible |

### 11.4 Statistics Impact
- **Missing stats:** Dynamic sampling (level 2) produces inaccurate estimates for skewed degree distributions.
- **Stale stats (> 7 days, > 10% row change):** CBO uses outdated estimates → suboptimal join orders.
- **Histograms:** Critical for edge FK columns with skewed degree (supernodes). Without them, CBO assumes uniform distribution.
- **Extended statistics:** For composite predicates like `WHERE src = :id AND end_date IS NULL`, create with `DBMS_STATS.CREATE_EXTENDED_STATS`.
- **Adaptive statistics (23ai):** Can learn from execution feedback but do not fully solve the supernode problem.

### 11.5 Variable-Length Path Expansion
- `{1,5}` generates a UNION ALL of 5 fixed-length sub-plans, each optimized independently.
- Maximum upper bound: 10.
- Without FK indexes, `{1,5}` means 5 full table scans — catastrophic.
- For depths > 10, use recursive CTEs.

### 11.6 Execution Plan Caching
- **After creating indexes:** Force a hard parse — new session, alter SQL with a comment change, or gather stats.
- **Cursor invalidation:** DDL on referenced tables (CREATE INDEX, GATHER_TABLE_STATS, ALTER TABLE) invalidates existing cursors.
- **SQL Plan Baselines:** `DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE` works normally with GRAPH_TABLE queries. Use `FIXED = 'YES'` to prevent regression.
- **Adaptive cursor sharing:** May create new child cursors when bind peeking produces different plans for different value distributions.

---

## 12. PGX vs SQL/PGQ — When to Use Each

*Source: `knowledge/oracle-internals/pgx-vs-sqlpgq.md`*

### SQL/PGQ (GRAPH_TABLE)
- Operational/transactional queries with known start vertex
- High-selectivity queries with aggressive filtering
- Real-time data (reads directly from base tables, sees latest committed changes)
- SQL integration (JOIN non-graph tables, embed in views, call from PL/SQL)
- Works on ADB-S (Serverless) and Free tier

**Limitations:** No unbounded path search, no built-in graph algorithms, no ANY/ALL SHORTEST, max quantifier bound = 10, variable-length paths generate UNION ALL (performance degrades with depth).

### PGX (Graph Server)
- Graph algorithms: PageRank, betweenness/closeness/eigenvector centrality
- Community detection: Louvain, label propagation, connected components
- Shortest path: Dijkstra, Bellman-Ford, A*
- Full-graph analytics touching every vertex/edge
- Exploratory analysis

**Architecture:** Separate Java process that loads the graph into memory (snapshot). Queries use PGQL (not SQL/PGQ).

**Availability:**
| Platform | PGX Available |
|----------|--------------|
| ADB-D (Dedicated) | Yes (Graph Server included as managed service) |
| On-premises Enterprise | Yes (with Graph Server installed) |
| ADB-S (Serverless) | **No** |
| Free tier | **No** |

**Memory sizing:** ~100 bytes/vertex + ~64 bytes/edge + property overhead. A 10M-vertex, 100M-edge graph with 3 numeric properties requires approximately 10 GB heap.

### Hybrid Approach (Recommended for algorithm + traversal workloads)
1. **PGX (batch/nightly):** Compute PageRank, community IDs, centrality scores.
2. **Store results:** Write computed scores back to the database as vertex/edge properties.
3. **SQL/PGQ (real-time):** Use pre-computed scores in traversal queries. These scores can be indexed for fast filtering.

---

## 13. Auto Indexing and Graph Workloads

*Source: `knowledge/optimization-rules/auto-indexing-graph.md`*

### What Auto Indexing CAN Do
- Detect missing single-column indexes on frequently accessed columns
- Identify edge FK columns if the workload has run long enough
- Create B-tree indexes on high-selectivity columns
- Validate improvement with SQL Performance Analyzer before committing

### What Auto Indexing CANNOT Do
- Create composite indexes that understand graph traversal semantics
- Recommend indexes proactively before a workload exists
- Understand fan-out patterns (supernodes)
- Create partial, function-based, or bitmap indexes
- Coordinate indexes across multiple tables for multi-table graph patterns
- Evaluate cumulative DML overhead across all indexes on a table

### Risks
| Risk | Description |
|------|-------------|
| Resource consumption | SQL Performance Analyzer runs on the same instance, competes with user workload |
| Cumulative write overhead | Edge tables have high INSERT rates; each auto-created index adds overhead |
| Storage waste | Invisible auto indexes with marginal benefit kept permanently |
| Low-selectivity pollution | Creates indexes on columns like `channel` (4 values) if one query benefits |
| Ad-hoc query pollution | A one-off analytical query triggers a permanent index for a non-recurring pattern |

### Recommended Interaction Pattern
- **Day 0:** Manually create FK indexes + key composites based on graph structure analysis.
- **Day 7+:** Auto Indexing adds complementary single-column indexes based on observed workload.
- **High-DML edge tables:** Consider excluding from Auto Indexing to prevent over-indexing.

### Alert Thresholds
- **> 7 indexes per edge table:** Flag as over-indexed.
- **Invisible auto indexes with no usage > 30 days:** Candidates for DROP.

---

## 14. SQL/PGQ Feature Matrix

*Source: `knowledge/oracle-internals/official-documentation-reference.md`*

### Supported in Oracle 23ai / 26ai
- `GRAPH_TABLE`, `MATCH`, fixed-length patterns, bounded quantifiers `{n,m}` (max m = 10)
- `WHERE` inside GRAPH_TABLE, `COLUMNS` projections, aggregate functions in COLUMNS
- `AS OF SCN` / `AS OF TIMESTAMP` (flashback queries on graph)
- Bind variables, PL/SQL functions, SQL hints (on outer SELECT)
- JSON dot-notation on properties
- Cross-schema queries, multiple path patterns (implicit INNER JOIN), cyclic patterns
- `ONE ROW PER MATCH` (default), `VERTEX_ID()`, `EDGE_ID()`
- Label expressions (`IS label1 | label2`)

### Additional with Graph Server 25.1+
- Path variables, `ONE ROW PER VERTEX`, `ONE ROW PER STEP`
- `MATCHNUM()`, `PATH_NAME()`, `ELEMENT_NUMBER()`
- `binding_count()`, `IS [NOT] LABELED`, `PROPERTY_EXISTS()`
- `SOURCE` / `DESTINATION` predicates, `LISTAGG` with path iteration

### NOT Supported
- `ANY` / `ALL` / `ALL SHORTEST` / `ANY CHEAPEST` path goals
- `COST` / `TOTAL_COST` clauses
- Inline subqueries or LATERAL views inside GRAPH_TABLE
- SQL Macros inside GRAPH_TABLE
- Unbounded quantifiers (`{1,}`, `*`, `+`)
- Variable-length path goal semantics (shortest/cheapest)

### ONE ROW PER Cardinality Impact
| Mode | Rows Produced | Use Case |
|------|--------------|----------|
| `ONE ROW PER MATCH` | 1 per pattern match | Default, most queries |
| `ONE ROW PER VERTEX(v)` | N+1 (N = edges in path) | Iterating vertices along a path |
| `ONE ROW PER STEP(v1, e, v2)` | N (N = edges in path) | Iterating edges along a path |

Cardinality multiplier affects sort/hash aggregation memory and temp tablespace usage.

---

*Generated from the Oracle Graph DBA Advisor knowledge base.*
*For maintenance procedures and version tracking, see `knowledge/FRESHNESS.md`.*
