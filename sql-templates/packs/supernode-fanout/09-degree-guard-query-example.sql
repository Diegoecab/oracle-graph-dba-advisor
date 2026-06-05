SELECT
  'AS_IS_ONLINE_TRAVERSAL' AS example_name,
  'SELECT COUNT(*) AS candidate_paths
FROM __GRAPH_OWNER__.__EDGE_TABLE__ first_hop
JOIN __GRAPH_OWNER__.__SECOND_EDGE_TABLE__ second_hop
  ON second_hop.src = first_hop.src
WHERE first_hop.dst = ''__ANCHOR_ID__''
  AND first_hop.end_date IS NULL
  AND second_hop.end_date IS NULL' AS example_sql,
  'Current online shape: expand every user connected to the high-degree identifier, then continue the traversal' AS explanation
FROM dual
UNION ALL
SELECT
  'TO_BE_DEGREE_GUARD',
  'WITH candidate_anchor AS (
  SELECT degree.identifier_id
  FROM __GRAPH_OWNER__.__DEGREE_TABLE__ degree
  WHERE degree.identifier_id = ''__ANCHOR_ID__''
    AND degree.active_degree <= __DEGREE_THRESHOLD__
)
SELECT COUNT(*) AS candidate_paths
FROM candidate_anchor anchor
JOIN __GRAPH_OWNER__.__EDGE_TABLE__ first_hop
  ON first_hop.dst = anchor.identifier_id
JOIN __GRAPH_OWNER__.__SECOND_EDGE_TABLE__ second_hop
  ON second_hop.src = first_hop.src
WHERE first_hop.end_date IS NULL
  AND second_hop.end_date IS NULL' AS example_sql,
  'Online traversal path: run only for normal-degree identifiers. High-degree anchors return no online expansion and must be handled by a separate route' AS explanation
FROM dual
UNION ALL
SELECT
  'TO_BE_HIGH_DEGREE_FEATURE_LOOKUP',
  'SELECT feature.identifier_id,
       feature.active_degree,
       feature.precomputed_risk_score,
       feature.last_refresh_time
FROM __GRAPH_OWNER__.__HIGH_DEGREE_FEATURE_TABLE__ feature
WHERE feature.identifier_id = ''__ANCHOR_ID__''
  AND feature.active_degree > __DEGREE_THRESHOLD__' AS example_sql,
  'Separate hot-anchor path: use a bounded aggregate or feature lookup instead of expanding every connected user online' AS explanation
FROM dual
