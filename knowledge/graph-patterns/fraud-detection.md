# Fraud Detection — Graph Patterns

Patterns derived from real-world fraud detection workloads on Oracle 23ai/26ai with SQL/PGQ. These patterns cover account linkage, device sharing, money laundering rings, and identity theft detection.

---

## Pattern 1: Shared Device / Shared Card (1-hop)

**Graph Pattern**:
```
(u1 IS user) -[e1 IS uses_device]-> (d IS device) <-[e2 IS uses_device]- (u2 IS user)
```

**SQL/PGQ**:
```sql
SELECT * FROM GRAPH_TABLE(fraud_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
  WHERE u1.id = :user_id
    AND u1.id <> u2.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (u2.id AS neighbor_id, d.device_fingerprint AS shared_device)
);
```

**Performance Characteristics**:
- Hops: 1 (via shared entity)
- Edge joins: 2 (e1, e2)
- Vertex joins: 3 (u1, d, u2)
- Fan-out risk: **HIGH** — popular devices (shared WiFi, public terminals) can have 1000+ edges
- Typical selectivity: `end_date IS NULL` filters ~80-90% of historical edges

**Index Strategy**:
- **Primary**: `CREATE INDEX idx_e_uses_device_src ON e_uses_device(src)` — enables nested loop from u1 to device edges
- **Primary**: `CREATE INDEX idx_e_uses_device_dst ON e_uses_device(dst)` — enables reverse traversal from device to u2
- **Composite**: `CREATE INDEX idx_e_uses_device_src_end ON e_uses_device(src, end_date)` — covers both filter and FK
- **Optimal**: `CREATE INDEX idx_e_uses_device_src_end_dst ON e_uses_device(src, end_date, dst)` — covers filter, source join, AND destination key

**Anti-patterns**:
- Do NOT skip the `end_date IS NULL` filter — without it, historical edges explode the result set
- Do NOT use this pattern without `u1.id <> u2.id` — produces self-joins

**Real-world frequency**: **HIGH** — 30-55% of all fraud graph queries in production (AWR data shows 21.93% + 4.45% DB time)

---

## Pattern 2: 2-Hop Device Chain (Friend of Friend)

**Graph Pattern**:
```
(u1) -[e1]-> (d1 IS device) <-[e2]- (u2) -[e3]-> (d2 IS device) <-[e4]- (u3)
```

**SQL/PGQ**:
```sql
SELECT * FROM GRAPH_TABLE(fraud_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d1 IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
                              -[e3 IS uses_device]-> (d2 IS device)
                             <-[e4 IS uses_device]- (u3 IS user_account)
  WHERE u1.id = :user_id
    AND u1.id <> u2.id AND u2.id <> u3.id AND u1.id <> u3.id
    AND e1.end_date IS NULL AND e2.end_date IS NULL
    AND e3.end_date IS NULL AND e4.end_date IS NULL
  COLUMNS (u3.id AS neighbor_2hop)
) FETCH FIRST 100 ROWS ONLY;
```

**Performance Characteristics**:
- Hops: 2
- Edge joins: 4 (e1, e2, e3, e4)
- Vertex joins: 5 (u1, d1, u2, d2, u3)
- Fan-out risk: **VERY HIGH** — multiplicative: if avg degree=10, 2-hop = 10x10 = 100 paths
- Typical selectivity: FETCH FIRST is essential to cap output

**Index Strategy**:
- All FK indexes on edge tables (SRC + DST) are **mandatory** — without them, 4 full table scans
- Composite indexes `(src, end_date, dst)` provide the best single-index coverage per edge access
- Consider `FETCH FIRST N ROWS ONLY` as part of the recommendation (not just indexing)

**Anti-patterns**:
- **Never** run 2-hop without FETCH FIRST — result explosion on supernodes
- Avoid hash joins on 2-hop — optimizer may choose them without indexes, leading to massive temp space usage

**Real-world frequency**: **LOW** (3-5% of executions) but **HIGH** elapsed time impact (11.93% DB time in AWR)

---

## Pattern 3: Triangle Detection (Circular 3-hop)

**Graph Pattern**:
```
(u1) -[e1]-> (d) <-[e2]- (u2) -[e3]-> (c) <-[e4]- (u3) -[e5]-> (p) <-[e6]- (u1)
```

**SQL/PGQ**:
```sql
SELECT * FROM GRAPH_TABLE(fraud_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]->     (d IS device)
                             <-[e2 IS uses_device]-      (u2 IS user_account)
                              -[e3 IS uses_card]->       (c IS card)
                             <-[e4 IS uses_card]-        (u3 IS user_account)
                              -[e5 IS validates_person]-> (p IS person)
                             <-[e6 IS validates_person]-  (u1)
  WHERE u1.id <> u2.id AND u2.id <> u3.id AND u1.id <> u3.id
    AND e1.end_date IS NULL AND e2.end_date IS NULL
    AND e3.end_date IS NULL AND e4.end_date IS NULL
    AND e5.end_date IS NULL AND e6.end_date IS NULL
  COLUMNS (u1.id AS u1_id, u2.id AS u2_id, u3.id AS u3_id)
) FETCH FIRST 10 ROWS ONLY;
```

**Performance Characteristics**:
- Hops: 3 (circular — closes back to u1)
- Edge joins: 6
- Vertex joins: 7
- Fan-out risk: **EXTREME** — without indexes, this generates 6 full table scans
- Typical runtime: 60+ seconds without indexes, <200ms with full FK indexes

**Index Strategy**:
- **All FK indexes are mandatory** (SRC + DST on every edge table in the pattern)
- Anchor predicate on u1 is critical — if u1 is constrained, the traversal starts from a small vertex set
- Without an anchor predicate, the optimizer does a cartesian product across all users — catastrophic
- Composite `(src, end_date, dst)` indexes eliminate both the filter and the join per edge access

**Anti-patterns**:
- **Never** run triangle detection without an anchor vertex predicate (WHERE u1.id = :id or similar)
- **Always** use FETCH FIRST — even with indexes, result sets can be large
- Break into two separate queries if possible (2-hop + existence check)

**Real-world frequency**: **RARE** (1%) but **highest cost per execution** — single executions can dominate DB time

---

## Pattern 4: Temporal Change Detection

**Graph Pattern**:
```
(u1) -[e1 WHERE start_date > :since]-> (d) <-[e2]- (u2)
```

**SQL/PGQ**:
```sql
SELECT * FROM GRAPH_TABLE(fraud_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
  WHERE u1.id = :user_id
    AND e2.start_date > :since_timestamp
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (u2.id AS neighbor_id, e2.start_date AS linked_since)
);
```

**Performance Characteristics**:
- Hops: 1
- Edge joins: 2
- Vertex joins: 3
- Fan-out risk: **MEDIUM** — temporal filter reduces result set
- Typical selectivity: `start_date > recent_date` filters 90-99% of edges (depending on time window)

**Index Strategy**:
- `CREATE INDEX idx_e_uses_device_start ON e_uses_device(start_date)` — for temporal range scan
- Composite: `CREATE INDEX idx_e_uses_device_dst_start ON e_uses_device(dst, start_date)` — enables index-only reverse traversal with temporal filter
- The `end_date IS NULL` filter can be combined: `CREATE INDEX idx_e_uses_device_dst_end_start ON e_uses_device(dst, end_date, start_date)`

**Anti-patterns**:
- Don't index `start_date` alone if the query also filters by `end_date IS NULL` — use composite
- Don't use `BETWEEN` for temporal filters when `>` suffices — BETWEEN generates different optimizer estimates

**Real-world frequency**: **MEDIUM** (10% of executions) — common for "recent activity" fraud alerts

---

## Pattern 5: High-Risk Neighbor Scoring

**Graph Pattern**:
```
(u1) -[e1]-> (entity) <-[e2]- (u2 WHERE risk_score > threshold)
```

**SQL/PGQ**:
```sql
SELECT * FROM GRAPH_TABLE(fraud_graph
  MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                             <-[e2 IS uses_device]- (u2 IS user_account)
  WHERE u1.id = :user_id
    AND u2.risk_score > 60
    AND u1.id <> u2.id
    AND e1.end_date IS NULL
    AND e2.end_date IS NULL
  COLUMNS (u2.id AS risky_neighbor, u2.risk_score AS score)
);
```

**Performance Characteristics**:
- Hops: 1
- Edge joins: 2
- Vertex joins: 3
- Fan-out risk: **LOW** — risk_score filter significantly reduces neighbors
- Typical selectivity: `risk_score > 60` matches 5-15% of users (depends on scoring model)

**Index Strategy**:
- Edge FK indexes (SRC, DST) are the primary need — vertex filter is applied after the join
- `CREATE INDEX idx_n_user_risk ON n_user(risk_score)` — only if selectivity < 5% AND the user table is large (>100K rows)
- The optimizer typically pushes the `risk_score` predicate into the join as a filter, so edge indexes matter more

**Anti-patterns**:
- Don't create a vertex index on `risk_score` if the predicate matches >15% of rows — full scan is faster
- Don't try to push the vertex filter into the edge table (denormalization) unless this is a top-3 query by elapsed time

**Real-world frequency**: **MEDIUM** (5-8% of executions) — used in real-time fraud scoring during transactions
