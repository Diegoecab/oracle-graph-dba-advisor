--------------------------------------------------------------------------------
-- 02_create_property_graph.sql
-- Fraud Detection Graph — Property Graph Definition (Oracle 23ai / 26ai)
--
-- Uses CREATE PROPERTY GRAPH DDL to define the graph over relational tables.
-- This replaces the manual relational-to-graph mapping used in 19c.
--------------------------------------------------------------------------------

CREATE PROPERTY GRAPH fraud_graph
  VERTEX TABLES (
    n_user      KEY (id)
      LABEL user_account
      PROPERTIES (id, user_name, email, risk_score, is_blocked,
                  adjacent_edges_count, created_date, last_updated),

    n_device    KEY (id)
      LABEL device
      PROPERTIES (id, device_fingerprint, device_type, os_name,
                  adjacent_edges_count, created_date),

    n_card      KEY (id)
      LABEL card
      PROPERTIES (id, card_hash, card_brand, is_prepaid,
                  adjacent_edges_count, created_date),

    n_person    KEY (id)
      LABEL person
      PROPERTIES (id, document_hash, document_type, country,
                  adjacent_edges_count, created_date),

    n_phone     KEY (id)
      LABEL phone
      PROPERTIES (id, phone_hash, country_code,
                  adjacent_edges_count, created_date),

    n_bank_account KEY (id)
      LABEL bank_account
      PROPERTIES (id, account_hash, bank_code, account_type,
                  adjacent_edges_count, created_date)
  )
  EDGE TABLES (
    e_validate_person   KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_person (id)
      LABEL validates_person
      PROPERTIES (id, start_date, end_date, last_updated),

    e_declare_person    KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_person (id)
      LABEL declares_person
      PROPERTIES (id, start_date, end_date, last_updated),

    e_uses_device       KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_device (id)
      LABEL uses_device
      PROPERTIES (id, start_date, end_date, last_updated),

    e_uses_guest_device KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_device (id)
      LABEL uses_guest_device
      PROPERTIES (id, start_date, end_date, last_updated),

    e_uses_card         KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_card (id)
      LABEL uses_card
      PROPERTIES (id, start_date, end_date, last_updated),

    e_uses_guest_card   KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_card (id)
      LABEL uses_guest_card
      PROPERTIES (id, start_date, end_date, last_updated),

    e_uses_smart_id     KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_person (id)
      LABEL uses_smart_id
      PROPERTIES (id, start_date, end_date, last_updated),

    e_uses_smart_email  KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_person (id)
      LABEL uses_smart_email
      PROPERTIES (id, start_date, end_date, last_updated),

    e_withdrawal_bank_account KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_bank_account (id)
      LABEL withdraws_from
      PROPERTIES (id, amount, start_date, end_date, last_updated),

    e_validate_phone    KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_phone (id)
      LABEL validates_phone
      PROPERTIES (id, start_date, end_date, last_updated),

    e_declare_phone     KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_phone (id)
      LABEL declares_phone
      PROPERTIES (id, start_date, end_date, last_updated)
  );

PROMPT ✅ Property graph FRAUD_GRAPH created successfully.
