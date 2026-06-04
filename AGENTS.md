# Repository Agent Guide

## Source Of Truth

- `SYSTEM_PROMPT.md` is the authoritative runtime methodology for Oracle Graph DBA Advisor.
- Do not duplicate long diagnostic logic in `SKILL.md`, `CLAUDE.md`, or client-specific entrypoints.
- Keep entrypoints as lightweight loaders that tell the agent when to read `SYSTEM_PROMPT.md` and which supporting folders may be needed.
- `README.md` is user-facing install and operation documentation, not runtime policy.
- For Mini-DOWNER, `docs/mini-downer-demo-database.md` is the operational source of truth. If older memory, local MCP files, or prior notes mention `GADVDOWNERAF`, `us-ashburn-1`, `graph-advisor-newfraud`, or an Ashburn OCID for Mini-DOWNER, treat that as stale unless the demo database doc has been updated to match it.
- The current Mini-DOWNER MCP name is `graph-mini-fraud-downer-26ai`; use that explicit server name when multiple ADB MCP servers are configured.

## Skill Packaging

- The root `SKILL.md` is for direct Codex/Claude skill installs from the repository root.
- `skills/oracle-graph-dba-advisor/SKILL.md` is the distributed plugin skill entrypoint.
- `CLAUDE.md` is a Claude project loader and must remain short.
- When runtime behavior changes, update all relevant plugin manifests and marketplace metadata versions together:
  - `.codex-plugin/plugin.json`
  - `.claude-plugin/plugin.json`
  - `.claude-plugin/marketplace.json`
- Keep plugin and skill metadata concise. Put detailed workflows in `SYSTEM_PROMPT.md`, `phases/`, `knowledge/`, `sql-templates/`, and `docs/`.

## Diagnostic Behavior

- Preserve the MCP target selection gate before the connection confirmation gate. If multiple database MCP servers are visible and the user did not name an exact alias, the skill must list candidates and ask for an explicit choice before executing SQL.
- Treat unauthenticated ADB Native MCP aliases that expose only `authenticate` or `authorize` as database candidates with status `needs authentication`; do not filter them out and auto-select another ready alias unless the user named it exactly.
- Always preserve the connection confirmation gate before any workload analysis.
- Do not infer the target database from workload names, schema names, graph names, or demo names alone.
- Do not choose a specialized diagnostic pack from the demo name alone.
- Select a pack only after evidence exists from the general triage path: connected context, graph inventory, candidate SQL, plan or wait evidence, and object/index metadata.
- For vague workload-performance prompts, require broad incident triage: inspect multiple relevant SQL statements and report coverage across missing-index, supernode/fan-out, plan-instability, and any other supported classes instead of stopping at the first plausible finding.
- For Mini-DOWNER, `missing-index` is the expected lab conclusion only when evidence shows a hot graph SQL, full scan or inefficient access on the edge table, and missing leading indexes on traversal columns.
- Preserve the cross-client output contract in `SYSTEM_PROMPT.md`: final diagnostic answers must keep the same section order and must end with `Recommendation Summary`, with no text after the table.
- Preserve the canonical final-summary category coverage in `SYSTEM_PROMPT.md`: actionable rows first, then concise `SKIPPED` rows for checked categories without supporting evidence.
- For Mini-DOWNER supernode/fan-out, `supernode-fanout` is justified only when evidence shows a high-degree vertex driving excessive intermediate rows or path expansion, not merely because the workload is tagged `DOWNER_SN_Q01`.
- For Mini-DOWNER plan instability, `plan-instability` is justified only when evidence shows multiple child cursors, multiple plan hashes, invalidations, bind mismatch, or elapsed-time deviation for the same SQL, not merely because the workload is tagged `DOWNER_PI_Q01`.
- During customer-facing diagnosis, treat Mini-DOWNER as a real operational workload. Do not use demo/lab language or cite `workload/` scripts unless the user asks for setup, reproduction, or out-of-band validation runbooks.
- During Phase 0, keep health checks on the `HEALTH-*` template allowlist. Do not add ad hoc dynamic performance view probes to runtime instructions unless a template gap is being intentionally closed.

## Runtime Safety

- Keep the diagnostic MCP surface read-only by default.
- ADB Native MCP demos should expose only the approved `RUN_SQL` read tool unless a task explicitly asks for a different controlled surface.
- Generate DDL recommendations as text with validation and rollback. Do not execute DDL/DML through the diagnostic channel.
- Never commit bearer tokens, wallets, generated per-database MCP configs, or passwords.

## Editing And Validation

- Preserve unrelated local worktree changes.
- Use focused edits and stage only files changed for the requested task.
- Before publishing plugin/runtime changes, run:
  - `claude plugin validate .`
  - `git diff --check`
- If SQL templates are changed, verify they remain plain `SELECT` or `WITH` statements with no comments or semicolons when they are intended for `RUN_SQL`.
