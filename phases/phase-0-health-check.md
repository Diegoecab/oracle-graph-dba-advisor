# Phase 0: DATABASE HEALTH CHECK — Is the database healthy enough for this workload?

**Goal**: Assess overall database resource utilization before graph-specific analysis. If the database is resource-constrained, no amount of index tuning will help — the user needs to address capacity first.

**Actions**:
1. Detect AWR availability → `HEALTH-00` (try DBA_HIST_SNAPSHOT; if denied, fall back to V$)
2. Check database type and configuration → `HEALTH-01`
3. Check CPU and wait event profile → `HEALTH-02A` (AWR: 24h trend) or `HEALTH-02B` (V$: last hour)
4. Check I/O throughput and contention → `HEALTH-03A` (AWR) or `HEALTH-03B` (V$)
5. Check memory (SGA/PGA) utilization → `HEALTH-04` + `HEALTH-04A` (AWR PGA trend if available)
6. Check tablespace usage and auto-extend → `HEALTH-05`
7. Check ADB-specific metrics + session pressure → `HEALTH-06` + `HEALTH-06A` (ASH if available)
8. Check Auto Indexing status (ADB only) → `HEALTH-07`, `HEALTH-08`, `HEALTH-09`

**AWR/ASH strategy**: Always try AWR views first. If ORA-00942 or ORA-01031, fall back to V$ views silently. When AWR is available, report historical trends (24h) and percentiles — this is significantly more valuable than a point-in-time snapshot. When not available, note in the report: "Using real-time metrics only (last hour). For richer analysis, enable AWR access."

**What you're looking for and what to recommend**:

| Finding | Severity | Recommendation |
|---------|----------|----------------|
| CPU utilization avg > 80% | Critical | ADB: verify auto-scaling is enabled and ECPU max is sufficient. Non-ADB: add CPUs or optimize top SQL |
| CPU utilization avg > 60% | Warning | Flag before adding indexes (indexes help reads but add write overhead) |
| I/O wait > 30% of DB time | Critical | ADB: check storage IOPS tier. Non-ADB: check ASM disk groups, consider faster storage |
| Buffer cache hit ratio < 90% | Warning | PGA/SGA may be undersized. Graph queries are join-heavy and need cache. Non-ADB: increase DB_CACHE_SIZE |
| PGA target exceeded (over-allocation) | Critical | Hash joins from graph queries spill to disk when PGA is too small. Non-ADB: increase PGA_AGGREGATE_TARGET |
| Tablespace > 85% full | Warning | Adding indexes will grow tablespace. Check auto-extend or add datafiles |
| Tablespace > 95% full | Critical | Block index creation until space is addressed |
| ADB auto-scaling disabled | Warning | Recommend enabling to handle graph workload spikes |
| ADB ECPU count < 4 | Warning | Graph queries with PARALLEL hints won't benefit. Complex multi-hop patterns may be slow |
| Undo retention too low + graph queries | Warning | Long-running graph queries may get ORA-01555. Check undo_retention vs longest graph query elapsed |
| Temp tablespace < 2x largest sort | Critical | Variable-length path queries generate UNION ALL sorts. Temp must be large enough |
| Active sessions >> CPU count | Warning | Concurrency contention. Graph queries with full scans hold resources longer |
| Auto Indexing disabled on ADB | Warning | Ask the user: "Auto Indexing is disabled. I recommend enabling it — it will create indexes automatically based on your workload. Want me to enable it? Command: `EXEC DBMS_AUTO_INDEX.CONFIGURE('AUTO_INDEX_MODE', 'IMPLEMENT')`" — NEVER enable without explicit user confirmation |
| Auto Indexing in REPORT ONLY mode | Info | Ask the user if they want to switch to IMPLEMENT mode for graph workloads — explain the trade-off (automatic index creation vs. manual control) |
| Auto Indexing enabled, no indexes on graph tables | Info | Normal if graph workload is new — Auto Indexing hasn't observed enough queries yet. The advisor's proactive recommendations fill this gap |
| Auto Indexing created indexes on edge FK columns | OK | Good — verify the index type matches what the advisor would recommend |
| Auto Indexing created single-column index where composite would be better | Warning | The advisor can complement this — Auto Indexing doesn't understand graph semantics |
| > 5 total indexes on an edge table | Warning | Over-indexing risk — cumulative DML overhead. Review which indexes are actually used (HEALTH-10a) |
| > 7 total indexes on an edge table | Critical | Over-indexed — INSERT/UPDATE performance likely degraded. Drop unused or redundant auto indexes |
| Invisible auto indexes consuming > 100MB total | Warning | Storage waste — consider dropping INVISIBLE auto indexes older than 30 days not promoted (HEALTH-10b) |
| Auto Indexing execution consuming > 30 min/day | Warning | Resource competition — especially on low-ECPU ADB. Consider narrowing scope or scheduling outside peak hours (HEALTH-10c) |

**How to present findings**:

```
DATABASE HEALTH ASSESSMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━
Environment: [connection_name]
Database:    [db_name] | [version]
Type:        [ADB-S / ADB-D / Base DB / Free]
ECPUs/CPUs:  [count] | Auto-scale: [ON/OFF]
Data source: [AWR (last 24h) / V$ real-time (last hour)]

| Resource        | Current     | Threshold | Status  | Action                          |
|-----------------|-------------|-----------|---------|-------------------------------- |
| CPU utilization | 72% avg     | <80%      | Warning | Monitor; may spike under graph  |
| I/O wait        | 12% db_time | <30%      | OK      |                                 |
| Buffer cache    | 94% hit     | >90%      | OK      |                                 |
| PGA usage       | 1.8GB/2GB   | <90%      | Warning | Graph hash joins may spill      |
| Tablespace DATA | 78%         | <85%      | OK      |                                 |
| Temp tablespace | 500MB free  | >1GB      | Warning | Increase before {n,m} queries   |
| ADB auto-scale  | OFF         | ON        | Warning | Enable for workload spikes      |

Overall: Proceed with graph analysis (2 warnings to address)
— OR —
Overall: Address resource constraints before optimizing graph queries
```

**Decision**: If any Critical finding exists, present the database health recommendations FIRST, before proceeding to Phase 1. The user should fix capacity issues before the advisor spends time on index analysis.
