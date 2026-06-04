# Supernode Fan-Out Query Pack

Prebuilt diagnostic SQL pack for graph traversals dominated by a high-degree
vertex. This is meant to distinguish fan-out/cardinality explosion from a pure
missing-index issue.

The pack is designed for ADB Native MCP `RUN_SQL` guardrails. SQL templates are
plain `SELECT` or `WITH` statements, with no SQL comments and no trailing
semicolons.

Files:

- `01-candidate-sql.sql`: finds tagged SQL candidates by elapsed time and buffer gets.
- `02-primary-sqlid.sql`: selects the strongest tagged SQL ID for drill-down.
- `03-hot-plan-operations.sql`: ranks plan operations and highlights high actual-vs-estimated rows.
- `04-degree-outliers.sql`: quantifies high-degree destination vertex outliers.
- `05-path-fanout-evidence.sql`: estimates path expansion from the anchor vertex to users to bank accounts.
- `06-recommendations.sql`: returns diagnostic recommendation text as SELECT rows.

Template placeholders:

- `__SQL_TAG__`: workload tag, normally `DOWNER_SN_Q01`.
- `__SQL_ID__`: selected SQL ID.
- `__GRAPH_OWNER__`: graph/table owner, normally `DOWNER_DEMO`.
- `__EDGE_TABLE__`: first-hop edge table, normally `E_USES_IP` for the coexistence Mini-DOWNER demo.
- `__SECOND_EDGE_TABLE__`: secondary edge table, normally `E_WITHDRAWAL_BANK_ACCOUNT`.
- `__ANCHOR_ID__`: high-degree destination vertex, normally `IP00000001`.

Runtime rule:

- Use this pack through `RUN_SQL` only for diagnosis.
- Do not treat a supernode finding as an index-only remediation. Validate index
  coverage, then focus recommendations on degree-aware query constraints,
  high-degree handling, precomputed features, or model cleanup.
