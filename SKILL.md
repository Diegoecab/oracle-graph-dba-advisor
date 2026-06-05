---
name: oracle-graph-dba-advisor
description: Diagnose Oracle SQL/PGQ property graph performance using read-only SQL evidence, packaged templates, and recommendations for ADB Native MCP or SQLcl MCP.
---

# Oracle Graph DBA Advisor

Use this skill when the user asks to diagnose, review, or optimize Oracle
SQL/PGQ or Property Graph workloads on Oracle Database 23ai or 26ai.

## Load Order

1. Read `SYSTEM_PROMPT.md` first. It is the authoritative methodology, safety
   policy, diagnostic path selection guide, and output contract.
2. Before producing a customer-facing diagnostic report, read
   `reporting/diagnostic-report-template.md` and follow it exactly.
3. Load only the supporting files needed for the current request:
   - `phases/` for the current diagnostic phase.
   - `sql-templates/` for executable read-only SQL templates.
   - `sql-templates/packs/` only after evidence justifies a specialized pack.
   - `knowledge/` for versioned graph, optimizer, and design guidance.
   - `workload/` and `docs/` only when the user explicitly asks for setup,
     reproduction, or out-of-band validation runbooks.
   Do not run recursive globs over all pack SQL files. If pack inventory is
   needed, list immediate pack directories, then open only the selected pack
   README and specific numbered templates justified by evidence.

## Runtime Rules

- Select the database MCP target before workload analysis. If multiple database
  MCP servers or SQL connections are visible and the user did not name an exact
  target, list the visible database candidates and ask the user to choose one
  before executing SQL.
- Treat unauthenticated ADB Native MCP servers that expose only
  `authenticate`/`authorize` as database candidates with status
  `needs authentication`; do not filter them out and auto-select another ready
  ADB alias unless the user named that alias exactly.
- If the user names an alias that is not visible, do not guess. Show visible
  database candidates or close matches and ask for explicit confirmation.
- Confirm the active database context on the selected target before workload
  analysis.
- Keep diagnostics read-only. Generate DDL recommendations as text with
  validation and rollback; do not execute DDL/DML through the diagnostic MCP
  channel.
- Use packaged SQL templates for health checks and diagnostics. Do not
  improvise extra dynamic performance view probes during customer-facing
  diagnosis unless the user explicitly asks for a metric outside the pack.
- If the MCP user is a technical diagnostic account and the graph belongs to a
  different owner, use the packaged DBA/cross-schema templates such as
  `sql-templates/01b-graph-dba-catalog.sql` and
  `sql-templates/02a-identify-dba.sql`. Do not rewrite `USER_PG_ELEMENTS`
  identify templates ad hoc.
- During Phase 0, run only default `HEALTH-*` blocks. Do not run `OPTIONAL-*`
  health probes such as `OPTIONAL-02C` / `V$SYS_TIME_MODEL` unless the user
  explicitly asks for that metric.
- Do not select `missing-index`, `supernode-fanout`, `plan-instability`, or any
  other specialized pack from a demo/workload name alone. Run general triage
  first and select the pack only when the SQL, plan, wait, and object metadata
  support it.
- For broad prompts such as "the graph is slow" or "the graph workload is slow",
  inspect multiple relevant SQL statements and report diagnostic coverage
  across missing-index, supernode/fan-out, plan-instability, and any other
  supported classes before concluding.
- Plan Stability is a SQL workload property, not a SQL/PGQ-only property. Do
  not skip the `plan-instability` pack merely because the relevant SQL is not a
  `GRAPH_TABLE` statement. Include non-graph SQL only when it is linked to the
  graph workload by backing tables, module/action, SQL tag, procedure, schema,
  incident window, or user-provided workload scope.
- Do not mark Plan Stability as `SKIPPED` based only on the hot SQL_IDs already
  selected for indexing or fan-out findings. First run the generic workload
  instability candidate search from `sql-templates/packs/plan-instability/`
  across the discovered workload scope.
- For Plan Stability coverage, start with only
  `sql-templates/packs/plan-instability/00-workload-instability-candidates.sql`.
  Load the rest of the plan-instability pack only if that query returns
  supporting evidence.
- `DBA_SQL_PLAN_BASELINES` is part of the full advisor-mode grant baseline for
  SQL Plan Management visibility. Do not query it during broad triage; use it
  only when SQL Plan Management state is in scope or after evidence supports a
  plan-control recommendation. If it is not visible, report `Not visible with
  current grants` and continue without it.
- Use the `SYSTEM_PROMPT.md` output contract and
  `reporting/diagnostic-report-template.md` exactly in every client: connected
  context, workload scope, top SQL classification, findings, diagnostic
  coverage, recommendations, and a final `Recommendation Summary` table. Do not
  omit diagnostic coverage just because only one finding is detected.
- Default to `quick-win` report mode for ordinary performance prompts: print
  high-impact/high-priority findings and first actions only, while keeping
  broader coverage internal and summarized. Use `extended` mode only when the
  user asks for full evidence, all checked categories, skipped rows, exact SQL
  scripts, rollback commands, or a DBA handoff.
- In the top SQL table, use the generic column `Workload Context`, not
  demo-specific labels, and always show `Executions`, `Total Elapsed (s)`, and
  `Avg Elapsed (ms/exec)` per SQL_ID when visible.
- Use customer-facing coverage labels such as `Found`,
  `Checked - no supporting evidence`, `Not visible with current grants`, and
  `Blocked by access`; never print internal status codes in the report.
- In the final `Recommendation Summary`, use the canonical category names from
  `SYSTEM_PROMPT.md`; use only the columns from
  `reporting/diagnostic-report-template.md`, include `Impact`, `Effort`, and
  `Priority`. In `quick-win` mode, include only actionable quick wins and any
  blocker that changes the first action; do not include the full `SKIPPED`
  coverage tail. In `extended` mode, put actionable rows first and include
  concise `SKIPPED` coverage rows for supported categories checked with no
  supporting evidence. In `quick-win` mode, one short follow-up question after
  the final table may ask whether the user wants the extended report.
- When recommending out-of-band DBA validation, provide exact step-by-step SQL
  commands before the final summary in `extended` mode or when the user asks
  for exact commands. In `quick-win` mode, provide the shortest safe validation
  approach for non-indexing recommendations. Exception: actionable `Indexing`
  recommendations must include the exact DBA validation runbook even in
  `quick-win` mode because that is usually the first DBA action.
  Do not stop at generic text such as "create invisible indexes and compare".
  For actionable `Indexing`, include two labeled paths when object names are
  known: direct visible `CREATE INDEX` plus before/after verification for
  approved dev/test, and controlled invisible-index validation plus promotion
  and rollback for production/pre-prod.
- Do not leave `:sqlid`, `:child`, `TARGET_SQL_ID`, or similar placeholders in
  user-facing validation SQL when the diagnosis has already identified the
  SQL_ID or child cursor. Use literal values, or include an exact child-resolver
  query and then the `DBMS_XPLAN.DISPLAY_CURSOR` command. Never use
  `DISPLAY_CURSOR()` without explicit `SQL_ID` and `CHILD_NUMBER`; resolve the
  cursor by SQL marker when validating a newly executed statement. For index
  validation, include executable SQL to compare baseline vs after cursor metrics
  and plan operations, either after immediate validation SQL or after the
  application reruns the statement. Do not say "re-run the SQL_ID" or "use this
  value as :ANCHOR_ID"; print the
  executable target SQL with exact bind setup or resolved literal values. Do not
  assume demo-specific bind names, bind datatypes, table names, labels, or graph
  names; derive them from SQL text, bind capture, catalog metadata, and pack
  evidence.
- Before recommending permanent indexes, collect visible DML/write-rate evidence
  yourself when the read-only grants allow it; do not merely tell the user to
  confirm INSERT rate. If the evidence is not visible, state that limitation.
- If the DML evidence template cannot access `DBA_TAB_MODIFICATIONS`, use the
  packaged visible-SQL fallback instead of stopping the diagnosis. Treat the
  missing grant as an evidence limitation, not as a performance finding, and
  make DBA workload confirmation a prerequisite for a permanent visible index
  change.
- Use `R1`, `R2`, etc. consistently in detailed recommendations and the final
  table. Do not use `P1/P2` for user-facing recommendations.
- For supernode/fan-out findings, provide concrete `AS-IS` and `TO-BE` query or
  feature-table examples, plus rollback/exit criteria.
- Do not infer a supernode/fan-out finding from average degree alone. Use the
  supernode pack only when skew/outlier evidence or measured path expansion
  supports it, such as anchor degree versus P95/P99, max-to-P95 ratio,
  high actual rows, or excessive intermediate rows for the candidate SQL.
- During diagnosis, treat the connected workload as a real incident. Do not call
  it a demo/lab or reference repository runbooks unless the user explicitly asks
  for setup or out-of-band validation commands.
