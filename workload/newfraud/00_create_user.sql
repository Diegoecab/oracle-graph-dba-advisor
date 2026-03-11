--------------------------------------------------------------------------------
-- 00_create_user.sql
-- Transaction Fraud Graph — Target Schema Setup (Oracle 23ai / 26ai ADB-S)
--
-- Creates the NEWFRAUD schema where all transaction fraud graph objects live.
-- Run as ADMIN (or a user with CREATE USER + GRANT privileges).
--
-- Usage:
--   @00_create_user.sql
--   -- Then run scripts 01-05 which create objects in NEWFRAUD.
--------------------------------------------------------------------------------

-- Drop user if exists
BEGIN
  EXECUTE IMMEDIATE 'DROP USER NEWFRAUD CASCADE';
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

CREATE USER NEWFRAUD IDENTIFIED BY "TxGraph#Advisor_2024x"
  DEFAULT TABLESPACE DATA
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON DATA;

-- Core privileges
GRANT CONNECT, RESOURCE TO NEWFRAUD;
GRANT CREATE SESSION TO NEWFRAUD;
GRANT CREATE TABLE TO NEWFRAUD;
GRANT CREATE VIEW TO NEWFRAUD;
GRANT CREATE SEQUENCE TO NEWFRAUD;
GRANT CREATE PROCEDURE TO NEWFRAUD;
GRANT CREATE PROPERTY GRAPH TO NEWFRAUD;

-- For data generation (DBMS_RANDOM, DBMS_STATS)
GRANT EXECUTE ON DBMS_RANDOM TO NEWFRAUD;
GRANT EXECUTE ON DBMS_STATS TO NEWFRAUD;

PROMPT Schema NEWFRAUD created with required privileges.
