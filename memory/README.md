# Agent Memory

This directory stores persistent memory for the Oracle Graph DBA Advisor. Files here are created and updated automatically by the agent during analysis sessions.

## Structure

- `_templates/` — Templates copied when connecting to a new environment
- `backends/` — Storage backend guides (Oracle ADB, etc.) for Phase 2+ upgrades
- `{connection_name}/` — One folder per database connection (auto-created)
  - `schema-snapshot.json` — Graph topology, table volumes, index inventory
  - `recommendation-log.md` — Chronological log of recommendations with outcomes
  - `active-issues.md` — Open issues being tracked across sessions
- `shared/` — Cross-environment context
  - `user-preferences.md` — Communication preferences, expertise level
  - `learned-patterns.md` — Confirmed optimization patterns

## Privacy

Environment folders and shared/ are gitignored. They may contain database schema details and performance data. Do not commit to public repositories. Templates in `_templates/` are committed as part of the project.

## Reset

- Reset one environment: delete its folder in `memory/`
- Reset all memory: delete `memory/shared/` and all environment folders
- Templates are never deleted (they live in `_templates/`)
