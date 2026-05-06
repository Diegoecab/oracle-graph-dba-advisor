#!/usr/bin/env bash
set -euo pipefail

# This demo has two phases:
# 1. Optional lab setup via SQLcl (read/write)
# 2. Detection via Native MCP (read-only, same path the skill uses)
#
# Required for setup phase:
#   SQLCL_CONN_USER / SQLCL_CONN_PASSWORD
#
# Required for MCP phase unless TOKEN_RESPONSE_FILE already exists:
#   ADB_USERNAME / ADB_PASSWORD
#
# Optional:
#   RUN_SETUP=1|0
#   ADB_REGION / ADB_OCID / TOKEN_RESPONSE_FILE

: "${RUN_SETUP:=1}"
: "${SQLCL_CONN_USER:=NEWFRAUD}"
: "${ADB_REGION:=us-ashburn-1}"
: "${ADB_OCID:=ocid1.autonomousdatabase.oc1.iad.anuwcljrrsnyneyaeyjebj6zcga2sl53otbquon56kv75ahopihbhidvpbaa}"
: "${TOKEN_RESPONSE_FILE:=/tmp/newfraud_mcp_token_http.txt}"
: "${SQLCL_BIN:=/mnt/c/DC/Soft/sqlcl-latest/sqlcl/bin/sql}"
: "${ADB_CONNECT_ALIAS:=graadvf260430_high}"
: "${ADB_WALLET_ZIP:=/tmp/graadvf260430_wallet.zip}"
: "${PLAN_INSTABILITY_TAG:=PLAN_INSTABILITY_Q03}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SQL_TEMPLATE_DIR="${REPO_ROOT}/sql-templates/packs/plan-instability"

URL="https://dataaccess.adb.${ADB_REGION}.oraclecloudapps.com/adb/mcp/v1/databases/${ADB_OCID}"
TOKEN_URL="https://dataaccess.adb.${ADB_REGION}.oraclecloudapps.com/adb/auth/v1/databases/${ADB_OCID}/token"

section() {
  printf '\n===== %s =====\n\n' "$1"
}

load_sql() {
  cat "$1"
}

render_sql_template() {
  local template_path="$1"
  local rendered

  rendered="$(cat "$template_path")"
  rendered="${rendered//__PLAN_TAG__/${PLAN_INSTABILITY_TAG}}"

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

run_sqlcl_setup() {
  if [[ -z "${SQLCL_CONN_PASSWORD:-}" ]]; then
    echo "RUN_SETUP=1 requires SQLCL_CONN_PASSWORD." >&2
    exit 1
  fi

  local wrapper
  wrapper="$(mktemp)"

  cat > "$wrapper" <<SQL
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET CLOUDCONFIG ${ADB_WALLET_ZIP}
CONNECT ${SQLCL_CONN_USER}/"${SQLCL_CONN_PASSWORD}"@${ADB_CONNECT_ALIAS}
@"${SCRIPT_DIR}/08_setup_plan_instability_lab.sql"
BEGIN
  RUN_PLAN_INSTABILITY_LAB(p_cycles => 24, p_optimizer_mode => 'FIRST_ROWS_1');
  RUN_PLAN_INSTABILITY_LAB(p_cycles => 24, p_optimizer_mode => 'ALL_ROWS');
END;
/
EXIT
SQL

  "${SQLCL_BIN}" -S /nolog @"${wrapper}"
}

SQL_LAB_SUMMARY="$(load_sql "${SQL_TEMPLATE_DIR}/00-lab-summary.sql")"
SQL_INSTABILITY_SUMMARY="$(render_sql_template "${SQL_TEMPLATE_DIR}/01-instability-summary.sql")"
SQL_PRIMARY_SQLID="$(render_sql_template "${SQL_TEMPLATE_DIR}/02-primary-sqlid.sql")"
SQL_CHILD_DETAIL_TEMPLATE="$(load_sql "${SQL_TEMPLATE_DIR}/03-child-detail.sql")"
SQL_SHARED_CURSOR_TEMPLATE="$(load_sql "${SQL_TEMPLATE_DIR}/04-shared-cursor.sql")"
SQL_PLAN_HASH_TEMPLATE="$(load_sql "${SQL_TEMPLATE_DIR}/05-plan-hash.sql")"

if [[ "$RUN_SETUP" == "1" ]]; then
  section "SQLcl Lab Setup"
  run_sqlcl_setup
fi

section "Lab Object Summary"
call_run_sql "$SQL_LAB_SUMMARY" | jq .

section "Instability Summary"
call_run_sql "$SQL_INSTABILITY_SUMMARY" | jq .

PRIMARY_SQL_ID="$(
  call_run_sql "$SQL_PRIMARY_SQLID" | jq -r '.[0].SQL_ID'
)"

section "Primary SQL_ID"
printf '%s\n' "$PRIMARY_SQL_ID"

SQL_CHILD_DETAIL="$(render_sql_template "${SQL_TEMPLATE_DIR}/03-child-detail.sql" "${PRIMARY_SQL_ID}")"
SQL_SHARED_CURSOR="$(render_sql_template "${SQL_TEMPLATE_DIR}/04-shared-cursor.sql" "${PRIMARY_SQL_ID}")"
SQL_PLAN_HASH="$(render_sql_template "${SQL_TEMPLATE_DIR}/05-plan-hash.sql" "${PRIMARY_SQL_ID}")"

section "Child Cursor Detail"
call_run_sql "$SQL_CHILD_DETAIL" | jq .

section "Non-Shared Reasons"
call_run_sql "$SQL_SHARED_CURSOR" | jq .

section "Plan Hash Summary"
call_run_sql "$SQL_PLAN_HASH" | jq .
