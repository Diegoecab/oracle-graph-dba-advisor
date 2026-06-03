--------------------------------------------------------------------------------
-- 02_create_property_graph.sql
-- Mini-DOWNER property graph definition.
--
-- Run as DOWNER_DEMO.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON

BEGIN
  EXECUTE IMMEDIATE 'DROP PROPERTY GRAPH DOWNER_GRAPH';
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

CREATE PROPERTY GRAPH downer_graph
  VERTEX TABLES (
    n_user KEY (id)
      LABEL user_account
      PROPERTIES (id, start_date, last_updated, registration_date, is_test_user, card_types_own, card_types_contagion, adjacent_edges_count, cancelled_date),

    n_device KEY (id)
      LABEL device
      PROPERTIES (id, start_date, last_updated, device_type, adjacent_edges_count),

    n_bank_account KEY (id)
      LABEL bank_account
      PROPERTIES (id, start_date, last_updated, adjacent_edges_count),

    n_card KEY (id)
      LABEL card
      PROPERTIES (id, start_date, last_updated, adjacent_edges_count),

    n_ip KEY (id)
      LABEL ip
      PROPERTIES (id, start_date, last_updated, adjacent_edges_count)
  )
  EDGE TABLES (
    e_uses_device KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_device (id)
      LABEL uses_device
      PROPERTIES (id, start_date, last_updated, device_type, end_date),

    e_withdrawal_bank_account KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_bank_account (id)
      LABEL withdrawal_bank_account
      PROPERTIES (id, start_date, last_updated, end_date),

    e_uses_card KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_card (id)
      LABEL uses_card
      PROPERTIES (id, start_date, last_updated, end_date),

    e_uses_ip KEY (id)
      SOURCE KEY (src) REFERENCES n_user (id)
      DESTINATION KEY (dst) REFERENCES n_ip (id)
      LABEL uses_ip
      PROPERTIES (id, start_date, last_updated, used_at_date, end_date)
  );

PROMPT Property graph DOWNER_GRAPH created.
