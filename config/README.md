# Configuration

This directory contains customizable configuration files for the Oracle Graph DBA Advisor.

## Files

### `production-guard.yaml`

Defines rules for identifying production vs non-production databases. The advisor reads this file at session start and blocks DDL/DML on production environments.

**Why customize this:**
Every organization has different naming conventions. Your production databases might be called `FINPROD`, `ERPDB`, or `myapp_production_us_east`. The built-in rules catch common patterns (`prod`, `prd`, `_high`, `_tp`), but you should add your specific names.

**How to customize:**
1. Open `config/production-guard.yaml`
2. Add your production database names to `block_patterns.db_name`
3. Add your production service names to `block_patterns.service_name`
4. Add your non-production patterns to `safe_patterns`
5. Choose `on_uncertain` behavior: `ask` (default), `block`, or `allow`

**Examples:**

```yaml
# Company with PROD/DEV/STG naming:
block_patterns:
  db_name: ["PROD", "PRD"]
  service_name: ["_prod_", "_prd_"]
safe_patterns:
  db_name: ["DEV", "STG", "UAT", "QA"]
  service_name: ["_dev_", "_stg_", "_uat_"]

# Company with region-based naming:
block_patterns:
  db_name: ["us_east_primary", "eu_west_primary"]
safe_patterns:
  db_name: ["us_east_dev", "eu_west_staging"]

# Company that uses specific users for production:
block_patterns:
  user_name: ["APP_PROD_OWNER", "SCHEMA_ADMIN"]
```

**What happens when production is detected:**
The advisor switches to read-only mode. All SELECT-based diagnostics work normally. Recommendations are produced as text (DDL scripts) but not executed. The advisor tells the user to deploy via their change management process.
