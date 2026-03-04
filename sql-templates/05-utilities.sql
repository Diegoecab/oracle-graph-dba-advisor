-- ============================================================
-- UTILITY TEMPLATES — Stats, Index Management, Reporting
-- ============================================================
-- These are ACTION queries (write operations). The agent
-- must ask for explicit user permission before executing.
-- ============================================================


-- ┌──────────────────────────────────────────────────────────┐
-- │ UTIL-01: Gather statistics on all graph tables           │
-- └──────────────────────────────────────────────────────────┘
-- ⚠ REQUIRES USER PERMISSION — this modifies database state.

BEGIN
    FOR t IN (
        SELECT DISTINCT table_name FROM user_pg_vertex_tables
        UNION
        SELECT DISTINCT table_name FROM user_pg_edge_tables
    ) LOOP
        DBMS_STATS.GATHER_TABLE_STATS(
            ownname     => USER,
            tabname     => t.table_name,
            method_opt  => 'FOR ALL COLUMNS SIZE AUTO',
            cascade     => TRUE,
            no_invalidate => FALSE
        );
        DBMS_OUTPUT.PUT_LINE('Stats gathered: ' || t.table_name);
    END LOOP;
END;
/


-- ┌──────────────────────────────────────────────────────────┐
-- │ UTIL-02: Gather extended stats for correlated columns    │
-- └──────────────────────────────────────────────────────────┘
-- For edge tables where multi-column predicates appear,
-- extended stats improve cardinality estimates.
-- Replace TABLE_NAME, COL1, COL2.

-- ⚠ REQUIRES USER PERMISSION
-- SELECT DBMS_STATS.CREATE_EXTENDED_STATS(USER, 'TABLE_NAME', '(COL1, COL2)') FROM dual;
-- EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'TABLE_NAME', method_opt => 'FOR ALL COLUMNS SIZE AUTO');


-- ┌──────────────────────────────────────────────────────────┐
-- │ UTIL-03: Create recommended index (invisible)            │
-- └──────────────────────────────────────────────────────────┘
-- Template for index creation. Always INVISIBLE first.
-- ⚠ REQUIRES USER PERMISSION

-- CREATE INDEX idx_{table}_{cols}
-- ON {table_name}({col1}, {col2})
-- INVISIBLE
-- NOLOGGING;
--
-- Verify:
-- SELECT index_name, visibility, status, num_rows
-- FROM user_indexes WHERE index_name = 'IDX_NAME';


-- ┌──────────────────────────────────────────────────────────┐
-- │ UTIL-04: Promote invisible index to visible              │
-- └──────────────────────────────────────────────────────────┘
-- After validating improvement with SIMULATE templates.
-- ⚠ REQUIRES USER PERMISSION

-- ALTER INDEX idx_name VISIBLE;


-- ┌──────────────────────────────────────────────────────────┐
-- │ UTIL-05: Rollback — make index invisible again           │
-- └──────────────────────────────────────────────────────────┘
-- Instant rollback, no data movement.

-- ALTER INDEX idx_name INVISIBLE;


-- ┌──────────────────────────────────────────────────────────┐
-- │ UTIL-06: Rollback — drop index entirely                  │
-- └──────────────────────────────────────────────────────────┘
-- ⚠ REQUIRES USER PERMISSION

-- DROP INDEX idx_name;


-- ┌──────────────────────────────────────────────────────────┐
-- │ UTIL-07: Index usage tracking (23ai+)                    │
-- └──────────────────────────────────────────────────────────┘
-- After indexes have been visible for some time, check
-- if they're actually being used.

WITH graph_tables AS (
    SELECT DISTINCT table_name FROM user_pg_vertex_tables
    UNION
    SELECT DISTINCT table_name FROM user_pg_edge_tables
)
SELECT
    i.index_name,
    i.table_name,
    i.visibility,
    LISTAGG(ic.column_name, ', ')
        WITHIN GROUP (ORDER BY ic.column_position) AS columns,
    NVL(u.total_access_count, 0)                   AS times_used,
    NVL(u.total_exec_count, 0)                     AS exec_count,
    NVL(u.total_rows_returned, 0)                  AS rows_returned,
    u.last_used
FROM user_indexes i
JOIN user_ind_columns ic ON i.index_name = ic.index_name
LEFT JOIN dba_index_usage u
    ON i.index_name = u.name AND i.table_owner = u.owner
WHERE i.table_name IN (SELECT table_name FROM graph_tables)
GROUP BY i.index_name, i.table_name, i.visibility,
         u.total_access_count, u.total_exec_count,
         u.total_rows_returned, u.last_used
ORDER BY NVL(u.total_access_count, 0) ASC;


-- ┌──────────────────────────────────────────────────────────┐
-- │ UTIL-08: Graph topology statistics                       │
-- └──────────────────────────────────────────────────────────┘
-- Summary report of the graph landscape. Useful for the
-- agent's opening analysis.

SELECT 'PROPERTY GRAPHS' AS section,
       COUNT(*) AS count, NULL AS detail
FROM user_property_graphs
UNION ALL
SELECT 'VERTEX TABLES',
       COUNT(*), LISTAGG(table_name, ', ') WITHIN GROUP (ORDER BY table_name)
FROM user_pg_vertex_tables
UNION ALL
SELECT 'EDGE TABLES',
       COUNT(*), LISTAGG(table_name, ', ') WITHIN GROUP (ORDER BY table_name)
FROM user_pg_edge_tables
UNION ALL
SELECT 'TOTAL VERTICES',
       SUM(num_rows), NULL
FROM user_tables t
WHERE t.table_name IN (SELECT table_name FROM user_pg_vertex_tables)
UNION ALL
SELECT 'TOTAL EDGES',
       SUM(num_rows), NULL
FROM user_tables t
WHERE t.table_name IN (SELECT table_name FROM user_pg_edge_tables)
UNION ALL
SELECT 'INDEXES ON GRAPH TABLES',
       COUNT(*), NULL
FROM user_indexes i
WHERE i.table_name IN (
    SELECT table_name FROM user_pg_vertex_tables
    UNION
    SELECT table_name FROM user_pg_edge_tables
);


-- ┌──────────────────────────────────────────────────────────┐
-- │ UTIL-09: Complete recommendation report query            │
-- └──────────────────────────────────────────────────────────┘
-- Combines discovery + identify + analyze into a single
-- diagnostic snapshot. Good for periodic health checks.

WITH graph_tables AS (
    SELECT DISTINCT table_name,
           CASE WHEN table_name IN (SELECT table_name FROM user_pg_edge_tables)
                THEN 'EDGE' ELSE 'VERTEX' END AS table_role
    FROM (
        SELECT table_name FROM user_pg_vertex_tables
        UNION
        SELECT table_name FROM user_pg_edge_tables
    )
),
table_stats AS (
    SELECT t.table_name, gt.table_role, t.num_rows, t.last_analyzed,
           (SELECT COUNT(*) FROM user_indexes i WHERE i.table_name = t.table_name) AS idx_count
    FROM user_tables t
    JOIN graph_tables gt ON t.table_name = gt.table_name
),
full_scans AS (
    SELECT p.object_name AS table_name, COUNT(DISTINCT p.sql_id) AS queries_with_fts
    FROM v$sql_plan p
    WHERE p.operation = 'TABLE ACCESS' AND p.options = 'FULL'
      AND UPPER(p.object_name) IN (SELECT table_name FROM graph_tables)
    GROUP BY p.object_name
)
SELECT
    ts.table_role,
    ts.table_name,
    ts.num_rows,
    ts.idx_count                              AS existing_indexes,
    NVL(fs.queries_with_fts, 0)               AS queries_doing_full_scan,
    ROUND(SYSDATE - ts.last_analyzed, 1)      AS days_since_stats,
    CASE
        WHEN ts.table_role = 'EDGE' AND ts.num_rows > 100000 AND NVL(fs.queries_with_fts,0) > 0
        THEN '🔴 Action needed: full scans on large edge table'
        WHEN ts.last_analyzed IS NULL OR SYSDATE - ts.last_analyzed > 7
        THEN '🟡 Stale stats — gather before analyzing'
        WHEN NVL(fs.queries_with_fts,0) = 0
        THEN '✅ No full scans detected'
        ELSE '🟢 Full scans on small table — likely optimal'
    END AS status
FROM table_stats ts
LEFT JOIN full_scans fs ON ts.table_name = fs.table_name
ORDER BY
    CASE ts.table_role WHEN 'EDGE' THEN 0 ELSE 1 END,
    ts.num_rows DESC;
