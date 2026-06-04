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

For the Mini-DOWNER demo, `../../workload/downer/` and
`../../docs/client-demo-diagnostic-mode-step-by-step.md` provide lab context.
Do not choose `missing-index` from the Mini-DOWNER name alone. Run the general
triage path first and select the pack only if the SQL, plan, wait, and
object/index evidence support that diagnosis.

Keep the runtime read-only. The diagnostic MCP surface should expose only an
approved SQL read tool such as `RUN_SQL`. Generate DDL recommendations as text
with validation and rollback steps; do not execute DDL/DML through the
diagnostic channel.
