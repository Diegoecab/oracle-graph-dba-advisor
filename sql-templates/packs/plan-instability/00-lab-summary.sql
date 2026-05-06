SELECT
  COUNT(*) AS row_count,
  SUM(CASE WHEN skew_key = 1 THEN 1 ELSE 0 END) AS hot_value_rows,
  MIN(skew_key) AS min_key,
  MAX(skew_key) AS max_key
FROM plan_instability_demo
