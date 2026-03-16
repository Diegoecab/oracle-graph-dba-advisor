---
verified_version: "23ai"
last_verified: "2026-03-09"
oracle_doc_urls:
  - https://docs.oracle.com/en/database/oracle/property-graph/25.3/spgdg/
next_review: "on_new_oracle_release"
confidence: "high"
---

# Advanced Indexing Strategies for Property Graphs

Beyond the 5 base strategies in SYSTEM_PROMPT.md, these advanced techniques address specific performance challenges in large-scale SQL/PGQ deployments.

## Contents
- [Strategy 1: Bidirectional FK Coverage](#strategy-1-bidirectional-fk-coverage)
- [Strategy 2: Composite FK + Filter Index (The "Graph Covering Index")](#strategy-2-composite-fk--filter-index-the-graph-covering-index)
- [Strategy 3: Function-Based Indexes for Derived Predicates](#strategy-3-function-based-indexes-for-derived-predicates)
- [Strategy 4: Partial Indexes via WHERE Clause (Oracle 23ai)](#strategy-4-partial-indexes-via-where-clause-oracle-23ai)
- [Strategy 5: Index-Organized Edge Tables (IOT)](#strategy-5-index-organized-edge-tables-iot)
- [Strategy 6: Bitmap Indexes for Low-Cardinality Edge Properties](#strategy-6-bitmap-indexes-for-low-cardinality-edge-properties)
- [Strategy 7: Invisible Index Rotation for A/B Testing](#strategy-7-invisible-index-rotation-for-ab-testing)
- [Edge Case: JSON Properties in Graph Tables](#edge-case-json-properties-in-graph-tables)
- [Edge Case: Vector Properties](#edge-case-vector-properties)

---

## Strategy 1: Bidirectional FK Coverage

**Problem**: Graph traversals go both forward (SRC→DST) and reverse (DST→SRC). Most DBAs only create one direction.

**Rule**: For every edge table, always create **both** SRC and DST indexes as a pair. A traversal pattern `(a)-[e]->(b)` needs `idx_e_src`, while `(b)<-[e]-(a)` needs `idx_e_dst`. Missing either direction forces a full table scan on the reverse traversal.

**DDL**:
```sql
CREATE INDEX idx_e_uses_device_src ON e_uses_device(src);
CREATE INDEX idx_e_uses_device_dst ON e_uses_device(dst);
```

**Expected Impact**: 80-99% reduction in buffer gets for any query using the reverse direction.

**Trade-off**: Two indexes per edge table = 2x write overhead on INSERTs. For append-only edge tables (common in fraud/social), this is acceptable. For high-update edge tables, consider partial indexes or deferred index maintenance.

---

## Strategy 2: Composite FK + Filter Index (The "Graph Covering Index")

**Problem**: Most graph queries combine an FK join (SRC or DST) with a filter predicate (`end_date IS NULL`, `is_active = 'Y'`). Two separate index accesses (one for FK, one for filter) result in an index intersection or a filter on top of the FK scan.

**Rule**: When a filter predicate appears in >50% of queries touching an edge table, create a composite index that combines the FK column with the filter column. Put the FK column first (for join access), then the filter column (for predicate elimination).

**DDL**:
```sql
-- Covers: WHERE src = :id AND end_date IS NULL
CREATE INDEX idx_e_uses_device_src_end ON e_uses_device(src, end_date);

-- Full coverage: also includes DST to avoid table access
CREATE INDEX idx_e_uses_device_src_end_dst ON e_uses_device(src, end_date, dst);
```

**Expected Impact**: 30-50% additional improvement over simple FK index, because the filter is evaluated during the index range scan (no table access needed for the filter).

**Trade-off**: Wider indexes = more storage, slightly slower INSERTs. The 3-column composite `(src, end_date, dst)` is the sweet spot for most graph edge tables — it covers the source join, the temporal filter, and the destination key.

---

## Strategy 3: Function-Based Indexes for Derived Predicates

**Problem**: Some graph queries use expressions in predicates: `TRUNC(created_date)`, `UPPER(name)`, `amount * exchange_rate > threshold`. Oracle cannot use a B-tree index on the base column for expression-based predicates.

**Rule**: Create a function-based index when the expression predicate has good selectivity and appears in multiple queries.

**DDL**:
```sql
-- For TRUNC(start_date) = DATE '2024-01-15'
CREATE INDEX idx_e_trunc_start ON e_uses_device(TRUNC(start_date));

-- For NVL(end_date, DATE '9999-12-31') comparisons
CREATE INDEX idx_e_end_nvl ON e_uses_device(NVL(end_date, DATE '9999-12-31'));
```

**Expected Impact**: Same as a regular B-tree index — depends on selectivity. Only create when selectivity < 5%.

**Trade-off**: Function-based indexes must be deterministic. Oracle re-evaluates the function on every DML. Avoid expensive functions (PL/SQL calls, complex calculations).

---

## Strategy 4: Partial Indexes via WHERE Clause (Oracle 23ai)

**Problem**: An index on `risk_score` is useful only for the 5% of rows where `risk_score > 60`. The other 95% of index entries are never accessed, wasting space and slowing DML.

**Rule**: In Oracle 23ai, use partial indexing to index only the rows that match a specific condition. This reduces index size and DML overhead.

**DDL**:
```sql
-- Only index high-risk users
ALTER TABLE n_user MODIFY PARTITION BY LIST (is_blocked) (
  PARTITION p_blocked VALUES ('Y'),
  PARTITION p_active VALUES ('N')
);

CREATE INDEX idx_n_user_risk_partial ON n_user(risk_score)
  LOCAL (PARTITION p_blocked, PARTITION p_active INDEXING OFF);
```

**Alternative (simpler)**: Use an invisible function-based index on a CASE expression:
```sql
CREATE INDEX idx_n_user_high_risk ON n_user(
  CASE WHEN risk_score > 60 THEN risk_score END
);
```

**Expected Impact**: 80-95% smaller index, faster DML, same query performance for the targeted predicate.

**Trade-off**: Partial indexes require partitioned tables or creative function-based approaches. Not worth it for small tables (<100K rows).

---

## Strategy 5: Index-Organized Edge Tables (IOT)

**Problem**: Edge tables are frequently accessed by SRC (or DST) and the data is scattered across blocks. Each edge lookup requires a table access by rowid after the index scan.

**Rule**: For edge tables where the primary access pattern is always by SRC (or DST), consider an Index-Organized Table (IOT) with the primary key as `(src, dst)` or `(src, end_date, dst)`. This physically clusters all edges from the same source vertex together, eliminating the table access by rowid.

**DDL**:
```sql
CREATE TABLE e_uses_device (
  src       NUMBER NOT NULL,
  dst       NUMBER NOT NULL,
  start_date TIMESTAMP DEFAULT SYSTIMESTAMP,
  end_date   TIMESTAMP,
  last_updated TIMESTAMP DEFAULT SYSTIMESTAMP,
  CONSTRAINT pk_e_uses_device PRIMARY KEY (src, end_date, dst)
) ORGANIZATION INDEX
  INCLUDING end_date
  OVERFLOW;
```

**Expected Impact**: Eliminates all table access by rowid for SRC-based traversals. 40-60% reduction in physical reads for 1-hop queries.

**Trade-off**:
- IOTs only have one physical ordering — reverse traversals (by DST) still need a secondary index
- DML is more expensive (inserts must maintain physical ordering)
- Not suitable for tables with frequent updates to non-key columns
- Best for append-only edge tables with primarily SRC-based access

---

## Strategy 6: Bitmap Indexes for Low-Cardinality Edge Properties

**Problem**: Edge properties like `relationship_type`, `is_active`, `status` have very low cardinality (2-10 distinct values). B-tree indexes on these columns have large leaf blocks with many rowids per key value.

**Rule**: For OLAP/batch graph workloads (not OLTP), bitmap indexes on low-cardinality edge properties can dramatically speed up queries that combine multiple such predicates with AND/OR.

**DDL**:
```sql
-- Only for read-heavy / batch workloads
CREATE BITMAP INDEX bix_e_relationship_type ON e_generic_edge(relationship_type);
CREATE BITMAP INDEX bix_e_is_active ON e_generic_edge(is_active);
```

**Expected Impact**: Bitmap AND/OR operations are 10-100x faster than B-tree index intersections for low-cardinality columns.

**Trade-off**:
- **Never use bitmap indexes on OLTP tables** — bitmap indexes cause row-level lock escalation on DML (a single INSERT can lock entire bitmap segments, blocking other sessions)
- Only suitable for read-mostly edge tables or data warehouse workloads
- Consider bitmap join indexes if the low-cardinality column is on a vertex table that's always joined

---

## Strategy 7: Invisible Index Rotation for A/B Testing

**Problem**: You want to test multiple index configurations to find the optimal set, but creating and dropping indexes is slow and disruptive.

**Rule**: Create all candidate indexes as INVISIBLE. Then systematically test combinations by making subsets VISIBLE (or using `OPTIMIZER_USE_INVISIBLE_INDEXES = TRUE`) and measuring workload performance.

**Workflow**:
```sql
-- Phase 1: Create all candidates as INVISIBLE
CREATE INDEX idx_candidate_1 ON e_uses_device(src, end_date) INVISIBLE;
CREATE INDEX idx_candidate_2 ON e_uses_device(src, end_date, dst) INVISIBLE;

-- Phase 2: Test candidate 1
ALTER INDEX idx_candidate_1 VISIBLE;
-- Run workload, measure elapsed/CPU
ALTER INDEX idx_candidate_1 INVISIBLE;

-- Phase 3: Test candidate 2
ALTER INDEX idx_candidate_2 VISIBLE;
-- Run workload, measure elapsed/CPU
ALTER INDEX idx_candidate_2 INVISIBLE;

-- Phase 4: Make the winner visible, drop the loser
ALTER INDEX idx_candidate_2 VISIBLE;
DROP INDEX idx_candidate_1;
```

**Expected Impact**: Enables data-driven index selection without production disruption.

**Trade-off**: All INVISIBLE indexes still incur DML overhead (they are maintained on every INSERT/UPDATE/DELETE). Don't leave unused invisible indexes permanently — either promote to VISIBLE or DROP.

---

## Edge Case: JSON Properties in Graph Tables

Some graph designs store variable properties as JSON columns on vertex or edge tables. This is a legitimate Oracle 23ai pattern but is an **edge case for indexing**.

### When It Matters

Only when a GRAPH_TABLE query filters on a value INSIDE the JSON column:
```sql
-- Query filtering on a JSON property inside the MATCH clause
SELECT * FROM GRAPH_TABLE(my_graph
    MATCH (a)-[e]->(b)
    WHERE JSON_VALUE(e.properties, '$.risk_score' RETURNING NUMBER) > 0.8
    COLUMNS (...)
);
```

### What to Recommend

1. **First ask: should this be a regular column?** If `risk_score` is filtered frequently, it should be a dedicated `NUMBER` column, not buried in JSON. Thinner tables, simpler indexes, better optimizer estimates.

2. **If JSON must stay**: Create a function-based index on the JSON path:
```sql
CREATE INDEX idx_edge_risk ON edge_table(
    JSON_VALUE(properties, '$.risk_score' RETURNING NUMBER)
);
```

3. **For multi-path search**: A JSON search index covers all paths but is heavy:
```sql
CREATE SEARCH INDEX idx_edge_json ON edge_table(properties) FOR JSON;
```
Only recommend this if the user queries multiple different JSON paths unpredictably.

### The Advisor's Default Stance

Do NOT proactively check for JSON indexing opportunities. Only investigate if:
- A query plan shows TABLE ACCESS FULL on a table with JSON columns AND
- The filter is on a JSON path expression AND
- The table has > 100K rows

In most graph workloads, JSON properties are accessed AFTER the traversal (in the COLUMNS projection), not during filtering. Indexing them would be waste.

## Edge Case: Vector Properties

If vertex or edge tables contain `VECTOR` columns (embeddings), these are indexed with vector-specific indexes (`CREATE VECTOR INDEX ... ORGANIZATION NEIGHBOR PARTITIONS`), not B-tree indexes.

This is outside the scope of graph traversal optimization — it belongs to RAG / similarity search workflows. The advisor should note: "I see a VECTOR column on [table]. Vector indexing is a separate domain from graph traversal indexing. If you need similarity search over graph properties, consult the Oracle AI Vector Search documentation."
