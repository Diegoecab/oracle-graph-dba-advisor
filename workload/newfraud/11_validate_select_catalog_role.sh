#!/usr/bin/env bash
set -euo pipefail

# Validates whether SELECT_CATALOG_ROLE alone covers the current skill needs.
#
# What this harness does:
# 1. Creates a disposable test user with a role-based read model
# 2. Runs session-level SQL checks against the exact view families used today
# 3. Runs representative stored PL/SQL checks to validate packaged runtime
#
# Required:
#   ADMIN_PASSWORD
#
# Optional:
#   ADMIN_USERNAME
#   TEST_USERNAME
#   TEST_PASSWORD
#   SQLCL_BIN
#   ADB_CONNECT_ALIAS
#   ADB_WALLET_ZIP

: "${ADMIN_USERNAME:=ADMIN}"
: "${TEST_USERNAME:=ROLE_COVERAGE_SKILL}"
: "${TEST_PASSWORD:=RoleCoverage123##!}"
: "${SQLCL_BIN:=/mnt/c/DC/Soft/sqlcl-latest/sqlcl/bin/sql}"
: "${ADB_CONNECT_ALIAS:=graadvf260430_high}"
: "${ADB_WALLET_ZIP:=/tmp/graadvf260430_wallet.zip}"

if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
  echo "ADMIN_PASSWORD is required." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATION_SQL="${REPO_ROOT}/clients/validate-select-catalog-role-coverage.sql"

section() {
  printf '\n===== %s =====\n\n' "$1"
}

run_full_validation() {
  local wrapper
  wrapper="$(mktemp)"

  cat > "${wrapper}" <<SQL
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO ON
SET FEEDBACK ON
SET HEADING ON
SET SERVEROUTPUT ON
SET CLOUDCONFIG ${ADB_WALLET_ZIP}
CONNECT ${ADMIN_USERNAME}/"${ADMIN_PASSWORD}"@${ADB_CONNECT_ALIAS}

BEGIN
  EXECUTE IMMEDIATE 'DROP USER ${TEST_USERNAME} CASCADE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1918 THEN
      RAISE;
    END IF;
END;
/

CREATE USER ${TEST_USERNAME} IDENTIFIED BY "${TEST_PASSWORD}"
  DEFAULT TABLESPACE DATA
  TEMPORARY TABLESPACE TEMP
  QUOTA 100M ON DATA;

GRANT CREATE SESSION TO ${TEST_USERNAME};
GRANT CREATE PROCEDURE TO ${TEST_USERNAME};
GRANT SELECT_CATALOG_ROLE TO ${TEST_USERNAME};
GRANT EXECUTE ON DBMS_XPLAN TO ${TEST_USERNAME};
GRANT EXECUTE ON C##CLOUD\$SERVICE.DBMS_CLOUD_AI_AGENT TO ${TEST_USERNAME};

PROMPT
PROMPT ===== ROLE-ONLY TEST USER READY =====
PROMPT

SELECT grantee, granted_role, default_role
FROM dba_role_privs
WHERE grantee = '${TEST_USERNAME}'
ORDER BY granted_role;

DEFINE test_user = ${TEST_USERNAME}
DEFINE test_password = ${TEST_PASSWORD}
DEFINE connect_alias = ${ADB_CONNECT_ALIAS}
DEFINE wallet_zip = ${ADB_WALLET_ZIP}
@"${VALIDATION_SQL}"
SQL

  "${SQLCL_BIN}" -S /nolog @"${wrapper}"
}

section "Create Role-Only Validation User + Run Coverage Validation"
run_full_validation
