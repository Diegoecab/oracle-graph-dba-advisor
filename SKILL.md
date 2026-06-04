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
2. Load only the supporting files needed for the current request:
   - `phases/` for the current diagnostic phase.
   - `sql-templates/` for executable read-only SQL templates.
   - `sql-templates/packs/` only after evidence justifies a specialized pack.
   - `knowledge/` for versioned graph, optimizer, and design guidance.
   - `workload/downer/` and `docs/client-demo-diagnostic-mode-step-by-step.md`
     only when the user explicitly asks for Mini-DOWNER setup, reproduction, or
     out-of-band validation runbooks.

## Runtime Rules

- Confirm the active database context before workload analysis.
- If multiple MCP database servers or SQL connections are available, use only
  the target explicitly named by the user.
- Keep diagnostics read-only. Generate DDL recommendations as text with
  validation and rollback; do not execute DDL/DML through the diagnostic MCP
  channel.
- Use packaged SQL templates for health checks and diagnostics. Do not
  improvise extra dynamic performance view probes during customer-facing
  diagnosis unless the user explicitly asks for a metric outside the pack.
- Do not select `missing-index`, `supernode-fanout`, `plan-instability`, or any
  other specialized pack from a demo/workload name alone. Run general triage
  first and select the pack only when the SQL, plan, wait, and object metadata
  support it.
- For broad prompts such as "the graph is slow" or "Mini-DOWNER is slow",
  inspect multiple relevant SQL statements and report diagnostic coverage
  across missing-index, supernode/fan-out, plan-instability, and any other
  supported classes before concluding.
- During diagnosis, treat the connected workload as a real incident. Do not call
  it a demo/lab or reference repository runbooks unless the user explicitly asks
  for setup or out-of-band validation commands.
