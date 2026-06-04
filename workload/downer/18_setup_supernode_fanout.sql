--------------------------------------------------------------------------------
-- 18_setup_supernode_fanout.sql
-- Prepares the Mini-DOWNER supernode / fan-out scenario.
--
-- Run as DOWNER_DEMO. This is an out-of-band setup script, not a diagnostic
-- MCP script. It keeps the missing-index device case intact and adds
-- high-degree evidence around IP00000001 on the already-indexed E_USES_IP edge.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

DEFINE supernode_ip_id = IP00000001
DEFINE supernode_users = 8000
DEFINE bank_edges_per_user = 2

MERGE INTO e_uses_ip t
USING (
  SELECT
    'IPSN' || LPAD(LEVEL, 12, '0') AS id,
    'U' || LPAD(LEVEL, 8, '0') AS src,
    '&&supernode_ip_id' AS dst,
    TIMESTAMP '2026-06-03 00:00:00' - NUMTODSINTERVAL(MOD(LEVEL, 90), 'DAY') AS start_date,
    SYSTIMESTAMP AS last_updated,
    TIMESTAMP '2026-06-03 00:00:00' - NUMTODSINTERVAL(MOD(LEVEL, 30), 'DAY') AS used_at_date,
    CAST(NULL AS TIMESTAMP) AS end_date
  FROM dual
  CONNECT BY LEVEL <= &&supernode_users
) s
ON (t.id = s.id)
WHEN NOT MATCHED THEN INSERT (
  id,
  src,
  dst,
  start_date,
  last_updated,
  used_at_date,
  end_date
) VALUES (
  s.id,
  s.src,
  s.dst,
  s.start_date,
  s.last_updated,
  s.used_at_date,
  s.end_date
);

MERGE INTO e_withdrawal_bank_account t
USING (
  SELECT
    'SNWBA' || LPAD(u.user_num, 8, '0') || '_' || b.edge_num AS id,
    'U' || LPAD(u.user_num, 8, '0') AS src,
    'B' || LPAD(MOD(u.user_num + (b.edge_num * 997), 4000) + 1, 8, '0') AS dst,
    TIMESTAMP '2026-06-03 00:00:00' - NUMTODSINTERVAL(MOD(u.user_num, 120), 'DAY') AS start_date,
    SYSTIMESTAMP AS last_updated,
    CAST(NULL AS TIMESTAMP) AS end_date
  FROM (
    SELECT LEVEL AS user_num
    FROM dual
    CONNECT BY LEVEL <= &&supernode_users
  ) u
  CROSS JOIN (
    SELECT LEVEL AS edge_num
    FROM dual
    CONNECT BY LEVEL <= &&bank_edges_per_user
  ) b
) s
ON (t.id = s.id)
WHEN NOT MATCHED THEN INSERT (
  id,
  src,
  dst,
  start_date,
  last_updated,
  end_date
) VALUES (
  s.id,
  s.src,
  s.dst,
  s.start_date,
  s.last_updated,
  s.end_date
);

UPDATE n_ip
SET adjacent_edges_count = (
      SELECT COUNT(*)
      FROM e_uses_ip
      WHERE dst = '&&supernode_ip_id'
        AND end_date IS NULL
    ),
    last_updated = SYSTIMESTAMP
WHERE id = '&&supernode_ip_id';

COMMIT;

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(
    ownname => USER,
    tabname => 'E_USES_IP',
    cascade => TRUE,
    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
    no_invalidate => FALSE
  );

  DBMS_STATS.GATHER_TABLE_STATS(
    ownname => USER,
    tabname => 'E_WITHDRAWAL_BANK_ACCOUNT',
    cascade => TRUE,
    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
    no_invalidate => FALSE
  );

  DBMS_STATS.GATHER_TABLE_STATS(
    ownname => USER,
    tabname => 'N_IP',
    cascade => TRUE,
    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
    no_invalidate => FALSE
  );
END;
/

SELECT
  dst AS ip_id,
  COUNT(*) AS active_in_degree
FROM e_uses_ip
WHERE end_date IS NULL
GROUP BY dst
ORDER BY active_in_degree DESC
FETCH FIRST 10 ROWS ONLY;

PROMPT Supernode fan-out scenario prepared. Run 19_run_supernode_workload.sql or 20_start_dashboard_load_supernode.sql next.
