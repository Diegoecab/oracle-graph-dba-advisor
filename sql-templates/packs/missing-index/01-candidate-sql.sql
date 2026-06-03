WITH candidate_sql AS (
  SELECT
    sql_id,
    child_number,
    plan_hash_value,
    executions,
    elapsed_time,
    buffer_gets,
    disk_reads,
    cpu_time,
    rows_processed,
    parse_calls,
    invalidations,
    last_active_time,
    SUBSTR(REPLACE(REPLACE(sql_text, CHR(10), ' '), CHR(13), ' '), 1, 180) AS sql_preview
  FROM v$sql
  WHERE UPPER(sql_text) LIKE '%__SQL_TAG__%'
    AND UPPER(sql_text) NOT LIKE '%V$SQL%'
    AND UPPER(sql_text) NOT LIKE '%V$SQL_PLAN%'
    AND UPPER(sql_text) NOT LIKE '%DBA_IND_COLUMNS%'
    AND UPPER(sql_text) NOT LIKE '%DBA_PG_EDGE_RELATIONSHIPS%'
    AND UPPER(sql_text) NOT LIKE '%DBA_TABLES%'
    AND UPPER(sql_text) NOT LIKE '%' || 'EX' || 'PLAIN PLAN%'
    AND NVL(executions, 0) > 0
)
SELECT
  sql_id,
  COUNT(*) AS child_cursor_count,
  COUNT(DISTINCT plan_hash_value) AS distinct_plan_hashes,
  SUM(executions) AS total_executions,
  ROUND(SUM(elapsed_time) / 1e6, 3) AS total_elapsed_sec,
  ROUND(SUM(elapsed_time) / NULLIF(SUM(executions), 0) / 1e3, 3) AS avg_elapsed_ms,
  SUM(buffer_gets) AS total_buffer_gets,
  ROUND(SUM(buffer_gets) / NULLIF(SUM(executions), 0)) AS avg_buffer_gets,
  SUM(disk_reads) AS total_disk_reads,
  SUM(cpu_time) AS total_cpu_us,
  SUM(rows_processed) AS total_rows_processed,
  SUM(parse_calls) AS total_parse_calls,
  SUM(invalidations) AS total_invalidations,
  MAX(last_active_time) AS last_active_time,
  MIN(sql_preview) AS sql_preview
FROM candidate_sql
GROUP BY sql_id
ORDER BY total_buffer_gets DESC, total_elapsed_sec DESC, child_cursor_count DESC
