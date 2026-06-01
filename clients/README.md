# Client Setup Guide

The advisor can run through more than one MCP transport. For the current
Diagnostic Mode work, use this order:

1. **ADB Native MCP** for ADB Serverless diagnostic deployments.
2. **SQLcl MCP** as a local or non-ADB-Native fallback.

Keep the skill, prompt, and SQL templates the same. Only the MCP server entry,
database endpoint or alias, and authentication method should change per target
database.

## Recommended for ADB Serverless: ADB Native MCP

Use ADB Native MCP when the target is Autonomous Database Serverless and the
client wants a production-style diagnostic skill without a SQLcl runtime
dependency.

Requirements:

- ADB Native MCP enabled on the target database.
- One dedicated technical database user per target database.
- OAuth or bearer token authentication.
- One approved read-only SQL tool, recommended as `RUN_SQL`.
- No broad write-capable tools exposed to the LLM.

Primary setup guide:

- [ADB Native MCP setup](adb-mcp-setup.md)

Recommended multi-database examples:

- `cline-adb-bearer-multidb.json`
- `claude-desktop-adb-bearer-multidb.json`

## Fallback: SQLcl MCP

Use SQLcl MCP when ADB Native MCP is not available or not the desired runtime.
Typical cases:

- ADB Dedicated
- Base DB
- On-premises Oracle Database
- Local test databases
- Workflows that need SQLcl-specific commands

### Claude Code / Claude Desktop

Use the `.mcp.json` in the project root, or add this shape to
`claude_desktop_config.json`:

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

Load `SYSTEM_PROMPT.md` as project instructions.

### VS Code + GitHub Copilot

The `.vscode/mcp.json` file can be used for SQLcl MCP fallback. Copilot
instructions live in `.github/copilot-instructions.md` when configured.

### Cline

The `.clinerules` file is automatically loaded by Cline. Configure MCP in Cline
settings:

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

The `.cursor/rules/oracle-graph-dba.mdc` file is loaded for matching files.

### Continue

See `continue-config-example.json` for `.continue/config.json` integration.

## Wallet configuration for SQLcl

If connecting to Autonomous Database through SQLcl, set `TNS_ADMIN` to the wallet
directory:

```json
{
  "env": {
    "TNS_ADMIN": "/path/to/wallet"
  }
}
```

## SQLcl saved connection

Before using SQLcl MCP, create a saved connection to the target graph-owning
schema:

```bash
sql /nolog
SQL> conn -save MyConnection -savepwd admin/password@host:1522/service_low
```

The connection name is case-sensitive and is used with the SQLcl MCP `connect`
tool.
