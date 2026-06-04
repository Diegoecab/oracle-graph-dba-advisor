# Missing Index Query Pack

Prebuilt diagnostic SQL pack for the Mini-DOWNER graph traversal scenario.

The pack is designed for ADB Native MCP `RUN_SQL` guardrails. SQL templates are
plain `SELECT` or `WITH` statements, with no SQL comments and no trailing
semicolons.

Files:

- `00-lab-summary.sql`: validates table shape, row counts, and index counts.
- `01-candidate-sql.sql`: finds tagged SQL candidates by elapsed time and buffer gets.
- `02-primary-sqlid.sql`: selects the strongest tagged SQL ID for drill-down.
- `03-hot-plan-operations.sql`: ranks plan operations by buffer gets and elapsed time.
- `04-edge-fk-leading-index-gap.sql`: checks missing leading indexes on graph edge FK columns.
- `05-degree-selectivity.sql`: quantifies degree distribution and active-edge selectivity.
- `06-recommendations.sql`: returns diagnostic recommendation text as SELECT rows.

Template placeholders:

- `__SQL_TAG__`: workload tag, normally `DOWNER_MI_Q01`.
- `__SQL_ID__`: selected SQL ID.
- `__GRAPH_OWNER__`: graph/table owner, normally `DOWNER_DEMO`.
- `__GRAPH_NAME__`: graph name, normally `DOWNER_GRAPH`.
- `__EDGE_TABLE__`: target edge table, normally `E_USES_DEVICE`.

Runtime rule:

- Use this pack through `RUN_SQL` only for diagnosis.
- Test indexes only through lab scripts outside the read-only MCP runtime.
- If this pack supports a missing-index recommendation, the advisor must output
  the exact DBA validation runbook in the recommendation detail: schema/session
  setup, invisible index DDL, `optimizer_use_invisible_indexes`, target SQL,
  `V$SQL` or `DBMS_XPLAN` comparison query, promotion command, and rollback.
  Do not leave the user with only "create invisible indexes and compare".
