--------------------------------------------------------------------------------
-- 05_run_workload.sql
-- Fraud Detection Graph — Automated Workload Runner (Oracle 23ai / 26ai)
--
-- Simulates realistic workload by executing queries with random user IDs
-- and timestamps, replicating the execution frequency distribution from AWR.
--
-- Execution distribution (from AWR, normalized):
--   Q01 (1-hop device):     HIGH   — 30% of executions
--   Q03 (1-hop card):       HIGH   — 25% of executions
--   Q07 (edge count):       MEDIUM — 15% of executions
--   Q06 (change detection): MEDIUM — 10% of executions
--   Q09 (temporal+degree):  MEDIUM — 8% of executions
--   Q11 (high-risk):        LOW    — 5% of executions
--   Q04 (2-hop device):     LOW    — 3% of executions
--   Q12 (aggregated):       LOW    — 2% of executions
--   Q13 (triangle):         RARE   — 1% of executions
--   Q14 (blocked network):  RARE   — 1% of executions
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
  SELECT MAX(id) INTO v_max_user FROM n_user;
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
      SELECT COUNT(*) INTO v_cnt
      FROM GRAPH_TABLE (fraud_graph
        MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                   <-[e2 IS uses_device]- (u2 IS user_account)
        WHERE u1.id = v_user_id
          AND u1.id <> u2.id
          AND e1.end_date IS NULL
          AND e2.end_date IS NULL
        COLUMNS (u2.id AS neighbor_id)
      );
      v_q01_cnt := v_q01_cnt + 1;
      IF p_verbose THEN
        DBMS_OUTPUT.PUT_LINE('[Q01] user=' || v_user_id || ' neighbors=' || v_cnt);
      END IF;

    ELSIF v_rand < 55 THEN
      -----------------------------------------------------------
      -- Q03: 1-hop via shared card (25%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt
      FROM GRAPH_TABLE (fraud_graph
        MATCH (u1 IS user_account) -[e1 IS uses_card]-> (c IS card)
                                   <-[e2 IS uses_card]- (u2 IS user_account)
        WHERE u1.id = v_user_id
          AND u1.id <> u2.id
          AND e1.end_date IS NULL
          AND e2.end_date IS NULL
        COLUMNS (u2.id AS neighbor_id)
      );
      v_q03_cnt := v_q03_cnt + 1;

    ELSIF v_rand < 70 THEN
      -----------------------------------------------------------
      -- Q07: Total edge count (15%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt
      FROM GRAPH_TABLE (fraud_graph
        MATCH (u IS user_account) -[e]-> (v)
        WHERE u.id = v_user_id
          AND e.end_date IS NULL
        COLUMNS (v.id AS vid)
      );
      v_q07_cnt := v_q07_cnt + 1;

    ELSIF v_rand < 80 THEN
      -----------------------------------------------------------
      -- Q06: Edge change detection (10%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt
      FROM GRAPH_TABLE (fraud_graph
        MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                   <-[e2 IS uses_device]- (u2 IS user_account)
        WHERE u1.id = v_user_id
          AND e2.start_date > v_ts
          AND e1.end_date IS NULL
          AND e2.end_date IS NULL
        COLUMNS (u2.id AS neighbor_id)
      );
      v_q06_cnt := v_q06_cnt + 1;

    ELSIF v_rand < 88 THEN
      -----------------------------------------------------------
      -- Q09: Temporal + degree filter (8%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt
      FROM GRAPH_TABLE (fraud_graph
        MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                   <-[e2 IS uses_device]- (u2 IS user_account)
        WHERE u1.id = v_user_id
          AND d.adjacent_edges_count < 200
          AND e1.last_updated > v_ts
          AND e2.last_updated > v_ts
          AND e1.end_date IS NULL
          AND e2.end_date IS NULL
        COLUMNS (u2.id AS neighbor_id)
      );
      v_q09_cnt := v_q09_cnt + 1;

    ELSIF v_rand < 93 THEN
      -----------------------------------------------------------
      -- Q11: High-risk neighbors (5%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt
      FROM GRAPH_TABLE (fraud_graph
        MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                   <-[e2 IS uses_device]- (u2 IS user_account)
        WHERE u1.id = v_user_id
          AND u2.risk_score > 60
          AND u1.id <> u2.id
          AND e1.end_date IS NULL
          AND e2.end_date IS NULL
        COLUMNS (u2.id AS neighbor_id)
      );
      v_q11_cnt := v_q11_cnt + 1;

    ELSIF v_rand < 96 THEN
      -----------------------------------------------------------
      -- Q04: 2-hop via device (3%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt FROM (
        SELECT 1 FROM GRAPH_TABLE (fraud_graph
          MATCH (u1 IS user_account)
                  -[e1 IS uses_device]-> (d1 IS device)
                 <-[e2 IS uses_device]- (u2 IS user_account)
                  -[e3 IS uses_device]-> (d2 IS device)
                 <-[e4 IS uses_device]- (u3 IS user_account)
          WHERE u1.id = v_user_id
            AND u1.id <> u2.id AND u2.id <> u3.id AND u1.id <> u3.id
            AND e1.end_date IS NULL AND e2.end_date IS NULL
            AND e3.end_date IS NULL AND e4.end_date IS NULL
          COLUMNS (u3.id AS neighbor_id)
        )
        FETCH FIRST 100 ROWS ONLY
      );
      v_q04_cnt := v_q04_cnt + 1;

    ELSIF v_rand < 98 THEN
      -----------------------------------------------------------
      -- Q12: Shared entity summary (2%)
      -----------------------------------------------------------
      SELECT COUNT(DISTINCT neighbor_id) INTO v_cnt FROM (
        SELECT * FROM GRAPH_TABLE (fraud_graph
          MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                     <-[e2 IS uses_device]- (u2 IS user_account)
          WHERE u1.id = v_user_id AND u1.id <> u2.id
            AND e1.end_date IS NULL AND e2.end_date IS NULL
          COLUMNS (u2.id AS neighbor_id)
        )
        UNION ALL
        SELECT * FROM GRAPH_TABLE (fraud_graph
          MATCH (u1 IS user_account) -[e1 IS uses_card]-> (c IS card)
                                     <-[e2 IS uses_card]- (u2 IS user_account)
          WHERE u1.id = v_user_id AND u1.id <> u2.id
            AND e1.end_date IS NULL AND e2.end_date IS NULL
          COLUMNS (u2.id AS neighbor_id)
        )
      );
      v_q12_cnt := v_q12_cnt + 1;

    ELSIF v_rand < 99 THEN
      -----------------------------------------------------------
      -- Q13: Triangle detection (1%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt FROM (
        SELECT 1 FROM GRAPH_TABLE (fraud_graph
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
      );
      v_q13_cnt := v_q13_cnt + 1;

    ELSE
      -----------------------------------------------------------
      -- Q14: Blocked user network (1%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt FROM (
        SELECT 1 FROM GRAPH_TABLE (fraud_graph
          MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                     <-[e2 IS uses_device]- (u2 IS user_account)
          WHERE u1.is_blocked = 'Y'
            AND u2.is_blocked = 'N'
            AND e1.end_date IS NULL
            AND e2.end_date IS NULL
          COLUMNS (u2.id AS neighbor_id)
        )
        FETCH FIRST 200 ROWS ONLY
      );
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
-- Increase for longer sustained workload (e.g., 2000 for ~10-15 min)
EXEC run_fraud_workload(p_iterations => 200, p_verbose => FALSE);
