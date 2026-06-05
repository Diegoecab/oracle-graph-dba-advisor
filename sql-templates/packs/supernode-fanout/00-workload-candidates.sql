WITH graph_tables AS (
  SELECT DISTINCT
    UPPER(object_owner) AS object_owner,
    UPPER(object_name) AS object_name
  FROM dba_pg_elements
  WHERE owner = UPPER('__GRAPH_OWNER__')
     OR object_owner = UPPER('__GRAPH_OWNER__')
),
candidate_sql AS (
  SELECT
    s.sql_id,
    s.child_number,
    s.plan_hash_value,
    s.executions,
    s.elapsed_time,
    s.buffer_gets,
    s.disk_reads,
    s.cpu_time,
    s.rows_processed,
    s.parse_calls,
    s.invalidations,
    s.parsing_schema_name,
    s.module,
    s.action,
    s.last_active_time,
    CASE WHEN UPPER(s.parsing_schema_name) = UPPER('__GRAPH_OWNER__') THEN 'Y' ELSE 'N' END AS linked_by_schema,
    CASE WHEN UPPER(NVL(s.module, ' ')) LIKE '%' || UPPER('__WORKLOAD_SCOPE__') || '%' THEN 'Y' ELSE 'N' END AS linked_by_module,
    CASE WHEN UPPER(NVL(s.action, ' ')) LIKE '%' || UPPER('__WORKLOAD_SCOPE__') || '%' THEN 'Y' ELSE 'N' END AS linked_by_action,
    CASE WHEN UPPER(s.sql_text) LIKE '%' || UPPER('__WORKLOAD_SCOPE__') || '%' THEN 'Y' ELSE 'N' END AS linked_by_text_scope,
    CASE WHEN UPPER(s.sql_text) LIKE '%GRAPH_TABLE%' THEN 'Y' ELSE 'N' END AS linked_by_graph_table,
    SUBSTR(REPLACE(REPLACE(s.sql_text, CHR(10), ' '), CHR(13), ' '), 1, 180) AS sql_preview
  FROM v$sql s
  WHERE NVL(s.executions, 0) > 0
    AND REGEXP_LIKE(LTRIM(s.sql_text), '^(SELECT|WITH)', 'i')
    AND UPPER(s.sql_text) NOT LIKE '%V$SQL%'
    AND UPPER(s.sql_text) NOT LIKE '%V_$SQL%'
    AND UPPER(s.sql_text) NOT LIKE '%V$SQL_PLAN%'
    AND UPPER(s.sql_text) NOT LIKE '%DBA_PG_ELEMENTS%'
    AND UPPER(s.sql_text) NOT LIKE '%DBA_TABLES%'
    AND UPPER(s.sql_text) NOT LIKE '%JSON_ARRAYAGG(JSON_OBJECT(*)%'
    AND UPPER(s.sql_text) NOT LIKE '%SQL ANALYZE%'
    AND UPPER(s.sql_text) NOT LIKE '%DBMS_STATS%'
    AND UPPER(s.sql_text) NOT LIKE '%DYNAMIC_SAMPLING%'
    AND UPPER(s.sql_text) NOT LIKE '%' || 'EX' || 'PLAIN PLAN%'
    AND INSTR(UPPER(s.sql_text), 'SELECT ' || CHR(47) || CHR(42) || ' OPT_DYN_SAMP') = 0
    AND UPPER(NVL(s.module, ' ')) NOT IN ('MMON_SLAVE', 'SQLCL')
    AND UPPER(NVL(s.action, ' ')) NOT LIKE 'AUTO ADDM%'
),
plan_graph_access AS (
  SELECT
    p.sql_id,
    p.child_number,
    COUNT(*) AS graph_plan_steps,
    SUM(CASE WHEN p.operation LIKE '%JOIN%' THEN 1 ELSE 0 END) AS graph_join_steps,
    SUM(CASE WHEN p.cardinality >= 10000 THEN 1 ELSE 0 END) AS high_estimated_row_steps,
    MAX(p.cardinality) AS max_estimated_rows,
    MAX(CASE WHEN p.operation = 'TABLE ACCESS' AND p.options = 'FULL' THEN p.object_name END) AS sample_full_scan_object
  FROM v$sql_plan p
  JOIN graph_tables gt
    ON gt.object_name = UPPER(p.object_name)
   AND (p.object_owner IS NULL OR gt.object_owner = UPPER(p.object_owner))
  GROUP BY p.sql_id, p.child_number
),
scoped_sql AS (
  SELECT
    cs.*,
    NVL(pga.graph_plan_steps, 0) AS graph_plan_steps,
    NVL(pga.graph_join_steps, 0) AS graph_join_steps,
    NVL(pga.high_estimated_row_steps, 0) AS high_estimated_row_steps,
    NVL(pga.max_estimated_rows, 0) AS max_estimated_rows,
    pga.sample_full_scan_object,
    CASE WHEN pga.sql_id IS NOT NULL THEN 'Y' ELSE 'N' END AS linked_by_graph_table_plan
  FROM candidate_sql cs
  LEFT JOIN plan_graph_access pga
    ON pga.sql_id = cs.sql_id
   AND pga.child_number = cs.child_number
  WHERE UPPER(cs.parsing_schema_name) = UPPER('__GRAPH_OWNER__')
     OR UPPER(NVL(cs.module, ' ')) LIKE '%' || UPPER('__WORKLOAD_SCOPE__') || '%'
     OR UPPER(NVL(cs.action, ' ')) LIKE '%' || UPPER('__WORKLOAD_SCOPE__') || '%'
     OR UPPER(cs.sql_preview) LIKE '%' || UPPER('__WORKLOAD_SCOPE__') || '%'
     OR cs.linked_by_graph_table = 'Y'
     OR pga.sql_id IS NOT NULL
)
SELECT
  sql_id,
  COUNT(DISTINCT child_number) AS child_cursor_count,
  COUNT(DISTINCT plan_hash_value) AS distinct_plan_hashes,
  SUM(executions) AS total_executions,
  ROUND(SUM(elapsed_time) / 1e6, 3) AS total_elapsed_sec,
  ROUND(SUM(elapsed_time) / NULLIF(SUM(executions), 0) / 1e3, 3) AS avg_elapsed_ms,
  SUM(buffer_gets) AS total_buffer_gets,
  ROUND(SUM(buffer_gets) / NULLIF(SUM(executions), 0)) AS avg_buffer_gets,
  SUM(rows_processed) AS total_rows_processed,
  ROUND(SUM(rows_processed) / NULLIF(SUM(executions), 0)) AS avg_rows_processed,
  SUM(graph_plan_steps) AS graph_plan_steps,
  SUM(graph_join_steps) AS graph_join_steps,
  SUM(high_estimated_row_steps) AS high_estimated_row_steps,
  MAX(max_estimated_rows) AS max_estimated_rows,
  MAX(sample_full_scan_object) AS sample_full_scan_object,
  MAX(linked_by_schema) AS linked_by_schema,
  MAX(linked_by_module) AS linked_by_module,
  MAX(linked_by_action) AS linked_by_action,
  MAX(linked_by_text_scope) AS linked_by_text_scope,
  MAX(linked_by_graph_table) AS linked_by_graph_table,
  MAX(linked_by_graph_table_plan) AS linked_by_graph_table_plan,
  MAX(last_active_time) AS last_active_time,
  MIN(sql_preview) AS sql_preview
FROM scoped_sql
GROUP BY sql_id
HAVING SUM(graph_plan_steps) > 0
ORDER BY total_rows_processed DESC, total_buffer_gets DESC, total_elapsed_sec DESC
FETCH FIRST 20 ROWS ONLY
