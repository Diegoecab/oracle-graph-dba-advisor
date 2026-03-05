--------------------------------------------------------------------------------
-- 04_workload_queries.sql
-- Fraud Detection Graph — Workload Queries (Oracle 23ai / 26ai SQL/PGQ)
--
-- TARGET SCHEMA: MYSCHEMA
-- These queries replicate the exact patterns found in the AWR report
-- (FRAUDACCRELDEFAULT 19c) but use native GRAPH_TABLE / MATCH syntax.
--
-- Usage: Run with bind variables or replace :user_id / :ts with literal values.
--        Each query has a comment tag /* FRAUD_QNN */ for easy identification.
--------------------------------------------------------------------------------

SET TIMING ON
SET LINESIZE 200
SET PAGESIZE 100

--------------------------------------------------------------------------------
-- Q1: 1-HOP NEIGHBOR VIA SHARED DEVICE (highest volume in AWR)
--------------------------------------------------------------------------------
/* FRAUD_Q01 */ -- 1-hop via shared device
SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
  WHERE u1.id = :user_id
    AND u1.id <> u2.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (
    u2.id           AS neighbor_id,
    u2.user_name    AS neighbor_name,
    u2.risk_score   AS neighbor_risk,
    u2.is_blocked   AS neighbor_blocked,
    d.device_type   AS shared_device_type,
    d.id            AS device_id,
    1               AS hops_away
  )
);

--------------------------------------------------------------------------------
-- Q2: 1-HOP NEIGHBOR VIA SHARED PERSON (VALIDATE + DECLARE combined)
--------------------------------------------------------------------------------
/* FRAUD_Q02 */ -- 1-hop via shared person (validates)
SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
  MATCH (u1 IS user_account) -[e1 IS validates_person]-> (p IS person)
                             <-[e2 IS validates_person]- (u2 IS user_account)
  WHERE u1.id = :user_id
    AND u1.id <> u2.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (
    u2.id             AS neighbor_id,
    u2.user_name      AS neighbor_name,
    u2.risk_score     AS neighbor_risk,
    p.document_type   AS shared_doc_type,
    p.country         AS shared_doc_country,
    1                 AS hops_away
  )
);

--------------------------------------------------------------------------------
-- Q3: 1-HOP NEIGHBOR VIA SHARED CARD
--------------------------------------------------------------------------------
/* FRAUD_Q03 */ -- 1-hop via shared card
SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
  MATCH (u1 IS user_account) -[e1 IS uses_card]-> (c IS card)
                             <-[e2 IS uses_card]- (u2 IS user_account)
  WHERE u1.id = :user_id
    AND u1.id <> u2.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (
    u2.id           AS neighbor_id,
    u2.user_name    AS neighbor_name,
    u2.risk_score   AS neighbor_risk,
    c.card_brand    AS shared_card_brand,
    c.is_prepaid    AS is_prepaid_card,
    1               AS hops_away
  )
);

--------------------------------------------------------------------------------
-- Q4: 2-HOP NEIGHBOR VIA DEVICE (friend-of-friend)
--------------------------------------------------------------------------------
/* FRAUD_Q04 */ -- 2-hop via shared devices
SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
  MATCH (u1 IS user_account)
          -[e1 IS uses_device]-> (d1 IS device)
         <-[e2 IS uses_device]- (u2 IS user_account)
          -[e3 IS uses_device]-> (d2 IS device)
         <-[e4 IS uses_device]- (u3 IS user_account)
  WHERE u1.id = :user_id
    AND u1.id <> u2.id
    AND u2.id <> u3.id
    AND u1.id <> u3.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
    AND e3.end_date IS NULL
    AND e4.end_date IS NULL
  COLUMNS (
    u3.id           AS neighbor_id,
    u3.user_name    AS neighbor_name,
    u3.risk_score   AS neighbor_risk,
    u2.id           AS intermediate_user_id,
    d1.id           AS device1_id,
    d2.id           AS device2_id,
    2               AS hops_away
  )
)
FETCH FIRST 100 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q5: 2-HOP NEIGHBOR VIA PERSON VALIDATION (cross-type)
--------------------------------------------------------------------------------
/* FRAUD_Q05 */ -- 2-hop cross-type (person->device)
SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
  MATCH (u1 IS user_account)
          -[e1 IS validates_person]-> (p IS person)
         <-[e2 IS declares_person]-  (u2 IS user_account)
          -[e3 IS uses_device]->     (d IS device)
         <-[e4 IS uses_device]-      (u3 IS user_account)
  WHERE u1.id = :user_id
    AND u1.id <> u2.id
    AND u2.id <> u3.id
    AND u1.id <> u3.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
    AND e3.end_date IS NULL
    AND e4.end_date IS NULL
  COLUMNS (
    u3.id           AS neighbor_id,
    u3.user_name    AS neighbor_name,
    u3.risk_score   AS neighbor_risk,
    u2.id           AS intermediate_user_id,
    p.document_type AS via_document_type,
    d.device_type   AS via_device_type,
    2               AS hops_away
  )
)
FETCH FIRST 100 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q6: EDGE CHANGE DETECTION (new connections since timestamp)
--------------------------------------------------------------------------------
/* FRAUD_Q06 */ -- Edge change detection via device
SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
  WHERE u1.id = :user_id
    AND e2.start_date > :ts
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (
    u2.id           AS new_neighbor_id,
    u2.user_name    AS new_neighbor_name,
    e2.start_date   AS connection_date,
    d.id            AS via_device_id,
    'uses_device'   AS edge_type
  )
);

--------------------------------------------------------------------------------
-- Q7: TOTAL EDGE COUNT PER USER (degree computation)
--------------------------------------------------------------------------------
/* FRAUD_Q07 */ -- Total edge count (all types)
SELECT neighbor_count FROM (
  SELECT COUNT(*) AS neighbor_count
  FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u IS user_account) -[e]-> (v)
    WHERE u.id = :user_id
      AND e.end_date IS NULL
    COLUMNS (
      u.id AS uid,
      v.id AS vid
    )
  )
);

--------------------------------------------------------------------------------
-- Q8: DEGREE MAINTENANCE (UPDATE adjacent_edges_count)
--------------------------------------------------------------------------------
/* FRAUD_Q08 */ -- Degree maintenance update
UPDATE MYSCHEMA.n_user
SET adjacent_edges_count = (
  SELECT COUNT(*)
  FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u IS user_account) -[e]-> (v)
    WHERE u.id = MYSCHEMA.n_user.id
      AND e.end_date IS NULL
    COLUMNS (1 AS dummy)
  )
),
last_updated = SYSTIMESTAMP
WHERE id = :user_id;

--------------------------------------------------------------------------------
-- Q9: TEMPORAL TRAVERSAL WITH DEGREE FILTER (supernode avoidance)
--------------------------------------------------------------------------------
/* FRAUD_Q09 */ -- Temporal traversal with supernode filter
SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
  WHERE u1.id = :user_id
    AND d.adjacent_edges_count < 200
    AND e1.last_updated > :ts
    AND e2.last_updated > :ts
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (
    u2.id                   AS neighbor_id,
    u2.user_name            AS neighbor_name,
    u2.risk_score           AS neighbor_risk,
    d.device_type           AS device_type,
    d.adjacent_edges_count  AS device_degree,
    e2.last_updated         AS edge_updated_at
  )
);

--------------------------------------------------------------------------------
-- Q10: ALL 1-HOP NEIGHBORS (UNION across all edge types)
--------------------------------------------------------------------------------
/* FRAUD_Q10 */ -- All 1-hop neighbors (all edge types)
SELECT neighbor_id, neighbor_name, neighbor_risk, edge_type, hops_away
FROM (
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                               <-[e2 IS uses_device]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'USES_DEVICE' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_guest_device]-> (d IS device)
                               <-[e2 IS uses_guest_device]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'USES_GUEST_DEVICE' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_card]-> (c IS card)
                               <-[e2 IS uses_card]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'USES_CARD' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_guest_card]-> (c IS card)
                               <-[e2 IS uses_guest_card]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'USES_GUEST_CARD' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS validates_person]-> (p IS person)
                               <-[e2 IS validates_person]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'VALIDATES_PERSON' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS declares_person]-> (p IS person)
                               <-[e2 IS declares_person]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'DECLARES_PERSON' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS validates_phone]-> (ph IS phone)
                               <-[e2 IS validates_phone]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'VALIDATES_PHONE' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS withdraws_from]-> (ba IS bank_account)
                               <-[e2 IS withdraws_from]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'WITHDRAWAL_BANK' AS edge_type, 1 AS hops_away)
  )
)
ORDER BY neighbor_risk DESC;

--------------------------------------------------------------------------------
-- Q11: HIGH-RISK NEIGHBOR DETECTION
--------------------------------------------------------------------------------
/* FRAUD_Q11 */ -- High-risk neighbors
SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
  WHERE u1.id = :user_id
    AND u2.risk_score > 60
    AND u1.id <> u2.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (
    u2.id           AS risky_neighbor_id,
    u2.user_name    AS risky_neighbor_name,
    u2.risk_score   AS risk_score,
    u2.is_blocked   AS is_blocked,
    d.device_type   AS shared_device_type
  )
);

--------------------------------------------------------------------------------
-- Q12: SHARED ENTITY SUMMARY (aggregated traversal)
--------------------------------------------------------------------------------
/* FRAUD_Q12 */ -- Shared entity summary (aggregated)
SELECT neighbor_id, neighbor_name,
       COUNT(*) AS shared_entities,
       COUNT(DISTINCT edge_type) AS relationship_types,
       MAX(neighbor_risk) AS max_risk
FROM (
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                               <-[e2 IS uses_device]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'DEVICE' AS edge_type)
  )
  UNION ALL
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_card]-> (c IS card)
                               <-[e2 IS uses_card]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'CARD' AS edge_type)
  )
  UNION ALL
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS validates_person]-> (p IS person)
                               <-[e2 IS validates_person]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'PERSON' AS edge_type)
  )
)
GROUP BY neighbor_id, neighbor_name
ORDER BY shared_entities DESC
FETCH FIRST 50 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q13: FRAUD RING DETECTION (circular pattern)
--------------------------------------------------------------------------------
/* FRAUD_Q13 */ -- Fraud ring detection (triangle)
SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]->     (d IS device)
                             <-[e2 IS uses_device]-      (u2 IS user_account)
                              -[e3 IS uses_card]->       (c IS card)
                             <-[e4 IS uses_card]-        (u3 IS user_account)
                              -[e5 IS validates_person]-> (p IS person)
                             <-[e6 IS validates_person]-  (u1)
  WHERE u1.id <> u2.id
    AND u2.id <> u3.id
    AND u1.id <> u3.id
    AND e1.end_date IS NULL AND e2.end_date IS NULL
    AND e3.end_date IS NULL AND e4.end_date IS NULL
    AND e5.end_date IS NULL AND e6.end_date IS NULL
  COLUMNS (
    u1.id AS user1_id, u1.user_name AS user1_name, u1.risk_score AS user1_risk,
    u2.id AS user2_id, u2.user_name AS user2_name, u2.risk_score AS user2_risk,
    u3.id AS user3_id, u3.user_name AS user3_name, u3.risk_score AS user3_risk,
    d.device_type AS shared_device,
    c.card_brand  AS shared_card,
    p.country     AS shared_person_country
  )
)
FETCH FIRST 50 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q14: BLOCKED USER NETWORK EXPANSION
--------------------------------------------------------------------------------
/* FRAUD_Q14 */ -- Blocked user contamination
SELECT blocked_user_id, blocked_user_name,
       neighbor_id, neighbor_name, neighbor_risk, edge_type
FROM (
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                               <-[e2 IS uses_device]- (u2 IS user_account)
    WHERE u1.is_blocked = 'Y'
      AND u2.is_blocked = 'N'
      AND e1.end_date IS NULL
      AND e2.end_date IS NULL
    COLUMNS (u1.id AS blocked_user_id, u1.user_name AS blocked_user_name,
             u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'DEVICE' AS edge_type)
  )
  UNION ALL
  SELECT * FROM GRAPH_TABLE (MYSCHEMA.fraud_graph
    MATCH (u1 IS user_account) -[e1 IS validates_person]-> (p IS person)
                               <-[e2 IS validates_person]- (u2 IS user_account)
    WHERE u1.is_blocked = 'Y'
      AND u2.is_blocked = 'N'
      AND e1.end_date IS NULL
      AND e2.end_date IS NULL
    COLUMNS (u1.id AS blocked_user_id, u1.user_name AS blocked_user_name,
             u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'PERSON' AS edge_type)
  )
)
ORDER BY neighbor_risk DESC
FETCH FIRST 200 ROWS ONLY;
