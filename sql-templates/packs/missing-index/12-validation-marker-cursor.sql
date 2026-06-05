SELECT
  sql_id,
  child_number,
  plan_hash_value,
  last_active_time,
  executions,
  ROUND(elapsed_time / NULLIF(executions, 0) / 1000, 2) AS avg_elapsed_ms,
  ROUND(cpu_time / NULLIF(executions, 0) / 1000, 2) AS avg_cpu_ms,
  ROUND(buffer_gets / NULLIF(executions, 0), 2) AS avg_buffer_gets,
  sql_text
FROM v$sql
WHERE UPPER(sql_text) LIKE '%' || UPPER('__VALIDATION_SQL_MARKER__') || '%'
  AND UPPER(sql_text) NOT LIKE '%V$SQL%'
  AND UPPER(sql_text) NOT LIKE '%DBMS_XPLAN.DISPLAY_CURSOR%'
  AND UPPER(sql_text) NOT LIKE '%DBMS_OUTPUT.GET_LINE%'
ORDER BY last_active_time DESC NULLS LAST, child_number DESC
FETCH FIRST 5 ROWS ONLY
