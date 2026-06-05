# Diagnostic Report Template

Use this template for every customer-facing Oracle Graph DBA Advisor diagnostic
report. The goal is consistent output across Claude Code, Claude Desktop/IDE,
Codex, and other MCP clients. Tool-call rendering may differ by client; the
assistant's final report must not.

Use the headings and section order below exactly unless the user explicitly
asks for a different report format. Prose may use the user's language, but keep
the headings, table column names, status values, category values, and
recommendation IDs stable.

Default report mode is `quick-win`. It is intentionally concise and aimed at
ordinary user prompts such as "the graph is slow". The advisor must still run
broad triage internally, but the default report should print only the evidence
needed for decisions and the recommendations with `Impact=High` or
`Priority=High`. Include `Medium` priority findings only when no high-priority
quick win is visible or when they materially change the first action.

Use `extended` mode only when the user asks for a full report, detailed
evidence, all SQL, all categories, all skipped rows, a DBA handoff runbook, or
troubleshooting detail. Extended mode may include all checked categories,
`SKIPPED` rows, exact validation SQL, rollback SQL, pack-by-pack evidence, and
longer explanation.

Do not include MCP tool-call logs, client UI details, repository file paths, or
demo/lab backstage language in the final report unless the user explicitly asks
for setup or reproduction details.

The final visible section must be `### 7. Recommendation Summary`. In
`quick-win` mode, the assistant may add exactly one short follow-up question
after the final table asking whether the user wants the extended report. Do not
add SQL blocks, extra caveats, citations, or additional explanation after that
question.

## Graph Workload Analysis Report

### 1. Connected Context

Keep this section compact in `quick-win` mode. Prefer one line:

`Connected context confirmed: DB_NAME=[db], SERVICE_NAME=[service], SESSION_USER=[user], CURRENT_SCHEMA=[schema], target=[alias].`

In `extended` mode, also include visible graphs and any material version note.

### 2. Workload Scope

In `quick-win` mode, use at most three bullets:

- Scope: `[user-stated workload, schema, graph, service, job, module, time window, or Not specified]`
- Evidence window: `[V$SQL/AWR/ASH/job table/window used, or Not visible]`
- Limitations: `[missing grants, old cursor cache, AWR not visible, no fresh workload window, or None]`

In `extended` mode, also list every evidence source used.

### 3. Top Graph SQL

Use at most 3 rows in `quick-win` mode and at most 5 rows in `extended` mode.
If the issue is connected to the graph workload but the SQL
text is not a `GRAPH_TABLE` statement, still include it when it is linked by
backing tables, schema, module/action, job, SQL text marker, incident window, or
the user's stated scope.

| Rank | SQL_ID | Workload Context | Execs | Total s | Avg ms/exec | Issue |
|------|--------|------------------|-------|---------|-------------|-------|
| 1 | `[sql_id]` | `[schema/module/action/graph/backing table/window]` | `[n]` | `[seconds]` | `[ms]` | `[primary issue class or Checked - no supporting evidence]` |

Rules:

- Use `Workload Context`, not `Tag/Module`.
- Always show average milliseconds per execution when elapsed time and
  executions are visible.
- If elapsed time is not visible, write `Not visible` instead of hiding the
  column.
- Do not print internal values such as `CHECKED_NOT_SUPPORTED`.
- Put plan, wait, row, and object evidence in the `Findings` section rather
  than widening this table.
- In `quick-win` mode, include only SQL tied to quick wins or to the reason no
  high-priority quick win was found.

### 4. Findings

Use one subsection per supported finding in `extended` mode. In `quick-win`
mode, include at most 3 findings and only those with `Impact=High`,
`Priority=High`, or material first-action relevance. If no high-priority quick
win is supported by evidence, state that plainly and show the strongest
available finding.

#### F1 - `[Category]` - `[short problem statement]`

- What: `[specific problem]`
- Where: `[SQL_ID, child cursor if relevant, plan operation, object]`
- Evidence: `[one to three strongest data points: elapsed, CPU, buffer gets, waits, rows, degree/skew, plan, metadata]`
- Why: `[root cause in graph/workload terms]`
- Confidence: `[High/Medium/Low and why]`
- Access notes: `[None, or missing view/grant/fallback used]`

Important access rule: an ORA-00942 or ORA-01031 against a diagnostic dictionary
view is an evidence limitation, not a workload root cause. For example, if
`DBA_TAB_MODIFICATIONS` is not granted, do not report that as the performance
problem. Use the packaged fallback when available and record the limitation.

### 5. Diagnostic Coverage

In `quick-win` mode, do not print a full coverage matrix. Summarize coverage in
one compact table row per relevant bucket: `Found`, `Checked - no supporting
evidence`, and `Not visible/blocked`, with category names compressed in the
`Checked Evidence` column. In `extended` mode, include actionable categories
first when found, then checked categories with no supporting evidence, then
categories not visible or blocked by grants.

| Category | Checked Evidence | Status | Decision |
|----------|------------------|--------|----------|
| Indexing | `[plan/index/FK/selectivity/write-rate evidence]` | `[status]` | `[pack selected, skipped, or blocked reason]` |

Customer-facing `Status` values:

- `Found`
- `Checked - no supporting evidence`
- `Not visible with current grants`
- `Blocked by access`

Canonical `Category` values:

- `Indexing`
- `Supernode/Fan-out`
- `Plan Stability`
- `Statistics & Optimizer`
- `Query Rewriting`
- `Graph Design / Modeling`
- `Schema & Architecture`
- `Resource / Health`
- `Auto Indexing`

For broad prompts such as "the graph is slow", perform coverage for the
supported categories that are applicable to the visible workload. In
`quick-win` mode, summarize that coverage instead of printing every `SKIPPED`
row. In `extended` mode, print the full category coverage.

If `DBA_TAB_MODIFICATIONS` is not granted, the `Indexing` coverage row may
still be `Found` when plan/index evidence supports the issue, but the checked
evidence must say that dictionary DML counters were not visible and that the
visible-SQL DML fallback was used.

### 6. Recommendations

Use stable recommendation IDs `R1`, `R2`, `R3`, etc. Do not use `P1/P2` in
customer-facing recommendations. The `P0`-`P4` labels are reserved for internal
graph index strategy reasoning only.

#### R1 - `[Category]` - `[short action]`

- Status: `[PROPOSED, DONE, or SKIPPED]`
- Impact: `[High, Medium, Low, or None]`
- Effort: `[Low, Medium, High, or None]`
- Priority: `[High, Medium, Low, or Skip]`
- Evidence: `[specific evidence supporting this recommendation]`
- Write-rate evidence: `[current index count, proposed index count, DML counters, fallback result, or Not applicable]`
- Action: `[exact DBA/app/query/design action]`
- Validation:

```sql
-- quick-win mode, non-indexing: one short validation approach
-- quick-win mode, Indexing: exact DBA validation runbook
-- extended mode: exact SQL or exact numbered runbook, with real SQL_ID/child values when known
```

- Rollback / Exit: `[exact DROP/ALTER/revert/observe criteria]`

Recommendation rules:

- In read-only MCP mode, recommendations are DBA/app out-of-band actions only.
  Do not say the assistant can execute DDL/DML through the diagnostic channel.
- In `quick-win` mode, include only quick-win recommendations and the shortest
  safe validation instruction for non-indexing recommendations.
- Indexing exception: when an actionable `Indexing` recommendation is proposed,
  include the exact DBA validation runbook in this section even in `quick-win`
  mode. Do not replace it with "short validation" and do not defer it to the
  extended report.
- In `extended` mode, include full validation and rollback SQL when available.
- Before recommending permanent indexes, collect write-side evidence yourself
  when grants allow it. Do not merely tell the user to confirm INSERT rate.
- If `sql-templates/packs/missing-index/07-dml-overhead-evidence.sql` fails
  with ORA-00942 or ORA-01031 on `DBA_TAB_MODIFICATIONS`, run
  `sql-templates/packs/missing-index/08-dml-overhead-visible-sql-fallback.sql`.
  In `Write-rate evidence`, state that dictionary modification counters were
  not visible, summarize the fallback results, and make DBA workload
  confirmation or this optional grant a prerequisite before a permanent visible
  index change:

```sql
GRANT SELECT ON DBA_TAB_MODIFICATIONS TO <diag_user>
```

- If a DBA validation needs a SQL_ID or child cursor and the diagnosis already
  identified it, use literal values. Do not leave placeholders such as
  `:sqlid`, `:child`, `TARGET_SQL_ID`, or `<child>` in user-facing SQL.
- When the child cursor is not known, include an exact resolver query ordered
  by `LAST_ACTIVE_TIME DESC NULLS LAST, CHILD_NUMBER DESC`, then use the latest
  validation child for `DBMS_XPLAN.DISPLAY_CURSOR`.
- Never use `DBMS_XPLAN.DISPLAY_CURSOR()` without explicit `SQL_ID` and
  `CHILD_NUMBER`, and never use a format-only call such as
  `DBMS_XPLAN.DISPLAY_CURSOR(FORMAT => 'ALLSTATS LAST')`. In Database Actions,
  SQL Developer Web, SQLcl, IDEs, and similar clients, the last cursor can be
  client helper SQL/PLSQL rather than the workload SQL. For validation runs,
  add a unique SQL marker, resolve the real cursor from `V$SQL`, then display
  that explicit cursor.
- Index validation runbooks must include schema/session setup, invisible index
  DDL, `optimizer_use_invisible_indexes`, the target validation SQL, measured
  elapsed/CPU/buffer-get comparison, plan verification query, plan-operation
  comparison query, promotion command, and rollback command.
- Include SQL for both validation modes when relevant: immediate validation
  with a unique SQL marker, and application rerun validation after a visible
  change. The report must include a query that compares baseline vs after
  elapsed/CPU/buffer gets and a query that compares baseline vs after plan
  operations. Do not leave this as prose.
- Promotion and rollback sections must print every object-specific command when
  names are known. Do not write "(and the second)" or "repeat for the other
  index".
- The target validation SQL must be executable as printed. Do not say
  "re-run the SQL_ID", "use this value as :ANCHOR_ID", or "execute the pattern"
  without printing the actual SQL. If the workload SQL is a `GRAPH_TABLE`
  statement, include the complete `GRAPH_TABLE` query with either exact bind
  setup or resolved literal values. A `SQL_ID` may be used for `DBMS_XPLAN` and
  `V$SQL` lookup, but not as a substitute for the SQL text.
- Bind names, bind datatypes, graph names, table names, labels, and columns must
  come from the selected SQL text, `V$SQL_BIND_CAPTURE`, graph catalog metadata,
  plan metadata, or pack evidence. Do not assume `anchor_id`, `NUMBER`, or any
  demo-specific table/label. If using SQLcl bind setup, use `BEGIN SELECT ...
  INTO :bind ...; END; /`, not `EXEC :bind := (SELECT ...)`.
- Measure improvements by elapsed time first, CPU time second, and buffer gets
  as supporting evidence. Do not use optimizer cost as the success metric.
- Supernode/fan-out recommendations must include at least one concrete `AS-IS`
  query pattern and one concrete `TO-BE` option such as a degree guard, bounded
  result/window, feature table, or model-cleanup route, plus rollback/exit
  criteria.

### 7. Recommendation Summary

In `quick-win` mode, include only actionable quick-win rows and any blocker
that changes the first action. Do not include the full `SKIPPED` coverage tail
by default. In `extended` mode, put actionable rows first, ordered by
`Priority` (`High`, `Medium`, `Low`), followed by concise `SKIPPED` coverage
rows.

| Rec | Category | Status | Impact | Effort | Priority | Action / Reason |
|-----|----------|--------|--------|--------|----------|-----------------|
| R1 | `[Category]` | PROPOSED | High | Medium | High | `[DBA validation/app review/observe/skip]` |

Allowed `Status` values:

- `DONE`
- `PROPOSED`
- `SKIPPED`

Allowed `Impact` values:

- `High`
- `Medium`
- `Low`
- `None`

Allowed `Effort` values:

- `Low`
- `Medium`
- `High`
- `None`

Allowed `Priority` values:

- `High`
- `Medium`
- `Low`
- `Skip`

Allowed read-only `Action / Reason` patterns:

- `DBA validation: create invisible index and compare`
- `DBA change: apply approved DDL`
- `App/query review`
- `Observe only: collect a fresh workload window before action`
- `Skip`
- `Not visible with current grants`
- `Blocked by access`

Default follow-up question after the final table:

`Quieres que genere el reporte extendido con evidencia completa, categorias SKIPPED, SQL exacto de validacion/rollback y alternativas?`

Translate the question to the user's language. Ask only one short question.
