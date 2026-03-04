-- ============================================================
-- IDENTIFY TEMPLATES — Find the Expensive Graph Queries
-- ============================================================
-- Filters V$SQL for queries involving graph tables or
-- GRAPH_TABLE syntax. Ranks by resource consumption.
-- ============================================================


-- ┌──────────────────────────────────────────────────────────┐
-- │ IDENTIFY-01: Top graph queries by total elapsed time     │
-- └──────────────────────────────────────────────────────────┘
-- Finds queries that reference known graph tables OR contain
-- GRAPH_TABLE syntax. Ranks by total elapsed time.

WITH graph_tables AS (
    SELECT DISTINCT UPPER(table_name) AS table_name
    FROM user_pg_vertex_tables
    UNION
    SELECT DISTINCT UPPER(table_name)
    FROM user_pg_edge_tables
),
graph_sql AS (
    SELECT s.sql_id, s.plan_hash_value, s.sql_text,
           s.elapsed_time, s.buffer_gets, s.disk_reads,
           s.executions, s.rows_processed,
           s.cpu_time, s.user_io_wait_time,
           s.first_load_time, s.last_active_time
    FROM v$sql s
    WHERE s.parsing_schema_name = SYS_CONTEXT('USERENV','CURRENT_SCHEMA')
      AND s.executions > 0
      AND (
          -- Method 1: SQL text contains GRAPH_TABLE or MATCH keyword
          UPPER(s.sql_text) LIKE '%GRAPH_TABLE%'
          OR UPPER(s.sql_text) LIKE '%MATCH%(%IS%'
          -- Method 2: Plan references graph underlying tables
          OR EXISTS (
              SELECT 1 FROM v$sql_plan p
              WHERE p.sql_id = s.sql_id
                AND p.child_number = s.child_number
                AND UPPER(p.object_name) IN (SELECT table_name FROM graph_tables)
          )
      )
      -- Exclude internal/recursive queries
      AND s.sql_text NOT LIKE '%v$sql%'
      AND s.sql_text NOT LIKE '%EXPLAIN PLAN%'
      AND s.sql_text NOT LIKE 'SELECT /* OPT_DYN_SAMP%'
)
SELECT
    sql_id,
    plan_hash_value,
    executions,
    ROUND(elapsed_time / 1e6, 2)                        AS total_elapsed_sec,
    ROUND(elapsed_time / NULLIF(executions,0) / 1e6, 3) AS avg_elapsed_sec,
    buffer_gets,
    ROUND(buffer_gets / NULLIF(executions,0))            AS avg_buffer_gets,
    disk_reads,
    ROUND(cpu_time / 1e6, 2)                             AS total_cpu_sec,
    rows_processed,
    SUBSTR(sql_text, 1, 150)                             AS sql_preview
FROM graph_sql
ORDER BY elapsed_time DESC
FETCH FIRST 15 ROWS ONLY;


-- ┌──────────────────────────────────────────────────────────┐
-- │ IDENTIFY-02: Top graph queries by buffer gets            │
-- └──────────────────────────────────────────────────────────┘
-- Buffer gets = logical I/O. High buffer gets on graph queries
-- typically means full table scans on edge tables.

WITH graph_tables AS (
    SELECT DISTINCT UPPER(table_name) AS table_name
    FROM user_pg_vertex_tables
    UNION
    SELECT DISTINCT UPPER(table_name)
    FROM user_pg_edge_tables
),
graph_sql AS (
    SELECT s.sql_id, s.plan_hash_value, s.sql_text,
           s.elapsed_time, s.buffer_gets, s.disk_reads,
           s.executions, s.rows_processed
    FROM v$sql s
    WHERE s.parsing_schema_name = SYS_CONTEXT('USERENV','CURRENT_SCHEMA')
      AND s.executions > 0
      AND (
          UPPER(s.sql_text) LIKE '%GRAPH_TABLE%'
          OR UPPER(s.sql_text) LIKE '%MATCH%(%IS%'
          OR EXISTS (
              SELECT 1 FROM v$sql_plan p
              WHERE p.sql_id = s.sql_id
                AND p.child_number = s.child_number
                AND UPPER(p.object_name) IN (SELECT table_name FROM graph_tables)
          )
      )
      AND s.sql_text NOT LIKE '%v$sql%'
      AND s.sql_text NOT LIKE '%EXPLAIN PLAN%'
)
SELECT
    sql_id,
    plan_hash_value,
    executions,
    buffer_gets                                          AS total_buffer_gets,
    ROUND(buffer_gets / NULLIF(executions,0))            AS avg_buffer_gets,
    ROUND(elapsed_time / NULLIF(executions,0) / 1e6, 3) AS avg_elapsed_sec,
    SUBSTR(sql_text, 1, 150)                             AS sql_preview
FROM graph_sql
ORDER BY buffer_gets DESC
FETCH FIRST 15 ROWS ONLY;


-- ┌──────────────────────────────────────────────────────────┐
-- │ IDENTIFY-03: Weighted impact (executions × avg_elapsed)  │
-- └──────────────────────────────────────────────────────────┘
-- A query that runs 1000×/hour at 50ms each is more impactful
-- than one that runs 1×/day at 10s. This weights accordingly.

WITH graph_tables AS (
    SELECT DISTINCT UPPER(table_name) AS table_name
    FROM user_pg_vertex_tables
    UNION
    SELECT DISTINCT UPPER(table_name)
    FROM user_pg_edge_tables
),
graph_sql AS (
    SELECT s.sql_id, s.plan_hash_value, s.sql_text,
           s.elapsed_time, s.buffer_gets,
           s.executions, s.rows_processed
    FROM v$sql s
    WHERE s.parsing_schema_name = SYS_CONTEXT('USERENV','CURRENT_SCHEMA')
      AND s.executions > 0
      AND (
          UPPER(s.sql_text) LIKE '%GRAPH_TABLE%'
          OR UPPER(s.sql_text) LIKE '%MATCH%(%IS%'
          OR EXISTS (
              SELECT 1 FROM v$sql_plan p
              WHERE p.sql_id = s.sql_id
                AND p.child_number = s.child_number
                AND UPPER(p.object_name) IN (SELECT table_name FROM graph_tables)
          )
      )
      AND s.sql_text NOT LIKE '%v$sql%'
      AND s.sql_text NOT LIKE '%EXPLAIN PLAN%'
)
SELECT
    sql_id,
    executions,
    ROUND(elapsed_time / NULLIF(executions,0) / 1e6, 3)           AS avg_elapsed_sec,
    ROUND(elapsed_time / 1e6, 2)                                   AS total_elapsed_sec,
    ROUND(buffer_gets / NULLIF(executions,0))                      AS avg_buffer_gets,
    -- Weighted impact score: total elapsed is already exec × avg
    ROUND(elapsed_time / 1e6, 2)                                   AS impact_score,
    SUBSTR(sql_text, 1, 150)                                       AS sql_preview
FROM graph_sql
ORDER BY elapsed_time DESC
FETCH FIRST 15 ROWS ONLY;


-- ┌──────────────────────────────────────────────────────────┐
-- │ IDENTIFY-04: Get full SQL text for a specific SQL_ID     │
-- └──────────────────────────────────────────────────────────┘
-- Replace :sql_id with the target SQL_ID from previous queries.
-- Shows the full, untruncated SQL text.

-- Usage: Replace 'TARGET_SQL_ID' with actual sql_id
SELECT sql_fulltext
FROM v$sql
WHERE sql_id = 'TARGET_SQL_ID'
  AND ROWNUM = 1;

-- Alternative: V$SQLTEXT for very long queries (>4000 chars)
SELECT piece, sql_text
FROM v$sqltext
WHERE sql_id = 'TARGET_SQL_ID'
ORDER BY piece;


-- ┌──────────────────────────────────────────────────────────┐
-- │ IDENTIFY-05: Graph query classification helper           │
-- └──────────────────────────────────────────────────────────┘
-- Counts join operations in execution plans of graph queries
-- to help classify pattern complexity (1-hop, 2-hop, etc.)

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
    COUNT(CASE WHEN p.operation LIKE '%JOIN%' THEN 1 END)       AS join_count,
    COUNT(CASE WHEN p.operation = 'TABLE ACCESS'
                AND p.options = 'FULL' THEN 1 END)              AS full_scan_count,
    COUNT(CASE WHEN p.operation LIKE '%INDEX%' THEN 1 END)      AS index_access_count,
    COUNT(CASE WHEN p.operation LIKE '%SORT%' THEN 1 END)       AS sort_count,
    LISTAGG(DISTINCT p.object_name, ', ')
        WITHIN GROUP (ORDER BY p.object_name)                   AS tables_accessed,
    CASE
        WHEN COUNT(CASE WHEN p.operation LIKE '%JOIN%' THEN 1 END) <= 2 THEN '1-hop'
        WHEN COUNT(CASE WHEN p.operation LIKE '%JOIN%' THEN 1 END) <= 4 THEN '2-hop'
        WHEN COUNT(CASE WHEN p.operation LIKE '%JOIN%' THEN 1 END) <= 6 THEN '3-hop'
        ELSE 'N-hop (complex)'
    END AS estimated_pattern
FROM v$sql_plan p
WHERE p.sql_id IN (SELECT sql_id FROM graph_sql_ids)
  AND p.object_name IS NOT NULL
GROUP BY p.sql_id
ORDER BY join_count DESC;
