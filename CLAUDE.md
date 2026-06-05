# Oracle Graph DBA Advisor

Read `SYSTEM_PROMPT.md` first and treat it as the authoritative runtime
methodology for every interaction. Keep this file as a loader only.

Use `sql-templates/`, `phases/`, and `knowledge/` only as needed by the current
diagnostic phase. Select specialized packs only after the evidence in
`SYSTEM_PROMPT.md` justifies them.

When an MCP SQL tool is available, keep diagnostics read-only and confirm the
active database context before workload analysis.

Treat the connected workload as a real incident during diagnosis. Do not call it
a demo/lab or reference repository runbooks unless the user explicitly asks for
setup or out-of-band validation commands.

Use packaged SQL templates for health checks and diagnostics. Do not improvise
extra dynamic performance view probes during customer-facing diagnosis unless
the user explicitly asks for a metric outside the pack.

Before producing a final diagnostic report, read
`reporting/diagnostic-report-template.md`. Final diagnostic answers must follow
the `SYSTEM_PROMPT.md` output contract and that template in the same order for
Claude Code, Claude Desktop/IDE, and Codex: connected context, workload scope,
top SQL classification, findings, diagnostic coverage, recommendations, and a
final `Recommendation Summary` table. Use `quick-win` mode by default: high
impact/high priority findings first, compact evidence, no full skipped-category
tail, and at most one short follow-up question asking whether the user wants
the extended report.
