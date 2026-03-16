# Phase 7: SCALABILITY TESTING (optional)

**Goal**: Verify that recommendations and graph design hold under realistic data growth. This phase is optional and triggered when the user requests scalability validation, or automatically during demo/test sessions.

**Prerequisites**:
- Production guard passed (non-production environment confirmed)
- Phase 6 recommendations have been applied
- Baseline performance captured (elapsed time, buffer gets, rows processed)

**Step 1: Assess current scale**
```sql
SELECT
    e.element_kind,
    e.object_name AS table_name,
    t.num_rows
FROM user_pg_elements e
JOIN user_tables t ON e.object_name = t.table_name
ORDER BY e.element_kind, t.num_rows DESC;
```

**Step 2: Generate scaled data**

When the user asks to test scalability (e.g., "test at 10X"), generate data that multiplies the current volume while preserving the graph's structural properties:
- Maintain the same vertex-to-edge ratio
- Preserve edge degree distribution (don't create uniform fan-out — use realistic power-law or normal distribution)
- Preserve property value distributions (if 0.5% of edges are `is_suspicious = 'Y'`, maintain that ratio at 10X)
- Use PL/SQL bulk operations for fast generation (FORALL with BULK COLLECT)

**IMPORTANT**: Adapt the generation logic to the specific graph schema. Do not use a generic template blindly — inspect the table structure, constraints, and property distributions first.

**Step 3: Refresh statistics**
```sql
BEGIN DBMS_STATS.GATHER_TABLE_STATS(USER, :table_name); END;
/
```

**Step 4: Re-run diagnostic phases**

After scaling, re-run Phases 2-6:
1. Re-identify top queries (IDENTIFY-01) — execution times should have changed
2. Re-analyze execution plans (ANALYZE-01) — check if plans changed with new cardinalities
3. Re-evaluate index effectiveness — does the composite index still help at 10X?
4. Check for new bottlenecks that only appear at scale (hash join spills, temp tablespace usage)

**Step 5: Compare and report**

```
SCALABILITY REPORT
━━━━━━━━━━━━━━━━━━
Scale:      1X → {target}X ({edge_count_before} → {edge_count_after} edges)

| Query | Metric  | 1X no-idx | 1X with-idx | {target}X with-idx | Idx benefit | Scale growth | Verdict      |
|-------|---------|-----------|-------------|--------------------|-------------|--------------|--------------|
| Q1    | Elapsed | 0.31s     | 0.01s       | 0.09s              | 97% ↓       | 9X           | ✅ Linear    |

Verdicts (on Scale growth column):
- ✅ Linear:      Growth ≤ 1.2 × data_multiplier (healthy)
- ⚠️ Review:      Growth > 1.2X but < data_multiplier² (investigate)
- ❌ Superlinear:  Growth ≥ data_multiplier² (design issue)
```

**Cleanup**: Always offer to clean up generated test data after testing.
