# Graph DBA Workload Mode — Client Requirements

Clear implementation requirements for running the skill in:

1. analyze workload
2. detect issues
3. propose changes
4. optionally validate changes with before/after comparison

Short shareable version:

- [docs/client-ready-diagnostic-access-summary.md](client-ready-diagnostic-access-summary.md)

## DB privileges only

If the client only wants the **database privileges** required by the technical user, use this summary.

### Broad read role shortcut on ADB

If the client wants a shorter **role-based read model** and does **not** want to use `DBA`, the practical built-in role on Autonomous Database is:

```sql
GRANT CREATE SESSION TO graph_diag_user;
GRANT SELECT_CATALOG_ROLE TO graph_diag_user;
GRANT EXECUTE ON DBMS_XPLAN TO graph_diag_user;
```

In our validated ADB test, `SELECT_CATALOG_ROLE` covered the current read-only objects used by this repo across:

- `SYS.V_$...` performance views
- graph catalog `DBA_*` views
- historical `DBA_HIST_*` views
- `DBA_SQL_PLAN_BASELINES`

Use this shortcut for:

- interactive SQL
- SQLcl MCP
- plain read-only `RUN_SQL` style access

Do **not** rely on `SELECT_CATALOG_ROLE` alone for packaged Native MCP tools implemented as stored PL/SQL functions.

Those functions run as named definer-rights PL/SQL by default, and roles are disabled there. For that runtime model, keep the direct grants listed below.

Validation assets in this repo:

- [workload/newfraud/11_validate_select_catalog_role.sh](../workload/newfraud/11_validate_select_catalog_role.sh)
- [clients/validate-select-catalog-role-coverage.sql](../clients/validate-select-catalog-role-coverage.sql)

### Mandatory for analyze + propose mode

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

### Recommended for Graph DBA catalog mode

```sql
GRANT SELECT ON DBA_PROPERTY_GRAPHS TO graph_diag_user;
GRANT SELECT ON DBA_PG_ELEMENTS TO graph_diag_user;
GRANT SELECT ON DBA_PG_EDGE_RELATIONSHIPS TO graph_diag_user;
GRANT SELECT ON DBA_TABLES TO graph_diag_user;
GRANT SELECT ON DBA_INDEXES TO graph_diag_user;
GRANT SELECT ON DBA_IND_COLUMNS TO graph_diag_user;
GRANT SELECT ON DBA_TAB_STATISTICS TO graph_diag_user;
GRANT SELECT ON DBA_TAB_COL_STATISTICS TO graph_diag_user;
```

### Recommended for fuller health-check / advisor mode

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

### Optional heavier historical extension

```sql
GRANT SELECT ON DBA_HIST_ACTIVE_SESS_HISTORY TO graph_diag_user;
```

### Installation-only for self-managed ADB Native MCP tools

Prefer a DBA/installer account to create or update `RUN_SQL` in the diagnostic
schema. Grant these to `graph_diag_user` only if that same user must self-install
or self-update the MCP tool:

```sql
GRANT CREATE PROCEDURE TO graph_diag_user;
GRANT EXECUTE ON C##CLOUD$SERVICE.DBMS_CLOUD_AI_AGENT TO graph_diag_user;
```

After installation and validation, revoke installation-only privileges that are
not needed at runtime.

### Optional for baseline / plan management visibility

```sql
GRANT SELECT ON DBA_SQL_PLAN_BASELINES TO graph_diag_user;
```

### Optional if the skill should execute test changes itself

```sql
GRANT CREATE INDEX TO graph_diag_user;
GRANT ALTER SESSION TO graph_diag_user;
GRANT EXECUTE ON DBMS_STATS TO graph_diag_user;
```

## What this mode is

This is the **Graph DBA** mode of the skill.

It is not a business assistant.

It does **not** need deep domain context to start.

Its first job is technical:

- inventory the property graphs in the database
- understand which tables and edges belong to each graph
- assess database health and graph-related pressure
- detect hotspots, waits, plan changes, cursor instability, stale stats, and missing indexes
- propose technical changes with evidence

## Minimal context for the client

The client should provide only the operational context needed to scope the
diagnosis:

- target database and environment classification
- target graph schema or graph name if known
- workload window to analyze
- confirmation that AWR/ASH access is approved

Business taxonomy or detailed product context can help later, but it is not
required for the base Graph DBA workflow.

## Minimum operating model

These are the baseline operational requirements.

### 1. One dedicated technical user per target database

Use one dedicated technical user for the skill in each target database.

That user should be:

- shared by the admin / DBA team
- non-personal
- non-`ADMIN`
- least-privilege
- auditable and rotatable

### 2. MCP connectivity to the database

Supported paths:

- SQLcl MCP
- ADB Native MCP

For multiple databases:

- keep the same skill
- create one MCP entry per database
- only the database endpoint / alias / token changes

### 3. Read-only diagnostic grants

To analyze workload and propose changes, the technical user needs:

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

With this layer, the skill can already:

- analyze top SQL
- inspect execution plans
- detect plan changes and cursor instability
- review waits and DB pressure
- propose changes

## Recommended for full Graph DBA mode

These are not strictly required to start, but they are strongly recommended.

### 4. Cross-schema graph catalog grants

If the client wants the skill to behave as a real **Graph DBA** and start by cataloging all graphs in the database, also grant:

```sql
GRANT SELECT ON DBA_PROPERTY_GRAPHS TO graph_diag_user;
GRANT SELECT ON DBA_PG_ELEMENTS TO graph_diag_user;
GRANT SELECT ON DBA_PG_EDGE_RELATIONSHIPS TO graph_diag_user;
GRANT SELECT ON DBA_TABLES TO graph_diag_user;
GRANT SELECT ON DBA_INDEXES TO graph_diag_user;
GRANT SELECT ON DBA_IND_COLUMNS TO graph_diag_user;
GRANT SELECT ON DBA_TAB_STATISTICS TO graph_diag_user;
GRANT SELECT ON DBA_TAB_COL_STATISTICS TO graph_diag_user;
```

This enables the first DBA step:

- what graphs exist
- who owns them
- which vertex tables and edge tables they use
- row counts
- stats freshness
- FK leading-index gaps on edge tables

Reference asset:

- [sql-templates/01b-graph-dba-catalog.sql](../sql-templates/01b-graph-dba-catalog.sql)

### 5. Full advisor / health-check visibility

Recommended extra visibility:

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

Optional heavier historical extension:

```sql
GRANT SELECT ON DBA_HIST_ACTIVE_SESS_HISTORY TO graph_diag_user;
```

## Native MCP requirements

If the client uses **ADB Native MCP**, prefer a DBA/installer-managed lifecycle
for the MCP tool. Grant these to `graph_diag_user` only if that same user must
self-install or self-update the tool:

```sql
GRANT CREATE PROCEDURE TO graph_diag_user;
GRANT EXECUTE ON C##CLOUD$SERVICE.DBMS_CLOUD_AI_AGENT TO graph_diag_user;
```

And operationally:

- enable the ADB MCP endpoint
- expose a read-only `RUN_SQL` tool
- validate that the MCP tool list exposes only the approved diagnostic tool
- revoke installation-only privileges after validation when they are not needed

## What the skill can do with only the read-only model

With the requirements above, the skill can:

- catalog graphs
- analyze workload
- identify waits, hotspots, plan changes, and cursor instability
- detect missing indexes and stale stats
- propose DDL changes
- define a validation procedure

It does **not** need write privileges to do that.

## Optional mode: validate changes with before/after diff

This is already mapped in the skill.

Reference asset:

- [sql-templates/04-selectivity-and-simulate.sql](../sql-templates/04-selectivity-and-simulate.sql)

Typical flow:

1. capture baseline metrics and current plan
2. apply a candidate change in a safe environment
3. rerun the target query or workload
4. compare before vs after
5. keep or rollback the change

This is useful for:

- invisible indexes
- FK index validation
- filter/composite index validation
- execution-plan comparison

## What is needed if the skill should execute the change itself

This is **optional** and should be allowed only in non-production with explicit approval.

Typical extra privileges depend on the change, for example:

```sql
GRANT CREATE INDEX TO graph_diag_user;
GRANT ALTER SESSION TO graph_diag_user;
GRANT EXECUTE ON DBMS_STATS TO graph_diag_user;
```

Important:

- these privileges are **not** required for analyze/propose mode
- they are only needed if the skill itself will implement the test change

## Recommended client framing

The cleanest way to explain it to the client is:

### Mandatory

- one dedicated technical user per database
- MCP connectivity
- read-only diagnostic grants on performance views

### Recommended

- DBA graph catalog grants
- health-check / AWR visibility
- packaged Native MCP tools

### Optional

- privileges to execute test changes in non-production
- before/after validation workflow managed by the skill

## Repo references

- Minimum prereqs: [docs/diagnostic-mode-minimum-prereqs.md](diagnostic-mode-minimum-prereqs.md)
- Packaged playbooks: [docs/native-mcp-packaged-playbooks.md](native-mcp-packaged-playbooks.md)
- Graph DBA catalog SQL: [sql-templates/01b-graph-dba-catalog.sql](../sql-templates/01b-graph-dba-catalog.sql)
- Simulation / diff path: [sql-templates/04-selectivity-and-simulate.sql](../sql-templates/04-selectivity-and-simulate.sql)
