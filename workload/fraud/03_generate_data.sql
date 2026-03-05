--------------------------------------------------------------------------------
-- 03_generate_data.sql
-- Fraud Detection Graph — Test Data Generation (Oracle 23ai / 26ai)
--
-- TARGET SCHEMA: MYSCHEMA (run as ADMIN with access to MYSCHEMA tables)
--
-- Generates realistic data volumes derived from AWR analysis.
-- Adjust v_scale_factor to increase/decrease volume proportionally.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON
SET TIMING ON

DECLARE
  v_scale_factor  NUMBER := 1;   -- Multiply all volumes by this factor
  -- Vertex volumes
  v_users         NUMBER := 50000  * v_scale_factor;
  v_devices       NUMBER := 20000  * v_scale_factor;
  v_cards         NUMBER := 15000  * v_scale_factor;
  v_persons       NUMBER := 10000  * v_scale_factor;
  v_phones        NUMBER := 8000   * v_scale_factor;
  v_bank_accounts NUMBER := 5000   * v_scale_factor;
  -- Edge volumes (approximate)
  v_validate_person   NUMBER := 45000  * v_scale_factor;
  v_declare_person    NUMBER := 48000  * v_scale_factor;
  v_uses_device       NUMBER := 80000  * v_scale_factor;
  v_uses_guest_device NUMBER := 30000  * v_scale_factor;
  v_uses_card         NUMBER := 60000  * v_scale_factor;
  v_uses_guest_card   NUMBER := 25000  * v_scale_factor;
  v_uses_smart_id     NUMBER := 20000  * v_scale_factor;
  v_uses_smart_email  NUMBER := 18000  * v_scale_factor;
  v_withdrawal_ba     NUMBER := 35000  * v_scale_factor;
  v_validate_phone    NUMBER := 30000  * v_scale_factor;
  v_declare_phone     NUMBER := 28000  * v_scale_factor;
  -- Timing
  v_start TIMESTAMP;
BEGIN
  v_start := SYSTIMESTAMP;
  DBMS_OUTPUT.PUT_LINE('=== Data generation started at ' || TO_CHAR(v_start, 'HH24:MI:SS') || ' ===');
  DBMS_OUTPUT.PUT_LINE('Scale factor: ' || v_scale_factor);
  DBMS_OUTPUT.PUT_LINE('Target schema: MYSCHEMA');

  ---------------------------------------------------------------
  -- VERTEX DATA
  ---------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('Generating ' || v_users || ' users...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.n_user (user_name, email, risk_score, is_blocked, adjacent_edges_count, created_date, last_updated)
  SELECT
    'user_' || LPAD(LEVEL, 6, '0'),
    'user_' || LPAD(LEVEL, 6, '0') || '@test.com',
    CASE
      WHEN DBMS_RANDOM.VALUE < 0.80 THEN TRUNC(DBMS_RANDOM.VALUE(0, 20))
      WHEN DBMS_RANDOM.VALUE < 0.95 THEN TRUNC(DBMS_RANDOM.VALUE(21, 60))
      ELSE TRUNC(DBMS_RANDOM.VALUE(61, 100))
    END,
    CASE WHEN DBMS_RANDOM.VALUE < 0.02 THEN 'Y' ELSE 'N' END,
    0,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 730),
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 30)
  FROM DUAL CONNECT BY LEVEL <= v_users;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_devices || ' devices...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.n_device (device_fingerprint, device_type, os_name, adjacent_edges_count, created_date)
  SELECT
    DBMS_RANDOM.STRING('X', 32),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,4))
      WHEN 1 THEN 'MOBILE' WHEN 2 THEN 'DESKTOP' ELSE 'TABLET'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,5))
      WHEN 1 THEN 'ANDROID' WHEN 2 THEN 'IOS' WHEN 3 THEN 'WINDOWS' ELSE 'MACOS'
    END,
    0,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 730)
  FROM DUAL CONNECT BY LEVEL <= v_devices;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_cards || ' cards...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.n_card (card_hash, card_brand, is_prepaid, adjacent_edges_count, created_date)
  SELECT
    DBMS_RANDOM.STRING('X', 40),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,5))
      WHEN 1 THEN 'VISA' WHEN 2 THEN 'MASTERCARD' WHEN 3 THEN 'AMEX' ELSE 'ELO'
    END,
    CASE WHEN DBMS_RANDOM.VALUE < 0.15 THEN 'Y' ELSE 'N' END,
    0,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 730)
  FROM DUAL CONNECT BY LEVEL <= v_cards;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_persons || ' persons...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.n_person (document_hash, document_type, country, adjacent_edges_count, created_date)
  SELECT
    DBMS_RANDOM.STRING('X', 40),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,4))
      WHEN 1 THEN 'CPF' WHEN 2 THEN 'DNI' ELSE 'PASSPORT'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,7))
      WHEN 1 THEN 'BR' WHEN 2 THEN 'AR' WHEN 3 THEN 'MX'
      WHEN 4 THEN 'CO' WHEN 5 THEN 'CL' ELSE 'UY'
    END,
    0,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 730)
  FROM DUAL CONNECT BY LEVEL <= v_persons;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_phones || ' phones...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.n_phone (phone_hash, country_code, adjacent_edges_count, created_date)
  SELECT
    DBMS_RANDOM.STRING('X', 20),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,7))
      WHEN 1 THEN '+55' WHEN 2 THEN '+54' WHEN 3 THEN '+52'
      WHEN 4 THEN '+57' WHEN 5 THEN '+56' ELSE '+598'
    END,
    0,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 730)
  FROM DUAL CONNECT BY LEVEL <= v_phones;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_bank_accounts || ' bank accounts...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.n_bank_account (account_hash, bank_code, account_type, adjacent_edges_count, created_date)
  SELECT
    DBMS_RANDOM.STRING('X', 30),
    LPAD(TRUNC(DBMS_RANDOM.VALUE(1, 300)), 3, '0'),
    CASE WHEN DBMS_RANDOM.VALUE < 0.6 THEN 'SAVINGS' ELSE 'CHECKING' END,
    0,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 730)
  FROM DUAL CONNECT BY LEVEL <= v_bank_accounts;
  COMMIT;

  ---------------------------------------------------------------
  -- EDGE DATA
  ---------------------------------------------------------------

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_validate_person || ' validate_person edges...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.e_validate_person (src, dst, start_date, end_date, last_updated)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)),
    CASE WHEN DBMS_RANDOM.VALUE < 0.10
      THEN TRUNC(DBMS_RANDOM.VALUE(1, GREATEST(v_persons * 0.01, 1) + 1))
      ELSE TRUNC(DBMS_RANDOM.VALUE(1, v_persons + 1))
    END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE WHEN DBMS_RANDOM.VALUE < 0.05
      THEN SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 30)
      ELSE NULL
    END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 90)
  FROM DUAL CONNECT BY LEVEL <= v_validate_person;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_declare_person || ' declare_person edges...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.e_declare_person (src, dst, start_date, end_date, last_updated)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)),
    CASE WHEN DBMS_RANDOM.VALUE < 0.10
      THEN TRUNC(DBMS_RANDOM.VALUE(1, GREATEST(v_persons * 0.01, 1) + 1))
      ELSE TRUNC(DBMS_RANDOM.VALUE(1, v_persons + 1))
    END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 30) ELSE NULL END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 90)
  FROM DUAL CONNECT BY LEVEL <= v_declare_person;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_uses_device || ' uses_device edges...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.e_uses_device (src, dst, start_date, end_date, last_updated)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)),
    CASE WHEN DBMS_RANDOM.VALUE < 0.15
      THEN TRUNC(DBMS_RANDOM.VALUE(1, GREATEST(v_devices * 0.01, 1) + 1))
      ELSE TRUNC(DBMS_RANDOM.VALUE(1, v_devices + 1))
    END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 30) ELSE NULL END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 90)
  FROM DUAL CONNECT BY LEVEL <= v_uses_device;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_uses_guest_device || ' uses_guest_device edges...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.e_uses_guest_device (src, dst, start_date, end_date, last_updated)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)),
    CASE WHEN DBMS_RANDOM.VALUE < 0.15
      THEN TRUNC(DBMS_RANDOM.VALUE(1, GREATEST(v_devices * 0.01, 1) + 1))
      ELSE TRUNC(DBMS_RANDOM.VALUE(1, v_devices + 1))
    END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 30) ELSE NULL END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 90)
  FROM DUAL CONNECT BY LEVEL <= v_uses_guest_device;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_uses_card || ' uses_card edges...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.e_uses_card (src, dst, start_date, end_date, last_updated)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)),
    CASE WHEN DBMS_RANDOM.VALUE < 0.10
      THEN TRUNC(DBMS_RANDOM.VALUE(1, GREATEST(v_cards * 0.01, 1) + 1))
      ELSE TRUNC(DBMS_RANDOM.VALUE(1, v_cards + 1))
    END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 30) ELSE NULL END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 90)
  FROM DUAL CONNECT BY LEVEL <= v_uses_card;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_uses_guest_card || ' uses_guest_card edges...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.e_uses_guest_card (src, dst, start_date, end_date, last_updated)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)),
    CASE WHEN DBMS_RANDOM.VALUE < 0.10
      THEN TRUNC(DBMS_RANDOM.VALUE(1, GREATEST(v_cards * 0.01, 1) + 1))
      ELSE TRUNC(DBMS_RANDOM.VALUE(1, v_cards + 1))
    END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 30) ELSE NULL END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 90)
  FROM DUAL CONNECT BY LEVEL <= v_uses_guest_card;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_uses_smart_id || ' uses_smart_id edges...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.e_uses_smart_id (src, dst, start_date, end_date, last_updated)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)),
    TRUNC(DBMS_RANDOM.VALUE(1, v_persons + 1)),
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 30) ELSE NULL END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 90)
  FROM DUAL CONNECT BY LEVEL <= v_uses_smart_id;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_uses_smart_email || ' uses_smart_email edges...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.e_uses_smart_email (src, dst, start_date, end_date, last_updated)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)),
    TRUNC(DBMS_RANDOM.VALUE(1, v_persons + 1)),
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 30) ELSE NULL END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 90)
  FROM DUAL CONNECT BY LEVEL <= v_uses_smart_email;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_withdrawal_ba || ' withdrawal_bank_account edges...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.e_withdrawal_bank_account (src, dst, amount, start_date, end_date, last_updated)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)),
    TRUNC(DBMS_RANDOM.VALUE(1, v_bank_accounts + 1)),
    ROUND(DBMS_RANDOM.VALUE(10, 50000), 2),
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 30) ELSE NULL END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 90)
  FROM DUAL CONNECT BY LEVEL <= v_withdrawal_ba;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_validate_phone || ' validate_phone edges...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.e_validate_phone (src, dst, start_date, end_date, last_updated)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)),
    TRUNC(DBMS_RANDOM.VALUE(1, v_phones + 1)),
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 30) ELSE NULL END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 90)
  FROM DUAL CONNECT BY LEVEL <= v_validate_phone;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_declare_phone || ' declare_phone edges...');
  INSERT /*+ APPEND */ INTO MYSCHEMA.e_declare_phone (src, dst, start_date, end_date, last_updated)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)),
    TRUNC(DBMS_RANDOM.VALUE(1, v_phones + 1)),
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 30) ELSE NULL END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 90)
  FROM DUAL CONNECT BY LEVEL <= v_declare_phone;
  COMMIT;

  ---------------------------------------------------------------
  -- UPDATE ADJACENT_EDGES_COUNT on vertex tables
  ---------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('Updating adjacent_edges_count on MYSCHEMA.n_user...');
  MERGE INTO MYSCHEMA.n_user u
  USING (
    SELECT src AS id, COUNT(*) AS cnt FROM (
      SELECT src FROM MYSCHEMA.e_validate_person   UNION ALL
      SELECT src FROM MYSCHEMA.e_declare_person    UNION ALL
      SELECT src FROM MYSCHEMA.e_uses_device       UNION ALL
      SELECT src FROM MYSCHEMA.e_uses_guest_device UNION ALL
      SELECT src FROM MYSCHEMA.e_uses_card         UNION ALL
      SELECT src FROM MYSCHEMA.e_uses_guest_card   UNION ALL
      SELECT src FROM MYSCHEMA.e_uses_smart_id     UNION ALL
      SELECT src FROM MYSCHEMA.e_uses_smart_email  UNION ALL
      SELECT src FROM MYSCHEMA.e_withdrawal_bank_account UNION ALL
      SELECT src FROM MYSCHEMA.e_validate_phone    UNION ALL
      SELECT src FROM MYSCHEMA.e_declare_phone
    ) GROUP BY src
  ) e ON (u.id = e.id)
  WHEN MATCHED THEN UPDATE SET u.adjacent_edges_count = e.cnt;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Updating adjacent_edges_count on MYSCHEMA.n_device...');
  MERGE INTO MYSCHEMA.n_device d
  USING (
    SELECT dst AS id, COUNT(*) AS cnt FROM (
      SELECT dst FROM MYSCHEMA.e_uses_device UNION ALL SELECT dst FROM MYSCHEMA.e_uses_guest_device
    ) GROUP BY dst
  ) e ON (d.id = e.id)
  WHEN MATCHED THEN UPDATE SET d.adjacent_edges_count = e.cnt;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Updating adjacent_edges_count on MYSCHEMA.n_card...');
  MERGE INTO MYSCHEMA.n_card c
  USING (
    SELECT dst AS id, COUNT(*) AS cnt FROM (
      SELECT dst FROM MYSCHEMA.e_uses_card UNION ALL SELECT dst FROM MYSCHEMA.e_uses_guest_card
    ) GROUP BY dst
  ) e ON (c.id = e.id)
  WHEN MATCHED THEN UPDATE SET c.adjacent_edges_count = e.cnt;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Updating adjacent_edges_count on MYSCHEMA.n_person...');
  MERGE INTO MYSCHEMA.n_person p
  USING (
    SELECT dst AS id, COUNT(*) AS cnt FROM (
      SELECT dst FROM MYSCHEMA.e_validate_person UNION ALL SELECT dst FROM MYSCHEMA.e_declare_person
      UNION ALL SELECT dst FROM MYSCHEMA.e_uses_smart_id UNION ALL SELECT dst FROM MYSCHEMA.e_uses_smart_email
    ) GROUP BY dst
  ) e ON (p.id = e.id)
  WHEN MATCHED THEN UPDATE SET p.adjacent_edges_count = e.cnt;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Updating adjacent_edges_count on MYSCHEMA.n_phone...');
  MERGE INTO MYSCHEMA.n_phone ph
  USING (
    SELECT dst AS id, COUNT(*) AS cnt FROM (
      SELECT dst FROM MYSCHEMA.e_validate_phone UNION ALL SELECT dst FROM MYSCHEMA.e_declare_phone
    ) GROUP BY dst
  ) e ON (ph.id = e.id)
  WHEN MATCHED THEN UPDATE SET ph.adjacent_edges_count = e.cnt;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Updating adjacent_edges_count on MYSCHEMA.n_bank_account...');
  MERGE INTO MYSCHEMA.n_bank_account ba
  USING (
    SELECT dst AS id, COUNT(*) AS cnt
    FROM MYSCHEMA.e_withdrawal_bank_account GROUP BY dst
  ) e ON (ba.id = e.id)
  WHEN MATCHED THEN UPDATE SET ba.adjacent_edges_count = e.cnt;
  COMMIT;

  ---------------------------------------------------------------
  -- GATHER STATISTICS
  ---------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('Gathering optimizer statistics for MYSCHEMA...');
  DBMS_STATS.GATHER_SCHEMA_STATS(
    ownname          => 'MYSCHEMA',
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
    method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
    cascade          => TRUE,
    no_invalidate    => FALSE
  );

  DBMS_OUTPUT.PUT_LINE('=== Data generation completed in ' ||
    EXTRACT(SECOND FROM (SYSTIMESTAMP - v_start)) || ' seconds ===');
END;
/

-- Summary
SELECT /* LLM in use is claude-opus-4-6 */ 'VERTICES' AS category, table_name, num_rows
FROM all_tables
WHERE owner = 'MYSCHEMA' AND table_name LIKE 'N\_%' ESCAPE '\'
UNION ALL
SELECT 'EDGES', table_name, num_rows
FROM all_tables
WHERE owner = 'MYSCHEMA' AND table_name LIKE 'E\_%' ESCAPE '\'
ORDER BY 1, 2
