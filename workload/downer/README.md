# Mini-DOWNER Graph Workloads

Synthetic ADB-S Always Free workload for the customer-facing Diagnostic Mode demo.

The schema mirrors a small subset of the customer-provided DOWNER metadata:

- vertices: `N_USER`, `N_DEVICE`, `N_BANK_ACCOUNT`, `N_CARD`, `N_IP`
- edges: `E_USES_DEVICE`, `E_WITHDRAWAL_BANK_ACCOUNT`, `E_USES_CARD`, `E_USES_IP`
- graph: `DOWNER_DEMO.DOWNER_GRAPH`

The primary induced issue is deliberate: `E_USES_DEVICE` has no leading index on
`SRC` or `DST`, while the other edge tables do. The tagged query
`DOWNER_MI_Q01` performs a shared-device traversal and should surface full scans
on `E_USES_DEVICE` until the out-of-band invisible indexes are tested.

The secondary induced issue is `DOWNER_SN_Q01`, a supernode / fan-out scenario.
It prepares `D00000001` as a high-degree shared fingerprint and uses indexed
traversal paths so the dominant problem is path expansion, not a simple missing
index.

The third induced issue is `DOWNER_PI_Q01`, a plan-instability scenario. It uses
a skewed Mini-DOWNER risk lookup query with one stable SQL text and controlled
optimizer environments so the same logical query can show child cursor churn,
plan hash drift, and elapsed-time deviation.

Execution order:

1. Run `00_create_users.sql` as `ADMIN`, passing strong lab passwords:
   `@workload/downer/00_create_users.sql "<downer_password>" "<graph_diag_password>"`.
   This also grants `GRAPH_DEVELOPER` and
   `ALTER USER DOWNER_DEMO GRANT CONNECT THROUGH GRAPH$PROXY_USER` so
   database-user login works in Graph Studio.
2. Connect as `DOWNER_DEMO` and run `01_create_schema.sql`.
3. Run `02_create_property_graph.sql`.
4. Run `03_generate_data.sql`.
5. Run `04_workload_queries.sql` for visible SQL examples.
6. Run `05_run_workload.sql` to seed `V$SQL` with `DOWNER_MI_Q01`.
7. Run `06_lab_summary.sql` for object/count validation.
8. Run `07_grant_diagnostic_access.sql` as `ADMIN`.
9. Register `RUN_SQL` as `GRAPH_DIAG_USER` using `clients/adb-native-run-sql-readonly.sql`.
10. Run `08_missing_index_mcp_demo.sh` from WSL/bash to exercise the read-only pack.
11. Optionally run `09_invisible_index_validation.sql` as `DOWNER_DEMO` for lab-only remediation proof.
12. To prepare the supernode scenario, run `18_setup_supernode_fanout.sql`, then
    `19_run_supernode_workload.sql` to seed `V$SQL` with `DOWNER_SN_Q01`.
13. For a live ADB Performance Dashboard demo, run `10_dashboard_load_setup.sql`, then `11_start_dashboard_load_before.sql`.
    For a longer customer demo window, use `16_start_dashboard_load_before_long.sql`.
    To keep the dashboard signal alive across several days, use `17_start_dashboard_load_before_5_days.sql`.
14. For the supernode dashboard signal, run `20_start_dashboard_load_supernode.sql`.
15. To prepare the plan-instability scenario, run
    `21_grant_plan_instability_extras.sql` as `ADMIN`, then
    `22_setup_plan_instability.sql` and `23_run_plan_instability_workload.sql`
    as `DOWNER_DEMO`.
16. For the plan-instability dashboard signal, run
    `24_start_dashboard_load_plan_instability.sql`.
17. After the advisor recommendation, run `14_apply_visible_index_fix.sql`, then `12_start_dashboard_load_after.sql`.
18. Stop or clean up with `13_stop_dashboard_load.sql` and `15_rollback_visible_index_fix.sql`.

The PowerShell helper can include the plan-instability setup with
`-SetupPlanInstability`. Use `-StartPlanInstabilityDashboardLoad` only when the
dashboard should focus on `DOWNER_PI_Q01_DASH` instead of the missing-index
signal.

`03_generate_data.sql` seeds `DBMS_RANDOM` for reproducible data and uses a
compact default volume: 12k users, 1.2k devices, and about 155k total edges.
Increase `scale_factor` only when the ADB has room for a larger diagnostic
sample.

## Performance Dashboard choreography

The dashboard workload uses `DBMS_SCHEDULER` jobs inside ADB, with a conservative
default of 4 workers for 12 minutes. For a live customer demo, the long-run
script starts the same workload for 120 minutes. For next-day prep, the five-day
script keeps the same bad-state signal running for 7200 minutes. This keeps the
demo under the Always Free session limit while producing active SQL load that
can appear in Performance Dashboard, Performance Hub, ASH, and `V$SQL`.

If `DOWNER_DEMO` was created before `00_create_users.sql` included scheduler
privileges, run this once as `ADMIN`:

```sql
GRANT CREATE JOB TO DOWNER_DEMO;
```

If Graph Studio reports `Missing GRAPH_DEVELOPER role` or asks to grant proxy
connection through `GRAPH$PROXY_USER`, run this once as `ADMIN`:

```sql
GRANT GRAPH_DEVELOPER TO DOWNER_DEMO;
ALTER USER DOWNER_DEMO DEFAULT ROLE ALL;
ALTER USER DOWNER_DEMO GRANT CONNECT THROUGH GRAPH$PROXY_USER;
```

Run once as `DOWNER_DEMO`:

```sql
@workload/downer/10_dashboard_load_setup.sql
```

Start the bad-state load:

```sql
@workload/downer/11_start_dashboard_load_before.sql
```

Start a longer bad-state load for a live dashboard session:

```sql
@workload/downer/16_start_dashboard_load_before_long.sql
```

Start a five-day bad-state load when the demo is scheduled for a later day:

```sql
@workload/downer/17_start_dashboard_load_before_5_days.sql
```

The five-day run is useful only for lab/demo environments. It keeps four
database sessions active and can consume Developer Tier compute while running.

Dashboard filters/signals:

- Module: `MINI_DOWNER_DASHBOARD_LOAD`
- SQL text tag: `DOWNER_MI_Q01_DASH_BEFORE`
- Expected symptom: `E_USES_DEVICE` full scans, higher elapsed time and buffer gets

After the skill identifies the missing leading indexes, apply the lab-only fix
outside the MCP runtime:

```sql
@workload/downer/14_apply_visible_index_fix.sql
@workload/downer/12_start_dashboard_load_after.sql
```

Dashboard after-fix tag:

- SQL text tag: `DOWNER_MI_Q01_DASH_AFTER`
- Expected signal: lower per-execution elapsed time and buffer gets; the SQL may
  also become less visible in Top SQL because it is no longer the dominant load.

Stop the load:

```sql
@workload/downer/13_stop_dashboard_load.sql
```

Rollback the lab-only visible indexes:

```sql
@workload/downer/15_rollback_visible_index_fix.sql
```

## Supernode / fan-out scenario

Prepare the high-degree device and supporting indexed access paths:

```sql
@workload/downer/18_setup_supernode_fanout.sql
```

Seed the SQL cache:

```sql
@workload/downer/19_run_supernode_workload.sql
```

Dashboard run:

```sql
@workload/downer/20_start_dashboard_load_supernode.sql
```

Dashboard filters/signals:

- Module: `MINI_DOWNER_DASHBOARD_LOAD`
- SQL text tag: `DOWNER_SN_Q01_DASH`
- Anchor device: `D00000001`
- Expected symptom: high rows processed and buffer gets caused by a high-degree
  device expanding to many users and bank-account paths.

The corresponding read-only diagnostic templates are in
`sql-templates/packs/supernode-fanout/`. The expected recommendation is not
"add another index" by default. The advisor should first verify index coverage
and then focus on degree-aware query guards, traversal constraints, precomputed
features, or identifier/model cleanup.

## Plan-instability scenario

Prepare the setup-only privilege and skewed lookup table:

```sql
@workload/downer/21_grant_plan_instability_extras.sql
@workload/downer/22_setup_plan_instability.sql
```

Seed the SQL cache:

```sql
@workload/downer/23_run_plan_instability_workload.sql
```

Dashboard run:

```sql
@workload/downer/24_start_dashboard_load_plan_instability.sql
```

Only one dashboard signal is active by default. Starting this script calls the
same loader used by the other scenarios and stops any existing `DDASH_%`
workers before launching the plan-instability workers.

Optional read-only MCP runner:

```bash
workload/downer/25_plan_instability_mcp_demo.sh
```

Dashboard filters/signals:

- Module: `MINI_DOWNER_PLAN_INSTABILITY`
- SQL text tag: `DOWNER_PI_Q01` or `DOWNER_PI_Q01_DASH`
- Expected symptom: one logical SQL shows multiple child cursors, potentially
  multiple plan hashes, and a large spread between child-cursor average elapsed
  time or buffer gets.

The corresponding read-only diagnostic templates are in
`sql-templates/packs/plan-instability/`. The expected recommendation is not an
immediate index. The advisor should identify the unstable SQL, quantify plan
and elapsed deviation, explain the child-cursor or optimizer-environment
signal, and recommend DBA-controlled stabilization such as bind discipline,
stats review, SQL Plan Management, or query shape hardening.
