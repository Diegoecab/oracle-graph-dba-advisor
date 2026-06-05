--------------------------------------------------------------------------------
-- 35_reset_missing_index_baseline.sql
-- Lab-only reset to reproduce the missing-index baseline.
--
-- Run as DOWNER_DEMO. Do not run through the read-only MCP runtime.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

BEGIN
  BEGIN
    EXECUTE IMMEDIATE 'BEGIN stop_downer_fixed_rate_load; END;';
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Fixed-rate stop skipped: ' || SQLERRM);
  END;

  BEGIN
    EXECUTE IMMEDIATE 'BEGIN stop_downer_dashboard_load; END;';
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Dashboard-load stop skipped: ' || SQLERRM);
  END;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP INDEX idx_e_uses_device_src_end_dst';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1418 THEN
      RAISE;
    END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP INDEX idx_e_uses_device_dst_end_src';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1418 THEN
      RAISE;
    END IF;
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

SELECT
  index_name,
  table_name,
  visibility,
  status
FROM user_indexes
WHERE table_name = 'E_USES_DEVICE'
ORDER BY index_name;

PROMPT Missing-index baseline reset complete. Start a fixed-rate window with 32_start_fixed_rate_missing_index_window.sql.
