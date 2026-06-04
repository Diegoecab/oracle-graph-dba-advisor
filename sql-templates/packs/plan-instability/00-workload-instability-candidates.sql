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
    s.invalidations,
    s.parse_calls,
    s.loads,
    s.is_bind_sensitive,
    s.is_bind_aware,
    s.is_shareable,
    s.parsing_schema_name,
    s.module,
    s.action,
    s.last_active_time,
    CASE WHEN UPPER(s.parsing_schema_name) = UPPER('__GRAPH_OWNER__') THEN 'Y' ELSE 'N' END AS linked_by_schema,
    CASE WHEN UPPER(NVL(s.module, ' ')) LIKE '%' || UPPER('__WORKLOAD_SCOPE__') || '%' THEN 'Y' ELSE 'N' END AS linked_by_module,
    CASE WHEN UPPER(NVL(s.action, ' ')) LIKE '%' || UPPER('__WORKLOAD_SCOPE__') || '%' THEN 'Y' ELSE 'N' END AS linked_by_action,
    CASE WHEN UPPER(s.sql_text) LIKE '%' || UPPER('__WORKLOAD_SCOPE__') || '%' THEN 'Y' ELSE 'N' END AS linked_by_text_scope,
    CASE WHEN UPPER(s.sql_text) LIKE '%GRAPH_TABLE%' THEN 'Y' ELSE 'N' END AS linked_by_graph_table,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM v$sql_plan p
        JOIN graph_tables gt
          ON gt.object_name = UPPER(p.object_name)
         AND (p.object_owner IS NULL OR gt.object_owner = UPPER(p.object_owner))
        WHERE p.sql_id = s.sql_id
          AND p.child_number = s.child_number
      ) THEN 'Y'
      ELSE 'N'
    END AS linked_by_graph_table_plan,
    SUBSTR(REPLACE(REPLACE(s.sql_text, CHR(10), ' '), CHR(13), ' '), 1, 180) AS sql_preview
  FROM v$sql s
  WHERE NVL(s.executions, 0) > 0
    AND UPPER(s.sql_text) NOT LIKE '%V$SQL%'
    AND UPPER(s.sql_text) NOT LIKE '%V_$SQL%'
    AND UPPER(s.sql_text) NOT LIKE '%EXPLAIN PLAN%'
    AND INSTR(UPPER(s.sql_text), 'SELECT ' || CHR(47) || CHR(42) || ' OPT_DYN_SAMP') = 0
    AND (
      UPPER(s.parsing_schema_name) = UPPER('__GRAPH_OWNER__')
      OR UPPER(NVL(s.module, ' ')) LIKE '%' || UPPER('__WORKLOAD_SCOPE__') || '%'
      OR UPPER(NVL(s.action, ' ')) LIKE '%' || UPPER('__WORKLOAD_SCOPE__') || '%'
      OR UPPER(s.sql_text) LIKE '%' || UPPER('__WORKLOAD_SCOPE__') || '%'
      OR UPPER(s.sql_text) LIKE '%GRAPH_TABLE%'
      OR EXISTS (
        SELECT 1
        FROM v$sql_plan p
        JOIN graph_tables gt
          ON gt.object_name = UPPER(p.object_name)
         AND (p.object_owner IS NULL OR gt.object_owner = UPPER(p.object_owner))
        WHERE p.sql_id = s.sql_id
          AND p.child_number = s.child_number
      )
    )
),
summary AS (
  SELECT
    sql_id,
    COUNT(DISTINCT child_number) AS child_cursor_count,
    COUNT(DISTINCT plan_hash_value) AS distinct_plan_hashes,
    SUM(executions) AS total_executions,
    SUM(invalidations) AS total_invalidations,
    SUM(parse_calls) AS total_parse_calls,
    SUM(loads) AS total_loads,
    ROUND(SUM(elapsed_time) / NULLIF(SUM(executions), 0) / 1000, 3) AS avg_elapsed_ms,
    ROUND(MIN(elapsed_time / NULLIF(executions, 0)) / 1000, 3) AS min_child_avg_elapsed_ms,
    ROUND(MAX(elapsed_time / NULLIF(executions, 0)) / 1000, 3) AS max_child_avg_elapsed_ms,
    ROUND(MAX(elapsed_time / NULLIF(executions, 0)) / NULLIF(MIN(elapsed_time / NULLIF(executions, 0)), 0), 2) AS child_elapsed_ratio,
    ROUND(SUM(buffer_gets) / NULLIF(SUM(executions), 0)) AS avg_buffer_gets,
    MAX(CASE WHEN is_bind_sensitive = 'Y' THEN 'Y' ELSE 'N' END) AS bind_sensitive,
    MAX(CASE WHEN is_bind_aware = 'Y' THEN 'Y' ELSE 'N' END) AS bind_aware,
    MAX(CASE WHEN is_shareable = 'N' THEN 'Y' ELSE 'N' END) AS has_nonshareable_child,
    MAX(linked_by_schema) AS linked_by_schema,
    MAX(linked_by_module) AS linked_by_module,
    MAX(linked_by_action) AS linked_by_action,
    MAX(linked_by_text_scope) AS linked_by_text_scope,
    MAX(linked_by_graph_table) AS linked_by_graph_table,
    MAX(linked_by_graph_table_plan) AS linked_by_graph_table_plan,
    ROUND(SUM(elapsed_time) / 1e6, 2) AS total_elapsed_sec,
    MAX(last_active_time) AS last_active_time,
    MIN(sql_preview) AS sql_preview
  FROM candidate_sql
  GROUP BY sql_id
)
SELECT
  sql_id,
  child_cursor_count,
  distinct_plan_hashes,
  total_executions,
  total_invalidations,
  total_parse_calls,
  total_loads,
  avg_elapsed_ms,
  min_child_avg_elapsed_ms,
  max_child_avg_elapsed_ms,
  child_elapsed_ratio,
  avg_buffer_gets,
  bind_sensitive,
  bind_aware,
  has_nonshareable_child,
  linked_by_schema,
  linked_by_module,
  linked_by_action,
  linked_by_text_scope,
  linked_by_graph_table,
  linked_by_graph_table_plan,
  total_elapsed_sec,
  last_active_time,
  CASE
    WHEN distinct_plan_hashes > 1 THEN 'PLAN_HASH_CHANGED'
    WHEN child_cursor_count > 1 AND total_invalidations > 0 THEN 'MULTI_CHILD_PLUS_INVALIDATION'
    WHEN child_cursor_count > 1 AND child_elapsed_ratio >= 3 THEN 'MULTI_CHILD_ELAPSED_DEVIATION'
    WHEN child_cursor_count > 1 THEN 'MULTIPLE_CHILD_CURSORS'
    WHEN total_invalidations > 0 THEN 'INVALIDATION_OBSERVED'
    ELSE 'NO_CLEAR_INSTABILITY_SIGNAL'
  END AS instability_signal,
  sql_preview
FROM summary
WHERE distinct_plan_hashes > 1
   OR child_cursor_count > 1
   OR total_invalidations > 0
   OR child_elapsed_ratio >= 3
ORDER BY
  distinct_plan_hashes DESC,
  child_cursor_count DESC,
  child_elapsed_ratio DESC,
  total_invalidations DESC,
  total_elapsed_sec DESC
FETCH FIRST 20 ROWS ONLY
