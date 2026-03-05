# SQL/PGQ Query Best Practices — Oracle 23ai / 26ai

## 1. Limit Variable-Length Path Depth

Always specify upper bounds on quantified patterns: `{1,3}` not `{1,}` or `*`.

Oracle 23ai has a **hard maximum of 10** for the upper bound. Internally, `{1,3}` generates UNION ALL of 3 fixed-length subqueries — so `{1,10}` = 10 unioned plans.

**Performance impact**: Each additional hop multiplies execution time. The CBO must optimize each sub-plan independently, and the UNION ALL aggregates all results.

```sql
-- ✅ Bounded: 3 sub-plans
MATCH (a) -[e]->{1,3} (b)

-- ❌ Max bound: 10 sub-plans (expensive)
MATCH (a) -[e]->{1,10} (b)

-- ❌ Will fail or produce terrible performance
MATCH (a) -[e]->{1,} (b)    -- Unbounded — Oracle rejects or caps at 10
```

**Rule of thumb**: If you need more than 4 hops, reconsider the graph design:
- Introduce shortcut edges (materialized paths)
- Use materialized views for common multi-hop results
- Break the query into stages using CTEs

---

## 2. Filter Before Traversal (Push Predicates Early)

Place WHERE conditions that filter the starting vertex BEFORE the MATCH expansion consumes resources.

The CBO pushes predicates from the WHERE clause into the GRAPH_TABLE expansion — but only if the column reference is unambiguous. Ensure your most selective predicate targets the starting vertex of the pattern.

```sql
-- ✅ GOOD: Selective predicate on start vertex — eliminates 95% of traversal start points
SELECT * FROM GRAPH_TABLE (my_graph
  MATCH (a IS account) -[e IS transfers]-> (b IS account)
  WHERE a.risk_score > 0.8    -- Only high-risk accounts as start points
    AND e.amount > 10000
  COLUMNS (a.id AS source, b.id AS target, e.amount)
)

-- ❌ BAD: No anchor predicate — scans ALL accounts as start points
SELECT * FROM GRAPH_TABLE (my_graph
  MATCH (a IS account) -[e IS transfers]-> (b IS account)
  WHERE e.amount > 10000      -- Only filters edges, not the start vertex
  COLUMNS (a.id AS source, b.id AS target, e.amount)
)
```

**Verification**: Use EXPLAIN PLAN and check that the most selective predicate appears in the FIRST operation (innermost access) of the plan, not as a late filter.

---

## 3. Use Bind Variables

Always use bind variables (`:account_id`, `:start_date`) instead of literals.

**Benefits**:
- Avoids hard parsing (parse-once, execute-many)
- Enables cursor sharing
- Stabilizes execution plans

**Oracle-specific**: With literals, each distinct value generates a new child cursor. For graph queries that run repeatedly with different start vertices, this means thousands of unnecessary hard parses and wasted shared pool memory.

```sql
-- ✅ GOOD: Bind variable — one cursor, many executions
EXECUTE IMMEDIATE '
  SELECT COUNT(*) FROM GRAPH_TABLE (my_graph
    MATCH (a) -[e]-> (b)
    WHERE a.id = :acct_id AND e.end_date IS NULL
    COLUMNS (b.id AS neighbor)
  )' INTO v_cnt USING v_account_id;

-- ❌ BAD: Literal — new cursor for every account
EXECUTE IMMEDIATE '
  SELECT COUNT(*) FROM GRAPH_TABLE (my_graph
    MATCH (a) -[e]-> (b)
    WHERE a.id = 12345 AND e.end_date IS NULL
    COLUMNS (b.id AS neighbor)
  )' INTO v_cnt;
```

**Note**: In PL/SQL, you MUST use `EXECUTE IMMEDIATE` with binds for GRAPH_TABLE queries (ORA-49028 workaround). This naturally enforces bind variable usage.

---

## 4. Minimal Projection in COLUMNS

Only select the columns you need in the `COLUMNS()` clause of GRAPH_TABLE.

Every additional column may force the CBO to access the base table even when an index would have sufficed. A covering index on `(src, end_date, dst)` can satisfy the filter AND join without touching the table — unless you request a column not in the index (like `start_date`).

```sql
-- ✅ GOOD: Only project what's needed — enables index-only scan
SELECT * FROM GRAPH_TABLE (my_graph
  MATCH (a) -[e IS uses_device]-> (d)
  WHERE a.id = :uid AND e.end_date IS NULL
  COLUMNS (d.id AS device_id)          -- Only need the device ID
)

-- ❌ BAD: Extra columns force table access
SELECT * FROM GRAPH_TABLE (my_graph
  MATCH (a) -[e IS uses_device]-> (d)
  WHERE a.id = :uid AND e.end_date IS NULL
  COLUMNS (d.id AS device_id,
           e.start_date,               -- Not in covering index
           e.last_updated,             -- Not in covering index
           d.device_fingerprint)       -- From vertex table — extra join
)
```

---

## 5. Avoid Multiple Variable-Length Expansions

A pattern like `(a)-[e1]->{1,3}(b)-[e2]->{1,3}(c)` produces the cartesian product of both expansions: 3 hops × 3 hops = up to 9 subqueries unioned. If the intermediate result set is large, this explodes.

**Solution**: Break into two queries or use a CTE to materialize the intermediate result:

```sql
-- ❌ BAD: Double expansion in one query
SELECT * FROM GRAPH_TABLE (my_graph
  MATCH (a) -[e1]->{1,3} (b) -[e2]->{1,3} (c)
  WHERE a.id = :start_id
  COLUMNS (c.id AS final_target)
)

-- ✅ GOOD: Two-stage approach with CTE
WITH stage1 AS (
  SELECT * FROM GRAPH_TABLE (my_graph
    MATCH (a) -[e1]->{1,3} (b)
    WHERE a.id = :start_id
    COLUMNS (b.id AS intermediate_id)
  )
)
SELECT * FROM GRAPH_TABLE (my_graph
  MATCH (b) -[e2]->{1,3} (c)
  WHERE b.id IN (SELECT intermediate_id FROM stage1)
  COLUMNS (c.id AS final_target)
)
```

---

## 6. Predicate Placement: Inside MATCH vs Outside

Predicates can be placed inside the MATCH WHERE or outside in the enclosing SELECT WHERE.

**Inside MATCH WHERE** (generally preferred):
```sql
SELECT * FROM GRAPH_TABLE (my_graph
  MATCH (a) -[e]-> (b)
  WHERE a.id = :uid              -- Inside: pushes down early
    AND e.end_date IS NULL       -- Inside: filters edges before join
  COLUMNS (b.id AS neighbor)
)
```

**Outside (enclosing SELECT)**:
```sql
SELECT * FROM (
  SELECT * FROM GRAPH_TABLE (my_graph
    MATCH (a) -[e]-> (b)
    COLUMNS (a.id AS src, b.id AS dst, e.end_date AS edate)
  )
)
WHERE src = :uid AND edate IS NULL   -- Outside: may or may not push down
```

**Rule**: Place predicates inside MATCH WHERE whenever possible. The CBO is more likely to push them into the earliest plan operation. Complex expressions (subqueries, CASE, analytic functions) may not push down — verify with EXPLAIN PLAN.

---

## 7. Hint Placement for GRAPH_TABLE Queries

Hints placed inside GRAPH_TABLE's COLUMNS clause do **NOT** propagate to the expanded plan. Always place optimizer hints on the **enclosing SELECT** statement.

```sql
-- ✅ CORRECT: Hint on outer SELECT
SELECT /*+ PARALLEL(4) */ * FROM GRAPH_TABLE (my_graph
  MATCH (a) -[e]-> (b)
  WHERE a.id = :uid
  COLUMNS (b.id AS neighbor)
)

-- ❌ WRONG: Hint inside COLUMNS (ignored)
SELECT * FROM GRAPH_TABLE (my_graph
  MATCH (a) -[e]-> (b)
  WHERE a.id = :uid
  COLUMNS (/*+ PARALLEL(4) */ b.id AS neighbor)    -- Ignored!
)
```

**Advanced**: To reference specific tables inside the expansion, use query block naming from EXPLAIN PLAN output:

```sql
-- Step 1: Run EXPLAIN PLAN to find query block names
-- Step 2: Use @"query_block" syntax
SELECT /*+ INDEX(@"SEL$5ED53527" "E2" "IDX_E_USES_DEVICE_DST") */ *
FROM GRAPH_TABLE (my_graph
  MATCH (u1) -[e1 IS uses_device]-> (d) <-[e2 IS uses_device]- (u2)
  WHERE u1.id = :uid
  COLUMNS (u2.id AS neighbor)
)
```
