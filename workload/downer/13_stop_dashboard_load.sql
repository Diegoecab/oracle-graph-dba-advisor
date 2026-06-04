--------------------------------------------------------------------------------
-- 13_stop_dashboard_load.sql
-- Stops Mini-DOWNER dashboard load jobs.
--
-- Run as DOWNER_DEMO.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

BEGIN
  stop_downer_dashboard_load;
  show_downer_dashboard_load_status;
END;
/

SELECT
  run_id,
  worker_id,
  job_name,
  status,
  executions,
  last_anchor_id,
  last_result_count,
  last_heartbeat,
  error_message
FROM downer_dashboard_load_workers
WHERE run_id = (
  SELECT MAX(run_id)
  FROM downer_dashboard_load_runs
)
ORDER BY worker_id;
