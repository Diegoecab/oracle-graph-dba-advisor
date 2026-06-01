# Oracle Autonomous AI Database — Native MCP Server Setup

## What This Is

Oracle Autonomous AI Database (Serverless) includes a **built-in, fully managed MCP server**. Instead of installing SQLcl locally and running it as an MCP server, the MCP endpoint runs directly inside your ADB instance. No client-side installation required — just a URL.

This is the preferred backend for **Diagnostic Mode on ADB Serverless** because
it avoids a runtime SQLcl dependency and exposes only the database-side tools
you register.

## When to Use This

Use this when you want a zero-install ADB Serverless deployment and are willing
to mirror the repo's expected read-only SQL behavior inside ADB.

| Scenario | Recommended path |
|---|---|
| ADB Serverless (23ai or 26ai) | This guide for Diagnostic Mode |
| ADB Dedicated | SQLcl MCP (local) |
| Base DB / On-prem / Free tier | SQLcl MCP (local) |
| Need local-only fallback | SQLcl MCP (local) |
| Need custom SQLcl commands (Data Pump, etc.) | SQLcl MCP (local) |

## Prerequisites

1. **Oracle Autonomous AI Database** (Serverless) — 23ai or 26ai
2. OCI user with permission to update the database (free-form tags)
3. Any MCP client (Claude Desktop, Cursor, Cline, VS Code + Copilot)
4. `npx` (comes with Node.js) — only client-side dependency
5. One dedicated technical database user for the skill in each target database
6. Minimum diagnostic grants on that technical user

> Short operational baseline for this repo: [Diagnostic Mode minimum prereqs](../docs/diagnostic-mode-minimum-prereqs.md)
> Baseline setup script: [adb-diagnostic-user-minimal.sql](adb-diagnostic-user-minimal.sql)
> Full advisor grants on an existing schema: [adb-diagnostic-grants-advisor.sql](adb-diagnostic-grants-advisor.sql)

## Setup

### Step 1: Enable the MCP Server

In the OCI Console, add a free-form tag to your ADB instance:

```
Tag Name:  adb$feature
Tag Value: {"name":"mcp_server","enable":true}
```

This creates the MCP endpoint:

```
https://dataaccess.adb.<region>.oraclecloudapps.com/adb/mcp/v1/databases/<database-ocid>
```

For Private Endpoint databases:

```
https://<hostname_prefix>.adb.<region>.oraclecloudapps.com/adb/mcp/v1/databases/<database-ocid>
```

### Step 2: Register the Read-Only SQL Tool Contract

> **Note:** We use `DBMS_CLOUD_AI_AGENT.CREATE_TOOL` only as the **tool registration mechanism** for the ADB MCP server. The advisor does NOT use Select AI's NL2SQL capability — the LLM generates SQL directly using the sql-templates and SYSTEM_PROMPT knowledge. The `CREATE_TOOL` API simply exposes PL/SQL functions as MCP-callable tools.

> **Important:** The repository's prompt and templates assume a read-only `run-sql` capability. SQLcl-only tools such as `connect` and `run-sqlcl` do not exist automatically in ADB Native MCP.

Register the read-only `RUN_SQL` tool in the dedicated diagnostic schema. For
this repo, prefer the hardened setup script:

```sql
@clients/adb-native-run-sql-readonly.sql
```

The function rejects non-`SELECT`/`WITH` statements, comments, semicolons, DDL,
DML, PL/SQL, SQLcl commands, `SELECT FOR UPDATE`, and known side-effect
packages. The simplified example below illustrates the contract only; do not use
it unchanged for a customer-facing deployment.

`CREATE PROCEDURE` is not a runtime privilege. Prefer a DBA/installer-managed
lifecycle to create or replace the backing PL/SQL function in the diagnostic
schema. Grant `CREATE PROCEDURE` to the diagnostic user only when that user must
self-install or self-update the tool, and revoke it after validation.

```sql
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL (
    tool_name  => 'RUN_SQL',
    attributes => '{
      "instruction": "Execute a read-only SQL query against the Oracle database. Use this for all diagnostic queries from the Graph DBA Advisor sql-templates/.",
      "function": "RUN_SQL",
      "tool_inputs": [
        {"name": "QUERY", "description": "SELECT SQL statement without trailing semicolon."},
        {"name": "OFFSET", "description": "Pagination offset (default 0)."},
        {"name": "LIMIT", "description": "Maximum rows to return (default 100)."}
      ]
    }'
  );
END;
/

-- The function that executes the query
CREATE OR REPLACE FUNCTION run_sql(
    query    IN CLOB,
    offset   IN NUMBER DEFAULT 0,
    limit    IN NUMBER DEFAULT 100
) RETURN CLOB
AS
    v_sql  CLOB;
    v_json CLOB;
BEGIN
    v_sql := 'SELECT NVL(JSON_ARRAYAGG(JSON_OBJECT(*) RETURNING CLOB), ''[]'') AS json_output ' ||
        'FROM ( ' ||
        '  SELECT * FROM ( ' || query || ' ) sub_q ' ||
        '  OFFSET :off ROWS FETCH NEXT :lim ROWS ONLY ' ||
        ')';
    EXECUTE IMMEDIATE v_sql INTO v_json USING offset, limit;
    RETURN v_json;
END;
/
```

For the production-style diagnostic baseline, expose only `RUN_SQL`. Additional
tools increase the LLM tool surface and should be added only after explicit
approval. If a lower-risk lab requires schema discovery as a separate MCP tool,
use the same review and write-rejection process before enabling it.

```sql
-- List schemas accessible to this user
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL (
    tool_name  => 'LIST_SCHEMAS',
    attributes => '{
      "instruction": "List all database schemas accessible to the current user.",
      "function": "LIST_SCHEMAS",
      "tool_inputs": []
    }'
  );
END;
/

CREATE OR REPLACE FUNCTION list_schemas RETURN CLOB AS
    v_json CLOB;
BEGIN
    SELECT JSON_ARRAYAGG(username ORDER BY username RETURNING CLOB)
    INTO v_json
    FROM all_users
    WHERE oracle_maintained = 'N';
    RETURN v_json;
END;
/
```

### Step 3: Configure the MCP Client

For this project, the practical default is:

- **Bearer token** for headless use or automation
- **One MCP server entry per target database**
- **Same tool contract in every database** (`RUN_SQL`)

This keeps the skill reusable across many ADBs. The skill stays the same; only the MCP server name, database OCID, and token change per target.

#### 3a. Generate a bearer token

```bash
curl --location 'https://dataaccess.adb.<region>.oraclecloudapps.com/adb/auth/v1/databases/<database-ocid>/token' \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  --data '{
    "grant_type":"password",
    "username":"<db-username>",
    "password":"<db-password>"
  }'
```

Use the returned `access_token` as `Bearer <your-token>`.

Practical note:

- the bearer token is temporary and must be refreshed periodically
- generate it with the dedicated technical database user for that target database

#### 3b. Cline / VS Code MCP settings

Use one named MCP server per database alias and repeat as needed:

```json
{
  "mcpServers": {
    "graph-advisor-<db-alias>": {
      "timeout": 300,
      "type": "streamableHttp",
      "url": "https://dataaccess.adb.<region>.oraclecloudapps.com/adb/mcp/v1/databases/<database-ocid>",
      "headers": {
        "Authorization": "Bearer <your-token>"
      }
    }
  }
}
```

Example file: `cline-adb-bearer-multidb.json`

#### 3c. Claude Desktop

Use one named MCP server per database alias and repeat as needed:

```json
{
  "mcpServers": {
    "graph-advisor-<db-alias>": {
      "description": "Oracle Graph Advisor on ADB Native MCP for <db-alias>.",
      "command": "/opt/homebrew/bin/npx",
      "args": [
        "-y",
        "mcp-remote",
        "https://dataaccess.adb.<region>.oraclecloudapps.com/adb/mcp/v1/databases/<database-ocid>",
        "--allow-http"
      ],
      "transport": "streamable-http",
      "headers": {
        "Authorization": "Bearer <your-token>"
      }
    }
  }
}
```

Example file: `claude-desktop-adb-bearer-multidb.json`

#### 3d. Interactive option: OAuth

If your client supports OAuth and you prefer interactive login, configure the MCP server without the `Authorization` header and let the client show the login screen.

In that case, the operator signs in interactively with the target database credentials.

### Step 4: Load the Advisor Skill

The advisor skill (SYSTEM_PROMPT.md, knowledge/, sql-templates/) works the same regardless of transport. Load it the same way as with SQLcl MCP — via CLAUDE.md, .clinerules, copilot-instructions.md, or as Claude Project instructions.

## Comparison: ADB Native MCP vs SQLcl MCP

| Aspect | SQLcl MCP (local) | ADB Native MCP |
|---|---|---|
| Client installation | SQLcl + Java 17 | Only `npx` |
| Where MCP runs | User's machine | Inside the database |
| Managed by | User | Oracle (patching, updates, SLAs) |
| Security | Local wallet / saved passwords | RBAC, VPD, ACLs, lockdown profiles, auditing |
| Custom tools | 5 fixed (connect, run-sql, etc.) | Customizable via `DBMS_CLOUD_AI_AGENT.CREATE_TOOL` |
| Multi-tenant | No | Built-in isolation |
| Custom tool registration | No | Yes (via `DBMS_CLOUD_AI_AGENT.CREATE_TOOL`) |
| Databases supported | Any Oracle 19c+ | ADB Serverless only |
| Offline use | Yes | No (requires network) |

## Security Notes

- The MCP server enforces your database's existing security policies (RBAC, VPD, ACLs)
- Create a least-privilege database user for the advisor with SELECT-only access
- For Private Endpoint databases, the MCP server is reachable only from the configured VCN
- All interactions are logged via Oracle's built-in auditing

## References

- [Announcing the Oracle Autonomous AI Database MCP Server](https://blogs.oracle.com/machinelearning/announcing-the-oracle-autonomous-ai-database-mcp-server)
- [ADB MCP Server Documentation](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/mcp-server.html)
- [Select AI Agent Documentation](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/select-ai-agent.html)
- [DBMS_CLOUD_AI_AGENT Package](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/dbms-cloud-ai-agent-package.html)
