--------------------------------------------------------------------------------
-- 16_start_dashboard_load_before_long.sql
-- Starts a longer bad-state Mini-DOWNER workload for live dashboard demos.
--
-- Run as DOWNER_DEMO after 10_dashboard_load_setup.sql.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

DEFINE dashboard_minutes = 120
DEFINE dashboard_workers = 4
DEFINE anchor_mode = MIXED

BEGIN
  start_downer_dashboard_load(
    p_minutes => &&dashboard_minutes,
    p_workers => &&dashboard_workers,
    p_sql_tag => 'DOWNER_MI_Q01_DASH_BEFORE',
    p_anchor_mode => '&&anchor_mode'
  );
END;
/

BEGIN
  show_downer_dashboard_load_status;
END;
/

SELECT
  run_id,
  sql_tag,
  status,
  requested_workers,
  started_at,
  ends_at
FROM downer_dashboard_load_runs
ORDER BY run_id DESC
FETCH FIRST 1 ROW ONLY;
