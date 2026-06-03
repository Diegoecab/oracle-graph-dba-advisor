--------------------------------------------------------------------------------
-- 09_invisible_index_validation.sql
-- Lab-only remediation proof. Do not run through the read-only MCP runtime.
--
-- Run as DOWNER_DEMO after baseline DOWNER_MI_Q01 evidence is captured.
-- The candidate indexes remain INVISIBLE unless explicitly made visible later.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON
SET LINESIZE 220
SET PAGESIZE 100

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
    ownname => USER,
    tabname => 'E_USES_DEVICE',
    cascade => TRUE,
    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
    no_invalidate => FALSE
  );
END;
/

SELECT
  index_name,
  table_name,
  visibility,
  status
FROM user_indexes
WHERE table_name = 'E_USES_DEVICE'
ORDER BY index_name;

DELETE FROM plan_table
WHERE statement_id IN ('DOWNER_MI_Q01_BASE', 'DOWNER_MI_Q01_INVISIBLE');

PROMPT
PROMPT ===== BASELINE EXPLAIN: INVISIBLE INDEXES DISABLED =====
PROMPT

ALTER SESSION SET optimizer_use_invisible_indexes = FALSE;

EXPLAIN PLAN SET STATEMENT_ID = 'DOWNER_MI_Q01_BASE' FOR
SELECT /* DOWNER_MI_Q01_BASE */
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
FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'DOWNER_MI_Q01_BASE', 'BASIC +PREDICATE'));

SELECT /* DOWNER_MI_Q01_BASE_RUN */
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

PROMPT
PROMPT ===== VALIDATION EXPLAIN: INVISIBLE INDEXES ENABLED =====
PROMPT

ALTER SESSION SET optimizer_use_invisible_indexes = TRUE;

EXPLAIN PLAN SET STATEMENT_ID = 'DOWNER_MI_Q01_INVISIBLE' FOR
SELECT /* DOWNER_MI_Q01_INVISIBLE */
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
FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'DOWNER_MI_Q01_INVISIBLE', 'BASIC +PREDICATE'));

SELECT /* DOWNER_MI_Q01_INVISIBLE_RUN */
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
    WHEN sql_text LIKE '%DOWNER_MI_Q01_INVISIBLE_RUN%' THEN 'WITH_INVISIBLE_INDEX'
    WHEN sql_text LIKE '%DOWNER_MI_Q01_BASE_RUN%' THEN 'BASELINE'
  END AS run_type,
  sql_id,
  plan_hash_value,
  executions,
  ROUND(elapsed_time / NULLIF(executions, 0) / 1e3, 3) AS avg_elapsed_ms,
  ROUND(buffer_gets / NULLIF(executions, 0)) AS avg_buffer_gets,
  last_active_time
FROM v$sql
WHERE (sql_text LIKE '%DOWNER_MI_Q01_BASE_RUN%' OR sql_text LIKE '%DOWNER_MI_Q01_INVISIBLE_RUN%')
  AND sql_text NOT LIKE '%V$SQL%'
ORDER BY run_type, last_active_time DESC;

PROMPT
PROMPT Lab validation complete. Invisible indexes remain invisible.
PROMPT To remove them manually:
PROMPT   DROP INDEX idx_e_uses_device_src_ed_dst;
PROMPT   DROP INDEX idx_e_uses_device_dst_ed_src;
