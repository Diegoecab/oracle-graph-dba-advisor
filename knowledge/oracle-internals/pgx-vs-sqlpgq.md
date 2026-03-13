---
verified_version: "23ai"
last_verified: "2026-03-09"
oracle_doc_urls:
  - https://docs.oracle.com/en/database/oracle/property-graph/23.1/spgdg/load-graph-memory-and-run-graph-analytics.html
next_review: "on_new_oracle_release"
confidence: "medium"
version_sensitive_facts:
  - "PGX not available on ADB-S Serverless"
  - "PGX uses PGQL, not SQL/PGQ"
---

# PGX vs SQL/PGQ — Decision Guide

## Overview

Oracle provides two graph processing engines. This guide helps the advisor determine which engine is appropriate for a given workload.

| Aspect | SQL/PGQ (GRAPH_TABLE) | PGX (Graph Server) |
|---|---|---|
| **Engine** | Oracle CBO (relational) | In-memory Java process |
| **Query language** | SQL/PGQ (ISO SQL:2023) | PGQL |
| **Data access** | Directly from tables (real-time) | Loaded into memory (snapshot) |
| **Availability** | 23ai/26ai (all editions, including ADB-S Free) | 23ai with Graph Server (ADB-D, on-prem only) |
| **Best for** | Focused traversals, filtered queries, OLTP | Full-graph algorithms, analytics, exploration |

---

## 1. SQL/PGQ (GRAPH_TABLE) — When to Use

The default engine for this advisor. Best for:

- **Operational/transactional queries**: Find specific fraud rings, check account connections, validate identity links. Queries that start from a known vertex and traverse a bounded number of hops.
- **High-selectivity queries**: Start from a known vertex (`WHERE a.id = :bind`), filter aggressively on edge/vertex properties, return a small result set.
- **Real-time data**: Reads directly from the underlying tables — sees committed changes immediately. No snapshot lag.
- **SQL integration**: Can JOIN with non-graph tables, embed in views, call from PL/SQL, use in CTAS/INSERT-SELECT. Full SQL ecosystem.
- **No infrastructure overhead**: Works on ADB-S (Serverless), Free tier, and any 23ai/26ai database. No separate server to deploy.

### Limitations

- No unbounded path search (max quantifier `{n,m}` upper bound = 10)
- No built-in graph algorithms (PageRank, community detection, betweenness centrality)
- No ANY SHORTEST / ALL SHORTEST / ANY CHEAPEST path semantics (23ai base)
- Variable-length paths expand to UNION ALL of fixed-length sub-plans — performance degrades with depth
- No graph-native visualization (requires external tools)

---

## 2. PGX (Graph Server) — When to Use

Best for workloads that require full-graph computation:

- **Graph algorithms**: PageRank, betweenness centrality, closeness centrality, eigenvector centrality
- **Community detection**: Louvain, label propagation, weakly/strongly connected components
- **Shortest path algorithms**: Dijkstra, Bellman-Ford, A* — finding THE shortest/cheapest path (not just any path)
- **Full-graph analytics**: Computations that touch every vertex/edge without a specific starting point
- **Exploratory analysis**: When you don't know the pattern in advance and need interactive graph exploration

### Architecture

PGX is a separate Java process (Graph Server) that loads graph data from the database **into memory**. It processes queries using PGQL (Property Graph Query Language), not SQL/PGQ.

```
┌─────────────────┐       ┌──────────────────┐
│  Client (PGQL)  │──────>│   Graph Server   │
│                 │       │    (PGX / Java)   │
└─────────────────┘       │                  │
                          │  In-Memory Graph │
                          │  (snapshot)      │
                          └────────┬─────────┘
                                   │ JDBC
                                   ▼
                          ┌──────────────────┐
                          │  Oracle Database  │
                          │  (source tables) │
                          └──────────────────┘
```

**Availability**:
- ADB-D (Dedicated): Yes
- On-premises Enterprise Edition: Yes (with Graph Server installed)
- ADB-S (Serverless): **No** — PGX is not available on Serverless
- Free tier: **No**

---

## 3. Decision Matrix: When to Recommend PGX

If the user's workload requires any of these, the advisor should recommend PGX:

| Requirement | SQL/PGQ | PGX | Recommendation |
|---|---|---|---|
| PageRank or centrality scores | Cannot compute | Built-in algorithms | **PGX** |
| Community detection (Louvain) | Cannot compute | Built-in | **PGX** |
| THE shortest path (Dijkstra) | No path semantics | Built-in | **PGX** |
| Full-graph analytics (no start vertex) | Very expensive (full scans) | Optimized (in-memory) | **PGX** |
| Connected components | Expensive recursive CTE | Built-in | **PGX** |
| 1-hop neighbors from known vertex | Optimal (index + NL join) | Overkill (load entire graph) | **SQL/PGQ** |
| Filtered traversal (2-3 hops) | Optimal (index-driven) | Possible but heavier setup | **SQL/PGQ** |
| Real-time data (see latest commits) | Yes (direct table access) | No (snapshot at load time) | **SQL/PGQ** |
| Integration with SQL/PL/SQL | Native | Requires PGQL ↔ SQL bridge | **SQL/PGQ** |

**Advisor response when PGX is needed**:
> "This workload is better suited for PGX (Graph Server) than SQL/PGQ. SQL/PGQ excels at focused, filtered traversals from known vertices — for full-graph algorithms like PageRank and community detection, PGX processes the graph in memory and is significantly faster. PGX requires ADB-D (Dedicated) which includes Graph Server as a fully managed service."

**Note**: Always recommend ADB-D (fully managed) for PGX workloads. Do not recommend on-premises Graph Server installations.

---

## 4. PGX Memory Optimization

When loading a graph into PGX, select only the properties needed for the analysis. Loading all vertex/edge properties into memory wastes heap space.

```java
// ✅ GOOD: Load only needed properties
GraphConfig config = GraphConfigBuilder.forPropertyGraphRdbms()
  .setJdbcUrl("jdbc:oracle:thin:@...")
  .addVertexProperty("risk_score", PropertyType.DOUBLE)
  .addEdgeProperty("amount", PropertyType.DOUBLE)
  .build();

// ❌ BAD: Load all properties (wastes memory)
GraphConfig config = GraphConfigBuilder.forPropertyGraphRdbms()
  .setJdbcUrl("jdbc:oracle:thin:@...")
  .setLoadAllProperties(true)    // Loads everything including CLOBs
  .build();
```

**Memory sizing rule of thumb**:
- Each vertex: ~100 bytes base + property storage
- Each edge: ~64 bytes base + property storage
- A 10M-vertex, 100M-edge graph with 3 numeric properties: ~10 GB heap

Reference: [Load Graph to Memory](https://docs.oracle.com/en/database/oracle/property-graph/23.1/spgdg/load-graph-memory-and-run-graph-analytics.html)

---

## 5. Hybrid Approach: PGX + SQL/PGQ

Some workloads benefit from both engines. The pattern:

1. **PGX (batch/nightly)**: Compute graph algorithms (PageRank, community IDs, centrality scores)
2. **Store results**: Write algorithm outputs as vertex/edge properties back to the database
3. **SQL/PGQ (real-time)**: Use the pre-computed scores in real-time traversal queries

```sql
-- Step 1: PGX computes PageRank nightly, stores in n_user.pagerank_score

-- Step 2: SQL/PGQ uses it in real-time queries
SELECT * FROM GRAPH_TABLE (fraud_graph
  MATCH (u1) -[e1 IS uses_device]-> (d) <-[e2 IS uses_device]- (u2)
  WHERE u1.id = :uid
    AND u2.pagerank_score > 0.01    -- Pre-computed by PGX
    AND e1.end_date IS NULL AND e2.end_date IS NULL
  COLUMNS (u2.id AS neighbor, u2.pagerank_score AS pr)
)
```

**Benefits**:
- Real-time traversals enriched with graph-wide analytics
- No need to load the graph into memory for every query
- SQL/PGQ can index the pre-computed score column for fast filtering

**Trade-off**: PageRank scores are stale between PGX runs. Acceptable for most use cases (daily/hourly refresh).
