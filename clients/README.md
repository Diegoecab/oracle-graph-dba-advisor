# Client Configuration Examples

This directory contains example MCP client configurations for using the Oracle Graph DBA Advisor with different LLM clients.

## Quick Setup by Client

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

## Wallet Configuration

If connecting to Oracle Autonomous Database (ADB), set the `TNS_ADMIN` environment variable to your wallet directory:

```json
{
  "env": {
    "TNS_ADMIN": "/path/to/wallet"
  }
}
```

## Creating a Saved Connection

Before using any client, create a saved connection in SQLcl:

```bash
sql /nolog
SQL> conn -save MyConnection -savepwd admin/password@host:1522/service_low
```

The connection name is case-sensitive and will be used with the `connect` MCP tool.
