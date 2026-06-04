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

Load supporting files only when needed:

- `../../phases/` for the current diagnostic phase
- `../../sql-templates/` for executable read-only SQL templates
- `../../sql-templates/packs/` after evidence justifies a specialized pack
- `../../knowledge/` for versioned graph, optimizer, and design guidance

For Mini-DOWNER setup, reproduction, or out-of-band validation requests,
`../../workload/downer/` and
`../../docs/client-demo-diagnostic-mode-step-by-step.md` provide runbook
context. Do not use those files as diagnostic evidence during normal workload
analysis unless the user explicitly asks for setup or validation commands.

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

Do not choose `missing-index`, `supernode-fanout`, `plan-instability`, or any
other specialized pack from the Mini-DOWNER name or SQL tag alone. Run the
general triage path first and select the pack only if the SQL, plan, wait, and
object/index evidence support that diagnosis. During diagnosis, treat the
connected workload as a real incident and avoid demo/lab backstage language.

For broad user prompts such as "the graph is slow" or "Mini-DOWNER is slow",
inspect multiple relevant SQL statements and report diagnostic coverage across
missing-index, supernode/fan-out, plan-instability, and other supported classes
before concluding. Do not stop after the first missing-index finding when other
visible SQL evidence points to a different issue class.

Use the `../../SYSTEM_PROMPT.md` output contract exactly in every client:
connected context, workload scope, top SQL classification, findings,
diagnostic coverage, recommendations, and a final `Recommendation Summary`
table. Do not omit diagnostic coverage just because only one finding is
detected. In the final table, use the canonical category names from
`../../SYSTEM_PROMPT.md`; include `Impact`, `Effort`, and `Priority`, put
actionable rows first, and include concise `SKIPPED` coverage rows for
supported categories that were checked but not evidenced.

When recommending out-of-band DBA validation, provide exact step-by-step SQL
commands before the final summary. Do not stop at generic text such as "create
invisible indexes and compare"; include schema, DDL, session settings,
validation query, measurement query, promotion, and rollback.

Before recommending permanent indexes, collect visible DML/write-rate evidence
yourself when the read-only grants allow it; do not merely tell the user to
confirm INSERT rate. If the evidence is not visible, state that limitation. Use
`R1`, `R2`, etc. consistently in detailed recommendations and the final table.
Do not use `P1/P2` for user-facing recommendations. For supernode/fan-out
findings, provide concrete `AS-IS` and `TO-BE` query or feature-table examples,
plus rollback/exit criteria.

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
