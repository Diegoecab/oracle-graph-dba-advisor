--------------------------------------------------------------------------------
-- 01_create_schema.sql
-- Fraud Detection Graph — Schema Creation (Oracle 23ai / 26ai)
--
-- TARGET SCHEMA: MYSCHEMA (run as ADMIN or privileged user)
--
-- Derived from AWR report: FRAUDACCRELDEFAULT (19c)
-- Adapted to SQL/PGQ native syntax
--
-- Vertex tables: MYSCHEMA.N_USER, N_DEVICE, N_CARD, N_PERSON, N_PHONE, N_BANK_ACCOUNT
-- Edge tables:   MYSCHEMA.E_VALIDATE_PERSON, E_DECLARE_PERSON, E_USES_DEVICE,
--                E_USES_GUEST_DEVICE, E_USES_CARD, E_USES_GUEST_CARD,
--                E_USES_SMART_ID, E_USES_SMART_EMAIL, E_WITHDRAWAL_BANK_ACCOUNT,
--                E_VALIDATE_PHONE, E_DECLARE_PHONE
--------------------------------------------------------------------------------

-- Clean up previous run (if exists)
BEGIN
  FOR t IN (
    SELECT table_name FROM all_tables
    WHERE owner = 'MYSCHEMA'
      AND table_name IN (
        'N_USER','N_DEVICE','N_CARD','N_PERSON','N_PHONE','N_BANK_ACCOUNT',
        'E_VALIDATE_PERSON','E_DECLARE_PERSON',
        'E_USES_DEVICE','E_USES_GUEST_DEVICE',
        'E_USES_CARD','E_USES_GUEST_CARD',
        'E_USES_SMART_ID','E_USES_SMART_EMAIL',
        'E_WITHDRAWAL_BANK_ACCOUNT',
        'E_VALIDATE_PHONE','E_DECLARE_PHONE'
      )
  ) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE MYSCHEMA.' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

-- Drop property graph if exists
BEGIN
  EXECUTE IMMEDIATE 'DROP PROPERTY GRAPH MYSCHEMA.fraud_graph';
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

--------------------------------------------------------------------------------
-- VERTEX TABLES
--------------------------------------------------------------------------------

CREATE TABLE MYSCHEMA.n_user (
  id                    NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_name             VARCHAR2(100) NOT NULL,
  email                 VARCHAR2(200),
  risk_score            NUMBER(3)     DEFAULT 0,       -- 0-100
  is_blocked            VARCHAR2(1)   DEFAULT 'N',     -- Y/N
  adjacent_edges_count  NUMBER        DEFAULT 0,
  created_date          TIMESTAMP     DEFAULT SYSTIMESTAMP,
  last_updated          TIMESTAMP     DEFAULT SYSTIMESTAMP
);

CREATE TABLE MYSCHEMA.n_device (
  id                    NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  device_fingerprint    VARCHAR2(200) NOT NULL,
  device_type           VARCHAR2(50),                  -- MOBILE, DESKTOP, TABLET
  os_name               VARCHAR2(50),
  adjacent_edges_count  NUMBER        DEFAULT 0,
  created_date          TIMESTAMP     DEFAULT SYSTIMESTAMP
);

CREATE TABLE MYSCHEMA.n_card (
  id                    NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  card_hash             VARCHAR2(200) NOT NULL,
  card_brand            VARCHAR2(30),                  -- VISA, MASTERCARD, AMEX
  is_prepaid            VARCHAR2(1)   DEFAULT 'N',
  adjacent_edges_count  NUMBER        DEFAULT 0,
  created_date          TIMESTAMP     DEFAULT SYSTIMESTAMP
);

CREATE TABLE MYSCHEMA.n_person (
  id                    NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  document_hash         VARCHAR2(200) NOT NULL,
  document_type         VARCHAR2(30),                  -- DNI, CPF, PASSPORT
  country               VARCHAR2(3),
  adjacent_edges_count  NUMBER        DEFAULT 0,
  created_date          TIMESTAMP     DEFAULT SYSTIMESTAMP
);

CREATE TABLE MYSCHEMA.n_phone (
  id                    NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  phone_hash            VARCHAR2(200) NOT NULL,
  country_code          VARCHAR2(5),
  adjacent_edges_count  NUMBER        DEFAULT 0,
  created_date          TIMESTAMP     DEFAULT SYSTIMESTAMP
);

CREATE TABLE MYSCHEMA.n_bank_account (
  id                    NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_hash          VARCHAR2(200) NOT NULL,
  bank_code             VARCHAR2(10),
  account_type          VARCHAR2(20),                  -- SAVINGS, CHECKING
  adjacent_edges_count  NUMBER        DEFAULT 0,
  created_date          TIMESTAMP     DEFAULT SYSTIMESTAMP
);

--------------------------------------------------------------------------------
-- EDGE TABLES
-- All edges have: SRC (source vertex FK), DST (dest vertex FK),
-- START_DATE, END_DATE (NULL = active), LAST_UPDATED
--------------------------------------------------------------------------------

-- User -[validates_person]-> Person
CREATE TABLE MYSCHEMA.e_validate_person (
  id            NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_user(id),
  dst           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_person(id),
  start_date    TIMESTAMP     DEFAULT SYSTIMESTAMP,
  end_date      TIMESTAMP,                             -- NULL = active
  last_updated  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- User -[declares_person]-> Person
CREATE TABLE MYSCHEMA.e_declare_person (
  id            NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_user(id),
  dst           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_person(id),
  start_date    TIMESTAMP     DEFAULT SYSTIMESTAMP,
  end_date      TIMESTAMP,
  last_updated  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- User -[uses_device]-> Device
CREATE TABLE MYSCHEMA.e_uses_device (
  id            NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_user(id),
  dst           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_device(id),
  start_date    TIMESTAMP     DEFAULT SYSTIMESTAMP,
  end_date      TIMESTAMP,
  last_updated  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- User -[uses_guest_device]-> Device
CREATE TABLE MYSCHEMA.e_uses_guest_device (
  id            NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_user(id),
  dst           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_device(id),
  start_date    TIMESTAMP     DEFAULT SYSTIMESTAMP,
  end_date      TIMESTAMP,
  last_updated  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- User -[uses_card]-> Card
CREATE TABLE MYSCHEMA.e_uses_card (
  id            NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_user(id),
  dst           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_card(id),
  start_date    TIMESTAMP     DEFAULT SYSTIMESTAMP,
  end_date      TIMESTAMP,
  last_updated  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- User -[uses_guest_card]-> Card
CREATE TABLE MYSCHEMA.e_uses_guest_card (
  id            NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_user(id),
  dst           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_card(id),
  start_date    TIMESTAMP     DEFAULT SYSTIMESTAMP,
  end_date      TIMESTAMP,
  last_updated  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- User -[uses_smart_id]-> Person
CREATE TABLE MYSCHEMA.e_uses_smart_id (
  id            NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_user(id),
  dst           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_person(id),
  start_date    TIMESTAMP     DEFAULT SYSTIMESTAMP,
  end_date      TIMESTAMP,
  last_updated  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- User -[uses_smart_email]-> Person
CREATE TABLE MYSCHEMA.e_uses_smart_email (
  id            NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_user(id),
  dst           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_person(id),
  start_date    TIMESTAMP     DEFAULT SYSTIMESTAMP,
  end_date      TIMESTAMP,
  last_updated  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- User -[withdrawal_bank_account]-> Bank Account
CREATE TABLE MYSCHEMA.e_withdrawal_bank_account (
  id            NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_user(id),
  dst           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_bank_account(id),
  amount        NUMBER(15,2),
  start_date    TIMESTAMP     DEFAULT SYSTIMESTAMP,
  end_date      TIMESTAMP,
  last_updated  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- User -[validate_phone]-> Phone
CREATE TABLE MYSCHEMA.e_validate_phone (
  id            NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_user(id),
  dst           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_phone(id),
  start_date    TIMESTAMP     DEFAULT SYSTIMESTAMP,
  end_date      TIMESTAMP,
  last_updated  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

-- User -[declare_phone]-> Phone
CREATE TABLE MYSCHEMA.e_declare_phone (
  id            NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  src           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_user(id),
  dst           NUMBER        NOT NULL REFERENCES MYSCHEMA.n_phone(id),
  start_date    TIMESTAMP     DEFAULT SYSTIMESTAMP,
  end_date      TIMESTAMP,
  last_updated  TIMESTAMP     DEFAULT SYSTIMESTAMP
);

PROMPT Schema created successfully in MYSCHEMA.
