--------------------------------------------------------------------------------
-- 00_create_users.sql
-- Mini-DOWNER demo users for ADB-S Diagnostic Mode.
--
-- Run as ADMIN.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON

PROMPT Usage: @workload/downer/00_create_users.sql "<downer_password>" "<graph_diag_password>"

DEFINE downer_user = DOWNER_DEMO
DEFINE downer_password = "&&1"
DEFINE diag_user = GRAPH_DIAG_USER
DEFINE diag_password = "&&2"

BEGIN
  EXECUTE IMMEDIATE 'CREATE USER &&downer_user IDENTIFIED BY &&downer_password DEFAULT TABLESPACE DATA TEMPORARY TABLESPACE TEMP QUOTA 10G ON DATA';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1920 THEN
      RAISE;
    END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'CREATE USER &&diag_user IDENTIFIED BY &&diag_password DEFAULT TABLESPACE DATA TEMPORARY TABLESPACE TEMP QUOTA 200M ON DATA';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1920 THEN
      RAISE;
    END IF;
END;
/

GRANT CREATE SESSION TO &&downer_user;
GRANT CREATE TABLE TO &&downer_user;
GRANT CREATE VIEW TO &&downer_user;
GRANT CREATE SEQUENCE TO &&downer_user;
GRANT CREATE PROCEDURE TO &&downer_user;
GRANT CREATE JOB TO &&downer_user;
GRANT CREATE PROPERTY GRAPH TO &&downer_user;
GRANT EXECUTE ON DBMS_RANDOM TO &&downer_user;
GRANT EXECUTE ON DBMS_STATS TO &&downer_user;

GRANT CREATE SESSION TO &&diag_user;
GRANT EXECUTE ON DBMS_XPLAN TO &&diag_user;

GRANT CREATE PROCEDURE TO &&diag_user;
GRANT EXECUTE ON C##CLOUD$SERVICE.DBMS_CLOUD_AI_AGENT TO &&diag_user;

PROMPT Users ready. Run workload scripts as DOWNER_DEMO, then register RUN_SQL as GRAPH_DIAG_USER.
