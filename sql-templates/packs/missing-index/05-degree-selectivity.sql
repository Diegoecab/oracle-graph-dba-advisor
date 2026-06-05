WITH filtered_edges AS (
  SELECT
    __SOURCE_FK__ AS source_key,
    __DESTINATION_FK__ AS destination_key
  FROM __GRAPH_OWNER__.__EDGE_TABLE__
  WHERE __EDGE_FILTER_PREDICATE__
),
table_summary AS (
  SELECT COUNT(*) AS total_rows
  FROM __GRAPH_OWNER__.__EDGE_TABLE__
),
filtered_summary AS (
  SELECT
    COUNT(*) AS filtered_rows,
    COUNT(DISTINCT source_key) AS distinct_source_keys,
    COUNT(DISTINCT destination_key) AS distinct_destination_keys
  FROM filtered_edges
),
source_degree AS (
  SELECT source_key, COUNT(*) AS degree_count
  FROM filtered_edges
  GROUP BY source_key
),
destination_degree AS (
  SELECT destination_key, COUNT(*) AS degree_count
  FROM filtered_edges
  GROUP BY destination_key
),
top_source AS (
  SELECT source_key, degree_count
  FROM source_degree
  ORDER BY degree_count DESC, TO_CHAR(source_key)
  FETCH FIRST 1 ROW ONLY
),
top_destination AS (
  SELECT destination_key, degree_count
  FROM destination_degree
  ORDER BY degree_count DESC, TO_CHAR(destination_key)
  FETCH FIRST 1 ROW ONLY
)
SELECT
  'TABLE_ROWS' AS metric_name,
  TO_CHAR(ts.total_rows) AS metric_value,
  'Rows in target edge table before predicate filtering' AS evidence
FROM table_summary ts
UNION ALL
SELECT
  'FILTERED_EDGE_ROWS',
  TO_CHAR(fs.filtered_rows),
  'Rows matching the traversal predicate used for selectivity evidence'
FROM filtered_summary fs
UNION ALL
SELECT
  'SOURCE_EQUALITY_SELECTIVITY_PCT',
  TO_CHAR(ROUND(100 / NULLIF(fs.distinct_source_keys, 0), 6)),
  'Expected selectivity for one source-side anchor on __SOURCE_FK__'
FROM filtered_summary fs
UNION ALL
SELECT
  'DESTINATION_EQUALITY_SELECTIVITY_PCT',
  TO_CHAR(ROUND(100 / NULLIF(fs.distinct_destination_keys, 0), 6)),
  'Expected selectivity for one destination-side anchor on __DESTINATION_FK__'
FROM filtered_summary fs
UNION ALL
SELECT
  'MAX_SOURCE_DEGREE',
  TO_CHAR(MAX(degree_count)),
  'Largest filtered fan-out by __SOURCE_FK__'
FROM source_degree
UNION ALL
SELECT
  'MAX_DESTINATION_DEGREE',
  TO_CHAR(MAX(degree_count)),
  'Largest filtered fan-in by __DESTINATION_FK__'
FROM destination_degree
UNION ALL
SELECT
  'TOP_SOURCE_KEY',
  TO_CHAR(source_key),
  'Representative source-side bind value for validation'
FROM top_source
UNION ALL
SELECT
  'TOP_DESTINATION_KEY',
  TO_CHAR(destination_key),
  'Representative destination-side bind value for validation'
FROM top_destination
