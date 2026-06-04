---
name: oracle-graph-dba-advisor
description: Diagnose Oracle SQL/PGQ property graph performance with read-only SQL evidence, templates, and recommendations for ADB Native MCP or SQLcl MCP.
---

# Oracle Graph DBA Advisor — Skill Manifest

## Identity

- **Name**: Oracle Graph DBA Advisor
- **Type**: Diagnostic + Advisory skill
- **Domain**: Oracle Property Graph (SQL/PGQ) on Oracle Database 23ai / 26ai
- **Scope**: Performance optimization, graph design review, best practices validation, workload diagnostics

## What It Does

Analyzes Oracle SQL/PGQ property graph workloads and produces actionable recommendations. Covers eight phases:

0. **Health Check** — Assesses database resource utilization (CPU, I/O, memory, tablespace) before graph analysis. Uses AWR/ASH historical data when available (24h trends, percentiles); falls back to V$ real-time views when not. Flags capacity constraints and recommends scaling/tuning
1. **Discovery** — For Graph DBA mode, first builds a technical catalog of property graphs, owners, underlying tables, volumes, indexes, and statistics freshness
2. **Identification** — Finds the most expensive graph queries in V$SQL, classifies by pattern type
3. **Deep Dive** — Reads execution plans, identifies full scans, join order issues, cardinality misestimates
4. **Selectivity Analysis** — Quantifies index benefit using column statistics and value distribution
5. **Simulation** — Tests index impact with invisible indexes before committing
6. **Recommendation** — Produces DDL with justification, rollback commands, and DML impact assessment
7. **Scalability Testing** — Generates synthetic data at configurable scale (2X, 5X, 10X), re-runs diagnostics, and reports which metrics scale linearly vs. superlinearly

Additionally integrates with Oracle Auto Indexing on ADB — checks auto-created indexes on graph tables, deduplicates recommendations, and explains how proactive (advisor) and reactive (Auto Indexing) approaches complement each other.

Also reviews graph design decisions (modeling, key choices, edge/vertex granularity) and validates query writing best practices (bind variables, projection, depth limits).

## Required Tools

| Tool | Provider | Purpose |
|------|----------|---------|
| `run-sql` | MCP SQL tool | Execute diagnostic SQL queries |
| `run-sqlcl` | Optional, SQLcl only | Execute SQLcl commands when available |
| `connect` | Optional, SQLcl only | Establish database connection |
| `disconnect` | Optional, SQLcl only | Close database connection |
| File read/write | MCP client (filesystem) | Persistent memory (optional) |

## Mandatory Connection Gate

Before any diagnostic phase, confirm the active database context with a
read-only query for `DB_NAME`, `SERVICE_NAME`, `SESSION_USER`, `CURRENT_USER`,
and `CURRENT_SCHEMA`. If more than one database MCP server or SQL connection is
available, use only the target explicitly named by the user. If the connected
context does not match the requested database/schema/workload, stop and ask the
user to confirm the target before continuing.

## Required Infrastructure

**Default — SQLcl MCP (canonical distribution):**
- Oracle SQLcl 25.2+ configured as MCP Server (`sql -mcp`)
- Java 17+
- A saved database connection with stored password

**Alternative — ADB Native MCP (requires a compatible tool contract):**
- Oracle Autonomous AI Database (Serverless) with MCP server enabled
- Tools registered via `DBMS_CLOUD_AI_AGENT.CREATE_TOOL`
- A compatible read-only `run-sql` tool registered in ADB
- Only `npx` needed on client side (comes with Node.js)

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| Database target | Yes | Saved SQLcl connection to the target graph-owning schema, or the active ADB MCP database/session context |
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
| `sql-templates/*.sql` | Parameterized diagnostic queries (50+ templates, 8-phase workflow) |
| `knowledge/` | Domain patterns, advanced indexing, Oracle internals, design rules |
| `memory/` | Persistent state across sessions (gitignored) |

## How to Invoke

**As a skill in an MCP client** (default):
Load `SYSTEM_PROMPT.md` as system instructions. Connect via SQLcl MCP (default) or ADB native MCP with a compatible `run-sql` contract. The MCP client provides the agent loop.

**SQLcl path (recommended default):**
Run SQLcl as the MCP server and connect using a saved connection to the target schema. See `clients/README.md`.

**Zero-install path (ADB Serverless, optional):**
Enable the built-in MCP server, register a compatible `run-sql` tool with `DBMS_CLOUD_AI_AGENT`, and point any MCP client to the HTTPS endpoint. See `clients/adb-mcp-setup.md`.

**As a skill inside an autonomous agent**:
The orchestrator (n8n, LangChain, custom) loads `SYSTEM_PROMPT.md` as the system prompt, provides ADB MCP endpoint or SQLcl MCP tools, and injects the trigger context (e.g., "run health check on PROD_ADB"). See `agent/` for n8n workflow templates.

**Minimum model requirements**:
30B+ parameters. The skill requires execution plan interpretation, multi-step diagnostic reasoning, and Oracle-specific domain knowledge. Tested with: Claude Sonnet/Opus, GPT-4o, Gemini Pro, Qwen2.5-72B, Llama-3.1-70B.

## Limitations

- Read-only by default — only executes DDL if the user explicitly requests it
- Does not support Oracle 19c (PGQL/PGX architecture is incompatible)
- Cannot run unbounded path queries (SQL/PGQ max quantifier = 10)
- Cannot recommend PGX algorithms — only identifies when PGX would be more appropriate
- The default discovery templates assume the current schema owns the graph objects (`USER_*` views). For Graph DBA observer mode, use the DBA catalog assets such as `sql-templates/01b-graph-dba-catalog.sql`
- Memory is file-based by default (Phase 1) — upgrade to Oracle ADB for semantic search and multi-user (see `memory/backends/oracle-adb-memory.md`)
