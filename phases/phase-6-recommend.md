# Phase 6: RECOMMEND — Generate Actionable DDL (report only — do not execute)

**Goal**: Produce CREATE INDEX statements with full justification. Present them as **proposed DDL scripts** for the user to review. Do not execute any DDL unless the user explicitly requests it.

**Recommendation Template**:
```
RECOMMENDATION #N
━━━━━━━━━━━━━━━━
Target:     [table_name].[column(s)]
Index DDL:  CREATE INDEX idx_name ON table(col1, col2) ...;
Pattern:    [which graph pattern this helps]
Queries:    [list of SQL_IDs affected]
Impact:     [estimated elapsed time + CPU reduction, e.g., "Avg elapsed 5.3 ms → 0.4 ms (92% reduction)"]
Why:        [1-2 sentence explanation in plain language]
Rollback:   ALTER INDEX idx_name INVISIBLE;
Risk:       [DML overhead estimate on INSERT-heavy edge tables]
```

**Auto Indexing Deduplication**:

Before recommending an index, check if Auto Indexing already created one on the same column(s):

1. If Auto Indexing created the EXACT same index → Don't recommend. Acknowledge: "Auto Indexing already identified and created this index."
2. If Auto Indexing created a single-column index but you recommend a composite → Recommend the composite as a REPLACEMENT. Explain: "Auto Indexing created an index on (column) alone. I recommend replacing it with (col1, col2) which covers both the filter and the edge join in a single index scan."
3. If Auto Indexing created an index on a column the advisor wouldn't recommend → Flag it. "Auto Indexing created an index on transfers(channel). This has low selectivity (4 values) and adds write overhead. Consider disabling it for this table."
4. If Auto Indexing is enabled but hasn't created graph indexes yet → Explain: "Auto Indexing needs real workload to learn from. My recommendations are proactive — based on graph structure analysis. Once your workload runs, Auto Indexing may create additional indexes. The two approaches complement each other."

**Index Naming Convention**:
- Auto Indexing names: `SYS_AI_xxxxxxx` (system-generated)
- Advisor names: `idx_{table}_{columns}` (descriptive)
- If both exist on the same column, prefer keeping the advisor's (descriptive name) and dropping the auto one — unless the auto index has workload-validated statistics
