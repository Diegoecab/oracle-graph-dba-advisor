# Plan Instability Query Pack

Prebuilt diagnostic SQL pack for SQL workload plan stability, child cursor
churn, plan-hash drift, invalidations, and elapsed-time deviation.

Files:

- `00-workload-instability-candidates.sql`: finds unstable SQL candidates from
  the visible graph/workload scope without requiring a known SQL tag.
- `01-instability-summary.sql`: finds tagged SQL candidates with child cursor
  churn and plan-hash drift when a workload tag or module/action fragment is
  already known.
- `02-primary-sqlid.sql`: picks the strongest tagged SQL ID candidate for
  drill-down.
- `02a-primary-workload-sqlid.sql`: picks the strongest generic workload SQL ID
  candidate for drill-down when no tag is known.
- `03-child-detail.sql`: shows child cursor-level execution and plan metrics.
- `04-shared-cursor.sql`: shows why child cursors were not shared.
- `05-plan-hash.sql`: summarizes parent cursor plan-hash history.
- `06-elapsed-deviation.sql`: quantifies elapsed-time and buffer-get spread
  across child cursors and plan hashes.
- `07-recommendations.sql`: returns read-only recommendation text for
  DBA/out-of-band plan-stability validation.

Template placeholders:

- `__PLAN_TAG__`: SQL comment tag, module/action fragment, application query
  family, incident label, or other workload marker used to isolate one logical
  statement family.
- `__GRAPH_OWNER__`: graph or workload owner/schema discovered during catalog
  discovery.
- `__WORKLOAD_SCOPE__`: workload marker discovered from schema, module/action,
  service/job, SQL text, application name, incident scope, or graph owner. If no
  better scope is visible, use the graph/workload owner as the fallback scope.
- `__SQL_ID__`: SQL ID selected during drill-down.

Intended use:

- runtime consumption by the skill or MCP wrappers
- no ad hoc SQL generation during diagnosis
- stable, versioned query assets per diagnostic playbook
- before marking Plan Stability as `SKIPPED`, run
  `00-workload-instability-candidates.sql` against the discovered workload
  scope; do not infer plan stability from only the SQL_IDs already selected for
  missing-index or fan-out analysis
- choose `__PLAN_TAG__` from the customer's visible workload scope: SQL comment
  tag, module/action, named application query family, incident label, service,
  job, or procedure name
- do not require the tagged SQL to contain `GRAPH_TABLE`; this pack diagnoses
  SQL workload plan stability, child cursor churn, plan-hash drift, and elapsed
  deviation for the same logical statement
- include non-`GRAPH_TABLE` SQL only when it is linked to the graph workload by
  backing tables, module/action, schema, SQL tag, procedure, AWR/ASH window, or
  user-provided scope
