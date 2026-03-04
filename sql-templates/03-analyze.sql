-- ============================================================
-- ANALYZE TEMPLATES — Deep Dive into Execution Plans
-- ============================================================
-- Retrieves actual execution plans with runtime statistics
-- for graph queries. Focuses on identifying the expensive
-- operations that are candidates for index optimization.
-- ============================================================


-- ┌──────────────────────────────────────────────────────────┐
-- │ ANALYZE-01: Actual execution plan with runtime stats     │
-- └──────────────────────────────────────────────────────────┘
-- DISPLAY_CURSOR shows the REAL plan (not estimated).
-- ALLSTATS LAST shows actual rows, buffer gets per operation.
-- Replace 'TARGET_SQL_ID' with the sql_id to analyze.

SELECT *
FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
    sql_id          => 'TARGET_SQL_ID',
    cursor_child_no => NULL,
    format          => 'ALLSTATS LAST +COST +BYTES +PREDICATE +ALIAS'
));

-- Interpretation guide for the output:
-- ┌────────────┬──────────────────────────────────────────────┐
-- │ Column     │ What to look for                             │
-- ├────────────┼──────────────────────────────────────────────┤
-- │ Starts     │ How many times this operation executed        │
-- │ E-Rows     │ Optimizer's ESTIMATE of rows                 │
-- │ A-Rows     │ ACTUAL rows (compare with E-Rows!)           │
-- │ Buffers    │ Buffer gets (logical I/O) per operation      │
-- │ Reads      │ Physical disk reads per operation             │
-- │ A-Time     │ Actual wall-clock time per operation          │
-- │ Operation  │ TABLE ACCESS FULL = bad on big edge tables   │
-- │            │ INDEX RANGE SCAN = good (selective access)    │
-- │            │ HASH JOIN = ok for large sets                 │
-- │            │ NESTED LOOPS = ok for small intermediate sets │
-- └────────────┴──────────────────────────────────────────────┘


-- ┌──────────────────────────────────────────────────────────┐
-- │ ANALYZE-02: Plan operations ranked by buffer gets        │
-- └──────────────────────────────────────────────────────────┘
-- Pinpoints EXACTLY which plan step consumes the most I/O.
-- This is where your index recommendation should target.

SELECT
    p.id                                          AS step_id,
    LPAD(' ', 2 * p.depth) || p.operation
        || ' ' || p.options                       AS operation,
    p.object_name                                 AS object,
    p.cardinality                                 AS estimated_rows,
    ps.last_output_rows                           AS actual_rows,
    ps.last_cr_buffer_gets + ps.last_cu_buffer_gets AS buffer_gets,
    ps.last_disk_reads                            AS disk_reads,
    ps.last_elapsed_time                          AS elapsed_us,
    p.access_predicates                           AS access_preds,
    p.filter_predicates                           AS filter_preds
FROM v$sql_plan p
LEFT JOIN v$sql_plan_statistics_all ps
    ON  p.sql_id = ps.sql_id
    AND p.child_number = ps.child_number
    AND p.id = ps.id
WHERE p.sql_id = 'TARGET_SQL_ID'
  AND p.child_number = (
      SELECT MAX(child_number) FROM v$sql_plan
      WHERE sql_id = 'TARGET_SQL_ID'
  )
ORDER BY (ps.last_cr_buffer_gets + ps.last_cu_buffer_gets) DESC NULLS LAST;


-- ┌──────────────────────────────────────────────────────────┐
-- │ ANALYZE-03: Full table scans on graph tables             │
-- └──────────────────────────────────────────────────────────┘
-- Finds ALL full table scans in graph query plans.
-- Each one is a potential index recommendation.

WITH graph_tables AS (
    SELECT DISTINCT UPPER(table_name) AS table_name
    FROM user_pg_vertex_tables
    UNION
    SELECT DISTINCT UPPER(table_name)
    FROM user_pg_edge_tables
),
graph_sql_ids AS (
    SELECT DISTINCT s.sql_id
    FROM v$sql s
    WHERE s.parsing_schema_name = SYS_CONTEXT('USERENV','CURRENT_SCHEMA')
      AND s.executions > 0
      AND (UPPER(s.sql_text) LIKE '%GRAPH_TABLE%'
           OR UPPER(s.sql_text) LIKE '%MATCH%(%IS%')
      AND s.sql_text NOT LIKE '%v$sql%'
)
SELECT
    p.sql_id,
    p.object_name                     AS table_scanned,
    t.num_rows                        AS table_rows,
    p.cardinality                     AS estimated_rows_returned,
    ROUND(p.cardinality / NULLIF(t.num_rows,0) * 100, 1) AS est_selectivity_pct,
    p.filter_predicates               AS filters_applied,
    p.access_predicates               AS access_preds,
    CASE
        WHEN t.num_rows > 100000 THEN '🔴 HIGH IMPACT — index strongly recommended'
        WHEN t.num_rows > 10000  THEN '🟡 MEDIUM — index likely beneficial'
        ELSE '🟢 LOW — full scan may be optimal at this size'
    END AS recommendation_urgency
FROM v$sql_plan p
JOIN user_tables t ON UPPER(p.object_name) = t.table_name
WHERE p.sql_id IN (SELECT sql_id FROM graph_sql_ids)
  AND p.operation = 'TABLE ACCESS'
  AND p.options = 'FULL'
  AND UPPER(p.object_name) IN (SELECT table_name FROM graph_tables)
ORDER BY t.num_rows DESC, p.sql_id;


-- ┌──────────────────────────────────────────────────────────┐
-- │ ANALYZE-04: Join method analysis for graph queries       │
-- └──────────────────────────────────────────────────────────┘
-- Shows what join strategies the optimizer chose.
-- HASH JOIN on large sets = expected. NESTED LOOPS on large
-- sets without index = problem.

WITH graph_sql_ids AS (
    SELECT DISTINCT s.sql_id
    FROM v$sql s
    WHERE s.parsing_schema_name = SYS_CONTEXT('USERENV','CURRENT_SCHEMA')
      AND s.executions > 0
      AND (UPPER(s.sql_text) LIKE '%GRAPH_TABLE%'
           OR UPPER(s.sql_text) LIKE '%MATCH%(%IS%')
      AND s.sql_text NOT LIKE '%v$sql%'
)
SELECT
    p.sql_id,
    p.id AS step,
    p.operation || ' ' || p.options AS join_method,
    p.cardinality AS estimated_rows,
    -- Look at children to see what's being joined
    (SELECT p2.object_name FROM v$sql_plan p2
     WHERE p2.sql_id = p.sql_id AND p2.child_number = p.child_number
       AND p2.parent_id = p.id AND p2.object_name IS NOT NULL
       AND ROWNUM = 1) AS inner_table,
    p.access_predicates,
    p.filter_predicates
FROM v$sql_plan p
WHERE p.sql_id IN (SELECT sql_id FROM graph_sql_ids)
  AND p.operation LIKE '%JOIN%'
ORDER BY p.sql_id, p.id;


-- ┌──────────────────────────────────────────────────────────┐
-- │ ANALYZE-05: Cardinality accuracy check (E-Rows vs A-Rows)│
-- └──────────────────────────────────────────────────────────┘
-- Large discrepancies between estimated and actual rows
-- indicate stale stats or missing histograms — which cause
-- the optimizer to pick wrong join methods for graph queries.

SELECT
    p.sql_id,
    p.id                                      AS step,
    p.operation || ' ' || NVL(p.options,'')   AS operation,
    p.object_name,
    p.cardinality                             AS estimated_rows,
    ps.last_output_rows                       AS actual_rows,
    CASE
        WHEN p.cardinality > 0 AND ps.last_output_rows > 0
        THEN ROUND(ps.last_output_rows / p.cardinality, 1)
        ELSE NULL
    END AS actual_to_estimated_ratio,
    CASE
        WHEN ps.last_output_rows > p.cardinality * 10
        THEN '⚠ UNDERESTIMATE (10×+) — may cause bad NL join'
        WHEN p.cardinality > ps.last_output_rows * 10
        THEN '⚠ OVERESTIMATE (10×+) — wasted resources'
        ELSE '✓ Reasonable'
    END AS accuracy_flag
FROM v$sql_plan p
LEFT JOIN v$sql_plan_statistics_all ps
    ON  p.sql_id = ps.sql_id
    AND p.child_number = ps.child_number
    AND p.id = ps.id
WHERE p.sql_id = 'TARGET_SQL_ID'
  AND p.child_number = (
      SELECT MAX(child_number) FROM v$sql_plan
      WHERE sql_id = 'TARGET_SQL_ID'
  )
  AND p.cardinality > 0
ORDER BY
    ABS(NVL(ps.last_output_rows / NULLIF(p.cardinality,0), 1) - 1) DESC;
