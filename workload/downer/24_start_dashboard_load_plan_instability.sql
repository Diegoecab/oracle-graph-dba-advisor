--------------------------------------------------------------------------------
-- 24_start_dashboard_load_plan_instability.sql
-- Starts the Mini-DOWNER plan-instability workload for ADB Performance Dashboard.
--
-- Run as DOWNER_DEMO after 10_dashboard_load_setup.sql and
-- 22_setup_plan_instability.sql.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON

BEGIN
  start_downer_dashboard_load(
    p_minutes     => 120,
    p_workers     => 4,
    p_sql_tag     => 'DOWNER_PI_Q01_DASH',
    p_anchor_mode => 'MIXED'
  );
END;
/

BEGIN
  show_downer_dashboard_load_status;
END;
/
