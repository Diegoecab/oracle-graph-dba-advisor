# Oracle Graph DBA Advisor

An AI-powered DBA advisor **specialized in Oracle Property Graph (SQL/PGQ) workload optimization**. Built on top of the official Oracle SQLcl MCP Server — zero custom infrastructure required.

---

## What This Is

A **system prompt framework + diagnostic SQL templates** that turns Claude (or any MCP-compatible LLM) into an expert Oracle DBA that specifically understands how `GRAPH_TABLE` queries translate into relational plans, where the optimizer struggles with graph patterns, and what indexes actually help.

```
You:     "Analyze my graph workload and tell me what's slow and why"

Agent:   1. Discovers your property graphs, tables, volumes
         2. Finds the most expensive graph queries in V$SQL
         3. Reads their execution plans, identifies full scans on edge tables
         4. Analyzes column selectivity to quantify index benefit
         5. Simulates improvements with invisible indexes
         6. Produces CREATE INDEX DDL with plain-language justification
         7. Includes rollback commands for every recommendation
```

Unlike Oracle's built-in Automatic Indexing (which is a black box that says "benefit: 847"), this advisor **explains why** each index helps in graph-specific terms: "This composite index on `transfers(is_suspicious, merchant_id)` eliminates 99.5% of edge rows before the hash join to merchants, reducing the fan-in pattern from 1M to 5K intermediate rows."

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                Claude / MCP-compatible LLM                   │
│                                                              │
│  SYSTEM_PROMPT.md loaded as project instructions             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Graph DBA Methodology                                 │ │
│  │  ├─ How GRAPH_TABLE expands to joins internally        │ │
│  │  ├─ 6-phase diagnostic workflow                        │ │
│  │  ├─ 5 index strategies ranked by impact                │ │
│  │  ├─ Anti-patterns to flag                              │ │
│  │  └─ Output format for recommendations                  │ │
│  └────────────────────────────────────────────────────────┘ │
│                          │                                   │
│                     MCP Protocol                             │
│                    (run-sql tool)                             │
│                          │                                   │
└──────────────────────────┼──────────────────────────────────┘
                           │
                           ▼
               ┌───────────────────────┐
               │   SQLcl MCP Server    │
               │   (Oracle official)   │
               │                       │
               │   Tools:              │
               │   ├─ list-connections │
               │   ├─ connect          │
               │   ├─ run-sql     ◄────── Executes SQL templates
               │   ├─ run-sqlcl        │
               │   └─ disconnect       │
               └───────────┬───────────┘
                           │
                    mTLS / TCP / ORDS
                           │
                           ▼
               ┌───────────────────────┐
               │   Oracle ADB-S 23ai  │
               │   (or 26ai, or 19c+) │
               │                       │
               │   V$SQL               │  ← Always Free ✓
               │   V$SQL_PLAN          │  ← Always Free ✓
               │   V$SQL_PLAN_STATS    │  ← Always Free ✓
               │   USER_PROPERTY_GRAPHS│  ← Always Free ✓
               │   USER_TAB_COL_STATS  │  ← Always Free ✓
               │   DBA_INDEX_USAGE     │  ← 23ai+ ✓
               │   DBMS_XPLAN         │  ← Always Free ✓
               └───────────────────────┘
```

---

## Prerequisites

1. **Oracle SQLcl 25.2+** installed (`sql -version`)
2. **Java 17+** (`java -version`)
3. **A saved database connection** with the password stored:
   ```bash
   sql /nolog
   SQL> conn -save MyADB -savepwd admin/MyPass@adb_host:1522/mydb_low
   ```
4. **Claude Desktop**, **VS Code + Copilot**, **Cline**, or any MCP client

---

## Multi-LLM Client Support

This project works with any MCP-compatible LLM client. Configuration files are included for each:

| Client | Config File | Auto-loaded |
|--------|-------------|-------------|
| **Claude Code** | `.mcp.json` (root) | Yes |
| **Claude Desktop** | See setup below | Manual |
| **VS Code + Copilot** | `.vscode/mcp.json` + `.github/copilot-instructions.md` | Yes |
| **Cline** | `.clinerules` | Yes |
| **Cursor** | `.cursor/rules/oracle-graph-dba.mdc` | Yes |
| **Continue** | `clients/continue-config-example.json` | Manual |

See `clients/README.md` for detailed setup instructions per client.

---

## Setup

### Step 1: Configure SQLcl as MCP Server

**Claude Code** — use the `.mcp.json` already in the project root, or create your own:
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

**Claude Desktop** — edit `claude_desktop_config.json`:
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

**VS Code + Copilot** — the `.vscode/mcp.json` is already configured. If using the Oracle SQL Developer Extension, MCP is registered automatically.

**Cline** — the `.clinerules` file is auto-loaded. Configure MCP in Cline settings:
```json
{
  "mcpServers": {
    "sqlcl": {
      "command": "/path/to/sqlcl/bin/sql",
      "args": ["-mcp"],
      "disabled": false
    }
  }
}
```

**Cursor** — the `.cursor/rules/oracle-graph-dba.mdc` is auto-loaded for matching files.

### Step 2: Load the System Prompt

**Option A — Claude Project (recommended):**
Create a Claude Project and add `SYSTEM_PROMPT.md` as Project Instructions. This way every conversation in the project gets the Graph DBA persona automatically.

**Option B — Paste at conversation start:**
Copy the contents of `SYSTEM_PROMPT.md` and paste it as the first message in a new conversation with the prefix "Use these instructions for this conversation:".

**Option C — Claude Code / Cline / Cursor:**
Place `SYSTEM_PROMPT.md` and the `sql-templates/` directory in your project root. The agent reads them with file access tools. Client-specific rules files (`.clinerules`, `.cursor/rules/`) reference the system prompt automatically.

### Step 3: Connect and Analyze

Start a conversation:

```
"Connect to MyADB and analyze my graph workloads.
 Focus on the transaction_pg graph — transfers table has 1M rows
 and some queries are slow."
```

The agent will:
1. Use `connect` tool to establish the database session
2. Run DISCOVERY templates to map the graph topology
3. Run IDENTIFY templates to find expensive queries
4. Deep-dive into execution plans
5. Analyze selectivity and simulate improvements
6. Present recommendations with DDL and justification

---

## SQL Template Reference

All templates are in `sql-templates/` and organized by diagnostic phase. The agent selects and parameterizes them dynamically — you don't need to run them manually.

| File | Phase | Templates |
|------|-------|-----------|
| `01-discovery.sql` | Discovery | DISCOVERY-01 through DISCOVERY-06 |
| `02-identify.sql` | Identify | IDENTIFY-01 through IDENTIFY-05 |
| `03-analyze.sql` | Deep Dive | ANALYZE-01 through ANALYZE-05 |
| `04-selectivity-and-simulate.sql` | Selectivity + Simulate | SELECTIVITY-01 through -04, SIMULATE-01 through -05 |
| `05-utilities.sql` | Actions | UTIL-01 through UTIL-09 (stats, index mgmt, reporting) |

### Key Templates

**DISCOVERY-06** (Edge FK Index Gap Analysis) — The single most important diagnostic query. Finds edge table foreign key columns that lack indexes. This is the #1 optimization opportunity in virtually every property graph deployment.

**ANALYZE-03** (Full Table Scans on Graph Tables) — Finds all full scans on graph underlying tables across all cached SQL. Each one is a potential index candidate.

**SELECTIVITY-04** (Edge Degree Distribution) — Shows vertex degree distribution (edges per vertex). Essential for understanding fan-out explosion in multi-hop patterns.

**UTIL-09** (Complete Diagnostic Snapshot) — Single query that combines discovery + identify + analyze into a health check summary.

---

## What the Agent Knows About Graphs

The system prompt encodes deep knowledge about how Oracle processes SQL/PGQ internally:

**Translation model**: Every `GRAPH_TABLE(MATCH ...)` expression becomes a set of relational joins. The agent understands that a 2-hop pattern = 2 edge joins + 3 vertex joins, and costs grow multiplicatively.

**Five index strategies**, prioritized:
1. Edge FK indexes (source_key, destination_key) — almost always missing, almost always beneficial
2. Filtered edge indexes — for predicates like `is_suspicious = 'Y'`
3. Composite edge indexes — filter + FK in one index (highest single-query impact)
4. Vertex property indexes — for filtered traversal start points
5. Temporal indexes — for date-range filtered graph queries

**Six anti-patterns** the agent actively flags:
1. Missing DBMS_STATS after data load
2. Over-indexing INSERT-heavy edge tables
3. Redundant indexes on PK columns
4. Full scans that are actually optimal (small tables)
5. N+1 query patterns in application code
6. Unconstrained multi-hop cartesian explosions

---

## AWR/ASH Support and Always Free Compatibility

The advisor **prefers AWR/ASH views** (`DBA_HIST_SQLSTAT`, `DBA_HIST_ACTIVE_SESS_HISTORY`) for historical trends, P90/P99 analysis, and workload evolution. If access is denied (Always Free tier or restricted privileges), it automatically falls back to `V$SQL`, `V$SQL_PLAN`, and `USER_*` views.

| View | Always Free | Paid |
|------|-------------|------|
| `V$SQL` | ✅ | ✅ |
| `V$SQL_PLAN` | ✅ | ✅ |
| `V$SQL_PLAN_STATISTICS_ALL` | ✅ | ✅ |
| `USER_PROPERTY_GRAPHS` | ✅ | ✅ |
| `USER_TAB_COL_STATISTICS` | ✅ | ✅ |
| `DBA_INDEX_USAGE` (23ai+) | ✅ | ✅ |
| `DBA_HIST_SQLSTAT` (AWR) | ❌ | ✅ |

---

## Example Session

```
User: Connect to my graph database and check if there are any
      index optimization opportunities for my property graphs.

Agent: [connect MyADB]
       [run-sql UTIL-08]  → Graph topology summary
       [run-sql DISCOVERY-06] → Edge FK gap analysis

       I found 2 property graphs: social_pg and transaction_pg.
       
       Critical finding: the TRANSFERS edge table (1M rows) is
       missing indexes on both FK columns:
       - from_account_id (SOURCE_FK) — NO INDEX
       - merchant_id (DESTINATION_FK) — NO INDEX
       
       This means every graph traversal involving transfers does
       a full table scan of 1M rows for vertex lookups.
       
       Let me check which queries are most affected...

       [run-sql IDENTIFY-01] → Top queries by elapsed
       [run-sql ANALYZE-01 for top SQL_ID] → Execution plan
       
       The fraud ring detection query (SQL_ID: abc123) consumes
       45M buffer gets per execution. The plan shows:
       
       HASH JOIN
         TABLE ACCESS FULL — TRANSFERS (1,000,000 rows)
           filter: IS_SUSPICIOUS = 'Y'
         TABLE ACCESS FULL — TRANSFERS (1,000,000 rows)
         INDEX UNIQUE SCAN — MERCHANTS_PK
       
       [run-sql SELECTIVITY-01 for is_suspicious]
       
       is_suspicious = 'Y' matches 0.5% of rows (5,000 of 1M).
       
       RECOMMENDATION #1
       ━━━━━━━━━━━━━━━━━━
       Target:     TRANSFERS(IS_SUSPICIOUS, MERCHANT_ID)
       DDL:        CREATE INDEX idx_transfers_susp_merch
                   ON transfers(is_suspicious, merchant_id) INVISIBLE;
       Impact:     Estimated 45M → ~50K buffer gets (99% reduction)
       Why:        Composite index satisfies both the edge filter
                   (is_suspicious='Y') and the destination vertex
                   join (merchant_id) in a single index range scan.
                   Only 5K rows enter the join instead of 1M.
       Rollback:   ALTER INDEX idx_transfers_susp_merch INVISIBLE;
       
       Shall I create this as an invisible index so we can test?
```

---

## Project Structure

```
oracle-graph-dba-advisor/
├── README.md                              # This file
├── SYSTEM_PROMPT.md                       # The AI DBA brain — load as project instructions
├── .mcp.json                              # Claude Code MCP config
├── .clinerules                            # Cline rules (auto-loaded)
├── .gitignore
├── .vscode/
│   └── mcp.json                           # VS Code MCP server config
├── .github/
│   └── copilot-instructions.md            # GitHub Copilot agent instructions
├── .cursor/
│   └── rules/
│       └── oracle-graph-dba.mdc           # Cursor rules (auto-loaded)
├── clients/
│   ├── README.md                          # Client setup guide
│   └── continue-config-example.json       # Continue MCP config example
├── sql-templates/
│   ├── 01-discovery.sql                   # Graph topology, indexes, stats
│   ├── 02-identify.sql                    # Top expensive graph queries
│   ├── 03-analyze.sql                     # Execution plans, full scans, joins
│   ├── 04-selectivity-and-simulate.sql    # Selectivity + index simulation
│   └── 05-utilities.sql                   # Stats, index mgmt, reporting
├── knowledge/
│   ├── README.md                          # Extension guide
│   ├── graph-patterns/
│   │   ├── README.md                      # Pattern format specification
│   │   ├── fraud-detection.md             # 5 fraud graph patterns
│   │   ├── social-network.md              # 5 social graph patterns
│   │   └── supply-chain.md                # 4 supply chain patterns
│   ├── optimization-rules/
│   │   └── advanced-indexing.md           # 7 advanced indexing strategies
│   └── oracle-internals/
│       ├── pgq-optimizer-behavior.md      # CBO behavior with GRAPH_TABLE
│       └── official-documentation-reference.md  # Feature matrix, URLs, perf models
└── workload/
    └── fraud/                             # Fraud detection workload generator
        ├── 00_README.sql                  # Execution guide
        ├── 01_create_schema.sql           # Vertex + edge tables
        ├── 02_create_property_graph.sql   # FRAUD_GRAPH definition
        ├── 03_generate_data.sql           # ~420K edges, ~108K vertices
        ├── 04_workload_queries.sql        # Individual test queries
        └── 05_run_workload.sql            # Automated workload runner
```

---

## Knowledge Extensions

The `knowledge/` directory provides domain-specific graph patterns and advanced optimization rules that the advisor uses to enhance its recommendations:

### Graph Patterns (`knowledge/graph-patterns/`)

| Domain | File | Patterns | Key Scenarios |
|--------|------|----------|---------------|
| Fraud Detection | `fraud-detection.md` | 5 | Shared device, 2-hop chains, triangles, temporal change, risk scoring |
| Social Network | `social-network.md` | 5 | Mutual friends, influence, communities, recommendations, shortest path |
| Supply Chain | `supply-chain.md` | 4 | BOM dependencies, risk propagation, logistics routing, commonality |

Each pattern includes: SQL/PGQ query, performance characteristics, index strategy, anti-patterns, and real-world frequency.

### Advanced Indexing (`knowledge/optimization-rules/`)

7 strategies beyond the base 5: bidirectional FK coverage, composite graph covering indexes, function-based indexes, partial indexes (23ai), IOT edge tables, bitmap indexes, invisible index A/B testing.

### Oracle Internals (`knowledge/oracle-internals/`)

CBO behavior with GRAPH_TABLE (6 topics), plus official documentation reference with SQL/PGQ feature matrix by version, variable-length path `{n,m}` performance model, ONE ROW PER cardinality multipliers, JSON property indexing, and verified Oracle documentation URLs.

### Adding Your Own

See `knowledge/README.md` for the extension guide and `knowledge/graph-patterns/README.md` for the pattern format specification.

---

## Extending

**Add new graph patterns**: Create a new `.md` file in `knowledge/graph-patterns/` following the format in `knowledge/graph-patterns/README.md`. The advisor automatically picks up new files.

**Add AWR templates**: For paid tier, add an `06-awr.sql` template file with `DBA_HIST_SQLSTAT` and `DBA_HIST_ACTIVE_SESS_HISTORY` queries for historical trend analysis.

**Multi-schema support**: The templates use `USER_*` views (current schema). To analyze other schemas, replace with `ALL_*` or `DBA_*` views and add an `:owner` bind variable.

**Custom MCP server**: If you need higher-level tools (e.g., `analyze_graph_workload` as a single tool call), wrap the SQL templates in a custom MCP server that delegates to SQLcl or ORDS.

---

## Credits

Built on: Oracle SQLcl MCP Server (official), Oracle ADB-S 23ai, SQL/PGQ (ISO SQL:2023).

Inspired by: D-Bot/DB-GPT (Tsinghua University) for the LLM-as-DBA concept, adapted and specialized for Oracle Property Graphs.
