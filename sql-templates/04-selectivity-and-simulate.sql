-- ============================================================
-- SELECTIVITY TEMPLATES — Quantify Index Benefit
-- ============================================================


-- ┌──────────────────────────────────────────────────────────┐
-- │ SELECTIVITY-01: Detailed column selectivity              │
-- └──────────────────────────────────────────────────────────┘
-- For a specific table and column, shows full stats.
-- Replace 'TABLE_NAME' and 'COLUMN_NAME'.

SELECT
    cs.table_name,
    cs.column_name,
    cs.data_type,
    t.num_rows                                            AS table_rows,
    cs.num_distinct,
    cs.num_nulls,
    cs.density,
    cs.low_value,
    cs.high_value,
    cs.histogram,
    cs.num_buckets,
    ROUND(1 / NULLIF(cs.num_distinct,0) * 100, 4)        AS equality_selectivity_pct,
    ROUND(t.num_rows / NULLIF(cs.num_distinct,0))         AS avg_rows_per_value,
    ROUND(t.num_rows * cs.density)                        AS est_rows_per_access
FROM user_tab_col_statistics cs
JOIN user_tables t ON cs.table_name = t.table_name
WHERE cs.table_name = 'TABLE_NAME'
  AND cs.column_name = 'COLUMN_NAME';


-- ┌──────────────────────────────────────────────────────────┐
-- │ SELECTIVITY-02: Value distribution for edge properties   │
-- └──────────────────────────────────────────────────────────┘
-- Shows actual value distribution. Critical for understanding
-- if a "selective-looking" column is actually skewed.
-- Replace 'TABLE_NAME' and 'COLUMN_NAME'.

SELECT
    COLUMN_NAME AS value,
    COUNT(*)    AS row_count,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM TABLE_NAME) * 100, 2) AS pct_of_total,
    CASE
        WHEN COUNT(*) / (SELECT COUNT(*) FROM TABLE_NAME) < 0.01 THEN '★ Excellent (<1%)'
        WHEN COUNT(*) / (SELECT COUNT(*) FROM TABLE_NAME) < 0.05 THEN '✓ Good (<5%)'
        WHEN COUNT(*) / (SELECT COUNT(*) FROM TABLE_NAME) < 0.15 THEN '~ Marginal (<15%)'
        ELSE '✗ Poor (>15%)'
    END AS index_suitability
FROM TABLE_NAME
GROUP BY COLUMN_NAME
ORDER BY row_count DESC;

-- NOTE: For the agent, dynamically construct this query:
-- SELECT is_suspicious, COUNT(*), ...
-- FROM transfers
-- GROUP BY is_suspicious
-- ORDER BY 2 DESC;


-- ┌──────────────────────────────────────────────────────────┐
-- │ SELECTIVITY-03: Composite index opportunity analysis     │
-- └──────────────────────────────────────────────────────────┘
-- For graph queries with multiple predicates on the same edge
-- table, shows combined selectivity of column pairs.
-- Replace TABLE_NAME, COL1, COL2.

-- Combined selectivity of two columns
SELECT
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN COL1 = 'VALUE1' THEN 1 END) AS col1_matches,
    COUNT(CASE WHEN COL2 = 'VALUE2' THEN 1 END) AS col2_matches,
    COUNT(CASE WHEN COL1 = 'VALUE1' AND COL2 = 'VALUE2' THEN 1 END) AS both_match,
    ROUND(COUNT(CASE WHEN COL1 = 'VALUE1' THEN 1 END) / COUNT(*) * 100, 2) AS col1_selectivity_pct,
    ROUND(COUNT(CASE WHEN COL2 = 'VALUE2' THEN 1 END) / COUNT(*) * 100, 2) AS col2_selectivity_pct,
    ROUND(COUNT(CASE WHEN COL1 = 'VALUE1' AND COL2 = 'VALUE2' THEN 1 END) / COUNT(*) * 100, 4) AS combined_selectivity_pct
FROM TABLE_NAME;

-- NOTE: For the agent, construct dynamically, e.g.:
-- SELECT COUNT(*) AS total,
--        COUNT(CASE WHEN is_suspicious = 'Y' THEN 1 END) AS suspicious,
--        COUNT(CASE WHEN amount > 9000 THEN 1 END) AS high_value,
--        COUNT(CASE WHEN is_suspicious = 'Y' AND amount > 9000 THEN 1 END) AS both
-- FROM transfers;


-- ┌──────────────────────────────────────────────────────────┐
-- │ SELECTIVITY-04: Edge degree distribution                 │
-- └──────────────────────────────────────────────────────────┘
-- Shows how many edges per vertex (degree distribution).
-- High-degree vertices cause "fan-out explosion" in multi-hop
-- traversals. Understanding this guides index strategy.
-- Replace EDGE_TABLE, SOURCE_KEY, VERTEX_TABLE, VERTEX_PK.

SELECT
    degree_bucket,
    COUNT(*) AS vertex_count,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 1) AS pct_of_vertices
FROM (
    SELECT
        v.VERTEX_PK,
        COUNT(e.SOURCE_KEY) AS out_degree,
        CASE
            WHEN COUNT(e.SOURCE_KEY) = 0    THEN '0 (isolated)'
            WHEN COUNT(e.SOURCE_KEY) <= 5   THEN '1-5 (low)'
            WHEN COUNT(e.SOURCE_KEY) <= 20  THEN '6-20 (medium)'
            WHEN COUNT(e.SOURCE_KEY) <= 100 THEN '21-100 (high)'
            ELSE '100+ (hub/supernode)'
        END AS degree_bucket
    FROM VERTEX_TABLE v
    LEFT JOIN EDGE_TABLE e ON v.VERTEX_PK = e.SOURCE_KEY
    GROUP BY v.VERTEX_PK
)
GROUP BY degree_bucket
ORDER BY
    CASE degree_bucket
        WHEN '0 (isolated)' THEN 1
        WHEN '1-5 (low)' THEN 2
        WHEN '6-20 (medium)' THEN 3
        WHEN '21-100 (high)' THEN 4
        ELSE 5
    END;

-- NOTE: Agent constructs dynamically, e.g.:
-- FROM users v LEFT JOIN follows e ON v.user_id = e.follower_id


-- ============================================================
-- SIMULATE TEMPLATES — Test Index Impact Without Risk
-- ============================================================


-- ┌──────────────────────────────────────────────────────────┐
-- │ SIMULATE-01: Compare plans with/without index hint       │
-- └──────────────────────────────────────────────────────────┘
-- Step 1: Get current plan (no hint)
-- Step 2: Get hypothetical plan with INDEX hint
-- Compare cost and operation types.
--
-- NOTE: This only works for hint-able queries. For GRAPH_TABLE
-- queries, the expanded SQL is what gets hinted. The agent
-- should extract the expanded form from V$SQL_PLAN and hint
-- the underlying table access directly.

-- Current plan (baseline):
EXPLAIN PLAN SET STATEMENT_ID = 'SIM_BASELINE' FOR
/* PASTE_THE_GRAPH_QUERY_HERE */
;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE','SIM_BASELINE','ALL'));

-- Hypothetical plan with index hint:
-- (Replace table alias and index name)
EXPLAIN PLAN SET STATEMENT_ID = 'SIM_WITH_IDX' FOR
SELECT /*+ INDEX(e idx_proposed) */ *
FROM /* PASTE_THE_EXPANDED_QUERY_HERE */
;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE','SIM_WITH_IDX','ALL'));

-- Clean up
DELETE FROM plan_table WHERE statement_id LIKE 'SIM_%';
COMMIT;


-- ┌──────────────────────────────────────────────────────────┐
-- │ SIMULATE-02: Create invisible index for testing          │
-- └──────────────────────────────────────────────────────────┘
-- Creates the proposed index as INVISIBLE — it exists but the
-- optimizer ignores it by default. Zero impact on production.
-- Only run this with explicit user permission.

-- CREATE INDEX idx_proposed_name
-- ON table_name(col1, col2)
-- INVISIBLE
-- NOLOGGING
-- PARALLEL 2;

-- After creation, verify it exists but is invisible:
-- SELECT index_name, visibility, status
-- FROM user_indexes
-- WHERE index_name = 'IDX_PROPOSED_NAME';


-- ┌──────────────────────────────────────────────────────────┐
-- │ SIMULATE-03: Test with invisible index using hint        │
-- └──────────────────────────────────────────────────────────┘
-- Force the optimizer to consider the invisible index.

-- Method A: Session-level override
-- ALTER SESSION SET optimizer_use_invisible_indexes = TRUE;
-- Then re-run the query and compare runtime.
-- ALTER SESSION SET optimizer_use_invisible_indexes = FALSE;

-- Method B: USE_INVISIBLE_INDEXES hint (per-query)
-- SELECT /*+ USE_INVISIBLE_INDEXES */ ...
-- FROM GRAPH_TABLE(...)


-- ┌──────────────────────────────────────────────────────────┐
-- │ SIMULATE-04: Measure actual runtime improvement          │
-- └──────────────────────────────────────────────────────────┘
-- After enabling invisible index, compare V$SQL stats.

-- Tag the test query differently to get clean stats:
-- SELECT /* GRAPH_SIM_TEST_Q1 */ ...
-- FROM GRAPH_TABLE(...)

-- Then compare:
SELECT
    CASE
        WHEN sql_text LIKE '%GRAPH_SIM_TEST%' THEN 'WITH_INDEX'
        WHEN sql_text LIKE '%AIDX_BASELINE%'  THEN 'BASELINE'
    END AS run_type,
    sql_id,
    elapsed_time,
    buffer_gets,
    executions,
    ROUND(elapsed_time / NULLIF(executions,0)) AS avg_elapsed_us,
    ROUND(buffer_gets / NULLIF(executions,0))  AS avg_buffer_gets,
    plan_hash_value
FROM v$sql
WHERE (sql_text LIKE '%GRAPH_SIM_TEST%' OR sql_text LIKE '%AIDX_BASELINE%')
  AND sql_text NOT LIKE '%v$sql%'
ORDER BY 1;


-- ┌──────────────────────────────────────────────────────────┐
-- │ SIMULATE-05: DML impact estimation                       │
-- └──────────────────────────────────────────────────────────┘
-- Before recommending an index on an edge table with heavy
-- INSERT workload, estimate the write overhead.

WITH edge_tables AS (
    SELECT DISTINCT table_name FROM user_pg_edge_tables
)
SELECT
    s.table_name,
    s.inserts,
    s.updates,
    s.deletes,
    s.inserts + s.updates + s.deletes                     AS total_dml,
    (SELECT COUNT(*) FROM user_indexes
     WHERE table_name = s.table_name)                     AS current_index_count,
    -- Each new index adds ~10-30% overhead per DML operation
    -- on the indexed columns. More for wide composite indexes.
    ROUND((s.inserts + s.updates + s.deletes) * 0.15)     AS est_overhead_per_new_index,
    s.timestamp                                            AS stats_since
FROM user_tab_modifications s
WHERE s.table_name IN (SELECT table_name FROM edge_tables)
ORDER BY total_dml DESC;
