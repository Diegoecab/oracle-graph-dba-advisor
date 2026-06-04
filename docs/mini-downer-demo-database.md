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
- Graph Studio:
  `https://JY2OTYFOMIMHAOC-F416HUO273AA732K.adb.sa-saopaulo-1.oraclecloudapps.com/graphstudio/?sso=true`
- SQL Developer Web:
  `https://JY2OTYFOMIMHAOC-F416HUO273AA732K.adb.sa-saopaulo-1.oraclecloudapps.com/ords/sql-developer`

## Runtime users

- Demo owner schema: `DOWNER_DEMO`
- Diagnostic technical user: `GRAPH_DIAG_USER`
- MCP tool: `RUN_SQL`

Do not store database passwords, wallet passwords, bearer tokens, or wallet ZIPs
in the repo.

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
