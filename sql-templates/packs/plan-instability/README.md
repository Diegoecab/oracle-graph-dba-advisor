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

Template placeholders:

- `__PLAN_TAG__`: SQL comment tag used to isolate one packaged scenario, for example `PLAN_INSTABILITY_Q03` or `DOWNER_PI_Q01`.
- `__SQL_ID__`: SQL ID selected during drill-down.

Intended use:

- runtime consumption by the skill or MCP wrappers
- no ad hoc SQL generation during diagnosis
- stable, versioned query assets per diagnostic playbook
