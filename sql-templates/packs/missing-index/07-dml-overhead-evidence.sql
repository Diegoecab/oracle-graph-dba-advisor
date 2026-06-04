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
modifications AS (
  SELECT
    table_owner AS owner,
    table_name,
    SUM(inserts) AS inserts_since_stats,
    SUM(updates) AS updates_since_stats,
    SUM(deletes) AS deletes_since_stats,
    MAX(timestamp) AS last_modification_sample_time
  FROM dba_tab_modifications
  WHERE table_owner = UPPER('__GRAPH_OWNER__')
    AND table_name = UPPER('__EDGE_TABLE__')
  GROUP BY table_owner, table_name
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
    AND UPPER(sql_text) NOT LIKE '%DBA_TAB_MODIFICATIONS%'
)
SELECT
  t.owner,
  t.table_name,
  t.num_rows,
  t.last_analyzed,
  NVL(m.inserts_since_stats, 0) AS inserts_since_stats,
  NVL(m.updates_since_stats, 0) AS updates_since_stats,
  NVL(m.deletes_since_stats, 0) AS deletes_since_stats,
  NVL(m.inserts_since_stats, 0) + NVL(m.updates_since_stats, 0) + NVL(m.deletes_since_stats, 0) AS total_dml_since_stats,
  m.last_modification_sample_time,
  CASE
    WHEN t.last_analyzed IS NOT NULL THEN ROUND((SYSDATE - t.last_analyzed) * 24, 2)
    ELSE NULL
  END AS hours_since_last_analyzed,
  CASE
    WHEN t.last_analyzed IS NOT NULL AND SYSDATE > t.last_analyzed THEN ROUND(NVL(m.inserts_since_stats, 0) / GREATEST((SYSDATE - t.last_analyzed) * 24, 1 / 60), 2)
    ELSE NULL
  END AS approx_inserts_per_hour_since_stats,
  NVL(i.current_index_count, 0) AS current_index_count,
  __PROPOSED_INDEX_COUNT__ AS proposed_new_index_count,
  v.visible_insert_sql_count,
  v.visible_insert_executions,
  v.visible_insert_rows_processed,
  v.last_visible_insert_time,
  CASE
    WHEN NVL(m.inserts_since_stats, 0) + NVL(m.updates_since_stats, 0) + NVL(m.deletes_since_stats, 0) = 0 AND NVL(v.visible_insert_rows_processed, 0) = 0 THEN 'LOW_OR_NOT_VISIBLE'
    WHEN NVL(m.inserts_since_stats, 0) / GREATEST(NVL(t.num_rows, 0), 1) >= 0.1 THEN 'HIGH_WRITE_RATE_REVIEW_REQUIRED'
    WHEN NVL(v.visible_insert_rows_processed, 0) > 0 THEN 'VISIBLE_INSERT_WORKLOAD_REVIEW_REQUIRED'
    ELSE 'MODERATE_WRITE_RATE_REVIEW'
  END AS dml_overhead_signal
FROM target_table t
LEFT JOIN modifications m
  ON m.owner = t.owner
 AND m.table_name = t.table_name
LEFT JOIN index_count i
  ON i.owner = t.owner
 AND i.table_name = t.table_name
CROSS JOIN visible_insert_sql v
