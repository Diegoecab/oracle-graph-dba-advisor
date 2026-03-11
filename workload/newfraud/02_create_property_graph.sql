--------------------------------------------------------------------------------
-- 02_create_property_graph.sql
-- Transaction Fraud Graph — Property Graph Definition (Oracle 23ai / 26ai)
--
-- TARGET SCHEMA: NEWFRAUD
-- Run as ADMIN with CURRENT_SCHEMA set to NEWFRAUD, or connect as NEWFRAUD.
--
-- NOTE: REFERENCES inside CREATE PROPERTY GRAPH must use unqualified table
-- names when CURRENT_SCHEMA matches the owner. Set session before running:
--   ALTER SESSION SET CURRENT_SCHEMA = NEWFRAUD;
--------------------------------------------------------------------------------

ALTER SESSION SET CURRENT_SCHEMA = NEWFRAUD;

CREATE PROPERTY GRAPH TX_FRAUD_GRAPH
  VERTEX TABLES (
    ACCOUNT     KEY (id)
      LABEL account
      PROPERTIES (id, account_number, holder_name, account_type, risk_level,
                  is_frozen, balance, country, opened_date, last_activity),

    MERCHANT    KEY (id)
      LABEL merchant
      PROPERTIES (id, merchant_name, mcc_code, category, country, is_high_risk,
                  created_date),

    IP_ADDRESS  KEY (id)
      LABEL ip_address
      PROPERTIES (id, ip_hash, country, is_vpn, is_tor, first_seen),

    ATM         KEY (id)
      LABEL atm
      PROPERTIES (id, atm_code, city, country, lat, lon, installed_date)
  )
  EDGE TABLES (
    TRANSFER    KEY (id)
      SOURCE KEY (src) REFERENCES ACCOUNT (id)
      DESTINATION KEY (dst) REFERENCES ACCOUNT (id)
      LABEL transfers_to
      PROPERTIES (id, amount, currency, channel, is_flagged, created_at),

    PURCHASE    KEY (id)
      SOURCE KEY (src) REFERENCES ACCOUNT (id)
      DESTINATION KEY (dst) REFERENCES MERCHANT (id)
      LABEL purchases_at
      PROPERTIES (id, amount, currency, is_flagged, created_at),

    LOGIN_FROM  KEY (id)
      SOURCE KEY (src) REFERENCES ACCOUNT (id)
      DESTINATION KEY (dst) REFERENCES IP_ADDRESS (id)
      LABEL logs_in_from
      PROPERTIES (id, login_time, success, device_type),

    WITHDRAWAL  KEY (id)
      SOURCE KEY (src) REFERENCES ACCOUNT (id)
      DESTINATION KEY (dst) REFERENCES ATM (id)
      LABEL withdraws_at
      PROPERTIES (id, amount, currency, created_at),

    OPERATES_NEAR KEY (id)
      SOURCE KEY (src) REFERENCES MERCHANT (id)
      DESTINATION KEY (dst) REFERENCES ATM (id)
      LABEL located_near
      PROPERTIES (id, distance_km, since_date)
  );

PROMPT Property graph NEWFRAUD.TX_FRAUD_GRAPH created successfully.
