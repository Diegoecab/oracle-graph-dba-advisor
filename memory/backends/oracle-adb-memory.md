# Oracle ADB as Centralized Memory Backend

## Architecture

```
┌────────────────────────────────┐
│  Advisor (any MCP client)      │
│                                │
│  Analyzes:     DB-PROD-1       │──── SQLcl MCP / ADB MCP
│  Analyzes:     DB-PROD-2       │──── SQLcl MCP / ADB MCP
│  Analyzes:     DB-DEV-3        │──── SQLcl MCP / ADB MCP
│                                │
│  Memory store: ADVISOR-MEMORY  │──── Separate ADB instance
│  (centralized, shared)         │     (not a target database)
└────────────────────────────────┘
```

The memory ADB is a **separate instance** from the databases being analyzed. This ensures:
- No resource competition between diagnostics and memory writes
- Memory survives if a target database goes down
- One memory store serves all environments and all users
- Independent scaling, backup, and security policies

## Prerequisites

- Oracle Autonomous Database (Serverless) — can be Always Free tier for small teams
- `langchain-oracledb` Python package (for vector search)
- OCI credentials for the memory ADB instance

## Schema

```sql
-- Connect to the ADVISOR-MEMORY ADB instance (not a target DB)

-- Conversation and recommendation memory
CREATE TABLE advisor_memory (
    id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    environment VARCHAR2(200) NOT NULL,
    tenant_id VARCHAR2(200),
    user_id VARCHAR2(200),
    memory_type VARCHAR2(50) NOT NULL
        CHECK (memory_type IN ('schema','recommendation','preference','pattern','episode')),
    category VARCHAR2(50),
    content CLOB NOT NULL,
    target VARCHAR2(500),
    status VARCHAR2(50) DEFAULT 'active'
        CHECK (status IN ('active','superseded','resolved','verified')),
    outcome CLOB,
    metadata JSON,
    embedding VECTOR(1536, FLOAT64),
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP,
    updated_at TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE INDEX idx_memory_env ON advisor_memory(environment, memory_type, status);
CREATE INDEX idx_memory_tenant ON advisor_memory(tenant_id, user_id);
CREATE INDEX idx_memory_created ON advisor_memory(created_at DESC);

-- Vector index for semantic search (find similar past situations)
CREATE VECTOR INDEX idx_memory_vector ON advisor_memory(embedding)
    ORGANIZATION NEIGHBOR PARTITIONS
    DISTANCE COSINE
    WITH TARGET ACCURACY 95;

-- Schema snapshots (JSON topology)
CREATE TABLE advisor_schema_snapshots (
    id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    environment VARCHAR2(200) NOT NULL,
    tenant_id VARCHAR2(200),
    snapshot JSON NOT NULL,
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE INDEX idx_snapshot_env ON advisor_schema_snapshots(environment, created_at DESC);

-- User preferences
CREATE TABLE advisor_user_profiles (
    user_id VARCHAR2(200) PRIMARY KEY,
    tenant_id VARCHAR2(200),
    preferences JSON NOT NULL,
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP,
    updated_at TIMESTAMP DEFAULT SYSTIMESTAMP
);

-- Audit log (append-only)
CREATE TABLE advisor_audit_log (
    id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    environment VARCHAR2(200),
    tenant_id VARCHAR2(200),
    user_id VARCHAR2(200),
    action VARCHAR2(100) NOT NULL,
    details CLOB,
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE INDEX idx_audit_env ON advisor_audit_log(environment, created_at DESC);
```

## Semantic Search

With the `embedding` column and vector index, the advisor can search for similar past situations:

```sql
-- "Find past recommendations similar to this situation"
SELECT content, category, target, status, outcome,
       VECTOR_DISTANCE(embedding, :query_embedding, COSINE) AS similarity
FROM advisor_memory
WHERE memory_type = 'recommendation'
  AND status IN ('verified', 'active')
  AND tenant_id = :tenant_id
ORDER BY similarity
FETCH FIRST 10 ROWS ONLY;
```

This enables queries like "we had a similar edge table with missing FK indexes — what did we recommend and did it work?" — answered by semantic similarity, not just keyword matching.

## Multi-Tenancy

Use Oracle VPD (Virtual Private Database) to enforce tenant isolation:

```sql
-- Each user only sees their tenant's data
BEGIN
  DBMS_RLS.ADD_POLICY(
    object_schema => 'ADVISOR_MEMORY_OWNER',
    object_name   => 'ADVISOR_MEMORY',
    policy_name   => 'TENANT_ISOLATION',
    function_schema => 'ADVISOR_MEMORY_OWNER',
    policy_function => 'TENANT_FILTER',
    statement_types => 'SELECT,INSERT,UPDATE,DELETE'
  );
END;
/

CREATE OR REPLACE FUNCTION tenant_filter(
    schema_name IN VARCHAR2,
    table_name  IN VARCHAR2
) RETURN VARCHAR2 AS
BEGIN
    RETURN 'tenant_id = SYS_CONTEXT(''ADVISOR_CTX'',''TENANT_ID'')';
END;
/
```

## Integration with the Advisor

The advisor's SYSTEM_PROMPT.md memory instructions stay the same — "read memory, write memory." The difference is that in Phase 1, those operations hit local files. In Phase 2 with Oracle ADB, they hit the centralized database via SQL tools.

For MCP-based access, register memory tools on the ADVISOR-MEMORY ADB using `DBMS_CLOUD_AI_AGENT.CREATE_TOOL` (same pattern as `clients/adb-mcp-setup.md`). The advisor then has two MCP connections:
1. **Target DB** — the database being analyzed (run-sql diagnostics)
2. **Memory DB** — the centralized memory store (read/write memory)

## When to Use This

| Scenario | Recommended |
|---|---|
| Single user, getting started | Phase 1 (files) |
| Small team, same office | Phase 1 (files) or SQLite |
| Enterprise team, multiple environments | Oracle ADB centralized |
| Compliance requirements (audit trail) | Oracle ADB centralized |
| Need semantic search over past recommendations | Oracle ADB centralized |
| Always Free budget | Works on ADB Always Free |

## References

- [Oracle AI Developer Hub — Memory Engineering notebook](https://github.com/oracle-devrel/oracle-ai-developer-hub/blob/main/notebooks/memory_context_engineering_agents.ipynb)
- [Oracle AI Developer Hub — Filesystem vs Database memory](https://github.com/oracle-devrel/oracle-ai-developer-hub/blob/main/notebooks/fs_vs_dbs.ipynb)
- [langchain-oracledb documentation](https://python.langchain.com/docs/integrations/providers/oracle/)
- [OracleVS vector store](https://docs.oracle.com/en/database/oracle/oracle-database/23/vecse/)
