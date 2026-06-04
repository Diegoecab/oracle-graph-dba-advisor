# Repository Agent Guide

## Source Of Truth

- `SYSTEM_PROMPT.md` is the authoritative runtime methodology for Oracle Graph DBA Advisor.
- Do not duplicate long diagnostic logic in `SKILL.md`, `CLAUDE.md`, or client-specific entrypoints.
- Keep entrypoints as lightweight loaders that tell the agent when to read `SYSTEM_PROMPT.md` and which supporting folders may be needed.
- `README.md` is user-facing install and operation documentation, not runtime policy.
- Demo and lab database details belong in `docs/` and `workload/` runbooks,
  not in the runtime skill. Use them only when the user explicitly asks for
  setup, reproduction, or out-of-band validation.
- Keep `SYSTEM_PROMPT.md` as the cross-client runtime contract, not a catch-all
  notebook. Put universal safety, phase-order, target-selection, and report
  format rules there. Put path-specific SQL, long examples, setup steps, and
  remediation runbooks in `sql-templates/`, `sql-templates/packs/`, `phases/`,
  `knowledge/`, `docs/`, or `workload/` instead.

## Skill Packaging

- The root `SKILL.md` is for direct Codex/Claude skill installs from the repository root.
- `skills/oracle-graph-dba-advisor/SKILL.md` is the distributed plugin skill entrypoint.
- `CLAUDE.md` is a Claude project loader and must remain short.
- When runtime behavior changes, update all relevant plugin manifests and marketplace metadata versions together:
  - `.codex-plugin/plugin.json`
  - `.claude-plugin/plugin.json`
  - `.claude-plugin/marketplace.json`
- Keep plugin and skill metadata concise. Put detailed workflows in `SYSTEM_PROMPT.md`, `phases/`, `knowledge/`, `sql-templates/`, and `docs/`.
- When `SYSTEM_PROMPT.md` grows, first check whether the new material is a
  universal behavioral contract. If it is only a diagnostic recipe, example,
  product note, or demo procedure, move it to a lazily loaded support file and
  add only a short pointer from the runtime contract.

## Diagnostic Behavior

- Preserve the MCP target selection gate before the connection confirmation gate. If multiple database MCP servers are visible and the user did not name an exact alias, the skill must list candidates and ask for an explicit choice before executing SQL.
- Treat unauthenticated ADB Native MCP aliases that expose only `authenticate` or `authorize` as database candidates with status `needs authentication`; do not filter them out and auto-select another ready alias unless the user named it exactly.
- Always preserve the connection confirmation gate before any workload analysis.
- Do not infer the target database from workload names, schema names, graph
  names, application labels, demo names, or prior local notes alone.
- Do not choose a specialized diagnostic pack from a workload, schema, graph,
  SQL tag, demo label, or prior expectation alone.
- Select a pack only after evidence exists from the general triage path: connected context, graph inventory, candidate SQL, plan or wait evidence, and object/index metadata.
- For vague workload-performance prompts, require broad incident triage: inspect multiple relevant SQL statements and report coverage across missing-index, supernode/fan-out, plan-instability, and any other supported classes instead of stopping at the first plausible finding.
- Preserve the cross-client output contract in `SYSTEM_PROMPT.md`: final diagnostic answers must keep the same section order and must end with `Recommendation Summary`, with no text after the table.
- Preserve the canonical final-summary category coverage in `SYSTEM_PROMPT.md`: actionable rows first, then concise `SKIPPED` rows for checked categories without supporting evidence.
- During customer-facing diagnosis, treat the connected workload as a real
  operational incident. Do not use demo/lab language or cite `workload/`
  scripts unless the user asks for setup, reproduction, or out-of-band
  validation runbooks.
- During Phase 0, keep health checks on the `HEALTH-*` template allowlist. Do not add ad hoc dynamic performance view probes to runtime instructions unless a template gap is being intentionally closed.
- Do not run `OPTIONAL-*` health probes such as `OPTIONAL-02C` / `V$SYS_TIME_MODEL` by default; these are opt-in or explicitly granted metrics only.

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
