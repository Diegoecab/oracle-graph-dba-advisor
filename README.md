# Oracle Graph DBA Advisor

An AI-powered advisor for **Oracle Property Graph (SQL/PGQ) on Oracle Database 23ai and 26ai** — covering performance optimization, graph design review, best practices validation, and workload diagnostics.

Built on top of the **Oracle ADB MCP Server** (fully managed, zero install) or the **SQLcl MCP Server** (local, any Oracle 23ai/26ai).

---

## Why Use This Skill vs a Plain LLM

A generic LLM can write SQL and read documentation — but it lacks the **structured methodology, pre-built diagnostic queries, and domain-specific knowledge** needed to reliably optimize Oracle Graph workloads. Here's what the skill adds:

| Capability | Plain LLM | With this skill |
|---|---|---|
| **Diagnostic methodology** | Ad-hoc questions, no systematic approach | 6-phase structured methodology (Discovery → Identify → Deep Dive → Selectivity → Simulate → Recommend) executed in order |
| **SQL templates** | Generates SQL from scratch each time — may be incorrect, incomplete, or use wrong views | 30+ pre-built, tested templates for Oracle 23ai/26ai property graph diagnostics (`V$SQL`, `DBMS_XPLAN`, `ALL_PG_ELEMENTS`, AWR/ASH) |
| **GRAPH_TABLE understanding** | Treats graph queries as black boxes | Knows that `GRAPH_TABLE(MATCH ...)` expands to relational joins — reads execution plans as join trees and traces each TABLE ACCESS / HASH JOIN back to the graph pattern hop |
| **Index strategy** | Generic "add an index" advice | 5 prioritized strategies specific to graph workloads: edge FK indexes, filtered edge indexes, composite covering indexes, vertex property indexes, temporal indexes — plus 7 advanced strategies |
| **Anti-pattern detection** | May not recognize graph-specific pitfalls | Actively flags: missing `DBMS_STATS`, unconstrained `{n,m}` cartesian explosions, over-indexing INSERT-heavy edge tables, redundant PK indexes, `SYSTIMESTAMP` vs `SYSDATE` type mismatch preventing index use |
| **Evaluation metric** | Often reports optimizer cost (arbitrary CBO units) | Always measures **actual elapsed time** — never evaluates by optimizer cost, which can be misleading (a higher-cost plan can execute faster) |
| **Recommendations** | Generic suggestions without DDL | Produces complete DDL with impact quantification (elapsed time reduction), rollback commands, and DML overhead assessment |
| **Persistent memory** | Starts from zero each session | Remembers schemas, past recommendations, and their outcomes across sessions — skips re-discovery on repeat visits |
| **Domain patterns** | No pre-built knowledge of graph use cases | 14+ pre-built patterns across fraud detection, social network, supply chain, and e-commerce recommendations — each with expected plan shape, index strategy, and anti-patterns |
| **Use case assessment** | Cannot evaluate whether data fits a graph model | Consultive mode: assesses relational schemas for graph potential, designs vertex/edge models, validates against 8 modeling rules, generates implementation scripts |
| **Always Free compatible** | May attempt queries that fail on restricted environments | Automatically falls back from AWR/ASH to `V$SQL` + `USER_*` views when access is denied — works on Always Free tier without manual intervention |

**In short**: a plain LLM might get you 60% of the way with generic Oracle advice. This skill provides the remaining 40% — the structured diagnostic process, the graph-specific expertise, and the pre-tested queries that make the difference between a vague suggestion and an actionable recommendation with measured impact.

---

## What This Is

A **system prompt + diagnostic SQL templates + knowledge base** that turns any MCP-compatible LLM into an Oracle Graph advisor. It understands how `GRAPH_TABLE` queries expand into relational joins, identifies performance bottlenecks, reviews graph design decisions, and recommends improvements.

```
You:     "Analyze my graph workload and tell me what's slow and why"

Agent:   1. Discovers property graphs, tables, volumes, and design
         2. Finds the most expensive graph queries by elapsed time
         3. Reads execution plans, identifies bottlenecks
         4. Reviews graph modeling (edge/vertex design, key choices)
         5. Analyzes selectivity to quantify index benefit
         6. Simulates improvements with invisible indexes
         7. Produces recommendations with DDL, measured elapsed time reduction, and rollback
```

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

The advisor uses AWR/ASH views (`DBA_HIST_SQLSTAT`, `DBA_HIST_ACTIVE_SESS_HISTORY`) for historical trend analysis and P90/P99 metrics when available. On Always Free tier or restricted environments, it automatically falls back to `V$SQL`, `V$SQL_PLAN`, `ALL_PG_ELEMENTS`, `DBA_INDEX_USAGE`, and `DBMS_XPLAN`.

---

## Prerequisites

**Primary path (ADB Serverless — zero install):**
1. Oracle Autonomous AI Database (Serverless) — 23ai or 26ai (including Always Free)
2. MCP server enabled on the ADB instance (one OCI tag)
3. Any MCP client (Claude Desktop, Cursor, Cline, VS Code + Copilot)

**Alternative path (any Oracle database):**
1. Oracle Database 23ai or 26ai (ADB-D, Base DB, or Free tier)
2. Oracle SQLcl 25.2+ installed locally (`sql -version`)
3. Java 17+ (`java -version`)
4. A saved database connection: `conn -save MyADB -savepwd admin/MyPass@host:1522/mydb_low`

---

## Quick Start

### Option A: ADB Serverless (recommended — zero install)

**Step 1:** Enable the MCP server on your ADB instance (OCI Console → free-form tag):
```
Tag: adb$feature → {"name":"mcp_server","enable":true}
```

**Step 2:** Register the advisor's SQL tool — connect to your ADB and run:
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

**Step 3:** Configure your MCP client with the ADB endpoint:
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

**Step 4:** Start a conversation — the system prompt loads automatically via CLAUDE.md / .clinerules / copilot-instructions.md.

> Full setup details: `clients/adb-mcp-setup.md`

### Option B: SQLcl local (any Oracle 23ai/26ai)

For ADB Dedicated, Base DB, on-prem, or Free tier where ADB native MCP isn't available:

**Step 1:** Add SQLcl as MCP server in your client config:
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

**Step 2:** Start a conversation.

> Full setup details: `clients/README.md`

### Connect and Analyze

```
"Connect to MyADB and analyze my graph workloads.
 Focus on the transaction_pg graph — transfers table has 1M rows
 and some queries are slow."
```

The agent will connect, discover your graphs, find expensive queries, analyze execution plans, and deliver recommendations with DDL and rollback commands.

The advisor remembers context between sessions — schemas, past recommendations, and their outcomes — in the `memory/` directory. On first connect it creates a snapshot; on subsequent sessions it uses it to skip re-discovery and track progress. Memory is file-based by default (zero infrastructure). For enterprise teams, it can be upgraded to a centralized Oracle ADB repository with semantic search — see `memory/backends/oracle-adb-memory.md`.

---

## Multi-LLM Client Support

| Client | MCP Transport | System Prompt |
|--------|---------------|---------------|
| **Any client (ADB native)** | HTTPS endpoint (zero install) | Same as below per client |
| **Claude Code** | `.mcp.json` | `CLAUDE.md` (auto-loaded) |
| **Claude Desktop** | Manual config | Create Project → add `SYSTEM_PROMPT.md` |
| **VS Code + Copilot** | `.vscode/mcp.json` | `.github/copilot-instructions.md` (auto-loaded) |
| **Cline** | MCP settings | `.clinerules` (auto-loaded) |
| **Cursor** | MCP settings | `.cursor/rules/oracle-graph-dba.mdc` (auto-loaded) |
| **Continue** | `clients/continue-config-example.json` | Manual |

**Minimum model size**: 30B+ parameters recommended. Smaller models may struggle with execution plan interpretation. Tested with: Claude Sonnet/Opus, GPT-4o, Gemini Pro, Qwen2.5-72B, Llama-3.1-70B.

---

## What the Agent Knows

The advisor carries a built-in knowledge base that combines Oracle internal documentation with field-tested optimization patterns. No external lookups needed — everything is embedded in the system prompt and the `knowledge/` directory.

### Oracle Internals (built-in)

- **GRAPH_TABLE translation model** — Every `GRAPH_TABLE(MATCH ...)` rewrites to relational joins. The agent reads execution plans as relational plans (TABLE ACCESS FULL, HASH JOIN, NESTED LOOPS — never "graph traversal") and traces each operation back to the original graph pattern.
- **SQL/PGQ feature matrix** — Knows which features are available in 23ai base vs. Graph Server 25.1+, including variable-length paths `{n,m}` (UNION ALL expansion, max 10), ONE ROW PER cardinality multipliers, JSON property indexing, and AS OF flashback queries.
- **CBO behavior with GRAPH_TABLE** — Rewrite mechanism, join order selection, predicate pushdown rules, statistics impact on plan quality, cursor caching, and adaptive plan behavior.
- **AWR/ASH analysis** — Uses `DBA_HIST_SQLSTAT` and `DBA_HIST_ACTIVE_SESS_HISTORY` for historical trends and P90/P99 analysis. Falls back to `V$SQL` automatically if access is denied (Always Free tier).

### Optimization Strategies (built-in)

**5 index strategies** (prioritized):
1. Edge FK indexes (SRC, DST) — almost always missing, almost always beneficial
2. Filtered edge indexes — for selective predicates like `is_suspicious = 'Y'`
3. Composite covering indexes — filter + FK in one index (index-only scans)
4. Vertex property indexes — for filtered traversal start points
5. Temporal indexes — for date-range filtered graph queries

Plus 7 advanced strategies: bidirectional FK coverage, function-based indexes, partial indexes (23ai), IOT edge tables, bitmap indexes, and invisible index A/B rotation.

### Domain Patterns (knowledge base)

14 pre-built graph query patterns across 3 domains (fraud detection, social network, supply chain), each with: SQL/PGQ query, expected plan shape, index strategy, anti-patterns, and real-world frequency data.

### Anti-patterns (actively flagged)

Missing DBMS_STATS, over-indexing INSERT-heavy edge tables, redundant PK indexes, optimal full scans on small tables, N+1 application patterns, unconstrained multi-hop cartesian explosions, variable-length quantifier `{n,m}` misuse.

---

## SQL Templates

All in `sql-templates/`, selected and parameterized by the agent automatically:

| File | Phase | Templates |
|------|-------|-----------|
| `00-health-check.sql` | Health Check | HEALTH-00 to -06A |
| `01-discovery.sql` | Discovery | DISCOVERY-01 to -06 |
| `02-identify.sql` | Identify | IDENTIFY-01 to -05 |
| `03-analyze.sql` | Deep Dive | ANALYZE-01 to -05 |
| `04-selectivity-and-simulate.sql` | Selectivity + Simulate | SELECTIVITY-01 to -04, SIMULATE-01 to -05 |
| `05-utilities.sql` | Actions | UTIL-01 to -09 |

**Highlights:**
- **DISCOVERY-06** — Edge FK gap analysis. Finds FK columns missing indexes — the #1 optimization opportunity in most graph deployments.
- **ANALYZE-03** — Full table scans on graph tables across all cached SQL.
- **SELECTIVITY-04** — Edge degree distribution (fan-out per vertex).
- **UTIL-09** — Complete health check snapshot in a single query.

---

## Example Session

```
User: Connect to my graph database and analyze my property graphs.
      The transfers table has 1M rows and some queries are slow.

Agent: [connect MyADB]
       [run-sql UTIL-08]  → Graph topology summary
       [run-sql DISCOVERY-06] → Edge FK gap analysis

       I found 2 property graphs: social_pg and transaction_pg.
       
       DESIGN OBSERVATION
       ━━━━━━━━━━━━━━━━━━
       The TRANSFERS edge table uses a composite natural key
       (from_account_id, to_account_id, transfer_date) as PK.
       This is good for uniqueness but suboptimal for graph
       traversals — the CBO cannot use this PK efficiently for
       single-column FK lookups.
       
       Critical finding: TRANSFERS (1M rows) is missing indexes
       on both FK columns:
       - from_account_id (SOURCE_FK) — NO INDEX
       - merchant_id (DESTINATION_FK) — NO INDEX
       
       [run-sql IDENTIFY-01] → Top queries by elapsed
       [run-sql ANALYZE-01 for top SQL_ID] → Execution plan
       
       The fraud ring query (SQL_ID: abc123) averages 5.3 ms elapsed.

       [run-sql SELECTIVITY-01 for is_suspicious]

       is_suspicious = 'Y' matches 0.5% of rows (5,000 of 1M).

       RECOMMENDATION #1 — Index
       ━━━━━━━━━━━━━━━━━━━━━━━━━
       Target:     TRANSFERS(IS_SUSPICIOUS, MERCHANT_ID)
       DDL:        CREATE INDEX idx_transfers_susp_merch
                   ON transfers(is_suspicious, merchant_id) INVISIBLE;
       Impact:     Avg elapsed 5.3 ms → 0.4 ms (92% reduction)
       Why:        Composite index covers both the edge filter and
                   the destination vertex join in a single scan.
       Rollback:   ALTER INDEX idx_transfers_susp_merch INVISIBLE;
       
       RECOMMENDATION #2 — Best Practice
       ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
       The fraud ring query uses {1,4} variable-length pattern
       with no WHERE predicate on the starting vertex — this is a
       cartesian explosion. Add a filter on the start vertex
       (risk_score, account_status, or a specific account_id).
       
       Shall I create the invisible index so we can test?
```

---

## Architecture: Skill vs Agent

This project is a **skill** — a system prompt, SQL templates, and knowledge base that works inside any MCP-compatible client. For most users, this is all you need.

| Use case | What to use |
|---|---|
| Interactive analysis in Claude Code, Copilot, Cursor | The skill (default) |
| Autonomous health checks, alerts, post-deploy verification | The agent layer (`agent/`) |

The agent layer is optional. It wraps the same skill in an orchestrator (n8n) to add triggers (cron, Slack, webhooks) and shared state. See `agent/README.md` for details.

---

## Knowledge Base

The `knowledge/` directory provides domain-specific patterns and rules the advisor consults during analysis:

| Directory | Content |
|-----------|---------|
| `graph-patterns/fraud-detection.md` | 5 patterns: shared device, 2-hop chains, triangles, temporal change, risk scoring |
| `graph-patterns/social-network.md` | 5 patterns: mutual friends, influence, communities, recommendations, shortest path |
| `graph-patterns/supply-chain.md` | 4 patterns: BOM dependencies, risk propagation, routing, commonality |
| `graph-patterns/use-case-assessment.md` | When/how to recommend new graph use cases from relational data |
| `graph-design/` | Modeling checklist (8 rules), physical design, query best practices |
| `optimization-rules/advanced-indexing.md` | 7 strategies: bidirectional FKs, covering indexes, function-based, partial, IOT, bitmap, invisible A/B |
| `oracle-internals/pgq-optimizer-behavior.md` | CBO behavior with GRAPH_TABLE (6 topics) |
| `oracle-internals/official-documentation-reference.md` | SQL/PGQ feature matrix by version, `{n,m}` performance model, verified doc URLs |
| `oracle-internals/pgx-vs-sqlpgq.md` | Decision guide: SQL/PGQ vs PGX, decision matrix, hybrid approach |
| `rag/` | Vectorized documentation layer for deep retrieval (Oracle docs, custom docs) |

**Add your own**: Create `.md` files in `knowledge/graph-patterns/` following the format in `knowledge/graph-patterns/README.md`. The advisor picks them up automatically.

---

## Project Structure

```
oracle-graph-dba-advisor/
├── SYSTEM_PROMPT.md                       # Advisor methodology & knowledge
├── SKILL.md                               # Skill manifest (inputs, outputs, limitations)
├── CLAUDE.md                              # Claude Code auto-loader
├── .mcp.json                              # Claude Code MCP config
├── .clinerules                            # Cline rules
├── .vscode/mcp.json                       # VS Code MCP config
├── .github/copilot-instructions.md        # Copilot instructions
├── .cursor/rules/oracle-graph-dba.mdc     # Cursor rules
├── config/
│   ├── README.md                          # Configuration guide
│   └── production-guard.yaml              # Production detection rules (customize per org)
├── clients/
│   ├── README.md                          # Client setup guide
│   ├── adb-mcp-setup.md                   # ADB native MCP server (zero-install)
│   └── continue-config-example.json       # Continue config
├── sql-templates/
│   ├── 00-health-check.sql               # Phase 0: DB health check (CPU, I/O, memory)
│   ├── 01-discovery.sql
│   ├── 02-identify.sql
│   ├── 03-analyze.sql
│   ├── 04-selectivity-and-simulate.sql
│   └── 05-utilities.sql
├── knowledge/
│   ├── graph-patterns/                    # Domain-specific patterns + use case assessment
│   ├── graph-design/                      # Modeling rules, physical design, query practices
│   ├── optimization-rules/                # Advanced indexing strategies
│   ├── oracle-internals/                  # CBO behavior, feature matrix, PGX vs SQL/PGQ
│   └── rag/                               # Vectorized documentation for deep retrieval
├── memory/                                # Persistent memory (gitignored)
│   ├── README.md                          # Memory system docs
│   ├── _templates/                        # Templates for new environments
│   └── backends/                          # Storage backend guides
├── agent/                                 # Optional agent layer
│   ├── README.md                          # When and why to use the agent
│   └── n8n/                               # n8n workflow templates
└── workload/
    ├── fraud/                             # Sample fraud detection workload
    │   ├── 01_create_schema.sql
    │   ├── 02_create_property_graph.sql
    │   ├── 03_generate_data.sql           # ~420K edges, ~108K vertices
    │   ├── 04_workload_queries.sql
    │   └── 05_run_workload.sql
    └── demo/                              # End-to-end demo (fraud detection)
        ├── README.md                      # Demo guide (~45 min)
        ├── 00_demo_script.sql             # 11-step reference script
        └── ADVISOR_DEMO_PROMPT.md         # Copy-paste prompt to start demo
```

---

## Extending

**New graph patterns** — Add `.md` files to `knowledge/graph-patterns/` following the format in `knowledge/graph-patterns/README.md`. The advisor picks them up automatically.

**Custom SQL templates** — Add new `.sql` files to `sql-templates/` for domain-specific diagnostics. Reference them in `SYSTEM_PROMPT.md` under the appropriate phase.

---

## Credits

Built on [Oracle SQLcl MCP Server](https://docs.oracle.com/en/database/oracle/sql-developer-command-line/) · Oracle Database 23ai/26ai · [SQL/PGQ (ISO SQL:2023)](https://blogs.oracle.com/database/property-graphs-in-oracle-database-23ai-the-sql-pgq-standard)