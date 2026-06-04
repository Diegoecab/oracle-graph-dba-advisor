#!/usr/bin/env bash
set -euo pipefail

: "${ADB_REGION:=sa-saopaulo-1}"
: "${ADB_OCID:?Set ADB_OCID to the target Autonomous Database OCID}"
: "${TOKEN_RESPONSE_FILE:=/tmp/downer_mcp_token_http.json}"
: "${PLAN_TAG:=DOWNER_PI_Q01}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SQL_TEMPLATE_DIR="${REPO_ROOT}/sql-templates/packs/plan-instability"

URL="https://dataaccess.adb.${ADB_REGION}.oraclecloudapps.com/adb/mcp/v1/databases/${ADB_OCID}"
TOKEN_URL="https://dataaccess.adb.${ADB_REGION}.oraclecloudapps.com/adb/auth/v1/databases/${ADB_OCID}/token"

section() {
  printf '\n===== %s =====\n\n' "$1"
}

render_sql_template() {
  local template_path="$1"
  local rendered
  rendered="$(cat "$template_path")"
  rendered="${rendered//__PLAN_TAG__/${PLAN_TAG}}"
  if [[ $# -ge 2 ]]; then
    rendered="${rendered//__SQL_ID__/$2}"
  fi
  printf '%s\n' "$rendered"
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
    echo "Set ADB_USERNAME and ADB_PASSWORD for GRAPH_DIAG_USER, or generate the token first." >&2
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
            LIMIT: 300
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

SQL_LAB_SUMMARY="$(render_sql_template "${SQL_TEMPLATE_DIR}/00-lab-summary.sql")"
SQL_INSTABILITY_SUMMARY="$(render_sql_template "${SQL_TEMPLATE_DIR}/01-instability-summary.sql")"
SQL_PRIMARY_SQLID="$(render_sql_template "${SQL_TEMPLATE_DIR}/02-primary-sqlid.sql")"

section "Lab Object Summary"
call_run_sql "$SQL_LAB_SUMMARY" | jq .

section "Instability Summary"
call_run_sql "$SQL_INSTABILITY_SUMMARY" | jq .

PRIMARY_SQL_ID="$(
  call_run_sql "$SQL_PRIMARY_SQLID" | jq -r '.[0].SQL_ID'
)"

if [[ -z "$PRIMARY_SQL_ID" || "$PRIMARY_SQL_ID" == "null" ]]; then
  echo "No primary SQL_ID found for tag ${PLAN_TAG}. Run workload/downer/23_run_plan_instability_workload.sql first." >&2
  exit 2
fi

section "Primary SQL_ID"
printf '%s\n' "$PRIMARY_SQL_ID"

SQL_CHILD_DETAIL="$(render_sql_template "${SQL_TEMPLATE_DIR}/03-child-detail.sql" "${PRIMARY_SQL_ID}")"
SQL_SHARED_CURSOR="$(render_sql_template "${SQL_TEMPLATE_DIR}/04-shared-cursor.sql" "${PRIMARY_SQL_ID}")"
SQL_PLAN_HASH="$(render_sql_template "${SQL_TEMPLATE_DIR}/05-plan-hash.sql" "${PRIMARY_SQL_ID}")"
SQL_DEVIATION="$(render_sql_template "${SQL_TEMPLATE_DIR}/06-elapsed-deviation.sql" "${PRIMARY_SQL_ID}")"

section "Child Cursor Detail"
call_run_sql "$SQL_CHILD_DETAIL" | jq .

section "Non-Shared Reasons"
call_run_sql "$SQL_SHARED_CURSOR" | jq .

section "Plan Hash Summary"
call_run_sql "$SQL_PLAN_HASH" | jq .

section "Elapsed Deviation"
call_run_sql "$SQL_DEVIATION" | jq .
