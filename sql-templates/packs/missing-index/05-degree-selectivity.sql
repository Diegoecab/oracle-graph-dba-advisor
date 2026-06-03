WITH base AS (
  SELECT src, dst, end_date
  FROM __GRAPH_OWNER__.__EDGE_TABLE__
),
active_base AS (
  SELECT src, dst
  FROM base
  WHERE end_date IS NULL
),
src_degree AS (
  SELECT src, COUNT(*) AS degree_count
  FROM active_base
  GROUP BY src
),
dst_degree AS (
  SELECT dst, COUNT(*) AS degree_count
  FROM active_base
  GROUP BY dst
),
summary AS (
  SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN end_date IS NULL THEN 1 ELSE 0 END) AS active_rows,
    COUNT(DISTINCT src) AS distinct_src,
    COUNT(DISTINCT dst) AS distinct_dst
  FROM base
)
SELECT
  'TABLE_ROWS' AS metric_name,
  TO_CHAR(total_rows) AS metric_value,
  'Rows in target edge table' AS evidence
FROM summary
UNION ALL
SELECT
  'ACTIVE_EDGE_ROWS',
  TO_CHAR(active_rows),
  'Rows participating in current traversal predicate'
FROM summary
UNION ALL
SELECT
  'SRC_EQUALITY_SELECTIVITY_PCT',
  TO_CHAR(ROUND(100 / NULLIF(distinct_src, 0), 6)),
  'Expected selectivity for one anchored source user'
FROM summary
UNION ALL
SELECT
  'DST_EQUALITY_SELECTIVITY_PCT',
  TO_CHAR(ROUND(100 / NULLIF(distinct_dst, 0), 6)),
  'Expected selectivity for one shared device lookup'
FROM summary
UNION ALL
SELECT
  'MAX_ACTIVE_OUT_DEGREE',
  TO_CHAR(MAX(degree_count)),
  'Largest active edge fan-out by SRC'
FROM src_degree
UNION ALL
SELECT
  'MAX_ACTIVE_IN_DEGREE',
  TO_CHAR(MAX(degree_count)),
  'Largest active edge fan-in by DST'
FROM dst_degree
UNION ALL
SELECT
  'ANCHOR_ACTIVE_OUT_DEGREE',
  TO_CHAR(COUNT(*)),
  'Active device edges for U00000042'
FROM active_base
WHERE src = 'U00000042'
