SELECT
  sql_id,
  child_number,
  plan_hash_value,
  parsing_schema_name,
  module,
  action,
  executions,
  ROUND(elapsed_time / NULLIF(executions, 0) / 1e3, 3) AS avg_elapsed_ms,
  ROUND(cpu_time / NULLIF(executions, 0) / 1e3, 3) AS avg_cpu_ms,
  ROUND(buffer_gets / NULLIF(executions, 0)) AS avg_buffer_gets,
  rows_processed,
  ROUND(rows_processed / NULLIF(executions, 0), 3) AS avg_rows_processed,
  disk_reads,
  last_active_time,
  SUBSTR(REPLACE(REPLACE(sql_text, CHR(10), ' '), CHR(13), ' '), 1, 240) AS sql_preview
FROM v$sql
WHERE parsing_schema_name = '__PARSING_SCHEMA__'
  AND module = '__MODULE__'
  AND action LIKE '__ACTION_LIKE__'
  AND UPPER(sql_text) LIKE '%__SQL_TEXT_TOKEN__%'
  AND UPPER(sql_text) NOT LIKE '%V$SQL%'
  AND UPPER(sql_text) NOT LIKE '%DBA_%'
  AND UPPER(sql_text) NOT LIKE '%' || 'EX' || 'PLAIN PLAN%'
ORDER BY last_active_time DESC NULLS LAST, elapsed_time DESC, child_number DESC
