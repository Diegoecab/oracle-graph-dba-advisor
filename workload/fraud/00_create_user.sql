--------------------------------------------------------------------------------
-- 00_create_user.sql
-- Fraud Detection Graph — Target Schema Setup (Oracle 23ai / 26ai ADB-S)
--
-- Creates the target schema (user) where all fraud graph objects will live.
-- Run as ADMIN (or a user with CREATE USER + GRANT privileges).
--
-- Usage:
--   @00_create_user.sql
--   -- Then run scripts 01-05 which create objects in MYSCHEMA.
--------------------------------------------------------------------------------

-- Create user MYSCHEMA (drop first if exists)
BEGIN
  EXECUTE IMMEDIATE 'DROP USER MYSCHEMA CASCADE';
EXCEPTION
  WHEN OTHERS THEN NULL;  -- user doesn't exist, ignore
END;
/

CREATE USER MYSCHEMA IDENTIFIED BY "MySchema#2024_Pwd"
  DEFAULT TABLESPACE DATA
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON DATA;

-- Core privileges
GRANT CONNECT, RESOURCE TO MYSCHEMA;
GRANT CREATE SESSION TO MYSCHEMA;
GRANT CREATE TABLE TO MYSCHEMA;
GRANT CREATE VIEW TO MYSCHEMA;
GRANT CREATE SEQUENCE TO MYSCHEMA;
GRANT CREATE PROCEDURE TO MYSCHEMA;
GRANT CREATE PROPERTY GRAPH TO MYSCHEMA;

-- For workload procedure (DBMS_RANDOM, DBMS_OUTPUT, DBMS_STATS)
GRANT EXECUTE ON DBMS_RANDOM TO MYSCHEMA;
GRANT EXECUTE ON DBMS_STATS TO MYSCHEMA;

-- For the advisor to query V$SQL, V$SQL_PLAN from MYSCHEMA context
GRANT SELECT ON V_$SQL TO MYSCHEMA;
GRANT SELECT ON V_$SQL_PLAN TO MYSCHEMA;
GRANT SELECT ON V_$SQL_PLAN_STATISTICS_ALL TO MYSCHEMA;

PROMPT Schema MYSCHEMA created with required privileges.
