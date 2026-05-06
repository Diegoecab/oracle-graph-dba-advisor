#!/usr/bin/env bash
set -euo pipefail

# Optional:
#   RUN_INSTALL=1|0
#   SQLCL_CONN_USER / SQLCL_CONN_PASSWORD
#   ADB_USERNAME / ADB_PASSWORD
#   TOKEN_RESPONSE_FILE / ADB_REGION / ADB_OCID
#   TOP_SQL_FILTER / LIMIT_ROWS / HOURS_BACK

: "${RUN_INSTALL:=0}"
: "${SQLCL_CONN_USER:=NEWFRAUD}"
: "${ADB_REGION:=us-ashburn-1}"
: "${ADB_OCID:=ocid1.autonomousdatabase.oc1.iad.anuwcljrrsnyneyaeyjebj6zcga2sl53otbquon56kv75ahopihbhidvpbaa}"
: "${TOKEN_RESPONSE_FILE:=/tmp/newfraud_mcp_token_http.txt}"
: "${SQLCL_BIN:=/mnt/c/DC/Soft/sqlcl-latest/sqlcl/bin/sql}"
: "${ADB_CONNECT_ALIAS:=graadvf260430_high}"
: "${ADB_WALLET_ZIP:=/tmp/graadvf260430_wallet.zip}"
: "${TOP_SQL_FILTER:=}"
: "${LIMIT_ROWS:=10}"
: "${HOURS_BACK:=4}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_SQL="${REPO_ROOT}/clients/adb-performance-diagnostic-tool-packs-poc.sql"

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

call_tool() {
  local tool_name="$1"
  local args_json="$2"
  local token body resp_file hdr_file

  token="$(get_token)"
  body="$(
    jq -cn \
      --arg name "$tool_name" \
      --argjson args "$args_json" \
      '{
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: $name,
          arguments: $args
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

run_install() {
  if [[ -z "${SQLCL_CONN_PASSWORD:-}" ]]; then
    echo "RUN_INSTALL=1 requires SQLCL_CONN_PASSWORD." >&2
    exit 1
  fi

  local wrapper
  wrapper="$(mktemp)"

  cat > "$wrapper" <<SQL
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET CLOUDCONFIG ${ADB_WALLET_ZIP}
CONNECT ${SQLCL_CONN_USER}/"${SQLCL_CONN_PASSWORD}"@${ADB_CONNECT_ALIAS}
@"${INSTALL_SQL}"
EXIT
SQL

  "${SQLCL_BIN}" -S /nolog @"${wrapper}"
}

if [[ "$RUN_INSTALL" == "1" ]]; then
  section "Install Additional Tool Packs"
  run_install
fi

TOP_SQL_ARGS="$(jq -cn --arg filter "$TOP_SQL_FILTER" --argjson hrs "$HOURS_BACK" --argjson lim "$LIMIT_ROWS" '{sql_text_filter: $filter, hours_back: $hrs, limit_rows: $lim}')"
LIMIT_ARGS="$(jq -cn --argjson lim "$LIMIT_ROWS" '{limit_rows: $lim}')"
ASH_ARGS="$(jq -cn --arg filter "$TOP_SQL_FILTER" --argjson hrs "$HOURS_BACK" --argjson lim "$LIMIT_ROWS" '{sql_text_filter: $filter, hours_back: $hrs, limit_rows: $lim}')"

section "Tool: GA_TOP_SQL_SUMMARY"
TOP_SQL_JSON="$(call_tool "GA_TOP_SQL_SUMMARY" "$TOP_SQL_ARGS")"
if [[ "$(printf '%s\n' "$TOP_SQL_JSON" | jq 'length')" == "0" && -n "${TOP_SQL_FILTER}" ]]; then
  printf 'No rows matched filter "%s". Re-running without sql_text_filter.\n' "$TOP_SQL_FILTER"
  TOP_SQL_ARGS="$(jq -cn --argjson lim "$LIMIT_ROWS" '{limit_rows: $lim}')"
  TOP_SQL_JSON="$(call_tool "GA_TOP_SQL_SUMMARY" "$TOP_SQL_ARGS")"
fi
printf '%s\n' "$TOP_SQL_JSON" | jq .

PRIMARY_SQL_ID="$(printf '%s\n' "$TOP_SQL_JSON" | jq -r 'if length > 0 then .[0].SQL_ID else "" end')"

section "Primary SQL_ID"
if [[ -n "$PRIMARY_SQL_ID" ]]; then
  printf '%s\n' "$PRIMARY_SQL_ID"
else
  printf 'No candidate SQL_ID found.\n'
fi

DETAIL_ARGS="$(jq -cn --arg sql_id "$PRIMARY_SQL_ID" '{target_sql_id: $sql_id}')"
PLAN_DETAIL_ARGS="$(jq -cn --arg sql_id "$PRIMARY_SQL_ID" --argjson hrs "$HOURS_BACK" '{target_sql_id: $sql_id, hours_back: $hrs}')"

section "Tool: GA_TOP_SQL_DETAIL"
if [[ -n "$PRIMARY_SQL_ID" ]]; then
  call_tool "GA_TOP_SQL_DETAIL" "$DETAIL_ARGS" | jq .
else
  printf 'Skipped because no primary SQL_ID was selected.\n'
fi

section "Tool: GA_ASH_SQL_HOTSPOTS"
call_tool "GA_ASH_SQL_HOTSPOTS" "$ASH_ARGS" | jq .

section "Tool: GA_ASH_WAIT_PROFILE"
call_tool "GA_ASH_WAIT_PROFILE" "$ASH_ARGS" | jq .

section "Tool: GA_PLAN_CHANGE_SUMMARY"
call_tool "GA_PLAN_CHANGE_SUMMARY" "$ASH_ARGS" | jq .

section "Tool: GA_PLAN_CHANGE_DETAIL"
if [[ -n "$PRIMARY_SQL_ID" ]]; then
  call_tool "GA_PLAN_CHANGE_DETAIL" "$PLAN_DETAIL_ARGS" | jq .
else
  printf 'Skipped because no primary SQL_ID was selected.\n'
fi

section "Tool: GA_DB_WAIT_EVENTS_SUMMARY"
call_tool "GA_DB_WAIT_EVENTS_SUMMARY" "$LIMIT_ARGS" | jq .
