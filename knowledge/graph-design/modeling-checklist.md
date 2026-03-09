---
verified_version: "23ai"
last_verified: "2026-03-09"
oracle_doc_urls: []
next_review: "on_new_oracle_release"
confidence: "high"
---

# Graph Modeling Checklist — 8 Rules for Oracle SQL/PGQ

## Rule 1: Query-First Modeling

Design your graph to answer the questions you'll actually ask. Start from the traversal patterns (which vertex is the start point, what edge types are traversed, what properties are filtered/projected) and work backward to table design.

**Oracle mapping**: The "start vertex lookup" must land on an indexed column. If your most common query starts from `account_id`, that column must be the vertex PK or have a dedicated index. The GRAPH_TABLE expansion always begins with the anchor vertex — if the CBO cannot efficiently locate that vertex, every downstream join inherits the cost.

**Example**:
```
-- If 80% of queries start from a user ID:
--   ✅ n_user(id NUMBER PRIMARY KEY)  → PK index, instant lookup
--   ❌ n_user(uuid VARCHAR2(36) PRIMARY KEY, id NUMBER)  → PK on UUID, need separate index on id
```

---

## Rule 2: Supernode/Hub Isolation

Vertices with millions of edges (e.g., a popular merchant, a system account) cause fan-out explosions at every hop. If a single vertex has 500K edges and you do a 2-hop, you hit 500K × avg_degree rows.

**Oracle mapping**: Identify hub vertices using SELECTIVITY-04 (edge degree distribution). Mitigations:

1. **Ultra-selective edge filters**: Add a filter on the edges of hub vertices (e.g., `WHERE e.created_date > SYSDATE - 7`) so only recent edges are traversed.
2. **Partition edge table by source_key**: `PARTITION BY HASH(src)` so hub traversals hit a single partition instead of the full table.
3. **Relay vertices**: Split the hub into logical sub-groups. Instead of one giant `merchant` vertex with 1M edges, create `merchant_2024_Q1`, `merchant_2024_Q2`, etc. Each has a manageable edge count.
4. **Degree cap in query**: Add `WHERE d.adjacent_edges_count < :max_degree` to skip supernodes entirely.

**Detection query**:
```sql
SELECT src, COUNT(*) AS degree
FROM edge_table
WHERE end_date IS NULL
GROUP BY src
ORDER BY degree DESC
FETCH FIRST 20 ROWS ONLY;
```

---

## Rule 3: Specific Relationship Types

Use `TRANSFERRED`, `PURCHASED`, `FOLLOWS` — never generic `RELATED_TO`. Each edge label in SQL/PGQ maps to a distinct edge table (or IS LABELED filter within one table).

**Oracle mapping**: With separate edge tables per label, the CBO only scans the relevant table for a given traversal. With a single table + label column, you need an index on `(label, source_key)` or partitioning by label.

| Approach | Pros | Cons |
|---|---|---|
| Separate tables per label | CBO scans only relevant table; independent stats; independent indexes | More tables to manage; UNION ALL for "all neighbors" queries |
| Single table + label column | Simpler schema; one set of indexes | Larger table; needs label-prefix indexes; mixed stats |

**Recommendation**: Use separate tables when labels have different property schemas or very different volumes. Use a single table when labels share identical schemas and you frequently query "all relationships."

---

## Rule 4: Branching Factor Control

If the average number of neighbors per hop is N, a K-hop query produces approximately N^K intermediate rows. For N=100 and K=3, that's 1M rows before any filtering.

**Oracle mapping**: Introduce intermediate vertices to break high-fanout hops.

```
-- HIGH FAN-OUT (10K purchases per user):
User -[PURCHASED]-> Product     -- N=10,000 per user

-- CONTROLLED FAN-OUT (introduce Order):
User -[PLACED]-> Order -[CONTAINS]-> Product
--    N=50            N=5
-- Total: 50 × 5 = 250 intermediate rows (vs 10,000)
```

The CBO can then apply filters between hops, and each join operates on a manageable result set. This also enables index-only scans on the intermediate edge table if it's thin enough.

---

## Rule 5: Separate Logical Graphs by Use Case

Don't put everything in one massive graph if the queries don't overlap. A fraud detection graph and a recommendation graph on the same data should be separate `CREATE PROPERTY GRAPH` definitions with different edge/vertex subsets.

**Oracle mapping**:
- Smaller graphs = more stable optimizer statistics
- Fewer UNION ALL branches in "all edges" queries (e.g., Q07-style edge count)
- Lower cardinality estimates = better CBO decisions
- Independent discovery phase (faster analysis)

```sql
-- Fraud-specific graph (only fraud-relevant edges)
CREATE PROPERTY GRAPH fraud_graph
  VERTEX TABLES (n_user, n_device, n_card)
  EDGE TABLES (e_uses_device, e_uses_card);

-- Recommendation graph (different subset)
CREATE PROPERTY GRAPH reco_graph
  VERTEX TABLES (n_user, n_product, n_category)
  EDGE TABLES (e_purchased, e_viewed, e_rated);
```

---

## Rule 6: Lightweight Vertex/Edge Tables

Keep graph tables "thin" — core identifiers, FKs, and frequently filtered/projected properties only. Large JSON blobs, CLOBs, or text descriptions belong in a separate detail table joined on demand.

**Oracle mapping**: Thinner rows = more rows per database block = faster full scans when they happen. Edge tables especially benefit because they're the most scanned tables in graph queries.

```sql
-- ✅ THIN edge table (good for graph traversals)
CREATE TABLE transfers (
  id          NUMBER PRIMARY KEY,
  from_acct   NUMBER NOT NULL,  -- FK to source vertex
  to_acct     NUMBER NOT NULL,  -- FK to dest vertex
  amount      NUMBER(15,2),
  txn_date    TIMESTAMP,
  is_suspicious CHAR(1)
);

-- ❌ FAT edge table (bad: CLOB and JSON bloat every block)
CREATE TABLE transfers (
  id          NUMBER PRIMARY KEY,
  from_acct   NUMBER NOT NULL,
  to_acct     NUMBER NOT NULL,
  amount      NUMBER(15,2),
  txn_date    TIMESTAMP,
  is_suspicious CHAR(1),
  description CLOB,              -- Move to detail table
  metadata    JSON,               -- Move to detail table
  audit_trail VARCHAR2(4000)      -- Move to detail table
);
```

**Split pattern**: Keep the thin table in the graph definition. Join the detail table only when the user queries those columns:
```sql
SELECT gt.neighbor_id, d.description
FROM GRAPH_TABLE(...) gt
JOIN transfer_details d ON d.transfer_id = gt.edge_id;
```

---

## Rule 7: Compact, Consistent ID Types

Use `NUMBER` or `INTEGER` for vertex/edge identifiers. Avoid `VARCHAR2` UUIDs or composite string keys where possible.

**Oracle mapping**: `NUMBER` PKs produce smaller B-tree indexes (8 bytes vs 36+ bytes for UUID strings), faster index lookups, and more efficient hash/nested-loop joins.

| ID Type | Index Size (1M rows) | Lookup Speed | Join Efficiency |
|---|---|---|---|
| `NUMBER` | ~8 MB | Fast (compact B-tree) | Optimal (hash on 8 bytes) |
| `VARCHAR2(36)` UUID | ~36 MB | 4× slower (wider keys) | 4× more memory for hash |
| Composite `(col1, col2)` | Variable | Requires multi-column access | Complex join predicates |

For edge FK columns (`SRC`, `DST`) — the most accessed columns in graph queries — this difference is amplified. A 1M-row edge table with NUMBER FKs has indexes roughly 4× smaller than with VARCHAR2(36) UUIDs.

**If you must use UUIDs**: Use `RAW(16)` instead of `VARCHAR2(36)`. RAW(16) stores the 128-bit UUID in binary (16 bytes vs 36 characters), cutting index size by more than half.

---

## Rule 8: Consistent Edge Directionality

Define a convention (e.g., `FROM → TO` always represents the chronological or causal direction) and document it. Inconsistent direction means you'll need bidirectional traversals (matching both `-[e]->` and `<-[e]-`), which doubles the edge scans.

**Oracle mapping**: With consistent direction, you only need an index on `source_key` for forward traversals OR `destination_key` for reverse — not both. Inconsistent direction forces bidirectional indexes on every edge table (2× index storage, 2× DML overhead).

```
-- ✅ CONSISTENT: source is always the actor, destination is the target
User -[USES]-> Device         -- User is the actor
User -[PURCHASES]-> Product   -- User is the actor
User -[TRANSFERS]-> Account   -- User is the sender

-- ❌ INCONSISTENT: direction is ambiguous
User -[ASSOCIATED_WITH]-> Device   -- Who "associated" whom?
Product -[BOUGHT_BY]-> User        -- Reversed direction!
Account -[RECEIVED_FROM]-> User    -- Reversed again!
```

**Documenting convention**: Add a comment in the `CREATE PROPERTY GRAPH` DDL:
```sql
-- Convention: SOURCE = actor/initiator, DESTINATION = target/recipient
-- All edges flow from the entity performing the action to the entity receiving it
CREATE PROPERTY GRAPH my_graph ...
```
