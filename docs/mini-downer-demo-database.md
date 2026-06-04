# Mini-DOWNER Demo Database

Last verified: 2026-06-04

Runtime update verified: 2026-06-04. `RUN_SQL` was replaced with the
literal-aware guard from `clients/adb-native-run-sql-readonly.sql` and validated
directly in the ADB.

This file is the operational source of truth for Mini-DOWNER. If another agent,
memory note, or local MCP config says the Mini-DOWNER target is `GADVDOWNERAF`,
`us-ashburn-1`, `graph-advisor-newfraud`, or an Ashburn OCID, that information
is stale unless this file has been intentionally updated to match it.

## OCI target

- Tenancy: `latinoamerica`
- OCI CLI profile: `LATINOAMERICA_APIKEY`
- Region: `sa-saopaulo-1`
- Compartment OCID: `ocid1.compartment.oc1..aaaaaaaaioa5ygpgefztw4ijt2epf5wmoygclpoqbm3wwlpfy7tpp2kdxtza`
- Autonomous Database OCID: `ocid1.autonomousdatabase.oc1.sa-saopaulo-1.antxeljrfioir7iauszrvqwbv6dsu5pybolkiidctbm53wjecldafli5xmsa`
- DB name: `F416HUO273AA732K`
- Display name: `F416HUO273AA732K`
- Database version: `26ai`
- Workload type: Transaction Processing / `OLTP`
- Tier: Developer Tier, not Always Free
- Compute: 4 ECPUs
- Storage: 20 GB

## URLs

- ADB Native MCP endpoint:
  `https://dataaccess.adb.sa-saopaulo-1.oraclecloudapps.com/adb/mcp/v1/databases/ocid1.autonomousdatabase.oc1.sa-saopaulo-1.antxeljrfioir7iauszrvqwbv6dsu5pybolkiidctbm53wjecldafli5xmsa`
- ADB Native MCP token endpoint:
  `https://dataaccess.adb.sa-saopaulo-1.oraclecloudapps.com/adb/auth/v1/databases/ocid1.autonomousdatabase.oc1.sa-saopaulo-1.antxeljrfioir7iauszrvqwbv6dsu5pybolkiidctbm53wjecldafli5xmsa/token`
- Graph Studio, database user login for `DOWNER_DEMO`:
  `https://JY2OTYFOMIMHAOC-F416HUO273AA732K.adb.sa-saopaulo-1.oraclecloudapps.com/graphstudio/`
- Graph Studio, OCI SSO launch:
  `https://JY2OTYFOMIMHAOC-F416HUO273AA732K.adb.sa-saopaulo-1.oraclecloudapps.com/graphstudio/?sso=true`
- Database Actions SQL / SQL Developer Web, for applying approved DBA
  validation or remediation scripts outside the read-only MCP channel:
  `https://JY2OTYFOMIMHAOC-F416HUO273AA732K.adb.sa-saopaulo-1.oraclecloudapps.com/ords/sql-developer`

This demo ADB is public. If a future lab or customer ADB uses Private Endpoint,
the MCP URL format changes only in the host:

```text
https://<hostname_prefix>.adb.<region>.oraclecloudapps.com/adb/mcp/v1/databases/<adb-ocid>
```

The client running Claude/Codex must be on the VCN or a connected network path
that can resolve and reach the private hostname. Keep the private hostname in
the MCP URL; do not replace it with `localhost`, a raw private IP, or a proxy
hostname.

## MCP client commands

If more than one ADB MCP is configured in the client, the skill should not guess
the target. It should list the visible database MCP candidates and ask the user
to choose one unless the prompt names `graph-mini-fraud-downer-26ai` exactly.
For gate testing, this repo also defines
`graph-mini-fraud-downer-26ai-shadow`, pointing to the same ADB endpoint.
If the shadow alias is not authenticated, it may expose only `authenticate`.
That still counts as an ADB MCP candidate with status `needs authentication`;
the skill should not filter it out and auto-select the primary alias unless the
prompt named the primary alias exactly.

Claude Code OAuth/no-bearer:

```powershell
claude mcp add --transport http --scope user `
  graph-mini-fraud-downer-26ai `
  "https://dataaccess.adb.sa-saopaulo-1.oraclecloudapps.com/adb/mcp/v1/databases/ocid1.autonomousdatabase.oc1.sa-saopaulo-1.antxeljrfioir7iauszrvqwbv6dsu5pybolkiidctbm53wjecldafli5xmsa"
```

When Claude Code prints the authorization URL, open it in a browser and sign in
with `GRAPH_DIAG_USER`. The OAuth callback is local to the Claude Code session.

Codex bearer-token mode:

```powershell
codex mcp add graph-mini-fraud-downer-26ai `
  --url "https://dataaccess.adb.sa-saopaulo-1.oraclecloudapps.com/adb/mcp/v1/databases/ocid1.autonomousdatabase.oc1.sa-saopaulo-1.antxeljrfioir7iauszrvqwbv6dsu5pybolkiidctbm53wjecldafli5xmsa" `
  --bearer-token-env-var ADB_MCP_TOKEN
```

Bearer tokens are valid for 1 hour from issuance. Refresh `ADB_MCP_TOKEN`
immediately before a live demo if using Codex or any static bearer-token client.
Claude Code OAuth/no-bearer mode avoids manual token refresh by running the
browser authorization flow.

If Claude Code reports new credentials but rejects them on reconnect, verify the
MCP entry has no stale bearer header:

```powershell
claude mcp get graph-mini-fraud-downer-26ai
```

For OAuth/no-bearer mode, the output should not include `Authorization`. If it
does, remove and re-add the MCP without headers:

```powershell
claude mcp remove graph-mini-fraud-downer-26ai --scope user
claude mcp add --transport http --scope user `
  graph-mini-fraud-downer-26ai `
  "https://dataaccess.adb.sa-saopaulo-1.oraclecloudapps.com/adb/mcp/v1/databases/ocid1.autonomousdatabase.oc1.sa-saopaulo-1.antxeljrfioir7iauszrvqwbv6dsu5pybolkiidctbm53wjecldafli5xmsa"
claude mcp get graph-mini-fraud-downer-26ai
```

The `get` output should show no `Authorization` header. Then restart Claude
Code, run `/mcp`, and authenticate with `GRAPH_DIAG_USER`.

## Runtime users

- Demo owner schema: `DOWNER_DEMO`
- Diagnostic technical user: `GRAPH_DIAG_USER`
- MCP tool: `RUN_SQL`
- Graph Studio role for the owner schema: `GRAPH_DEVELOPER`
- Graph Studio proxy grant:
  `ALTER USER DOWNER_DEMO GRANT CONNECT THROUGH GRAPH$PROXY_USER`
- `RUN_SQL` runtime: literal-aware read-only guard. It blocks DDL, DML,
  PL/SQL, comments, statement terminators, `SELECT FOR UPDATE`, and
  side-effect packages outside string literals, while allowing recommendation
  text literals that contain words such as `CREATE INDEX` or `DROP INDEX`.
- `SYS.V_$SYS_TIME_MODEL` is required only if the demo scope includes DB time
  vs DB CPU breakdown through `OPTIONAL-02C`. If that evidence is expected,
  request/apply `GRANT SELECT ON SYS.V_$SYS_TIME_MODEL TO GRAPH_DIAG_USER`.
  If the grant is not approved or `RUN_SQL` returns ORA-00942 for that view, do
  not stop the diagnosis; skip `OPTIONAL-02C` and continue with the default
  `HEALTH-*` path.

DB time model grant update from 2026-06-04:

- applied `GRANT SELECT ON SYS.V_$SYS_TIME_MODEL TO GRAPH_DIAG_USER`
- verified in `DBA_TAB_PRIVS`
- verified through the real diagnostic path:
  `GRAPH_DIAG_USER.RUN_SQL('SELECT COUNT(*) AS TOTAL_ROWS FROM V$SYS_TIME_MODEL', 0, 10)`
  returned `TOTAL_ROWS=15`

Validation evidence from 2026-06-04:

- accepted `SELECT` returning a text literal containing `CREATE INDEX`,
  `DROP INDEX`, `SELECT FOR UPDATE`, `--`, and `;`
- rejected real `CREATE TABLE`
- rejected `--` comment outside a string literal

Do not store database passwords, wallet passwords, bearer tokens, or wallet ZIPs
in the repo.

## Update the skill before rerunning analysis

If the advisor code or plugin version changed, update the client-side
skill/plugin before rerunning the Mini-DOWNER analysis. The ADB MCP entry does
not need to be recreated unless the endpoint, MCP name, or authentication mode
changed.

Claude Code:

```powershell
claude plugin marketplace update oracle-graph-dba-advisor
claude plugin update oracle-graph-dba-advisor@oracle-graph-dba-advisor --scope user
claude plugin list --json
```

Then restart Claude Code and confirm it loads the new plugin version in the
first response.

Codex:

```powershell
codex plugin marketplace upgrade oracle-graph-dba-advisor
```

If Codex reports that the marketplace is not configured as a Git marketplace,
add the GitHub marketplace again and restart Codex:

```powershell
codex plugin marketplace add Diegoecab/oracle-graph-dba-advisor
```

Claude Desktop / claude.ai uploaded skill:

1. Rebuild the ZIP from the current repository version.
2. Upload it again in `Customize > Skills`.
3. Confirm the ADB MCP connector is enabled in the chat.

## Required tags

Defined tags in `0-ResourceControl`:

```text
DeleteResource=WeeklyDeleteResourceNo
ShutdownResource=NightlyShutdownNo
KeepResource=Mini-DOWNER demo ADB - preserve for customer demo
ShutdownTime=Manual only
Team=To_be_Assigned
```

Freeform tags:

```text
adb$feature={"name":"mcp_server","enable":true}
```

## Current demo state

The Mini-DOWNER setup creates:

- `DOWNER_DEMO.DOWNER_GRAPH`
- node tables `N_USER`, `N_DEVICE`, `N_BANK_ACCOUNT`, `N_CARD`, `N_IP`
- edge tables `E_USES_DEVICE`, `E_WITHDRAWAL_BANK_ACCOUNT`, `E_USES_CARD`, `E_USES_IP`
- deliberate missing leading indexes on `E_USES_DEVICE.SRC` and `E_USES_DEVICE.DST`
- coexisting supernode/fan-out evidence on indexed `E_USES_IP`, anchored at
  `IP00000001`
- optional plan-instability case `DOWNER_PI_Q01` using `PLAN_INSTABILITY_DEMO`
- dashboard workload procedures and scheduler workers

The current demo runbook supports three positive issue classes:

- R1/R2 missing-index: `DOWNER_MI_Q01*`, remediated by validating
  `E_USES_DEVICE(SRC, END_DATE, DST)` and
  `E_USES_DEVICE(DST, END_DATE, SRC)` with invisible indexes.
- R3 supernode/fan-out: `DOWNER_SN_Q01*`, remediated by routing high-degree
  identifiers through `DOWNER_IP_FANOUT_FEATURES` instead of doing the full
  online graph traversal.
- R4 plan-instability: `DOWNER_PI_Q01*`, remediated first by stabilizing input
  and optimizer environment; DBA-controlled SQL Plan Management is reserved for
  cases where a single better plan is proven.

The final advisor `Recommendation Summary` should still show the broader
category coverage tail. In this Mini-DOWNER database, the positive rows should
come from `Indexing`, `Supernode/Fan-out`, and `Plan Stability` when the
coexistence workload is visible. Other categories such as
`Statistics & Optimizer`, `Query Rewriting`, `Graph Design / Modeling`,
`Schema & Architecture`, `Resource / Health`, and `Auto Indexing` should appear
as concise `SKIPPED` rows unless their own evidence is visible. Positive rows
should include `Impact`, `Effort`, and `Priority` so the table is decision
ready:

- missing-index rows: usually `Impact=High`, `Effort=Medium`,
  `Priority=High` when the top SQL still shows full scans on
  `E_USES_DEVICE`.
- supernode/fan-out row: usually `Impact=High`, `Effort=Medium`,
  `Priority=High` when the high-degree anchor dominates a visible workload
  query.
- plan-instability row: usually `Impact=Medium`, `Effort=Medium`,
  `Priority=Medium` unless one unstable SQL is the dominant workload driver.
- checked categories without evidence: `Impact=None`, `Effort=None`,
  `Priority=Skip`.

Use `workload/downer/16_start_dashboard_load_before_long.sql` to start a
120-minute bad-state workload for a live dashboard session.

Use `workload/downer/17_start_dashboard_load_before_5_days.sql` when the demo is
scheduled for a later day and the Performance Hub signal should stay alive for
five consecutive days. This run keeps four database sessions active and can
consume Developer Tier compute while running.

Use `workload/downer/27_start_dashboard_load_all_issues_5_days.sql` when the
demo should show all three coexistence signals at once: missing-index,
supernode/fan-out, and plan-instability.

Out-of-band validation scripts:

- `workload/downer/28_missing_index_exact_plan_validation.sql`: exact
  `EXPLAIN PLAN`, baseline run, invisible-index run, and visible-index command.
- `workload/downer/29_supernode_feature_mitigation_validation.sql`: online
  traversal vs precomputed feature lookup.
- `workload/downer/30_plan_instability_stabilization_validation.sql`: unstable
  optimizer environment vs stable execution pattern.

Current run as of 2026-06-04:

- run_id `9`: `DOWNER_MI_Q01_DASH_BEFORE`, status `RUNNING`, workers `2`
- run_id `10`: `DOWNER_SN_Q01_DASH`, status `RUNNING`, workers `1`
- run_id `11`: `DOWNER_PI_Q01_DASH`, status `RUNNING`, workers `1`
- expected end: `2026-06-09 19:19:10 UTC`

Validation evidence from the 2026-06-04 refresh:

- `DOWNER_MI_Q01_DASH_BEFORE`: SQL_ID `7dyt3c6xcjg76` still shows two
  `TABLE ACCESS FULL` operations on `DOWNER_DEMO.E_USES_DEVICE`, cost `478`,
  average buffer gets around `1755` per execution.
- `DOWNER_SN_Q01_DASH`: anchor `IP00000001` has active in-degree `12007`;
  the online traversal expands to about `118599` joined bank-account paths and
  currently averages about `90 ms` in the grouped fan-out query.
- `DOWNER_PI_Q01_DASH`: plan-instability evidence is positive. SQL_ID
  `fhvn4b3bguvvr` shows `2` child cursors, `2` distinct plan hashes, optimizer
  modes `ALL_ROWS,FIRST_ROWS`, and elapsed ratio about `55x`. SQL_ID
  `fcs0b3h0xkh06` also shows `3` child cursors, `2` plan hashes, bind-aware
  execution, and elapsed ratio about `2.37x`.

Do not execute the out-of-band remediation validation scripts before the
customer-facing diagnosis unless the purpose is to show the post-analysis
validation step. They are intentionally outside the read-only MCP channel.

## Optional plan-instability signal

The demo can also seed a query-specific plan-instability case:

- setup scripts: `workload/downer/21_grant_plan_instability_extras.sql`,
  `22_setup_plan_instability.sql`
- workload script: `workload/downer/23_run_plan_instability_workload.sql`
- dashboard script: `workload/downer/24_start_dashboard_load_plan_instability.sql`
- read-only pack runner: `workload/downer/25_plan_instability_mcp_demo.sh`
- SQL tag: `DOWNER_PI_Q01`
- dashboard tag: `DOWNER_PI_Q01_DASH`

Use this after capturing the missing-index evidence if the demo narrative needs
to show one SQL with child cursor churn, plan hash drift, and elapsed-time
deviation. The diagnostic path must select `plan-instability` only after seeing
evidence of multiple child cursors, multiple plan hashes, invalidations, bind
mismatch, or elapsed spread for the same SQL.

The standard single-signal scripts still stop existing `DDASH_%` workers when a
new signal starts. Use `27_start_dashboard_load_all_issues_5_days.sql` when all
three signals must remain active together.
