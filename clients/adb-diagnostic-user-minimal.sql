--------------------------------------------------------------------------------
-- adb-diagnostic-user-minimal.sql
--
-- Creates a least-privilege user for the repo's default diagnostic flow on ADB.
-- Run as ADMIN.
--
-- Assumes this user is, or will be, the graph-owning schema used by the skill.
--
-- Usage:
--   DEFINE diag_user = GRAPH_DIAG_USER
--   DEFINE diag_password = GraphDiag123##!
--   @clients/adb-diagnostic-user-minimal.sql
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON
SET HEADING ON
SET SERVEROUTPUT ON

CREATE USER &&diag_user IDENTIFIED BY "&&diag_password"
  DEFAULT TABLESPACE DATA
  TEMPORARY TABLESPACE TEMP
  QUOTA 200M ON DATA;

GRANT CREATE SESSION TO &&diag_user;
GRANT EXECUTE ON DBMS_XPLAN TO &&diag_user;

GRANT SELECT ON SYS.V_$SQL TO &&diag_user;
GRANT SELECT ON SYS.V_$SQLSTATS TO &&diag_user;
GRANT SELECT ON SYS.V_$SQLAREA_PLAN_HASH TO &&diag_user;
GRANT SELECT ON SYS.V_$SQL_PLAN TO &&diag_user;
GRANT SELECT ON SYS.V_$SQL_PLAN_STATISTICS_ALL TO &&diag_user;
GRANT SELECT ON SYS.V_$SQL_SHARED_CURSOR TO &&diag_user;
GRANT SELECT ON SYS.V_$SQLTEXT TO &&diag_user;
GRANT SELECT ON SYS.V_$PARAMETER TO &&diag_user;
GRANT SELECT ON SYS.V_$SESSION TO &&diag_user;
GRANT SELECT ON SYS.V_$SYSMETRIC_HISTORY TO &&diag_user;
GRANT SELECT ON SYS.V_$SYSTEM_EVENT TO &&diag_user;
GRANT SELECT ON SYS.V_$SGASTAT TO &&diag_user;
GRANT SELECT ON SYS.V_$PGASTAT TO &&diag_user;

PROMPT
PROMPT Broad ADB shortcut for session-based SQL-only access:
PROMPT   GRANT SELECT_CATALOG_ROLE TO &&diag_user;
PROMPT   -- keep CREATE SESSION and EXECUTE ON DBMS_XPLAN
PROMPT   -- do not rely on role-only access for stored PL/SQL Native MCP tools
PROMPT
PROMPT Optional recent-ASH pack extra:
PROMPT   GRANT SELECT ON SYS.V_$ACTIVE_SESSION_HISTORY TO &&diag_user;
PROMPT
PROMPT Optional DB time model extra for OPTIONAL-02C:
PROMPT   GRANT SELECT ON SYS.V_$SYS_TIME_MODEL TO &&diag_user;
PROMPT
PROMPT Optional Native MCP extras:
PROMPT   GRANT CREATE PROCEDURE TO &&diag_user;
PROMPT   GRANT EXECUTE ON C##CLOUD$SERVICE.DBMS_CLOUD_AI_AGENT TO &&diag_user;
PROMPT
PROMPT Optional historical AWR extras:
PROMPT   GRANT SELECT ON DBA_HIST_SNAPSHOT TO &&diag_user;
PROMPT   GRANT SELECT ON DBA_HIST_SYSMETRIC_SUMMARY TO &&diag_user;
PROMPT   GRANT SELECT ON DBA_HIST_SYSTEM_EVENT TO &&diag_user;
PROMPT   GRANT SELECT ON DBA_HIST_PGASTAT TO &&diag_user;
PROMPT   GRANT SELECT ON DBA_HIST_ACTIVE_SESS_HISTORY TO &&diag_user;
PROMPT
PROMPT Optional lab-only extras if this user will also create a new graph schema:
PROMPT   GRANT CREATE TABLE TO &&diag_user;
PROMPT   GRANT CREATE PROPERTY GRAPH TO &&diag_user;
