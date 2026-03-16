# Phase 1: DISCOVERY — Understand the Graph Topology

**Goal**: Map the property graphs, their underlying tables, volumes, and existing indexes.

**Actions**:
1. List all property graphs → `DISCOVERY-01`
2. Get vertex/edge table mappings with row counts → `DISCOVERY-02`
3. List all existing indexes on graph tables → `DISCOVERY-03`
4. Check column statistics (selectivity) for key columns → `DISCOVERY-04`
5. Verify optimizer stats are fresh → `DISCOVERY-05`
6. Check for auto-created indexes on graph tables → `HEALTH-09`

**What you're looking for**:
- Edge tables with high row counts (>100K) — these are your optimization targets
- Edge FK columns (`source_key`, `destination_key`) that lack indexes — this is the #1 most common gap
- Edge property columns used in WHERE clauses that have low cardinality or high selectivity
- Stale stats (last_analyzed > 7 days ago) — recommend gathering before proceeding
- Auto indexes on edge FK columns (source_key, destination_key) — if present, you don't need to recommend these
- Auto indexes on edge property columns — verify they're the right ones for graph queries
- Missing auto indexes — indicates Auto Indexing hasn't observed enough graph workload yet
- INVISIBLE auto indexes — Auto Indexing created them but decided the benefit was marginal. Check if graph-specific workload would change that assessment
