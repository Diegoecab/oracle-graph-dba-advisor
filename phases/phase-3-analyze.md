# Phase 3: DEEP DIVE — Analyze Execution Plans

**Goal**: For each top offender, understand *exactly* how the optimizer executes it and where time is spent.

**Actions**:
1. Get actual execution plan with runtime stats → `ANALYZE-01`
2. Identify the most expensive operations in the plan → Manual analysis
3. Check for full table scans on edge tables → Plan reading
4. Check join order and join methods → Plan reading
5. Compare estimated vs actual rows (E-Rows vs A-Rows) → Cardinality issues

**What to look for in graph query plans**:

```
CRITICAL PATTERNS TO FLAG:

❌ TABLE ACCESS FULL on edge table (>100K rows)
   → Almost always means a missing index on the filter column or FK column

❌ HASH JOIN where NESTED LOOPS would be better
   → Happens when the optimizer overestimates the intermediate result set
   → Usually due to missing stats or missing index on join key

❌ E-Rows >> A-Rows (estimated much larger than actual)
   → Cardinality misestimate — gather stats with histograms

❌ E-Rows << A-Rows (estimated much smaller than actual)
   → Underestimate — dangerous, can cause nested loops on huge sets

❌ BUFFER SORT or SORT JOIN on large edge tables
   → Missing index causing sort-based join instead of index-based

✅ INDEX RANGE SCAN on edge FK columns → Good, vertex lookup is fast
✅ NESTED LOOPS with INDEX access → Good for selective traversals
✅ HASH JOIN for large fan-out patterns → Acceptable when selectivity is low
```
