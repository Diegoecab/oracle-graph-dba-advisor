# Supernode Fan-Out Query Pack

Prebuilt diagnostic SQL pack for graph traversals dominated by a high-degree
vertex. This is meant to distinguish fan-out/cardinality explosion from a pure
missing-index issue.

The pack is designed for ADB Native MCP `RUN_SQL` guardrails. SQL templates are
plain `SELECT` or `WITH` statements, with no SQL comments and no trailing
semicolons.

Files:

- `00-workload-candidates.sql`: finds candidate SQL from the visible graph or
  workload scope without requiring SQL tags.
- `01-candidate-sql.sql`: finds tagged SQL candidates by elapsed time and buffer gets.
- `02-primary-sqlid.sql`: selects the strongest tagged SQL ID for drill-down.
- `03-hot-plan-operations.sql`: ranks plan operations and highlights high actual-vs-estimated rows.
- `04-degree-outliers.sql`: quantifies high-degree destination vertex outliers.
- `05-path-fanout-evidence.sql`: estimates path expansion from the anchor vertex to users to bank accounts.
- `06-recommendations.sql`: returns diagnostic recommendation text as SELECT rows.

Template placeholders:

- `__SQL_TAG__`: workload tag, module/action fragment, or SQL text marker used
  to scope candidate SQL when one is visible. Tags are optional convenience
  signals, not a requirement for real workloads.
- `__WORKLOAD_SCOPE__`: workload marker discovered from schema, module/action,
  service/job, SQL text, application name, incident scope, or graph owner. If no
  better scope is visible, use the graph/workload owner as the fallback scope.
- `__SQL_ID__`: selected SQL ID.
- `__GRAPH_OWNER__`: graph or backing-table owner.
- `__EDGE_TABLE__`: first-hop edge table involved in the high-degree expansion.
- `__SECOND_EDGE_TABLE__`: optional secondary edge table used to quantify path
  expansion beyond the first hop.
- `__ANCHOR_ID__`: high-degree source or destination vertex identified from
  workload evidence.

Runtime rule:

- Use this pack through `RUN_SQL` only for diagnosis.
- Prefer `00-workload-candidates.sql` when the customer workload has no SQL tag
  or stable module/action marker. Use the tagged candidates only when the tag or
  marker is visible in the connected database evidence.
- Average degree alone is not sufficient evidence for a supernode/fan-out
  finding. Treat average degree as a context metric only. The finding requires
  skew/outlier or path-expansion evidence, such as anchor degree versus P95/P99,
  max-to-P95 ratio, actual rows far above estimates, or measured intermediate
  row expansion for the candidate SQL.
- Do not treat a supernode finding as an index-only remediation. Validate index
  coverage, then focus recommendations on degree-aware query constraints,
  high-degree handling, precomputed features, or model cleanup.
- The recommendation detail must include concrete `AS-IS` and `TO-BE` examples:
  a bounded or degree-aware traversal, a feature/materialized lookup pattern, or
  a model-cleanup path for NAT/proxy/shared infrastructure. Include rollback or
  exit criteria for the chosen option.
