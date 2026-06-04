--------------------------------------------------------------------------------
-- 27_start_dashboard_load_all_issues_5_days.sql
-- Starts a combined Mini-DOWNER dashboard signal for all three coexistence cases.
--
-- Run as DOWNER_DEMO after:
--   - 10_dashboard_load_setup.sql
--   - 18_setup_supernode_fanout.sql
--   - 22_setup_plan_instability.sql
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

DEFINE dashboard_minutes = 7200

BEGIN
  stop_downer_dashboard_load;
END;
/

BEGIN
  start_downer_dashboard_load(
    p_minutes => &&dashboard_minutes,
    p_workers => 2,
    p_sql_tag => 'DOWNER_MI_Q01_DASH_BEFORE',
    p_anchor_mode => 'MIXED',
    p_stop_existing => 'N'
  );

  start_downer_dashboard_load(
    p_minutes => &&dashboard_minutes,
    p_workers => 1,
    p_sql_tag => 'DOWNER_SN_Q01_DASH',
    p_anchor_mode => 'HOT',
    p_stop_existing => 'N'
  );

  start_downer_dashboard_load(
    p_minutes => &&dashboard_minutes,
    p_workers => 1,
    p_sql_tag => 'DOWNER_PI_Q01_DASH',
    p_anchor_mode => 'MIXED',
    p_stop_existing => 'N'
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
WHERE status = 'RUNNING'
ORDER BY run_id DESC;
