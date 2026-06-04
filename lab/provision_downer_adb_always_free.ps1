param(
  [string]$Profile = "LATINOAMERICA_APIKEY",
  [string]$Region = "us-ashburn-1",
  [string]$ParentCompartmentName = "diego.e.cabrera",
  [string]$RequiredChildCompartmentName = "pitwall",
  [string]$DbName = "GADVDOWNERAF",
  [string]$DisplayName = "Graph Advisor DOWNER Always Free",
  [string]$DbVersion = "26ai",
  [string]$KeepResourceReason = "Mini-DOWNER demo ADB - preserve for customer demo",
  [string]$ResourceControlTeam = "To_be_Assigned",
  [switch]$SkipResourceControlTags,
  [switch]$AllowNonHomeRegion,
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
    if ($arg -eq "--admin-password") {
      $maskNext = $true
    }
  }

  return ($safeArgs -join ' ')
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
  $safeArgs = @()
  $maskNext = $false
  foreach ($arg in $OciArgs) {
    if ($maskNext) {
      $safeArgs += '$env:ADB_ADMIN_PASSWORD'
      $maskNext = $false
      continue
    }

    $safeArgs += $arg
    if ($arg -eq "--admin-password") {
      $maskNext = $true
    }
  }

  $quoted = foreach ($arg in $safeArgs) {
    if ($arg -match '^[A-Za-z0-9._:/=\\\-$]+$') {
      $arg
    } else {
      "'" + ($arg -replace "'", "''") + "'"
    }
  }
  "oci $($quoted -join ' ')"
}

function New-OciJsonFileArg {
  param(
    [string]$Name,
    [string]$JsonText
  )

  $fileName = "{0}-{1}.json" -f $Name, ([guid]::NewGuid().ToString("N"))
  $path = Join-Path ([System.IO.Path]::GetTempPath()) $fileName
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $JsonText, $utf8NoBom)
  return "file://$path"
}

$mcpTagKey = 'adb$feature'
$mcpTagValue = '{"name":"mcp_server","enable":true}'
$resourceControlNamespace = '0-ResourceControl'
$preserveDeleteValue = 'WeeklyDeleteResourceNo'
$preserveShutdownValue = 'NightlyShutdownNo'

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

function ConvertTo-Hashtable {
  param($InputObject)

  $hash = @{}
  if (-not $InputObject) {
    return $hash
  }

  foreach ($prop in $InputObject.PSObject.Properties) {
    if ($prop.Value -is [System.Management.Automation.PSCustomObject]) {
      $hash[$prop.Name] = ConvertTo-Hashtable $prop.Value
    } else {
      $hash[$prop.Name] = $prop.Value
    }
  }

  return $hash
}

function New-DemoDefinedTagsJson {
  param($ExistingTags)

  $tags = ConvertTo-Hashtable $ExistingTags
  if (-not $tags.ContainsKey($resourceControlNamespace) -or -not ($tags[$resourceControlNamespace] -is [hashtable])) {
    $tags[$resourceControlNamespace] = @{}
  }

  $resourceTags = $tags[$resourceControlNamespace]
  $resourceTags['DeleteResource'] = $preserveDeleteValue
  $resourceTags['ShutdownResource'] = $preserveShutdownValue
  $resourceTags['KeepResource'] = $KeepResourceReason
  $resourceTags['ShutdownTime'] = 'Manual only'
  $resourceTags['Team'] = $ResourceControlTeam

  return ($tags | ConvertTo-Json -Compress -Depth 8)
}

function Assert-DemoResourceControlTags {
  param($AutonomousDatabase)

  if ($SkipResourceControlTags) {
    Write-Warning "Resource-control tag validation skipped by operator."
    return
  }

  $definedTags = $AutonomousDatabase."defined-tags"
  if (-not $definedTags -or -not ($definedTags.PSObject.Properties.Name -contains $resourceControlNamespace)) {
    throw "ADB $($AutonomousDatabase.'display-name') is missing $resourceControlNamespace defined tags. This tenancy may auto-delete or auto-shutdown untagged resources."
  }

  $resourceTags = $definedTags.PSObject.Properties[$resourceControlNamespace].Value
  $deleteResource = $resourceTags.DeleteResource
  $shutdownResource = $resourceTags.ShutdownResource

  if ($deleteResource -ne $preserveDeleteValue) {
    throw "ADB $($AutonomousDatabase.'display-name') has DeleteResource=$deleteResource; expected $preserveDeleteValue to avoid scheduled deletion."
  }

  if ($shutdownResource -ne $preserveShutdownValue) {
    throw "ADB $($AutonomousDatabase.'display-name') has ShutdownResource=$shutdownResource; expected $preserveShutdownValue to avoid scheduled shutdown."
  }
}

function Get-AutonomousDatabase {
  param([string]$AutonomousDatabaseId)

  $response = Invoke-OciJson @(
    "db", "autonomous-database", "get",
    "--profile", $Profile,
    "--region", $Region,
    "--autonomous-database-id", $AutonomousDatabaseId,
    "--output", "json"
  )

  return $response.data
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

if ($homeRegion."region-name" -ne $Region -and -not $AllowNonHomeRegion) {
  throw "Always Free must be created in the tenancy home region. Home region is $($homeRegion.'region-name'), requested $Region."
}

if ($homeRegion."region-name" -ne $Region -and $AllowNonHomeRegion) {
  Write-Warning "Requested region $Region differs from home region $($homeRegion.'region-name'). Always Free creation may fail; continuing because -AllowNonHomeRegion was set."
}

$createFreeformTagsArg = New-OciJsonFileArg -Name "downer-freeform-tags" -JsonText (New-McpFreeformTagsJson $null)

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
  "--freeform-tags", $createFreeformTagsArg
)

if (-not $SkipResourceControlTags) {
  $createDefinedTagsArg = New-OciJsonFileArg -Name "downer-defined-tags" -JsonText (New-DemoDefinedTagsJson $null)
  $createBaseArgs += @("--defined-tags", $createDefinedTagsArg)
}

$createBaseArgs += @(
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

$createdAdb = $null
if ($ExecuteCreate) {
  if (-not $env:ADB_ADMIN_PASSWORD) {
    throw "Set ADB_ADMIN_PASSWORD before using -ExecuteCreate."
  }
  $createResponse = Invoke-OciJson $createRunArgs
  $createResponse | ConvertTo-Json -Depth 8

  if ($createResponse -and $createResponse.data -and $createResponse.data.id) {
    $createdAdb = Get-AutonomousDatabase -AutonomousDatabaseId $createResponse.data.id
    Assert-DemoResourceControlTags -AutonomousDatabase $createdAdb
  }
}

$targetAdb = if ($createdAdb) { $createdAdb } elseif (@($existingTarget).Count -gt 0) { $existingTarget[0] } else { $null }
if ($targetAdb) {
  $mcpTags = New-OciJsonFileArg -Name "downer-update-freeform-tags" -JsonText (New-McpFreeformTagsJson $targetAdb."freeform-tags")
  $tagArgs = @(
    "db", "autonomous-database", "update",
    "--profile", $Profile,
    "--region", $Region,
    "--autonomous-database-id", $targetAdb.id,
    "--freeform-tags", $mcpTags,
    "--force"
  )

  if (-not $SkipResourceControlTags) {
    $definedTagsArg = New-OciJsonFileArg -Name "downer-update-defined-tags" -JsonText (New-DemoDefinedTagsJson $targetAdb."defined-tags")
    $tagArgs += @("--defined-tags", $definedTagsArg)

    try {
      Assert-DemoResourceControlTags -AutonomousDatabase $targetAdb
    } catch {
      Write-Warning "$($_.Exception.Message) The update command below will re-apply preservation tags."
    }
  }

  Write-Host ""
  Write-Host "MCP/resource-control tag command:"
  Show-Command $tagArgs

  if ($ExecuteMcpTag) {
    Invoke-OciJson $tagArgs | ConvertTo-Json -Depth 8
    $targetAdb = Get-AutonomousDatabase -AutonomousDatabaseId $targetAdb.id
    Assert-DemoResourceControlTags -AutonomousDatabase $targetAdb
  }

  Write-Host ""
  Write-Host "MCP endpoint:"
  Write-Host "https://dataaccess.adb.$Region.oraclecloudapps.com/adb/mcp/v1/databases/$($targetAdb.id)"
} else {
  Write-Host ""
  Write-Host "No existing $DbName ADB was visible. Re-run after create completes to emit the MCP tag command and endpoint."
}
