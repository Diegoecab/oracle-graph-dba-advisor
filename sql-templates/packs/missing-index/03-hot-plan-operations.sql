WITH selected_child AS (
  SELECT MAX(child_number) AS child_number
  FROM v$sql_plan
  WHERE sql_id = '__SQL_ID__'
),
plan_ops AS (
  SELECT
    p.sql_id,
    p.child_number,
    p.id,
    p.parent_id,
    p.depth,
    p.operation,
    p.options,
    p.object_owner,
    p.object_name,
    p.cardinality,
    p.cost,
    p.access_predicates,
    p.filter_predicates,
    NVL(ps.last_output_rows, 0) AS actual_rows,
    NVL(ps.last_cr_buffer_gets, 0) + NVL(ps.last_cu_buffer_gets, 0) AS buffer_gets,
    NVL(ps.last_disk_reads, 0) AS disk_reads,
    NVL(ps.last_elapsed_time, 0) AS elapsed_us
  FROM v$sql_plan p
  JOIN selected_child sc
    ON sc.child_number = p.child_number
  LEFT JOIN v$sql_plan_statistics_all ps
    ON ps.sql_id = p.sql_id
   AND ps.child_number = p.child_number
   AND ps.id = p.id
  WHERE p.sql_id = '__SQL_ID__'
)
SELECT
  sql_id,
  child_number,
  id AS step_id,
  parent_id,
  depth,
  operation,
  options,
  object_owner,
  object_name,
  cardinality AS estimated_rows,
  actual_rows,
  buffer_gets,
  disk_reads,
  elapsed_us,
  cost,
  access_predicates,
  filter_predicates,
  CASE
    WHEN operation = 'TABLE ACCESS' AND options = 'FULL' AND object_name = '__EDGE_TABLE__' THEN 'HIGH_IMPACT_FULL_SCAN_ON_TARGET_EDGE'
    WHEN operation = 'TABLE ACCESS' AND options = 'FULL' THEN 'FULL_SCAN'
    WHEN operation LIKE '%INDEX%' THEN 'INDEX_ACCESS'
    ELSE 'OTHER'
  END AS evidence_signal
FROM plan_ops
WHERE object_name IS NOT NULL
ORDER BY buffer_gets DESC, elapsed_us DESC, id
FETCH FIRST 30 ROWS ONLY
