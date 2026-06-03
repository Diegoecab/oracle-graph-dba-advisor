WITH candidate_sql AS (
  SELECT
    sql_id,
    child_number,
    plan_hash_value,
    executions,
    elapsed_time,
    buffer_gets,
    last_active_time,
    sql_text
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
SELECT sql_id
FROM (
  SELECT
    sql_id,
    SUM(buffer_gets) AS total_buffer_gets,
    SUM(elapsed_time) AS total_elapsed_time,
    SUM(executions) AS total_executions,
    MAX(last_active_time) AS last_active_time
  FROM candidate_sql
  GROUP BY sql_id
  ORDER BY total_buffer_gets DESC, total_elapsed_time DESC, total_executions DESC, last_active_time DESC
)
WHERE ROWNUM = 1
