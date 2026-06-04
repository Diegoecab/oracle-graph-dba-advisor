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
    p_cycles         => 20,
    p_sql_tag        => 'DOWNER_PI_Q01',
    p_optimizer_mode => 'ALL_ROWS',
    p_key_mode       => 'HOT'
  );

  run_downer_plan_instability_workload(
    p_cycles         => 20,
    p_sql_tag        => 'DOWNER_PI_Q01',
    p_optimizer_mode => 'FIRST_ROWS_1',
    p_key_mode       => 'COLD'
  );

  run_downer_plan_instability_workload(
    p_cycles         => 20,
    p_sql_tag        => 'DOWNER_PI_Q01',
    p_optimizer_mode => 'FIRST_ROWS_100',
    p_key_mode       => 'MIXED'
  );

  run_downer_plan_instability_workload(
    p_cycles         => 20,
    p_sql_tag        => 'DOWNER_PI_Q01',
    p_optimizer_mode => 'ALL_ROWS',
    p_key_mode       => 'MIXED'
  );
END;
/

SELECT
  sql_id,
  COUNT(*) AS child_cursor_count,
  COUNT(DISTINCT plan_hash_value) AS distinct_plan_hashes,
  SUM(executions) AS total_executions,
  ROUND(SUM(elapsed_time) / NULLIF(SUM(executions), 0) / 1000, 3) AS avg_elapsed_ms,
  ROUND(MIN(elapsed_time / NULLIF(executions, 0)) / 1000, 3) AS min_child_avg_elapsed_ms,
  ROUND(MAX(elapsed_time / NULLIF(executions, 0)) / 1000, 3) AS max_child_avg_elapsed_ms,
  SUM(buffer_gets) AS total_buffer_gets,
  MAX(last_active_time) AS last_active_time
FROM v$sql
WHERE UPPER(sql_text) LIKE '%DOWNER_PI_Q01%'
  AND UPPER(sql_text) NOT LIKE '%V$SQL%'
  AND NVL(executions, 0) > 0
GROUP BY sql_id
ORDER BY distinct_plan_hashes DESC, child_cursor_count DESC, total_buffer_gets DESC;

PROMPT DOWNER_PI_Q01 seeded. Use sql-templates/packs/plan-instability/ through RUN_SQL for read-only diagnosis.
