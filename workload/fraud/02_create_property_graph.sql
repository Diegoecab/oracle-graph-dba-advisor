--------------------------------------------------------------------------------
-- 02_create_property_graph.sql
-- Fraud Detection Graph — Property Graph Definition (Oracle 23ai / 26ai)
--
-- TARGET SCHEMA: MYSCHEMA
-- Uses CREATE PROPERTY GRAPH DDL to define the graph over relational tables.
--------------------------------------------------------------------------------

CREATE PROPERTY GRAPH MYSCHEMA.fraud_graph
  VERTEX TABLES (
    MYSCHEMA.n_user      KEY (id)
      LABEL user_account
      PROPERTIES (id, user_name, email, risk_score, is_blocked,
                  adjacent_edges_count, created_date, last_updated),

    MYSCHEMA.n_device    KEY (id)
      LABEL device
      PROPERTIES (id, device_fingerprint, device_type, os_name,
                  adjacent_edges_count, created_date),

    MYSCHEMA.n_card      KEY (id)
      LABEL card
      PROPERTIES (id, card_hash, card_brand, is_prepaid,
                  adjacent_edges_count, created_date),

    MYSCHEMA.n_person    KEY (id)
      LABEL person
      PROPERTIES (id, document_hash, document_type, country,
                  adjacent_edges_count, created_date),

    MYSCHEMA.n_phone     KEY (id)
      LABEL phone
      PROPERTIES (id, phone_hash, country_code,
                  adjacent_edges_count, created_date),

    MYSCHEMA.n_bank_account KEY (id)
      LABEL bank_account
      PROPERTIES (id, account_hash, bank_code, account_type,
                  adjacent_edges_count, created_date)
  )
  EDGE TABLES (
    MYSCHEMA.e_validate_person   KEY (id)
      SOURCE KEY (src) REFERENCES MYSCHEMA.n_user (id)
      DESTINATION KEY (dst) REFERENCES MYSCHEMA.n_person (id)
      LABEL validates_person
      PROPERTIES (id, start_date, end_date, last_updated),

    MYSCHEMA.e_declare_person    KEY (id)
      SOURCE KEY (src) REFERENCES MYSCHEMA.n_user (id)
      DESTINATION KEY (dst) REFERENCES MYSCHEMA.n_person (id)
      LABEL declares_person
      PROPERTIES (id, start_date, end_date, last_updated),

    MYSCHEMA.e_uses_device       KEY (id)
      SOURCE KEY (src) REFERENCES MYSCHEMA.n_user (id)
      DESTINATION KEY (dst) REFERENCES MYSCHEMA.n_device (id)
      LABEL uses_device
      PROPERTIES (id, start_date, end_date, last_updated),

    MYSCHEMA.e_uses_guest_device KEY (id)
      SOURCE KEY (src) REFERENCES MYSCHEMA.n_user (id)
      DESTINATION KEY (dst) REFERENCES MYSCHEMA.n_device (id)
      LABEL uses_guest_device
      PROPERTIES (id, start_date, end_date, last_updated),

    MYSCHEMA.e_uses_card         KEY (id)
      SOURCE KEY (src) REFERENCES MYSCHEMA.n_user (id)
      DESTINATION KEY (dst) REFERENCES MYSCHEMA.n_card (id)
      LABEL uses_card
      PROPERTIES (id, start_date, end_date, last_updated),

    MYSCHEMA.e_uses_guest_card   KEY (id)
      SOURCE KEY (src) REFERENCES MYSCHEMA.n_user (id)
      DESTINATION KEY (dst) REFERENCES MYSCHEMA.n_card (id)
      LABEL uses_guest_card
      PROPERTIES (id, start_date, end_date, last_updated),

    MYSCHEMA.e_uses_smart_id     KEY (id)
      SOURCE KEY (src) REFERENCES MYSCHEMA.n_user (id)
      DESTINATION KEY (dst) REFERENCES MYSCHEMA.n_person (id)
      LABEL uses_smart_id
      PROPERTIES (id, start_date, end_date, last_updated),

    MYSCHEMA.e_uses_smart_email  KEY (id)
      SOURCE KEY (src) REFERENCES MYSCHEMA.n_user (id)
      DESTINATION KEY (dst) REFERENCES MYSCHEMA.n_person (id)
      LABEL uses_smart_email
      PROPERTIES (id, start_date, end_date, last_updated),

    MYSCHEMA.e_withdrawal_bank_account KEY (id)
      SOURCE KEY (src) REFERENCES MYSCHEMA.n_user (id)
      DESTINATION KEY (dst) REFERENCES MYSCHEMA.n_bank_account (id)
      LABEL withdraws_from
      PROPERTIES (id, amount, start_date, end_date, last_updated),

    MYSCHEMA.e_validate_phone    KEY (id)
      SOURCE KEY (src) REFERENCES MYSCHEMA.n_user (id)
      DESTINATION KEY (dst) REFERENCES MYSCHEMA.n_phone (id)
      LABEL validates_phone
      PROPERTIES (id, start_date, end_date, last_updated),

    MYSCHEMA.e_declare_phone     KEY (id)
      SOURCE KEY (src) REFERENCES MYSCHEMA.n_user (id)
      DESTINATION KEY (dst) REFERENCES MYSCHEMA.n_phone (id)
      LABEL declares_phone
      PROPERTIES (id, start_date, end_date, last_updated)
  );

PROMPT Property graph MYSCHEMA.FRAUD_GRAPH created successfully.
