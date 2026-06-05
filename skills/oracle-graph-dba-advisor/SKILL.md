---
name: oracle-graph-dba-advisor
description: Diagnose Oracle SQL/PGQ property graph performance using read-only SQL evidence, packaged templates, and recommendations for ADB Native MCP or SQLcl MCP.
---

# Oracle Graph DBA Advisor

Use this skill when the user asks to diagnose, review, or optimize Oracle
SQL/PGQ or Property Graph workloads, especially through ADB Native MCP or SQLcl
MCP.

Before running diagnostics, read the packaged methodology. It is the single
source of truth for safety gates, diagnostic path selection, phase order, and
output format:

- `../../SYSTEM_PROMPT.md`
- `../../reporting/diagnostic-report-template.md` before producing a
  customer-facing diagnostic report

Load supporting files only when needed:

- `../../phases/` for the current diagnostic phase
- `../../sql-templates/` for executable read-only SQL templates
- `../../sql-templates/packs/` after evidence justifies a specialized pack
- `../../knowledge/` for versioned graph, optimizer, and design guidance

For setup, reproduction, or out-of-band validation requests, `../../workload/`
and `../../docs/` may provide runbook context. Do not use those files as
diagnostic evidence during normal workload analysis unless the user explicitly
asks for setup or validation commands.

Before executing SQL, select the database MCP target. If multiple database MCP
servers or SQL connections are visible and the user did not name an exact
target, list the visible database candidates and ask the user to choose one. If
the user names an alias that is not visible, do not guess; show visible
candidates or close matches and ask for explicit confirmation. If no Oracle SQL
channel is visible, stop and explain that the database MCP connector is missing.
Treat unauthenticated ADB Native MCP servers that expose only
`authenticate`/`authorize` as database candidates with status
`needs authentication`; do not filter them out and auto-select another ready ADB
alias unless the user named that alias exactly.
After selecting a target, confirm the active database context there before any
workload analysis.

If the MCP user is a technical diagnostic account and the graph belongs to a
different owner, use the packaged DBA/cross-schema templates such as
`../../sql-templates/01b-graph-dba-catalog.sql` and
`../../sql-templates/02a-identify-dba.sql`. Do not rewrite `USER_PG_ELEMENTS`
identify templates ad hoc.

Do not choose `missing-index`, `supernode-fanout`, `plan-instability`, or any
other specialized pack from a workload name, graph name, schema name, SQL tag,
or prior expectation alone. Run the general triage path first and select the
pack only if the SQL, plan, wait, and object/index evidence support that
diagnosis. During diagnosis, treat the connected workload as a real incident
and avoid demo/lab backstage language.

For broad user prompts such as "the graph is slow" or "the graph workload is
slow", inspect multiple relevant SQL statements and report diagnostic coverage
across missing-index, supernode/fan-out, plan-instability, and other supported
classes before concluding. Do not stop after the first missing-index finding
when other visible SQL evidence points to a different issue class.
Plan Stability is a SQL workload property, not a SQL/PGQ-only property. Do not
skip the `plan-instability` pack merely because the relevant SQL is not a
`GRAPH_TABLE` statement. Include non-graph SQL only when it is linked to the
graph workload by backing tables, module/action, SQL tag, procedure, schema,
incident window, or user-provided workload scope.
Do not mark Plan Stability as `SKIPPED` based only on the hot SQL_IDs already
selected for indexing or fan-out findings. First run the generic workload
instability candidate search from `../../sql-templates/packs/plan-instability/`
across the discovered workload scope.

Use the `../../SYSTEM_PROMPT.md` output contract and
`../../reporting/diagnostic-report-template.md` exactly in every client:
connected context, workload scope, top SQL classification, findings,
diagnostic coverage, recommendations, and a final `Recommendation Summary`
table. Do not omit diagnostic coverage just because only one finding is
detected. Default to `quick-win` report mode for ordinary performance prompts:
print high-impact/high-priority findings and first actions only, while keeping
broader coverage internal and summarized. Use `extended` mode only when the
user asks for full evidence, all checked categories, skipped rows, exact SQL
scripts, rollback commands, or a DBA handoff. In the top SQL table, use the
generic column `Workload Context`, not
demo-specific labels, and always show `Execs`, `Total s`, and `Avg ms/exec` per
SQL_ID when visible. Use customer-facing coverage labels such as `Found`,
`Checked - no supporting evidence`, `Not visible with current grants`, and
`Blocked by access`; never print internal status codes in the report. In the
final table, use the canonical category names from `../../SYSTEM_PROMPT.md`;
use only the columns from `../../reporting/diagnostic-report-template.md`,
include `Impact`, `Effort`, and `Priority`. In `quick-win` mode, include only
actionable quick wins and any blocker that changes the first action; do not
include the full `SKIPPED` coverage tail. In `extended` mode, put actionable
rows first and include concise `SKIPPED` coverage rows for supported categories
checked with no supporting evidence. In `quick-win` mode, one short follow-up
question after the final table may ask whether the user wants the extended
report.

When recommending out-of-band DBA validation, provide exact step-by-step SQL
commands before the final summary in `extended` mode or when the user asks for
exact commands. In `quick-win` mode, provide the shortest safe validation
approach for non-indexing recommendations. Exception: actionable `Indexing`
recommendations must include the exact DBA validation runbook even in
`quick-win` mode because that is usually the first DBA action. Do not stop at
generic text such as "create invisible indexes and compare".
Do not leave `:sqlid`, `:child`, `TARGET_SQL_ID`, or similar placeholders in
user-facing validation SQL when the diagnosis has already identified the SQL_ID
or child cursor. Use literal values, or include an exact child-resolver query
and then the `DBMS_XPLAN.DISPLAY_CURSOR` command. Never use `DISPLAY_CURSOR()`
without explicit `SQL_ID` and `CHILD_NUMBER`; resolve the cursor by SQL marker
when validating a newly executed statement. For index validation, do not
say "re-run the SQL_ID" or "use this value as :ANCHOR_ID"; print the executable
target SQL with exact bind setup or resolved literal values. Do not assume
demo-specific bind names, bind datatypes, table names, labels, or graph names;
derive them from SQL text, bind capture, catalog metadata, and pack evidence.

Before recommending permanent indexes, collect visible DML/write-rate evidence
yourself when the read-only grants allow it; do not merely tell the user to
confirm INSERT rate. If the evidence is not visible, state that limitation. If
the DML evidence template cannot access `DBA_TAB_MODIFICATIONS`, use the
packaged visible-SQL fallback instead of stopping the diagnosis. Treat the
missing grant as an evidence limitation, not as a performance finding, and make
DBA workload confirmation a prerequisite for a permanent visible index change.
Use `R1`, `R2`, etc. consistently in detailed recommendations and the final table.
Do not use `P1/P2` for user-facing recommendations. For supernode/fan-out
findings, provide concrete `AS-IS` and `TO-BE` query or feature-table examples,
plus rollback/exit criteria.
Do not infer a supernode/fan-out finding from average degree alone. Use the
supernode pack only when skew/outlier evidence or measured path expansion
supports it, such as anchor degree versus P95/P99, max-to-P95 ratio, high
actual rows, or excessive intermediate rows for the candidate SQL.

Keep the runtime read-only. The diagnostic MCP surface should expose only an
approved SQL read tool such as `RUN_SQL`. Generate DDL recommendations as text
with validation and rollback steps; do not execute DDL/DML through the
diagnostic channel.

Use packaged SQL templates for health checks and diagnostics. During Phase 0,
run only the named `HEALTH-*` blocks from `../../sql-templates/00-health-check.sql`.
Do not run `OPTIONAL-*` health probes such as `OPTIONAL-02C` /
`V$SYS_TIME_MODEL` unless the user explicitly asks for that metric. Do not
improvise extra dynamic performance view probes during customer-facing
diagnosis unless the user explicitly asks for a metric outside the pack.
