--------------------------------------------------------------------------------
-- 04_workload_queries.sql
-- Fraud Detection Graph — Workload Queries (Oracle 23ai / 26ai SQL/PGQ)
--
-- These queries replicate the exact patterns found in the AWR report
-- (FRAUDACCRELDEFAULT 19c) but use native GRAPH_TABLE / MATCH syntax.
--
-- AWR Pattern Mapping:
--   Pattern A (0ammkzmpnsa49, bs7dfvh6ukjcx) → Q1, Q2, Q3  (1-hop neighbor)
--   Pattern B (2k831rbg4c5rh, 0g34jw7zk93g7) → Q4, Q5      (2-hop neighbor)
--   Pattern C (a1gd2pnpbwhcq)                → Q6           (edge change detection)
--   Pattern D (7g2uc57ksjy9m)                → Q7           (edge count)
--   Pattern E (g3kwbf8q76fgw)                → Q8           (degree maintenance)
--   Pattern F (dr4xhkun2vxjr)               → Q9           (temporal + degree filter)
--   Additional patterns for richer workload  → Q10-Q14
--
-- Usage: Run with bind variables or replace :user_id / :ts with literal values.
--        Each query has a comment tag /* FRAUD_QNN */ for easy identification.
--------------------------------------------------------------------------------

SET TIMING ON
SET LINESIZE 200
SET PAGESIZE 100

--------------------------------------------------------------------------------
-- Q1: 1-HOP NEIGHBOR VIA SHARED DEVICE (highest volume in AWR)
-- AWR: 0ammkzmpnsa49 — 21.93% DB time, 44.9M executions
-- Pattern: User -> uses_device -> Device <- uses_device <- OtherUser
-- "Find all users who share a device with user :user_id"
--------------------------------------------------------------------------------
/* FRAUD_Q01 */ -- 1-hop via shared device
SELECT * FROM GRAPH_TABLE (fraud_graph
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
-- AWR: 0ammkzmpnsa49 — Part of the UNION ALL pattern
-- Pattern: User -> validates_person -> Person <- validates_person <- OtherUser
-- "Find users who validated the same identity document"
--------------------------------------------------------------------------------
/* FRAUD_Q02 */ -- 1-hop via shared person (validates)
SELECT * FROM GRAPH_TABLE (fraud_graph
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
-- AWR: bs7dfvh6ukjcx — 4.45% DB time, 403M executions
-- Pattern: User -> uses_card -> Card <- uses_card <- OtherUser
-- "Find users who use the same card"
--------------------------------------------------------------------------------
/* FRAUD_Q03 */ -- 1-hop via shared card
SELECT * FROM GRAPH_TABLE (fraud_graph
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
-- AWR: 2k831rbg4c5rh — 11.93% DB time, 1.1M executions
-- Pattern: User -[e1]-> Device <-[e2]- User2 -[e3]-> Device2 <-[e4]- User3
-- "Find users 2 hops away through shared devices"
--------------------------------------------------------------------------------
/* FRAUD_Q04 */ -- 2-hop via shared devices
SELECT * FROM GRAPH_TABLE (fraud_graph
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
-- Q5: 2-HOP NEIGHBOR VIA PERSON VALIDATION
-- AWR: 0g34jw7zk93g7 — 3.43% DB time
-- Pattern: User -> validates_person -> Person <- declares_person <- User2
--          -> uses_device -> Device <- uses_device <- User3
-- "Cross-type 2-hop: identity doc links to device links"
--------------------------------------------------------------------------------
/* FRAUD_Q05 */ -- 2-hop cross-type (person->device)
SELECT * FROM GRAPH_TABLE (fraud_graph
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
-- AWR: a1gd2pnpbwhcq — 2.84% DB time, 202M executions
-- "Find new edges connecting to the same nodes as user :user_id since :ts"
--------------------------------------------------------------------------------
/* FRAUD_Q06 */ -- Edge change detection via device
SELECT * FROM GRAPH_TABLE (fraud_graph
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
-- AWR: 7g2uc57ksjy9m — 2.52% DB time, 129M executions
-- "Count all active edges from user :user_id across all edge types"
-- NOTE: In SQL/PGQ we can use a single pattern with ANY edge label
--------------------------------------------------------------------------------
/* FRAUD_Q07 */ -- Total edge count (all types)
SELECT neighbor_count FROM (
  SELECT COUNT(*) AS neighbor_count
  FROM GRAPH_TABLE (fraud_graph
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
-- AWR: g3kwbf8q76fgw — 94M executions
-- "Update the cached edge count for a user after new edges are added"
-- NOTE: This is a DML operation, not a graph query per se.
-- It runs AFTER Q7 to update the materialized degree.
--------------------------------------------------------------------------------
/* FRAUD_Q08 */ -- Degree maintenance update
UPDATE n_user
SET adjacent_edges_count = (
  SELECT COUNT(*)
  FROM GRAPH_TABLE (fraud_graph
    MATCH (u IS user_account) -[e]-> (v)
    WHERE u.id = n_user.id
      AND e.end_date IS NULL
    COLUMNS (1 AS dummy)
  )
),
last_updated = SYSTIMESTAMP
WHERE id = :user_id;

--------------------------------------------------------------------------------
-- Q9: TEMPORAL TRAVERSAL WITH DEGREE FILTER (supernode avoidance)
-- AWR: dr4xhkun2vxjr — 90M executions
-- "Find neighbors via device, but only if the device isn't a supernode
--  (adjacent_edges_count < 200) and edges were updated recently"
--------------------------------------------------------------------------------
/* FRAUD_Q09 */ -- Temporal traversal with supernode filter
SELECT * FROM GRAPH_TABLE (fraud_graph
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
-- AWR: 0ammkzmpnsa49 full pattern — the complete UNION ALL
-- "Find ALL first-degree neighbors regardless of relationship type"
-- This is the most expensive query pattern in the AWR (21.93% DB time)
--------------------------------------------------------------------------------
/* FRAUD_Q10 */ -- All 1-hop neighbors (all edge types)
SELECT neighbor_id, neighbor_name, neighbor_risk, edge_type, hops_away
FROM (
  -- Via device
  SELECT * FROM GRAPH_TABLE (fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                               <-[e2 IS uses_device]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'USES_DEVICE' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  -- Via guest device
  SELECT * FROM GRAPH_TABLE (fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_guest_device]-> (d IS device)
                               <-[e2 IS uses_guest_device]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'USES_GUEST_DEVICE' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  -- Via card
  SELECT * FROM GRAPH_TABLE (fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_card]-> (c IS card)
                               <-[e2 IS uses_card]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'USES_CARD' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  -- Via guest card
  SELECT * FROM GRAPH_TABLE (fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_guest_card]-> (c IS card)
                               <-[e2 IS uses_guest_card]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'USES_GUEST_CARD' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  -- Via validated person
  SELECT * FROM GRAPH_TABLE (fraud_graph
    MATCH (u1 IS user_account) -[e1 IS validates_person]-> (p IS person)
                               <-[e2 IS validates_person]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'VALIDATES_PERSON' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  -- Via declared person
  SELECT * FROM GRAPH_TABLE (fraud_graph
    MATCH (u1 IS user_account) -[e1 IS declares_person]-> (p IS person)
                               <-[e2 IS declares_person]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'DECLARES_PERSON' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  -- Via phone
  SELECT * FROM GRAPH_TABLE (fraud_graph
    MATCH (u1 IS user_account) -[e1 IS validates_phone]-> (ph IS phone)
                               <-[e2 IS validates_phone]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'VALIDATES_PHONE' AS edge_type, 1 AS hops_away)
  )
  UNION ALL
  -- Via bank account
  SELECT * FROM GRAPH_TABLE (fraud_graph
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
-- "Find 1-hop neighbors with risk_score > 60 — fraud ring candidates"
-- Filtered traversal pattern (index candidate on n_user.risk_score)
--------------------------------------------------------------------------------
/* FRAUD_Q11 */ -- High-risk neighbors
SELECT * FROM GRAPH_TABLE (fraud_graph
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
-- "How many shared entities does user :user_id have with each neighbor?"
-- Aggregated pattern — benefits from covering indexes
--------------------------------------------------------------------------------
/* FRAUD_Q12 */ -- Shared entity summary (aggregated)
SELECT neighbor_id, neighbor_name,
       COUNT(*) AS shared_entities,
       COUNT(DISTINCT edge_type) AS relationship_types,
       MAX(neighbor_risk) AS max_risk
FROM (
  SELECT * FROM GRAPH_TABLE (fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                               <-[e2 IS uses_device]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'DEVICE' AS edge_type)
  )
  UNION ALL
  SELECT * FROM GRAPH_TABLE (fraud_graph
    MATCH (u1 IS user_account) -[e1 IS uses_card]-> (c IS card)
                               <-[e2 IS uses_card]- (u2 IS user_account)
    WHERE u1.id = :user_id AND u1.id <> u2.id
      AND e1.end_date IS NULL AND e2.end_date IS NULL
    COLUMNS (u2.id AS neighbor_id, u2.user_name AS neighbor_name,
             u2.risk_score AS neighbor_risk, 'CARD' AS edge_type)
  )
  UNION ALL
  SELECT * FROM GRAPH_TABLE (fraud_graph
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
-- "Find triangles: User1 shares device with User2, User2 shares card with
--  User3, User3 shares person with User1 — potential fraud ring"
-- This is the most expensive pattern type (circular/ring)
--------------------------------------------------------------------------------
/* FRAUD_Q13 */ -- Fraud ring detection (triangle)
SELECT * FROM GRAPH_TABLE (fraud_graph
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
-- "Find all active neighbors of blocked users — contamination analysis"
-- Fan-out pattern starting from filtered vertices
--------------------------------------------------------------------------------
/* FRAUD_Q14 */ -- Blocked user contamination
SELECT blocked_user_id, blocked_user_name,
       neighbor_id, neighbor_name, neighbor_risk, edge_type
FROM (
  SELECT * FROM GRAPH_TABLE (fraud_graph
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
  SELECT * FROM GRAPH_TABLE (fraud_graph
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
