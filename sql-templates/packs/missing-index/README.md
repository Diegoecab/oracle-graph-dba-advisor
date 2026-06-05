# Missing Index Query Pack

Prebuilt diagnostic SQL pack for graph traversal workloads with suspected
missing or incomplete leading indexes on vertex or edge access columns.

The pack is designed for ADB Native MCP `RUN_SQL` guardrails. SQL templates are
plain `SELECT` or `WITH` statements, with no SQL comments and no trailing
semicolons.

Files:

- `00-lab-summary.sql`: validates table shape, row counts, and index counts.
- `00-workload-candidates.sql`: finds candidate SQL from the visible graph or
  workload scope without requiring SQL tags.
- `01-candidate-sql.sql`: finds tagged SQL candidates by elapsed time and buffer gets.
- `02-primary-sqlid.sql`: selects the strongest tagged SQL ID for drill-down.
- `03-hot-plan-operations.sql`: ranks plan operations by buffer gets and elapsed time.
- `04-edge-fk-leading-index-gap.sql`: checks missing leading indexes on graph edge FK columns.
- `05-degree-selectivity.sql`: quantifies degree distribution and active-edge selectivity.
- `06-recommendations.sql`: returns diagnostic recommendation text as SELECT rows.
- `07-dml-overhead-evidence.sql`: estimates write/DML overhead risk before recommending new indexes.
- `08-dml-overhead-visible-sql-fallback.sql`: fallback when
  `DBA_TAB_MODIFICATIONS` is not visible; reports table stats, current index
  count, proposed index count, and visible INSERT SQL from `V$SQL`.
- `09-display-cursor-latest-child.sql`: displays the latest child cursor plan
  for the selected `SQL_ID` with `ALLSTATS LAST`.
- `10-target-sql-fulltext.sql`: retrieves the selected cursor SQL text so the
  DBA validation runbook can print executable SQL instead of referring to a
  `SQL_ID` as if it were runnable text.

Template placeholders:

- `__SQL_TAG__`: workload tag, module/action fragment, or SQL text marker used
  to scope candidate SQL when one is visible. Tags are optional convenience
  signals, not a requirement for real workloads.
- `__WORKLOAD_SCOPE__`: workload marker discovered from schema, module/action,
  service/job, SQL text, application name, incident scope, or graph owner. If no
  better scope is visible, use the graph/workload owner as the fallback scope.
- `__SQL_ID__`: selected SQL ID.
- `__GRAPH_OWNER__`: graph or backing-table owner.
- `__GRAPH_NAME__`: property graph name.
- `__EDGE_TABLE__`: target vertex or edge table identified from the hot plan
  operation and graph catalog.
- `__PROPOSED_INDEX_COUNT__`: number of proposed new indexes for DML overhead
  estimation.

Runtime rule:

- Use this pack through `RUN_SQL` only for diagnosis.
- Prefer `00-workload-candidates.sql` when the customer workload has no SQL tag
  or stable module/action marker. Use the tagged candidates only when the tag or
  marker is visible in the connected database evidence.
- Test indexes only through out-of-band DBA validation scripts outside the
  read-only MCP runtime.
- If this pack supports a missing-index recommendation, the advisor must output
  the exact DBA validation runbook in the recommendation detail: schema/session
  setup, invisible index DDL, `optimizer_use_invisible_indexes`, target SQL,
  `V$SQL` or `DBMS_XPLAN` comparison query, promotion command, and rollback.
  Do not leave the user with only "create invisible indexes and compare".
- Do not output `:sqlid`, `:child`, `TARGET_SQL_ID`, or similar placeholders in
  the user-facing DBA runbook when the SQL_ID or child cursor is known. Use the
  selected SQL_ID as a literal. Use the observed child cursor as a numeric
  literal, or use `09-display-cursor-latest-child.sql` when the post-validation
  latest child must be resolved from `V$SQL`.
- Do not output "re-run the SQL_ID", "use that value as :ANCHOR_ID", or similar
  partial instructions. Fetch the target SQL with `10-target-sql-fulltext.sql`
  or another visible SQL text source, then print the executable validation SQL.
  If the workload SQL uses binds, provide exact bind setup or a literalized
  equivalent with representative values resolved from read-only evidence. For
  `GRAPH_TABLE` targets, print the complete `GRAPH_TABLE` query.
- Before proposing visible indexes, run `07-dml-overhead-evidence.sql` when the
  required views are available. Include the insert/DML rate and current index
  count in the evidence. If `DBA_TAB_MODIFICATIONS` is not visible, run
  `08-dml-overhead-visible-sql-fallback.sql`, say that dictionary modification
  counters were not visible, and make DBA workload confirmation an explicit
  prerequisite before a permanent visible index change.
