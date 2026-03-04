-- ============================================================
-- DISCOVERY TEMPLATES — Understand the Graph Topology
-- ============================================================
-- Execute via SQLcl MCP: run-sql
-- These are parameterized templates. Replace :owner with the
-- target schema (or use USER for current schema).
-- ============================================================


-- ┌──────────────────────────────────────────────────────────┐
-- │ DISCOVERY-01: List all Property Graphs                   │
-- └──────────────────────────────────────────────────────────┘
-- Shows graph name, vertex tables, and edge tables.
-- Run this FIRST to understand what graphs exist.

SELECT
    pg.graph_name,
    pg.graph_type,
    (SELECT COUNT(*) FROM user_pg_vertex_tables vt
     WHERE vt.graph_name = pg.graph_name)    AS vertex_table_count,
    (SELECT COUNT(*) FROM user_pg_edge_tables et
     WHERE et.graph_name = pg.graph_name)    AS edge_table_count
FROM user_property_graphs pg
ORDER BY pg.graph_name;


-- ┌──────────────────────────────────────────────────────────┐
-- │ DISCOVERY-02: Vertex and Edge table mappings + volumes   │
-- └──────────────────────────────────────────────────────────┘
-- For each graph, shows underlying tables with row counts
-- and the source/destination key mappings for edges.

-- 2a: Vertex tables
SELECT
    vt.graph_name,
    'VERTEX' AS element_type,
    vt.table_name,
    vt.key_column,
    t.num_rows,
    t.last_analyzed,
    t.avg_row_len
FROM user_pg_vertex_tables vt
JOIN user_tables t ON vt.table_name = t.table_name
ORDER BY vt.graph_name, vt.table_name;

-- 2b: Edge tables with FK mappings
SELECT
    et.graph_name,
    'EDGE' AS element_type,
    et.table_name,
    et.key_column                     AS edge_pk,
    et.source_vertex_table            AS src_vertex_table,
    et.source_key_column              AS src_fk_column,
    et.destination_vertex_table       AS dst_vertex_table,
    et.destination_key_column         AS dst_fk_column,
    t.num_rows,
    t.last_analyzed,
    t.avg_row_len
FROM user_pg_edge_tables et
JOIN user_tables t ON et.table_name = t.table_name
ORDER BY et.graph_name, t.num_rows DESC;


-- ┌──────────────────────────────────────────────────────────┐
-- │ DISCOVERY-03: Existing indexes on graph tables           │
-- └──────────────────────────────────────────────────────────┘
-- Shows all indexes on tables participating in property graphs.
-- CRITICAL: Check if edge FK columns have indexes.

WITH graph_tables AS (
    SELECT DISTINCT table_name FROM user_pg_vertex_tables
    UNION
    SELECT DISTINCT table_name FROM user_pg_edge_tables
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
    SELECT DISTINCT table_name FROM user_pg_vertex_tables
    UNION
    SELECT DISTINCT table_name FROM user_pg_edge_tables
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
    SELECT DISTINCT table_name FROM user_pg_vertex_tables
    UNION
    SELECT DISTINCT table_name FROM user_pg_edge_tables
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
    t.stale_stats
FROM user_tables t
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
    -- Source FK columns
    SELECT
        et.graph_name,
        et.table_name,
        et.source_key_column AS fk_column,
        'SOURCE_FK' AS fk_type,
        et.source_vertex_table AS references_table
    FROM user_pg_edge_tables et
    UNION ALL
    -- Destination FK columns
    SELECT
        et.graph_name,
        et.table_name,
        et.destination_key_column AS fk_column,
        'DESTINATION_FK' AS fk_type,
        et.destination_vertex_table AS references_table
    FROM user_pg_edge_tables et
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
