--------------------------------------------------------------------------------
-- 08_setup_plan_instability_lab.sql
--
-- Creates a small relational lab inside NEWFRAUD to demonstrate:
--   - same SQL_ID with multiple child cursors
--   - different PLAN_HASH_VALUE values for one parent cursor
--   - reasons visible in V$SQL_SHARED_CURSOR
--
-- Assumes current schema = NEWFRAUD.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET SERVEROUTPUT ON
SET FEEDBACK ON
SET ECHO ON

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE PLAN_INSTABILITY_DEMO PURGE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -942 THEN
      RAISE;
    END IF;
END;
/

CREATE TABLE PLAN_INSTABILITY_DEMO (
  ID        NUMBER       NOT NULL,
  SKEW_KEY  NUMBER       NOT NULL,
  MEASURE   NUMBER       NOT NULL,
  PADDING   VARCHAR2(200),
  CONSTRAINT PLAN_INSTABILITY_DEMO_PK PRIMARY KEY (ID)
);

INSERT /*+ APPEND */ INTO PLAN_INSTABILITY_DEMO (ID, SKEW_KEY, MEASURE, PADDING)
SELECT
  LEVEL AS ID,
  CASE
    WHEN LEVEL <= 120000 THEN 1
    ELSE LEVEL
  END AS SKEW_KEY,
  MOD(LEVEL, 100) + 1 AS MEASURE,
  RPAD('x', 200, 'x') AS PADDING
FROM dual
CONNECT BY LEVEL <= 160000;

COMMIT;

CREATE INDEX IDX_PID_SKEW ON PLAN_INSTABILITY_DEMO (SKEW_KEY);

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(
    ownname    => USER,
    tabname    => 'PLAN_INSTABILITY_DEMO',
    cascade    => TRUE,
    method_opt => 'FOR COLUMNS SIZE 254 SKEW_KEY'
  );
END;
/

CREATE OR REPLACE PROCEDURE RUN_PLAN_INSTABILITY_LAB (
  P_CYCLES                    NUMBER   DEFAULT 20,
  P_OPTIMIZER_MODE            VARCHAR2 DEFAULT 'ALL_ROWS',
  P_OPTIMIZER_INDEX_COST_ADJ  NUMBER   DEFAULT NULL
) AS
  V_KEY NUMBER;
  V_ID  NUMBER;
BEGIN
  EXECUTE IMMEDIATE 'ALTER SESSION SET optimizer_mode = ''' || REPLACE(P_OPTIMIZER_MODE, '''', '') || '''';

  -- ADB allows optimizer_mode in the lab session, but more invasive
  -- optimizer knobs such as optimizer_index_cost_adj may be blocked.
  IF P_OPTIMIZER_INDEX_COST_ADJ IS NOT NULL THEN
    EXECUTE IMMEDIATE 'ALTER SESSION SET optimizer_index_cost_adj = ' || TO_CHAR(P_OPTIMIZER_INDEX_COST_ADJ);
  END IF;

  FOR I IN 1 .. P_CYCLES LOOP
    IF MOD(I, 2) = 1 THEN
      V_KEY := 1;            -- hot value
    ELSE
      V_KEY := 150000 + I;   -- cold value
    END IF;

    EXECUTE IMMEDIATE q'[
      SELECT /* PLAN_INSTABILITY_Q03 */
             id
      FROM plan_instability_demo
      WHERE skew_key = :b1
      ORDER BY id
      FETCH FIRST 1 ROW ONLY
    ]'
      INTO V_ID
      USING V_KEY;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE(
    'Completed PLAN_INSTABILITY_Q03 with optimizer_mode=' || P_OPTIMIZER_MODE ||
    ', optimizer_index_cost_adj=' || P_OPTIMIZER_INDEX_COST_ADJ ||
    ', cycles=' || P_CYCLES
  );
END;
/

PROMPT
PROMPT PLAN_INSTABILITY_DEMO ready.
PROMPT Example:
PROMPT   EXEC RUN_PLAN_INSTABILITY_LAB(p_cycles => 24, p_optimizer_mode => 'FIRST_ROWS_1');
PROMPT   EXEC RUN_PLAN_INSTABILITY_LAB(p_cycles => 24, p_optimizer_mode => 'ALL_ROWS');
