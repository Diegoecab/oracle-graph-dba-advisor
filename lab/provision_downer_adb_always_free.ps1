param(
  [string]$Profile = "LATINOAMERICA_APIKEY",
  [string]$Region = "us-ashburn-1",
  [string]$ParentCompartmentName = "diego.e.cabrera",
  [string]$RequiredChildCompartmentName = "pitwall",
  [string]$DbName = "GADVDOWNERAF",
  [string]$DisplayName = "Graph Advisor DOWNER Always Free",
  [string]$DbVersion = "26ai",
  [switch]$ExecuteCreate,
  [switch]$ExecuteMcpTag
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$env:OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING = "True"
$env:SUPPRESS_LABEL_WARNING = "True"

function Invoke-OciJson {
  param([string[]]$OciArgs)

  $output = & oci @OciArgs
  if ($LASTEXITCODE -ne 0) {
    throw "OCI CLI failed: oci $($OciArgs -join ' ')"
  }

  $text = ($output -join "`n").Trim()
  if (-not $text) {
    return $null
  }

  return $text | ConvertFrom-Json
}

function Get-OciProfileValue {
  param(
    [string]$ProfileName,
    [string]$Key
  )

  $configPath = Join-Path $env:USERPROFILE ".oci\config"
  $currentProfile = $null
  foreach ($line in Get-Content -Path $configPath) {
    $trimmed = $line.Trim()
    if ($trimmed -match '^\[(.+)\]$') {
      $currentProfile = $matches[1]
      continue
    }
    if ($currentProfile -eq $ProfileName -and $trimmed -match "^$Key\s*=\s*(.+)$") {
      return $matches[1].Trim()
    }
  }

  return $null
}

function Resolve-TargetCompartment {
  $parents = Invoke-OciJson @(
    "iam", "compartment", "list",
    "--profile", $Profile,
    "--all",
    "--compartment-id-in-subtree", "true",
    "--access-level", "ACCESSIBLE",
    "--name", $ParentCompartmentName,
    "--output", "json"
  )

  if (-not $parents -or -not $parents.data -or $parents.data.Count -eq 0) {
    throw "No accessible compartment named $ParentCompartmentName was found."
  }

  foreach ($parent in @($parents.data)) {
    $children = Invoke-OciJson @(
      "iam", "compartment", "list",
      "--profile", $Profile,
      "--compartment-id", $parent.id,
      "--name", $RequiredChildCompartmentName,
      "--all",
      "--output", "json"
    )

    if ($children -and $children.data -and $children.data.Count -gt 0) {
      return [pscustomobject]@{
        Parent = $parent
        Child = $children.data[0]
      }
    }
  }

  throw "No $ParentCompartmentName compartment with child $RequiredChildCompartmentName was found."
}

function Show-Command {
  param([string[]]$OciArgs)
  $quoted = foreach ($arg in $OciArgs) {
    if ($arg -match '^[A-Za-z0-9._:/=\\\-$]+$') {
      $arg
    } else {
      "'" + ($arg -replace "'", "''") + "'"
    }
  }
  "oci $($quoted -join ' ')"
}

$mcpTagKey = 'adb$feature'
$mcpTagValue = '{"name":"mcp_server","enable":true}'

function New-McpFreeformTagsJson {
  param($ExistingTags)

  $tags = @{}
  if ($ExistingTags) {
    foreach ($prop in $ExistingTags.PSObject.Properties) {
      $tags[$prop.Name] = [string]$prop.Value
    }
  }

  $tags[$mcpTagKey] = $mcpTagValue
  return ($tags | ConvertTo-Json -Compress)
}

$tenancyId = Get-OciProfileValue -ProfileName $Profile -Key "tenancy"
if (-not $tenancyId) {
  throw "Profile $Profile does not expose a tenancy entry in OCI config."
}

$tenancy = Invoke-OciJson @(
  "iam", "tenancy", "get",
  "--profile", $Profile,
  "--tenancy-id", $tenancyId,
  "--output", "json"
)

$regions = Invoke-OciJson @(
  "iam", "region-subscription", "list",
  "--profile", $Profile,
  "--output", "json"
)

$homeRegion = @($regions.data | Where-Object { $_."is-home-region" -eq $true })[0]
$target = Resolve-TargetCompartment

$adbs = Invoke-OciJson @(
  "db", "autonomous-database", "list",
  "--profile", $Profile,
  "--region", $Region,
  "--compartment-id", $target.Parent.id,
  "--all",
  "--output", "json"
)

$adbCount = if ($adbs -and $adbs.data) { @($adbs.data).Count } else { 0 }
$freeAdbs = if ($adbs -and $adbs.data) { @($adbs.data | Where-Object { $_."is-free-tier" -eq $true }) } else { @() }
$existingTarget = if ($adbs -and $adbs.data) { @($adbs.data | Where-Object { $_."db-name" -eq $DbName -or $_."display-name" -eq $DisplayName }) } else { @() }

[pscustomobject]@{
  profile = $Profile
  tenancy_name = $tenancy.data.name
  home_region_key = $homeRegion."region-key"
  home_region = $homeRegion."region-name"
  target_region = $Region
  target_parent_compartment = $target.Parent.name
  target_parent_compartment_ocid = $target.Parent.id
  required_child_compartment = $target.Child.name
  visible_adb_count_in_parent = $adbCount
  visible_always_free_adb_count_in_parent = @($freeAdbs).Count
  existing_target_count = @($existingTarget).Count
} | ConvertTo-Json

if ($homeRegion."region-name" -ne $Region) {
  throw "Always Free must be created in the tenancy home region. Home region is $($homeRegion.'region-name'), requested $Region."
}

$createBaseArgs = @(
  "db", "autonomous-database", "create",
  "--profile", $Profile,
  "--region", $Region,
  "--compartment-id", $target.Parent.id,
  "--db-name", $DbName,
  "--display-name", $DisplayName,
  "--db-version", $DbVersion,
  "--db-workload", "OLTP",
  "--is-free-tier", "true",
  "--license-model", "LICENSE_INCLUDED",
  "--is-mtls-connection-required", "true",
  "--freeform-tags", (New-McpFreeformTagsJson $null),
  "--wait-for-state", "AVAILABLE",
  "--max-wait-seconds", "3600"
)

$createDisplayArgs = $createBaseArgs + @("--admin-password", '$env:ADB_ADMIN_PASSWORD')
$createRunArgs = $createBaseArgs
if ($env:ADB_ADMIN_PASSWORD) {
  $createRunArgs += @("--admin-password", $env:ADB_ADMIN_PASSWORD)
} else {
  Write-Host "ADB_ADMIN_PASSWORD is not set; create command is shown without execution."
}

Write-Host ""
Write-Host "Create command:"
Show-Command $createDisplayArgs

if ($ExecuteCreate) {
  if (-not $env:ADB_ADMIN_PASSWORD) {
    throw "Set ADB_ADMIN_PASSWORD before using -ExecuteCreate."
  }
  Invoke-OciJson $createRunArgs | ConvertTo-Json -Depth 8
}

$targetAdb = if (@($existingTarget).Count -gt 0) { $existingTarget[0] } else { $null }
if ($targetAdb) {
  $mcpTags = New-McpFreeformTagsJson $targetAdb."freeform-tags"
  $tagArgs = @(
    "db", "autonomous-database", "update",
    "--profile", $Profile,
    "--region", $Region,
    "--autonomous-database-id", $targetAdb.id,
    "--freeform-tags", $mcpTags,
    "--force"
  )

  Write-Host ""
  Write-Host "MCP tag command:"
  Show-Command $tagArgs

  if ($ExecuteMcpTag) {
    Invoke-OciJson $tagArgs | ConvertTo-Json -Depth 8
  }

  Write-Host ""
  Write-Host "MCP endpoint:"
  Write-Host "https://dataaccess.adb.$Region.oraclecloudapps.com/adb/mcp/v1/databases/$($targetAdb.id)"
} else {
  Write-Host ""
  Write-Host "No existing $DbName ADB was visible. Re-run after create completes to emit the MCP tag command and endpoint."
}
