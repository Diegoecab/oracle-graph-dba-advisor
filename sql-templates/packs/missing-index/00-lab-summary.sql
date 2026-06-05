WITH graph_tables AS (
  SELECT DISTINCT
    e.object_owner AS table_owner,
    e.object_name AS table_name,
    e.element_kind
  FROM dba_pg_elements e
  WHERE e.owner = '__GRAPH_OWNER__'
    AND e.graph_name = '__GRAPH_NAME__'
),
index_counts AS (
  SELECT table_owner, table_name, COUNT(*) AS index_count
  FROM dba_indexes
  GROUP BY table_owner, table_name
)
SELECT
  gt.table_owner,
  gt.table_name,
  gt.element_kind,
  t.num_rows,
  t.blocks,
  t.last_analyzed,
  NVL(ic.index_count, 0) AS index_count
FROM graph_tables gt
LEFT JOIN dba_tables t
  ON t.owner = gt.table_owner
 AND t.table_name = gt.table_name
LEFT JOIN index_counts ic
  ON ic.table_owner = gt.table_owner
 AND ic.table_name = gt.table_name
ORDER BY gt.element_kind, gt.table_owner, gt.table_name
