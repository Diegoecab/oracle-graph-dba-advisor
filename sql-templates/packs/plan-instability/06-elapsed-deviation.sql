WITH child_metrics AS (
  SELECT
    sql_id,
    child_number,
    plan_hash_value,
    executions,
    elapsed_time,
    buffer_gets,
    CASE
      WHEN executions > 0 THEN elapsed_time / executions / 1000
    END AS avg_elapsed_ms,
    CASE
      WHEN executions > 0 THEN buffer_gets / executions
    END AS avg_buffer_gets
  FROM v$sql
  WHERE sql_id = '__SQL_ID__'
    AND NVL(executions, 0) > 0
)
SELECT
  sql_id,
  COUNT(*) AS child_cursor_count,
  COUNT(DISTINCT plan_hash_value) AS distinct_plan_hashes,
  ROUND(MIN(avg_elapsed_ms), 3) AS min_child_avg_elapsed_ms,
  ROUND(MAX(avg_elapsed_ms), 3) AS max_child_avg_elapsed_ms,
  ROUND(MAX(avg_elapsed_ms) / NULLIF(MIN(avg_elapsed_ms), 0), 2) AS child_elapsed_ratio,
  ROUND(AVG(avg_elapsed_ms), 3) AS mean_child_avg_elapsed_ms,
  ROUND(MIN(avg_buffer_gets)) AS min_child_avg_buffer_gets,
  ROUND(MAX(avg_buffer_gets)) AS max_child_avg_buffer_gets,
  ROUND(MAX(avg_buffer_gets) / NULLIF(MIN(avg_buffer_gets), 0), 2) AS child_buffer_gets_ratio,
  SUM(executions) AS total_executions,
  ROUND(SUM(elapsed_time) / 1e6, 3) AS total_elapsed_sec
FROM child_metrics
GROUP BY sql_id
