SELECT
  10 AS priority_order,
  'EVIDENCE' AS recommendation_area,
  'Use the candidate and primary SQL_ID templates with tag __SQL_TAG__ before making any physical design change' AS recommendation_text,
  '01-candidate-sql.sql' AS supporting_template
FROM dual
UNION ALL
SELECT
  20,
  'PLAN',
  'Use the hot plan operations template for SQL_ID __SQL_ID__ and confirm the target edge table is a high buffer or full access step',
  '03-hot-plan-operations.sql'
FROM dual
UNION ALL
SELECT
  30,
  'INDEX_GAP',
  'For graph __GRAPH_OWNER__.__GRAPH_NAME__, propose DBA validation of leading btree coverage for missing SOURCE_FK and DESTINATION_FK rows reported on __EDGE_TABLE__, then validate with invisible indexes before any approved visible change',
  '04-edge-fk-leading-index-gap.sql'
FROM dual
UNION ALL
SELECT
  40,
  'SELECTIVITY',
  'For __GRAPH_OWNER__.__EDGE_TABLE__, compare __SOURCE_FK__ and __DESTINATION_FK__ degree skew before choosing single-column or composite leading key order',
  '05-degree-selectivity.sql'
FROM dual
UNION ALL
SELECT
  50,
  'VALIDATION',
  'Before any visible change, provide an exact DBA runbook with CURRENT_SCHEMA, CREATE INDEX INVISIBLE, optimizer_use_invisible_indexes TRUE, target SQL, V$SQL elapsed and buffer comparison, ALTER INDEX visible commands, and every DROP INDEX rollback command',
  '01-candidate-sql.sql'
FROM dual
UNION ALL
SELECT
  60,
  'DML_OVERHEAD',
  'Before proposing permanent indexes, run the DML overhead evidence template for __GRAPH_OWNER__.__EDGE_TABLE__ and report inserts per hour, visible INSERT SQL, current index count, proposed index count, and whether write overhead requires DBA review',
  '07-dml-overhead-evidence.sql'
FROM dual
ORDER BY priority_order
