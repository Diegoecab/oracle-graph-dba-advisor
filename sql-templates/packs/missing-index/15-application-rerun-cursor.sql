SELECT
  sql_id,
  child_number,
  plan_hash_value,
  parsing_schema_name,
  module,
  action,
  executions,
  ROUND(elapsed_time / NULLIF(executions, 0) / 1000, 2) AS avg_elapsed_ms,
  ROUND(cpu_time / NULLIF(executions, 0) / 1000, 2) AS avg_cpu_ms,
  ROUND(buffer_gets / NULLIF(executions, 0), 2) AS avg_buffer_gets,
  rows_processed,
  last_active_time,
  sql_text
FROM v$sql
WHERE (
    sql_id = '__ORIGINAL_SQL_ID__'
    OR UPPER(sql_text) LIKE '%' || UPPER('__WORKLOAD_SQL_MARKER__') || '%'
    OR UPPER(module) LIKE '%' || UPPER('__WORKLOAD_MODULE__') || '%'
    OR UPPER(action) LIKE '%' || UPPER('__WORKLOAD_ACTION__') || '%'
  )
  AND UPPER(sql_text) NOT LIKE '%V$SQL%'
  AND UPPER(sql_text) NOT LIKE '%DBMS_XPLAN.DISPLAY_CURSOR%'
  AND UPPER(sql_text) NOT LIKE '%DBMS_OUTPUT.GET_LINE%'
ORDER BY last_active_time DESC NULLS LAST, child_number DESC
FETCH FIRST 10 ROWS ONLY
