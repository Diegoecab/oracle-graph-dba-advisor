#!/usr/bin/env bash
set -euo pipefail

# Optional runtime env vars:
#   ADB_USERNAME / ADB_PASSWORD  -> fetch a fresh bearer token automatically
#   TOKEN_RESPONSE_FILE          -> cache file for the token payload
#   ADB_REGION / ADB_OCID        -> target database

: "${ADB_REGION:=us-ashburn-1}"
: "${ADB_OCID:=ocid1.autonomousdatabase.oc1.iad.anuwcljrrsnyneyaeyjebj6zcga2sl53otbquon56kv75ahopihbhidvpbaa}"
: "${TOKEN_RESPONSE_FILE:=/tmp/newfraud_mcp_token_http.txt}"

URL="https://dataaccess.adb.${ADB_REGION}.oraclecloudapps.com/adb/mcp/v1/databases/${ADB_OCID}"
TOKEN_URL="https://dataaccess.adb.${ADB_REGION}.oraclecloudapps.com/adb/auth/v1/databases/${ADB_OCID}/token"

section() {
  printf '\n===== %s =====\n\n' "$1"
}

get_token() {
  if [[ -n "${ADB_USERNAME:-}" && -n "${ADB_PASSWORD:-}" ]]; then
    curl -sS --location "$TOKEN_URL" \
      --header 'Content-Type: application/json' \
      --header 'Accept: application/json' \
      --data "$(jq -cn --arg u "$ADB_USERNAME" --arg p "$ADB_PASSWORD" '{grant_type:"password",username:$u,password:$p}')" \
      > "$TOKEN_RESPONSE_FILE"
  fi

  if [[ ! -f "$TOKEN_RESPONSE_FILE" ]]; then
    echo "Token file not found: $TOKEN_RESPONSE_FILE" >&2
    echo "Set ADB_USERNAME and ADB_PASSWORD, or generate the token first." >&2
    exit 1
  fi

  tail -n 1 "$TOKEN_RESPONSE_FILE" | jq -r '.access_token'
}

call_run_sql() {
  local query="$1"
  local token body resp_file hdr_file

  token="$(get_token)"
  body="$(
    jq -cn \
      --arg q "$query" \
      '{
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "RUN_SQL",
          arguments: {
            QUERY: $q,
            OFFSET: 0,
            LIMIT: 200
          }
        }
      }'
  )"

  resp_file="$(mktemp)"
  hdr_file="$(mktemp)"

  curl -sS --location "$URL" \
    --header "Authorization: Bearer ${token}" \
    --header 'Content-Type: application/json' \
    --header 'Accept: application/json, text/event-stream' \
    --data "$body" \
    -D "$hdr_file" \
    -o "$resp_file"

  python3 - "$resp_file" <<'PY'
import json
import sys
from pathlib import Path

resp = Path(sys.argv[1]).read_text()
payload = None
for line in resp.splitlines():
    if line.startswith("data: "):
        payload = json.loads(line[6:])
        break

if payload is None:
    raise SystemExit(resp)

result = payload.get("result", {})
content = result.get("content", [])
text = content[0].get("text", "") if content else ""

if result.get("isError"):
    print(text)
    raise SystemExit(2)

print(text)
PY
}

pretty_sql() {
  local title="$1"
  local query="$2"

  section "$title"
  call_run_sql "$query" | jq .
}

SQL_CONTEXT="$(cat <<'SQL'
SELECT
  USER AS user_col,
  SYS_CONTEXT('USERENV','SESSION_USER') AS session_user,
  SYS_CONTEXT('USERENV','CURRENT_USER') AS current_user,
  SYS_CONTEXT('USERENV','CURRENT_SCHEMA') AS current_schema,
  SYS_CONTEXT('USERENV','DB_NAME') AS db_name,
  SYS_CONTEXT('USERENV','SERVICE_NAME') AS service_name
FROM dual
SQL
)"

SQL_HEALTH="$(cat <<'SQL'
SELECT
  (SELECT banner FROM v$version WHERE ROWNUM = 1) AS db_version,
  (SELECT value FROM v$parameter WHERE name = 'cpu_count') AS cpu_count,
  (SELECT value FROM v$parameter WHERE name = 'undo_retention') AS undo_retention
FROM dual
SQL
)"

SQL_TABLESPACE="$(cat <<'SQL'
SELECT
  tablespace_name,
  ROUND(used_percent, 1) AS pct_used,
  CASE
    WHEN used_percent > 95 THEN 'CRITICAL'
    WHEN used_percent > 85 THEN 'WARNING'
    ELSE 'OK'
  END AS status
FROM dba_tablespace_usage_metrics
ORDER BY used_percent DESC
SQL
)"

SQL_GRAPH_SUMMARY="$(cat <<'SQL'
SELECT
  pg.graph_name,
  pg.graph_mode,
  (SELECT COUNT(DISTINCT e.object_name)
   FROM user_pg_elements e
   WHERE e.graph_name = pg.graph_name
     AND UPPER(e.element_kind) = 'VERTEX') AS vertex_table_count,
  (SELECT COUNT(DISTINCT e.object_name)
   FROM user_pg_elements e
   WHERE e.graph_name = pg.graph_name
     AND UPPER(e.element_kind) = 'EDGE') AS edge_table_count
FROM user_property_graphs pg
ORDER BY pg.graph_name
SQL
)"

SQL_EDGE_COUNTS="$(cat <<'SQL'
WITH edge_elements AS (
  SELECT DISTINCT
    graph_name,
    element_name,
    object_name AS table_name
  FROM user_pg_elements
  WHERE UPPER(element_kind) = 'EDGE'
)
SELECT
  ee.graph_name,
  ee.element_name AS edge_name,
  ee.table_name,
  t.num_rows,
  t.last_analyzed
FROM edge_elements ee
JOIN user_tables t
  ON ee.table_name = t.table_name
ORDER BY t.num_rows DESC, ee.table_name
SQL
)"

SQL_INDEX_GAPS="$(cat <<'SQL'
WITH edge_fk_cols AS (
  SELECT DISTINCT
      r.graph_name,
      r.edge_tab_name AS table_name,
      r.edge_col_name AS fk_column,
      CASE
          WHEN UPPER(r.edge_end) LIKE '%SOURCE%' THEN 'SOURCE_FK'
          WHEN UPPER(r.edge_end) LIKE '%DEST%' THEN 'DESTINATION_FK'
          ELSE r.edge_end
      END AS fk_type,
      r.vertex_tab_name AS references_table,
      r.vertex_col_name AS references_column
  FROM user_pg_edge_relationships r
),
indexed_cols AS (
  SELECT DISTINCT
      ic.table_name,
      ic.column_name
  FROM user_ind_columns ic
  WHERE ic.column_position = 1
)
SELECT
  efk.graph_name,
  efk.table_name,
  efk.fk_column,
  efk.fk_type,
  efk.references_table,
  efk.references_column,
  CASE
    WHEN ix.column_name IS NOT NULL THEN 'INDEXED'
    ELSE 'MISSING LEADING INDEX'
  END AS index_status
FROM edge_fk_cols efk
LEFT JOIN indexed_cols ix
  ON efk.table_name = ix.table_name
 AND efk.fk_column = ix.column_name
ORDER BY efk.table_name, efk.fk_type
SQL
)"

SQL_TOP_WORKLOAD="$(cat <<'SQL'
WITH tagged_sql AS (
  SELECT
    sql_id,
    plan_hash_value,
    executions,
    elapsed_time,
    buffer_gets,
    disk_reads,
    rows_processed,
    last_active_time,
    CASE
      WHEN UPPER(sql_text) LIKE '%DEMO_FRAUD_Q05%' THEN 'DEMO_FRAUD_Q05'
      WHEN UPPER(sql_text) LIKE '%DEMO_FRAUD_Q04%' THEN 'DEMO_FRAUD_Q04'
      WHEN UPPER(sql_text) LIKE '%DEMO_FRAUD_Q06%' THEN 'DEMO_FRAUD_Q06'
      WHEN UPPER(sql_text) LIKE '%DEMO_FRAUD_Q02%' THEN 'DEMO_FRAUD_Q02'
      WHEN UPPER(sql_text) LIKE '%TXFRAUD_Q%' THEN 'TXFRAUD'
      ELSE 'OTHER'
    END AS workload_tag,
    SUBSTR(REPLACE(REPLACE(sql_text, CHR(10), ' '), CHR(13), ' '), 1, 180) AS sql_preview
  FROM v$sql
  WHERE parsing_schema_name = SYS_CONTEXT('USERENV','CURRENT_SCHEMA')
    AND (
      UPPER(sql_text) LIKE '%DEMO_FRAUD_Q%'
      OR UPPER(sql_text) LIKE '%TXFRAUD_Q%'
    )
    AND UPPER(sql_text) NOT LIKE '%FROM V$SQL%'
)
SELECT
  workload_tag,
  sql_id,
  plan_hash_value,
  executions,
  ROUND(elapsed_time / 1e6, 2) AS total_elapsed_sec,
  ROUND(elapsed_time / NULLIF(executions, 0) / 1e6, 4) AS avg_elapsed_sec,
  buffer_gets,
  ROUND(buffer_gets / NULLIF(executions, 0)) AS avg_buffer_gets,
  disk_reads,
  rows_processed,
  last_active_time,
  sql_preview
FROM tagged_sql
ORDER BY elapsed_time DESC, last_active_time DESC
FETCH FIRST 12 ROWS ONLY
SQL
)"

SQL_PRIMARY_SQLID="$(cat <<'SQL'
SELECT sql_id
FROM (
  SELECT
    sql_id,
    elapsed_time,
    last_active_time
  FROM v$sql
  WHERE parsing_schema_name = SYS_CONTEXT('USERENV','CURRENT_SCHEMA')
    AND (
      UPPER(sql_text) LIKE '%DEMO_FRAUD_Q05%'
      OR UPPER(sql_text) LIKE '%DEMO_FRAUD_Q04%'
      OR UPPER(sql_text) LIKE '%DEMO_FRAUD_Q06%'
      OR UPPER(sql_text) LIKE '%DEMO_FRAUD_Q02%'
    )
    AND UPPER(sql_text) NOT LIKE '%FROM V$SQL%'
  ORDER BY elapsed_time DESC, last_active_time DESC
)
WHERE ROWNUM = 1
SQL
)"

section "MCP Native Context"
call_run_sql "$SQL_CONTEXT" | jq .

section "Health Check"
call_run_sql "$SQL_HEALTH" | jq .

section "Tablespace"
call_run_sql "$SQL_TABLESPACE" | jq .

section "Graph Summary"
call_run_sql "$SQL_GRAPH_SUMMARY" | jq .

section "Edge Volumes"
call_run_sql "$SQL_EDGE_COUNTS" | jq .

section "Index Gaps"
call_run_sql "$SQL_INDEX_GAPS" | jq .

section "Top Workload"
TOP_WORKLOAD_JSON="$(call_run_sql "$SQL_TOP_WORKLOAD")"
printf '%s\n' "$TOP_WORKLOAD_JSON" | jq .

PRIMARY_SQL_ID="$(
  call_run_sql "$SQL_PRIMARY_SQLID" | jq -r '.[0].SQL_ID'
)"

section "Primary SQL_ID"
printf '%s\n' "$PRIMARY_SQL_ID"

SQL_PLAN="$(cat <<'SQL'
SELECT plan_table_output
FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
  sql_id          => '__SQL_ID__',
  cursor_child_no => NULL,
  format          => 'ALLSTATS LAST +COST +BYTES +PREDICATE +ALIAS'
))
SQL
)"
SQL_PLAN="${SQL_PLAN/__SQL_ID__/${PRIMARY_SQL_ID}}"

SQL_PLAN_STEPS="$(cat <<'SQL'
SELECT
  p.id AS step_id,
  LPAD(' ', 2 * p.depth) || p.operation || ' ' || NVL(p.options, '') AS operation,
  p.object_name,
  p.cardinality AS estimated_rows,
  ps.last_output_rows AS actual_rows,
  ps.last_cr_buffer_gets + ps.last_cu_buffer_gets AS buffer_gets,
  ps.last_disk_reads AS disk_reads,
  ROUND(ps.last_elapsed_time / 1e6, 4) AS elapsed_sec,
  p.access_predicates,
  p.filter_predicates
FROM v$sql_plan p
LEFT JOIN v$sql_plan_statistics_all ps
  ON p.sql_id = ps.sql_id
 AND p.child_number = ps.child_number
 AND p.id = ps.id
WHERE p.sql_id = '__SQL_ID__'
ORDER BY (ps.last_cr_buffer_gets + ps.last_cu_buffer_gets) DESC NULLS LAST, p.id
SQL
)"
SQL_PLAN_STEPS="${SQL_PLAN_STEPS/__SQL_ID__/${PRIMARY_SQL_ID}}"

section "Execution Plan"
call_run_sql "$SQL_PLAN" | jq .

section "Plan Steps"
call_run_sql "$SQL_PLAN_STEPS" | jq .
