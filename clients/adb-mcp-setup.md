# Oracle Autonomous AI Database — Native MCP Server Setup

## What This Is

Oracle Autonomous AI Database (Serverless) includes a **built-in, fully managed MCP server**. Instead of installing SQLcl locally and running it as an MCP server, the MCP endpoint runs directly inside your ADB instance. No client-side installation required — just a URL.

## When to Use This

| Scenario | Recommended path |
|---|---|
| ADB Serverless (19c or 26ai) | This guide (ADB native MCP) |
| ADB Dedicated | SQLcl MCP (local) |
| Base DB / On-prem / Free tier | SQLcl MCP (local) |
| Want zero client-side installation | This guide |
| Need custom SQLcl commands (Data Pump, etc.) | SQLcl MCP (local) |

## Prerequisites

1. **Oracle Autonomous AI Database** (Serverless) — 19c or 26ai
2. OCI user with permission to update the database (free-form tags)
3. Any MCP client (Claude Desktop, Cursor, Cline, VS Code + Copilot)
4. `npx` (comes with Node.js) — only client-side dependency

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

### Step 2: Register the Advisor's SQL Tools

Connect to your ADB as an admin user and register the `run-sql` tool using Select AI Agent:

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

Optionally register additional tools for schema discovery:

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

**Claude Desktop** — edit `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "oracle-adb-advisor": {
      "command": "npx",
      "args": [
        "-y", "mcp-remote",
        "https://dataaccess.adb.<region>.oraclecloudapps.com/adb/mcp/v1/databases/<database-ocid>",
        "--allow-http"
      ],
      "transport": "streamable-http"
    }
  }
}
```

**VS Code (Copilot / Cline)** — add to `.vscode/mcp.json` or MCP settings:

```json
{
  "servers": {
    "oracle-adb-advisor": {
      "command": "npx",
      "args": [
        "-y", "mcp-remote",
        "https://dataaccess.adb.<region>.oraclecloudapps.com/adb/mcp/v1/databases/<database-ocid>"
      ],
      "transport": "streamable-http"
    }
  }
}
```

Replace `<region>` and `<database-ocid>` with your actual values from the OCI Console.

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
| NL2SQL / RAG | No | Yes (via Select AI) |
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
