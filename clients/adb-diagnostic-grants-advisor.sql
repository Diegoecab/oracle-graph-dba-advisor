--------------------------------------------------------------------------------
-- adb-diagnostic-grants-advisor.sql
--
-- Grants the direct privileges needed for the repo's current diagnostic/advisor
-- mode on Oracle Autonomous Database.
--
-- Run as ADMIN against an EXISTING dedicated diagnostic schema.
--
-- Why direct grants:
--   The Native MCP flow uses a stored RUN_SQL PL/SQL function. For definer-rights
--   PL/SQL, relying only on role-based access is fragile; direct grants are the
--   safer model for predictable runtime behavior.
--
-- Simpler ADB alternative for session-based SQL only:
--   GRANT SELECT_CATALOG_ROLE TO <diag_user>;
--   plus CREATE SESSION and EXECUTE ON DBMS_XPLAN.
--
-- We intentionally do not use SELECT_CATALOG_ROLE in this script because the
-- current packaged Native MCP tools are stored PL/SQL functions.
--
-- Usage:
--   DEFINE diag_user = GRAPH_DIAG_USER
--   @clients/adb-diagnostic-grants-advisor.sql
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON
SET HEADING ON
SET SERVEROUTPUT ON

PROMPT
PROMPT Granting full advisor-mode direct access to &&diag_user ...
PROMPT

--------------------------------------------------------------------------------
-- Runtime session + plan inspection
--------------------------------------------------------------------------------
GRANT CREATE SESSION TO &&diag_user;
GRANT EXECUTE ON DBMS_XPLAN TO &&diag_user;

--------------------------------------------------------------------------------
-- Dynamic performance views used by the repo
--------------------------------------------------------------------------------
GRANT SELECT ON SYS.V_$SQL TO &&diag_user;
GRANT SELECT ON SYS.V_$SQLSTATS TO &&diag_user;
GRANT SELECT ON SYS.V_$SQLAREA_PLAN_HASH TO &&diag_user;
GRANT SELECT ON SYS.V_$SQL_PLAN TO &&diag_user;
GRANT SELECT ON SYS.V_$SQL_PLAN_STATISTICS_ALL TO &&diag_user;
GRANT SELECT ON SYS.V_$SQL_SHARED_CURSOR TO &&diag_user;
GRANT SELECT ON SYS.V_$SQL_BIND_CAPTURE TO &&diag_user;
GRANT SELECT ON SYS.V_$SQLTEXT TO &&diag_user;
GRANT SELECT ON SYS.V_$PARAMETER TO &&diag_user;
GRANT SELECT ON SYS.V_$SESSION TO &&diag_user;
GRANT SELECT ON SYS.V_$ACTIVE_SESSION_HISTORY TO &&diag_user;
GRANT SELECT ON SYS.V_$SYSMETRIC_HISTORY TO &&diag_user;
GRANT SELECT ON SYS.V_$SYSTEM_EVENT TO &&diag_user;
-- Required when DB time model breakdown / OPTIONAL-02C is in scope.
GRANT SELECT ON SYS.V_$SYS_TIME_MODEL TO &&diag_user;
GRANT SELECT ON SYS.V_$SGASTAT TO &&diag_user;
GRANT SELECT ON SYS.V_$PGASTAT TO &&diag_user;

-- Advisor-mode SQL Plan Management visibility.
GRANT SELECT ON SYS.DBA_SQL_PLAN_BASELINES TO &&diag_user;

--------------------------------------------------------------------------------
-- Graph DBA catalog and object metadata
--------------------------------------------------------------------------------
GRANT SELECT ON DBA_PROPERTY_GRAPHS TO &&diag_user;
GRANT SELECT ON DBA_PG_ELEMENTS TO &&diag_user;
GRANT SELECT ON DBA_PG_EDGE_RELATIONSHIPS TO &&diag_user;
GRANT SELECT ON DBA_TABLES TO &&diag_user;
GRANT SELECT ON DBA_INDEXES TO &&diag_user;
GRANT SELECT ON DBA_IND_COLUMNS TO &&diag_user;
GRANT SELECT ON DBA_TAB_STATISTICS TO &&diag_user;
GRANT SELECT ON DBA_TAB_COL_STATISTICS TO &&diag_user;
GRANT SELECT ON DBA_TAB_MODIFICATIONS TO &&diag_user;

--------------------------------------------------------------------------------
-- Health-check views used by current templates
--------------------------------------------------------------------------------
GRANT SELECT ON DBA_TABLESPACE_USAGE_METRICS TO &&diag_user;
GRANT SELECT ON DBA_TEMP_FREE_SPACE TO &&diag_user;
GRANT SELECT ON DBA_AUTO_INDEX_CONFIG TO &&diag_user;
GRANT SELECT ON DBA_AUTO_INDEX_IND_ACTIONS TO &&diag_user;
GRANT SELECT ON DBA_AUTO_INDEX_EXECUTIONS TO &&diag_user;
GRANT SELECT ON DBA_HIST_SNAPSHOT TO &&diag_user;
GRANT SELECT ON DBA_HIST_SYSMETRIC_SUMMARY TO &&diag_user;
GRANT SELECT ON DBA_HIST_SYSTEM_EVENT TO &&diag_user;
GRANT SELECT ON DBA_HIST_PGASTAT TO &&diag_user;
GRANT SELECT ON DBA_HIST_ACTIVE_SESS_HISTORY TO &&diag_user;

--------------------------------------------------------------------------------
-- Native MCP tool lifecycle.
-- Prefer a DBA/installer account to create RUN_SQL in the diagnostic schema.
-- This runtime grants script does not grant tool installation privileges.
--------------------------------------------------------------------------------

PROMPT
PROMPT Advisor-mode direct grants completed for &&diag_user.
PROMPT ADB Native MCP tool creation is DBA/installer-managed by default.
PROMPT Optional demo/build-only extras are NOT included here:
PROMPT   CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
PROMPT   CREATE PROPERTY GRAPH, ALTER SESSION,
PROMPT   EXECUTE ON DBMS_RANDOM, EXECUTE ON DBMS_STATS
PROMPT Advisor-mode SQL Plan Management visibility included:
PROMPT   GRANT SELECT ON SYS.DBA_SQL_PLAN_BASELINES TO &&diag_user;
PROMPT Optional advanced baseline remediation:
PROMPT   GRANT ADMINISTER SQL MANAGEMENT OBJECT TO &&diag_user;
PROMPT
