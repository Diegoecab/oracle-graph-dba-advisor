--------------------------------------------------------------------------------
-- 28_missing_index_exact_plan_validation.sql
-- Exact out-of-band EXPLAIN PLAN and invisible-index validation for R1/R2.
--
-- Run as DOWNER_DEMO. Do not run through the read-only MCP diagnostic channel.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON
SET LINESIZE 220
SET PAGESIZE 120

ALTER SESSION SET CURRENT_SCHEMA = DOWNER_DEMO;

PROMPT Current V$SQL snapshot for the hot SQL_ID identified by the advisor.

SELECT
  sql_id,
  child_number,
  plan_hash_value,
  executions,
  ROUND(elapsed_time / NULLIF(executions, 0) / 1e3, 3) AS avg_elapsed_ms,
  ROUND(cpu_time / NULLIF(executions, 0) / 1e3, 3) AS avg_cpu_ms,
  ROUND(buffer_gets / NULLIF(executions, 0)) AS avg_buffer_gets,
  last_active_time
FROM v$sql
WHERE sql_id = 'gbqr5nn5muh7j'
ORDER BY child_number, last_active_time DESC;

BEGIN
  EXECUTE IMMEDIATE 'DROP INDEX idx_e_uses_device_src_ed_dst';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1418 THEN
      RAISE;
    END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP INDEX idx_e_uses_device_dst_ed_src';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1418 THEN
      RAISE;
    END IF;
END;
/

CREATE INDEX idx_e_uses_device_src_ed_dst
  ON e_uses_device (src, end_date, dst)
  INVISIBLE;

CREATE INDEX idx_e_uses_device_dst_ed_src
  ON e_uses_device (dst, end_date, src)
  INVISIBLE;

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(
    ownname => 'DOWNER_DEMO',
    tabname => 'E_USES_DEVICE',
    cascade => TRUE,
    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
    no_invalidate => FALSE
  );
END;
/

DELETE FROM plan_table
WHERE statement_id IN ('DOWNER_MI_Q01_EXACT_BASE', 'DOWNER_MI_Q01_EXACT_INVISIBLE');

ALTER SESSION SET optimizer_use_invisible_indexes = FALSE;

EXPLAIN PLAN SET STATEMENT_ID = 'DOWNER_MI_Q01_EXACT_BASE' FOR
SELECT /* DOWNER_MI_Q01_EXACT_BASE */
       COUNT(*)
FROM GRAPH_TABLE (downer_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
  WHERE u1.id = 'U00000042'
    AND u1.id <> u2.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (
    u2.id AS neighbor_user_id,
    d.id AS shared_device_id,
    e2.device_type AS edge_device_type
  )
);

SELECT *
FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'DOWNER_MI_Q01_EXACT_BASE', 'BASIC +PREDICATE +ALIAS'));

SELECT /* DOWNER_MI_Q01_EXACT_BASE_RUN */
       COUNT(*) AS result_count
FROM GRAPH_TABLE (downer_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
  WHERE u1.id = 'U00000042'
    AND u1.id <> u2.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (
    u2.id AS neighbor_user_id,
    d.id AS shared_device_id,
    e2.device_type AS edge_device_type
  )
);

ALTER SESSION SET optimizer_use_invisible_indexes = TRUE;

EXPLAIN PLAN SET STATEMENT_ID = 'DOWNER_MI_Q01_EXACT_INVISIBLE' FOR
SELECT /* DOWNER_MI_Q01_EXACT_INVISIBLE */
       COUNT(*)
FROM GRAPH_TABLE (downer_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
  WHERE u1.id = 'U00000042'
    AND u1.id <> u2.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (
    u2.id AS neighbor_user_id,
    d.id AS shared_device_id,
    e2.device_type AS edge_device_type
  )
);

SELECT *
FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'DOWNER_MI_Q01_EXACT_INVISIBLE', 'BASIC +PREDICATE +ALIAS'));

SELECT /* DOWNER_MI_Q01_EXACT_INVISIBLE_RUN */
       COUNT(*) AS result_count
FROM GRAPH_TABLE (downer_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
  WHERE u1.id = 'U00000042'
    AND u1.id <> u2.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (
    u2.id AS neighbor_user_id,
    d.id AS shared_device_id,
    e2.device_type AS edge_device_type
  )
);

ALTER SESSION SET optimizer_use_invisible_indexes = FALSE;

SELECT
  CASE
    WHEN sql_text LIKE '%DOWNER_MI_Q01_EXACT_INVISIBLE_RUN%' THEN 'WITH_INVISIBLE_INDEX'
    WHEN sql_text LIKE '%DOWNER_MI_Q01_EXACT_BASE_RUN%' THEN 'BASELINE'
  END AS run_type,
  sql_id,
  plan_hash_value,
  executions,
  ROUND(elapsed_time / NULLIF(executions, 0) / 1e3, 3) AS avg_elapsed_ms,
  ROUND(cpu_time / NULLIF(executions, 0) / 1e3, 3) AS avg_cpu_ms,
  ROUND(buffer_gets / NULLIF(executions, 0)) AS avg_buffer_gets,
  last_active_time
FROM v$sql
WHERE (sql_text LIKE '%DOWNER_MI_Q01_EXACT_BASE_RUN%' OR sql_text LIKE '%DOWNER_MI_Q01_EXACT_INVISIBLE_RUN%')
  AND sql_text NOT LIKE '%V$SQL%'
ORDER BY run_type, last_active_time DESC;

PROMPT Invisible indexes remain invisible. To approve the change after validation:
PROMPT   ALTER INDEX DOWNER_DEMO.IDX_E_USES_DEVICE_SRC_ED_DST VISIBLE;
PROMPT   ALTER INDEX DOWNER_DEMO.IDX_E_USES_DEVICE_DST_ED_SRC VISIBLE;
