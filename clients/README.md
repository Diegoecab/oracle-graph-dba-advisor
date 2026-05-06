# Client Setup Guide

## Recommended: SQLcl MCP Server (default repo setup)

This repository ships with SQLcl MCP as its canonical tool contract. Use it for Oracle Database 23ai/26ai across ADB Dedicated, Base DB, on-prem, or Free tier.

### Claude Code / Claude Desktop

Use the `.mcp.json` in the project root, or add to `claude_desktop_config.json`:

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

Load `SYSTEM_PROMPT.md` as Project Instructions.

### VS Code + GitHub Copilot

The `.vscode/mcp.json` is already configured in this repo. Also uses `.github/copilot-instructions.md` for agent behavior.

If using the Oracle SQL Developer Extension for VS Code, MCP is registered automatically.

### Cline

The `.clinerules` file in the repo root is automatically loaded. Configure MCP in Cline settings:

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

### Cursor

The `.cursor/rules/oracle-graph-dba.mdc` file is automatically loaded for matching files.

### Continue

See `continue-config-example.json` in this directory for `.continue/config.json` integration.

---

## Optional: ADB Native MCP Server (ADB Serverless only)

Use this only if you are on **Oracle Autonomous AI Database (Serverless)** and are willing to register a compatible `run-sql` tool contract in ADB. The rest of the repo still assumes the same prompt/template behavior as the SQLcl path.

**[Complete ADB Native guide: adb-mcp-setup.md](adb-mcp-setup.md)**

For multi-database use, keep the skill constant and add one MCP server entry per target ADB alias. Recommended examples:

- `cline-adb-bearer-multidb.json`
- `claude-desktop-adb-bearer-multidb.json`

---

## Wallet Configuration

If connecting to Oracle Autonomous Database (ADB) via SQLcl, set the `TNS_ADMIN` environment variable to your wallet directory:

```json
{
  "env": {
    "TNS_ADMIN": "/path/to/wallet"
  }
}
```

## Creating a Saved Connection (SQLcl only)

Before using SQLcl MCP, create a saved connection to the target graph-owning schema:

```bash
sql /nolog
SQL> conn -save MyConnection -savepwd admin/password@host:1522/service_low
```

The connection name is case-sensitive and will be used with the `connect` MCP tool.
