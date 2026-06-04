--------------------------------------------------------------------------------
-- 19_run_supernode_workload.sql
-- Seeds V$SQL with the DOWNER_SN_Q01 supernode / fan-out workload.
--
-- Run as DOWNER_DEMO after 18_setup_supernode_fanout.sql.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

CREATE OR REPLACE PROCEDURE run_downer_supernode_workload (
  p_cycles    NUMBER DEFAULT 12,
  p_device_id VARCHAR2 DEFAULT 'D00000001'
) AS
  v_count NUMBER;
BEGIN
  FOR i IN 1 .. p_cycles LOOP
    EXECUTE IMMEDIATE q'[
      SELECT /* DOWNER_SN_Q01 */
             COUNT(*)
      FROM GRAPH_TABLE (downer_graph
        MATCH (d IS device) <-[ed IS uses_device]- (u IS user_account)
                            -[wb IS withdrawal_bank_account]-> (b IS bank_account)
        WHERE d.id = :device_id
          AND ed.end_date IS NULL
          AND wb.end_date IS NULL
        COLUMNS (
          d.id AS device_id,
          u.id AS user_id,
          b.id AS bank_account_id,
          ed.device_type AS device_edge_type
        )
      )
    ]'
    INTO v_count
    USING p_device_id;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('DOWNER_SN_Q01 cycles=' || p_cycles || ', result_count=' || v_count);
END;
/

BEGIN
  run_downer_supernode_workload(p_cycles => 16, p_device_id => 'D00000001');
END;
/
