# Native MCP Packaged Playbooks

Short operational note for the client-facing diagnostic mode.

## What is runtime vs lab

Runtime packaged assets:

- `clients/adb-plan-instability-tool-pack-poc.sql`
- `clients/adb-performance-diagnostic-tool-packs-poc.sql`

These are the packaged database-side playbooks. They register MCP-callable tools inside ADB and are the pieces that matter for the skill runtime.

Lab / validation harness only:

- `workload/newfraud/08_plan_instability_demo.sh`
- `workload/newfraud/09_native_mcp_tool_pack_poc.sh`
- `workload/newfraud/10_native_mcp_perf_tool_packs_poc.sh`

These shell scripts are only used to install, replay workload, and validate the packs in the test database. They are not part of the client runtime model.

## Recommended packaged playbooks

1. `GA_TOP_SQL_SUMMARY`
   DB-wide top degraded SQL by elapsed time, CPU, and buffer gets from `V$SQLSTATS`.

2. `GA_TOP_SQL_DETAIL`
   Current cursor detail for one `SQL_ID` from `V$SQL`.

3. `GA_ASH_SQL_HOTSPOTS`
   Recent active SQL hotspots from `V$ACTIVE_SESSION_HISTORY`.

4. `GA_ASH_WAIT_PROFILE`
   Recent wait profile by wait class / `ON CPU` from `V$ACTIVE_SESSION_HISTORY`.

5. `GA_PLAN_CHANGE_SUMMARY`
   Recent multi-plan candidates from `V$SQLAREA_PLAN_HASH`.

6. `GA_PLAN_CHANGE_DETAIL`
   Per-plan evidence for one `SQL_ID` from `V$SQLAREA_PLAN_HASH`.

7. `GA_DB_WAIT_EVENTS_SUMMARY`
   DB-wide foreground wait-event summary from `V$SYSTEM_EVENT`.

8. `GA_PLAN_INSTABILITY_SUMMARY`
   Cursor-instability candidates from `V$SQL`.

9. `GA_SQL_CHILD_DETAIL`
   Child-cursor drill-down for one `SQL_ID`.

10. `GA_SQL_PLAN_EVIDENCE`
    Shared-cursor reasons and plan-hash evidence for one `SQL_ID`.

## How to use them well

- For a broad admin view, start with `GA_TOP_SQL_SUMMARY`, `GA_ASH_SQL_HOTSPOTS`, and `GA_DB_WAIT_EVENTS_SUMMARY`.
- For transient problems, prefer the `ASH` playbooks over heavier historical queries.
- For cursor churn or plan regressions, switch to the plan-instability / plan-change playbooks.
- If you already know the workload signature, pass `sql_text_filter` so the pack narrows to the graph/application SQL instead of generic database activity.

## Packaging rule

If a scenario is important and repeatable, it should become a packaged database-side tool.

If a scenario is exploratory or one-off, it can stay on `RUN_SQL`.

The target state is:

- packaged tools for high-value repeatable diagnostics
- `RUN_SQL` only as fallback
- no ad hoc diagnostic SQL invented live during a customer demo
