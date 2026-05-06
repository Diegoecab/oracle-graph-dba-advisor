WITH candidate_sql AS (
  SELECT
    sql_id,
    child_number,
    plan_hash_value,
    executions,
    elapsed_time,
    buffer_gets,
    invalidations,
    parse_calls,
    loads,
    is_bind_sensitive,
    is_bind_aware,
    is_shareable,
    last_active_time,
    SUBSTR(REPLACE(REPLACE(sql_text, CHR(10), ' '), CHR(13), ' '), 1, 140) AS sql_preview
  FROM v$sql
  WHERE parsing_schema_name = SYS_CONTEXT('USERENV','CURRENT_SCHEMA')
    AND UPPER(sql_text) LIKE '%__PLAN_TAG__%'
    AND UPPER(sql_text) NOT LIKE '%V$SQL%'
    AND UPPER(sql_text) NOT LIKE '%EXPLAIN PLAN%'
)
SELECT
  sql_id,
  COUNT(*) AS child_cursor_count,
  COUNT(DISTINCT plan_hash_value) AS distinct_plan_hashes,
  SUM(executions) AS total_executions,
  SUM(invalidations) AS total_invalidations,
  SUM(parse_calls) AS total_parse_calls,
  MAX(CASE WHEN is_bind_sensitive = 'Y' THEN 'Y' ELSE 'N' END) AS bind_sensitive,
  MAX(CASE WHEN is_bind_aware = 'Y' THEN 'Y' ELSE 'N' END) AS bind_aware,
  MAX(CASE WHEN is_shareable = 'N' THEN 'Y' ELSE 'N' END) AS has_nonshareable_child,
  ROUND(SUM(elapsed_time) / 1e6, 2) AS total_elapsed_sec,
  MIN(sql_preview) AS sql_preview
FROM candidate_sql
GROUP BY sql_id
ORDER BY distinct_plan_hashes DESC, child_cursor_count DESC, total_invalidations DESC
