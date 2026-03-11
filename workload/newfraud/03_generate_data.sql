--------------------------------------------------------------------------------
-- 03_generate_data.sql
-- Transaction Fraud Graph — Test Data Generation (Oracle 23ai / 26ai)
--
-- TARGET SCHEMA: NEWFRAUD (run as ADMIN with access to NEWFRAUD tables)
--
-- Generates realistic data for transaction-based fraud detection.
-- 10% of transfers concentrated on "hot" accounts (mule pattern).
-- 12% of purchases go to "hot" merchants (high-risk).
-- 8% of logins use shared suspicious IPs.
--
-- Adjust v_scale_factor to increase/decrease volume proportionally.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON
SET TIMING ON

DECLARE
  v_scale_factor    NUMBER := 1;
  -- Vertex volumes
  v_accounts        NUMBER := 30000  * v_scale_factor;
  v_merchants       NUMBER := 5000   * v_scale_factor;
  v_ips             NUMBER := 10000  * v_scale_factor;
  v_atms            NUMBER := 2000   * v_scale_factor;
  -- Edge volumes
  v_transfers       NUMBER := 100000 * v_scale_factor;
  v_purchases       NUMBER := 80000  * v_scale_factor;
  v_logins          NUMBER := 60000  * v_scale_factor;
  v_withdrawals     NUMBER := 40000  * v_scale_factor;
  v_operates_near   NUMBER := 3000   * v_scale_factor;
  -- Timing
  v_start TIMESTAMP;
BEGIN
  v_start := SYSTIMESTAMP;
  DBMS_OUTPUT.PUT_LINE('=== Data generation started at ' || TO_CHAR(v_start, 'HH24:MI:SS') || ' ===');
  DBMS_OUTPUT.PUT_LINE('Scale factor: ' || v_scale_factor);
  DBMS_OUTPUT.PUT_LINE('Target schema: NEWFRAUD');

  ---------------------------------------------------------------
  -- VERTEX DATA
  ---------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('Generating ' || v_accounts || ' accounts...');
  INSERT /*+ APPEND */ INTO NEWFRAUD.ACCOUNT
    (account_number, holder_name, account_type, risk_level, is_frozen, balance, country, opened_date, last_activity)
  SELECT
    'ACC' || LPAD(LEVEL, 8, '0'),
    'holder_' || LPAD(LEVEL, 6, '0'),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,5))
      WHEN 1 THEN 'SAVINGS' WHEN 2 THEN 'CHECKING' WHEN 3 THEN 'PREPAID' ELSE 'CRYPTO'
    END,
    CASE
      WHEN DBMS_RANDOM.VALUE < 0.70 THEN 'LOW'
      WHEN DBMS_RANDOM.VALUE < 0.90 THEN 'MEDIUM'
      WHEN DBMS_RANDOM.VALUE < 0.97 THEN 'HIGH'
      ELSE 'FROZEN'
    END,
    CASE WHEN DBMS_RANDOM.VALUE < 0.03 THEN 'Y' ELSE 'N' END,
    ROUND(DBMS_RANDOM.VALUE(0, 500000), 2),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,8))
      WHEN 1 THEN 'BR' WHEN 2 THEN 'AR' WHEN 3 THEN 'MX'
      WHEN 4 THEN 'CO' WHEN 5 THEN 'CL' WHEN 6 THEN 'US' ELSE 'UY'
    END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(30, 730),
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 60)
  FROM DUAL CONNECT BY LEVEL <= v_accounts;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_merchants || ' merchants...');
  INSERT /*+ APPEND */ INTO NEWFRAUD.MERCHANT
    (merchant_name, mcc_code, category, country, is_high_risk, created_date)
  SELECT
    'merchant_' || LPAD(LEVEL, 5, '0'),
    LPAD(TRUNC(DBMS_RANDOM.VALUE(1000, 9999)), 4, '0'),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,8))
      WHEN 1 THEN 'GAMBLING' WHEN 2 THEN 'CRYPTO_EXCHANGE' WHEN 3 THEN 'RETAIL'
      WHEN 4 THEN 'ELECTRONICS' WHEN 5 THEN 'JEWELRY' WHEN 6 THEN 'TRAVEL' ELSE 'FOOD'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,8))
      WHEN 1 THEN 'BR' WHEN 2 THEN 'AR' WHEN 3 THEN 'MX'
      WHEN 4 THEN 'CO' WHEN 5 THEN 'CL' WHEN 6 THEN 'US' ELSE 'UY'
    END,
    CASE WHEN DBMS_RANDOM.VALUE < 0.15 THEN 'Y' ELSE 'N' END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(30, 1095)
  FROM DUAL CONNECT BY LEVEL <= v_merchants;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_ips || ' IP addresses...');
  INSERT /*+ APPEND */ INTO NEWFRAUD.IP_ADDRESS
    (ip_hash, country, is_vpn, is_tor, first_seen)
  SELECT
    DBMS_RANDOM.STRING('X', 64),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,10))
      WHEN 1 THEN 'BR' WHEN 2 THEN 'AR' WHEN 3 THEN 'MX' WHEN 4 THEN 'CO'
      WHEN 5 THEN 'RU' WHEN 6 THEN 'NG' WHEN 7 THEN 'US' WHEN 8 THEN 'CN' ELSE 'UY'
    END,
    CASE WHEN DBMS_RANDOM.VALUE < 0.12 THEN 'Y' ELSE 'N' END,
    CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN 'Y' ELSE 'N' END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 730)
  FROM DUAL CONNECT BY LEVEL <= v_ips;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_atms || ' ATMs...');
  INSERT /*+ APPEND */ INTO NEWFRAUD.ATM
    (atm_code, city, country, lat, lon, installed_date)
  SELECT
    'ATM' || LPAD(LEVEL, 5, '0'),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,10))
      WHEN 1 THEN 'Sao Paulo' WHEN 2 THEN 'Buenos Aires' WHEN 3 THEN 'CDMX'
      WHEN 4 THEN 'Bogota' WHEN 5 THEN 'Santiago' WHEN 6 THEN 'Lima'
      WHEN 7 THEN 'Montevideo' WHEN 8 THEN 'Quito' ELSE 'Caracas'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,8))
      WHEN 1 THEN 'BR' WHEN 2 THEN 'AR' WHEN 3 THEN 'MX'
      WHEN 4 THEN 'CO' WHEN 5 THEN 'CL' WHEN 6 THEN 'PE' ELSE 'UY'
    END,
    ROUND(DBMS_RANDOM.VALUE(-34, 4), 6),
    ROUND(DBMS_RANDOM.VALUE(-75, -35), 6),
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(30, 1825)
  FROM DUAL CONNECT BY LEVEL <= v_atms;
  COMMIT;

  ---------------------------------------------------------------
  -- EDGE DATA
  ---------------------------------------------------------------

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_transfers || ' transfer edges...');
  -- 10% concentrated on hot accounts 1-300 (mule pattern)
  INSERT /*+ APPEND */ INTO NEWFRAUD.TRANSFER
    (src, dst, amount, currency, channel, is_flagged, created_at)
  SELECT
    CASE WHEN DBMS_RANDOM.VALUE < 0.10
      THEN TRUNC(DBMS_RANDOM.VALUE(1, 301))
      ELSE TRUNC(DBMS_RANDOM.VALUE(1, v_accounts + 1))
    END,
    CASE WHEN DBMS_RANDOM.VALUE < 0.10
      THEN TRUNC(DBMS_RANDOM.VALUE(1, 301))
      ELSE TRUNC(DBMS_RANDOM.VALUE(1, v_accounts + 1))
    END,
    ROUND(DBMS_RANDOM.VALUE(1, 50000), 2),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,4)) WHEN 1 THEN 'USD' WHEN 2 THEN 'BRL' ELSE 'ARS' END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,6))
      WHEN 1 THEN 'WIRE' WHEN 2 THEN 'ACH' WHEN 3 THEN 'P2P'
      WHEN 4 THEN 'CRYPTO' ELSE 'INTERNAL'
    END,
    CASE WHEN DBMS_RANDOM.VALUE < 0.08 THEN 'Y' ELSE 'N' END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 365)
  FROM DUAL CONNECT BY LEVEL <= v_transfers;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_purchases || ' purchase edges...');
  -- 12% go to hot merchants 1-100 (high-risk)
  INSERT /*+ APPEND */ INTO NEWFRAUD.PURCHASE
    (src, dst, amount, currency, is_flagged, created_at)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_accounts + 1)),
    CASE WHEN DBMS_RANDOM.VALUE < 0.12
      THEN TRUNC(DBMS_RANDOM.VALUE(1, 101))
      ELSE TRUNC(DBMS_RANDOM.VALUE(1, v_merchants + 1))
    END,
    ROUND(DBMS_RANDOM.VALUE(5, 10000), 2),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,4)) WHEN 1 THEN 'USD' WHEN 2 THEN 'BRL' ELSE 'ARS' END,
    CASE WHEN DBMS_RANDOM.VALUE < 0.06 THEN 'Y' ELSE 'N' END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 365)
  FROM DUAL CONNECT BY LEVEL <= v_purchases;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_logins || ' login edges...');
  -- 8% use shared suspicious IPs 1-200
  INSERT /*+ APPEND */ INTO NEWFRAUD.LOGIN_FROM
    (src, dst, login_time, success, device_type)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_accounts + 1)),
    CASE WHEN DBMS_RANDOM.VALUE < 0.08
      THEN TRUNC(DBMS_RANDOM.VALUE(1, 201))
      ELSE TRUNC(DBMS_RANDOM.VALUE(1, v_ips + 1))
    END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 365),
    CASE WHEN DBMS_RANDOM.VALUE < 0.05 THEN 'N' ELSE 'Y' END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,5))
      WHEN 1 THEN 'MOBILE' WHEN 2 THEN 'DESKTOP' WHEN 3 THEN 'TABLET' ELSE 'API'
    END
  FROM DUAL CONNECT BY LEVEL <= v_logins;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_withdrawals || ' withdrawal edges...');
  INSERT /*+ APPEND */ INTO NEWFRAUD.WITHDRAWAL
    (src, dst, amount, currency, created_at)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_accounts + 1)),
    TRUNC(DBMS_RANDOM.VALUE(1, v_atms + 1)),
    ROUND(DBMS_RANDOM.VALUE(20, 5000), 2),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,4)) WHEN 1 THEN 'USD' WHEN 2 THEN 'BRL' ELSE 'ARS' END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(0, 365)
  FROM DUAL CONNECT BY LEVEL <= v_withdrawals;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_operates_near || ' operates_near edges...');
  INSERT /*+ APPEND */ INTO NEWFRAUD.OPERATES_NEAR
    (src, dst, distance_km, since_date)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_merchants + 1)),
    TRUNC(DBMS_RANDOM.VALUE(1, v_atms + 1)),
    ROUND(DBMS_RANDOM.VALUE(0.1, 25), 2),
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(30, 1095)
  FROM DUAL CONNECT BY LEVEL <= v_operates_near;
  COMMIT;

  ---------------------------------------------------------------
  -- GATHER STATISTICS
  ---------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('Gathering optimizer statistics for NEWFRAUD...');
  DBMS_STATS.GATHER_SCHEMA_STATS(
    ownname          => 'NEWFRAUD',
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
SELECT /* LLM in use is claude-opus-4-6 */
  CASE WHEN table_name IN ('ACCOUNT','MERCHANT','IP_ADDRESS','ATM') THEN 'VERTEX' ELSE 'EDGE' END AS category,
  table_name,
  num_rows
FROM all_tables
WHERE owner = 'NEWFRAUD'
  AND table_name NOT LIKE 'DBTOOLS%'
ORDER BY 1, num_rows DESC;
