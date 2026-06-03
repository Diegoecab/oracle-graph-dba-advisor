WITH target_tables AS (
  SELECT 'N_USER' AS table_name FROM dual
  UNION ALL SELECT 'N_DEVICE' FROM dual
  UNION ALL SELECT 'N_BANK_ACCOUNT' FROM dual
  UNION ALL SELECT 'N_CARD' FROM dual
  UNION ALL SELECT 'N_IP' FROM dual
  UNION ALL SELECT 'E_USES_DEVICE' FROM dual
  UNION ALL SELECT 'E_WITHDRAWAL_BANK_ACCOUNT' FROM dual
  UNION ALL SELECT 'E_USES_CARD' FROM dual
  UNION ALL SELECT 'E_USES_IP' FROM dual
),
index_counts AS (
  SELECT table_owner, table_name, COUNT(*) AS index_count
  FROM dba_indexes
  WHERE table_owner = '__GRAPH_OWNER__'
  GROUP BY table_owner, table_name
)
SELECT
  t.owner AS table_owner,
  t.table_name,
  t.num_rows,
  t.blocks,
  t.last_analyzed,
  NVL(ic.index_count, 0) AS index_count
FROM dba_tables t
JOIN target_tables tt
  ON tt.table_name = t.table_name
LEFT JOIN index_counts ic
  ON ic.table_owner = t.owner
 AND ic.table_name = t.table_name
WHERE t.owner = '__GRAPH_OWNER__'
ORDER BY
  CASE WHEN t.table_name LIKE 'N_%' THEN 1 ELSE 2 END,
  t.table_name
