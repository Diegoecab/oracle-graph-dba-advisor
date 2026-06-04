--------------------------------------------------------------------------------
-- 23_run_plan_instability_workload.sql
-- Seeds V$SQL with the DOWNER_PI_Q01 plan-instability workload.
--
-- Run as DOWNER_DEMO after 22_setup_plan_instability.sql.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON
SET LINESIZE 220
SET PAGESIZE 100

BEGIN
  run_downer_plan_instability_workload(
    p_cycles                   => 40,
    p_sql_tag                  => 'DOWNER_PI_Q01',
    p_optimizer_mode           => 'ALL_ROWS',
    p_optimizer_index_cost_adj => 10000,
    p_key_mode                 => 'HOT'
  );

  run_downer_plan_instability_workload(
    p_cycles                   => 40,
    p_sql_tag                  => 'DOWNER_PI_Q01',
    p_optimizer_mode           => 'FIRST_ROWS_1',
    p_optimizer_index_cost_adj => 1,
    p_key_mode                 => 'HOT'
  );

  run_downer_plan_instability_workload(
    p_cycles                   => 40,
    p_sql_tag                  => 'DOWNER_PI_Q01',
    p_optimizer_mode           => 'FIRST_ROWS_1',
    p_optimizer_index_cost_adj => 1,
    p_key_mode                 => 'COLD'
  );

  run_downer_plan_instability_workload(
    p_cycles                   => 40,
    p_sql_tag                  => 'DOWNER_PI_Q01',
    p_optimizer_mode           => 'ALL_ROWS',
    p_optimizer_index_cost_adj => 10000,
    p_key_mode                 => 'MIXED'
  );
END;
/

DECLARE
  v_count NUMBER;
BEGIN
  EXECUTE IMMEDIATE q'[
    SELECT COUNT(*)
    FROM v$sql
    WHERE UPPER(sql_text) LIKE '%DOWNER_PI_Q01%'
      AND UPPER(sql_text) NOT LIKE '%V$SQL%'
      AND NVL(executions, 0) > 0
  ]' INTO v_count;

  DBMS_OUTPUT.PUT_LINE('DOWNER_PI_Q01 visible rows in V$SQL=' || v_count);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('V$SQL summary skipped for DOWNER_DEMO: ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE('Use GRAPH_DIAG_USER/RUN_SQL or ADMIN for the read-only plan-instability pack.');
END;
/

PROMPT DOWNER_PI_Q01 seeded. Use sql-templates/packs/plan-instability/ through RUN_SQL for read-only diagnosis.
