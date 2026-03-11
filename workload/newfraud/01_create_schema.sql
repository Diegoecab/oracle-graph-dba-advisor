--------------------------------------------------------------------------------
-- 01_create_schema.sql
-- Transaction Fraud Graph — Schema Creation (Oracle 23ai / 26ai)
--
-- TARGET SCHEMA: NEWFRAUD (run as ADMIN or privileged user)
--
-- Focus: Transaction-based fraud detection — mule chains, shared IPs,
--        high-risk merchants, ATM cash-out patterns.
--
-- Vertex tables: NEWFRAUD.ACCOUNT, MERCHANT, IP_ADDRESS, ATM
-- Edge tables:   NEWFRAUD.TRANSFER, PURCHASE, LOGIN_FROM, WITHDRAWAL, OPERATES_NEAR
--------------------------------------------------------------------------------

-- Clean up previous run (if exists)
BEGIN
  FOR t IN (
    SELECT table_name FROM all_tables
    WHERE owner = 'NEWFRAUD'
      AND table_name IN (
        'ACCOUNT','MERCHANT','IP_ADDRESS','ATM',
        'TRANSFER','PURCHASE','LOGIN_FROM','WITHDRAWAL','OPERATES_NEAR'
      )
  ) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE NEWFRAUD.' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

-- Drop property graph if exists
BEGIN
  EXECUTE IMMEDIATE 'DROP PROPERTY GRAPH NEWFRAUD.TX_FRAUD_GRAPH';
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

--------------------------------------------------------------------------------
-- VERTEX TABLES
--------------------------------------------------------------------------------

CREATE TABLE NEWFRAUD.ACCOUNT (
  id              NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_number  VARCHAR2(20)  NOT NULL,
  holder_name     VARCHAR2(100) NOT NULL,
  account_type    VARCHAR2(20),          -- SAVINGS, CHECKING, PREPAID, CRYPTO
  risk_level      VARCHAR2(10)  DEFAULT 'LOW',  -- LOW, MEDIUM, HIGH, FROZEN
  is_frozen       VARCHAR2(1)   DEFAULT 'N',
  balance         NUMBER(15,2)  DEFAULT 0,
  country         VARCHAR2(3),
  opened_date     TIMESTAMP     DEFAULT SYSTIMESTAMP,
  last_activity   TIMESTAMP     DEFAULT SYSTIMESTAMP
);

CREATE TABLE NEWFRAUD.MERCHANT (
  id              NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  merchant_name   VARCHAR2(100) NOT NULL,
  mcc_code        VARCHAR2(4),            -- Merchant Category Code
  category        VARCHAR2(50),           -- GAMBLING, CRYPTO_EXCHANGE, RETAIL, etc.
  country         VARCHAR2(3),
  is_high_risk    VARCHAR2(1)   DEFAULT 'N',
  created_date    TIMESTAMP     DEFAULT SYSTIMESTAMP
);

CREATE TABLE NEWFRAUD.IP_ADDRESS (
  id              NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ip_hash         VARCHAR2(64)  NOT NULL,
  country         VARCHAR2(3),
  is_vpn          VARCHAR2(1)   DEFAULT 'N',
  is_tor          VARCHAR2(1)   DEFAULT 'N',
  first_seen      TIMESTAMP     DEFAULT SYSTIMESTAMP
);

CREATE TABLE NEWFRAUD.ATM (
  id              NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  atm_code        VARCHAR2(20)  NOT NULL,
  city            VARCHAR2(50),
  country         VARCHAR2(3),
  lat             NUMBER(9,6),
  lon             NUMBER(9,6),
  installed_date  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

--------------------------------------------------------------------------------
-- EDGE TABLES
-- All edges have: SRC (source vertex FK), DST (dest vertex FK)
--------------------------------------------------------------------------------

-- Account -[transfers_to]-> Account (money movement — core of mule detection)
CREATE TABLE NEWFRAUD.TRANSFER (
  id              NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src             NUMBER        NOT NULL REFERENCES NEWFRAUD.ACCOUNT(id),
  dst             NUMBER        NOT NULL REFERENCES NEWFRAUD.ACCOUNT(id),
  amount          NUMBER(15,2)  NOT NULL,
  currency        VARCHAR2(3)   DEFAULT 'USD',
  channel         VARCHAR2(20),           -- WIRE, ACH, P2P, CRYPTO, INTERNAL
  is_flagged      VARCHAR2(1)   DEFAULT 'N',
  created_at      TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- Account -[purchases_at]-> Merchant
CREATE TABLE NEWFRAUD.PURCHASE (
  id              NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src             NUMBER        NOT NULL REFERENCES NEWFRAUD.ACCOUNT(id),
  dst             NUMBER        NOT NULL REFERENCES NEWFRAUD.MERCHANT(id),
  amount          NUMBER(15,2)  NOT NULL,
  currency        VARCHAR2(3)   DEFAULT 'USD',
  is_flagged      VARCHAR2(1)   DEFAULT 'N',
  created_at      TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- Account -[logs_in_from]-> IP_Address
CREATE TABLE NEWFRAUD.LOGIN_FROM (
  id              NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src             NUMBER        NOT NULL REFERENCES NEWFRAUD.ACCOUNT(id),
  dst             NUMBER        NOT NULL REFERENCES NEWFRAUD.IP_ADDRESS(id),
  login_time      TIMESTAMP     DEFAULT SYSTIMESTAMP,
  success         VARCHAR2(1)   DEFAULT 'Y',
  device_type     VARCHAR2(20)            -- MOBILE, DESKTOP, TABLET, API
);

-- Account -[withdraws_at]-> ATM
CREATE TABLE NEWFRAUD.WITHDRAWAL (
  id              NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src             NUMBER        NOT NULL REFERENCES NEWFRAUD.ACCOUNT(id),
  dst             NUMBER        NOT NULL REFERENCES NEWFRAUD.ATM(id),
  amount          NUMBER(15,2)  NOT NULL,
  currency        VARCHAR2(3)   DEFAULT 'USD',
  created_at      TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- Merchant -[located_near]-> ATM (co-location for cash-out patterns)
CREATE TABLE NEWFRAUD.OPERATES_NEAR (
  id              NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src             NUMBER        NOT NULL REFERENCES NEWFRAUD.MERCHANT(id),
  dst             NUMBER        NOT NULL REFERENCES NEWFRAUD.ATM(id),
  distance_km     NUMBER(6,2),
  since_date      TIMESTAMP     DEFAULT SYSTIMESTAMP
);

PROMPT Schema created successfully in NEWFRAUD.
