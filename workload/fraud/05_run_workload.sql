--------------------------------------------------------------------------------
-- 05_run_workload.sql
-- Fraud Detection Graph — Automated Workload Runner (Oracle 23ai / 26ai)
--
-- TARGET SCHEMA: MYSCHEMA
-- Uses EXECUTE IMMEDIATE for all GRAPH_TABLE queries (ORA-49028 workaround).
--
-- Usage:
--   @05_run_workload.sql
--   -- or with custom iterations:
--   EXEC run_fraud_workload(p_iterations => 500);
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON
SET TIMING ON

CREATE OR REPLACE PROCEDURE run_fraud_workload (
  p_iterations  IN NUMBER DEFAULT 200,
  p_verbose     IN BOOLEAN DEFAULT FALSE
) AS
  v_user_id     NUMBER;
  v_ts          TIMESTAMP;
  v_max_user    NUMBER;
  v_rand        NUMBER;
  v_cnt         NUMBER;
  v_start       TIMESTAMP;
  v_elapsed     INTERVAL DAY TO SECOND;
  -- Counters per query type
  v_q01_cnt     NUMBER := 0;
  v_q03_cnt     NUMBER := 0;
  v_q04_cnt     NUMBER := 0;
  v_q06_cnt     NUMBER := 0;
  v_q07_cnt     NUMBER := 0;
  v_q09_cnt     NUMBER := 0;
  v_q11_cnt     NUMBER := 0;
  v_q12_cnt     NUMBER := 0;
  v_q13_cnt     NUMBER := 0;
  v_q14_cnt     NUMBER := 0;
BEGIN
  SELECT MAX(id) INTO v_max_user FROM MYSCHEMA.n_user;
  v_start := SYSTIMESTAMP;

  DBMS_OUTPUT.PUT_LINE('=== Fraud Graph Workload Started ===');
  DBMS_OUTPUT.PUT_LINE('Iterations: ' || p_iterations);
  DBMS_OUTPUT.PUT_LINE('Max user ID: ' || v_max_user);
  DBMS_OUTPUT.PUT_LINE('Start time: ' || TO_CHAR(v_start, 'HH24:MI:SS.FF3'));

  FOR i IN 1..p_iterations LOOP
    -- Random user and timestamp for each iteration
    v_user_id := TRUNC(DBMS_RANDOM.VALUE(1, v_max_user + 1));
    v_ts := SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 60);  -- last 1-60 days
    v_rand := DBMS_RANDOM.VALUE(0, 100);

    IF v_rand < 30 THEN
      -----------------------------------------------------------
      -- Q01: 1-hop via shared device (30%)
      -----------------------------------------------------------
      EXECUTE IMMEDIATE '
        SELECT COUNT(*) FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
          MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                     <-[e2 IS uses_device]- (u2 IS user_account)
          WHERE u1.id = :p_uid
            AND u1.id <> u2.id
            AND e1.end_date IS NULL
            AND e2.end_date IS NULL
          COLUMNS (u2.id AS neighbor_id)
        )' INTO v_cnt USING v_user_id;
      v_q01_cnt := v_q01_cnt + 1;
      IF p_verbose THEN
        DBMS_OUTPUT.PUT_LINE('[Q01] user=' || v_user_id || ' neighbors=' || v_cnt);
      END IF;

    ELSIF v_rand < 55 THEN
      -----------------------------------------------------------
      -- Q03: 1-hop via shared card (25%)
      -----------------------------------------------------------
      EXECUTE IMMEDIATE '
        SELECT COUNT(*) FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
          MATCH (u1 IS user_account) -[e1 IS uses_card]-> (c IS card)
                                     <-[e2 IS uses_card]- (u2 IS user_account)
          WHERE u1.id = :p_uid
            AND u1.id <> u2.id
            AND e1.end_date IS NULL
            AND e2.end_date IS NULL
          COLUMNS (u2.id AS neighbor_id)
        )' INTO v_cnt USING v_user_id;
      v_q03_cnt := v_q03_cnt + 1;

    ELSIF v_rand < 70 THEN
      -----------------------------------------------------------
      -- Q07: Total edge count (15%)
      -----------------------------------------------------------
      EXECUTE IMMEDIATE '
        SELECT COUNT(*) FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
          MATCH (u IS user_account) -[e]-> (v)
          WHERE u.id = :p_uid
            AND e.end_date IS NULL
          COLUMNS (v.id AS vid)
        )' INTO v_cnt USING v_user_id;
      v_q07_cnt := v_q07_cnt + 1;

    ELSIF v_rand < 80 THEN
      -----------------------------------------------------------
      -- Q06: Edge change detection (10%)
      -----------------------------------------------------------
      EXECUTE IMMEDIATE '
        SELECT COUNT(*) FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
          MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                     <-[e2 IS uses_device]- (u2 IS user_account)
          WHERE u1.id = :p_uid
            AND e2.start_date > :p_tstamp
            AND e1.end_date IS NULL
            AND e2.end_date IS NULL
          COLUMNS (u2.id AS neighbor_id)
        )' INTO v_cnt USING v_user_id, v_ts;
      v_q06_cnt := v_q06_cnt + 1;

    ELSIF v_rand < 88 THEN
      -----------------------------------------------------------
      -- Q09: Temporal + degree filter (8%)
      -----------------------------------------------------------
      EXECUTE IMMEDIATE '
        SELECT COUNT(*) FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
          MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                     <-[e2 IS uses_device]- (u2 IS user_account)
          WHERE u1.id = :p_uid
            AND d.adjacent_edges_count < 200
            AND e1.last_updated > :p_tstamp
            AND e2.last_updated > :p_tstamp
            AND e1.end_date IS NULL
            AND e2.end_date IS NULL
          COLUMNS (u2.id AS neighbor_id)
        )' INTO v_cnt USING v_user_id, v_ts;
      v_q09_cnt := v_q09_cnt + 1;

    ELSIF v_rand < 93 THEN
      -----------------------------------------------------------
      -- Q11: High-risk neighbors (5%)
      -----------------------------------------------------------
      EXECUTE IMMEDIATE '
        SELECT COUNT(*) FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
          MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                     <-[e2 IS uses_device]- (u2 IS user_account)
          WHERE u1.id = :p_uid
            AND u2.risk_score > 60
            AND u1.id <> u2.id
            AND e1.end_date IS NULL
            AND e2.end_date IS NULL
          COLUMNS (u2.id AS neighbor_id)
        )' INTO v_cnt USING v_user_id;
      v_q11_cnt := v_q11_cnt + 1;

    ELSIF v_rand < 96 THEN
      -----------------------------------------------------------
      -- Q04: 2-hop via device (3%)
      -----------------------------------------------------------
      EXECUTE IMMEDIATE '
        SELECT COUNT(*) FROM (
          SELECT 1 FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
            MATCH (u1 IS user_account)
                    -[e1 IS uses_device]-> (d1 IS device)
                   <-[e2 IS uses_device]- (u2 IS user_account)
                    -[e3 IS uses_device]-> (d2 IS device)
                   <-[e4 IS uses_device]- (u3 IS user_account)
            WHERE u1.id = :p_uid
              AND u1.id <> u2.id AND u2.id <> u3.id AND u1.id <> u3.id
              AND e1.end_date IS NULL AND e2.end_date IS NULL
              AND e3.end_date IS NULL AND e4.end_date IS NULL
            COLUMNS (u3.id AS neighbor_id)
          )
          FETCH FIRST 100 ROWS ONLY
        )' INTO v_cnt USING v_user_id;
      v_q04_cnt := v_q04_cnt + 1;

    ELSIF v_rand < 98 THEN
      -----------------------------------------------------------
      -- Q12: Shared entity summary (2%)
      -----------------------------------------------------------
      EXECUTE IMMEDIATE '
        SELECT COUNT(DISTINCT neighbor_id) FROM (
          SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
            MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                       <-[e2 IS uses_device]- (u2 IS user_account)
            WHERE u1.id = :p_uid AND u1.id <> u2.id
              AND e1.end_date IS NULL AND e2.end_date IS NULL
            COLUMNS (u2.id AS neighbor_id)
          )
          UNION ALL
          SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
            MATCH (u1 IS user_account) -[e1 IS uses_card]-> (c IS card)
                                       <-[e2 IS uses_card]- (u2 IS user_account)
            WHERE u1.id = :p_uid2 AND u1.id <> u2.id
              AND e1.end_date IS NULL AND e2.end_date IS NULL
            COLUMNS (u2.id AS neighbor_id)
          )
        )' INTO v_cnt USING v_user_id, v_user_id;
      v_q12_cnt := v_q12_cnt + 1;

    ELSIF v_rand < 99 THEN
      -----------------------------------------------------------
      -- Q13: Triangle detection (1%)
      -----------------------------------------------------------
      EXECUTE IMMEDIATE '
        SELECT COUNT(*) FROM (
          SELECT 1 FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
            MATCH (u1 IS user_account) -[e1 IS uses_device]->     (d IS device)
                                       <-[e2 IS uses_device]-      (u2 IS user_account)
                                        -[e3 IS uses_card]->       (c IS card)
                                       <-[e4 IS uses_card]-        (u3 IS user_account)
                                        -[e5 IS validates_person]-> (p IS person)
                                       <-[e6 IS validates_person]-  (u1)
            WHERE u1.id <> u2.id AND u2.id <> u3.id AND u1.id <> u3.id
              AND e1.end_date IS NULL AND e2.end_date IS NULL
              AND e3.end_date IS NULL AND e4.end_date IS NULL
              AND e5.end_date IS NULL AND e6.end_date IS NULL
            COLUMNS (u1.id AS u1_id)
          )
          FETCH FIRST 10 ROWS ONLY
        )' INTO v_cnt;
      v_q13_cnt := v_q13_cnt + 1;

    ELSE
      -----------------------------------------------------------
      -- Q14: Blocked user network (1%)
      -----------------------------------------------------------
      EXECUTE IMMEDIATE '
        SELECT COUNT(*) FROM (
          SELECT 1 FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
            MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                       <-[e2 IS uses_device]- (u2 IS user_account)
            WHERE u1.is_blocked = ''Y''
              AND u2.is_blocked = ''N''
              AND e1.end_date IS NULL
              AND e2.end_date IS NULL
            COLUMNS (u2.id AS neighbor_id)
          )
          FETCH FIRST 200 ROWS ONLY
        )' INTO v_cnt;
      v_q14_cnt := v_q14_cnt + 1;
    END IF;

    -- Progress every 50 iterations
    IF MOD(i, 50) = 0 THEN
      DBMS_OUTPUT.PUT_LINE('Progress: ' || i || '/' || p_iterations ||
        ' (' || ROUND(i/p_iterations*100) || '%)');
    END IF;
  END LOOP;

  v_elapsed := SYSTIMESTAMP - v_start;

  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('=== Fraud Graph Workload Completed ===');
  DBMS_OUTPUT.PUT_LINE('Total time: ' || v_elapsed);
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('Query distribution:');
  DBMS_OUTPUT.PUT_LINE('  Q01 (1-hop device):     ' || v_q01_cnt);
  DBMS_OUTPUT.PUT_LINE('  Q03 (1-hop card):       ' || v_q03_cnt);
  DBMS_OUTPUT.PUT_LINE('  Q07 (edge count):       ' || v_q07_cnt);
  DBMS_OUTPUT.PUT_LINE('  Q06 (change detection): ' || v_q06_cnt);
  DBMS_OUTPUT.PUT_LINE('  Q09 (temporal+degree):  ' || v_q09_cnt);
  DBMS_OUTPUT.PUT_LINE('  Q11 (high-risk):        ' || v_q11_cnt);
  DBMS_OUTPUT.PUT_LINE('  Q04 (2-hop device):     ' || v_q04_cnt);
  DBMS_OUTPUT.PUT_LINE('  Q12 (aggregated):       ' || v_q12_cnt);
  DBMS_OUTPUT.PUT_LINE('  Q13 (triangle):         ' || v_q13_cnt);
  DBMS_OUTPUT.PUT_LINE('  Q14 (blocked network):  ' || v_q14_cnt);
END;
/

-- Execute with default 200 iterations
EXEC run_fraud_workload(p_iterations => 200, p_verbose => FALSE);
