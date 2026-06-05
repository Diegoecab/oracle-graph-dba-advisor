--------------------------------------------------------------------------------
-- 33_stop_fixed_rate_load.sql
-- Stops fixed-rate Mini-DOWNER workload jobs.
--
-- Run as DOWNER_DEMO.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

BEGIN
  stop_downer_fixed_rate_load;
  show_downer_fixed_rate_status;
END;
/

SELECT
  worker.run_id,
  worker.worker_id,
  worker.status,
  worker.executions,
  ROUND(worker.total_elapsed_ms / NULLIF(worker.executions, 0), 3) AS avg_elapsed_ms,
  worker.last_elapsed_ms,
  worker.last_anchor_id,
  worker.last_heartbeat,
  worker.error_message
FROM downer_fixed_rate_workers worker
WHERE worker.run_id = (
  SELECT MAX(run_id)
  FROM downer_fixed_rate_runs
)
ORDER BY worker.worker_id;
