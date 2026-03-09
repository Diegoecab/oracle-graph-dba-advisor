-- ============================================================
-- 00-health-check.sql
-- Oracle Graph DBA Advisor — Database Health Check Templates
-- Run BEFORE graph-specific diagnostics (Phase 0)
--
-- STRATEGY: Try AWR/ASH views first for richer historical data.
-- If access denied (ORA-00942 / ORA-01031 — no Diagnostics Pack
-- license or Always Free tier), fall back to V$ real-time views.
--
-- The advisor should:
--   1. Run HEALTH-00 to detect AWR availability
--   2. If AWR available → use HEALTH-xxA (AWR) variants
--   3. If not → use HEALTH-xxB (V$) variants
-- ============================================================

-- HEALTH-00: Detect AWR availability
-- Run this first. If it returns rows, AWR is accessible.
-- If ORA-00942 or ORA-01031 → set awr_available = FALSE
SELECT COUNT(*) AS awr_accessible
FROM DBA_HIST_SNAPSHOT
WHERE ROWNUM = 1;

-- HEALTH-01: Database type, version, and configuration
-- (Same for both paths — V$ views always available)
SELECT
    (SELECT banner FROM v$version WHERE ROWNUM = 1) AS db_version,
    SYS_CONTEXT('USERENV', 'DB_NAME') AS db_name,
    SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS service_name,
    SYS_CONTEXT('USERENV', 'DATABASE_ROLE') AS db_role,
    (SELECT VALUE FROM V$PARAMETER WHERE NAME = 'cpu_count') AS cpu_count,
    (SELECT VALUE FROM V$PARAMETER WHERE NAME = 'parallel_max_servers') AS max_parallel,
    (SELECT VALUE FROM V$PARAMETER WHERE NAME = 'pga_aggregate_target') AS pga_target,
    (SELECT VALUE FROM V$PARAMETER WHERE NAME = 'sga_target') AS sga_target,
    (SELECT VALUE FROM V$PARAMETER WHERE NAME = 'db_block_size') AS block_size,
    (SELECT VALUE FROM V$PARAMETER WHERE NAME = 'undo_retention') AS undo_retention
FROM DUAL;

-- ============================================================
-- HEALTH-02: CPU utilization and top wait events
-- ============================================================

-- HEALTH-02A: AWR path (last 24h, hourly granularity, P90/P99)
-- Richer: shows trends, percentiles, and peak hours
SELECT
    s.snap_id,
    TO_CHAR(s.end_interval_time, 'YYYY-MM-DD HH24:MI') AS snap_time,
    ROUND(m.average, 2) AS avg_cpu_pct,
    ROUND(m.maxval, 2) AS max_cpu_pct
FROM DBA_HIST_SYSMETRIC_SUMMARY m
JOIN DBA_HIST_SNAPSHOT s ON m.snap_id = s.snap_id AND m.dbid = s.dbid
WHERE m.metric_name = 'Host CPU Utilization (%)'
  AND s.end_interval_time > SYSDATE - 1
ORDER BY s.snap_id;

-- AWR: Top wait events over last 24h (aggregated)
SELECT * FROM (
    SELECT
        event_name,
        wait_class,
        SUM(total_waits_fg) AS total_waits,
        ROUND(SUM(time_waited_micro_fg)/1e6, 2) AS total_time_sec,
        ROUND(AVG(time_waited_micro_fg/GREATEST(total_waits_fg,1))/1000, 2) AS avg_wait_ms
    FROM DBA_HIST_SYSTEM_EVENT
    WHERE snap_id >= (SELECT MAX(snap_id) - 24 FROM DBA_HIST_SNAPSHOT)
      AND wait_class NOT IN ('Idle', 'Other')
    GROUP BY event_name, wait_class
    ORDER BY total_time_sec DESC
) WHERE ROWNUM <= 10;

-- HEALTH-02B: V$ fallback (last hour only, no trends)
SELECT
    METRIC_NAME,
    ROUND(AVG(VALUE), 2) AS avg_value,
    ROUND(MAX(VALUE), 2) AS max_value,
    METRIC_UNIT
FROM V$SYSMETRIC_HISTORY
WHERE METRIC_NAME IN (
    'CPU Usage Per Sec',
    'Host CPU Utilization (%)',
    'Database CPU Time Ratio',
    'Database Wait Time Ratio',
    'Executions Per Sec',
    'Hard Parse Count Per Sec',
    'Buffer Cache Hit Ratio'
)
AND BEGIN_TIME > SYSDATE - 1/24
GROUP BY METRIC_NAME, METRIC_UNIT
ORDER BY METRIC_NAME;

-- V$ fallback: Top wait events (cumulative since startup)
SELECT * FROM (
    SELECT
        event,
        total_waits,
        ROUND(time_waited_micro/1e6, 2) AS time_waited_sec,
        ROUND(average_wait/1000, 2) AS avg_wait_ms,
        wait_class
    FROM V$SYSTEM_EVENT
    WHERE wait_class NOT IN ('Idle', 'Other')
    ORDER BY time_waited_micro DESC
) WHERE ROWNUM <= 10;

-- ============================================================
-- HEALTH-03: I/O throughput and latency
-- ============================================================

-- HEALTH-03A: AWR path (I/O trends over 24h)
SELECT
    TO_CHAR(s.end_interval_time, 'YYYY-MM-DD HH24:MI') AS snap_time,
    ROUND(m.average, 2) AS avg_value,
    ROUND(m.maxval, 2) AS max_value,
    m.metric_name,
    m.metric_unit
FROM DBA_HIST_SYSMETRIC_SUMMARY m
JOIN DBA_HIST_SNAPSHOT s ON m.snap_id = s.snap_id AND m.dbid = s.dbid
WHERE m.metric_name IN (
    'Physical Reads Per Sec',
    'Physical Writes Per Sec',
    'I/O Megabytes per Second',
    'Average Synchronous Single-Block Read Latency'
)
AND s.end_interval_time > SYSDATE - 1
ORDER BY m.metric_name, s.snap_id;

-- HEALTH-03B: V$ fallback (last hour)
SELECT
    METRIC_NAME,
    ROUND(AVG(VALUE), 2) AS avg_value,
    ROUND(MAX(VALUE), 2) AS max_value,
    METRIC_UNIT
FROM V$SYSMETRIC_HISTORY
WHERE METRIC_NAME IN (
    'Physical Reads Per Sec',
    'Physical Writes Per Sec',
    'Physical Read Total Bytes Per Sec',
    'I/O Megabytes per Second',
    'Average Synchronous Single-Block Read Latency'
)
AND BEGIN_TIME > SYSDATE - 1/24
GROUP BY METRIC_NAME, METRIC_UNIT
ORDER BY METRIC_NAME;

-- ============================================================
-- HEALTH-04: Memory utilization (SGA + PGA)
-- (Same for both paths — V$ views are sufficient and always available)
-- ============================================================

SELECT
    'SGA' AS area,
    ROUND(SUM(bytes)/1024/1024, 0) AS used_mb,
    (SELECT ROUND(VALUE/1024/1024, 0) FROM V$PARAMETER WHERE NAME = 'sga_target') AS target_mb
FROM V$SGASTAT
WHERE pool IS NOT NULL
UNION ALL
SELECT
    'PGA',
    ROUND(VALUE/1024/1024, 0),
    (SELECT ROUND(VALUE/1024/1024, 0) FROM V$PARAMETER WHERE NAME = 'pga_aggregate_target')
FROM V$PGASTAT
WHERE NAME = 'total PGA allocated';

-- PGA over-allocation detail (graph hash joins are the main cause)
SELECT NAME, VALUE
FROM V$PGASTAT
WHERE NAME IN (
    'total PGA allocated',
    'total PGA used for auto workareas',
    'over allocation count',
    'cache hit percentage',
    'total freeable PGA memory'
);

-- AWR bonus: PGA usage trend over 24h (only if AWR available)
-- HEALTH-04A: AWR PGA trend
SELECT
    TO_CHAR(s.end_interval_time, 'HH24:MI') AS snap_time,
    ROUND(p.value/1024/1024, 0) AS pga_allocated_mb
FROM DBA_HIST_PGASTAT p
JOIN DBA_HIST_SNAPSHOT s ON p.snap_id = s.snap_id AND p.dbid = s.dbid
WHERE p.name = 'total PGA allocated'
  AND s.end_interval_time > SYSDATE - 1
ORDER BY s.snap_id;

-- ============================================================
-- HEALTH-05: Tablespace usage
-- (Same for both paths)
-- ============================================================

SELECT
    tablespace_name,
    ROUND(used_space * 8192 / 1024 / 1024, 0) AS used_mb,
    ROUND(tablespace_size * 8192 / 1024 / 1024, 0) AS total_mb,
    ROUND(used_percent, 1) AS pct_used,
    CASE
        WHEN used_percent > 95 THEN 'CRITICAL'
        WHEN used_percent > 85 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM DBA_TABLESPACE_USAGE_METRICS
ORDER BY used_percent DESC;

-- Temp tablespace (critical for graph UNION ALL sorts)
SELECT
    tablespace_name,
    ROUND(tablespace_size / 1024 / 1024, 0) AS total_mb,
    ROUND(allocated_space / 1024 / 1024, 0) AS allocated_mb,
    ROUND(free_space / 1024 / 1024, 0) AS free_mb
FROM DBA_TEMP_FREE_SPACE;

-- ============================================================
-- HEALTH-06: ADB-specific + session pressure
-- ============================================================

-- Active sessions vs CPU capacity (works on all Oracle)
SELECT
    (SELECT COUNT(*) FROM V$SESSION WHERE STATUS = 'ACTIVE' AND TYPE = 'USER') AS active_sessions,
    (SELECT VALUE FROM V$PARAMETER WHERE NAME = 'cpu_count') AS cpu_count,
    CASE
        WHEN (SELECT COUNT(*) FROM V$SESSION WHERE STATUS = 'ACTIVE' AND TYPE = 'USER') >
             (SELECT VALUE FROM V$PARAMETER WHERE NAME = 'cpu_count') * 2
        THEN 'OVERSUBSCRIBED'
        WHEN (SELECT COUNT(*) FROM V$SESSION WHERE STATUS = 'ACTIVE' AND TYPE = 'USER') >
             (SELECT VALUE FROM V$PARAMETER WHERE NAME = 'cpu_count')
        THEN 'SATURATED'
        ELSE 'OK'
    END AS session_pressure
FROM DUAL;

-- AWR bonus: ASH analysis for I/O vs CPU wait breakdown (last hour)
-- HEALTH-06A: ASH active session breakdown
SELECT
    wait_class,
    COUNT(*) AS sample_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_db_time
FROM DBA_HIST_ACTIVE_SESS_HISTORY
WHERE sample_time > SYSDATE - 1/24
GROUP BY wait_class
ORDER BY sample_count DESC;
