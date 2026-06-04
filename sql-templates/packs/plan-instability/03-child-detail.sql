SELECT
  sql_id,
  child_number,
  plan_hash_value,
  executions,
  ROUND(elapsed_time / 1e6, 3) AS total_elapsed_sec,
  ROUND(elapsed_time / NULLIF(executions, 0) / 1000, 3) AS avg_elapsed_ms,
  ROUND(buffer_gets / NULLIF(executions, 0)) AS avg_buffer_gets,
  invalidations,
  parse_calls,
  loads,
  optimizer_cost,
  is_bind_sensitive,
  is_bind_aware,
  is_shareable,
  last_active_time,
  SUBSTR(REPLACE(REPLACE(sql_text, CHR(10), ' '), CHR(13), ' '), 1, 160) AS sql_preview
FROM v$sql
WHERE sql_id = '__SQL_ID__'
ORDER BY child_number
