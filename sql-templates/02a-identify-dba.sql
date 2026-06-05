WITH graph_tables AS (
    SELECT DISTINCT
        UPPER(e.owner) AS graph_owner,
        e.graph_name,
        UPPER(e.object_owner) AS table_owner,
        UPPER(e.object_name) AS table_name
    FROM dba_pg_elements e
    WHERE UPPER(e.owner) = UPPER('__GRAPH_OWNER__')
),
plan_hits AS (
    SELECT
        p.sql_id,
        p.child_number,
        LISTAGG(DISTINCT gt.graph_owner || '.' || gt.graph_name, ', ')
            WITHIN GROUP (ORDER BY gt.graph_owner || '.' || gt.graph_name) AS graph_context,
        LISTAGG(DISTINCT gt.table_owner || '.' || gt.table_name, ', ')
            WITHIN GROUP (ORDER BY gt.table_owner || '.' || gt.table_name) AS graph_tables_seen
    FROM v$sql_plan p
    JOIN graph_tables gt
        ON  UPPER(p.object_name) = gt.table_name
        AND (p.object_owner IS NULL OR UPPER(p.object_owner) = gt.table_owner)
    WHERE p.object_name IS NOT NULL
    GROUP BY p.sql_id, p.child_number
),
sql_candidates AS (
    SELECT
        s.sql_id,
        s.child_number,
        s.plan_hash_value,
        s.parsing_schema_name,
        s.module,
        s.action,
        s.service,
        s.executions,
        s.elapsed_time,
        s.cpu_time,
        s.buffer_gets,
        s.disk_reads,
        s.rows_processed,
        s.first_load_time,
        s.last_active_time,
        s.sql_text,
        ph.graph_context,
        ph.graph_tables_seen,
        CASE
            WHEN ph.sql_id IS NOT NULL THEN 'plan references graph backing tables'
            WHEN UPPER(s.sql_text) LIKE '%GRAPH_TABLE%' THEN 'sql text contains GRAPH_TABLE'
            WHEN UPPER(s.sql_text) LIKE '%MATCH%(%IS%' THEN 'sql text contains SQL/PGQ MATCH pattern'
            ELSE 'workload owner scope'
        END AS match_evidence
    FROM v$sql s
    LEFT JOIN plan_hits ph
        ON  ph.sql_id = s.sql_id
        AND ph.child_number = s.child_number
    WHERE s.executions > 0
      AND (
          ph.sql_id IS NOT NULL
          OR UPPER(s.sql_text) LIKE '%GRAPH_TABLE%'
          OR UPPER(s.sql_text) LIKE '%MATCH%(%IS%'
      )
      AND s.sql_text NOT LIKE '%v$sql%'
      AND s.sql_text NOT LIKE '%EXPLAIN PLAN%'
      AND s.sql_text NOT LIKE 'SELECT /* OPT_DYN_SAMP%'
)
SELECT
    sql_id,
    child_number,
    plan_hash_value,
    COALESCE(graph_context, UPPER('__GRAPH_OWNER__') || ' via SQL text') AS workload_context,
    parsing_schema_name,
    module,
    action,
    service,
    executions,
    ROUND(elapsed_time / 1e6, 2) AS total_elapsed_sec,
    ROUND(elapsed_time / NULLIF(executions, 0) / 1e3, 2) AS avg_elapsed_ms_per_exec,
    ROUND(cpu_time / 1e6, 2) AS total_cpu_sec,
    ROUND(cpu_time / NULLIF(executions, 0) / 1e3, 2) AS avg_cpu_ms_per_exec,
    buffer_gets,
    ROUND(buffer_gets / NULLIF(executions, 0)) AS avg_buffer_gets_per_exec,
    disk_reads,
    rows_processed,
    ROUND(rows_processed / NULLIF(executions, 0)) AS avg_rows_per_exec,
    first_load_time,
    last_active_time,
    match_evidence,
    graph_tables_seen,
    SUBSTR(sql_text, 1, 200) AS sql_preview
FROM sql_candidates
ORDER BY elapsed_time DESC
FETCH FIRST 15 ROWS ONLY
