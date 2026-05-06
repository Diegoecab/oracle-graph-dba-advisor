SELECT
  sql_id,
  plan_hash_value,
  version_count,
  open_versions,
  users_opening,
  users_executing,
  executions,
  invalidations,
  parse_calls,
  loads,
  ROUND(elapsed_time / 1e6, 3) AS total_elapsed_sec,
  optimizer_cost,
  last_active_time
FROM v$sqlarea_plan_hash
WHERE sql_id = '__SQL_ID__'
ORDER BY last_active_time DESC, plan_hash_value
