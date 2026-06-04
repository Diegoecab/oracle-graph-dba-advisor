# Oracle Graph DBA Advisor

A system prompt, SQL template set, and knowledge base that turns an
MCP-compatible LLM into a read-only Oracle Property Graph performance advisor
for Oracle Database 23ai and 26ai.

The primary path is **Diagnostic Mode**: analyze an existing graph workload,
collect database evidence, explain the root cause, and produce DBA-ready
recommendations. For ADB Serverless, the preferred runtime is **ADB Native MCP**
with one controlled read-only SQL tool.

## What this does

Diagnostic Mode answers questions like:

```text
Analyze my graph workload and tell me what is slow, why it is slow, and what the DBA team should change.
```

The advisor:

1. Confirms the safety posture and stays read-only by default.
2. Builds a database health baseline from performance views.
3. Discovers property graph objects, owners, backing tables, indexes, and stats.
4. Finds expensive SQL/PGQ workload from `V$SQL`, AWR, and ASH.
5. Reads execution plans and maps relational operators back to graph hops.
6. Explains root cause with `SQL_ID`, plan, wait, and object evidence.
7. Produces recommendations with DDL, validation SQL, and rollback text.

The skill is designed for DBAs and platform teams that already have an Oracle
property graph workload and need a repeatable diagnostic workflow without giving
the LLM write access to the database.

## Current focus

| Area | Status | Notes |
|---|---|---|
| Diagnostic Mode | Primary | Customer-facing path for workload diagnosis and tuning. |
| ADB Native MCP | Preferred for ADB Serverless | No SQLcl runtime dependency; expose only approved database-side tools. |
| SQLcl MCP | Secondary fallback | Useful for local, on-prem, Base DB, ADB Dedicated, or non-ADB Native MCP cases. |
| Consultive Mode | Secondary | Design-from-description flow; kept below the diagnostic path. |
| Agent Factory governance | Roadmap | Evaluate only for governance, guardrails, auditing, and tool allowlisting. |

## Architecture

```mermaid
flowchart TB
    user["DBA / Admin<br/>diagnostic request"]
    llm["MCP-compatible LLM<br/>advisor runtime"]

    subgraph skill["Graph DBA Advisor skill"]
        prompt["SYSTEM_PROMPT.md<br/>methodology and safety rules"]
        templates["sql-templates/<br/>diagnostic SQL"]
        knowledge["knowledge/<br/>graph and optimizer rules"]
    end

    subgraph runtime["Primary runtime: ADB Native MCP"]
        endpoint["ADB Native MCP endpoint<br/>one endpoint per target database"]
        auth["OAuth or bearer token<br/>dedicated technical user"]
        tool["RUN_SQL<br/>read-only SELECT/WITH only"]
        guardrails["Database-side guardrails<br/>block DDL, DML, PL/SQL, comments, semicolons"]
    end

    subgraph database["Oracle Database 23ai / 26ai"]
        perf["Performance evidence<br/>V$SQL, plans, waits, AWR, ASH"]
        catalog["Graph catalog<br/>DBA_PROPERTY_GRAPHS, DBA_PG_*"]
        output["Advisor output<br/>root cause, recommendations, rollback SQL"]
    end

    fallback["SQLcl MCP fallback<br/>local or non-ADB Native cases"]

    user --> llm
    llm --> skill
    skill --> endpoint
    endpoint --> auth
    auth --> tool
    tool --> guardrails
    guardrails --> perf
    guardrails --> catalog
    perf --> output
    catalog --> output
    output --> llm

    skill -. secondary compatibility path .-> fallback
    fallback -.-> database

    classDef actor fill:#f8fafc,stroke:#64748b,color:#0f172a;
    classDef skillNode fill:#eef2ff,stroke:#4f46e5,color:#111827;
    classDef runtimeNode fill:#ecfdf5,stroke:#059669,color:#064e3b;
    classDef dbNode fill:#fff7ed,stroke:#ea580c,color:#7c2d12;
    classDef fallbackNode fill:#f3f4f6,stroke:#9ca3af,color:#374151,stroke-dasharray: 5 5;

    class user,llm actor;
    class prompt,templates,knowledge skillNode;
    class endpoint,auth,tool,guardrails runtimeNode;
    class perf,catalog,output dbNode;
    class fallback fallbackNode;
```

For ADB Serverless Diagnostic Mode, the runtime should expose a minimal MCP tool
surface. The recommended tool contract is `RUN_SQL`; it must accept only
read-only diagnostic SQL and reject DDL, DML, PL/SQL, comments, semicolons,
client commands, side-effect packages, and `SELECT FOR UPDATE`.

SQLcl MCP remains a compatibility path when ADB Native MCP is not the target.
It should not be required for the production ADB Serverless diagnostic skill.

## Diagnostic Mode requirements

Use this checklist to implement the Diagnostic Mode skill.

### Environment

- Autonomous Database Serverless with MCP enabled.
- Oracle Database graph workload on 23ai or 26ai.
- OAuth or bearer-token authentication for the MCP client.
- One dedicated technical database user per target database.
- No personal user and no `ADMIN` runtime identity.
- Target schema, graph name, workload window, and environment classification.
- AWR/ASH access approved for historical diagnosis.

### MCP tool contract

- Expose one read-only SQL tool through ADB Native MCP.
- Recommended tool name: `RUN_SQL`.
- Recommended implementation: [clients/adb-native-run-sql-readonly.sql](clients/adb-native-run-sql-readonly.sql).
- Validate `tools/list` so only the approved diagnostic tool is exposed.
- Run a write-rejection test before the skill is used.

Tool lifecycle:

1. A DBA or installer creates or replaces `RUN_SQL` in the diagnostic schema.
2. The MCP tool is registered for the runtime identity used by ADB Native MCP.
3. The diagnostic runtime user receives only the read grants it needs.
4. `CREATE PROCEDURE` is granted to the diagnostic user only if that same user
   must self-install or self-update the tool. It is not a runtime privilege.

### Runtime grants

Minimum session and plan access:

```sql
GRANT CREATE SESSION TO graph_diag_user;
GRANT EXECUTE ON DBMS_XPLAN TO graph_diag_user;
```

Dynamic performance views:

```sql
GRANT SELECT ON SYS.V_$SQL TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQLSTATS TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQLAREA_PLAN_HASH TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQL_PLAN TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQL_PLAN_STATISTICS_ALL TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQL_SHARED_CURSOR TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQLTEXT TO graph_diag_user;
GRANT SELECT ON SYS.V_$PARAMETER TO graph_diag_user;
GRANT SELECT ON SYS.V_$SESSION TO graph_diag_user;
GRANT SELECT ON SYS.V_$ACTIVE_SESSION_HISTORY TO graph_diag_user;
GRANT SELECT ON SYS.V_$SYSMETRIC_HISTORY TO graph_diag_user;
GRANT SELECT ON SYS.V_$SYSTEM_EVENT TO graph_diag_user;
GRANT SELECT ON SYS.V_$SYS_TIME_MODEL TO graph_diag_user;
GRANT SELECT ON SYS.V_$SGASTAT TO graph_diag_user;
GRANT SELECT ON SYS.V_$PGASTAT TO graph_diag_user;
```

Graph catalog and object metadata:

```sql
GRANT SELECT ON DBA_PROPERTY_GRAPHS TO graph_diag_user;
GRANT SELECT ON DBA_PG_ELEMENTS TO graph_diag_user;
GRANT SELECT ON DBA_PG_EDGE_RELATIONSHIPS TO graph_diag_user;
GRANT SELECT ON DBA_TABLES TO graph_diag_user;
GRANT SELECT ON DBA_INDEXES TO graph_diag_user;
GRANT SELECT ON DBA_IND_COLUMNS TO graph_diag_user;
GRANT SELECT ON DBA_TAB_STATISTICS TO graph_diag_user;
GRANT SELECT ON DBA_TAB_COL_STATISTICS TO graph_diag_user;
```

Health, AWR, ASH, and Auto Indexing:

```sql
GRANT SELECT ON DBA_HIST_SNAPSHOT TO graph_diag_user;
GRANT SELECT ON DBA_HIST_SYSMETRIC_SUMMARY TO graph_diag_user;
GRANT SELECT ON DBA_HIST_SYSTEM_EVENT TO graph_diag_user;
GRANT SELECT ON DBA_HIST_PGASTAT TO graph_diag_user;
GRANT SELECT ON DBA_HIST_ACTIVE_SESS_HISTORY TO graph_diag_user;

GRANT SELECT ON DBA_TABLESPACE_USAGE_METRICS TO graph_diag_user;
GRANT SELECT ON DBA_TEMP_FREE_SPACE TO graph_diag_user;
GRANT SELECT ON DBA_AUTO_INDEX_CONFIG TO graph_diag_user;
GRANT SELECT ON DBA_AUTO_INDEX_IND_ACTIONS TO graph_diag_user;
GRANT SELECT ON DBA_AUTO_INDEX_EXECUTIONS TO graph_diag_user;
```

Detailed docs:

- [docs/diagnostic-mode-minimum-prereqs.md](docs/diagnostic-mode-minimum-prereqs.md)
- [Diagnostic requirements selector](https://diegoecab.github.io/oracle-graph-dba-advisor/diagnostic-requirements-selector.html) - interactive selector for the recommended Diagnostic Mode requirements.
- [docs/graph-dba-workload-mode-requirements.md](docs/graph-dba-workload-mode-requirements.md)
- [clients/adb-mcp-setup.md](clients/adb-mcp-setup.md)
- [docs/native-mcp-packaged-playbooks.md](docs/native-mcp-packaged-playbooks.md)

## Quick start for ADB Serverless Diagnostic Mode

1. Enable ADB Native MCP on the target database.

   ```text
   Tag name:  adb$feature
   Tag value: {"name":"mcp_server","enable":true}
   ```

2. Create or choose the dedicated diagnostic user.

   Use one technical schema per target database. Do not use a personal account
   or `ADMIN` for runtime access.

3. Apply the read grants.

   Recommended: a DBA/ADMIN runs
   [clients/adb-diagnostic-grants-advisor.sql](clients/adb-diagnostic-grants-advisor.sql)
   as the baseline grant script. Alternative: the client DBA copies the grant
   list from this README and applies it manually through their change-management
   process. The skill does not grant privileges to itself.

4. Register the read-only MCP tool.

   Prefer:

   ```sql
   @clients/adb-native-run-sql-readonly.sql
   ```

   A DBA or installer can create the backing function in the diagnostic schema.
   The diagnostic user does not need `CREATE PROCEDURE` at runtime.
   See [clients/adb-native-run-sql-readonly.sql](clients/adb-native-run-sql-readonly.sql).

5. Configure the MCP client with the ADB Native MCP endpoint.

   ```json
   {
     "mcpServers": {
       "oracle-graph-advisor": {
         "type": "streamableHttp",
         "url": "https://dataaccess.adb.<region>.oraclecloudapps.com/adb/mcp/v1/databases/<adb-ocid>",
         "headers": {
           "Authorization": "Bearer <token>"
         }
       }
     }
   }
   ```

6. Start the diagnostic prompt.

   Load `SYSTEM_PROMPT.md` or the client-specific instruction file, then ask the
   advisor to analyze the target graph workload.

## What the advisor knows

| Capability | Description |
|---|---|
| SQL/PGQ workload diagnosis | Finds graph queries, expensive plans, and graph-specific bottlenecks. |
| Execution-plan analysis | Maps `GRAPH_TABLE` execution back to relational joins and table access. |
| AWR/ASH evidence | Uses historical snapshots and active session data when available. |
| Graph catalog discovery | Reads graph, table, index, and stats metadata. |
| P0-P4 index strategy | Verifies PKs, edge FKs, filters, composites, and advanced designs in that order. |
| Auto Indexing awareness | Detects auto-created indexes and avoids duplicate recommendations. |
| Production guardrails | Read-only by default; DDL/DML recommendations are generated as scripts, not executed. |

## Diagnostic methodology

| Phase | Goal |
|---|---|
| 0. Safety gate | Confirm environment, runtime user, tool surface, and read-only posture. |
| 1. Health baseline | Review CPU, memory, I/O, temp, tablespace, waits, and Auto Indexing. |
| 2. Graph discovery | Inventory graphs, backing tables, indexes, stats, and owner metadata. |
| 3. Workload identification | Find top SQL/PGQ statements by elapsed time, executions, and waits. |
| 4. Plan deep dive | Inspect plans, child cursors, cardinality estimates, and join behavior. |
| 5. Selectivity analysis | Quantify whether filters and edge joins justify indexes. |
| 6. Recommendation | Produce DDL, validation SQL, rollback SQL, and expected impact. |
| 7. Optional validation | Test safely in approved lower environments or with explicitly approved simulations. |

## Secondary modes

### Consultive Mode

Consultive Mode helps design a new graph from a business description. It can
assess whether a graph model fits, propose vertices and edges, generate Mermaid
diagrams, and draft `CREATE PROPERTY GRAPH` DDL and starter queries.

This mode does not require database access when working from a description. It
is intentionally secondary while Diagnostic Mode is the customer-facing focus.

### SQLcl MCP fallback

Use SQLcl MCP when ADB Native MCP is not available or not the target runtime.
This includes ADB Dedicated, Base DB, on-premises databases, local test
databases, and workflows that require SQLcl-specific capabilities.

See [Client setup](clients/README.md) for local SQLcl MCP configuration.

## SQL templates

The advisor selects and parameterizes templates from `sql-templates/`.

| File | Phase |
|---|---|
| `00-health-check.sql` | Health baseline and Auto Indexing |
| `01-discovery.sql` | Graph and object discovery |
| `01b-graph-dba-catalog.sql` | Owner-aware DBA catalog discovery |
| `02-identify.sql` | Expensive workload identification |
| `02b-plan-instability.sql` | Plan instability and child cursor analysis |
| `03-analyze.sql` | Plan deep dive |
| `04-selectivity-and-simulate.sql` | Selectivity and approved simulation |
| `05-utilities.sql` | Utility queries |
| `packs/missing-index/` | Evidence-selected missing-index diagnostic pack |
| `packs/plan-instability/` | Evidence-selected plan drift and child cursor diagnostic pack |
| `packs/supernode-fanout/` | Evidence-selected high-degree fan-out diagnostic pack |

## Knowledge base

| Directory | Content |
|---|---|
| `knowledge/graph-patterns/` | Fraud, social network, supply chain, and use-case patterns |
| `knowledge/graph-design/` | Modeling checklist, physical design, and query practices |
| `knowledge/optimization-rules/` | Indexing and Auto Indexing rules |
| `knowledge/oracle-internals/` | SQL/PGQ, optimizer behavior, and PGX comparison |
| `knowledge/rag/` | Planned retrieval layer |

Knowledge files include version metadata such as `verified_version` and
`last_verified`. See `knowledge/FRESHNESS.md`.

## Client support

| Client | Primary Diagnostic Mode path | Notes |
|---|---|---|
| Codex | ADB Native MCP endpoint | Use one named MCP server per target ADB. |
| Claude Desktop | ADB Native MCP via remote MCP bridge | Load `SYSTEM_PROMPT.md` as project instructions. |
| VS Code + Copilot | ADB Native MCP or SQLcl MCP | Uses `.github/copilot-instructions.md` when configured. |
| Cline | ADB Native MCP or SQLcl MCP | Uses `.clinerules`. |
| Cursor | ADB Native MCP or SQLcl MCP | Uses `.cursor/rules/oracle-graph-dba.mdc`. |

### Install in Codex

Recommended professional path: add this repository as a Codex plugin
marketplace, then install **Oracle Graph DBA Advisor** from the Codex plugin
directory.

```powershell
codex plugin marketplace add Diegoecab/oracle-graph-dba-advisor
```

For local development or a quick one-user install, copy the skill files into
the local Codex skills directory.

Windows PowerShell:

```powershell
npx --yes degit Diegoecab/oracle-graph-dba-advisor "$env:USERPROFILE\.agents\skills\oracle-graph-dba-advisor"
```

macOS/Linux:

```bash
npx --yes degit Diegoecab/oracle-graph-dba-advisor "$HOME/.agents/skills/oracle-graph-dba-advisor"
```

If Node.js is not available, use Git instead:

```powershell
git clone --depth 1 https://github.com/Diegoecab/oracle-graph-dba-advisor.git "$env:USERPROFILE\.agents\skills\oracle-graph-dba-advisor"
```

Restart Codex after installing the marketplace plugin or local skill.

#### Generate the ADB Native MCP bearer token

Generate the bearer token from the ADB Native MCP auth endpoint with the
dedicated diagnostic database user, normally `GRAPH_DIAG_USER`. The token is
temporary; regenerate it when it expires.

For the current Mini-DOWNER live demo database, use the values in
[docs/mini-downer-demo-database.md](docs/mini-downer-demo-database.md):

```powershell
$env:ADB_REGION = "sa-saopaulo-1"
$env:ADB_OCID = "ocid1.autonomousdatabase.oc1.sa-saopaulo-1.antxeljrfioir7iauszrvqwbv6dsu5pybolkiidctbm53wjecldafli5xmsa"
$env:ADB_USERNAME = "GRAPH_DIAG_USER"
```

```powershell
$env:ADB_REGION = "<adb-region>"
$env:ADB_OCID = "<adb-ocid>"
$env:ADB_USERNAME = "GRAPH_DIAG_USER"
$securePassword = Read-Host "GRAPH_DIAG_USER password" -AsSecureString
$passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
  $graphDiagPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtr)
} finally {
  if ($passwordPtr -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr)
  }
}

$tokenBody = @{
  grant_type = "password"
  username = $env:ADB_USERNAME
  password = $graphDiagPassword
} | ConvertTo-Json -Compress

$tokenResponse = Invoke-RestMethod `
  -Method Post `
  -Uri "https://dataaccess.adb.$env:ADB_REGION.oraclecloudapps.com/adb/auth/v1/databases/$env:ADB_OCID/token" `
  -ContentType "application/json" `
  -Headers @{ Accept = "application/json" } `
  -Body $tokenBody

$env:ADB_MCP_TOKEN = $tokenResponse.access_token
Remove-Variable graphDiagPassword -ErrorAction SilentlyContinue
```

#### Add the ADB Native MCP server in Codex

Configure one MCP server per target ADB. For the Mini-DOWNER demo, replace the
ADB OCID and use the token generated above:

```powershell
codex mcp add graph-advisor-downer `
  --url "https://dataaccess.adb.$env:ADB_REGION.oraclecloudapps.com/adb/mcp/v1/databases/$env:ADB_OCID" `
  --bearer-token-env-var ADB_MCP_TOKEN
```

Ask Codex to use the `oracle-graph-dba-advisor` skill. The runtime MCP surface
should expose only `RUN_SQL`.

Mini-DOWNER starter prompt:

```text
Usa el skill oracle-graph-dba-advisor y exclusivamente el MCP graph-advisor-downer.

Estoy viendo lentitud en Mini-DOWNER y Performance Hub muestra carga constante. Primero confirma el contexto de conexion con DB_NAME, SERVICE_NAME, SESSION_USER y grafos disponibles. Si corresponde a Mini-DOWNER, continua con el diagnostico read-only: identifica el SQL mas relevante, explicame en simple la causa principal, que evidencia la sostiene y que recomendacion concreta le pasarias al DBA. No ejecutes cambios.

No asumas la causa por el nombre Mini-DOWNER: selecciona el camino diagnostico o pack correcto solo despues de ver evidencia de SQL, plan, waits y metadata de objetos.
```

The skill treats this context check as a mandatory connection gate. If multiple
ADB MCP servers are configured, always name the intended MCP server in the user
prompt and require the first diagnostic response to show the connected database
context.

#### Update the Codex plugin or local skill

For the marketplace path, refresh the configured marketplace and restart Codex:

```powershell
codex plugin marketplace upgrade oracle-graph-dba-advisor
```

This Codex CLI build exposes marketplace `add`, `upgrade`, and `remove`, but not
a separate `codex plugin list` or `codex plugin update` command. To know a new
version is available, use the repository release/tag or the plugin manifest
version in `.codex-plugin/plugin.json`, then run `marketplace upgrade`.

If Codex reports `No configured Git marketplaces to upgrade`, add the GitHub
marketplace again, restart Codex, and select the plugin from the plugin
directory:

```powershell
codex plugin marketplace add Diegoecab/oracle-graph-dba-advisor
```

If the skill was installed by cloning the repository into the local skills
directory, update it with Git:

```powershell
git -C "$env:USERPROFILE\.agents\skills\oracle-graph-dba-advisor" pull --ff-only
```

If the skill was installed with `degit`, reinstall from the marketplace path or
replace the local skill directory from a fresh checkout, then restart Codex.

### Install in Claude

Recommended professional path for Claude Code: add this repository as a Claude
plugin marketplace, then install the plugin.

```powershell
claude plugin marketplace add Diegoecab/oracle-graph-dba-advisor
claude plugin install oracle-graph-dba-advisor@oracle-graph-dba-advisor --scope user
claude plugin list
```

If the current Claude Code build does not resolve the marketplace package after
`marketplace add`, use the Claude Code skill fallback below.

Claude also has two useful non-marketplace paths:

- **Claude Code**: install this repository as a local skill.
- **Claude Desktop / claude.ai**: package the repository as a skill ZIP and
  upload it through Claude's Skills UI.

#### Claude Code skill

Windows PowerShell:

```powershell
npx --yes degit Diegoecab/oracle-graph-dba-advisor "$env:USERPROFILE\.claude\skills\oracle-graph-dba-advisor"
```

macOS/Linux:

```bash
npx --yes degit Diegoecab/oracle-graph-dba-advisor "$HOME/.claude/skills/oracle-graph-dba-advisor"
```

Then start Claude Code and ask it to use the `oracle-graph-dba-advisor` skill
for graph workload diagnostics.

#### Add the ADB Native MCP server in Claude Code

Configure the ADB Native MCP server separately. Example for Mini-DOWNER:

```powershell
claude mcp add --transport http --scope user `
  graph-advisor-downer `
  "https://dataaccess.adb.$env:ADB_REGION.oraclecloudapps.com/adb/mcp/v1/databases/$env:ADB_OCID" `
  --header "Authorization: Bearer $env:ADB_MCP_TOKEN"
```

Use `/mcp` inside Claude Code to verify that the server is connected and that
only the approved read-only tool, normally `RUN_SQL`, is available.

#### Update the Claude Code plugin

Refresh the marketplace metadata, update the installed plugin, then restart
Claude Code so the new skill instructions are loaded:

```powershell
claude plugin marketplace update oracle-graph-dba-advisor
claude plugin update oracle-graph-dba-advisor@oracle-graph-dba-advisor --scope user
claude plugin list --json
```

To check whether a newer plugin version is available in Claude Code, compare the
installed version with the available marketplace entry:

```powershell
$plugins = claude plugin list --available --json | ConvertFrom-Json
$plugins.installed | Where-Object { $_.id -eq "oracle-graph-dba-advisor@oracle-graph-dba-advisor" } |
  Select-Object id, version, lastUpdated
$plugins.available | Where-Object { $_.pluginId -eq "oracle-graph-dba-advisor@oracle-graph-dba-advisor" -or $_.name -eq "oracle-graph-dba-advisor" } |
  Select-Object pluginId, version, marketplaceName
```

Claude Code also exposes `claude plugin details oracle-graph-dba-advisor` for a
component inventory, but `plugin list --available --json` is the practical
version-check command.

#### Claude Desktop / claude.ai skill

Package the skill as a ZIP.

Windows PowerShell:

```powershell
npx --yes degit Diegoecab/oracle-graph-dba-advisor "$env:TEMP\oracle-graph-dba-advisor-skill\oracle-graph-dba-advisor"
Compress-Archive -Path "$env:TEMP\oracle-graph-dba-advisor-skill\oracle-graph-dba-advisor" -DestinationPath ".\oracle-graph-dba-advisor-skill.zip" -Force
```

macOS/Linux:

```bash
tmpdir="$(mktemp -d)"
out="$PWD/oracle-graph-dba-advisor-skill.zip"
npx --yes degit Diegoecab/oracle-graph-dba-advisor "$tmpdir/oracle-graph-dba-advisor"
(cd "$tmpdir" && zip -qr "$out" oracle-graph-dba-advisor)
```

Upload `oracle-graph-dba-advisor-skill.zip` in Claude under
`Customize > Skills > Create skill > Upload a skill`.

If the target is Claude Desktop with local MCP enabled, add the ADB Native MCP
server to `claude_desktop_config.json`. Example for Mini-DOWNER:

```json
{
  "mcpServers": {
    "graph-advisor-downer": {
      "description": "Oracle Graph DBA Advisor on ADB Native MCP for Mini-DOWNER.",
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote",
        "https://dataaccess.adb.us-ashburn-1.oraclecloudapps.com/adb/mcp/v1/databases/<adb-ocid>"
      ],
      "transport": "streamable-http",
      "headers": {
        "Authorization": "Bearer <bearer-token>"
      }
    }
  }
}
```

Restart Claude Desktop and verify that the server lists only the approved
read-only tool, normally `RUN_SQL`.

See [clients/README.md](clients/README.md) and
[clients/claude-desktop-adb-bearer-multidb.json](clients/claude-desktop-adb-bearer-multidb.json)
for more client examples. Do not commit bearer tokens, wallets, or generated
per-database client files.

## Sample workloads

| Workload | Description |
|---|---|
| `workload/fraud/` | Fraud detection graph workload |
| `workload/newfraud/` | Updated fraud workload and Native MCP validation scripts |
| `workload/downer/` | Mini-DOWNER missing-index, supernode fan-out, and plan-instability diagnostic demo |
| `workload/catalog_compat/` | Catalog compatibility test workload |

## Project structure

```text
oracle-graph-dba-advisor/
|-- .agents/
|   `-- plugins/marketplace.json
|-- .codex-plugin/
|   `-- plugin.json
|-- .claude-plugin/
|   |-- marketplace.json
|   `-- plugin.json
|-- AGENTS.md
|-- SYSTEM_PROMPT.md
|-- SKILL.md
|-- CLAUDE.md
|-- skills/
|   `-- oracle-graph-dba-advisor/
|-- clients/
|   |-- adb-mcp-setup.md
|   |-- adb-native-run-sql-readonly.sql
|   |-- adb-diagnostic-grants-advisor.sql
|   `-- README.md
|-- sql-templates/
|-- knowledge/
|-- docs/
|-- config/
|-- agent/
|-- memory/
`-- workload/
```

Runtime source-of-truth model:

1. `SYSTEM_PROMPT.md` contains the full diagnostic methodology and safety gates.
2. `SKILL.md`, `CLAUDE.md`, and `skills/oracle-graph-dba-advisor/SKILL.md` are
   lightweight loaders.
3. `AGENTS.md` captures repository maintenance rules for future coding agents.

## Roadmap

| Feature | Status | Description |
|---|---|---|
| RAG layer | Planned | Vectorized Oracle and customer docs for deeper retrieval. |
| Persistent memory | Planned | Schema snapshots, recommendation history, and learned patterns. |
| Centralized memory | Planned | ADB-backed memory with vector search, tenancy boundaries, and audit trail. |
| Autonomous agent workflows | Planned | Scheduled health checks and post-deploy analysis. |
| Automated diagnostic reports | Planned | Scheduled read-only Diagnostic Mode reports for recurring workload reviews and post-deploy checks. |
| Governed mitigation workflows | Future/Research | Controlled non-production mitigation flows with approvals, audit trail, and prod/non-prod separation. |
| Agent Factory governance spike | Pending | Evaluate Private Agent Factory for RBAC, prompt guardrails, read-only tool allowlisting, audit trails, evaluation, and controlled endpoint exposure. |

## Disclaimer

This is an independent, community-driven project. It is not an official Oracle
product, nor is it endorsed, sponsored, or supported by Oracle Corporation.
Oracle, Oracle Database, Oracle Cloud, ADB, Exadata, SQL/PGQ, PGX, and related
names and logos are trademarks or registered trademarks of Oracle Corporation
and/or its affiliates.

## Credits

Built for Oracle Database property graph diagnostics with ADB Native MCP, Oracle
SQLcl MCP fallback, Oracle Database 23ai/26ai, and SQL/PGQ.
