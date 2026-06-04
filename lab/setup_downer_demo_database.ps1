param(
  [string]$Profile = "LATINOAMERICA_APIKEY",
  [string]$Region = "sa-saopaulo-1",
  [Parameter(Mandatory = $true)]
  [string]$AutonomousDatabaseId,
  [Parameter(Mandatory = $true)]
  [string]$AdminPassword,
  [Parameter(Mandatory = $true)]
  [string]$DownerPassword,
  [Parameter(Mandatory = $true)]
  [string]$GraphDiagPassword,
  [string]$WalletPassword = "MiniDowner#2026Wallet!",
  [switch]$ResetAdminPassword,
  [switch]$StartDashboardLoad,
  [switch]$SetupPlanInstability,
  [switch]$StartPlanInstabilityDashboardLoad
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$env:OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING = "True"
$env:SUPPRESS_LABEL_WARNING = "True"

if ($StartDashboardLoad -and $StartPlanInstabilityDashboardLoad) {
  throw "Choose either -StartDashboardLoad or -StartPlanInstabilityDashboardLoad. The dashboard loader runs one signal at a time."
}

if ($StartPlanInstabilityDashboardLoad) {
  $SetupPlanInstability = $true
}

function Invoke-OciJson {
  param([string[]]$OciArgs)

  $output = & oci @OciArgs
  if ($LASTEXITCODE -ne 0) {
    throw "OCI CLI failed: oci $(Format-OciArgsForLog $OciArgs)"
  }

  $text = ($output -join "`n").Trim()
  if (-not $text) {
    return $null
  }

  return $text | ConvertFrom-Json
}

function Format-OciArgsForLog {
  param([string[]]$OciArgs)

  $safeArgs = @()
  $maskNext = $false
  foreach ($arg in $OciArgs) {
    if ($maskNext) {
      $safeArgs += "********"
      $maskNext = $false
      continue
    }

    $safeArgs += $arg
    if ($arg -eq "--admin-password" -or $arg -eq "--password") {
      $maskNext = $true
    }
  }

  return ($safeArgs -join ' ')
}

function Get-Adb {
  $response = Invoke-OciJson @(
    "db", "autonomous-database", "get",
    "--profile", $Profile,
    "--region", $Region,
    "--autonomous-database-id", $AutonomousDatabaseId,
    "--output", "json"
  )

  return $response.data
}

function ConvertTo-SqlclPath {
  param([string]$Path)
  return ($Path -replace "\\", "/")
}

function ConvertTo-SqlclScriptRef {
  param([string]$Path)
  return '@"' + (ConvertTo-SqlclPath $Path) + '"'
}

function Quote-SqlString {
  param([string]$Value)
  return $Value.Replace('"', '""')
}

function Invoke-SqlclScript {
  param([string]$ScriptPath)

  & sql -L -S /nolog "@$ScriptPath"
  if ($LASTEXITCODE -ne 0) {
    throw "SQLcl failed with exit code $LASTEXITCODE for $ScriptPath"
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$walletDir = Join-Path $repoRoot "wallet"
New-Item -ItemType Directory -Force -Path $walletDir | Out-Null

$adb = Get-Adb
if ($adb."lifecycle-state" -ne "AVAILABLE") {
  Write-Host "Waiting for ADB to become AVAILABLE. Current state: $($adb.'lifecycle-state')"
  Invoke-OciJson @(
    "db", "autonomous-database", "get",
    "--profile", $Profile,
    "--region", $Region,
    "--autonomous-database-id", $AutonomousDatabaseId,
    "--wait-for-state", "AVAILABLE",
    "--max-wait-seconds", "1800",
    "--output", "json"
  ) | Out-Null
  $adb = Get-Adb
}

if ($ResetAdminPassword) {
  Write-Host "Resetting ADMIN password for demo setup."
  Invoke-OciJson @(
    "db", "autonomous-database", "update",
    "--profile", $Profile,
    "--region", $Region,
    "--autonomous-database-id", $AutonomousDatabaseId,
    "--admin-password", $AdminPassword,
    "--wait-for-state", "AVAILABLE",
    "--max-wait-seconds", "1800",
    "--force",
    "--output", "json"
  ) | Out-Null
  $adb = Get-Adb
}

$dbName = $adb."db-name"
$connectAlias = ($dbName.ToLowerInvariant() + "_high")
$walletZip = Join-Path $walletDir ("Wallet_{0}.zip" -f $dbName)

Write-Host "Generating wallet: $walletZip"
& oci db autonomous-database generate-wallet `
  --profile $Profile `
  --region $Region `
  --autonomous-database-id $AutonomousDatabaseId `
  --password $WalletPassword `
  --generate-type SINGLE `
  --file $walletZip
if ($LASTEXITCODE -ne 0) {
  throw "Wallet generation failed."
}

$sqlScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("setup-downer-{0}.sql" -f ([guid]::NewGuid().ToString("N")))
$walletSql = ConvertTo-SqlclPath $walletZip
$adminPasswordSql = Quote-SqlString $AdminPassword
$downerPasswordSql = Quote-SqlString $DownerPassword
$graphDiagPasswordSql = Quote-SqlString $GraphDiagPassword

$scripts = @{
  users = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "workload/downer/00_create_users.sql")
  schema = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "workload/downer/01_create_schema.sql")
  graph = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "workload/downer/02_create_property_graph.sql")
  data = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "workload/downer/03_generate_data.sql")
  workload = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "workload/downer/05_run_workload.sql")
  grants = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "workload/downer/07_grant_diagnostic_access.sql")
  runSql = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "clients/adb-native-run-sql-readonly.sql")
  dashSetup = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "workload/downer/10_dashboard_load_setup.sql")
  dashStart = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "workload/downer/11_start_dashboard_load_before.sql")
  planInstabilityGrant = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "workload/downer/21_grant_plan_instability_extras.sql")
  planInstabilitySetup = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "workload/downer/22_setup_plan_instability.sql")
  planInstabilityWorkload = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "workload/downer/23_run_plan_instability_workload.sql")
  planInstabilityDashStart = ConvertTo-SqlclScriptRef (Join-Path $repoRoot "workload/downer/24_start_dashboard_load_plan_instability.sql")
}

$sqlLines = @(
  "WHENEVER SQLERROR EXIT SQL.SQLCODE",
  "SET CLOUDCONFIG $walletSql",
  "SET DEFINE ON",
  "SET ECHO ON",
  "SET FEEDBACK ON",
  "SET SERVEROUTPUT ON",
  "SET TIMING ON",
  "CONNECT ADMIN/`"$adminPasswordSql`"@$connectAlias",
  "$($scripts.users) `"$downerPasswordSql`" `"$graphDiagPasswordSql`"",
  "CONNECT DOWNER_DEMO/`"$downerPasswordSql`"@$connectAlias",
  "$($scripts.schema)",
  "$($scripts.graph)",
  "$($scripts.data)",
  "$($scripts.workload)",
  "CONNECT ADMIN/`"$adminPasswordSql`"@$connectAlias",
  "$($scripts.grants)",
  "CONNECT GRAPH_DIAG_USER/`"$graphDiagPasswordSql`"@$connectAlias",
  "$($scripts.runSql)",
  "CONNECT DOWNER_DEMO/`"$downerPasswordSql`"@$connectAlias",
  "$($scripts.dashSetup)"
)

if ($StartDashboardLoad) {
  $sqlLines += "$($scripts.dashStart)"
}

if ($SetupPlanInstability) {
  $sqlLines += @(
    "CONNECT ADMIN/`"$adminPasswordSql`"@$connectAlias",
    "$($scripts.planInstabilityGrant)",
    "CONNECT DOWNER_DEMO/`"$downerPasswordSql`"@$connectAlias",
    "$($scripts.planInstabilitySetup)",
    "$($scripts.planInstabilityWorkload)"
  )
}

if ($StartPlanInstabilityDashboardLoad) {
  $sqlLines += "$($scripts.planInstabilityDashStart)"
}

$sqlLines += @(
  "EXIT"
)

[System.IO.File]::WriteAllLines($sqlScriptPath, $sqlLines, [System.Text.UTF8Encoding]::new($false))

Write-Host "Running SQLcl setup against $connectAlias"
Invoke-SqlclScript -ScriptPath $sqlScriptPath

$mcpEndpoint = "https://dataaccess.adb.$Region.oraclecloudapps.com/adb/mcp/v1/databases/$AutonomousDatabaseId"
[pscustomobject]@{
  autonomous_database_id = $AutonomousDatabaseId
  region = $Region
  db_name = $dbName
  connect_alias = $connectAlias
  wallet_zip = $walletZip
  mcp_endpoint = $mcpEndpoint
  downer_user = "DOWNER_DEMO"
  graph_diag_user = "GRAPH_DIAG_USER"
  dashboard_load_started = [bool]$StartDashboardLoad
  plan_instability_setup = [bool]$SetupPlanInstability
  plan_instability_dashboard_load_started = [bool]$StartPlanInstabilityDashboardLoad
} | ConvertTo-Json -Depth 4
