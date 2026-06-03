--------------------------------------------------------------------------------
-- 03_generate_data.sql
-- Mini-DOWNER deterministic synthetic data generation.
--
-- Run as DOWNER_DEMO.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

DEFINE scale_factor = 1

DECLARE
  v_scale_factor       NUMBER := &&scale_factor;
  v_users              NUMBER := 12000 * v_scale_factor;
  v_devices            NUMBER := 1200 * v_scale_factor;
  v_bank_accounts      NUMBER := 4000 * v_scale_factor;
  v_cards              NUMBER := 6000 * v_scale_factor;
  v_ips                NUMBER := 3000 * v_scale_factor;
  v_uses_device        NUMBER := 80000 * v_scale_factor;
  v_withdrawals        NUMBER := 25000 * v_scale_factor;
  v_uses_card          NUMBER := 20000 * v_scale_factor;
  v_uses_ip            NUMBER := 30000 * v_scale_factor;
  v_anchor_user        VARCHAR2(64) := 'U00000042';
  v_base_ts            TIMESTAMP := TIMESTAMP '2026-06-03 00:00:00';
BEGIN
  DBMS_OUTPUT.PUT_LINE('Mini-DOWNER data generation scale=' || v_scale_factor);
  DBMS_OUTPUT.PUT_LINE('Deterministic seed: DOWNER_MINI_20260603');

  DBMS_RANDOM.SEED('DOWNER_MINI_20260603');

  INSERT /*+ APPEND */ INTO n_user (id, start_date, last_updated, registration_date, is_test_user, card_types_own, card_types_contagion, adjacent_edges_count)
  SELECT
    'U' || LPAD(LEVEL, 8, '0'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 1095), 'DAY'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 30), 'DAY'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 1095), 'DAY'),
    CASE WHEN MOD(LEVEL, 997) = 0 THEN 1 ELSE 0 END,
    CASE MOD(LEVEL, 4) WHEN 0 THEN 'CREDIT' WHEN 1 THEN 'DEBIT' WHEN 2 THEN 'PREPAID' ELSE 'MIXED' END,
    CASE MOD(LEVEL, 5) WHEN 0 THEN 'CREDIT' WHEN 1 THEN 'DEBIT' ELSE 'NONE' END,
    TRUNC(DBMS_RANDOM.VALUE(1, 250))
  FROM dual
  CONNECT BY LEVEL <= v_users;
  COMMIT;

  INSERT /*+ APPEND */ INTO n_device (id, start_date, last_updated, device_type, adjacent_edges_count)
  SELECT
    'D' || LPAD(LEVEL, 8, '0'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 730), 'DAY'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 30), 'DAY'),
    CASE MOD(LEVEL, 4) WHEN 0 THEN 'MOBILE' WHEN 1 THEN 'DESKTOP' WHEN 2 THEN 'TABLET' ELSE 'API' END,
    CASE WHEN LEVEL <= 200 THEN TRUNC(DBMS_RANDOM.VALUE(1000, 8000)) ELSE TRUNC(DBMS_RANDOM.VALUE(1, 80)) END
  FROM dual
  CONNECT BY LEVEL <= v_devices;
  COMMIT;

  INSERT /*+ APPEND */ INTO n_bank_account (id, start_date, last_updated, adjacent_edges_count)
  SELECT 'B' || LPAD(LEVEL, 8, '0'),
         v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 730), 'DAY'),
         v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 30), 'DAY'),
         TRUNC(DBMS_RANDOM.VALUE(1, 80))
  FROM dual
  CONNECT BY LEVEL <= v_bank_accounts;
  COMMIT;

  INSERT /*+ APPEND */ INTO n_card (id, start_date, last_updated, adjacent_edges_count)
  SELECT 'C' || LPAD(LEVEL, 8, '0'),
         v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 730), 'DAY'),
         v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 30), 'DAY'),
         TRUNC(DBMS_RANDOM.VALUE(1, 60))
  FROM dual
  CONNECT BY LEVEL <= v_cards;
  COMMIT;

  INSERT /*+ APPEND */ INTO n_ip (id, start_date, last_updated, adjacent_edges_count)
  SELECT 'IP' || LPAD(LEVEL, 8, '0'),
         v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 730), 'DAY'),
         v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 30), 'DAY'),
         TRUNC(DBMS_RANDOM.VALUE(1, 120))
  FROM dual
  CONNECT BY LEVEL <= v_ips;
  COMMIT;

  INSERT /*+ APPEND */ INTO e_uses_device (id, src, dst, start_date, last_updated, device_type, end_date)
  SELECT
    'UDANCH' || LPAD(LEVEL, 8, '0'),
    v_anchor_user,
    'D' || LPAD(MOD(LEVEL - 1, 200) + 1, 8, '0'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 365), 'DAY'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 30), 'DAY'),
    CASE MOD(LEVEL, 4) WHEN 0 THEN 'MOBILE' WHEN 1 THEN 'DESKTOP' WHEN 2 THEN 'TABLET' ELSE 'API' END,
    NULL
  FROM dual
  CONNECT BY LEVEL <= 200;
  COMMIT;

  INSERT /*+ APPEND */ INTO e_uses_device (id, src, dst, start_date, last_updated, device_type, end_date)
  SELECT
    'UD' || LPAD(LEVEL, 12, '0'),
    'U' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)), 8, '0'),
    CASE
      WHEN DBMS_RANDOM.VALUE < 0.38 THEN 'D' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1, 201)), 8, '0')
      ELSE 'D' || LPAD(TRUNC(DBMS_RANDOM.VALUE(201, v_devices + 1)), 8, '0')
    END,
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 365), 'DAY'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 30), 'DAY'),
    CASE MOD(LEVEL, 4) WHEN 0 THEN 'MOBILE' WHEN 1 THEN 'DESKTOP' WHEN 2 THEN 'TABLET' ELSE 'API' END,
    CASE WHEN DBMS_RANDOM.VALUE < 0.82 THEN NULL ELSE v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 180), 'DAY') END
  FROM dual
  CONNECT BY LEVEL <= v_uses_device;
  COMMIT;

  INSERT /*+ APPEND */ INTO e_withdrawal_bank_account (id, src, dst, start_date, last_updated, end_date)
  SELECT
    'WBA' || LPAD(LEVEL, 12, '0'),
    'U' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)), 8, '0'),
    'B' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1, v_bank_accounts + 1)), 8, '0'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 365), 'DAY'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 30), 'DAY'),
    CASE WHEN DBMS_RANDOM.VALUE < 0.9 THEN NULL ELSE v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 180), 'DAY') END
  FROM dual
  CONNECT BY LEVEL <= v_withdrawals;
  COMMIT;

  INSERT /*+ APPEND */ INTO e_uses_card (id, src, dst, start_date, last_updated, end_date)
  SELECT
    'UC' || LPAD(LEVEL, 12, '0'),
    'U' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)), 8, '0'),
    'C' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1, v_cards + 1)), 8, '0'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 365), 'DAY'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 30), 'DAY'),
    CASE WHEN DBMS_RANDOM.VALUE < 0.88 THEN NULL ELSE v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 180), 'DAY') END
  FROM dual
  CONNECT BY LEVEL <= v_uses_card;
  COMMIT;

  INSERT /*+ APPEND */ INTO e_uses_ip (id, src, dst, start_date, last_updated, used_at_date, end_date)
  SELECT
    'UIP' || LPAD(LEVEL, 12, '0'),
    'U' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1, v_users + 1)), 8, '0'),
    'IP' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1, v_ips + 1)), 8, '0'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 365), 'DAY'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 30), 'DAY'),
    v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 365), 'DAY'),
    CASE WHEN DBMS_RANDOM.VALUE < 0.84 THEN NULL ELSE v_base_ts - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, 180), 'DAY') END
  FROM dual
  CONNECT BY LEVEL <= v_uses_ip;
  COMMIT;

  DBMS_STATS.GATHER_SCHEMA_STATS(
    ownname => USER,
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
    cascade => TRUE,
    no_invalidate => FALSE
  );
END;
/

PROMPT Mini-DOWNER synthetic data generated.
