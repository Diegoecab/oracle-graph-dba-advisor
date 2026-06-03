--------------------------------------------------------------------------------
-- 06_lab_summary.sql
-- Mini-DOWNER lab validation.
--
-- Run as DOWNER_DEMO.
--------------------------------------------------------------------------------

SET LINESIZE 220
SET PAGESIZE 100

SELECT
  table_name,
  num_rows,
  blocks,
  last_analyzed
FROM user_tables
WHERE table_name IN (
  'N_USER',
  'N_DEVICE',
  'N_BANK_ACCOUNT',
  'N_CARD',
  'N_IP',
  'E_USES_DEVICE',
  'E_WITHDRAWAL_BANK_ACCOUNT',
  'E_USES_CARD',
  'E_USES_IP'
)
ORDER BY table_name;

SELECT
  index_name,
  table_name,
  visibility,
  status
FROM user_indexes
WHERE table_name LIKE 'E_%'
ORDER BY table_name, index_name;

WITH indexed_cols AS (
  SELECT table_name, column_name
  FROM user_ind_columns
  WHERE table_name = 'E_USES_DEVICE'
    AND column_position = 1
)
SELECT 'E_USES_DEVICE' AS table_name,
       c.column_name,
       CASE WHEN i.column_name IS NULL THEN 'MISSING LEADING INDEX' ELSE 'INDEXED' END AS index_status
FROM (
  SELECT 'SRC' AS column_name FROM dual
  UNION ALL
  SELECT 'DST' AS column_name FROM dual
) c
LEFT JOIN indexed_cols i
  ON i.column_name = c.column_name
ORDER BY c.column_name;

SELECT
  COUNT(*) AS e_uses_device_rows,
  COUNT(DISTINCT src) AS distinct_src,
  COUNT(DISTINCT dst) AS distinct_dst,
  SUM(CASE WHEN end_date IS NULL THEN 1 ELSE 0 END) AS active_edges
FROM e_uses_device;

SELECT
  src,
  COUNT(*) AS edge_count
FROM e_uses_device
WHERE src = 'U00000042'
GROUP BY src;
