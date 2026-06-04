--------------------------------------------------------------------------------
-- 29_supernode_feature_mitigation_validation.sql
-- Out-of-band validation for R3 supernode / fan-out mitigation.
--
-- Run as DOWNER_DEMO after 18_setup_supernode_fanout.sql.
-- Do not run through the read-only MCP diagnostic channel.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON
SET LINESIZE 220
SET PAGESIZE 120

ALTER SESSION SET CURRENT_SCHEMA = DOWNER_DEMO;

BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE TABLE downer_ip_fanout_features (
      ip_id                    VARCHAR2(64) PRIMARY KEY,
      active_user_count        NUMBER NOT NULL,
      estimated_bank_paths     NUMBER NOT NULL,
      suspicious_bank_accounts NUMBER NOT NULL,
      risk_tier                VARCHAR2(16) NOT NULL,
      computed_at              TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
    )
  ]';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -955 THEN
      RAISE;
    END IF;
END;
/

CREATE OR REPLACE PROCEDURE refresh_downer_ip_fanout_feature (
  p_ip_id IN VARCHAR2 DEFAULT 'IP00000001'
) AS
BEGIN
  MERGE INTO downer_ip_fanout_features f
  USING (
    WITH anchor_users AS (
      SELECT DISTINCT src AS user_id
      FROM e_uses_ip
      WHERE dst = p_ip_id
        AND end_date IS NULL
    ),
    bank_paths AS (
      SELECT
        w.dst AS bank_account_id,
        COUNT(DISTINCT au.user_id) AS users_on_bank
      FROM anchor_users au
      JOIN e_withdrawal_bank_account w
        ON w.src = au.user_id
       AND w.end_date IS NULL
      GROUP BY w.dst
    )
    SELECT
      p_ip_id AS ip_id,
      (SELECT COUNT(*) FROM anchor_users) AS active_user_count,
      NVL(SUM(users_on_bank), 0) AS estimated_bank_paths,
      NVL(SUM(CASE WHEN users_on_bank >= 2 THEN 1 ELSE 0 END), 0) AS suspicious_bank_accounts,
      CASE
        WHEN (SELECT COUNT(*) FROM anchor_users) >= 10000 THEN 'SUPERHIGH'
        WHEN (SELECT COUNT(*) FROM anchor_users) >= 1000 THEN 'HIGH'
        ELSE 'NORMAL'
      END AS risk_tier
    FROM bank_paths
  ) s
  ON (f.ip_id = s.ip_id)
  WHEN MATCHED THEN UPDATE SET
    active_user_count = s.active_user_count,
    estimated_bank_paths = s.estimated_bank_paths,
    suspicious_bank_accounts = s.suspicious_bank_accounts,
    risk_tier = s.risk_tier,
    computed_at = SYSTIMESTAMP
  WHEN NOT MATCHED THEN INSERT (
    ip_id,
    active_user_count,
    estimated_bank_paths,
    suspicious_bank_accounts,
    risk_tier,
    computed_at
  ) VALUES (
    s.ip_id,
    s.active_user_count,
    s.estimated_bank_paths,
    s.suspicious_bank_accounts,
    s.risk_tier,
    SYSTIMESTAMP
  );

  COMMIT;
END;
/

BEGIN
  refresh_downer_ip_fanout_feature('IP00000001');
  DBMS_STATS.GATHER_TABLE_STATS(
    ownname => 'DOWNER_DEMO',
    tabname => 'DOWNER_IP_FANOUT_FEATURES',
    cascade => TRUE,
    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
    no_invalidate => FALSE
  );
END;
/

DELETE FROM plan_table
WHERE statement_id IN ('DOWNER_SN_Q01_ONLINE', 'DOWNER_SN_Q01_FEATURE');

EXPLAIN PLAN SET STATEMENT_ID = 'DOWNER_SN_Q01_ONLINE' FOR
SELECT /* DOWNER_SN_Q01_ONLINE */
       COUNT(*)
FROM (
  SELECT
    bank_account_id,
    COUNT(DISTINCT user_id) AS users_on_bank,
    MAX(ip_used_at_date) AS last_ip_seen
  FROM GRAPH_TABLE (downer_graph
    MATCH (ipn IS ip) <-[ei IS uses_ip]- (u IS user_account)
                       -[wb IS withdrawal_bank_account]-> (b IS bank_account)
    WHERE ipn.id = 'IP00000001'
      AND ei.end_date IS NULL
      AND wb.end_date IS NULL
    COLUMNS (
      ipn.id AS ip_id,
      u.id AS user_id,
      b.id AS bank_account_id,
      ei.used_at_date AS ip_used_at_date
    )
  )
  GROUP BY bank_account_id
  HAVING COUNT(DISTINCT user_id) >= 2
);

SELECT *
FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'DOWNER_SN_Q01_ONLINE', 'BASIC +PREDICATE +ALIAS'));

SELECT /* DOWNER_SN_Q01_BEFORE_ONLINE_RUN */
       COUNT(*) AS suspicious_bank_accounts
FROM (
  SELECT
    bank_account_id,
    COUNT(DISTINCT user_id) AS users_on_bank,
    MAX(ip_used_at_date) AS last_ip_seen
  FROM GRAPH_TABLE (downer_graph
    MATCH (ipn IS ip) <-[ei IS uses_ip]- (u IS user_account)
                       -[wb IS withdrawal_bank_account]-> (b IS bank_account)
    WHERE ipn.id = 'IP00000001'
      AND ei.end_date IS NULL
      AND wb.end_date IS NULL
    COLUMNS (
      ipn.id AS ip_id,
      u.id AS user_id,
      b.id AS bank_account_id,
      ei.used_at_date AS ip_used_at_date
    )
  )
  GROUP BY bank_account_id
  HAVING COUNT(DISTINCT user_id) >= 2
);

EXPLAIN PLAN SET STATEMENT_ID = 'DOWNER_SN_Q01_FEATURE' FOR
SELECT /* DOWNER_SN_Q01_FEATURE */
       suspicious_bank_accounts
FROM downer_ip_fanout_features
WHERE ip_id = 'IP00000001'
  AND risk_tier IN ('HIGH', 'SUPERHIGH');

SELECT *
FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'DOWNER_SN_Q01_FEATURE', 'BASIC +PREDICATE +ALIAS'));

SELECT /* DOWNER_SN_Q01_AFTER_FEATURE_RUN */
       suspicious_bank_accounts
FROM downer_ip_fanout_features
WHERE ip_id = 'IP00000001'
  AND risk_tier IN ('HIGH', 'SUPERHIGH');

SELECT
  CASE
    WHEN sql_text LIKE '%DOWNER_SN_Q01_AFTER_FEATURE_RUN%' THEN 'FEATURE_LOOKUP'
    WHEN sql_text LIKE '%DOWNER_SN_Q01_BEFORE_ONLINE_RUN%' THEN 'ONLINE_GRAPH_TRAVERSAL'
  END AS run_type,
  sql_id,
  plan_hash_value,
  executions,
  ROUND(elapsed_time / NULLIF(executions, 0) / 1e3, 3) AS avg_elapsed_ms,
  ROUND(buffer_gets / NULLIF(executions, 0)) AS avg_buffer_gets,
  rows_processed,
  last_active_time
FROM v$sql
WHERE (sql_text LIKE '%DOWNER_SN_Q01_BEFORE_ONLINE_RUN%' OR sql_text LIKE '%DOWNER_SN_Q01_AFTER_FEATURE_RUN%')
  AND sql_text NOT LIKE '%V$SQL%'
ORDER BY run_type, last_active_time DESC;

PROMPT Supernode mitigation proof complete. Use the feature lookup for high-degree identifiers and keep the online traversal for normal-degree identifiers.
