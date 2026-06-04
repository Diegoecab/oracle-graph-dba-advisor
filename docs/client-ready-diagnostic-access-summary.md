# Client-Ready Diagnostic Access Summary

Short version to share with the client when they ask what DB access is required for the Graph DBA diagnostic mode.

## Option 1. Minimum read-only access

Use this when the skill will connect through:

- SQLcl MCP
- interactive SQL
- a simple read-only `RUN_SQL` style MCP tool

This is the simplest model and does **not** require the `DBA` role.

```sql
GRANT CREATE SESSION TO graph_diag_user;
GRANT SELECT_CATALOG_ROLE TO graph_diag_user;
GRANT EXECUTE ON DBMS_XPLAN TO graph_diag_user;
```

What this enables:

- read performance views used for troubleshooting
- read graph catalog metadata through `DBA_*` views
- inspect execution plans
- analyze workload and propose changes

Use this option when the skill only needs to **read and analyze**.

## Option 2. Packaged Native MCP runtime

Use this when the skill will run through **ADB Native MCP** with packaged diagnostic tools implemented as stored PL/SQL functions inside the database.

In this model, do **not** rely only on `SELECT_CATALOG_ROLE`.

Use direct grants instead:

```sql
GRANT CREATE SESSION TO graph_diag_user;
GRANT EXECUTE ON DBMS_XPLAN TO graph_diag_user;

GRANT SELECT ON SYS.V_$SQL TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQLSTATS TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQLAREA_PLAN_HASH TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQL_PLAN TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQL_PLAN_STATISTICS_ALL TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQL_SHARED_CURSOR TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQLTEXT TO graph_diag_user;
GRANT SELECT ON SYS.V_$PARAMETER TO graph_diag_user;
GRANT SELECT ON SYS.V_$SESSION TO graph_diag_user;
GRANT SELECT ON SYS.V_$ACTIVE_SESSION_HISTORY TO graph_diag_user;
GRANT SELECT ON SYS.V_$SYSMETRIC_HISTORY TO graph_diag_user;
GRANT SELECT ON SYS.V_$SYSTEM_EVENT TO graph_diag_user;
GRANT SELECT ON SYS.V_$SGASTAT TO graph_diag_user;
GRANT SELECT ON SYS.V_$PGASTAT TO graph_diag_user;

GRANT SELECT ON DBA_PROPERTY_GRAPHS TO graph_diag_user;
GRANT SELECT ON DBA_PG_ELEMENTS TO graph_diag_user;
GRANT SELECT ON DBA_PG_EDGE_RELATIONSHIPS TO graph_diag_user;
GRANT SELECT ON DBA_TABLES TO graph_diag_user;
GRANT SELECT ON DBA_INDEXES TO graph_diag_user;
GRANT SELECT ON DBA_IND_COLUMNS TO graph_diag_user;
GRANT SELECT ON DBA_TAB_STATISTICS TO graph_diag_user;
GRANT SELECT ON DBA_TAB_COL_STATISTICS TO graph_diag_user;
GRANT SELECT ON DBA_TAB_MODIFICATIONS TO graph_diag_user;

GRANT SELECT ON DBA_TABLESPACE_USAGE_METRICS TO graph_diag_user;
GRANT SELECT ON DBA_TEMP_FREE_SPACE TO graph_diag_user;
GRANT SELECT ON DBA_AUTO_INDEX_CONFIG TO graph_diag_user;
GRANT SELECT ON DBA_AUTO_INDEX_IND_ACTIONS TO graph_diag_user;
GRANT SELECT ON DBA_AUTO_INDEX_EXECUTIONS TO graph_diag_user;
GRANT SELECT ON DBA_HIST_SNAPSHOT TO graph_diag_user;
GRANT SELECT ON DBA_HIST_SYSMETRIC_SUMMARY TO graph_diag_user;
GRANT SELECT ON DBA_HIST_SYSTEM_EVENT TO graph_diag_user;
GRANT SELECT ON DBA_HIST_PGASTAT TO graph_diag_user;

GRANT CREATE PROCEDURE TO graph_diag_user;
GRANT EXECUTE ON C##CLOUD$SERVICE.DBMS_CLOUD_AI_AGENT TO graph_diag_user;
```

Optional extras:

```sql
GRANT SELECT ON DBA_HIST_ACTIVE_SESS_HISTORY TO graph_diag_user;
GRANT SELECT ON DBA_SQL_PLAN_BASELINES TO graph_diag_user;
```

Use this option when the skill must:

- expose packaged MCP tools from inside ADB
- run repeatable diagnostic playbooks
- keep the runtime fully packaged and predictable

## Which one to use

Use **Option 1** if:

- the client wants the minimum access model
- the skill only needs read-only analysis
- the MCP path is session-based SQL

Use **Option 2** if:

- the client wants ADB Native MCP with packaged in-database tools
- the runtime must be fully packaged inside the database
- the diagnostic functions will be created as stored PL/SQL code

## Recommendation

For the client conversation, the clean recommendation is:

1. start with **Option 1** if they only want diagnostic visibility
2. move to **Option 2** if they want the skill packaged as native in-database tools on ADB

## Validated behavior

This was validated on our ADB test environment with:

- `workload/newfraud/11_validate_select_catalog_role.sh`
- `clients/validate-select-catalog-role-coverage.sql`

Observed result:

- `SELECT_CATALOG_ROLE` was enough for the current **session-based SQL** checks, including `V$`, graph catalog `DBA_*`, historical `DBA_HIST_*`, `DBA_SQL_PLAN_BASELINES`, and `DBMS_XPLAN.DISPLAY_CURSOR`
- the same user **failed** when the same reads were moved into stored definer-rights PL/SQL functions
- static PL/SQL failed at compile time with `ORA-00942`
- dynamic SQL inside definer-rights PL/SQL compiled, but failed at runtime with `ORA-00942`

Conclusion:

- `SELECT_CATALOG_ROLE` is valid for read-only session access
- it is **not** sufficient for the current packaged Native MCP runtime

## Reference

Longer technical detail:

- `docs/graph-dba-workload-mode-requirements.md`
- `docs/diagnostic-mode-minimum-prereqs.md`
- `clients/adb-diagnostic-grants-advisor.sql`
