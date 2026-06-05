# Diagnostic Report Template

Use this template for every customer-facing Oracle Graph DBA Advisor diagnostic
report. The goal is consistent output across Claude Code, Claude Desktop/IDE,
Codex, and other MCP clients. Tool-call rendering may differ by client; the
assistant's final report must not.

Use the headings and section order below exactly unless the user explicitly
asks for a different report format. Prose may use the user's language, but keep
the headings, table column names, status values, category values, and
recommendation IDs stable.

Do not include MCP tool-call logs, client UI details, repository file paths, or
demo/lab backstage language in the final report unless the user explicitly asks
for setup or reproduction details.

The final visible section must be `### 7. Recommendation Summary`. Do not add
closing prose, SQL blocks, notes, or citations after that final table.

## Graph Workload Analysis Report

### 1. Connected Context

- Database: `[DB_NAME]`
- Service: `[SERVICE_NAME]`
- Session user: `[SESSION_USER]`
- Current schema: `[CURRENT_SCHEMA]`
- Target MCP/server: `[alias or Not visible]`
- Graphs visible: `[owner.graph_name list or Not visible with current grants]`
- Version note: `[only if material to the finding]`

### 2. Workload Scope

- Incident/request scope: `[user-stated workload, schema, graph, service, job, module, time window, or Not specified]`
- Evidence window: `[V$SQL/AWR/ASH/job table/window used, or Not visible]`
- Evidence sources used: `[catalog, V$SQL, V$SQL_PLAN, DBA_* views, pack templates, etc.]`
- Evidence limitations: `[missing grants, old cursor cache, AWR not visible, no fresh workload window, or None]`

### 3. Top Graph SQL

Use at most 5 rows. If the issue is connected to the graph workload but the SQL
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

### 4. Findings

Use one subsection per supported finding. If no finding is supported by
evidence, state that plainly and keep the coverage rows in section 5.

#### F1 - `[Category]` - `[short problem statement]`

- What: `[specific problem]`
- Where: `[SQL_ID, child cursor if relevant, plan operation, object]`
- Evidence: `[elapsed, CPU, buffer gets, waits, rows, degree/skew, plan, metadata]`
- Why: `[root cause in graph/workload terms]`
- Confidence: `[High/Medium/Low and why]`
- Access notes: `[None, or missing view/grant/fallback used]`

Important access rule: an ORA-00942 or ORA-01031 against a diagnostic dictionary
view is an evidence limitation, not a workload root cause. For example, if
`DBA_TAB_MODIFICATIONS` is not granted, do not report that as the performance
problem. Use the packaged fallback when available and record the limitation.

### 5. Diagnostic Coverage

Include actionable categories first when found, then checked categories with no
supporting evidence, then categories not visible or blocked by grants.

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

For broad prompts such as "the graph is slow", include coverage for the
supported categories that were checked, even when the final recommendation only
has one actionable finding.

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
-- exact SQL or exact numbered runbook, with real SQL_ID/child values when known
```

- Rollback / Exit: `[exact DROP/ALTER/revert/observe criteria]`

Recommendation rules:

- In read-only MCP mode, recommendations are DBA/app out-of-band actions only.
  Do not say the assistant can execute DDL/DML through the diagnostic channel.
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
- Index validation runbooks must include schema/session setup, invisible index
  DDL, `optimizer_use_invisible_indexes`, the target validation SQL, measured
  elapsed/CPU/buffer-get comparison, promotion command, and rollback command.
- Measure improvements by elapsed time first, CPU time second, and buffer gets
  as supporting evidence. Do not use optimizer cost as the success metric.
- Supernode/fan-out recommendations must include at least one concrete `AS-IS`
  query pattern and one concrete `TO-BE` option such as a degree guard, bounded
  result/window, feature table, or model-cleanup route, plus rollback/exit
  criteria.

### 7. Recommendation Summary

The report must end with this table. Put actionable rows first, ordered by
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
