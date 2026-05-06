SELECT
  sql_id,
  child_number,
  plan_hash_value,
  executions,
  ROUND(elapsed_time / 1e6, 3) AS total_elapsed_sec,
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
