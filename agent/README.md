# Agent Layer (Optional)

The Oracle Graph DBA Advisor is designed as a **skill** — a system prompt + tools + knowledge base that works inside any MCP-compatible client. You don't need this agent layer for interactive use.

## When You Need This

The agent layer adds capabilities that a skill can't provide:

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

The agent layer doesn't replace the skill — it wraps it. Internally, the agent loads the same `SYSTEM_PROMPT.md`, uses the same `sql-templates/`, and consults the same `knowledge/` directory.

```
┌────────────────────────────────────────┐
│  Orchestrator (n8n / LangChain / etc.) │
│                                        │
│  Triggers: Slack, Cron, Webhook, CI/CD │
│                                        │
│  ┌──────────────────────────────────┐  │
│  │  AI Agent (Claude / GPT-4o)      │  │
│  │  System prompt: SYSTEM_PROMPT.md │  │
│  │  Tools: SQLcl MCP + Memory       │  │
│  └──────────────────────────────────┘  │
│                                        │
│  State: File-based or any DB (memory)  │
└────────────────────────────────────────┘
```

## Available Implementations

- **n8n** — Workflow templates in `agent/n8n/`. Recommended for teams already using n8n.
- **Custom** — Use any orchestrator that supports LLM tool calling. Load `SYSTEM_PROMPT.md` as system instructions, expose SQLcl as a tool.

## Getting Started with n8n

See `agent/n8n/README.md` for setup instructions and workflow descriptions.
