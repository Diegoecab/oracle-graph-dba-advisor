--------------------------------------------------------------------------------
-- 05_run_workload.sql
-- Seeds V$SQL with Mini-DOWNER tagged workloads.
--
-- Run as DOWNER_DEMO.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

CREATE OR REPLACE PROCEDURE run_downer_missing_index_workload (
  p_cycles    NUMBER DEFAULT 20,
  p_anchor_id VARCHAR2 DEFAULT 'U00000042'
) AS
  v_count NUMBER;
BEGIN
  FOR i IN 1 .. p_cycles LOOP
    EXECUTE IMMEDIATE q'[
      SELECT /* DOWNER_MI_Q01 */
             COUNT(*)
      FROM GRAPH_TABLE (downer_graph
        MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                   <-[e2 IS uses_device]- (u2 IS user_account)
        WHERE u1.id = :anchor_id
          AND u1.id <> u2.id
          AND e1.end_date IS NULL
          AND e2.end_date IS NULL
        COLUMNS (
          u2.id AS neighbor_user_id,
          d.id AS shared_device_id,
          e2.device_type AS edge_device_type
        )
      )
    ]'
    INTO v_count
    USING p_anchor_id;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('DOWNER_MI_Q01 cycles=' || p_cycles || ', result_count=' || v_count);
END;
/

CREATE OR REPLACE PROCEDURE run_downer_supernode_workload (
  p_cycles NUMBER DEFAULT 12,
  p_ip_id  VARCHAR2 DEFAULT 'IP00000001'
) AS
  v_count NUMBER;
BEGIN
  FOR i IN 1 .. p_cycles LOOP
    EXECUTE IMMEDIATE q'[
      SELECT /* DOWNER_SN_Q01 */
             COUNT(*)
      FROM GRAPH_TABLE (downer_graph
        MATCH (ipn IS ip) <-[ei IS uses_ip]- (u IS user_account)
                           -[wb IS withdrawal_bank_account]-> (b IS bank_account)
        WHERE ipn.id = :ip_id
          AND ei.end_date IS NULL
          AND wb.end_date IS NULL
        COLUMNS (
          ipn.id AS ip_id,
          u.id AS user_id,
          b.id AS bank_account_id,
          ei.used_at_date AS ip_used_at_date
        )
      )
    ]'
    INTO v_count
    USING p_ip_id;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('DOWNER_SN_Q01 cycles=' || p_cycles || ', result_count=' || v_count);
END;
/

BEGIN
  run_downer_missing_index_workload(p_cycles => 24, p_anchor_id => 'U00000042');
END;
/
