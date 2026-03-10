# Oracle Graph DBA Advisor

A **system prompt + SQL templates + knowledge base** that turns any MCP-compatible LLM into an Oracle Property Graph (SQL/PGQ) performance advisor for Oracle Database 23ai and 26ai.

Connects via the **ADB MCP Server** (fully managed, zero install) or **SQLcl MCP Server** (local, any Oracle 23ai/26ai).

---

## What It Does

```
You:     "Analyze my graph workload and tell me what's slow and why"

Advisor: 1. Checks database health (CPU, I/O, memory, tablespace)
         2. Discovers property graphs, tables, volumes, indexes
         3. Finds the most expensive graph queries by elapsed time
         4. Reads execution plans, identifies bottlenecks
         5. Recommends indexes with DDL, measured impact, and rollback
```

The advisor follows a **simplicity-first philosophy**: a property graph is just node tables and edge tables. Index the FKs, index the filters if needed, and stop. Advanced strategies only with measured evidence.

---

## Why Use This vs a Plain LLM

| Capability | Plain LLM | With this skill |
|---|---|---|
| **Methodology** | Ad-hoc | 8-phase structured diagnostic (Health Check → Discovery → Identify → Deep Dive → Selectivity → Simulate → Recommend → Scale Test) |
| **SQL templates** | Generates from scratch — may use wrong views | 40+ pre-built, tested templates for Oracle 23ai/26ai graph diagnostics |
| **GRAPH_TABLE** | Treats as black box | Knows it expands to relational joins — traces TABLE ACCESS / HASH JOIN back to graph hops |
| **Index strategy** | Generic "add an index" | Priority hierarchy P0-P4: PK → FK → filter → composite → advanced. Stops at the lowest level that solves the problem |
| **Auto Indexing** | No awareness | Checks ADB Auto Indexing status, deduplicates with auto-created indexes, recommends composites Auto Indexing can't create |
| **Anti-patterns** | May miss graph pitfalls | Flags 9 graph-specific anti-patterns: missing stats, cartesian explosions, SYSTIMESTAMP type mismatch, VERTEX_ID overhead, co-view scaling, and more |
| **Evaluation** | Reports optimizer cost | Always measures **actual elapsed time** — never evaluates by cost |
| **Safety** | No guardrails | Production guard, read-only by default, never executes DDL/DML or changes configuration without explicit approval |
| **Memory** | Starts from zero | Remembers schemas, past recommendations, and outcomes across sessions |

---

## Architecture

```
┌──────────────────────────────────────────┐
│           MCP-compatible LLM             │
│                                          │
│  SYSTEM_PROMPT.md (auto-loaded)          │
│  sql-templates/  (diagnostic queries)    │
│  knowledge/      (patterns & rules)      │
│                                          │
└────────────────┬─────────────────────────┘
                 │ MCP Protocol
                 ▼
    ┌──── Primary ────┐  ┌── Alternative ──┐
    │  ADB MCP Server │  │  SQLcl MCP      │
    │  (fully managed,│  │  (local,        │
    │   in-database)  │  │   any Oracle)   │
    └────────┬────────┘  └───────┬─────────┘
             │                   │
             ▼                   ▼
    ┌────────────────────────────────┐
    │   Oracle Database 23ai / 26ai  │
    └────────────────────────────────┘
```

Uses AWR/ASH when available for historical trends. Falls back to `V$SQL` + `USER_*` views automatically on Always Free tier.

---

## Quick Start

### Option A: ADB Serverless (recommended — zero install)

1. Enable MCP on your ADB (OCI Console → free-form tag):
   ```
   Tag: adb$feature → {"name":"mcp_server","enable":true}
   ```

2. Register the SQL tool — connect to ADB and run:
   ```sql
   BEGIN
     DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
       tool_name  => 'RUN_SQL',
       attributes => '{"instruction": "Execute a read-only SQL query.",
          "function": "RUN_SQL",
          "tool_inputs": [
            {"name":"QUERY","description":"SELECT SQL statement without trailing semicolon."},
            {"name":"OFFSET","description":"Pagination offset (default 0)."},
            {"name":"LIMIT","description":"Max rows to return (default 100)."}
          ]}'
     );
   END;
   /
   ```

3. Configure your MCP client:
   ```json
   {
     "mcpServers": {
       "oracle-graph-advisor": {
         "command": "npx",
         "args": ["-y", "mcp-remote",
           "https://dataaccess.adb.<region>.oraclecloudapps.com/adb/mcp/v1/databases/<ocid>"],
         "transport": "streamable-http"
       }
     }
   }
   ```

4. Start a conversation — the system prompt loads automatically.

> Full details: `clients/adb-mcp-setup.md`

### Option B: SQLcl local (any Oracle 23ai/26ai)

1. Add SQLcl as MCP server:
   ```json
   {
     "mcpServers": {
       "sqlcl": {
         "command": "/path/to/sqlcl/bin/sql",
         "args": ["-mcp"]
       }
     }
   }
   ```

2. Start a conversation.

> Full details: `clients/README.md`

---

## What the Advisor Knows

### Indexing (simplicity-first)

| Priority | What | When |
|----------|------|------|
| **P0** | PK indexes | Always (Oracle creates automatically — just verify) |
| **P1** | Edge FK indexes (source_key, destination_key) | Always — the #1 gap in most graph deployments |
| **P2** | Filter indexes | Only if EXPLAIN PLAN shows full scan + selectivity < 5% |
| **P3** | Composite (filter + FK) | Only if both columns appear in the same expensive plan |
| **P4** | Advanced (partitioning, IOT, bitmap) | Only at scale (>10M edges) with measured problems |

Most graphs need only P0 + P1. Auto Indexing on ADB handles additional single-column filters reactively — the advisor focuses on FK indexes (proactive) and graph-aware composites (which Auto Indexing can't create).

### Oracle Internals

- **GRAPH_TABLE translation** — reads execution plans as relational join trees
- **SQL/PGQ feature matrix** — variable-length paths `{n,m}`, ONE ROW PER, JSON properties
- **CBO behavior** — predicate pushdown, join order, adaptive plans
- **AWR/ASH** — historical trends and P90/P99 when available

### Domain Patterns

14+ pre-built graph query patterns across fraud detection, social network, supply chain, and e-commerce — each with expected plan shape, index strategy, and anti-patterns.

### Anti-Patterns (9 actively flagged)

Missing DBMS_STATS, over-indexing INSERT-heavy edge tables, unconstrained multi-hop cartesian explosions, SYSTIMESTAMP type mismatch preventing index use, VERTEX_ID/EDGE_ID client overhead, co-view fan-out scaling, and more.

---

## SQL Templates

40+ templates in `sql-templates/`, selected and parameterized automatically:

| File | Phase | Templates |
|------|-------|-----------|
| `00-health-check.sql` | Health Check + Auto Indexing | HEALTH-00 to -10c |
| `01-discovery.sql` | Discovery | DISCOVERY-01 to -06 |
| `02-identify.sql` | Identify | IDENTIFY-01 to -05 |
| `03-analyze.sql` | Deep Dive | ANALYZE-01 to -05 |
| `04-selectivity-and-simulate.sql` | Selectivity + Simulate | SELECTIVITY-01 to -04, SIMULATE-01 to -05 |
| `05-utilities.sql` | Utilities | UTIL-01 to -09 |

---

## Client Support

| Client | MCP Transport | System Prompt |
|--------|---------------|---------------|
| **Any client (ADB native)** | HTTPS endpoint | Same as below per client |
| **Claude Code** | `.mcp.json` | `CLAUDE.md` (auto-loaded) |
| **Claude Desktop** | Manual config | Create Project → add `SYSTEM_PROMPT.md` |
| **VS Code + Copilot** | `.vscode/mcp.json` | `.github/copilot-instructions.md` |
| **Cline** | MCP settings | `.clinerules` |
| **Cursor** | MCP settings | `.cursor/rules/oracle-graph-dba.mdc` |

Minimum model: 30B+ parameters. Tested with Claude Sonnet/Opus, GPT-4o, Gemini Pro, Qwen2.5-72B, Llama-3.1-70B.

---

## Knowledge Base

| Directory | Content |
|-----------|---------|
| `graph-patterns/` | Fraud detection, social network, supply chain, use case assessment |
| `graph-design/` | Modeling checklist (8 rules), physical design, query best practices |
| `optimization-rules/` | Advanced indexing, Auto Indexing + graphs, JSON/vector edge cases |
| `oracle-internals/` | CBO behavior, SQL/PGQ feature matrix, PGX vs SQL/PGQ |

Knowledge files include version metadata (`verified_version`, `last_verified`). The advisor flags when your DB version is newer than the knowledge. See `knowledge/FRESHNESS.md`.

---

## Project Structure

```
oracle-graph-dba-advisor/
├── SYSTEM_PROMPT.md                       # Advisor brain (methodology + knowledge)
├── SKILL.md                               # Skill manifest
├── CLAUDE.md                              # Claude Code auto-loader
├── .mcp.json                              # Claude Code MCP config
├── config/
│   └── production-guard.yaml              # Production detection rules (customize)
├── clients/                               # Setup guides per client
├── sql-templates/                         # 40+ diagnostic SQL templates
├── knowledge/                             # Patterns, rules, Oracle internals
├── memory/                                # Persistent state (gitignored)
├── agent/                                 # Optional: n8n workflows for automation
└── workload/
    ├── fraud/                             # Sample fraud detection workload
    └── demo/                              # End-to-end demo (~45 min)
```

---

## Extending

**New graph patterns** — Add `.md` files to `knowledge/graph-patterns/`. The advisor picks them up automatically.

**Custom SQL templates** — Add `.sql` files to `sql-templates/` and reference in `SYSTEM_PROMPT.md`.

---

## Credits

Built on [Oracle SQLcl MCP Server](https://docs.oracle.com/en/database/oracle/sql-developer-command-line/) · Oracle Database 23ai/26ai · [SQL/PGQ (ISO SQL:2023)](https://blogs.oracle.com/database/property-graphs-in-oracle-database-23ai-the-sql-pgq-standard)
