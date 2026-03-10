---
verified_version: "23ai"
last_verified: "2026-03-10"
oracle_doc_urls:
  - https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/manage-auto-indexes.html
next_review: "on_new_oracle_release"
confidence: "high"
version_sensitive_facts:
  - "Auto indexes created HIDDEN by default in 23ai"
  - "Auto Indexing available on ADB-S and ADB-D only"
---

# Auto Indexing and Graph Workloads

## How Auto Indexing Works

Oracle Auto Indexing (available on ADB-S and ADB-D) monitors SQL workload via `V$SQL`, identifies candidates, creates indexes as INVISIBLE, validates improvement, and either makes them VISIBLE (benefit confirmed) or drops them (no benefit or regression).

In 23ai, auto indexes are created as **HIDDEN** by default — they're invisible to the optimizer until validated, and instantly reversible. This is the same safety model the advisor uses with INVISIBLE indexes.

## What Auto Indexing Can and Cannot Do for Graphs

### What it CAN do
- Detect missing single-column indexes on frequently accessed columns
- Identify edge FK columns (source_key, destination_key) that need indexes — IF enough graph queries have already run
- Create B-tree indexes on high-selectivity filter columns
- Validate that a new index actually improves performance before committing

### What it CANNOT do
- **Create composite indexes that match graph semantics**: Auto Indexing doesn't understand that `(is_suspicious, to_account_id)` is better than `(is_suspicious)` alone because it covers both the edge filter AND the destination vertex join. It sees SQL access patterns, not graph traversal patterns.
- **Proactively recommend indexes before workload exists**: It needs real queries in V$SQL to analyze. The advisor can recommend from graph structure alone.
- **Understand fan-out patterns**: Auto Indexing doesn't know that a vertex with 500K edges is a supernode that needs special indexing. It just sees a table with 500K rows.
- **Create partial indexes, function-based indexes, or bitmap indexes**: Auto Indexing only creates standard B-tree indexes.
- **Coordinate indexes across tables for graph patterns**: A graph traversal pattern like `(a)-[e1]->(b)-[e2]->(c)` involves indexes on e1 AND e2 — Auto Indexing evaluates each table independently.
- **Evaluate cumulative DML overhead**: It tests each index individually. Five indexes that each pass the benefit test can collectively degrade INSERT performance by 30-40%.

## Risks and Disadvantages

The advisor should actively monitor and warn about these:

### Resource Consumption
Auto Indexing runs SQL Performance Analyzer (SPA) internally for each candidate index. This means:
- CPU and I/O consumed **on the same instance** as the user's workload
- Each candidate is physically created (HIDDEN), tested, then either kept or dropped — even the rejected ones generate write I/O
- On ADB with low ECPU count (2-4), this competes with production queries

**What the advisor should check:**
```sql
-- Time spent on Auto Indexing activity (last 7 days)
SELECT
    task_name,
    status,
    ROUND(EXTRACT(MINUTE FROM (end_time - start_time)) +
          EXTRACT(HOUR FROM (end_time - start_time)) * 60, 1) AS duration_min,
    start_time, end_time
FROM DBA_AUTO_INDEX_EXECUTIONS
WHERE start_time > SYSDATE - 7
ORDER BY start_time DESC;
```

### Cumulative Write Overhead
The most insidious problem for graph workloads. Edge tables often have high INSERT rates (streaming transactions). Each auto index on an edge table adds overhead to every INSERT:

**What the advisor should check:**
```sql
-- Count total indexes (auto + manual) on graph edge tables
-- Flag if total > 5 per edge table
SELECT
    t.table_name,
    COUNT(i.index_name) AS total_indexes,
    SUM(CASE WHEN i.index_name LIKE 'SYS_AI%' THEN 1 ELSE 0 END) AS auto_indexes,
    SUM(CASE WHEN i.index_name NOT LIKE 'SYS_AI%' THEN 1 ELSE 0 END) AS manual_indexes,
    t.num_rows,
    CASE
        WHEN COUNT(i.index_name) > 7 THEN 'OVER-INDEXED'
        WHEN COUNT(i.index_name) > 5 THEN 'REVIEW'
        ELSE 'OK'
    END AS status
FROM user_tables t
JOIN user_indexes i ON t.table_name = i.table_name
WHERE t.table_name IN (
    SELECT object_name FROM USER_PG_ELEMENTS WHERE element_kind = 'EDGE'
)
GROUP BY t.table_name, t.num_rows
ORDER BY total_indexes DESC;
```

### Storage Waste from Invisible Auto Indexes
Auto Indexing may keep INVISIBLE indexes that showed marginal benefit — not enough to activate but not negative enough to drop. These consume space silently:

**What the advisor should check:**
```sql
-- Invisible auto indexes and their space consumption
SELECT
    ai.index_name,
    ai.table_name,
    ai.index_columns,
    ai.visibility,
    ROUND(seg.bytes/1024/1024, 1) AS size_mb,
    ai.last_modified
FROM DBA_AUTO_INDEX_IND_ACTIONS ai
JOIN USER_SEGMENTS seg ON ai.index_name = seg.segment_name
WHERE ai.visibility = 'INVISIBLE'
  AND ai.status = 'VALID'
ORDER BY seg.bytes DESC;
```

### Low-Selectivity Index Creation
Auto Indexing may create indexes on columns like `channel` (4 values) or `currency` (3 values) because a specific query benefits. For graph tables, these indexes add write overhead with minimal read benefit across the broader workload:

**What the advisor should flag:**
```sql
-- Auto indexes with low distinct values (potential waste)
SELECT
    ai.index_name,
    ai.table_name,
    ai.index_columns,
    cs.num_distinct,
    t.num_rows,
    ROUND(cs.num_distinct / GREATEST(t.num_rows, 1) * 100, 2) AS selectivity_pct,
    CASE
        WHEN cs.num_distinct < 10 THEN 'LOW SELECTIVITY — review benefit'
        ELSE 'OK'
    END AS assessment
FROM DBA_AUTO_INDEX_IND_ACTIONS ai
JOIN USER_TAB_COL_STATISTICS cs ON ai.table_name = cs.table_name
    AND ai.index_columns = cs.column_name
JOIN USER_TABLES t ON ai.table_name = t.table_name
WHERE ai.table_name IN (
    SELECT object_name FROM USER_PG_ELEMENTS WHERE element_kind = 'EDGE'
)
  AND ai.status != 'DROPPED'
ORDER BY cs.num_distinct;
```

### Ad-hoc Query Pollution
If a DBA runs a one-time analytical query, Auto Indexing may create a permanent index for a pattern that won't recur. The advisor should check the SQL that triggered each auto index:

```sql
-- What SQL triggered each auto index?
SELECT
    ai.index_name,
    ai.table_name,
    ai.index_columns,
    s.sql_text,
    s.executions,
    CASE
        WHEN s.executions < 5 THEN 'LOW EXECUTION COUNT — may be ad-hoc'
        ELSE 'Recurring query'
    END AS pattern_confidence
FROM DBA_AUTO_INDEX_IND_ACTIONS ai
JOIN V$SQL s ON s.sql_id = ai.sql_id
WHERE ai.table_name IN (
    SELECT object_name FROM USER_PG_ELEMENTS WHERE element_kind = 'EDGE'
)
  AND ai.status = 'VISIBLE'
ORDER BY s.executions;
```

## Interaction Patterns

### Pattern 1: Auto Indexing + Advisor = Best Coverage

```
Timeline:
  Day 0: Deploy graph (no indexes, no workload)
    └── Advisor: "Based on your graph structure, create these 5 indexes"
  Day 1-7: Workload runs
    └── Auto Indexing: "I observed these SQL patterns, adding 2 more indexes"
  Day 30: Review
    └── Advisor: "Auto Indexing added idx on transfers(amount) — good.
                  But it missed the composite on (is_suspicious, merchant_id).
                  And the idx on transfers(channel) has low selectivity — consider dropping."
```

### Pattern 2: Auto Indexing Created Something Suboptimal

Auto Indexing may create:
```sql
-- Auto created (single column, decent but not optimal):
CREATE INDEX SYS_AI_abc123 ON transfers(is_suspicious);
```

The advisor recommends:
```sql
-- Composite (covers filter + FK join in one scan):
CREATE INDEX idx_transfers_susp_merch ON transfers(is_suspicious, merchant_id);

-- The auto index becomes redundant — the composite covers its use case
-- Recommend dropping the auto index:
ALTER INDEX SYS_AI_abc123 INVISIBLE;
-- Monitor for regressions, then:
-- DROP INDEX SYS_AI_abc123;
```

### Pattern 3: Disable Auto Indexing for Specific Tables

For INSERT-heavy edge tables (streaming graphs), Auto Indexing may create too many indexes. Exclude specific tables:

```sql
-- Exclude high-DML edge table from Auto Indexing
EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_SCHEMA', 'HR', NULL, TRUE);
```

## Auto Indexing Configuration Recommendations for Graph Workloads

| Setting | Recommended Value | Why |
|---------|-------------------|-----|
| `AUTO_INDEX_MODE` | `IMPLEMENT` | Let it create indexes (not just report) |
| `AUTO_INDEX_REPORT_RETENTION` | `31` (days) | Keep reports long enough to correlate with graph workload changes |
| `AUTO_INDEX_SPACE_BUDGET_PERCENT` | `50` (default) | Graph tables benefit from indexes — don't restrict space too aggressively |
| `AUTO_INDEX_DEFAULT_TABLESPACE` | Same as graph tables | Keep auto indexes collocated with graph data |

## Monitoring Auto Index Impact on Graph Queries

```sql
-- Check if auto indexes are being used by graph queries
SELECT
    ai.index_name,
    ai.table_name,
    ai.index_columns,
    u.total_access_count,
    u.last_used
FROM DBA_AUTO_INDEX_IND_ACTIONS ai
JOIN DBA_INDEX_USAGE u ON ai.index_name = u.name
WHERE ai.table_name IN (
    SELECT object_name FROM USER_PG_ELEMENTS
)
AND ai.status = 'VISIBLE'
ORDER BY u.total_access_count DESC;
```
