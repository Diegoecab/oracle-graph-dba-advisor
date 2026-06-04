SELECT
  1 AS recommendation_order,
  'CONFIRM_INDEX_COVERAGE_FIRST' AS recommendation_type,
  'Verify that the traversal edge has usable leading indexes for both directions before treating this as fan-out. If indexes are present and the SQL still processes high intermediate rows, the dominant issue is graph degree skew rather than a simple access-path gap.' AS recommendation_text,
  'Use catalog index metadata and the plan operations for the selected SQL_ID.' AS validation_text,
  'No rollback required for this diagnostic step.' AS rollback_text
FROM dual
UNION ALL
SELECT
  2,
  'ADD_DEGREE_AWARE_QUERY_GUARD',
  'Provide an AS-IS online traversal and a TO-BE degree-aware query example. The TO-BE should exclude or route very high-degree identifiers such as __ANCHOR_ID__ through a separate feature path instead of expanding every connected user online.',
  'Compare anchor active in-degree against P95/P99 and confirm the high-degree node dominates result expansion.',
  'Remove the predicate or threshold change if business recall is harmed.'
FROM dual
UNION ALL
SELECT
  3,
  'CONSTRAIN_TRAVERSAL_CONTEXT',
  'Constrain the traversal with time windows, identifier type, risk category, or stronger business predicates so the query does not expand every user connected to a shared identifier.',
  'Rerun the tagged SQL and compare rows processed, buffer gets, elapsed time, and candidate result quality.',
  'Revert the query predicate change through application release control.'
FROM dual
UNION ALL
SELECT
  4,
  'PRECOMPUTE_HIGH_DEGREE_FEATURES',
  'For recurring fraud scoring, provide DDL and query examples for a precomputed feature table keyed by the high-degree identifier, then use a direct lookup for hot anchors instead of the online graph traversal.',
  'Validate that online SQL elapsed time drops while the feature refresh job remains bounded.',
  'Disable the feature lookup, drop the feature table if it is validation-only, and return to the prior query path.'
FROM dual
UNION ALL
SELECT
  5,
  'REVIEW_IDENTIFIER_MODELING',
  'Investigate whether the high-degree identifier represents a real shared signal, recycled identifier, NAT/proxy infrastructure, bot infrastructure, or data-quality artifact. Model or segment it accordingly.',
  'Sample users and events attached to the high-degree identifier and verify whether it has operational meaning.',
  'No database rollback required. Model changes should follow the normal data governance process.'
FROM dual
