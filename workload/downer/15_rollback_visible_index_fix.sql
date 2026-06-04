--------------------------------------------------------------------------------
-- 15_rollback_visible_index_fix.sql
-- Rolls back lab-only visible indexes used for the dashboard before/after demo.
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
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP INDEX idx_e_uses_device_src_ed_dst';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1418 THEN
      RAISE;
    END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP INDEX idx_e_uses_device_dst_ed_src';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1418 THEN
      RAISE;
    END IF;
END;
/

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(
    ownname => USER,
    tabname => 'E_USES_DEVICE',
    cascade => TRUE,
    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
    no_invalidate => FALSE
  );
END;
/

PROMPT Visible dashboard indexes dropped.
