--------------------------------------------------------------------------------
-- 32_start_fixed_rate_missing_index_window.sql
-- Starts a fixed-rate graph traversal window for visual impact comparison.
--
-- Run as DOWNER_DEMO after 31_fixed_rate_load_setup.sql.
-- The executed SQL text has no before/after comments; compare by time window.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

DEFINE fixed_minutes = 20
DEFINE fixed_workers = 4
DEFINE fixed_total_execs_per_minute = 1200
DEFINE anchor_mode = MIXED

BEGIN
  start_downer_fixed_rate_missing_index_load(
    p_minutes => &&fixed_minutes,
    p_workers => &&fixed_workers,
    p_total_execs_per_minute => &&fixed_total_execs_per_minute,
    p_anchor_mode => '&&anchor_mode',
    p_stop_existing => 'Y'
  );
END;
/

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
  started_at,
  ends_at
FROM downer_fixed_rate_runs
ORDER BY run_id DESC
FETCH FIRST 1 ROW ONLY;
