/*
 * Oracle Graph DBA Advisor — End-to-End Demo Script
 *
 * This script is a REFERENCE for the advisor. The advisor reads these
 * sections and executes them step by step, adapting parameters and
 * adding analysis between steps.
 *
 * DO NOT run this script directly — let the advisor drive it.
 */

-- ============================================================
-- STEP 0: PRODUCTION SAFETY CHECK
-- ============================================================
-- The advisor runs this FIRST and blocks if production detected.
SELECT
    SYS_CONTEXT('USERENV', 'DB_NAME') AS db_name,
    SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS service_name,
    SYS_CONTEXT('USERENV', 'CON_NAME') AS container_name
FROM DUAL;

-- ============================================================
-- STEP 1: CONSULTIVE — "Should I use a graph for fraud detection?"
-- ============================================================
-- But first, the advisor checks database health:
-- "Before evaluating the use case, let me check if your database
-- has enough resources for a graph workload. I'll run a quick
-- health assessment."
--
-- [Runs HEALTH-01 through HEALTH-06]
--
-- Now the advisor proceeds with the use case assessment:
-- The user has relational tables. The advisor evaluates the use case.
--
-- The advisor should:
--   1. Ask what questions the user needs to answer
--   2. Identify graph indicators in the described scenario:
--      - Path-dependent queries: "find circular money flows"
--      - Variable-depth traversal: "chains of 2-4 hops"
--      - Pattern matching: "triangles, shared devices"
--      - Relationship-centric filtering: "suspicious transfers"
--   3. Reference knowledge/graph-patterns/use-case-assessment.md
--   4. Conclude: "A property graph is strongly indicated for this use case.
--      Here's why and here's how I'd design it."

-- ============================================================
-- STEP 2: DESIGN — "How should I model the graph?"
-- ============================================================
-- The advisor proposes the graph design, explaining each decision:
--
-- "Based on your fraud detection needs, I recommend this model:
--
--  VERTICES:
--  - accounts   -> The main entity you traverse FROM
--  - merchants  -> Transaction endpoints, filtered by risk level
--  - devices    -> Shared devices link otherwise unrelated accounts
--
--  EDGES:
--  - transferred_to     (account -> account)  -> Core traversal for fraud rings
--  - uses_device        (account -> device)   -> Shared device detection
--  - transacts_with     (account -> merchant) -> Merchant risk convergence
--
--  DESIGN DECISIONS:
--  - account_id as NUMBER (compact, fast joins — Rule #7)
--  - Consistent direction: transfers go from_account -> to_account (Rule #8)
--  - Separate edge tables per relationship type (Rule #3)
--  - Lightweight tables: no CLOBs, no JSON blobs on edge tables (Rule #6)"

-- ============================================================
-- STEP 3: BUILD — Create schema and property graph
-- ============================================================
-- The advisor generates the DDL based on the design from Step 2.

-- Vertex tables
CREATE TABLE accounts (
    account_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_name  VARCHAR2(100) NOT NULL,
    account_type  VARCHAR2(20) DEFAULT 'PERSONAL',
    risk_score    NUMBER(3,2) DEFAULT 0.00,
    status        VARCHAR2(20) DEFAULT 'ACTIVE',
    created_date  DATE DEFAULT SYSDATE,
    country       VARCHAR2(3) DEFAULT 'US'
);

CREATE TABLE merchants (
    merchant_id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    merchant_name VARCHAR2(100) NOT NULL,
    category      VARCHAR2(50),
    risk_level    VARCHAR2(10) DEFAULT 'LOW',
    country       VARCHAR2(3) DEFAULT 'US'
);

CREATE TABLE devices (
    device_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    device_type   VARCHAR2(30),
    fingerprint   VARCHAR2(64),
    first_seen    DATE DEFAULT SYSDATE
);

-- Edge tables
CREATE TABLE transfers (
    transfer_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_account_id NUMBER NOT NULL REFERENCES accounts(account_id),
    to_account_id   NUMBER NOT NULL REFERENCES accounts(account_id),
    amount          NUMBER(12,2) NOT NULL,
    transfer_date   DATE DEFAULT SYSDATE,
    channel         VARCHAR2(20) DEFAULT 'ONLINE',
    is_suspicious   VARCHAR2(1) DEFAULT 'N',
    currency        VARCHAR2(3) DEFAULT 'USD'
);

CREATE TABLE account_device (
    id              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id      NUMBER NOT NULL REFERENCES accounts(account_id),
    device_id       NUMBER NOT NULL REFERENCES devices(device_id),
    first_used      DATE DEFAULT SYSDATE,
    last_used       DATE DEFAULT SYSDATE
);

CREATE TABLE account_merchant (
    id              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id      NUMBER NOT NULL REFERENCES accounts(account_id),
    merchant_id     NUMBER NOT NULL REFERENCES merchants(merchant_id),
    transaction_count NUMBER DEFAULT 1,
    total_amount    NUMBER(14,2) DEFAULT 0,
    last_transaction DATE DEFAULT SYSDATE
);

-- Property Graph Definition
CREATE PROPERTY GRAPH fraud_graph
    VERTEX TABLES (
        accounts KEY (account_id)
            LABEL account
            PROPERTIES (account_name, account_type, risk_score, status, country),
        merchants KEY (merchant_id)
            LABEL merchant
            PROPERTIES (merchant_name, category, risk_level),
        devices KEY (device_id)
            LABEL device
            PROPERTIES (device_type, fingerprint)
    )
    EDGE TABLES (
        transfers
            KEY (transfer_id)
            SOURCE KEY (from_account_id) REFERENCES accounts (account_id)
            DESTINATION KEY (to_account_id) REFERENCES accounts (account_id)
            LABEL transferred_to
            PROPERTIES (amount, transfer_date, channel, is_suspicious),
        account_device
            KEY (id)
            SOURCE KEY (account_id) REFERENCES accounts (account_id)
            DESTINATION KEY (device_id) REFERENCES devices (device_id)
            LABEL uses_device,
        account_merchant
            KEY (id)
            SOURCE KEY (account_id) REFERENCES accounts (account_id)
            DESTINATION KEY (merchant_id) REFERENCES merchants (merchant_id)
            LABEL transacts_with
            PROPERTIES (transaction_count, total_amount)
    );

-- ============================================================
-- STEP 4: POPULATE — Generate realistic test data
-- ============================================================
-- Target: ~10K accounts, ~500 merchants, ~2K devices
--         ~100K transfers, ~15K account_device, ~30K account_merchant
-- Real fraud data has specific patterns:
--   - Most accounts have few transfers, a few have thousands (power-law)
--   - Only 0.5% of transfers are suspicious (highly skewed)
--   - Activity is spread over 12 months (temporal distribution)

-- Accounts (10,000)
BEGIN
    FOR i IN 1..10000 LOOP
        INSERT INTO accounts (account_name, account_type, risk_score, status, country)
        VALUES (
            'ACCT_' || LPAD(i, 6, '0'),
            CASE MOD(i, 5) WHEN 0 THEN 'BUSINESS' ELSE 'PERSONAL' END,
            ROUND(DBMS_RANDOM.VALUE(0, 1), 2),
            CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN 'SUSPENDED' ELSE 'ACTIVE' END,
            CASE MOD(i, 10) WHEN 0 THEN 'UK' WHEN 1 THEN 'DE' ELSE 'US' END
        );
    END LOOP;
    COMMIT;
END;
/

-- Merchants (500)
BEGIN
    FOR i IN 1..500 LOOP
        INSERT INTO merchants (merchant_name, category, risk_level, country)
        VALUES (
            'MERCHANT_' || LPAD(i, 4, '0'),
            CASE MOD(i, 6)
                WHEN 0 THEN 'RETAIL' WHEN 1 THEN 'FOOD'
                WHEN 2 THEN 'TRAVEL' WHEN 3 THEN 'ELECTRONICS'
                WHEN 4 THEN 'CRYPTO' ELSE 'OTHER'
            END,
            CASE WHEN MOD(i, 20) = 0 THEN 'HIGH'
                 WHEN MOD(i, 5) = 0 THEN 'MEDIUM'
                 ELSE 'LOW' END,
            'US'
        );
    END LOOP;
    COMMIT;
END;
/

-- Devices (2,000)
BEGIN
    FOR i IN 1..2000 LOOP
        INSERT INTO devices (device_type, fingerprint, first_seen)
        VALUES (
            CASE MOD(i, 3) WHEN 0 THEN 'MOBILE' WHEN 1 THEN 'DESKTOP' ELSE 'TABLET' END,
            STANDARD_HASH('device_' || i, 'SHA256'),
            SYSDATE - DBMS_RANDOM.VALUE(1, 365)
        );
    END LOOP;
    COMMIT;
END;
/

-- Transfers (100,000) — main edge table, power-law degree
DECLARE
    v_from   NUMBER;
    v_to     NUMBER;
    v_max_id NUMBER;
BEGIN
    SELECT MAX(account_id) INTO v_max_id FROM accounts;

    FOR i IN 1..100000 LOOP
        -- Power-law: 80% of transfers come from 20% of accounts
        IF DBMS_RANDOM.VALUE < 0.8 THEN
            v_from := FLOOR(DBMS_RANDOM.VALUE(1, v_max_id * 0.2));
        ELSE
            v_from := FLOOR(DBMS_RANDOM.VALUE(1, v_max_id));
        END IF;
        v_to := FLOOR(DBMS_RANDOM.VALUE(1, v_max_id));

        INSERT INTO transfers (from_account_id, to_account_id, amount, transfer_date, channel, is_suspicious)
        VALUES (
            v_from, v_to,
            ROUND(DBMS_RANDOM.VALUE(10, 50000), 2),
            SYSDATE - DBMS_RANDOM.VALUE(1, 365),
            CASE MOD(i, 4) WHEN 0 THEN 'ATM' WHEN 1 THEN 'WIRE' WHEN 2 THEN 'APP' ELSE 'ONLINE' END,
            CASE WHEN DBMS_RANDOM.VALUE < 0.005 THEN 'Y' ELSE 'N' END
        );

        IF MOD(i, 10000) = 0 THEN COMMIT; END IF;
    END LOOP;
    COMMIT;
END;
/

-- Account-Device links (15,000)
-- Account-Merchant links (30,000)
-- [Similar pattern — advisor generates these adapting to the schema]

-- Gather statistics
BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(USER);
END;
/

-- ============================================================
-- STEP 5: EXPLORE — "Here's what your graph can answer"
-- ============================================================
-- The advisor writes queries that answer the user's fraud questions.

-- Q1: 2-hop fraud ring (circular money flow)
SELECT * FROM GRAPH_TABLE(fraud_graph
    MATCH (a IS account)-[t1 IS transferred_to]->(b IS account)
                        -[t2 IS transferred_to]->(c IS account)
                        -[t3 IS transferred_to]->(a)
    WHERE t1.is_suspicious = 'Y' OR t2.is_suspicious = 'Y'
    COLUMNS (
        a.account_name AS origin,
        b.account_name AS intermediary,
        c.account_name AS return_point,
        t1.amount AS amt_1, t2.amount AS amt_2, t3.amount AS amt_3
    )
);

-- Q2: Shared device detection
SELECT * FROM GRAPH_TABLE(fraud_graph
    MATCH (a1 IS account)-[d1 IS uses_device]->(d IS device)
                         <-[d2 IS uses_device]-(a2 IS account)
    WHERE a1.account_id < a2.account_id
    COLUMNS (
        a1.account_name AS account_1,
        a2.account_name AS account_2,
        d.fingerprint AS shared_device
    )
);

-- Q3: High-risk merchant convergence
SELECT * FROM GRAPH_TABLE(fraud_graph
    MATCH (a IS account)-[t IS transacts_with]->(m IS merchant)
    WHERE m.risk_level = 'HIGH'
      AND t.total_amount > 10000
    COLUMNS (
        a.account_name, m.merchant_name, t.total_amount
    )
);

-- Q4: Multi-hop money trail
-- NOTE: This query uses {1,3} variable-length pattern —
-- performance implications discussed in Step 6.
SELECT * FROM GRAPH_TABLE(fraud_graph
    MATCH (a IS account)-[t IS transferred_to]->{1,3}(b IS account)
    WHERE a.risk_score > 0.8
      AND t.amount > 9000
    COLUMNS (
        a.account_name AS origin,
        b.account_name AS destination,
        t.amount
    )
);

-- ============================================================
-- STEP 6: PROACTIVE DIAGNOSTIC — "Before you go to production..."
-- ============================================================
-- The advisor runs its full 6-phase methodology.
-- Expected findings:
--   1. Missing FK indexes on transfers(from_account_id, to_account_id)
--   2. Missing FK indexes on account_device(account_id, device_id)
--   3. Composite index on transfers(is_suspicious, to_account_id)
--   4. Histograms needed on is_suspicious (skewed: 99.5% N, 0.5% Y)
--   5. Q4 design warning: {1,3} without start vertex filter = explosion risk
--
-- As part of Step 6, the advisor also checks Auto Indexing:
--
-- "I also checked Auto Indexing status on your ADB:
--
--  Auto Indexing: ENABLED (IMPLEMENT mode)
--  Auto indexes on graph tables: 0
--
--  This is expected — your graph workload is brand new, so
--  Auto Indexing hasn't observed enough queries yet.
--  My recommendations below are proactive, based on your
--  graph structure. Once your workload runs for a few days,
--  Auto Indexing may create additional indexes. The two
--  approaches complement each other.
--
--  After applying my recommendations and running the workload,
--  I'll check again to see if Auto Indexing found anything
--  I missed."

-- ============================================================
-- STEP 7: RECOMMEND + CREATE indexes as INVISIBLE
-- ============================================================
-- Example (advisor generates dynamically based on Phase 6):
--
-- CREATE INDEX idx_transfers_from ON transfers(from_account_id) INVISIBLE;
-- CREATE INDEX idx_transfers_to ON transfers(to_account_id) INVISIBLE;
-- CREATE INDEX idx_transfers_susp_to ON transfers(is_suspicious, to_account_id) INVISIBLE;
-- CREATE INDEX idx_acct_device_acct ON account_device(account_id) INVISIBLE;
-- CREATE INDEX idx_acct_device_dev ON account_device(device_id) INVISIBLE;
-- CREATE INDEX idx_acct_merch_acct ON account_merchant(account_id) INVISIBLE;
-- CREATE INDEX idx_acct_merch_merch ON account_merchant(merchant_id) INVISIBLE;

-- ============================================================
-- STEP 8: PROVE IT — Show execution plan changes
-- ============================================================
-- For each index:
--   8a. Capture plan with index INVISIBLE (TABLE ACCESS FULL)
--   8b. ALTER INDEX ... VISIBLE
--   8c. Re-run query, capture new plan (INDEX RANGE SCAN)
--   8d. Compare elapsed time from V$SQL

-- ============================================================
-- STEP 9: SCALE — Generate 10X data and re-test
-- ============================================================
-- 9a. Generate 9X additional data (preserving distributions)
-- 9b. Re-gather statistics
BEGIN DBMS_STATS.GATHER_SCHEMA_STATS(USER); END;
/
-- 9c. Re-run Q1-Q4, capture metrics
-- 9d. Check for plan regressions

-- ============================================================
-- STEP 10: FULL REPORT — 3-column comparison
-- ============================================================
-- | Query | Metric | 1X no-idx | 1X with-idx | 10X with-idx | Growth | Verdict |
-- Verdicts:
--   Linear:      Growth <= 1.2 x data_multiplier
--   Review:      Growth > 1.2X but < data_multiplier^2
--   Superlinear: Growth >= data_multiplier^2

-- AUTO INDEXING INTEGRATION
-- Status:            ENABLED (IMPLEMENT mode)
-- Auto indexes found: 0 before advisor analysis
-- Advisor indexes:    5 created manually
-- Recommendation:     Keep both active. Auto Indexing will complement
--                     the advisor's proactive indexes with workload-driven
--                     additions over time. Review in 30 days.

-- ============================================================
-- STEP 11: SUMMARY + CLEANUP
-- ============================================================
-- If cleanup:
-- DROP PROPERTY GRAPH fraud_graph;
-- DROP TABLE account_merchant PURGE;
-- DROP TABLE account_device PURGE;
-- DROP TABLE transfers PURGE;
-- DROP TABLE devices PURGE;
-- DROP TABLE merchants PURGE;
-- DROP TABLE accounts PURGE;
