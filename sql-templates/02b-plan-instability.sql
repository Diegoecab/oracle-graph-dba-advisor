-- ============================================================
-- PLAN INSTABILITY TEMPLATES — Child cursors / plan churn
-- ============================================================
-- Analyst-facing template catalog.
-- Runtime-ready query pack used by the demo/skill lives under:
--   sql-templates/packs/plan-instability/
-- ============================================================
-- Use these when the symptom is:
--   - same SQL text, but performance changes over time
--   - multiple child cursors for the same SQL_ID
--   - different PLAN_HASH_VALUE values for one parent cursor
--   - repeated invalidations / reparses
--   - adaptive cursor sharing / bind-peeking side effects
--
-- Default scope:
--   - graph workload visible in the current schema
--   - lab/demo statements tagged with PLAN_INSTABILITY_Q%
--
-- Optional advanced checks:
--   - V$SQL_SHARED_CURSOR
--   - V$SQLAREA_PLAN_HASH
--   - DBA_SQL_PLAN_BASELINES (if granted)
-- ============================================================


-- ┌──────────────────────────────────────────────────────────┐
-- │ INSTABILITY-01: Summary by SQL_ID                        │
-- └──────────────────────────────────────────────────────────┘
-- Flags the strongest candidates for plan churn.

WITH graph_tables AS (
    SELECT DISTINCT UPPER(object_name) AS table_name
    FROM user_pg_elements
),
candidate_sql AS (
    SELECT
        s.sql_id,
        s.child_number,
        s.plan_hash_value,
        s.executions,
        s.elapsed_time,
        s.buffer_gets,
        s.invalidations,
        s.parse_calls,
        s.loads,
        s.is_bind_sensitive,
        s.is_bind_aware,
        s.is_shareable,
        s.last_active_time,
        SUBSTR(REPLACE(REPLACE(s.sql_text, CHR(10), ' '), CHR(13), ' '), 1, 150) AS sql_preview
    FROM v$sql s
    WHERE s.parsing_schema_name = SYS_CONTEXT('USERENV','CURRENT_SCHEMA')
      AND (
          UPPER(s.sql_text) LIKE '%PLAN_INSTABILITY_Q%'
          OR UPPER(s.sql_text) LIKE '%GRAPH_TABLE%'
          OR UPPER(s.sql_text) LIKE '%MATCH%(%IS%'
          OR EXISTS (
              SELECT 1
              FROM v$sql_plan p
              WHERE p.sql_id = s.sql_id
                AND p.child_number = s.child_number
                AND UPPER(p.object_name) IN (SELECT table_name FROM graph_tables)
          )
      )
      AND s.sql_text NOT LIKE '%v$sql%'
      AND s.sql_text NOT LIKE '%EXPLAIN PLAN%'
)
SELECT
    sql_id,
    COUNT(*) AS child_cursor_count,
    COUNT(DISTINCT plan_hash_value) AS distinct_plan_hashes,
    SUM(executions) AS total_executions,
    SUM(invalidations) AS total_invalidations,
    SUM(parse_calls) AS total_parse_calls,
    MAX(CASE WHEN is_bind_sensitive = 'Y' THEN 'Y' ELSE 'N' END) AS bind_sensitive,
    MAX(CASE WHEN is_bind_aware = 'Y' THEN 'Y' ELSE 'N' END) AS bind_aware,
    MAX(CASE WHEN is_shareable = 'N' THEN 'Y' ELSE 'N' END) AS has_nonshareable_child,
    ROUND(SUM(elapsed_time) / 1e6, 2) AS total_elapsed_sec,
    ROUND(SUM(buffer_gets) / NULLIF(SUM(executions), 0)) AS avg_buffer_gets,
    MIN(last_active_time) AS first_seen_child_time,
    MAX(last_active_time) AS last_seen_child_time,
    CASE
        WHEN COUNT(DISTINCT plan_hash_value) > 1 THEN 'PLAN_HASH_CHANGED'
        WHEN COUNT(*) > 1 AND SUM(invalidations) > 0 THEN 'MULTI_CHILD_PLUS_INVALIDATION'
        WHEN COUNT(*) > 1 THEN 'MULTIPLE_CHILD_CURSORS'
        WHEN SUM(invalidations) > 0 THEN 'INVALIDATION_OBSERVED'
        ELSE 'NO_CLEAR_INSTABILITY_SIGNAL'
    END AS instability_signal,
    MIN(sql_preview) AS sql_preview
FROM candidate_sql
GROUP BY sql_id
HAVING COUNT(*) > 1
    OR COUNT(DISTINCT plan_hash_value) > 1
    OR SUM(invalidations) > 0
ORDER BY
    COUNT(DISTINCT plan_hash_value) DESC,
    COUNT(*) DESC,
    SUM(invalidations) DESC,
    SUM(elapsed_time) DESC;


-- ┌──────────────────────────────────────────────────────────┐
-- │ INSTABILITY-02: Child cursor detail for one SQL_ID       │
-- └──────────────────────────────────────────────────────────┘
-- Replace TARGET_SQL_ID with the SQL_ID from INSTABILITY-01.

SELECT
    sql_id,
    child_number,
    plan_hash_value,
    executions,
    ROUND(elapsed_time / 1e6, 3) AS total_elapsed_sec,
    ROUND(elapsed_time / NULLIF(executions,0) / 1e6, 4) AS avg_elapsed_sec,
    buffer_gets,
    invalidations,
    parse_calls,
    loads,
    optimizer_cost,
    is_bind_sensitive,
    is_bind_aware,
    is_shareable,
    last_active_time,
    SUBSTR(REPLACE(REPLACE(sql_text, CHR(10), ' '), CHR(13), ' '), 1, 180) AS sql_preview
FROM v$sql
WHERE sql_id = 'TARGET_SQL_ID'
ORDER BY child_number;


-- ┌──────────────────────────────────────────────────────────┐
-- │ INSTABILITY-03: Why cursors were not shared              │
-- └──────────────────────────────────────────────────────────┘
-- Requires access to V$SQL_SHARED_CURSOR.
-- Replace TARGET_SQL_ID with the SQL_ID from INSTABILITY-01.

SELECT
    child_number,
    optimizer_mismatch,
    stats_row_mismatch,
    user_bind_peek_mismatch,
    bind_uacs_diff,
    use_feedback_stats,
    literal_mismatch,
    force_hard_parse,
    DBMS_LOB.SUBSTR(reason, 500, 1) AS reason_preview
FROM v$sql_shared_cursor
WHERE sql_id = 'TARGET_SQL_ID'
ORDER BY child_number;


-- ┌──────────────────────────────────────────────────────────┐
-- │ INSTABILITY-04: Plan-hash history under one parent       │
-- └──────────────────────────────────────────────────────────┘
-- Requires access to V$SQLAREA_PLAN_HASH.
-- Replace TARGET_SQL_ID with the SQL_ID from INSTABILITY-01.

SELECT
    sql_id,
    plan_hash_value,
    version_count,
    open_versions,
    users_opening,
    users_executing,
    executions,
    invalidations,
    parse_calls,
    loads,
    ROUND(elapsed_time / 1e6, 3) AS total_elapsed_sec,
    ROUND(buffer_gets / NULLIF(executions,0)) AS avg_buffer_gets,
    optimizer_cost,
    last_active_time
FROM v$sqlarea_plan_hash
WHERE sql_id = 'TARGET_SQL_ID'
ORDER BY last_active_time DESC, plan_hash_value;


-- ┌──────────────────────────────────────────────────────────┐
-- │ INSTABILITY-05: Optional SQL Plan Baseline visibility    │
-- └──────────────────────────────────────────────────────────┘
-- Requires SELECT on DBA_SQL_PLAN_BASELINES.
-- Replace PLAN_TAG with a distinctive fragment of the SQL text,
-- for example: PLAN_INSTABILITY_Q03 or DEMO_FRAUD_Q05

SELECT
    sql_handle,
    plan_name,
    origin,
    enabled,
    accepted,
    fixed,
    reproduced,
    adaptive,
    last_verified
FROM dba_sql_plan_baselines
WHERE UPPER(sql_text) LIKE '%PLAN_TAG%'
ORDER BY sql_handle, plan_name;
