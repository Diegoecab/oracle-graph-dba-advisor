-- ============================================================
-- GRAPH DBA CATALOG — Cross-Schema Inventory for Admin Teams
-- ============================================================
-- Execute via MCP: run-sql
-- Purpose:
--   First operational step for a Graph DBA workflow.
--   Build a technical catalog of all property graphs visible in
--   the database before analyzing workload, waits, plans, or
--   index gaps.
--
-- Required direct grants:
--   SELECT ON DBA_PROPERTY_GRAPHS
--   SELECT ON DBA_PG_ELEMENTS
--   SELECT ON DBA_PG_EDGE_RELATIONSHIPS
--   SELECT ON DBA_TABLES
--   SELECT ON DBA_INDEXES
--   SELECT ON DBA_IND_COLUMNS
--   SELECT ON DBA_TAB_STATISTICS
--   SELECT ON DBA_TAB_COL_STATISTICS
--
-- Notes:
--   - This pack is for a dedicated Graph DBA / observer account.
--   - It does not assume the current schema owns the graph.
--   - Add owner filters if the client wants to scope to a subset
--     of schemas.
-- ============================================================


-- ┌──────────────────────────────────────────────────────────┐
-- │ GDBA-CATALOG-01: Property graph inventory summary        │
-- └──────────────────────────────────────────────────────────┘
-- Lists every property graph plus high-level shape.

SELECT
    pg.owner AS graph_owner,
    pg.graph_name,
    pg.graph_mode,
    pg.allows_mixed_types,
    pg.inmemory,
    COUNT(CASE WHEN UPPER(e.element_kind) = 'VERTEX' THEN 1 END) AS vertex_element_count,
    COUNT(CASE WHEN UPPER(e.element_kind) = 'EDGE' THEN 1 END)   AS edge_element_count,
    COUNT(DISTINCT CASE
        WHEN UPPER(e.element_kind) = 'VERTEX'
        THEN e.object_owner || '.' || e.object_name
    END) AS vertex_table_count,
    COUNT(DISTINCT CASE
        WHEN UPPER(e.element_kind) = 'EDGE'
        THEN e.object_owner || '.' || e.object_name
    END) AS edge_table_count
FROM dba_property_graphs pg
LEFT JOIN dba_pg_elements e
    ON  e.owner = pg.owner
    AND e.graph_name = pg.graph_name
GROUP BY
    pg.owner,
    pg.graph_name,
    pg.graph_mode,
    pg.allows_mixed_types,
    pg.inmemory
ORDER BY pg.owner, pg.graph_name;


-- ┌──────────────────────────────────────────────────────────┐
-- │ GDBA-CATALOG-02: Graph element detail + table stats      │
-- └──────────────────────────────────────────────────────────┘
-- Maps graph elements to underlying tables and current stats.

SELECT
    e.owner        AS graph_owner,
    e.graph_name,
    e.element_kind,
    e.element_name,
    e.object_owner,
    e.object_name,
    t.num_rows,
    t.last_analyzed,
    t.avg_row_len,
    ts.stale_stats
FROM dba_pg_elements e
LEFT JOIN dba_tables t
    ON  t.owner = e.object_owner
    AND t.table_name = e.object_name
LEFT JOIN dba_tab_statistics ts
    ON  ts.owner = e.object_owner
    AND ts.table_name = e.object_name
    AND ts.partition_name IS NULL
ORDER BY
    e.owner,
    e.graph_name,
    CASE
        WHEN UPPER(e.element_kind) = 'VERTEX' THEN 1
        WHEN UPPER(e.element_kind) = 'EDGE' THEN 2
        ELSE 3
    END,
    e.object_owner,
    e.object_name;


-- ┌──────────────────────────────────────────────────────────┐
-- │ GDBA-CATALOG-03: Edge relationship map                   │
-- └──────────────────────────────────────────────────────────┘
-- Shows the source/destination FK mapping of each edge table.

SELECT
    r.owner AS graph_owner,
    r.graph_name,
    r.edge_tab_name AS edge_table_name,
    MAX(CASE WHEN UPPER(r.edge_end) LIKE '%SOURCE%' THEN r.vertex_tab_name END) AS src_vertex_table,
    MAX(CASE WHEN UPPER(r.edge_end) LIKE '%SOURCE%' THEN r.edge_col_name END)   AS src_fk_column,
    MAX(CASE WHEN UPPER(r.edge_end) LIKE '%SOURCE%' THEN r.vertex_col_name END) AS src_vertex_key,
    MAX(CASE WHEN UPPER(r.edge_end) LIKE '%DEST%' THEN r.vertex_tab_name END)   AS dst_vertex_table,
    MAX(CASE WHEN UPPER(r.edge_end) LIKE '%DEST%' THEN r.edge_col_name END)     AS dst_fk_column,
    MAX(CASE WHEN UPPER(r.edge_end) LIKE '%DEST%' THEN r.vertex_col_name END)   AS dst_vertex_key
FROM dba_pg_edge_relationships r
GROUP BY
    r.owner,
    r.graph_name,
    r.edge_tab_name
ORDER BY
    r.owner,
    r.graph_name,
    r.edge_tab_name;


-- ┌──────────────────────────────────────────────────────────┐
-- │ GDBA-CATALOG-04: Edge FK leading-index gap analysis      │
-- └──────────────────────────────────────────────────────────┘
-- Checks whether source/destination FK columns are covered
-- as the leading column of an index.

WITH edge_tables AS (
    SELECT DISTINCT
        e.owner AS graph_owner,
        e.graph_name,
        e.object_owner AS table_owner,
        e.object_name AS table_name
    FROM dba_pg_elements e
    WHERE UPPER(e.element_kind) = 'EDGE'
),
edge_fk_cols AS (
    SELECT DISTINCT
        r.owner AS graph_owner,
        r.graph_name,
        r.edge_tab_name AS table_name,
        r.edge_col_name AS fk_column,
        CASE
            WHEN UPPER(r.edge_end) LIKE '%SOURCE%' THEN 'SOURCE_FK'
            WHEN UPPER(r.edge_end) LIKE '%DEST%'   THEN 'DESTINATION_FK'
            ELSE r.edge_end
        END AS fk_type,
        r.vertex_tab_name AS references_table,
        r.vertex_col_name AS references_column
    FROM dba_pg_edge_relationships r
),
leading_index_cols AS (
    SELECT DISTINCT
        ic.table_owner,
        ic.table_name,
        ic.column_name
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
    CASE
        WHEN lic.column_name IS NOT NULL THEN 'INDEXED'
        ELSE 'MISSING_LEADING_INDEX'
    END AS index_status
FROM edge_fk_cols efk
JOIN edge_tables et
    ON  et.graph_owner = efk.graph_owner
    AND et.graph_name = efk.graph_name
    AND et.table_name = efk.table_name
LEFT JOIN dba_tables t
    ON  t.owner = et.table_owner
    AND t.table_name = et.table_name
LEFT JOIN leading_index_cols lic
    ON  lic.table_owner = et.table_owner
    AND lic.table_name = efk.table_name
    AND lic.column_name = efk.fk_column
ORDER BY
    efk.graph_owner,
    efk.graph_name,
    efk.table_name,
    efk.fk_type;
