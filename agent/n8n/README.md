# n8n Workflows for Oracle Graph DBA Advisor

Pre-built n8n workflows that turn the advisor skill into an autonomous agent.

## Prerequisites

- n8n (self-hosted or cloud), v1.60+
- Oracle SQLcl 25.2+ accessible from the n8n server
- A saved SQLcl connection to your Oracle database
- LLM API key (Claude, GPT-4o, or Gemini)

## Workflows

### 1. Interactive Chat (`workflow-chat.json`)

Connects the advisor to Slack, Teams, or a webhook for interactive analysis.

**Flow**: Chat message → AI Agent (with SYSTEM_PROMPT.md) → Execute SQLcl → Respond

**Setup**:
1. Import `workflow-chat.json` into n8n
2. Configure the Chat Trigger (Slack token or webhook URL)
3. Set the LLM credential (Anthropic / OpenAI / Google)
4. Set `SQLCL_PATH` in the Execute Command node
5. Set the saved connection name in the tool description

### 2. Daily Health Check (`workflow-healthcheck.json`)

Runs UTIL-09 (complete diagnostic snapshot) every morning and alerts on new issues.

**Flow**: Cron (8:00 AM) → AI Agent: "Run health check, compare with last snapshot, report changes" → If findings → Slack alert

**Setup**:
1. Import `workflow-healthcheck.json` into n8n
2. Configure Cron schedule
3. Set LLM credential, SQLCL_PATH, connection name
4. Configure Slack webhook for alerts
5. Optionally connect a database (SQLite, PostgreSQL, Supabase, etc.) for structured memory

### 3. Post-Deploy Verification (`workflow-postdeploy.json`)

Called from CI/CD after deploying index or schema changes. Verifies impact.

**Flow**: Webhook (with change description) → AI Agent: "Verify the impact of this change against the baseline" → Report results → Update recommendation status

**Setup**:
1. Import `workflow-postdeploy.json` into n8n
2. Configure webhook authentication (API key)
3. Set LLM credential, SQLCL_PATH, connection name
4. Call from CI/CD: `curl -X POST https://n8n.yourcompany.com/webhook/postdeploy -H "X-API-Key: ..." -d '{"environment": "PROD", "changes": "Created index idx_transfers_susp_merch"}'`

## Memory in n8n

**Phase 1 (file-based, no extra infrastructure):**
Mount the repo's `memory/` directory into the n8n container or point workflows to the repo path. Use Code nodes with `fs.readFileSync` / `fs.writeFileSync`.

**Phase 2+ (structured storage, when you need queries/multi-user):**
Use any backend n8n supports. The schema is the same regardless of engine:

| Field | Type | Description |
|-------|------|-------------|
| id | auto-increment | Primary key |
| environment | text | Database connection name |
| tenant_id | text | Company/team (multi-tenant) |
| user_id | text | Individual user |
| memory_type | text | `schema` / `recommendation` / `preference` / `pattern` |
| category | text | `index` / `design` / `query` / `stats` |
| content | text | The fact or recommendation |
| target | text | Affected table/query |
| status | text | `active` / `superseded` / `resolved` |
| outcome | text | Measured impact |
| metadata | json | Additional structured data |
| created_at | timestamp | When recorded |

**Backend options:**

| Backend | n8n Node | Extra infra | Best for |
|---------|----------|-------------|----------|
| Files (markdown/JSON) | Code | None | Getting started, single user |
| SQLite | SQLite | None (one file) | Structured queries, single server |
| PostgreSQL | Postgres | PG instance | Multi-user, already have PG |
| Oracle ADB | HTTP Request / Code | ADB instance (separate) | Enterprise teams, semantic search, centralized repo |
| Supabase | Supabase | Cloud account | Hosted, REST API, free tier |
| Airtable | Airtable | Cloud account | Non-technical teams, visual UI |

Pick whatever you already have. The workflows use a `read_memory` / `write_memory` tool abstraction — swap the implementation without changing the AI Agent node.

**Oracle ADB as centralized memory repository:**
For enterprise teams, a dedicated ADB instance (separate from the databases being analyzed) can serve as a centralized memory store for all advisor sessions across all environments. This gives you ACID guarantees, vector search via OracleVS (HNSW indexes), RBAC/VPD multi-tenancy, and Oracle's native audit trail — without competing for resources on the databases being diagnosed. See `memory/backends/oracle-adb-memory.md` for setup.

## Security

- Use n8n Credentials vault for all secrets
- Create a least-privilege Oracle user for the advisor
- Protect webhooks with API key authentication
- In multi-tenant setups, filter memory by tenant_id
