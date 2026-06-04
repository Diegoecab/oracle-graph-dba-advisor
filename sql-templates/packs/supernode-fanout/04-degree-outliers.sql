WITH active_edges AS (
  SELECT src, dst
  FROM __GRAPH_OWNER__.__EDGE_TABLE__
  WHERE end_date IS NULL
),
degree_by_dst AS (
  SELECT
    dst,
    COUNT(*) AS active_in_degree
  FROM active_edges
  GROUP BY dst
),
degree_stats AS (
  SELECT
    COUNT(*) AS node_count,
    ROUND(AVG(active_in_degree), 2) AS avg_degree,
    MAX(active_in_degree) AS max_degree,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY active_in_degree) AS p50_degree,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY active_in_degree) AS p95_degree,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY active_in_degree) AS p99_degree
  FROM degree_by_dst
),
anchor_degree AS (
  SELECT
    dst,
    active_in_degree
  FROM degree_by_dst
  WHERE dst = '__ANCHOR_ID__'
)
SELECT
  'ANCHOR_ID' AS metric_name,
  '__ANCHOR_ID__' AS metric_value,
  'Vertex used as traversal anchor'
FROM dual
UNION ALL
SELECT
  'ANCHOR_ACTIVE_IN_DEGREE',
  TO_CHAR(active_in_degree),
  'Active users connected to the anchor vertex'
FROM anchor_degree
UNION ALL
SELECT
  'AVG_ACTIVE_IN_DEGREE',
  TO_CHAR(avg_degree),
  'Average active in-degree for this edge destination'
FROM degree_stats
UNION ALL
SELECT
  'P95_ACTIVE_IN_DEGREE',
  TO_CHAR(ROUND(p95_degree, 2)),
  'P95 active in-degree for this edge destination'
FROM degree_stats
UNION ALL
SELECT
  'P99_ACTIVE_IN_DEGREE',
  TO_CHAR(ROUND(p99_degree, 2)),
  'P99 active in-degree for this edge destination'
FROM degree_stats
UNION ALL
SELECT
  'MAX_ACTIVE_IN_DEGREE',
  TO_CHAR(max_degree),
  'Largest active in-degree for this edge destination'
FROM degree_stats
UNION ALL
SELECT
  'ANCHOR_TO_P95_RATIO',
  TO_CHAR(ROUND(a.active_in_degree / NULLIF(s.p95_degree, 0), 2)),
  'How extreme the anchor is compared with P95'
FROM anchor_degree a
CROSS JOIN degree_stats s
