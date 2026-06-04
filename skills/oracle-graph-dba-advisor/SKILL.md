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

Keep the runtime read-only. The diagnostic MCP surface should expose only an
approved SQL read tool such as `RUN_SQL`. Generate DDL recommendations as text
with validation and rollback steps; do not execute DDL/DML through the
diagnostic channel.

Use packaged SQL templates for health checks and diagnostics. During Phase 0,
run only the named `HEALTH-*` blocks from `../../sql-templates/00-health-check.sql`.
Do not improvise extra dynamic performance view probes during customer-facing
diagnosis unless the user explicitly asks for a metric outside the pack.
