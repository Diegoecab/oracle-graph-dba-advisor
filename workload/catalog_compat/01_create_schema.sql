--------------------------------------------------------------------------------
-- 01_create_schema.sql
-- Catalog Compatibility Graph — Schema Creation (Oracle 23ai / 26ai)
--
-- Derived from AWR report: CATALOGCOMPATSOCIASH3 (19c, RAC 2-node)
-- PDB: GCBF9D6AE94EDE2_CATALOGCOMPATSOCIASH3
--
-- Data model: Product/Item compatibility network
--   Vertex tables: MAIN_PRODUCT, ITEM, USER_PRODUCT
--   Edge tables:   COMPATIBLE_WITH_ITEM, COMPATIBLE_WITH_USER_PRODUCT,
--                  COMPATIBLE_WITH_PRODUCT
--
-- Access pattern: Heavy INSERT + point lookups on composite keys.
-- Real workload: 73M inserts + 82M selects in 24h on edge tables.
--------------------------------------------------------------------------------

-- Clean up previous run
BEGIN
  FOR t IN (
    SELECT table_name FROM user_tables
    WHERE table_name IN (
      'MAIN_PRODUCT','ITEM','USER_PRODUCT',
      'COMPATIBLE_WITH_ITEM','COMPATIBLE_WITH_USER_PRODUCT',
      'COMPATIBLE_WITH_PRODUCT'
    )
  ) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP PROPERTY GRAPH catalog_compat_graph';
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

--------------------------------------------------------------------------------
-- VERTEX TABLES
--------------------------------------------------------------------------------

CREATE TABLE main_product (
  product_id    NUMBER        NOT NULL,
  site_id       VARCHAR2(10)  NOT NULL,
  product_name  VARCHAR2(200),
  category      VARCHAR2(100),
  domain_code   VARCHAR2(50),
  status        VARCHAR2(20)  DEFAULT 'ACTIVE',
  created_date  TIMESTAMP     DEFAULT SYSTIMESTAMP,
  CONSTRAINT pk_main_product PRIMARY KEY (product_id)
);

CREATE TABLE item (
  item_id       NUMBER        NOT NULL,
  site_id       VARCHAR2(10)  NOT NULL,
  item_title    VARCHAR2(300),
  seller_id     NUMBER,
  price         NUMBER(15,2),
  condition     VARCHAR2(20),              -- NEW, USED, REFURBISHED
  status        VARCHAR2(20)  DEFAULT 'ACTIVE',
  created_date  TIMESTAMP     DEFAULT SYSTIMESTAMP,
  CONSTRAINT pk_item PRIMARY KEY (item_id)
);

-- USER_PRODUCT: represents a user's listing/publication of a product
CREATE TABLE user_product (
  user_product_id  NUMBER        NOT NULL,
  site_id          VARCHAR2(10)  NOT NULL,
  user_id          NUMBER,
  product_id       NUMBER,
  listing_type     VARCHAR2(30),           -- GOLD_SPECIAL, GOLD, SILVER, BRONZE
  status           VARCHAR2(20)  DEFAULT 'ACTIVE',
  created_date     TIMESTAMP     DEFAULT SYSTIMESTAMP,
  CONSTRAINT pk_user_product PRIMARY KEY (user_product_id)
);

--------------------------------------------------------------------------------
-- EDGE TABLES (Compatibility Relationships)
-- All partitioned by SITE_ID for multi-marketplace support (MLA, MLB, MLM...)
-- Schema matches AWR: COMPATIBILITY_ID as PK (sequence-generated),
-- composite unique constraints on (entity_id, main_product_id, site_id, domain_code)
--------------------------------------------------------------------------------

-- Item <-> Product compatibility
CREATE TABLE compatible_with_item (
  compatibility_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  item_id             NUMBER        NOT NULL REFERENCES item(item_id),
  main_product_id     NUMBER        NOT NULL REFERENCES main_product(product_id),
  site_id             VARCHAR2(10)  NOT NULL,
  main_domain_code    VARCHAR2(50)  NOT NULL,
  source              VARCHAR2(50),
  creation_source     VARCHAR2(50),
  date_created        TIMESTAMP     DEFAULT SYSTIMESTAMP,
  reputation_level    VARCHAR2(20),
  note_status         VARCHAR2(20)  DEFAULT 'NONE',   -- NONE, NOTE, WARNING
  note                VARCHAR2(500),
  claims              NUMBER        DEFAULT 0,
  restrictions        VARCHAR2(500),
  restrictions_status VARCHAR2(20)  DEFAULT 'NONE'
)
PARTITION BY LIST (site_id) (
  PARTITION cwi_mla VALUES ('MLA'),
  PARTITION cwi_mlb VALUES ('MLB'),
  PARTITION cwi_mlm VALUES ('MLM'),
  PARTITION cwi_mlc VALUES ('MLC'),
  PARTITION cwi_mco VALUES ('MCO'),
  PARTITION cwi_mlu VALUES ('MLU'),
  PARTITION cwi_default VALUES (DEFAULT)
);

-- User Product <-> Product compatibility
CREATE TABLE compatible_with_user_product (
  compatibility_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_product_id     NUMBER        NOT NULL REFERENCES user_product(user_product_id),
  main_product_id     NUMBER        NOT NULL REFERENCES main_product(product_id),
  site_id             VARCHAR2(10)  NOT NULL,
  main_domain_code    VARCHAR2(50)  NOT NULL,
  source              VARCHAR2(50),
  creation_source     VARCHAR2(50),
  date_created        TIMESTAMP     DEFAULT SYSTIMESTAMP,
  reputation_level    VARCHAR2(20),
  note_status         VARCHAR2(20)  DEFAULT 'NONE',
  note                VARCHAR2(500),
  claims              NUMBER        DEFAULT 0,
  restrictions        VARCHAR2(500),
  restrictions_status VARCHAR2(20)  DEFAULT 'NONE'
)
PARTITION BY LIST (site_id) (
  PARTITION cwup_mla VALUES ('MLA'),
  PARTITION cwup_mlb VALUES ('MLB'),
  PARTITION cwup_mlm VALUES ('MLM'),
  PARTITION cwup_mlc VALUES ('MLC'),
  PARTITION cwup_mco VALUES ('MCO'),
  PARTITION cwup_mlu VALUES ('MLU'),
  PARTITION cwup_default VALUES (DEFAULT)
);

-- Product <-> Product compatibility (secondary compatibility)
CREATE TABLE compatible_with_product (
  compatibility_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  main_product_id     NUMBER        NOT NULL REFERENCES main_product(product_id),
  secondary_product_id NUMBER       NOT NULL REFERENCES main_product(product_id),
  site_id             VARCHAR2(10)  NOT NULL,
  main_domain_code    VARCHAR2(50)  NOT NULL,
  source              VARCHAR2(50),
  creation_source     VARCHAR2(50),
  date_created        TIMESTAMP     DEFAULT SYSTIMESTAMP,
  reputation_level    VARCHAR2(20),
  note_status         VARCHAR2(20)  DEFAULT 'NONE',
  note                VARCHAR2(500),
  claims              NUMBER        DEFAULT 0,
  restrictions        VARCHAR2(500),
  restrictions_status VARCHAR2(20)  DEFAULT 'NONE'
)
PARTITION BY LIST (site_id) (
  PARTITION cwp_mla VALUES ('MLA'),
  PARTITION cwp_mlb VALUES ('MLB'),
  PARTITION cwp_mlm VALUES ('MLM'),
  PARTITION cwp_mlc VALUES ('MLC'),
  PARTITION cwp_mco VALUES ('MCO'),
  PARTITION cwp_mlu VALUES ('MLU'),
  PARTITION cwp_default VALUES (DEFAULT)
);

--------------------------------------------------------------------------------
-- UNIQUE CONSTRAINTS (from AWR index names)
-- These replicate the real indexes seen in the AWR segment statistics
--------------------------------------------------------------------------------

-- CWI: unique on (ITEM_ID, MAIN_PRODUCT_ID) — maps to IDX_CWI_ITEM_PROD_U
CREATE UNIQUE INDEX idx_cwi_item_prod_u
  ON compatible_with_item (item_id, main_product_id) LOCAL;

-- CWUP: unique on (USER_PRODUCT_ID, MAIN_PRODUCT_ID, SITE_ID, MAIN_DOMAIN_CODE)
-- Maps to CWUP_USER_MAINP_SITE_MAINDC_U — #1 hottest index (30.9% logical reads)
CREATE UNIQUE INDEX cwup_user_mainp_site_maindc_u
  ON compatible_with_user_product (user_product_id, main_product_id, site_id, main_domain_code) LOCAL;

-- CWP: unique on (MAIN_PRODUCT_ID, SECONDARY_PRODUCT_ID, SITE_ID, MAIN_DOMAIN_CODE)
-- Maps to IDX_CWP_MPROD_SPROD_SITE_DOMCODE_U
CREATE UNIQUE INDEX idx_cwp_mprod_sprod_site_domcode_u
  ON compatible_with_product (main_product_id, secondary_product_id, site_id, main_domain_code) LOCAL;

-- Additional indexes seen in AWR (on MAIN_PRODUCT_ID for FK lookups)
CREATE INDEX idx_cwi_main_product_id
  ON compatible_with_item (main_product_id) LOCAL;

CREATE INDEX idx_cwup_main_product_id
  ON compatible_with_user_product (main_product_id) LOCAL;

PROMPT Schema created successfully. Partitioned by SITE_ID (MLA, MLB, MLM, MLC, MCO, MLU).
