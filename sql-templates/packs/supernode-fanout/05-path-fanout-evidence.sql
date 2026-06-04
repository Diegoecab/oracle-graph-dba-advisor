WITH anchor_users AS (
  SELECT DISTINCT src AS user_id
  FROM __GRAPH_OWNER__.__EDGE_TABLE__
  WHERE dst = '__ANCHOR_ID__'
    AND end_date IS NULL
),
bank_edges AS (
  SELECT
    w.src AS user_id,
    COUNT(*) AS active_bank_edges
  FROM __GRAPH_OWNER__.__SECOND_EDGE_TABLE__ w
  JOIN anchor_users au
    ON au.user_id = w.src
  WHERE w.end_date IS NULL
  GROUP BY w.src
),
summary AS (
  SELECT
    COUNT(*) AS users_reached_from_anchor,
    NVL(SUM(active_bank_edges), 0) AS estimated_anchor_user_bank_paths,
    ROUND(AVG(active_bank_edges), 2) AS avg_bank_edges_per_reached_user,
    MAX(active_bank_edges) AS max_bank_edges_per_reached_user
  FROM bank_edges
),
coverage AS (
  SELECT
    COUNT(*) AS users_without_bank_edge
  FROM anchor_users au
  WHERE NOT EXISTS (
    SELECT 1
    FROM __GRAPH_OWNER__.__SECOND_EDGE_TABLE__ w
    WHERE w.src = au.user_id
      AND w.end_date IS NULL
  )
)
SELECT
  'USERS_REACHED_FROM_ANCHOR' AS metric_name,
  TO_CHAR(COUNT(*)) AS metric_value,
  'First-hop users reached from the anchor vertex'
FROM anchor_users
UNION ALL
SELECT
  'ESTIMATED_ANCHOR_USER_BANK_PATHS',
  TO_CHAR(estimated_anchor_user_bank_paths),
  'Estimated result paths after expanding reached users to bank accounts'
FROM summary
UNION ALL
SELECT
  'AVG_BANK_EDGES_PER_REACHED_USER',
  TO_CHAR(avg_bank_edges_per_reached_user),
  'Average second-hop expansion for reached users'
FROM summary
UNION ALL
SELECT
  'MAX_BANK_EDGES_PER_REACHED_USER',
  TO_CHAR(max_bank_edges_per_reached_user),
  'Largest second-hop expansion for one reached user'
FROM summary
UNION ALL
SELECT
  'USERS_WITHOUT_BANK_EDGE',
  TO_CHAR(users_without_bank_edge),
  'Reached users that do not contribute second-hop bank paths'
FROM coverage
