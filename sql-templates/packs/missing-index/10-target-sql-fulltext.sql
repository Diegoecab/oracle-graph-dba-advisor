SELECT
  sql_id,
  child_number,
  plan_hash_value,
  last_active_time,
  sql_fulltext
FROM v$sql
WHERE sql_id = '__SQL_ID__'
ORDER BY last_active_time DESC NULLS LAST, child_number DESC
FETCH FIRST 1 ROWS ONLY
