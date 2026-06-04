# Plan Instability Query Pack

Prebuilt diagnostic SQL pack for the advisor's cursor-instability scenario.

Files:

- `00-lab-summary.sql`: validates the synthetic lab data shape.
- `01-instability-summary.sql`: finds candidate SQL IDs with child cursor churn and plan-hash drift.
- `02-primary-sqlid.sql`: picks the strongest SQL ID candidate for drill-down.
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
- `__SQL_ID__`: SQL ID selected during drill-down.

Intended use:

- runtime consumption by the skill or MCP wrappers
- no ad hoc SQL generation during diagnosis
- stable, versioned query assets per diagnostic playbook
- choose `__PLAN_TAG__` from the customer's visible workload scope: SQL comment
  tag, module/action, named application query family, incident label, service,
  job, or procedure name
- do not require the tagged SQL to contain `GRAPH_TABLE`; this pack diagnoses
  SQL workload plan stability, child cursor churn, plan-hash drift, and elapsed
  deviation for the same logical statement
- include non-`GRAPH_TABLE` SQL only when it is linked to the graph workload by
  backing tables, module/action, schema, SQL tag, procedure, AWR/ASH window, or
  user-provided scope
