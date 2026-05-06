# Diagnostic Mode — Minimum Prereqs

Short operational version for the client-facing diagnostic/advisor flow.

For the **Graph DBA workload-analysis** case, use this together with:

- `docs/graph-dba-workload-mode-requirements.md`

## Recommended client model

- Create **one dedicated technical schema per target database**.
- The **admin team** uses that technical user; do not use `ADMIN`.
- Keep the same skill and the same `RUN_SQL` tool contract in every database.
- For multiple databases, only the MCP alias, database OCID, and token change.
- If the client wants a **Graph DBA** workflow, the first step should be a technical graph catalog, not business-domain classification.

In this repo, **dedicated technical schema** means:

- one database user created specifically for the skill in one target database
- not a personal user
- not `ADMIN`
- least-privilege direct grants only
- reusable by the admin team with normal credential rotation and auditing

For the packaged admin playbooks, this user **does not need to own the application tables or graph objects**. The core performance packs operate on database performance views and optionally narrow to the target workload by `sql_text_filter`.

## Baseline diagnostic access

For the current repo behavior, the technical schema should have:

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
```

Notes:

- If the client wants a broader built-in read role instead of many per-view grants, `SELECT_CATALOG_ROLE` is the right ADB shortcut, not `DBA`.
- For session-based SQL access, this compact model is valid:

```sql
GRANT CREATE SESSION TO graph_diag_user;
GRANT SELECT_CATALOG_ROLE TO graph_diag_user;
GRANT EXECUTE ON DBMS_XPLAN TO graph_diag_user;
```

- In our validated ADB test, `SELECT_CATALOG_ROLE` covered the repo's current `SYS.V_$...`, graph catalog `DBA_*`, historical `DBA_HIST_*`, and `DBA_SQL_PLAN_BASELINES` reads.
- On ADB, grant dynamic performance views as `SYS.V_$...`.
- The packaged admin playbooks (`top SQL`, `ASH`, `plan change`, `wait events`) are **DB-wide** and do not require the technical user to be the graph owner.
- For packaged Native MCP tools implemented as stored PL/SQL functions, keep **direct grants**. Role-only access is not the safe runtime model there.
- Some legacy discovery templates still use `USER_*` graph/object views, so that older path remains tied to the graph-owning schema unless you adapt those templates to `ALL_*` / `DBA_*`.
- A central observer schema across other application schemas is possible, but that is a different model and would require `ALL_*` / `DBA_*` templates plus owner filters.
- For the packaged recent-activity playbooks, `V$ACTIVE_SESSION_HISTORY` is the practical default. It is much faster than `DBA_HIST_ACTIVE_SESS_HISTORY` over Native MCP for the baseline troubleshooting flow.

## Extra grants for full advisor mode

If the client wants the fuller health-check/advisor path, add:

```sql
GRANT SELECT ON DBA_TABLESPACE_USAGE_METRICS TO graph_diag_user;
GRANT SELECT ON DBA_TEMP_FREE_SPACE TO graph_diag_user;
GRANT SELECT ON DBA_AUTO_INDEX_CONFIG TO graph_diag_user;
GRANT SELECT ON DBA_AUTO_INDEX_IND_ACTIONS TO graph_diag_user;
GRANT SELECT ON DBA_AUTO_INDEX_EXECUTIONS TO graph_diag_user;
GRANT SELECT ON DBA_HIST_SNAPSHOT TO graph_diag_user;
GRANT SELECT ON DBA_HIST_SYSMETRIC_SUMMARY TO graph_diag_user;
GRANT SELECT ON DBA_HIST_SYSTEM_EVENT TO graph_diag_user;
GRANT SELECT ON DBA_HIST_PGASTAT TO graph_diag_user;
```

Reference script for this layer: `clients/adb-diagnostic-grants-advisor.sql`

If the client also wants heavier historical AWR/ASH extensions beyond the core Native MCP playbooks, add:

```sql
GRANT SELECT ON DBA_HIST_ACTIVE_SESS_HISTORY TO graph_diag_user;
```

## Optional extras for plan instability / baseline cases

If the client wants the skill to diagnose cursor instability and baseline state more explicitly, add:

```sql
GRANT SELECT ON DBA_SQL_PLAN_BASELINES TO graph_diag_user;
```

If they want the DBA team to use the database user itself for baseline actions such as loading/fixing plans with `DBMS_SPM`, that becomes a separate elevated capability and should be granted only if explicitly approved:

```sql
GRANT ADMINISTER SQL MANAGEMENT OBJECT TO graph_diag_user;
```

## If you use ADB Native MCP

In addition to the grants above:

- Enable the ADB MCP endpoint with the `adb$feature` free-form tag.
- Expose a read-only `RUN_SQL` function as an MCP tool.
- Grant `CREATE PROCEDURE` to the technical schema.
- If that same schema will register its own tools, also grant:

```sql
GRANT EXECUTE ON C##CLOUD$SERVICE.DBMS_CLOUD_AI_AGENT TO graph_diag_user;
```

Reference scripts:

- `clients/adb-diagnostic-user-minimal.sql`
- `clients/adb-diagnostic-grants-advisor.sql`

## Native MCP runtime behavior we validated

In our ADB Native MCP lab:

- `SESSION_USER` and `USER` appeared as `C##CLOUD$SERVICE`
- `CURRENT_USER` and `CURRENT_SCHEMA` resolved to the tool-owning schema (`NEWFRAUD`)
- the current `USER_*` graph/object views still worked through `RUN_SQL`

This means the current templates were usable over Native MCP in our test, even though the session is brokered by Oracle's cloud service user.

## Authentication

- Use **OAuth** for interactive login.
- Use **bearer token** for headless or automated flows.

For this project, bearer token remains the practical default for Native MCP.

Concretely:

- `OAuth`:
  configure the MCP server URL without an `Authorization` header and let the client show the Oracle login screen
- `Bearer token`:
  call the ADB token endpoint with the technical schema username and password, then send `Authorization: Bearer <token>` in the MCP client configuration

Operationally:

- use one MCP server entry per target database
- keep the same skill and tool contract for every database
- only the MCP URL, database OCID, and bearer token change per database

## Best practices

- For packaged MCP tools, prefer **direct grants on the technical schema** for predictable runtime behavior.
- For session-based SQL access, `SELECT_CATALOG_ROLE` is acceptable and much simpler than enumerating many read-only views.
- Keep the schema least-privileged.
- Prefer one technical schema per database over broad shared admin access.
- For sensitive environments, add Private Endpoint, ACL/VPD, and auditing.

## Validation assets

- Baseline setup: `clients/adb-diagnostic-user-minimal.sql`
- Full advisor grants: `clients/adb-diagnostic-grants-advisor.sql`
- Graph DBA workload mode summary: `docs/graph-dba-workload-mode-requirements.md`
- Demo-only lab extras: `workload/newfraud/08_grant_plan_instability_lab_extras.sql`
- Native MCP lab run: `workload/newfraud/07_native_mcp_advisor_demo.sh`
- Plan instability lab run: `workload/newfraud/08_plan_instability_demo.sh`
