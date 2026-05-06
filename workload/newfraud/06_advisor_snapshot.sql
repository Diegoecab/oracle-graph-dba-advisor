--------------------------------------------------------------------------------
-- 06_advisor_snapshot.sql
--
-- Captures a reproducible advisor snapshot for the NEWFRAUD demo workload.
--
-- Expected session:
--   - Connected as the graph-owning schema (NEWFRAUD in the lab)
--   - Workload already executed so V$SQL contains DEMO_FRAUD_* statements
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET HEADING ON
SET PAGESIZE 500
SET LINESIZE 240
SET LONG 200000
SET LONGCHUNKSIZE 200000
SET SERVEROUTPUT ON
SET TIMING ON
SET DEFINE OFF

PROMPT
PROMPT ===== STEP 0: NON-PROD CONTEXT =====
PROMPT

SELECT
  USER AS current_user,
  SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS current_schema,
  SYS_CONTEXT('USERENV', 'DB_NAME') AS db_name,
  SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS service_name
FROM dual;

PROMPT
PROMPT ===== STEP 1: HEALTH CHECK (PRACTICAL SUBSET) =====
PROMPT

SELECT
  (SELECT banner FROM v$version WHERE ROWNUM = 1) AS db_version,
  (SELECT value FROM v$parameter WHERE name = 'cpu_count') AS cpu_count,
  (SELECT value FROM v$parameter WHERE name = 'undo_retention') AS undo_retention
FROM dual;

SELECT
  tablespace_name,
  ROUND(used_percent, 1) AS pct_used,
  CASE
    WHEN used_percent > 95 THEN 'CRITICAL'
    WHEN used_percent > 85 THEN 'WARNING'
    ELSE 'OK'
  END AS status
FROM dba_tablespace_usage_metrics
ORDER BY used_percent DESC;

SELECT
  tablespace_name,
  ROUND(free_space / 1024 / 1024, 1) AS free_mb,
  ROUND(used_space / 1024 / 1024, 1) AS used_mb
FROM dba_temp_free_space;

SELECT *
FROM (
  SELECT
    event,
    ROUND(time_waited_micro / 1e6, 2) AS time_waited_sec,
    wait_class
  FROM v$system_event
  WHERE wait_class NOT IN ('Idle', 'Other')
  ORDER BY time_waited_micro DESC
)
WHERE ROWNUM <= 8;

PROMPT
PROMPT ===== STEP 2: GRAPH DISCOVERY =====
PROMPT

@"/mnt/c/Users/Diego/Documents/Meli/Graphs/Performance Advisor/oracle-graph-dba-advisor/sql-templates/01-discovery.sql"

PROMPT
PROMPT ===== STEP 3: TAGGED WORKLOAD CANDIDATES =====
PROMPT

WITH tagged_sql AS (
  SELECT
    sql_id,
    child_number,
    plan_hash_value,
    executions,
    elapsed_time,
    buffer_gets,
    disk_reads,
    rows_processed,
    last_active_time,
    CASE
      WHEN UPPER(sql_text) LIKE '%DEMO_FRAUD_Q05%' THEN 'DEMO_FRAUD_Q05'
      WHEN UPPER(sql_text) LIKE '%DEMO_FRAUD_Q04%' THEN 'DEMO_FRAUD_Q04'
      WHEN UPPER(sql_text) LIKE '%DEMO_FRAUD_Q06%' THEN 'DEMO_FRAUD_Q06'
      WHEN UPPER(sql_text) LIKE '%DEMO_FRAUD_Q02%' THEN 'DEMO_FRAUD_Q02'
      WHEN UPPER(sql_text) LIKE '%TXFRAUD_Q%' THEN 'TXFRAUD'
      ELSE 'OTHER'
    END AS workload_tag,
    SUBSTR(REPLACE(REPLACE(sql_text, CHR(10), ' '), CHR(13), ' '), 1, 180) AS sql_preview
  FROM v$sql
  WHERE parsing_schema_name = USER
    AND (
      UPPER(sql_text) LIKE '%DEMO_FRAUD_Q%'
      OR UPPER(sql_text) LIKE '%TXFRAUD_Q%'
    )
    AND UPPER(sql_text) NOT LIKE '%FROM V$SQL%'
)
SELECT
  workload_tag,
  sql_id,
  plan_hash_value,
  executions,
  ROUND(elapsed_time / 1e6, 2) AS total_elapsed_sec,
  ROUND(elapsed_time / NULLIF(executions, 0) / 1e6, 4) AS avg_elapsed_sec,
  buffer_gets,
  ROUND(buffer_gets / NULLIF(executions, 0)) AS avg_buffer_gets,
  disk_reads,
  rows_processed,
  last_active_time,
  sql_preview
FROM tagged_sql
ORDER BY elapsed_time DESC, last_active_time DESC
FETCH FIRST 20 ROWS ONLY;

PROMPT
PROMPT ===== STEP 4: PRIMARY QUERY FOR PLAN ANALYSIS =====
PROMPT

SET DEFINE ON
COLUMN primary_sql_id NEW_VALUE PRIMARY_SQL_ID
SELECT sql_id AS primary_sql_id
FROM (
  SELECT
    sql_id,
    elapsed_time,
    last_active_time
  FROM v$sql
  WHERE parsing_schema_name = USER
    AND (
      UPPER(sql_text) LIKE '%DEMO_FRAUD_Q05%'
      OR UPPER(sql_text) LIKE '%DEMO_FRAUD_Q04%'
      OR UPPER(sql_text) LIKE '%DEMO_FRAUD_Q06%'
      OR UPPER(sql_text) LIKE '%DEMO_FRAUD_Q02%'
    )
    AND UPPER(sql_text) NOT LIKE '%FROM V$SQL%'
  ORDER BY elapsed_time DESC, last_active_time DESC
)
WHERE ROWNUM = 1;

PROMPT Selected SQL_ID = &PRIMARY_SQL_ID

PROMPT
PROMPT ===== STEP 5: EXECUTION PLAN =====
PROMPT

SELECT *
FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
  sql_id          => '&PRIMARY_SQL_ID',
  cursor_child_no => NULL,
  format          => 'ALLSTATS LAST +COST +BYTES +PREDICATE +ALIAS'
));

PROMPT
PROMPT ===== STEP 6: PLAN STEPS BY BUFFER GETS =====
PROMPT

SELECT
  p.id AS step_id,
  LPAD(' ', 2 * p.depth) || p.operation || ' ' || NVL(p.options, '') AS operation,
  p.object_name,
  p.cardinality AS estimated_rows,
  ps.last_output_rows AS actual_rows,
  ps.last_cr_buffer_gets + ps.last_cu_buffer_gets AS buffer_gets,
  ps.last_disk_reads AS disk_reads,
  ROUND(ps.last_elapsed_time / 1e6, 4) AS elapsed_sec,
  p.access_predicates,
  p.filter_predicates
FROM v$sql_plan p
LEFT JOIN v$sql_plan_statistics_all ps
  ON p.sql_id = ps.sql_id
 AND p.child_number = ps.child_number
 AND p.id = ps.id
WHERE p.sql_id = '&PRIMARY_SQL_ID'
ORDER BY (ps.last_cr_buffer_gets + ps.last_cu_buffer_gets) DESC NULLS LAST, p.id;

PROMPT
PROMPT ===== STEP 7: EDGE FK INDEX GAP ANALYSIS =====
PROMPT

WITH edge_fk_cols AS (
  SELECT DISTINCT
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
  FROM user_pg_edge_relationships r
),
indexed_cols AS (
  SELECT DISTINCT
      ic.table_name,
      ic.column_name
  FROM user_ind_columns ic
  WHERE ic.column_position = 1
)
SELECT
  efk.graph_name,
  efk.table_name,
  efk.fk_column,
  efk.fk_type,
  efk.references_table,
  efk.references_column,
  CASE
    WHEN ix.column_name IS NOT NULL THEN 'INDEXED'
    ELSE 'MISSING LEADING INDEX'
  END AS index_status
FROM edge_fk_cols efk
LEFT JOIN indexed_cols ix
  ON efk.table_name = ix.table_name
 AND efk.fk_column = ix.column_name
ORDER BY efk.table_name, efk.fk_type;

PROMPT
PROMPT ===== STEP 8: DDL CANDIDATES =====
PROMPT

SELECT 'CREATE INDEX idx_transfer_src ON transfer(src) INVISIBLE;' AS ddl FROM dual
UNION ALL
SELECT 'CREATE INDEX idx_transfer_dst ON transfer(dst) INVISIBLE;' FROM dual
UNION ALL
SELECT 'CREATE INDEX idx_login_from_src ON login_from(src) INVISIBLE;' FROM dual
UNION ALL
SELECT 'CREATE INDEX idx_login_from_dst ON login_from(dst) INVISIBLE;' FROM dual
UNION ALL
SELECT 'CREATE INDEX idx_purchase_src ON purchase(src) INVISIBLE;' FROM dual
UNION ALL
SELECT 'CREATE INDEX idx_purchase_dst ON purchase(dst) INVISIBLE;' FROM dual
UNION ALL
SELECT 'CREATE INDEX idx_withdrawal_src ON withdrawal(src) INVISIBLE;' FROM dual
UNION ALL
SELECT 'CREATE INDEX idx_withdrawal_dst ON withdrawal(dst) INVISIBLE;' FROM dual
ORDER BY 1;

SET DEFINE OFF
