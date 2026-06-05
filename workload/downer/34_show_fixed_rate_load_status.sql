--------------------------------------------------------------------------------
-- 34_show_fixed_rate_load_status.sql
-- Shows fixed-rate Mini-DOWNER run and worker status.
--
-- Run as DOWNER_DEMO.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON
SET LINESIZE 220
SET PAGESIZE 120

BEGIN
  show_downer_fixed_rate_status;
END;
/

SELECT
  run_id,
  workload_name,
  status,
  requested_workers,
  target_execs_per_minute,
  total_executions,
  ROUND(total_elapsed_ms / NULLIF(total_executions, 0), 3) AS avg_elapsed_ms,
  started_at,
  stopped_at,
  ends_at
FROM downer_fixed_rate_runs
ORDER BY run_id DESC
FETCH FIRST 10 ROWS ONLY;

SELECT
  worker.run_id,
  worker.worker_id,
  worker.status,
  worker.target_execs_per_minute,
  worker.executions,
  ROUND(worker.total_elapsed_ms / NULLIF(worker.executions, 0), 3) AS avg_elapsed_ms,
  worker.last_elapsed_ms,
  worker.last_anchor_id,
  worker.last_result_count,
  worker.last_heartbeat,
  worker.error_message
FROM downer_fixed_rate_workers worker
WHERE worker.run_id = (
  SELECT MAX(run_id)
  FROM downer_fixed_rate_runs
)
ORDER BY worker.worker_id;

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
WHERE module = 'MINI_DOWNER_FIXED_RATE_LOAD'
  AND UPPER(sql_text) LIKE '%GRAPH_TABLE%'
ORDER BY last_active_time DESC
FETCH FIRST 10 ROWS ONLY;
