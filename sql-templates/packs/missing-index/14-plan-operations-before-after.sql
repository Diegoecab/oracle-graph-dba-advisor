WITH targets AS (
  SELECT 'BEFORE' AS sample_label, '__BEFORE_SQL_ID__' AS sql_id, TO_NUMBER('__BEFORE_CHILD_NUMBER__') AS child_number FROM dual
  UNION ALL
  SELECT 'AFTER' AS sample_label, '__AFTER_SQL_ID__' AS sql_id, TO_NUMBER('__AFTER_CHILD_NUMBER__') AS child_number FROM dual
),
plan_rows AS (
  SELECT
    t.sample_label,
    p.sql_id,
    p.child_number,
    p.plan_hash_value,
    p.id,
    p.parent_id,
    p.depth,
    LPAD(' ', p.depth) || p.operation || CASE WHEN p.options IS NOT NULL THEN ' ' || p.options ELSE '' END AS operation_text,
    p.object_owner,
    p.object_name,
    p.cardinality,
    p.cost,
    NVL(ps.last_starts, 0) AS last_starts,
    NVL(ps.last_output_rows, 0) AS last_output_rows,
    NVL(ps.last_cr_buffer_gets, 0) + NVL(ps.last_cu_buffer_gets, 0) AS last_buffer_gets,
    NVL(ps.last_elapsed_time, 0) AS last_elapsed_us,
    p.access_predicates,
    p.filter_predicates
  FROM targets t
  JOIN v$sql_plan p
    ON p.sql_id = t.sql_id
   AND p.child_number = t.child_number
  LEFT JOIN v$sql_plan_statistics_all ps
    ON ps.sql_id = p.sql_id
   AND ps.child_number = p.child_number
   AND ps.id = p.id
)
SELECT
  sample_label,
  sql_id,
  child_number,
  plan_hash_value,
  id,
  parent_id,
  operation_text,
  object_owner,
  object_name,
  cardinality,
  cost,
  last_starts,
  last_output_rows,
  last_buffer_gets,
  last_elapsed_us,
  access_predicates,
  filter_predicates
FROM plan_rows
ORDER BY CASE sample_label WHEN 'BEFORE' THEN 1 ELSE 2 END, id
