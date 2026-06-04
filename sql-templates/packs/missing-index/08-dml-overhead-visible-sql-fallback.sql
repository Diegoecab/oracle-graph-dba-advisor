WITH target_table AS (
  SELECT
    owner,
    table_name,
    num_rows,
    last_analyzed
  FROM dba_tables
  WHERE owner = UPPER('__GRAPH_OWNER__')
    AND table_name = UPPER('__EDGE_TABLE__')
),
index_count AS (
  SELECT
    table_owner AS owner,
    table_name,
    COUNT(*) AS current_index_count
  FROM dba_indexes
  WHERE table_owner = UPPER('__GRAPH_OWNER__')
    AND table_name = UPPER('__EDGE_TABLE__')
  GROUP BY table_owner, table_name
),
visible_insert_sql AS (
  SELECT
    COUNT(DISTINCT sql_id) AS visible_insert_sql_count,
    NVL(SUM(executions), 0) AS visible_insert_executions,
    NVL(SUM(rows_processed), 0) AS visible_insert_rows_processed,
    MAX(last_active_time) AS last_visible_insert_time
  FROM v$sql
  WHERE command_type = 2
    AND UPPER(sql_text) LIKE '%' || UPPER('__EDGE_TABLE__') || '%'
    AND UPPER(sql_text) NOT LIKE '%V$SQL%'
)
SELECT
  t.owner,
  t.table_name,
  t.num_rows,
  t.last_analyzed,
  CAST(NULL AS NUMBER) AS inserts_since_stats,
  CAST(NULL AS NUMBER) AS updates_since_stats,
  CAST(NULL AS NUMBER) AS deletes_since_stats,
  CAST(NULL AS NUMBER) AS total_dml_since_stats,
  CAST(NULL AS DATE) AS last_modification_sample_time,
  CASE
    WHEN t.last_analyzed IS NOT NULL THEN ROUND((SYSDATE - t.last_analyzed) * 24, 2)
    ELSE NULL
  END AS hours_since_last_analyzed,
  CAST(NULL AS NUMBER) AS approx_inserts_per_hour_since_stats,
  NVL(i.current_index_count, 0) AS current_index_count,
  __PROPOSED_INDEX_COUNT__ AS proposed_new_index_count,
  v.visible_insert_sql_count,
  v.visible_insert_executions,
  v.visible_insert_rows_processed,
  v.last_visible_insert_time,
  CASE
    WHEN NVL(v.visible_insert_rows_processed, 0) = 0 THEN 'WRITE_RATE_NOT_VISIBLE'
    ELSE 'VISIBLE_INSERT_WORKLOAD_REVIEW_REQUIRED'
  END AS dml_overhead_signal
FROM target_table t
LEFT JOIN index_count i
  ON i.owner = t.owner
 AND i.table_name = t.table_name
CROSS JOIN visible_insert_sql v
