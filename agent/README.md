# Agent Layer (Optional)

The Oracle Graph DBA Advisor is designed as a **skill**: a system prompt,
approved database tools, and a knowledge base that works inside any
MCP-compatible client. You do not need this agent layer for interactive use.

## When You Need This

The agent layer adds capabilities that a skill cannot provide:

| Capability | Skill (default) | Agent layer |
|---|---|---|
| Interactive analysis on-demand | Yes | Not needed |
| Static knowledge base | Yes | Not needed |
| File-based memory across sessions | Yes | Not needed |
| **Autonomous health checks (cron)** | No | Yes |
| **Proactive alerts (Slack/Teams)** | No | Yes |
| **Post-deployment verification** | No | Yes |
| **Multi-user shared memory** | No | Yes |
| **Temporal workflows (wait, retry)** | No | Yes |

## Architecture

The agent layer does not replace the skill; it wraps it. Internally, the agent
loads the same `SYSTEM_PROMPT.md`, uses the same `sql-templates/`, and consults
the same `knowledge/` directory.

```text
+----------------------------------------+
| Orchestrator (n8n / LangChain / etc.)  |
|                                        |
| Triggers: Slack, Cron, Webhook, CI/CD  |
|                                        |
|  +----------------------------------+  |
|  | AI agent                         |  |
|  | System prompt: SYSTEM_PROMPT.md  |  |
|  | Tools:                           |  |
|  | - ADB Native MCP RUN_SQL         |  |
|  | - SQLcl MCP fallback             |  |
|  | - Memory                         |  |
|  +----------------------------------+  |
|                                        |
| State: file-based or database memory   |
+----------------------------------------+
```

## Available Implementations

- **n8n** - Workflow templates in `agent/n8n/`. Recommended for teams already
  using n8n.
- **Custom** - Use any orchestrator that supports LLM tool calling. Load
  `SYSTEM_PROMPT.md` as system instructions, expose ADB Native MCP `RUN_SQL` for
  ADB Serverless, or SQLcl MCP only as fallback.

## Getting Started with n8n

See `agent/n8n/README.md` for setup instructions and workflow descriptions.
