param(
  [string[]]$Extensions = @(".md", ".sql", ".json", ".yml", ".yaml", ".html", ".js", ".css", ".sh", ".ps1", ".bat", ".cmd"),
  [switch]$All
)

$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$bad = New-Object System.Collections.Generic.List[string]

if ($All) {
  $files = git ls-files
} else {
  $files = @(
    git diff --name-only
    git diff --name-only --cached
  ) | Where-Object { $_ } | Sort-Object -Unique
}

if (-not $files) {
  Write-Output "text integrity ok: no changed tracked files"
  exit 0
}

foreach ($file in $files) {
  $ext = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
  if ($Extensions -notcontains $ext) {
    continue
  }

  $path = Join-Path (Get-Location) $file
  if (-not [System.IO.File]::Exists($path)) {
    continue
  }

  $bytes = [System.IO.File]::ReadAllBytes($path)
  try {
    $text = $utf8.GetString($bytes)
  } catch {
    $bad.Add("$file : invalid UTF-8 bytes")
    continue
  }

  if ($text.IndexOf([char]0xFFFD) -ge 0) {
    $bad.Add("$file : contains Unicode replacement character U+FFFD")
  }

  if ($text -match "Ã|Â|â") {
    $bad.Add("$file : contains common mojibake marker")
  }
}

if ($bad.Count -gt 0) {
  $bad | ForEach-Object { Write-Error $_ }
  exit 1
}

Write-Output "text integrity ok"
