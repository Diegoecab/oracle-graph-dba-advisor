--------------------------------------------------------------------------------
-- 21_grant_plan_instability_extras.sql
-- Grants the setup-only privilege needed to induce optimizer environment
-- changes for the Mini-DOWNER plan-instability scenario.
--
-- Run as ADMIN.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON

DEFINE downer_user = DOWNER_DEMO

GRANT ALTER SESSION TO &&downer_user;

PROMPT Plan-instability setup extras granted to &&downer_user.
