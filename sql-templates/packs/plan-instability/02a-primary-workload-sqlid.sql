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
    s.invalidations
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
    ROUND(MAX(elapsed_time / NULLIF(executions, 0)) / NULLIF(MIN(elapsed_time / NULLIF(executions, 0)), 0), 2) AS child_elapsed_ratio,
    ROUND(SUM(elapsed_time) / 1e6, 2) AS total_elapsed_sec
  FROM candidate_sql
  GROUP BY sql_id
)
SELECT sql_id
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
FETCH FIRST 1 ROW ONLY
