--------------------------------------------------------------------------------
-- 04_workload_queries.sql
-- Tagged Mini-DOWNER graph workload examples.
--
-- Run as DOWNER_DEMO.
--------------------------------------------------------------------------------

SET TIMING ON
SET LINESIZE 220
SET PAGESIZE 100

SELECT /* DOWNER_MI_Q01 */
  *
FROM GRAPH_TABLE (downer_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
  WHERE u1.id = 'U00000042'
    AND u1.id <> u2.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (
    u1.id AS anchor_user_id,
    u2.id AS neighbor_user_id,
    d.id AS shared_device_id,
    d.device_type AS node_device_type,
    e2.device_type AS edge_device_type
  )
)
FETCH FIRST 100 ROWS ONLY;

SELECT /* DOWNER_SN_Q01 */
  COUNT(*) AS candidate_paths
FROM GRAPH_TABLE (downer_graph
  MATCH (d IS device) <-[ed IS uses_device]- (u IS user_account)
                      -[wb IS withdrawal_bank_account]-> (b IS bank_account)
  WHERE d.id = 'D00000001'
    AND ed.end_date IS NULL
    AND wb.end_date IS NULL
  COLUMNS (
    d.id AS device_id,
    u.id AS user_id,
    b.id AS bank_account_id,
    ed.device_type AS device_edge_type
  )
);
