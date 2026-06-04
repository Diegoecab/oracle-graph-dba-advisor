SELECT sql_id
FROM (
  SELECT
    sql_id,
    COUNT(DISTINCT plan_hash_value) AS distinct_plan_hashes,
    COUNT(*) AS child_cursor_count,
    SUM(invalidations) AS total_invalidations
  FROM v$sql
  WHERE UPPER(sql_text) LIKE '%__PLAN_TAG__%'
    AND UPPER(sql_text) NOT LIKE '%V$SQL%'
    AND UPPER(sql_text) NOT LIKE '%EXPLAIN PLAN%'
    AND NVL(executions, 0) > 0
  GROUP BY sql_id
  ORDER BY COUNT(DISTINCT plan_hash_value) DESC, COUNT(*) DESC, SUM(invalidations) DESC, SUM(elapsed_time) DESC
)
WHERE ROWNUM = 1
