# Mini-DOWNER Demo Database

Last verified: 2026-06-04

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
- SQL Developer Web:
  `https://JY2OTYFOMIMHAOC-F416HUO273AA732K.adb.sa-saopaulo-1.oraclecloudapps.com/ords/sql-developer`

## MCP client commands

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
- optional plan-instability case `DOWNER_PI_Q01` using `PLAN_INSTABILITY_DEMO`
- dashboard workload procedures and scheduler workers

Use `workload/downer/16_start_dashboard_load_before_long.sql` to start a
120-minute bad-state workload for a live dashboard session.

Use `workload/downer/17_start_dashboard_load_before_5_days.sql` when the demo is
scheduled for a later day and the Performance Hub signal should stay alive for
five consecutive days. This run keeps four database sessions active and can
consume Developer Tier compute while running.

Current run as of 2026-06-04:

- run_id: `5`
- SQL tag: `DOWNER_MI_Q01_DASH_BEFORE`
- status: `RUNNING`
- workers: `4`
- expected end: `2026-06-09 04:32:15 UTC`

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

Do not start `DOWNER_PI_Q01_DASH` while preserving the current
`DOWNER_MI_Q01_DASH_BEFORE` dashboard signal. The shared dashboard loader stops
existing `DDASH_%` workers when a new signal starts, so use these scenarios
sequentially.
