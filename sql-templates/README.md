# SQL Templates

This directory has two different layers on purpose:

- numbered root files such as `00-health-check.sql`, `02-identify.sql`, and `02b-plan-instability.sql`:
  analyst-facing template catalog for manual investigation and prompt design
- `packs/`:
  runtime-ready SQL packs consumed by the skill, MCP wrappers, or demo scripts

Current runtime packs:

- `packs/missing-index/`:
  packaged SQL set for edge traversal access-path and leading-index gaps
- `packs/plan-instability/`:
  packaged SQL set for the cursor and plan-instability diagnostic playbook
- `packs/supernode-fanout/`:
  packaged SQL set for high-degree vertex and fan-out diagnostics

Rule of thumb:

- if the skill executes it directly, it should live under `packs/`
- if it is a broader human-readable template or analysis notebook, it should stay at the root level
- `02-identify-queries.sql` is a compatibility alias for clients that search
  for a semantic identify filename; the canonical file remains `02-identify.sql`
