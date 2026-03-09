# Oracle Graph DBA Advisor — Skill Manifest

## Identity

- **Name**: Oracle Graph DBA Advisor
- **Type**: Diagnostic + Advisory skill
- **Domain**: Oracle Property Graph (SQL/PGQ) on Oracle Database 23ai / 26ai
- **Scope**: Performance optimization, graph design review, best practices validation, workload diagnostics

## What It Does

Analyzes Oracle SQL/PGQ property graph workloads and produces actionable recommendations. Covers six areas:

0. **Health Check** — Assesses database resource utilization (CPU, I/O, memory, tablespace) before graph analysis. Uses AWR/ASH historical data when available (24h trends, percentiles); falls back to V$ real-time views when not. Flags capacity constraints and recommends scaling/tuning
1. **Discovery** — Maps property graphs, underlying tables, volumes, indexes, statistics freshness
2. **Identification** — Finds the most expensive graph queries in V$SQL, classifies by pattern type
3. **Deep Dive** — Reads execution plans, identifies full scans, join order issues, cardinality misestimates
4. **Selectivity Analysis** — Quantifies index benefit using column statistics and value distribution
5. **Simulation** — Tests index impact with invisible indexes before committing
6. **Recommendation** — Produces DDL with justification, rollback commands, and DML impact assessment
7. **Scalability Testing** — Generates synthetic data at configurable scale (2X, 5X, 10X), re-runs diagnostics, and reports which metrics scale linearly vs. superlinearly

Additionally reviews graph design decisions (modeling, key choices, edge/vertex granularity) and validates query writing best practices (bind variables, projection, depth limits).

## Required Tools

| Tool | Provider | Purpose |
|------|----------|---------|
| `run-sql` | SQLcl MCP Server | Execute diagnostic SQL queries |
| `run-sqlcl` | SQLcl MCP Server | Execute SQLcl commands |
| `connect` | SQLcl MCP Server | Establish database connection |
| `disconnect` | SQLcl MCP Server | Close database connection |
| File read/write | MCP client (filesystem) | Persistent memory (optional) |

## Required Infrastructure

**Primary — ADB Native MCP (zero client installation):**
- Oracle Autonomous AI Database (Serverless) with MCP server enabled
- Tools registered via `DBMS_CLOUD_AI_AGENT.CREATE_TOOL`
- Only `npx` needed on client side (comes with Node.js)

**Alternative — SQLcl MCP (any Oracle 23ai/26ai):**
- Oracle SQLcl 25.2+ configured as MCP Server (`sql -mcp`)
- Java 17+
- A saved database connection with stored password

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| Database connection name | Yes | Name of saved SQLcl connection |
| Focus area (optional) | No | Specific graph, table, or query to prioritize |
| Past memory context | No | `memory/{env}/` files if available |

## Outputs

| Output | Format | Description |
|--------|--------|-------------|
| Recommendations | Structured text | DDL + justification + rollback for each finding |
| Schema snapshot | JSON | Graph topology, tables, indexes, volumes |
| Recommendation log | Markdown | Chronological record with status tracking |
| Active issues | Markdown | Unresolved items tracked across sessions |
| Scalability report | Structured text | Before/after/scaled metrics with growth verdicts |
| Test data | PL/SQL | Synthetic graph data preserving realistic distributions |

## Files

| File | Role |
|------|------|
| `SYSTEM_PROMPT.md` | Full methodology, core knowledge, diagnostic phases, output format |
| `sql-templates/*.sql` | Parameterized diagnostic queries (30+ templates, 6 phases) |
| `knowledge/` | Domain patterns, advanced indexing, Oracle internals, design rules |
| `memory/` | Persistent state across sessions (gitignored) |

## How to Invoke

**As a skill in an MCP client** (default):
Load `SYSTEM_PROMPT.md` as system instructions. Connect via ADB native MCP (recommended, zero install) or SQLcl MCP (local). The MCP client provides the agent loop.

**Zero-install path (ADB Serverless):**
Enable the built-in MCP server, register tools with `DBMS_CLOUD_AI_AGENT`, point any MCP client to the HTTPS endpoint. No SQLcl, Java, or local tooling needed. See `clients/adb-mcp-setup.md`.

**As a skill inside an autonomous agent**:
The orchestrator (n8n, LangChain, custom) loads `SYSTEM_PROMPT.md` as the system prompt, provides ADB MCP endpoint or SQLcl MCP tools, and injects the trigger context (e.g., "run health check on PROD_ADB"). See `agent/` for n8n workflow templates.

**Minimum model requirements**:
30B+ parameters. The skill requires execution plan interpretation, multi-step diagnostic reasoning, and Oracle-specific domain knowledge. Tested with: Claude Sonnet/Opus, GPT-4o, Gemini Pro, Qwen2.5-72B, Llama-3.1-70B.

## Limitations

- Read-only by default — only executes DDL if the user explicitly requests it
- Does not support Oracle 19c (PGQL/PGX architecture is incompatible)
- Cannot run unbounded path queries (SQL/PGQ max quantifier = 10)
- Cannot recommend PGX algorithms — only identifies when PGX would be more appropriate
- Memory is file-based by default (Phase 1) — upgrade to Oracle ADB for semantic search and multi-user (see `memory/backends/oracle-adb-memory.md`)
