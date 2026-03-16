# Phase 5: SIMULATE — Test Index Impact (OPTIONAL — requires user approval)

**Goal**: Estimate the plan change if an index existed. This phase creates invisible indexes and is **not executed unless the user explicitly approves**.

**Before proceeding**: Present the proposed indexes from Phase 4 and ask the user: *"Would you like me to create invisible indexes to simulate and validate the expected improvements?"* Only proceed if the user confirms.

**Actions**:
1. Use optimizer hints to simulate index access → `SIMULATE-01`
2. Compare **actual elapsed time** and plan structure → Manual comparison (never evaluate by optimizer cost alone — cost is an internal estimate that can be misleading; always measure real execution time)
3. For high-confidence recommendations, create invisible index → `SIMULATE-02`
4. Re-explain with invisible index → `SIMULATE-03`
5. Measure actual runtime improvement → `SIMULATE-04`

**Invisible Index Testing Protocol**:

Invisible indexes are **ignored by the optimizer by default**. To test them:

```sql
-- Enable invisible indexes for the current session ONLY (no impact on other users)
ALTER SESSION SET OPTIMIZER_USE_INVISIBLE_INDEXES = TRUE;

-- Now run the workload — optimizer will consider invisible indexes
-- Compare actual elapsed time and plans vs. the baseline without this setting
```

**Lock/Contention behavior when creating indexes**:
- `CREATE INDEX ... INVISIBLE` takes a **DML lock** on the table during creation (blocks INSERTs/UPDATEs/DELETEs) — same as a visible index.
- To minimize contention on production systems, use `CREATE INDEX ... INVISIBLE ONLINE` — only acquires a brief lock at start and end, allowing concurrent DML during the build.
- **After creation**, invisible indexes are **maintained on every DML** (write overhead exists even though the optimizer doesn't use them). Factor this cost into recommendations for INSERT-heavy edge tables.
- **Safe testing workflow**: Create INVISIBLE → test with session parameter → if beneficial, `ALTER INDEX idx VISIBLE` → if not, `DROP INDEX idx`.
