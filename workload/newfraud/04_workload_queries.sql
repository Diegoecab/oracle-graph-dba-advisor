--------------------------------------------------------------------------------
-- 04_workload_queries.sql
-- Transaction Fraud Graph — Workload Queries (Oracle 23ai / 26ai SQL/PGQ)
--
-- TARGET SCHEMA: NEWFRAUD
-- Graph: NEWFRAUD.TX_FRAUD_GRAPH
--
-- Focus: Transaction-based fraud patterns — mule chains, shared IPs,
--        high-risk merchant networks, ATM cash-out, triangular transfers.
--
-- Usage: Run with bind variables or replace :account_id / :ts with literals.
--        Each query has a comment tag /* TXFRAUD_QNN */ for easy identification.
--------------------------------------------------------------------------------

SET TIMING ON
SET LINESIZE 200
SET PAGESIZE 100

--------------------------------------------------------------------------------
-- Q1: DIRECT TRANSFER NEIGHBORS (who did this account send money to?)
--------------------------------------------------------------------------------
/* TXFRAUD_Q01 */ -- 1-hop outgoing transfers
SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
  MATCH (a1 IS account) -[t IS transfers_to]-> (a2 IS account)
  WHERE a1.id = :account_id
  COLUMNS (
    a2.id            AS recipient_id,
    a2.holder_name   AS recipient_name,
    a2.risk_level    AS recipient_risk,
    a2.is_frozen     AS recipient_frozen,
    t.amount         AS tx_amount,
    t.channel        AS tx_channel,
    t.is_flagged     AS flagged,
    t.created_at     AS tx_date
  )
);

--------------------------------------------------------------------------------
-- Q2: SHARED IP LOGIN (accounts logging in from the same IP)
--------------------------------------------------------------------------------
/* TXFRAUD_Q02 */ -- 1-hop via shared IP
SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
  MATCH (a1 IS account) -[l1 IS logs_in_from]-> (ip IS ip_address)
                         <-[l2 IS logs_in_from]- (a2 IS account)
  WHERE a1.id = :account_id
    AND a1.id <> a2.id
  COLUMNS (
    a2.id            AS neighbor_id,
    a2.holder_name   AS neighbor_name,
    a2.risk_level    AS neighbor_risk,
    ip.country       AS ip_country,
    ip.is_vpn        AS is_vpn,
    ip.is_tor        AS is_tor,
    l1.device_type   AS my_device,
    l2.device_type   AS their_device
  )
);

--------------------------------------------------------------------------------
-- Q3: PURCHASES AT HIGH-RISK MERCHANTS
--------------------------------------------------------------------------------
/* TXFRAUD_Q03 */ -- Purchases at high-risk merchants for an account
SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
  MATCH (a IS account) -[p IS purchases_at]-> (m IS merchant)
  WHERE a.id = :account_id
    AND m.is_high_risk = 'Y'
  COLUMNS (
    m.id             AS merchant_id,
    m.merchant_name  AS merchant_name,
    m.category       AS merchant_category,
    m.country        AS merchant_country,
    p.amount         AS purchase_amount,
    p.is_flagged     AS flagged,
    p.created_at     AS purchase_date
  )
);

--------------------------------------------------------------------------------
-- Q4: 2-HOP MULE CHAIN (A sends to B, B sends to C)
--------------------------------------------------------------------------------
/* TXFRAUD_Q04 */ -- 2-hop transfer chain (mule detection)
SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
  MATCH (a1 IS account) -[t1 IS transfers_to]-> (a2 IS account)
                          -[t2 IS transfers_to]-> (a3 IS account)
  WHERE a1.id = :account_id
    AND a1.id <> a2.id
    AND a2.id <> a3.id
    AND a1.id <> a3.id
  COLUMNS (
    a2.id            AS mule_id,
    a2.holder_name   AS mule_name,
    a2.risk_level    AS mule_risk,
    a3.id            AS final_recipient_id,
    a3.holder_name   AS final_recipient_name,
    a3.risk_level    AS final_risk,
    t1.amount        AS hop1_amount,
    t1.channel       AS hop1_channel,
    t2.amount        AS hop2_amount,
    t2.channel       AS hop2_channel
  )
)
FETCH FIRST 100 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q5: TRIANGULAR TRANSFER (A->B->C->A — money laundering ring)
--------------------------------------------------------------------------------
/* TXFRAUD_Q05 */ -- Circular transfer triangle
SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
  MATCH (a1 IS account) -[t1 IS transfers_to]-> (a2 IS account)
                          -[t2 IS transfers_to]-> (a3 IS account)
                          -[t3 IS transfers_to]-> (a1)
  WHERE a1.id <> a2.id
    AND a2.id <> a3.id
    AND a1.id <> a3.id
  COLUMNS (
    a1.id AS account1_id, a1.holder_name AS account1_name, a1.risk_level AS risk1,
    a2.id AS account2_id, a2.holder_name AS account2_name, a2.risk_level AS risk2,
    a3.id AS account3_id, a3.holder_name AS account3_name, a3.risk_level AS risk3,
    t1.amount AS amount_1to2, t1.channel AS channel_1to2,
    t2.amount AS amount_2to3, t2.channel AS channel_2to3,
    t3.amount AS amount_3to1, t3.channel AS channel_3to1
  )
)
FETCH FIRST 50 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q6: CROSS-TYPE 2-HOP (transfer recipient shares IP with suspect)
--------------------------------------------------------------------------------
/* TXFRAUD_Q06 */ -- Transfer + shared IP cross-type
SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
  MATCH (a1 IS account) -[t IS transfers_to]->  (a2 IS account)
                          -[l1 IS logs_in_from]-> (ip IS ip_address)
                         <-[l2 IS logs_in_from]-  (a3 IS account)
  WHERE a1.id = :account_id
    AND a1.id <> a2.id
    AND a2.id <> a3.id
    AND a1.id <> a3.id
  COLUMNS (
    a2.id            AS transfer_recipient,
    a3.id            AS ip_neighbor_id,
    a3.holder_name   AS ip_neighbor_name,
    a3.risk_level    AS ip_neighbor_risk,
    ip.is_vpn        AS shared_ip_vpn,
    ip.is_tor        AS shared_ip_tor,
    t.amount         AS transfer_amount
  )
)
FETCH FIRST 100 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q7: ATM CASH-OUT AFTER TRANSFER (receive money then withdraw at ATM)
--------------------------------------------------------------------------------
/* TXFRAUD_Q07 */ -- Transfer in + ATM withdrawal pattern
SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
  MATCH (a1 IS account) -[t IS transfers_to]-> (a2 IS account)
                          -[w IS withdraws_at]-> (atm IS atm)
  WHERE a1.id = :account_id
  COLUMNS (
    a2.id            AS recipient_id,
    a2.holder_name   AS recipient_name,
    a2.risk_level    AS recipient_risk,
    t.amount         AS transfer_amount,
    t.channel        AS transfer_channel,
    w.amount         AS withdrawal_amount,
    atm.city         AS atm_city,
    atm.country      AS atm_country
  )
)
FETCH FIRST 100 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q8: MERCHANT-ATM CO-LOCATION (purchase at merchant near ATM withdrawal)
--------------------------------------------------------------------------------
/* TXFRAUD_Q08 */ -- Purchase + nearby ATM withdrawal cross-pattern
SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
  MATCH (a IS account) -[p IS purchases_at]-> (m IS merchant)
                         -[o IS located_near]-> (atm IS atm)
                        <-[w IS withdraws_at]-  (a)
  WHERE a.id = :account_id
  COLUMNS (
    m.merchant_name  AS merchant,
    m.category       AS merchant_category,
    p.amount         AS purchase_amount,
    atm.atm_code     AS atm_code,
    atm.city         AS atm_city,
    w.amount         AS withdrawal_amount,
    o.distance_km    AS distance_km
  )
)
FETCH FIRST 50 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q9: FROZEN ACCOUNT NETWORK (who transacted with frozen accounts?)
--------------------------------------------------------------------------------
/* TXFRAUD_Q09 */ -- Neighbors of frozen accounts
SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
  MATCH (frozen IS account) -[t IS transfers_to]-> (neighbor IS account)
  WHERE frozen.is_frozen = 'Y'
    AND neighbor.is_frozen = 'N'
  COLUMNS (
    frozen.id          AS frozen_account_id,
    frozen.holder_name AS frozen_holder,
    neighbor.id        AS neighbor_id,
    neighbor.holder_name AS neighbor_name,
    neighbor.risk_level  AS neighbor_risk,
    t.amount           AS tx_amount,
    t.channel          AS tx_channel,
    t.is_flagged       AS flagged
  )
)
ORDER BY t.amount DESC
FETCH FIRST 200 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q10: FLAGGED TRANSFER SUMMARY (aggregated by recipient)
--------------------------------------------------------------------------------
/* TXFRAUD_Q10 */ -- Top recipients of flagged transfers
SELECT recipient_id, recipient_name, recipient_risk,
       COUNT(*)        AS flagged_count,
       SUM(tx_amount)  AS total_flagged_amount,
       MIN(tx_date)    AS first_flagged,
       MAX(tx_date)    AS last_flagged
FROM (
  SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
    MATCH (a1 IS account) -[t IS transfers_to]-> (a2 IS account)
    WHERE t.is_flagged = 'Y'
    COLUMNS (
      a2.id          AS recipient_id,
      a2.holder_name AS recipient_name,
      a2.risk_level  AS recipient_risk,
      t.amount       AS tx_amount,
      t.created_at   AS tx_date
    )
  )
)
GROUP BY recipient_id, recipient_name, recipient_risk
ORDER BY total_flagged_amount DESC
FETCH FIRST 50 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q11: VPN/TOR LOGIN DETECTION
--------------------------------------------------------------------------------
/* TXFRAUD_Q11 */ -- Accounts logging in from VPN or TOR IPs
SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
  MATCH (a IS account) -[l IS logs_in_from]-> (ip IS ip_address)
  WHERE a.id = :account_id
    AND (ip.is_vpn = 'Y' OR ip.is_tor = 'Y')
  COLUMNS (
    ip.ip_hash       AS ip_hash,
    ip.country       AS ip_country,
    ip.is_vpn        AS is_vpn,
    ip.is_tor        AS is_tor,
    l.login_time     AS login_time,
    l.success        AS login_success,
    l.device_type    AS device_type
  )
);

--------------------------------------------------------------------------------
-- Q12: 3-HOP MULE CHAIN (A->B->C->D — deep laundering path)
--------------------------------------------------------------------------------
/* TXFRAUD_Q12 */ -- 3-hop transfer chain
SELECT * FROM GRAPH_TABLE (NEWFRAUD.TX_FRAUD_GRAPH
  MATCH (a1 IS account) -[t1 IS transfers_to]-> (a2 IS account)
                          -[t2 IS transfers_to]-> (a3 IS account)
                          -[t3 IS transfers_to]-> (a4 IS account)
  WHERE a1.id = :account_id
    AND a1.id <> a2.id AND a2.id <> a3.id AND a3.id <> a4.id
    AND a1.id <> a3.id AND a1.id <> a4.id AND a2.id <> a4.id
  COLUMNS (
    a2.id AS hop1_id, a2.risk_level AS hop1_risk,
    a3.id AS hop2_id, a3.risk_level AS hop2_risk,
    a4.id AS hop3_id, a4.risk_level AS hop3_risk,
    t1.amount AS amount_1, t2.amount AS amount_2, t3.amount AS amount_3,
    t1.channel AS ch1, t2.channel AS ch2, t3.channel AS ch3
  )
)
FETCH FIRST 50 ROWS ONLY;
