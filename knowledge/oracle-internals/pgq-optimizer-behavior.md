# Oracle CBO Behavior with GRAPH_TABLE (SQL/PGQ)

Documented observations from Oracle 23ai and 26ai regarding how the Cost-Based Optimizer handles SQL/PGQ queries. These findings are based on real-world testing and AWR analysis.

See also: `official-documentation-reference.md` in this directory for the feature matrix, variable-length path performance model, and verified documentation URLs.

---

## 1. GRAPH_TABLE Rewrite Mechanism

**How it works**: The `GRAPH_TABLE` operator is expanded by the optimizer during the query transformation phase — before cost estimation. By the time the CBO evaluates join orders and access paths, the query is pure relational SQL.

**Key observations**:

- The rewrite happens in the **query transformation** phase, not during parsing. You can see the expanded query in `V$SQL_PLAN` — it shows standard table access operations.
- Each `IS label` clause in the MATCH pattern resolves to a specific table from the property graph definition. If the label matches multiple tables, Oracle generates a `UNION ALL` across all matching tables.
- Edge patterns like `(a)-[e]->(b)` generate `JOIN edge_table e ON e.src = a.pk JOIN vertex_table b ON e.dst = b.pk`. The join predicates are derived from `USER_PG_EDGE_RELATIONSHIPS`.
- The expanded query preserves all user-specified predicates from the `WHERE` clause inside `GRAPH_TABLE`. These are applied as close to the base table access as possible (predicate pushdown works normally).

**Implication for the advisor**: Execution plans from GRAPH_TABLE queries are **standard relational plans**. Read them as such — TABLE ACCESS FULL, INDEX RANGE SCAN, HASH JOIN, NESTED LOOPS. There is no special "graph execution engine".

---

## 2. Join Order Selection for Multi-Hop Patterns

**How it works**: For a pattern like `(a)-[e1]->(b)-[e2]->(c)`, the CBO must decide the join order among tables `a`, `e1`, `b`, `e2`, `c`. The optimizer uses standard cardinality estimation and cost models.

**Key observations**:

- **With indexes**: The CBO typically chooses a left-deep nested loop plan starting from the most selective vertex predicate. For `WHERE a.id = :id`, it starts with `a`, does an index range scan on `e1(src)`, nested loops to `b`, index range scan on `e2(src)`, and nested loops to `c`. This is optimal for selective start vertices.

- **Without indexes on edge FK columns**: The CBO falls back to hash joins. It reads the entire edge table into a hash table, then probes with vertex keys. For large edge tables (>100K rows), this causes massive buffer gets and temp space usage.

- **Cardinality estimation challenges**: The CBO estimates join cardinality using column statistics and join selectivity. For graph patterns, the intermediate result cardinality after the first edge join is critical. If the CBO overestimates it, it chooses hash join (wasteful for selective patterns). If it underestimates, it chooses nested loops on a huge intermediate set (even worse).

- **Star transformation**: Oracle's star transformation does NOT apply to GRAPH_TABLE expansions (even though the edge table pattern resembles a fact table with dimension joins). Don't rely on it.

**Implication for the advisor**: Missing FK indexes on edge tables cause the CBO to switch from nested loops (optimal for selective traversals) to hash joins (acceptable for analytics, terrible for OLTP graph lookups).

---

## 3. Predicate Pushdown in GRAPH_TABLE

**How it works**: Predicates in the `WHERE` clause of `GRAPH_TABLE` are pushed down to the base table access during query transformation.

**Key observations**:

- Predicates on **vertex properties** (e.g., `WHERE u1.id = :id`) are pushed to the vertex table access. This is standard predicate pushdown and works reliably.

- Predicates on **edge properties** (e.g., `WHERE e1.end_date IS NULL`) are pushed to the edge table access. Combined with an index on the predicate column, this can dramatically reduce the edge rows entering the join.

- Predicates on **vertex properties of non-anchor vertices** (e.g., `WHERE u2.risk_score > 60` where u2 is the destination) are applied **after** the join to u2. They cannot be pushed into the edge table access because the predicate depends on the joined vertex table.

- **Cross-table predicates** (e.g., `WHERE u1.id <> u2.id`) are applied as join filters, not as base table filters. The optimizer handles these correctly as anti-join conditions.

- **Predicates outside GRAPH_TABLE**: Predicates in the outer query (outside the `GRAPH_TABLE(...)` expression) are applied after the graph pattern is fully materialized. Move filters inside `GRAPH_TABLE` when possible for better performance.

**Implication for the advisor**: Always recommend moving predicates inside the GRAPH_TABLE WHERE clause. Predicates outside the expression are applied late, after the full graph pattern materialization.

---

## 4. Statistics Impact on GRAPH_TABLE Plans

**How it works**: The CBO relies on `DBMS_STATS` table and column statistics for cardinality estimation. Graph queries are particularly sensitive to stale or missing statistics because of the multiplicative nature of join cardinality in multi-hop patterns.

**Key observations**:

- **Missing stats**: When table statistics are missing (e.g., after a fresh data load), Oracle uses **dynamic sampling** (level 2 by default in 23ai). Dynamic sampling samples a small number of blocks and extrapolates. For skewed graph data (supernodes), this produces wildly inaccurate estimates.

- **Stale stats**: After significant DML (>10% row change), stats become stale. The CBO may continue using old cardinality estimates, leading to suboptimal join orders. Check `USER_TAB_STATISTICS.STALE_STATS` (note: this column is in `USER_TAB_STATISTICS`, not `USER_TABLES`).

- **Histograms**: For edge FK columns with skewed degree distributions (supernodes), frequency or hybrid histograms are critical. Without histograms, the CBO assumes uniform distribution — estimating the same number of edges per vertex. This causes massive underestimates for supernode vertices and overestimates for low-degree vertices.

- **Extended statistics**: For composite predicates like `WHERE src = :id AND end_date IS NULL`, create column group statistics:
  ```sql
  SELECT DBMS_STATS.CREATE_EXTENDED_STATS(USER, 'E_USES_DEVICE', '(SRC, END_DATE)') FROM DUAL;
  EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'E_USES_DEVICE', METHOD_OPT => 'FOR ALL COLUMNS SIZE AUTO');
  ```

- **Adaptive statistics** (23ai): Oracle can learn from execution feedback and adjust statistics between executions. This is controlled by `OPTIMIZER_ADAPTIVE_STATISTICS`. For graph workloads with varying selectivity (different user IDs have different degrees), adaptive statistics help but don't fully solve the supernode problem.

**Implication for the advisor**: Always check `LAST_ANALYZED` dates and gather stats with histograms before making optimization recommendations. Stale stats can make good indexes appear ineffective.

---

## 5. PL/SQL Integration Limitations

**How it works**: PL/SQL has specific limitations when interacting with SQL/PGQ constructs.

**Key observations**:

- **ORA-49028**: PL/SQL variables (declared in `DECLARE` or procedure parameters) **cannot** be referenced directly inside a `GRAPH_TABLE` expression. The PL/SQL compiler does not recognize the variable reference inside the SQL/PGQ syntax.

  ```sql
  -- FAILS with ORA-49028
  SELECT COUNT(*) INTO v_cnt
  FROM GRAPH_TABLE(g MATCH (a)-[e]->(b) WHERE a.id = v_user_id COLUMNS (...));

  -- WORKS: use EXECUTE IMMEDIATE with bind variables
  EXECUTE IMMEDIATE '
    SELECT COUNT(*) FROM GRAPH_TABLE(g
      MATCH (a)-[e]->(b) WHERE a.id = :p_uid COLUMNS (...)
    )' INTO v_cnt USING v_user_id;
  ```

- **Bind variable naming**: Avoid short bind variable names like `:ts` or `:id` — they can conflict with Oracle reserved words or parser tokens. Use descriptive names like `:p_user_id`, `:p_timestamp`.

- **Cursor sharing**: `EXECUTE IMMEDIATE` GRAPH_TABLE queries participate in cursor sharing normally. The CBO generates a shared cursor with bind variable peeking on the first execution. Subsequent executions reuse the plan (unless adaptive cursor sharing kicks in).

- **Bulk operations**: `FORALL` + `EXECUTE IMMEDIATE` does work for DML inside GRAPH_TABLE, but `BULK COLLECT INTO` with GRAPH_TABLE requires careful syntax — the `COLUMNS` clause must match the collection type.

**Implication for the advisor**: When recommending PL/SQL procedures for workload testing, always use `EXECUTE IMMEDIATE` with named bind variables. Test with representative bind values to ensure the first-execution plan is reasonable.

---

## 6. Execution Plan Caching and Aging

**How it works**: GRAPH_TABLE queries generate standard SQL cursors in the shared pool. They follow the same cursor caching, aging, and invalidation rules as regular SQL.

**Key observations**:

- **Cursor aging**: When the shared pool is under memory pressure, older cursors are aged out (LRU). This means previously warmed graph query plans disappear and must be re-parsed + re-optimized on next execution. After creating indexes, the old plans (without indexes) may still be cached — new plans only appear when a new child cursor is created.

- **Cursor invalidation**: DDL operations on tables referenced by GRAPH_TABLE queries (e.g., `CREATE INDEX`, `GATHER_TABLE_STATS`, `ALTER TABLE`) invalidate existing cursors. The next execution triggers a hard parse, which considers the new index. This is the mechanism by which new indexes become visible to cached queries.

- **Child cursors**: If bind variable peeking produces a bad plan for a different bind value distribution (e.g., supernode vs. low-degree user), Oracle creates a new child cursor with adaptive cursor sharing (ACS). Monitor `V$SQL.IS_BIND_SENSITIVE` and `V$SQL.IS_BIND_AWARE` columns.

- **SQL Plan Baselines**: `DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE` works normally with GRAPH_TABLE queries. Use it to lock good plans after optimization. Set `FIXED = 'YES'` to prevent plan regression.

- **Flushing considerations**: `ALTER SYSTEM FLUSH SHARED_POOL` may require elevated privileges on ADB-S. As an alternative, executing a GRAPH_TABLE query with `EXECUTE IMMEDIATE` from a new session generates a fresh cursor without flushing.

**Implication for the advisor**: After creating invisible indexes, force a hard parse by either: (1) altering the SQL text slightly (add a comment), (2) executing from a new session, or (3) gathering stats (which invalidates cursors). Don't assume the existing cached plan will automatically pick up new indexes.
