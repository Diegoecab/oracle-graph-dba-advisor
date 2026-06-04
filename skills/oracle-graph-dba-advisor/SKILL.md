---
name: oracle-graph-dba-advisor
description: Diagnose Oracle SQL/PGQ property graph performance using read-only SQL evidence, packaged templates, and recommendations for ADB Native MCP or SQLcl MCP.
---

# Oracle Graph DBA Advisor

Use this skill when the user asks to diagnose, review, or optimize Oracle
SQL/PGQ or Property Graph workloads, especially through ADB Native MCP or SQLcl
MCP.

Before running diagnostics, read the packaged methodology:

- `../../SYSTEM_PROMPT.md`
- `../../sql-templates/`
- `../../knowledge/`
- `../../phases/`

For the Mini-DOWNER demo, use:

- `../../workload/downer/`
- `../../sql-templates/packs/missing-index/`
- `../../docs/client-demo-diagnostic-mode-step-by-step.md`

Keep the runtime read-only. The diagnostic MCP surface should expose only an
approved SQL read tool such as `RUN_SQL`. Generate DDL recommendations as text
with validation and rollback steps; do not execute DDL/DML through the
diagnostic channel.
