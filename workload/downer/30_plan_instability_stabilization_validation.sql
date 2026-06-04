--------------------------------------------------------------------------------
-- 30_plan_instability_stabilization_validation.sql
-- Out-of-band validation for R4 plan-instability mitigation.
--
-- Run as DOWNER_DEMO after 22_setup_plan_instability.sql.
-- Do not run through the read-only MCP diagnostic channel.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON
SET LINESIZE 220
SET PAGESIZE 120

ALTER SESSION SET CURRENT_SCHEMA = DOWNER_DEMO;

BEGIN
  run_downer_plan_instability_workload(
    p_cycles                   => 40,
    p_sql_tag                  => 'DOWNER_PI_Q01_UNSTABLE',
    p_optimizer_mode           => 'ALL_ROWS',
    p_optimizer_index_cost_adj => 10000,
    p_key_mode                 => 'HOT'
  );

  run_downer_plan_instability_workload(
    p_cycles                   => 40,
    p_sql_tag                  => 'DOWNER_PI_Q01_UNSTABLE',
    p_optimizer_mode           => 'FIRST_ROWS_1',
    p_optimizer_index_cost_adj => 1,
    p_key_mode                 => 'HOT'
  );

  run_downer_plan_instability_workload(
    p_cycles                   => 40,
    p_sql_tag                  => 'DOWNER_PI_Q01_UNSTABLE',
    p_optimizer_mode           => 'FIRST_ROWS_1',
    p_optimizer_index_cost_adj => 1,
    p_key_mode                 => 'COLD'
  );

  run_downer_plan_instability_workload(
    p_cycles                   => 40,
    p_sql_tag                  => 'DOWNER_PI_Q01_STABLE',
    p_optimizer_mode           => 'ALL_ROWS',
    p_optimizer_index_cost_adj => 10000,
    p_key_mode                 => 'HOT'
  );

  run_downer_plan_instability_workload(
    p_cycles                   => 40,
    p_sql_tag                  => 'DOWNER_PI_Q01_STABLE',
    p_optimizer_mode           => 'ALL_ROWS',
    p_optimizer_index_cost_adj => 10000,
    p_key_mode                 => 'HOT'
  );
END;
/

WITH tagged_sql AS (
  SELECT
    CASE
      WHEN UPPER(sql_text) LIKE '%DOWNER_PI_Q01_STABLE%' THEN 'STABLE'
      WHEN UPPER(sql_text) LIKE '%DOWNER_PI_Q01_UNSTABLE%' THEN 'UNSTABLE'
      WHEN UPPER(sql_text) LIKE '%DOWNER_PI_Q01%' THEN 'BASE_DEMO'
    END AS run_type,
    sql_id,
    child_number,
    plan_hash_value,
    executions,
    elapsed_time,
    buffer_gets,
    invalidations,
    parse_calls,
    is_bind_sensitive,
    is_bind_aware,
    is_shareable,
    last_active_time
  FROM v$sql
  WHERE UPPER(sql_text) LIKE '%DOWNER_PI_Q01%'
    AND UPPER(sql_text) NOT LIKE '%V$SQL%'
    AND NVL(executions, 0) > 0
)
SELECT
  run_type,
  sql_id,
  COUNT(*) AS child_cursor_count,
  COUNT(DISTINCT plan_hash_value) AS distinct_plan_hashes,
  SUM(executions) AS total_executions,
  ROUND(SUM(elapsed_time) / NULLIF(SUM(executions), 0) / 1e3, 3) AS avg_elapsed_ms,
  ROUND(MIN(elapsed_time / NULLIF(executions, 0)) / 1e3, 3) AS min_child_avg_elapsed_ms,
  ROUND(MAX(elapsed_time / NULLIF(executions, 0)) / 1e3, 3) AS max_child_avg_elapsed_ms,
  ROUND(MAX(elapsed_time / NULLIF(executions, 0)) / NULLIF(MIN(elapsed_time / NULLIF(executions, 0)), 0), 2) AS elapsed_ratio,
  ROUND(SUM(buffer_gets) / NULLIF(SUM(executions), 0)) AS avg_buffer_gets,
  SUM(invalidations) AS total_invalidations,
  SUM(parse_calls) AS total_parse_calls,
  MAX(last_active_time) AS last_active_time
FROM tagged_sql
WHERE run_type IS NOT NULL
GROUP BY run_type, sql_id
ORDER BY
  CASE run_type WHEN 'UNSTABLE' THEN 1 WHEN 'BASE_DEMO' THEN 2 ELSE 3 END,
  distinct_plan_hashes DESC,
  child_cursor_count DESC;

SELECT
  sql_id,
  child_number,
  plan_hash_value,
  executions,
  ROUND(elapsed_time / NULLIF(executions, 0) / 1e3, 3) AS avg_elapsed_ms,
  ROUND(buffer_gets / NULLIF(executions, 0)) AS avg_buffer_gets,
  invalidations,
  parse_calls,
  is_bind_sensitive,
  is_bind_aware,
  is_shareable,
  last_active_time
FROM v$sql
WHERE UPPER(sql_text) LIKE '%DOWNER_PI_Q01_UNSTABLE%'
  AND UPPER(sql_text) NOT LIKE '%V$SQL%'
  AND NVL(executions, 0) > 0
ORDER BY sql_id, child_number;

PROMPT Plan-stability mitigation proof complete. Stable execution uses one controlled optimizer environment; production remediation should use bind discipline, consistent optimizer settings, or DBA-approved SQL Plan Management.
