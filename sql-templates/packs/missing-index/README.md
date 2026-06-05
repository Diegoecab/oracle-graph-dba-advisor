# Missing Index Query Pack

Prebuilt diagnostic SQL pack for graph traversal workloads with suspected
missing or incomplete leading indexes on vertex or edge access columns.

The pack is designed for ADB Native MCP `RUN_SQL` guardrails. SQL templates are
plain `SELECT` or `WITH` statements, with no SQL comments and no trailing
semicolons.

Files:

- `00-graph-table-summary.sql`: validates graph table shape, row counts, and
  index counts from the graph catalog.
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
- `11-target-sql-binds.sql`: retrieves captured bind names, positions, datatypes,
  and values for the selected `SQL_ID` when visible.
- `12-validation-marker-cursor.sql`: resolves the actual post-validation cursor
  by a unique SQL text marker before printing `DBMS_XPLAN.DISPLAY_CURSOR`.
- `13-cursor-metrics-before-after.sql`: compares baseline and after cursor
  elapsed time, CPU time, buffer gets, executions, and plan hash.
- `14-plan-operations-before-after.sql`: compares baseline and after plan
  operations with available row and buffer statistics.
- `15-application-rerun-cursor.sql`: resolves the newest application cursor
  after a visible change when the after plan should come from the real workload
  instead of an immediate validation marker.

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
- `__SOURCE_FK__`: source-side FK column on the target edge table, discovered
  from `DBA_PG_EDGE_RELATIONSHIPS`.
- `__DESTINATION_FK__`: destination-side FK column on the target edge table,
  discovered from `DBA_PG_EDGE_RELATIONSHIPS`.
- `__EDGE_FILTER_PREDICATE__`: predicate used for degree/selectivity evidence,
  such as an active-edge filter. Use `1 = 1` when no edge filter applies.
- `__PROPOSED_INDEX_COUNT__`: number of proposed new indexes for DML overhead
  estimation.
- `__BEFORE_SQL_ID__`, `__BEFORE_CHILD_NUMBER__`: baseline cursor identity.
- `__AFTER_SQL_ID__`, `__AFTER_CHILD_NUMBER__`: post-validation or post-change
  cursor identity.
- `__VALIDATION_SQL_MARKER__`: unique SQL text marker added to immediate
  validation SQL.
- `__ORIGINAL_SQL_ID__`: original application cursor SQL_ID used as a stable
  resolver when the application reruns the same SQL text.
- `__WORKLOAD_SQL_MARKER__`, `__WORKLOAD_MODULE__`, `__WORKLOAD_ACTION__`:
  optional stable workload scope values for resolving an application rerun
  cursor when SQL_ID alone is not enough.

Runtime rule:

- Use this pack through `RUN_SQL` only for diagnosis.
- Prefer `00-workload-candidates.sql` when the customer workload has no SQL tag
  or stable module/action marker. Use the tagged candidates only when the tag or
  marker is visible in the connected database evidence.
- Test indexes only through out-of-band DBA validation scripts outside the
  read-only MCP runtime.
- If this pack supports a missing-index recommendation, the advisor must output
  exact DBA action SQL in the recommendation detail. When object names are
  known, split the action into two labeled paths:
  `Implement now in dev/test`, with direct visible `CREATE INDEX` DDL and exact
  before/after verification SQL; and `Controlled validation for
  production/pre-prod`, with invisible index DDL,
  `optimizer_use_invisible_indexes`, target SQL, `V$SQL` or `DBMS_XPLAN`
  comparison query, promotion command, and rollback. Do not leave the user with
  only "create invisible indexes and compare".
- Do not output `:sqlid`, `:child`, `TARGET_SQL_ID`, or similar placeholders in
  the user-facing DBA runbook when the SQL_ID or child cursor is known. Use the
  selected SQL_ID as a literal. Use the observed child cursor as a numeric
  literal, or use `09-display-cursor-latest-child.sql` when the post-validation
  latest child must be resolved from `V$SQL`.
- Do not use `DBMS_XPLAN.DISPLAY_CURSOR()` without explicit `SQL_ID` and
  `CHILD_NUMBER`, and do not use format-only calls. For newly executed validation
  SQL, add a unique marker and use `12-validation-marker-cursor.sql` or an
  equivalent resolver before printing the explicit `DISPLAY_CURSOR` command.
- Include `13-cursor-metrics-before-after.sql` and
  `14-plan-operations-before-after.sql`, or equivalent SQL, in both dev/test
  implementation blocks and controlled validation runbooks so the user can
  compare the old plan/cursor to the new one. Support both immediate validation
  by SQL marker and application rerun after an approved visible change. Use
  `15-application-rerun-cursor.sql` or equivalent SQL to find the newest real
  application cursor after a visible change.
- Promotion and rollback sections must enumerate every proposed index command;
  do not abbreviate with "and the second index" when names are known.
- Do not output "re-run the SQL_ID", "use that value as :ANCHOR_ID", or similar
  partial instructions. Fetch the target SQL with `10-target-sql-fulltext.sql`
  or another visible SQL text source, then print the executable validation SQL.
  If the workload SQL uses binds, use `11-target-sql-binds.sql` and catalog
  metadata to derive bind names and datatypes, or provide a literalized
  equivalent with representative values resolved from read-only evidence. Do not
  assume demo-specific bind names, bind datatypes, graph names, table names, or
  labels. For `GRAPH_TABLE` targets, print the complete `GRAPH_TABLE` query.
- If `11-target-sql-binds.sql` fails with ORA-00942 or ORA-01031 for
  `V$SQL_BIND_CAPTURE`, continue without bind capture. State that captured bind
  values are not visible with current grants, derive representative literals
  from read-only evidence such as degree outliers or plan predicates, and include
  the optional DBA grant:
  `GRANT SELECT ON SYS.V_$SQL_BIND_CAPTURE TO <diag_user>`.
- Before proposing visible indexes, run `07-dml-overhead-evidence.sql` when the
  required views are available. Include the insert/DML rate and current index
  count in the evidence. If `DBA_TAB_MODIFICATIONS` is not visible, run
  `08-dml-overhead-visible-sql-fallback.sql`, say that dictionary modification
  counters were not visible, and make DBA workload confirmation an explicit
  prerequisite before a permanent visible index change.
