--------------------------------------------------------------------------------
-- 05_run_workload.sql
-- Transaction Fraud Graph — Automated Workload Runner (Oracle 23ai / 26ai)
--
-- TARGET SCHEMA: NEWFRAUD
-- Creates a procedure that runs the workload queries in a loop with random
-- account IDs, simulating real production traffic for V$SQL population.
--
-- Usage:
--   @05_run_workload.sql
--   -- Then execute:
--   EXEC NEWFRAUD.RUN_TX_FRAUD_WORKLOAD(p_iterations => 50);
--------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE NEWFRAUD.RUN_TX_FRAUD_WORKLOAD (
  p_iterations  NUMBER DEFAULT 50
) AS
  v_account_id  NUMBER;
  v_max_account NUMBER;
  v_dummy       NUMBER;
  v_cnt         NUMBER;
  v_start       TIMESTAMP;
BEGIN
  v_start := SYSTIMESTAMP;
  SELECT MAX(id) INTO v_max_account FROM NEWFRAUD.ACCOUNT;

  FOR i IN 1..p_iterations LOOP
    -- Pick a random account (bias toward hot accounts 1-300 for 20% of iterations)
    IF DBMS_RANDOM.VALUE < 0.20 THEN
      v_account_id := TRUNC(DBMS_RANDOM.VALUE(1, 301));
    ELSE
      v_account_id := TRUNC(DBMS_RANDOM.VALUE(1, v_max_account + 1));
    END IF;

    -- Q01: Direct transfer neighbors
    BEGIN
      EXECUTE IMMEDIATE '
        SELECT /* TXFRAUD_Q01 */ COUNT(*) FROM (
          SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
            MATCH (a1 IS account) -[t IS transfers_to]-> (a2 IS account)
            WHERE a1.id = :1
            COLUMNS (a2.id AS rid)
          )
        )' INTO v_cnt USING v_account_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- Q02: Shared IP login
    BEGIN
      EXECUTE IMMEDIATE '
        SELECT /* TXFRAUD_Q02 */ COUNT(*) FROM (
          SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
            MATCH (a1 IS account) -[l1 IS logs_in_from]-> (ip IS ip_address)
                                   <-[l2 IS logs_in_from]- (a2 IS account)
            WHERE a1.id = :1 AND a1.id <> a2.id
            COLUMNS (a2.id AS nid)
          )
        )' INTO v_cnt USING v_account_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- Q03: High-risk merchant purchases
    BEGIN
      EXECUTE IMMEDIATE '
        SELECT /* TXFRAUD_Q03 */ COUNT(*) FROM (
          SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
            MATCH (a IS account) -[p IS purchases_at]-> (m IS merchant)
            WHERE a.id = :1 AND m.is_high_risk = ''Y''
            COLUMNS (m.id AS mid)
          )
        )' INTO v_cnt USING v_account_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- Q04: 2-hop mule chain
    BEGIN
      EXECUTE IMMEDIATE '
        SELECT /* TXFRAUD_Q04 */ COUNT(*) FROM (
          SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
            MATCH (a1 IS account) -[t1 IS transfers_to]-> (a2 IS account)
                                    -[t2 IS transfers_to]-> (a3 IS account)
            WHERE a1.id = :1
              AND a1.id <> a2.id AND a2.id <> a3.id AND a1.id <> a3.id
            COLUMNS (a3.id AS fid)
          ) FETCH FIRST 100 ROWS ONLY
        )' INTO v_cnt USING v_account_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- Q07: ATM cash-out after transfer
    BEGIN
      EXECUTE IMMEDIATE '
        SELECT /* TXFRAUD_Q07 */ COUNT(*) FROM (
          SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
            MATCH (a1 IS account) -[t IS transfers_to]-> (a2 IS account)
                                    -[w IS withdraws_at]-> (atm IS atm)
            WHERE a1.id = :1
            COLUMNS (a2.id AS rid)
          ) FETCH FIRST 100 ROWS ONLY
        )' INTO v_cnt USING v_account_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- Q11: VPN/TOR login detection
    BEGIN
      EXECUTE IMMEDIATE '
        SELECT /* TXFRAUD_Q11 */ COUNT(*) FROM (
          SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
            MATCH (a IS account) -[l IS logs_in_from]-> (ip IS ip_address)
            WHERE a.id = :1 AND (ip.is_vpn = ''Y'' OR ip.is_tor = ''Y'')
            COLUMNS (ip.id AS ipid)
          )
        )' INTO v_cnt USING v_account_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    IF MOD(i, 10) = 0 THEN
      DBMS_OUTPUT.PUT_LINE('Iteration ' || i || '/' || p_iterations ||
        ' (account_id=' || v_account_id || ')');
    END IF;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Workload completed: ' || p_iterations || ' iterations in ' ||
    EXTRACT(SECOND FROM (SYSTIMESTAMP - v_start)) || ' seconds');
END;
/

PROMPT Workload procedure NEWFRAUD.RUN_TX_FRAUD_WORKLOAD created.
PROMPT Run with: EXEC NEWFRAUD.RUN_TX_FRAUD_WORKLOAD(p_iterations => 50);
