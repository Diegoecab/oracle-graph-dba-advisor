--------------------------------------------------------------------------------
-- 08_grant_plan_instability_lab_extras.sql
--
-- Demo-only privilege for the synthetic plan-instability lab.
--
-- Run as ADMIN:
--   DEFINE diag_user = NEWFRAUD
--   @workload/newfraud/08_grant_plan_instability_lab_extras.sql
--
-- This is NOT part of the minimum diagnostic-mode runtime grants.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON

PROMPT
PROMPT Granting plan-instability lab extras to &&diag_user ...
PROMPT

GRANT ALTER SESSION TO &&diag_user;

PROMPT
PROMPT Plan-instability lab extras granted to &&diag_user.
PROMPT
