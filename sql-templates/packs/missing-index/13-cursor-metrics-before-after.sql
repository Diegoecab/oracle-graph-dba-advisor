WITH targets AS (
  SELECT 'BEFORE' AS sample_label, '__BEFORE_SQL_ID__' AS sql_id, TO_NUMBER('__BEFORE_CHILD_NUMBER__') AS child_number FROM dual
  UNION ALL
  SELECT 'AFTER' AS sample_label, '__AFTER_SQL_ID__' AS sql_id, TO_NUMBER('__AFTER_CHILD_NUMBER__') AS child_number FROM dual
),
metrics AS (
  SELECT
    t.sample_label,
    s.sql_id,
    s.child_number,
    s.plan_hash_value,
    s.executions,
    ROUND(s.elapsed_time / NULLIF(s.executions, 0) / 1000, 2) AS avg_elapsed_ms,
    ROUND(s.cpu_time / NULLIF(s.executions, 0) / 1000, 2) AS avg_cpu_ms,
    ROUND(s.buffer_gets / NULLIF(s.executions, 0), 2) AS avg_buffer_gets,
    s.rows_processed,
    s.last_active_time
  FROM targets t
  JOIN v$sql s
    ON s.sql_id = t.sql_id
   AND s.child_number = t.child_number
)
SELECT
  sample_label,
  sql_id,
  child_number,
  plan_hash_value,
  executions,
  avg_elapsed_ms,
  avg_cpu_ms,
  avg_buffer_gets,
  rows_processed,
  last_active_time
FROM metrics
ORDER BY CASE sample_label WHEN 'BEFORE' THEN 1 ELSE 2 END
