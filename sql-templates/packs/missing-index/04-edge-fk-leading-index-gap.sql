WITH edge_tables AS (
  SELECT DISTINCT
    e.owner AS graph_owner,
    e.graph_name,
    e.object_owner AS table_owner,
    e.object_name AS table_name
  FROM dba_pg_elements e
  WHERE e.owner = '__GRAPH_OWNER__'
    AND e.graph_name = '__GRAPH_NAME__'
    AND UPPER(e.element_kind) = 'EDGE'
),
edge_fk_cols AS (
  SELECT DISTINCT
    r.owner AS graph_owner,
    r.graph_name,
    r.edge_tab_name AS table_name,
    r.edge_col_name AS fk_column,
    CASE
      WHEN UPPER(r.edge_end) LIKE '%SOURCE%' THEN 'SOURCE_FK'
      WHEN UPPER(r.edge_end) LIKE '%DEST%' THEN 'DESTINATION_FK'
      ELSE r.edge_end
    END AS fk_type,
    r.vertex_tab_name AS references_table,
    r.vertex_col_name AS references_column
  FROM dba_pg_edge_relationships r
  WHERE r.owner = '__GRAPH_OWNER__'
    AND r.graph_name = '__GRAPH_NAME__'
),
leading_index_cols AS (
  SELECT DISTINCT
    ic.table_owner,
    ic.table_name,
    ic.column_name,
    ic.index_name
  FROM dba_ind_columns ic
  WHERE ic.column_position = 1
)
SELECT
  efk.graph_owner,
  efk.graph_name,
  et.table_owner,
  efk.table_name AS edge_table_name,
  efk.fk_column,
  efk.fk_type,
  efk.references_table,
  efk.references_column,
  t.num_rows AS edge_table_rows,
  lic.index_name AS leading_index_name,
  CASE
    WHEN lic.column_name IS NOT NULL THEN 'INDEXED'
    ELSE 'MISSING_LEADING_INDEX'
  END AS index_status,
  CASE
    WHEN efk.table_name = '__EDGE_TABLE__' AND lic.column_name IS NULL THEN 'DEMO_ROOT_CAUSE'
    WHEN lic.column_name IS NULL THEN 'REVIEW'
    ELSE 'OK'
  END AS diagnostic_signal
FROM edge_fk_cols efk
JOIN edge_tables et
  ON et.graph_owner = efk.graph_owner
 AND et.graph_name = efk.graph_name
 AND et.table_name = efk.table_name
LEFT JOIN dba_tables t
  ON t.owner = et.table_owner
 AND t.table_name = et.table_name
LEFT JOIN leading_index_cols lic
  ON lic.table_owner = et.table_owner
 AND lic.table_name = efk.table_name
 AND lic.column_name = efk.fk_column
ORDER BY
  CASE WHEN efk.table_name = '__EDGE_TABLE__' THEN 1 ELSE 2 END,
  efk.table_name,
  efk.fk_type
