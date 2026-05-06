--------------------------------------------------------------------------------
-- adb-performance-diagnostic-tool-packs-poc.sql
--
-- Additional Select AI Agent / Native MCP diagnostic tool packs aligned with
-- common Oracle troubleshooting flows:
--   - Top degraded SQL
--   - ASH SQL hotspots
--   - Plan changes over time
--   - Database wait events
--
-- Run as the technical schema owner (for example NEWFRAUD), not as ADMIN.
--
-- Required:
--   - CREATE PROCEDURE
--   - EXECUTE ON C##CLOUD$SERVICE.DBMS_CLOUD_AI_AGENT
--   - direct SELECT grants on the V$ / DBA_HIST views used below
--
-- Usage:
--   @clients/adb-performance-diagnostic-tool-packs-poc.sql
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE OFF
SET ECHO ON
SET FEEDBACK ON
SET HEADING ON
SET SERVEROUTPUT ON

PROMPT
PROMPT Creating additional performance diagnostic tool-pack PoC functions ...
PROMPT

CREATE OR REPLACE FUNCTION ga_top_sql_summary_fn(
    sql_text_filter IN VARCHAR2 DEFAULT NULL,
    hours_back      IN NUMBER   DEFAULT 4,
    limit_rows      IN NUMBER   DEFAULT 20
) RETURN CLOB
AS
    v_json CLOB;
BEGIN
    SELECT NVL(
             JSON_ARRAYAGG(
               JSON_OBJECT(
                 'SQL_ID' VALUE sql_id,
                 'PLAN_HASH_VALUE' VALUE plan_hash_value,
                 'VERSION_COUNT' VALUE version_count,
                 'TOTAL_EXECUTIONS' VALUE total_executions,
                 'TOTAL_ELAPSED_SEC' VALUE total_elapsed_sec,
                 'TOTAL_CPU_SEC' VALUE total_cpu_sec,
                 'AVG_ELAPSED_MS' VALUE avg_elapsed_ms,
                 'TOTAL_BUFFER_GETS' VALUE total_buffer_gets,
                 'AVG_BUFFER_GETS' VALUE avg_buffer_gets,
                 'TOTAL_DISK_READS' VALUE total_disk_reads,
                 'PARSE_CALLS' VALUE parse_calls,
                 'INVALIDATIONS' VALUE invalidations,
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
        SELECT *
        FROM (
            SELECT
                sql_id,
                plan_hash_value,
                version_count,
                executions AS total_executions,
                ROUND(elapsed_time / 1e6, 3) AS total_elapsed_sec,
                ROUND(cpu_time / 1e6, 3) AS total_cpu_sec,
                ROUND(elapsed_time / NULLIF(executions, 0) / 1e3, 3) AS avg_elapsed_ms,
                buffer_gets AS total_buffer_gets,
                ROUND(buffer_gets / NULLIF(executions, 0)) AS avg_buffer_gets,
                disk_reads AS total_disk_reads,
                parse_calls,
                invalidations,
                TO_CHAR(last_active_time, 'YYYY-MM-DD"T"HH24:MI:SS') AS last_active_time,
                SUBSTR(REPLACE(REPLACE(sql_text, CHR(10), ' '), CHR(13), ' '), 1, 180) AS sql_preview
            FROM v$sqlstats
            WHERE last_active_time >= SYSDATE - (LEAST(GREATEST(NVL(hours_back, 4), 1), 168) / 24)
              AND (sql_text_filter IS NULL OR UPPER(sql_text) LIKE '%' || UPPER(sql_text_filter) || '%')
              AND NOT REGEXP_LIKE(sql_text, '^[[:space:]]*(BEGIN|DECLARE|CALL)([[:space:]]|$)', 'in')
              AND UPPER(sql_text) NOT LIKE '/* SQL ANALYZE%'
              AND UPPER(sql_text) NOT LIKE '%V$SQL%'
              AND UPPER(sql_text) NOT LIKE '%V$SQLAREA_PLAN_HASH%'
              AND UPPER(sql_text) NOT LIKE '%V$ACTIVE_SESSION_HISTORY%'
              AND UPPER(sql_text) NOT LIKE '%V$SYSTEM_EVENT%'
              AND UPPER(sql_text) NOT LIKE '%EXPLAIN PLAN%'
              AND NVL(executions, 0) > 0
            ORDER BY
                elapsed_time DESC,
                cpu_time DESC,
                buffer_gets DESC
        )
        WHERE ROWNUM <= LEAST(GREATEST(NVL(limit_rows, 20), 1), 100)
    );

    RETURN v_json;
END;
/

CREATE OR REPLACE FUNCTION ga_top_sql_detail_fn(
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
                 'AVG_ELAPSED_MS' VALUE avg_elapsed_ms,
                 'TOTAL_CPU_SEC' VALUE total_cpu_sec,
                 'BUFFER_GETS' VALUE buffer_gets,
                 'AVG_BUFFER_GETS' VALUE avg_buffer_gets,
                 'DISK_READS' VALUE disk_reads,
                 'INVALIDATIONS' VALUE invalidations,
                 'PARSE_CALLS' VALUE parse_calls,
                 'OPTIMIZER_COST' VALUE optimizer_cost,
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
            ROUND(elapsed_time / NULLIF(executions, 0) / 1e3, 3) AS avg_elapsed_ms,
            ROUND(cpu_time / 1e6, 3) AS total_cpu_sec,
            buffer_gets,
            ROUND(buffer_gets / NULLIF(executions, 0)) AS avg_buffer_gets,
            disk_reads,
            invalidations,
            parse_calls,
            optimizer_cost,
            TO_CHAR(last_active_time, 'YYYY-MM-DD"T"HH24:MI:SS') AS last_active_time,
            SUBSTR(REPLACE(REPLACE(sql_text, CHR(10), ' '), CHR(13), ' '), 1, 180) AS sql_preview
        FROM v$sql
        WHERE sql_id = target_sql_id
        ORDER BY child_number
    );

    RETURN v_json;
END;
/

CREATE OR REPLACE FUNCTION ga_ash_sql_hotspots_fn(
    sql_text_filter IN VARCHAR2 DEFAULT NULL,
    hours_back      IN NUMBER   DEFAULT 24,
    limit_rows      IN NUMBER   DEFAULT 20
) RETURN CLOB
AS
    v_json CLOB;
BEGIN
    SELECT NVL(
             JSON_ARRAYAGG(
               JSON_OBJECT(
                 'SQL_ID' VALUE sql_id,
                 'ACTIVE_SAMPLES' VALUE active_samples,
                 'DISTINCT_PLAN_HASHES' VALUE distinct_plan_hashes,
                 'DISTINCT_SESSIONS' VALUE distinct_sessions,
                 'CPU_SAMPLES' VALUE cpu_samples,
                 'WAITING_SAMPLES' VALUE waiting_samples,
                 'FIRST_SEEN' VALUE first_seen,
                 'LAST_SEEN' VALUE last_seen
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
            SELECT
                ash.sql_id,
                COUNT(*) AS active_samples,
                COUNT(DISTINCT ash.sql_plan_hash_value) AS distinct_plan_hashes,
                COUNT(DISTINCT TO_CHAR(ash.session_id) || ':' || TO_CHAR(ash.session_serial#)) AS distinct_sessions,
                SUM(CASE WHEN ash.session_state = 'ON CPU' THEN 1 ELSE 0 END) AS cpu_samples,
                SUM(CASE WHEN ash.session_state = 'WAITING' THEN 1 ELSE 0 END) AS waiting_samples,
                TO_CHAR(MIN(ash.sample_time), 'YYYY-MM-DD"T"HH24:MI:SS') AS first_seen,
                TO_CHAR(MAX(ash.sample_time), 'YYYY-MM-DD"T"HH24:MI:SS') AS last_seen
            FROM v$active_session_history ash
            WHERE ash.sample_time >= SYSTIMESTAMP - NUMTODSINTERVAL(LEAST(GREATEST(NVL(hours_back, 4), 1), 24), 'HOUR')
              AND ash.sql_id IS NOT NULL
              AND (
                    sql_text_filter IS NULL
                    OR EXISTS (
                        SELECT 1
                        FROM v$sqlstats s
                        WHERE s.sql_id = ash.sql_id
                          AND UPPER(s.sql_text) LIKE '%' || UPPER(sql_text_filter) || '%'
                    )
                  )
            GROUP BY ash.sql_id
            ORDER BY COUNT(*) DESC, COUNT(DISTINCT ash.sql_plan_hash_value) DESC
        )
        WHERE ROWNUM <= LEAST(GREATEST(NVL(limit_rows, 20), 1), 100)
    );

    RETURN v_json;
END;
/

CREATE OR REPLACE FUNCTION ga_ash_wait_profile_fn(
    sql_text_filter IN VARCHAR2 DEFAULT NULL,
    hours_back      IN NUMBER   DEFAULT 24,
    limit_rows      IN NUMBER   DEFAULT 20
) RETURN CLOB
AS
    v_json CLOB;
BEGIN
    SELECT NVL(
             JSON_ARRAYAGG(
               JSON_OBJECT(
                 'ACTIVITY_GROUP' VALUE activity_group,
                 'EVENT_NAME' VALUE event_name,
                 'ACTIVE_SAMPLES' VALUE active_samples,
                 'DISTINCT_SQL_IDS' VALUE distinct_sql_ids,
                 'FIRST_SEEN' VALUE first_seen,
                 'LAST_SEEN' VALUE last_seen
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
            SELECT
                CASE
                    WHEN ash.session_state = 'ON CPU' THEN 'ON CPU'
                    WHEN ash.wait_class IS NULL THEN 'WAITING'
                    ELSE ash.wait_class
                END AS activity_group,
                CASE
                    WHEN ash.session_state = 'ON CPU' THEN 'ON CPU'
                    WHEN ash.event IS NULL THEN '(event not captured)'
                    ELSE ash.event
                END AS event_name,
                COUNT(*) AS active_samples,
                COUNT(DISTINCT ash.sql_id) AS distinct_sql_ids,
                TO_CHAR(MIN(ash.sample_time), 'YYYY-MM-DD"T"HH24:MI:SS') AS first_seen,
                TO_CHAR(MAX(ash.sample_time), 'YYYY-MM-DD"T"HH24:MI:SS') AS last_seen
            FROM v$active_session_history ash
            WHERE ash.sample_time >= SYSTIMESTAMP - NUMTODSINTERVAL(LEAST(GREATEST(NVL(hours_back, 4), 1), 24), 'HOUR')
              AND (
                    sql_text_filter IS NULL
                    OR (
                        ash.sql_id IS NOT NULL
                        AND EXISTS (
                            SELECT 1
                            FROM v$sqlstats s
                            WHERE s.sql_id = ash.sql_id
                              AND UPPER(s.sql_text) LIKE '%' || UPPER(sql_text_filter) || '%'
                        )
                    )
                  )
            GROUP BY
                CASE
                    WHEN ash.session_state = 'ON CPU' THEN 'ON CPU'
                    WHEN ash.wait_class IS NULL THEN 'WAITING'
                    ELSE ash.wait_class
                END,
                CASE
                    WHEN ash.session_state = 'ON CPU' THEN 'ON CPU'
                    WHEN ash.event IS NULL THEN '(event not captured)'
                    ELSE ash.event
                END
            ORDER BY COUNT(*) DESC
        )
        WHERE ROWNUM <= LEAST(GREATEST(NVL(limit_rows, 20), 1), 100)
    );

    RETURN v_json;
END;
/

CREATE OR REPLACE FUNCTION ga_plan_change_summary_fn(
    sql_text_filter IN VARCHAR2 DEFAULT NULL,
    hours_back      IN NUMBER   DEFAULT 24,
    limit_rows      IN NUMBER   DEFAULT 20
) RETURN CLOB
AS
    v_json CLOB;
BEGIN
    SELECT NVL(
             JSON_ARRAYAGG(
               JSON_OBJECT(
                 'SQL_ID' VALUE sql_id,
                 'DISTINCT_PLAN_HASHES' VALUE distinct_plan_hashes,
                 'TOTAL_EXECUTIONS' VALUE total_executions,
                 'TOTAL_INVALIDATIONS' VALUE total_invalidations,
                 'TOTAL_ELAPSED_SEC' VALUE total_elapsed_sec,
                 'FIRST_SEEN' VALUE first_seen,
                 'LAST_SEEN' VALUE last_seen,
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
            WITH recent_plan_sql AS (
                SELECT
                    s.sql_id,
                    s.plan_hash_value,
                    s.executions,
                    s.invalidations,
                    s.elapsed_time,
                    s.last_active_time,
                    SUBSTR(REPLACE(REPLACE(s.sql_text, CHR(10), ' '), CHR(13), ' '), 1, 180) AS sql_preview
                FROM v$sqlarea_plan_hash s
                WHERE s.last_active_time >= SYSDATE - (LEAST(GREATEST(NVL(hours_back, 4), 1), 168) / 24)
                  AND (sql_text_filter IS NULL OR UPPER(s.sql_text) LIKE '%' || UPPER(sql_text_filter) || '%')
                  AND NOT REGEXP_LIKE(s.sql_text, '^[[:space:]]*(BEGIN|DECLARE|CALL)([[:space:]]|$)', 'in')
                  AND UPPER(s.sql_text) NOT LIKE '/* SQL ANALYZE%'
                  AND UPPER(s.sql_text) NOT LIKE '%V$SQL%'
                  AND UPPER(s.sql_text) NOT LIKE '%V$SQLAREA_PLAN_HASH%'
                  AND UPPER(s.sql_text) NOT LIKE '%V$ACTIVE_SESSION_HISTORY%'
                  AND UPPER(s.sql_text) NOT LIKE '%V$SYSTEM_EVENT%'
                  AND UPPER(s.sql_text) NOT LIKE '%EXPLAIN PLAN%'
            )
            SELECT
                sql_id,
                COUNT(DISTINCT plan_hash_value) AS distinct_plan_hashes,
                SUM(executions) AS total_executions,
                SUM(invalidations) AS total_invalidations,
                ROUND(SUM(elapsed_time) / 1e6, 3) AS total_elapsed_sec,
                TO_CHAR(MIN(last_active_time), 'YYYY-MM-DD"T"HH24:MI:SS') AS first_seen,
                TO_CHAR(MAX(last_active_time), 'YYYY-MM-DD"T"HH24:MI:SS') AS last_seen,
                MIN(sql_preview) AS sql_preview
            FROM recent_plan_sql
            GROUP BY sql_id
            HAVING COUNT(DISTINCT plan_hash_value) > 1
            ORDER BY COUNT(DISTINCT plan_hash_value) DESC, SUM(elapsed_time) DESC
        )
        WHERE ROWNUM <= LEAST(GREATEST(NVL(limit_rows, 20), 1), 100)
    );

    RETURN v_json;
END;
/

CREATE OR REPLACE FUNCTION ga_plan_change_detail_fn(
    target_sql_id IN VARCHAR2,
    hours_back    IN NUMBER DEFAULT 24
) RETURN CLOB
AS
    v_json CLOB;
BEGIN
    SELECT NVL(
             JSON_ARRAYAGG(
               JSON_OBJECT(
                 'PLAN_HASH_VALUE' VALUE plan_hash_value,
                 'VERSION_COUNT' VALUE version_count,
                 'EXECUTIONS' VALUE executions,
                 'INVALIDATIONS' VALUE invalidations,
                 'PARSE_CALLS' VALUE parse_calls,
                 'TOTAL_ELAPSED_SEC' VALUE total_elapsed_sec,
                 'TOTAL_CPU_SEC' VALUE total_cpu_sec,
                 'BUFFER_GETS' VALUE buffer_gets,
                 'DISK_READS' VALUE disk_reads,
                 'OPTIMIZER_COST' VALUE optimizer_cost,
                 'FIRST_SEEN' VALUE first_seen,
                 'LAST_SEEN' VALUE last_seen
                 RETURNING CLOB
               )
               RETURNING CLOB
             ),
             '[]'
           )
    INTO v_json
    FROM (
        SELECT
            plan_hash_value,
            version_count,
            executions,
            invalidations,
            parse_calls,
            ROUND(elapsed_time / 1e6, 3) AS total_elapsed_sec,
            ROUND(cpu_time / 1e6, 3) AS total_cpu_sec,
            buffer_gets,
            disk_reads,
            optimizer_cost,
            SUBSTR(first_load_time, 1, 19) AS first_seen,
            TO_CHAR(last_active_time, 'YYYY-MM-DD"T"HH24:MI:SS') AS last_seen
        FROM v$sqlarea_plan_hash
        WHERE sql_id = target_sql_id
          AND last_active_time >= SYSDATE - (LEAST(GREATEST(NVL(hours_back, 4), 1), 168) / 24)
        ORDER BY last_active_time DESC, plan_hash_value
    );

    RETURN v_json;
END;
/

CREATE OR REPLACE FUNCTION ga_db_wait_events_summary_fn(
    limit_rows IN NUMBER DEFAULT 20
) RETURN CLOB
AS
    v_json CLOB;
BEGIN
    SELECT NVL(
             JSON_ARRAYAGG(
               JSON_OBJECT(
                 'EVENT' VALUE event,
                 'WAIT_CLASS' VALUE wait_class,
                 'TOTAL_WAITS' VALUE total_waits,
                 'TIME_WAITED_SEC' VALUE time_waited_sec,
                 'AVG_WAIT_MS' VALUE avg_wait_ms
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
            SELECT
                event,
                wait_class,
                total_waits_fg AS total_waits,
                ROUND(time_waited_micro_fg / 1e6, 3) AS time_waited_sec,
                ROUND(average_wait_fg / 10, 3) AS avg_wait_ms
            FROM v$system_event
            WHERE wait_class <> 'Idle'
            ORDER BY time_waited_micro_fg DESC, total_waits_fg DESC
        )
        WHERE ROWNUM <= LEAST(GREATEST(NVL(limit_rows, 20), 1), 100)
    );

    RETURN v_json;
END;
/

PROMPT
PROMPT Registering additional MCP tools ...
PROMPT

BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name => 'GA_TOP_SQL_SUMMARY', force => TRUE);
    DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name => 'GA_TOP_SQL_DETAIL', force => TRUE);
    DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name => 'GA_ASH_SQL_HOTSPOTS', force => TRUE);
    DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name => 'GA_ASH_WAIT_PROFILE', force => TRUE);
    DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name => 'GA_PLAN_CHANGE_SUMMARY', force => TRUE);
    DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name => 'GA_PLAN_CHANGE_DETAIL', force => TRUE);
    DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name => 'GA_DB_WAIT_EVENTS_SUMMARY', force => TRUE);
END;
/

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name  => 'GA_TOP_SQL_SUMMARY',
        attributes => q'!{
          "instruction": "Summarize the top SQL statements in the database by elapsed time, CPU time, and buffer gets using V$SQLSTATS. Use this first when the symptom is a degraded SQL workload or top SQL investigation.",
          "function": "GA_TOP_SQL_SUMMARY_FN",
          "tool_inputs": [
            {"name": "sql_text_filter", "description": "Optional case-insensitive SQL text fragment to narrow the SQL set."},
            {"name": "hours_back", "description": "Lookback window in hours based on LAST_ACTIVE_TIME. Default 4, max 168."},
            {"name": "limit_rows", "description": "Optional maximum rows to return. Default 20, max 100."}
          ]
        }!'
    );
END;
/

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name  => 'GA_TOP_SQL_DETAIL',
        attributes => q'!{
          "instruction": "Return detailed current cursor metrics for one SQL_ID, including executions, elapsed time, CPU time, buffer gets, disk reads, invalidations, and plan hash by child cursor.",
          "function": "GA_TOP_SQL_DETAIL_FN",
          "tool_inputs": [
            {"name": "target_sql_id", "description": "The SQL_ID to inspect."}
          ]
        }!'
    );
END;
/

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name  => 'GA_ASH_SQL_HOTSPOTS',
        attributes => q'!{
          "instruction": "Summarize the top SQL_ID values in V$ACTIVE_SESSION_HISTORY across the database over the requested recent hours. Use this when you need recent ASH-style evidence of where active time is concentrated.",
          "function": "GA_ASH_SQL_HOTSPOTS_FN",
          "tool_inputs": [
            {"name": "sql_text_filter", "description": "Optional case-insensitive SQL text fragment to focus the ASH summary on a target workload."},
            {"name": "hours_back", "description": "Lookback window in hours. Practical default 1 to 4, max 24."},
            {"name": "limit_rows", "description": "Optional maximum rows to return. Default 20, max 100."}
          ]
        }!'
    );
END;
/

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name  => 'GA_ASH_WAIT_PROFILE',
        attributes => q'!{
          "instruction": "Summarize recent activity from V$ACTIVE_SESSION_HISTORY by wait class or ON CPU across the database. Use this to understand the recent wait profile and dominant activity classes.",
          "function": "GA_ASH_WAIT_PROFILE_FN",
          "tool_inputs": [
            {"name": "sql_text_filter", "description": "Optional case-insensitive SQL text fragment to focus the wait profile on a target workload."},
            {"name": "hours_back", "description": "Lookback window in hours. Practical default 1 to 4, max 24."},
            {"name": "limit_rows", "description": "Optional maximum rows to return. Default 20, max 100."}
          ]
        }!'
    );
END;
/

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name  => 'GA_PLAN_CHANGE_SUMMARY',
        attributes => q'!{
          "instruction": "Summarize SQL statements that currently show multiple plan hashes in V$SQLAREA_PLAN_HASH over the requested recent activity window across the database. Use this when the symptom suggests plan drift or recurring regressions.",
          "function": "GA_PLAN_CHANGE_SUMMARY_FN",
          "tool_inputs": [
            {"name": "sql_text_filter", "description": "Optional case-insensitive SQL text fragment to narrow the summary to a target workload."},
            {"name": "hours_back", "description": "Lookback window in hours. Default 4, max 168."},
            {"name": "limit_rows", "description": "Optional maximum rows to return. Default 20, max 100."}
          ]
        }!'
    );
END;
/

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name  => 'GA_PLAN_CHANGE_DETAIL',
        attributes => q'!{
          "instruction": "Return plan-hash-level current evidence for one SQL_ID from V$SQLAREA_PLAN_HASH, including executions, invalidations, elapsed time, and first/last seen times.",
          "function": "GA_PLAN_CHANGE_DETAIL_FN",
          "tool_inputs": [
            {"name": "target_sql_id", "description": "The SQL_ID to inspect."},
            {"name": "hours_back", "description": "Lookback window in hours. Default 4, max 168."}
          ]
        }!'
    );
END;
/

BEGIN
    DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
        tool_name  => 'GA_DB_WAIT_EVENTS_SUMMARY',
        attributes => q'!{
          "instruction": "Summarize top non-idle foreground database wait events from V$SYSTEM_EVENT. Use this to understand the dominant wait profile at the database level.",
          "function": "GA_DB_WAIT_EVENTS_SUMMARY_FN",
          "tool_inputs": [
            {"name": "limit_rows", "description": "Optional maximum rows to return. Default 20, max 100."}
          ]
        }!'
    );
END;
/

PROMPT
PROMPT Additional performance diagnostic tool packs installed.
PROMPT Tools:
PROMPT   GA_TOP_SQL_SUMMARY
PROMPT   GA_TOP_SQL_DETAIL
PROMPT   GA_ASH_SQL_HOTSPOTS
PROMPT   GA_ASH_WAIT_PROFILE
PROMPT   GA_PLAN_CHANGE_SUMMARY
PROMPT   GA_PLAN_CHANGE_DETAIL
PROMPT   GA_DB_WAIT_EVENTS_SUMMARY
PROMPT
