--------------------------------------------------------------------------------
-- 36_apply_missing_index_fix.sql
-- Lab-only visible remediation for the fixed-rate visual impact demo.
--
-- Run as DOWNER_DEMO after baseline evidence is captured.
-- Do not run through the read-only MCP runtime.
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

CREATE INDEX idx_e_uses_device_src_end_dst
  ON e_uses_device (src, end_date, dst);

CREATE INDEX idx_e_uses_device_dst_end_src
  ON e_uses_device (dst, end_date, src);

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

PROMPT Missing-index fix applied. Start a second fixed-rate window with 32_start_fixed_rate_missing_index_window.sql.
