# Physical Design for Graph Tables — Oracle 23ai / 26ai

## 1. Edge Table Partitioning Strategies

Edge tables are the most critical tables for graph performance — they drive every traversal. Three partitioning strategies with trade-offs:

### 1a. HASH(source_key)

Best for forward traversals from known vertices. All edges from one source are in the same partition, enabling partition pruning when the start vertex is known.

```sql
CREATE TABLE e_transfers (
  id        NUMBER,
  src       NUMBER NOT NULL,
  dst       NUMBER NOT NULL,
  amount    NUMBER(15,2),
  txn_date  TIMESTAMP,
  end_date  TIMESTAMP,
  CONSTRAINT pk_transfers PRIMARY KEY (id)
)
PARTITION BY HASH (src)
PARTITIONS 16;
```

**Pros**: Forward traversals prune to a single partition. Uniform data distribution.
**Cons**: Reverse traversals (by `dst`) cannot prune — they scan all partitions. Partition count should be a power of 2 for optimal hash distribution.

### 1b. RANGE(date) SUBPARTITION BY HASH(source_key)

Best for temporal graph queries ("transfers in last 30 days from account X"). Range partition prunes by date, hash subpartition prunes by source.

```sql
CREATE TABLE e_transfers (
  id        NUMBER,
  src       NUMBER NOT NULL,
  dst       NUMBER NOT NULL,
  amount    NUMBER(15,2),
  txn_date  TIMESTAMP NOT NULL,
  end_date  TIMESTAMP,
  CONSTRAINT pk_transfers PRIMARY KEY (id)
)
PARTITION BY RANGE (txn_date)
  SUBPARTITION BY HASH (src) SUBPARTITIONS 8
(
  PARTITION p_2025_q1 VALUES LESS THAN (TIMESTAMP '2025-04-01 00:00:00'),
  PARTITION p_2025_q2 VALUES LESS THAN (TIMESTAMP '2025-07-01 00:00:00'),
  PARTITION p_2025_q3 VALUES LESS THAN (TIMESTAMP '2025-10-01 00:00:00'),
  PARTITION p_2025_q4 VALUES LESS THAN (TIMESTAMP '2026-01-01 00:00:00'),
  PARTITION p_future   VALUES LESS THAN (MAXVALUE)
);
```

**Pros**: Double pruning (date + source). Easy data lifecycle (drop old partitions). Ideal for temporal fraud detection.
**Cons**: More complex maintenance. Requires careful partition boundary planning.

### 1c. LIST(label)

When multiple edge types share one table. Each label gets its own partition.

```sql
CREATE TABLE e_all_relationships (
  id              NUMBER,
  src             NUMBER NOT NULL,
  dst             NUMBER NOT NULL,
  relationship_type VARCHAR2(30) NOT NULL,
  start_date      TIMESTAMP,
  end_date        TIMESTAMP,
  CONSTRAINT pk_all_rel PRIMARY KEY (id)
)
PARTITION BY LIST (relationship_type)
(
  PARTITION p_uses_device VALUES ('USES_DEVICE'),
  PARTITION p_uses_card   VALUES ('USES_CARD'),
  PARTITION p_validates   VALUES ('VALIDATES_PERSON'),
  PARTITION p_declares    VALUES ('DECLARES_PERSON'),
  PARTITION p_other       VALUES (DEFAULT)
);
```

**Pros**: Queries filtering by edge type prune to one partition. Combines with separate-table-per-label in the graph definition.
**Cons**: Skewed partition sizes if label distribution is uneven. May need subpartitioning for large partitions.

---

## 2. Local Indexes on Partitioned Tables

When edge tables are partitioned, all non-unique indexes should be **LOCAL** (one index segment per partition).

```sql
-- LOCAL index: one segment per partition
CREATE INDEX idx_transfers_src ON e_transfers(src) LOCAL;
CREATE INDEX idx_transfers_dst ON e_transfers(dst) LOCAL;

-- LOCAL composite covering index
CREATE INDEX idx_transfers_src_end_dst ON e_transfers(src, end_date, dst) LOCAL;
```

**Benefits**:
- **Partition maintenance**: Add/drop partitions without global index rebuild
- **Parallelism**: Each partition's index is scanned independently
- **Reduced contention**: DML on different partitions updates different index segments

**Exception**: If you need a globally unique constraint on a non-partition-key column, you must use GLOBAL. But for graph FK lookups (SRC, DST), LOCAL is almost always correct.

**GLOBAL index use case**: When reverse traversals (by DST) need to be fast on a HASH(SRC)-partitioned table:
```sql
-- GLOBAL index on DST for reverse traversals across all partitions
CREATE INDEX idx_transfers_dst_global ON e_transfers(dst) GLOBAL;
```

---

## 3. Partition-Wise Joins

When both the edge table and vertex table are partitioned on compatible columns, Oracle can perform **partition-wise joins** — each partition-pair joins independently, reducing memory and enabling full parallelism.

**Requirements**:
- Same partition key column semantics (e.g., edge.src ↔ vertex.id)
- Same number of partitions
- Same partitioning method (both HASH or both RANGE)

```sql
-- Edge table: HASH(src) 16 partitions
CREATE TABLE e_transfers (...) PARTITION BY HASH (src) PARTITIONS 16;

-- Vertex table: HASH(id) 16 partitions (same count!)
CREATE TABLE n_account (...) PARTITION BY HASH (id) PARTITIONS 16;

-- The CBO can now do full partition-wise join for forward traversals:
-- Partition 1 of e_transfers joins only with Partition 1 of n_account
```

**Note**: This is an advanced optimization — only worth the effort for very large graphs (10M+ edges). For smaller graphs, the overhead of managing identical partition counts across tables outweighs the benefit.

---

## 4. Vertex Table Considerations

Vertex tables are typically smaller and accessed by PK. Partitioning vertex tables is usually unnecessary unless:

- The vertex table is very large (1M+ rows)
- It has temporal access patterns (e.g., `WHERE created_date > :cutoff`)
- You want partition-wise joins with the edge table (see above)

If partitioned, use the same strategy as the edge table's FK column to enable partition-wise joins. For most graphs, a simple heap table with a PK index is sufficient for vertex tables.

---

## 5. Index-Organized Tables (IOT) for Edge Tables

An alternative to heap + indexes: make the edge table itself an IOT organized on `(source_key, destination_key)`.

```sql
CREATE TABLE e_transfers (
  src       NUMBER NOT NULL,
  dst       NUMBER NOT NULL,
  id        NUMBER NOT NULL,
  amount    NUMBER(15,2),
  txn_date  TIMESTAMP,
  end_date  TIMESTAMP,
  CONSTRAINT pk_transfers PRIMARY KEY (src, dst, id)
)
ORGANIZATION INDEX
COMPRESS 1;    -- Compress the leading column (src) for storage savings
```

**How it works**: The table data IS the index. Edges for one source vertex are stored physically contiguously. Forward traversals become sequential I/O instead of random I/O.

**Pros**:
- Excellent for read-heavy graph analytics
- Forward traversals are physically sequential (better cache behavior)
- No separate index needed for `(src, dst)` — the table IS the index
- COMPRESS 1 deduplicates the leading key (src), saving storage

**Cons**:
- Poor for random INSERT performance (B-tree maintenance on every insert)
- Secondary indexes on IOTs use logical rowids (slower than physical rowids)
- UPDATE/DELETE performance may degrade vs heap tables

**Recommend for**: Read-heavy/analytics graphs, batch-loaded graphs, OLAP-style traversals.
**Avoid for**: High-DML streaming graphs, real-time INSERT-heavy workloads.
