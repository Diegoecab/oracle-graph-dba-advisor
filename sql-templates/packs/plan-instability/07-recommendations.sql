SELECT
  1 AS recommendation_order,
  'CONFIRM_PLAN_DRIFT' AS recommendation_type,
  'Confirm that SQL_ID __SQL_ID__ has multiple child cursors, multiple plan hashes, or material elapsed-time deviation before proposing any optimizer stabilization change.' AS recommendation_text,
  'Use 00-workload-instability-candidates.sql or 01-instability-summary.sql, then 03-child-detail.sql, 05-plan-hash.sql, and 06-elapsed-deviation.sql for evidence.' AS validation_text,
  'No rollback required for this diagnostic step.' AS rollback_text
FROM dual
UNION ALL
SELECT
  2,
  'STABILIZE_INPUTS_FIRST',
  'Review bind usage, predicate selectivity, statistics freshness, and object metadata before using a plan-control mechanism. The preferred first action is to remove avoidable causes of child cursor churn or unstable selectivity.',
  'Use shared cursor evidence and child-level metrics to identify bind mismatch, invalidations, or large selectivity spread.',
  'Revert application bind/query changes through normal release control if validation shows no improvement.'
FROM dual
UNION ALL
SELECT
  3,
  'DBA_PLAN_CONTROL_REVIEW',
  'If the same logical SQL has one clearly better plan and the workload is business critical, ask the DBA to review SQL Plan Baseline or SQL Profile options in an approved validation environment.',
  'Compare child plan elapsed time, CPU time, buffer gets, and plan hash stability before and after the DBA validation.',
  'Rollback through the DBA-approved plan-control mechanism, such as disabling or dropping the baseline/profile.'
FROM dual
UNION ALL
SELECT
  4,
  'OBSERVE_AFTER_STABILIZATION',
  'After stabilization, observe the same SQL_ID or normalized SQL text over a fresh workload window and verify child cursor count, plan hash count, and elapsed-time spread are reduced.',
  'Rerun the pack over the fresh window and compare the diagnostic coverage table.',
  'Return to observe-only if the workload no longer shows visible plan instability evidence.'
FROM dual
