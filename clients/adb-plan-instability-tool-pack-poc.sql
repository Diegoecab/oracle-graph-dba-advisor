--------------------------------------------------------------------------------
-- adb-plan-instability-tool-pack-poc.sql
--
-- Minimal Select AI Agent / Native MCP PoC for the plan-instability playbook.
--
-- Run as the technical schema owner (for example NEWFRAUD), not as ADMIN.
--
-- Required:
--   - CREATE PROCEDURE
--   - EXECUTE ON C##CLOUD$SERVICE.DBMS_CLOUD_AI_AGENT
--   - direct SELECT grants on the V$ views used below
--
-- What this script does:
--   1. Creates three read-only PL/SQL functions that return JSON
--   2. Registers them as MCP-callable tools with DBMS_CLOUD_AI_AGENT.CREATE_TOOL
--
-- Usage:
--   @clients/adb-plan-instability-tool-pack-poc.sql
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE OFF
SET ECHO ON
SET FEEDBACK ON
SET HEADING ON
SET SERVEROUTPUT ON

PROMPT
PROMPT Creating plan-instability tool-pack PoC functions ...
PROMPT

CREATE OR REPLACE FUNCTION ga_plan_instability_summary_fn(
    sql_text_filter IN VARCHAR2 DEFAULT NULL,
    limit_rows      IN NUMBER   DEFAULT 20
) RETURN CLOB
AS
    v_json CLOB;
BEGIN
    SELECT NVL(
             JSON_ARRAYAGG(
               JSON_OBJECT(
                 'SQL_ID' VALUE sql_id,
                 'CHILD_CURSOR_COUNT' VALUE child_cursor_count,
                 'DISTINCT_PLAN_HASHES' VALUE distinct_plan_hashes,
                 'TOTAL_EXECUTIONS' VALUE total_executions,
                 'TOTAL_INVALIDATIONS' VALUE total_invalidations,
                 'TOTAL_PARSE_CALLS' VALUE total_parse_calls,
                 'BIND_SENSITIVE' VALUE bind_sensitive,
                 'BIND_AWARE' VALUE bind_aware,
                 'HAS_NONSHAREABLE_CHILD' VALUE has_nonshareable_child,
                 'TOTAL_ELAPSED_SEC' VALUE total_elapsed_sec,
                 'FIRST_SEEN_CHILD_TIME' VALUE first_seen_child_time,
                 'LAST_SEEN_CHILD_TIME' VALUE last_seen_child_time,
                 'INSTABILITY_SIGNAL' VALUE instability_signal,
                 'SQL_PREVIEW' VALUE sql_preview
                 RETURNING CLOB
               )
               RETURNING CLOB
             ),
             '[]'
           )
    INTO v_json
    FROM (
        SELECT *
        FROM (
            WITH candidate_sql AS (
                SELECT
                    s.sql_id,
                    s.child_number,
                    s.plan_hash_value,
                    s.executions,
                    s.elapsed_time,
                    s.invalidations,
                    s.parse_calls,
                    s.is_bind_sensitive,
                    s.is_bind_aware,
                    s.is_shareable,
                    TO_CHAR(s.last_active_time, 'YYYY-MM-DD"T"HH24:MI:SS') AS last_active_time,
                    SUBSTR(REPLACE(REPLACE(s.sql_text, CHR(10), ' '), CHR(13), ' '), 1, 180) AS sql_preview
                FROM v$sql s
                WHERE (sql_text_filter IS NULL OR UPPER(s.sql_text) LIKE '%' || UPPER(sql_text_filter) || '%')
                  AND NOT REGEXP_LIKE(s.sql_text, '^[[:space:]]*(BEGIN|DECLARE|CALL)([[:space:]]|$)', 'in')
                  AND UPPER(s.sql_text) NOT LIKE '/* SQL ANALYZE%'
                  AND UPPER(s.sql_text) NOT LIKE '%DBMS_CLOUD_AI_AGENT%'
                  AND UPPER(s.sql_text) NOT LIKE '%V$SQL%'
                  AND UPPER(s.sql_text) NOT LIKE '%EXPLAIN PLAN%'
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
                ROUND(SUM(elapsed_time) / 1e6, 3) AS total_elapsed_sec,
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
                SUM(elapsed_time) DESC
        )
        WHERE ROWNUM <= LEAST(GREATEST(NVL(limit_rows, 20), 1), 100)
    );

    RETURN v_json;
END;
/

CREATE OR REPLACE FUNCTION ga_sql_child_detail_fn(
    target_sql_id IN VARCHAR2
) RETURN CLOB
AS
    v_json CLOB;
BEGIN
    SELECT NVL(
             JSON_ARRAYAGG(
               JSON_OBJECT(
                 'SQL_ID' VALUE sql_id,
                 'CHILD_NUMBER' VALUE child_number,
                 'PLAN_HASH_VALUE' VALUE plan_hash_value,
                 'EXECUTIONS' VALUE executions,
                 'TOTAL_ELAPSED_SEC' VALUE total_elapsed_sec,
                 'INVALIDATIONS' VALUE invalidations,
                 'PARSE_CALLS' VALUE parse_calls,
                 'LOADS' VALUE loads,
                 'OPTIMIZER_COST' VALUE optimizer_cost,
                 'IS_BIND_SENSITIVE' VALUE is_bind_sensitive,
                 'IS_BIND_AWARE' VALUE is_bind_aware,
                 'IS_SHAREABLE' VALUE is_shareable,
                 'LAST_ACTIVE_TIME' VALUE last_active_time,
                 'SQL_PREVIEW' VALUE sql_preview
                 RETURNING CLOB
               )
               RETURNING CLOB
             ),
             '[]'
           )
    INTO v_json
    FROM (
        SELECT
            sql_id,
            child_number,
            plan_hash_value,
            executions,
            ROUND(elapsed_time / 1e6, 3) AS total_elapsed_sec,
            invalidations,
            parse_calls,
            loads,
            optimizer_cost,
            is_bind_sensitive,
            is_bind_aware,
            is_shareable,
            TO_CHAR(last_active_time, 'YYYY-MM-DD"T"HH24:MI:SS') AS last_active_time,
            SUBSTR(REPLACE(REPLACE(sql_text, CHR(10), ' '), CHR(13), ' '), 1, 180) AS sql_preview
        FROM v$sql
        WHERE sql_id = target_sql_id
        ORDER BY child_number
    );

    RETURN v_json;
END;
/

CREATE OR REPLACE FUNCTION ga_sql_plan_evidence_fn(
    target_sql_id IN VARCHAR2
) RETURN CLOB
AS
    v_json CLOB;
BEGIN
    SELECT JSON_OBJECT(
             'TARGET_SQL_ID' VALUE target_sql_id,
             'SHARED_CURSOR_REASONS' VALUE NVL(
               (
                 SELECT JSON_ARRAYAGG(
                          JSON_OBJECT(
                            'CHILD_NUMBER' VALUE child_number,
                            'OPTIMIZER_MISMATCH' VALUE optimizer_mismatch,
                            'STATS_ROW_MISMATCH' VALUE stats_row_mismatch,
                            'USER_BIND_PEEK_MISMATCH' VALUE user_bind_peek_mismatch,
                            'BIND_UACS_DIFF' VALUE bind_uacs_diff,
                            'USE_FEEDBACK_STATS' VALUE use_feedback_stats,
                            'LITERAL_MISMATCH' VALUE literal_mismatch,
                            'FORCE_HARD_PARSE' VALUE force_hard_parse,
                            'REASON_PREVIEW' VALUE DBMS_LOB.SUBSTR(reason, 400, 1)
                            RETURNING CLOB
                          )
                          RETURNING CLOB
                        )
                 FROM v$sql_shared_cursor
                 WHERE sql_id = target_sql_id
               ),
               '[]'
             ) FORMAT JSON,
             'PLAN_HASH_SUMMARY' VALUE NVL(
               (
                 SELECT JSON_ARRAYAGG(
                          JSON_OBJECT(
                            'SQL_ID' VALUE sql_id,
                            'PLAN_HASH_VALUE' VALUE plan_hash_value,
                            'VERSION_COUNT' VALUE version_count,
                            'OPEN_VERSIONS' VALUE open_versions,
                            'USERS_OPENING' VALUE users_opening,
                            'USERS_EXECUTING' VALUE users_executing,
                            'EXECUTIONS' VALUE executions,
                            'INVALIDATIONS' VALUE invalidations,
                            'PARSE_CALLS' VALUE parse_calls,
                            'LOADS' VALUE loads,
                            'TOTAL_ELAPSED_SEC' VALUE total_elapsed_sec,
                            'OPTIMIZER_COST' VALUE optimizer_cost,
                            'LAST_ACTIVE_TIME' VALUE last_active_time
                            RETURNING CLOB
                          )
                          RETURNING CLOB
                        )
                 FROM (
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
                         optimizer_cost,
                         TO_CHAR(last_active_time, 'YYYY-MM-DD"T"HH24:MI:SS') AS last_active_time
                     FROM v$sqlarea_plan_hash
                     WHERE sql_id = target_sql_id
                     ORDER BY last_active_time DESC, plan_hash_value
                 )
               ),
               '[]'
             ) FORMAT JSON
             RETURNING CLOB
           )
    INTO v_json
    FROM dual;

    RETURN v_json;
END;
/

PROMPT
PROMPT Registering MCP tools ...
PROMPT

BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name => 'GA_PLAN_INSTABILITY_SUMMARY', force => TRUE);
    DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name => 'GA_SQL_CHILD_DETAIL', force => TRUE);
    DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name => 'GA_SQL_PLAN_EVIDENCE', force => TRUE);
END;
/

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name  => 'GA_PLAN_INSTABILITY_SUMMARY',
        attributes => q'!{
          "instruction": "Summarize candidate SQL statements with plan instability, child cursor churn, invalidations, or plan-hash changes across the database. Use this first for recurring SQL performance regressions. Optionally filter by a SQL text fragment such as PLAN_INSTABILITY_Q03.",
          "function": "GA_PLAN_INSTABILITY_SUMMARY_FN",
          "tool_inputs": [
            {"name": "sql_text_filter", "description": "Optional case-insensitive SQL text fragment to narrow the search."},
            {"name": "limit_rows", "description": "Optional maximum rows to return. Default 20, max 100."}
          ]
        }!'
    );
END;
/

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name  => 'GA_SQL_CHILD_DETAIL',
        attributes => q'!{
          "instruction": "Return child cursor detail for one SQL_ID, including plan hash, executions, invalidations, parse calls, optimizer cost, and shareability.",
          "function": "GA_SQL_CHILD_DETAIL_FN",
          "tool_inputs": [
            {"name": "target_sql_id", "description": "The SQL_ID to inspect."}
          ]
        }!'
    );
END;
/

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name  => 'GA_SQL_PLAN_EVIDENCE',
        attributes => q'!{
          "instruction": "Return deeper evidence for one SQL_ID, including V$SQL_SHARED_CURSOR reasons and V$SQLAREA_PLAN_HASH history.",
          "function": "GA_SQL_PLAN_EVIDENCE_FN",
          "tool_inputs": [
            {"name": "target_sql_id", "description": "The SQL_ID to inspect."}
          ]
        }!'
    );
END;
/

PROMPT
PROMPT Plan-instability tool-pack PoC installed.
PROMPT Tools:
PROMPT   GA_PLAN_INSTABILITY_SUMMARY
PROMPT   GA_SQL_CHILD_DETAIL
PROMPT   GA_SQL_PLAN_EVIDENCE
PROMPT
