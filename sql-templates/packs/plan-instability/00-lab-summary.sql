SELECT
  t.owner,
  t.table_name,
  t.num_rows,
  t.last_analyzed,
  c.num_distinct AS skew_key_num_distinct,
  c.num_buckets AS skew_key_num_buckets,
  c.histogram AS skew_key_histogram
FROM all_tables t
LEFT JOIN all_tab_col_statistics c
  ON c.owner = t.owner
 AND c.table_name = t.table_name
 AND c.column_name = 'SKEW_KEY'
WHERE t.table_name = 'PLAN_INSTABILITY_DEMO'
ORDER BY t.owner
