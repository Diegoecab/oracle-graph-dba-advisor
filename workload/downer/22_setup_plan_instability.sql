--------------------------------------------------------------------------------
-- 22_setup_plan_instability.sql
-- Prepares a Mini-DOWNER plan-instability scenario.
--
-- Run as DOWNER_DEMO. This is an out-of-band setup script, not a diagnostic
-- MCP script. It creates a skewed operational lookup table used by a stable
-- SQL text tagged DOWNER_PI_Q01.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE plan_instability_demo PURGE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -942 THEN
      RAISE;
    END IF;
END;
/

CREATE TABLE plan_instability_demo (
  id          NUMBER NOT NULL,
  skew_key    NUMBER NOT NULL,
  user_id     VARCHAR2(64) NOT NULL,
  device_id   VARCHAR2(64) NOT NULL,
  risk_score  NUMBER NOT NULL,
  event_state VARCHAR2(16) NOT NULL,
  created_at  TIMESTAMP NOT NULL,
  padding     VARCHAR2(200),
  CONSTRAINT plan_instability_demo_pk PRIMARY KEY (id)
);

INSERT /*+ APPEND */ INTO plan_instability_demo (
  id,
  skew_key,
  user_id,
  device_id,
  risk_score,
  event_state,
  created_at,
  padding
)
SELECT
  LEVEL AS id,
  CASE
    WHEN LEVEL <= 120000 THEN 1
    ELSE LEVEL
  END AS skew_key,
  'U' || LPAD(MOD(LEVEL, 12000) + 1, 8, '0') AS user_id,
  CASE
    WHEN LEVEL <= 120000 THEN 'D00000001'
    ELSE 'D' || LPAD(MOD(LEVEL, 1200) + 1, 8, '0')
  END AS device_id,
  MOD(LEVEL, 1000) AS risk_score,
  CASE
    WHEN MOD(LEVEL, 5) = 0 THEN 'REVIEW'
    WHEN MOD(LEVEL, 7) = 0 THEN 'BLOCKED'
    ELSE 'ALLOW'
  END AS event_state,
  TIMESTAMP '2026-06-03 00:00:00' - NUMTODSINTERVAL(MOD(LEVEL, 365), 'DAY') AS created_at,
  RPAD('risk-event', 120, 'x') AS padding
FROM dual
CONNECT BY LEVEL <= 160000;

COMMIT;

CREATE INDEX idx_pid_skew ON plan_instability_demo (skew_key);

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(
    ownname    => USER,
    tabname    => 'PLAN_INSTABILITY_DEMO',
    cascade    => TRUE,
    method_opt => 'FOR COLUMNS SIZE 254 SKEW_KEY'
  );
END;
/

CREATE OR REPLACE PROCEDURE run_downer_plan_instability_workload (
  p_cycles                   IN NUMBER   DEFAULT 24,
  p_sql_tag                  IN VARCHAR2 DEFAULT 'DOWNER_PI_Q01',
  p_optimizer_mode           IN VARCHAR2 DEFAULT 'ALL_ROWS',
  p_optimizer_index_cost_adj IN NUMBER   DEFAULT NULL,
  p_key_mode                 IN VARCHAR2 DEFAULT 'MIXED'
) AS
  v_cycles         NUMBER := LEAST(GREATEST(TRUNC(NVL(p_cycles, 24)), 1), 1000);
  v_sql_tag        VARCHAR2(64);
  v_optimizer_mode VARCHAR2(30);
  v_key_mode       VARCHAR2(16);
  v_key            NUMBER;
  v_sum            NUMBER;
  v_sql            CLOB;
BEGIN
  v_sql_tag := REGEXP_REPLACE(UPPER(SUBSTR(NVL(p_sql_tag, 'DOWNER_PI_Q01'), 1, 60)), '[^A-Z0-9_]', '_');
  IF v_sql_tag NOT LIKE 'DOWNER_PI_Q01%' THEN
    RAISE_APPLICATION_ERROR(-20000, 'SQL tag must start with DOWNER_PI_Q01');
  END IF;

  v_optimizer_mode := UPPER(SUBSTR(NVL(p_optimizer_mode, 'ALL_ROWS'), 1, 30));
  IF v_optimizer_mode NOT IN ('ALL_ROWS', 'FIRST_ROWS_1', 'FIRST_ROWS_10', 'FIRST_ROWS_100') THEN
    v_optimizer_mode := 'ALL_ROWS';
  END IF;

  v_key_mode := UPPER(SUBSTR(NVL(p_key_mode, 'MIXED'), 1, 16));
  IF v_key_mode NOT IN ('HOT', 'COLD', 'MIXED') THEN
    v_key_mode := 'MIXED';
  END IF;

  EXECUTE IMMEDIATE 'ALTER SESSION SET optimizer_mode = ' || v_optimizer_mode;

  IF p_optimizer_index_cost_adj IS NOT NULL THEN
    EXECUTE IMMEDIATE 'ALTER SESSION SET optimizer_index_cost_adj = ' ||
      TO_CHAR(LEAST(GREATEST(TRUNC(p_optimizer_index_cost_adj), 1), 10000));
  END IF;

  DBMS_APPLICATION_INFO.SET_MODULE(
    module_name => 'MINI_DOWNER_PLAN_INSTABILITY',
    action_name => v_sql_tag || ':' || v_optimizer_mode || ':' || v_key_mode
  );

  v_sql := '
    SELECT /* ' || v_sql_tag || ' */
           SUM(risk_score)
    FROM plan_instability_demo
    WHERE skew_key = :b1';

  FOR i IN 1 .. v_cycles LOOP
    IF v_key_mode = 'HOT' THEN
      v_key := 1;
    ELSIF v_key_mode = 'COLD' THEN
      v_key := 120000 + MOD(i, 40000) + 1;
    ELSIF MOD(i, 4) = 0 THEN
      v_key := 120000 + MOD(i, 40000) + 1;
    ELSE
      v_key := 1;
    END IF;

    EXECUTE IMMEDIATE v_sql INTO v_sum USING v_key;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE(
    'DOWNER_PI_Q01 tag=' || v_sql_tag ||
    ', optimizer_mode=' || v_optimizer_mode ||
    ', key_mode=' || v_key_mode ||
    ', cycles=' || v_cycles ||
    ', last_sum=' || NVL(TO_CHAR(v_sum), 'NULL')
  );
END;
/

GRANT SELECT ON plan_instability_demo TO graph_diag_user;

SELECT
  COUNT(*) AS row_count,
  SUM(CASE WHEN skew_key = 1 THEN 1 ELSE 0 END) AS hot_value_rows,
  COUNT(DISTINCT skew_key) AS distinct_skew_keys
FROM plan_instability_demo;

PROMPT Plan-instability scenario prepared. Run 23_run_plan_instability_workload.sql next.
