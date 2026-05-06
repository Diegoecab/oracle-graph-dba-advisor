-- ============================================================
-- DISCOVERY TEMPLATES — Understand the Graph Topology
-- ============================================================
-- Execute via SQLcl MCP: run-sql
-- These templates assume the current schema owns the property
-- graph objects. They intentionally use USER_* dictionary views.
-- ============================================================


-- ┌──────────────────────────────────────────────────────────┐
-- │ DISCOVERY-01: List all Property Graphs                   │
-- └──────────────────────────────────────────────────────────┘
-- Shows graph name, vertex tables, and edge tables.
-- Run this FIRST to understand what graphs exist.

SELECT
    pg.graph_name,
    pg.graph_mode,
    (SELECT COUNT(DISTINCT e.object_name)
     FROM user_pg_elements e
     WHERE e.graph_name = pg.graph_name
       AND UPPER(e.element_kind) = 'VERTEX') AS vertex_table_count,
    (SELECT COUNT(DISTINCT e.object_name)
     FROM user_pg_elements e
     WHERE e.graph_name = pg.graph_name
       AND UPPER(e.element_kind) = 'EDGE')   AS edge_table_count
FROM user_property_graphs pg
ORDER BY pg.graph_name;


-- ┌──────────────────────────────────────────────────────────┐
-- │ DISCOVERY-02: Vertex and Edge table mappings + volumes   │
-- └──────────────────────────────────────────────────────────┘
-- For each graph, shows underlying tables with row counts
-- and the source/destination key mappings for edges.

-- 2a: Vertex tables
WITH vertex_elements AS (
    SELECT DISTINCT
        graph_name,
        element_name,
        object_name AS table_name
    FROM user_pg_elements
    WHERE UPPER(element_kind) = 'VERTEX'
)
SELECT
    ve.graph_name,
    'VERTEX' AS element_type,
    ve.element_name AS vertex_name,
    ve.table_name,
    t.num_rows,
    t.last_analyzed,
    t.avg_row_len
FROM vertex_elements ve
JOIN user_tables t ON ve.table_name = t.table_name
ORDER BY ve.graph_name, ve.table_name;

-- 2b: Edge tables with FK mappings
WITH edge_elements AS (
    SELECT DISTINCT
        graph_name,
        element_name,
        object_name AS table_name
    FROM user_pg_elements
    WHERE UPPER(element_kind) = 'EDGE'
),
edge_relationships AS (
    SELECT
        graph_name,
        edge_tab_name AS table_name,
        MAX(CASE WHEN UPPER(edge_end) LIKE '%SOURCE%' THEN vertex_tab_name END) AS src_vertex_table,
        MAX(CASE WHEN UPPER(edge_end) LIKE '%SOURCE%' THEN edge_col_name END)   AS src_fk_column,
        MAX(CASE WHEN UPPER(edge_end) LIKE '%SOURCE%' THEN vertex_col_name END) AS src_vertex_key,
        MAX(CASE WHEN UPPER(edge_end) LIKE '%DEST%' THEN vertex_tab_name END)   AS dst_vertex_table,
        MAX(CASE WHEN UPPER(edge_end) LIKE '%DEST%' THEN edge_col_name END)     AS dst_fk_column,
        MAX(CASE WHEN UPPER(edge_end) LIKE '%DEST%' THEN vertex_col_name END)   AS dst_vertex_key
    FROM user_pg_edge_relationships
    GROUP BY graph_name, edge_tab_name
)
SELECT
    ee.graph_name,
    'EDGE' AS element_type,
    ee.element_name                   AS edge_name,
    ee.table_name,
    er.src_vertex_table,
    er.src_fk_column,
    er.src_vertex_key,
    er.dst_vertex_table,
    er.dst_fk_column,
    er.dst_vertex_key,
    t.num_rows,
    t.last_analyzed,
    t.avg_row_len
FROM edge_elements ee
JOIN user_tables t ON ee.table_name = t.table_name
LEFT JOIN edge_relationships er
    ON  ee.graph_name = er.graph_name
    AND ee.table_name = er.table_name
ORDER BY ee.graph_name, t.num_rows DESC;


-- ┌──────────────────────────────────────────────────────────┐
-- │ DISCOVERY-03: Existing indexes on graph tables           │
-- └──────────────────────────────────────────────────────────┘
-- Shows all indexes on tables participating in property graphs.
-- CRITICAL: Check if edge FK columns have indexes.

WITH graph_tables AS (
    SELECT DISTINCT object_name AS table_name
    FROM user_pg_elements
)
SELECT
    i.table_name,
    i.index_name,
    i.index_type,
    i.uniqueness,
    i.visibility,
    i.status,
    LISTAGG(ic.column_name, ', ')
        WITHIN GROUP (ORDER BY ic.column_position) AS indexed_columns,
    i.num_rows AS index_rows,
    i.leaf_blocks,
    i.distinct_keys
FROM user_indexes i
JOIN user_ind_columns ic ON i.index_name = ic.index_name
WHERE i.table_name IN (SELECT table_name FROM graph_tables)
GROUP BY i.table_name, i.index_name, i.index_type,
         i.uniqueness, i.visibility, i.status,
         i.num_rows, i.leaf_blocks, i.distinct_keys
ORDER BY i.table_name, i.index_name;


-- ┌──────────────────────────────────────────────────────────┐
-- │ DISCOVERY-04: Column statistics for key graph columns    │
-- └──────────────────────────────────────────────────────────┘
-- Checks selectivity of columns commonly used in graph
-- traversal predicates (edge properties, vertex filters).

WITH graph_tables AS (
    SELECT DISTINCT object_name AS table_name
    FROM user_pg_elements
)
SELECT
    cs.table_name,
    cs.column_name,
    cs.num_distinct,
    cs.num_nulls,
    cs.density,
    cs.histogram,
    cs.num_buckets,
    t.num_rows AS table_rows,
    CASE
        WHEN cs.num_distinct > 0
        THEN ROUND(1 / cs.num_distinct * 100, 2)
        ELSE NULL
    END AS approx_selectivity_pct,
    CASE
        WHEN cs.num_distinct > 0 AND t.num_rows > 0
        THEN ROUND(t.num_rows / cs.num_distinct)
        ELSE NULL
    END AS avg_rows_per_value
FROM user_tab_col_statistics cs
JOIN user_tables t ON cs.table_name = t.table_name
WHERE cs.table_name IN (SELECT table_name FROM graph_tables)
  AND cs.num_distinct IS NOT NULL
ORDER BY t.num_rows DESC, cs.table_name, approx_selectivity_pct ASC;


-- ┌──────────────────────────────────────────────────────────┐
-- │ DISCOVERY-05: Stale statistics check                     │
-- └──────────────────────────────────────────────────────────┘
-- Flags tables where stats are missing or older than 7 days.

WITH graph_tables AS (
    SELECT DISTINCT object_name AS table_name
    FROM user_pg_elements
)
SELECT
    t.table_name,
    t.num_rows,
    t.last_analyzed,
    ROUND(SYSDATE - t.last_analyzed, 1) AS days_since_analyzed,
    CASE
        WHEN t.last_analyzed IS NULL THEN '⚠ NEVER ANALYZED'
        WHEN SYSDATE - t.last_analyzed > 7 THEN '⚠ STALE (>7 days)'
        ELSE '✓ Fresh'
    END AS stats_status,
    ts.stale_stats
FROM user_tables t
LEFT JOIN user_tab_statistics ts
    ON  t.table_name = ts.table_name
    AND ts.partition_name IS NULL
WHERE t.table_name IN (SELECT table_name FROM graph_tables)
ORDER BY
    CASE WHEN t.last_analyzed IS NULL THEN 0
         ELSE SYSDATE - t.last_analyzed END DESC;


-- ┌──────────────────────────────────────────────────────────┐
-- │ DISCOVERY-06: Edge FK index gap analysis                 │
-- └──────────────────────────────────────────────────────────┘
-- THE MOST IMPORTANT DISCOVERY QUERY.
-- Finds edge table FK columns that do NOT have indexes.
-- These are almost always the #1 optimization opportunity.

WITH edge_fk_cols AS (
    SELECT DISTINCT
        r.graph_name,
        r.edge_tab_name  AS table_name,
        r.edge_col_name  AS fk_column,
        CASE
            WHEN UPPER(r.edge_end) LIKE '%SOURCE%' THEN 'SOURCE_FK'
            WHEN UPPER(r.edge_end) LIKE '%DEST%'   THEN 'DESTINATION_FK'
            ELSE r.edge_end
        END AS fk_type,
        r.vertex_tab_name AS references_table,
        r.vertex_col_name AS references_column
    FROM user_pg_edge_relationships r
),
indexed_cols AS (
    SELECT DISTINCT
        ic.table_name,
        ic.column_name
    FROM user_ind_columns ic
    WHERE ic.column_position = 1  -- Leading column of an index
)
SELECT
    efk.graph_name,
    efk.table_name,
    efk.fk_column,
    efk.fk_type,
    efk.references_table,
    efk.references_column,
    t.num_rows AS edge_table_rows,
    CASE
        WHEN ix.column_name IS NOT NULL THEN '✓ Indexed'
        ELSE '❌ NO INDEX — recommend creating'
    END AS index_status
FROM edge_fk_cols efk
JOIN user_tables t ON efk.table_name = t.table_name
LEFT JOIN indexed_cols ix ON efk.table_name = ix.table_name
                         AND efk.fk_column = ix.column_name
ORDER BY
    CASE WHEN ix.column_name IS NULL THEN 0 ELSE 1 END,
    t.num_rows DESC;
