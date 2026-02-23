param(
  [string]$KibanaUrl,
  [string]$ApiKey,
  [string]$WorkflowId,                                    # Optional: export a single workflow by ID
  [string]$OutDir = "workflows\exported"                  # Output directory for YAML files
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Try to load scripts/env.ps1 if parameters are not provided
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Resolve-Path (Join-Path $scriptDir "..")
$envFile   = Join-Path $scriptDir "env.ps1"

if ((-not $KibanaUrl -or -not $ApiKey) -and (Test-Path $envFile)) {
  . $envFile
  if (-not $KibanaUrl) { $KibanaUrl = $env:KIBANA_URL }
  if (-not $ApiKey)    { $ApiKey    = $env:API_KEY }
}

if (-not $KibanaUrl) { throw "Missing KibanaUrl. Provide -KibanaUrl or set `$env:KIBANA_URL in scripts/env.ps1" }
if (-not $ApiKey)    { throw "Missing ApiKey. Provide -ApiKey or set `$env:API_KEY in scripts/env.ps1" }

$KibanaUrl = $KibanaUrl.TrimEnd("/")

# Ensure output directory exists
$fullOutDir = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Force -Path $fullOutDir | Out-Null

# ── Helper: call Kibana, return @{Code=<http>; Body=<string>} ─────────────────
function Invoke-Kibana {
  param([string]$Method = "GET", [string]$Path, [string]$BodyFile = "")

  $tempOut = [System.IO.Path]::GetTempFileName()
  try {
    $args = @(
      "-sS", "-o", $tempOut, "-w", "%{http_code}",
      "-X", $Method,
      "$KibanaUrl$Path",
      "-H", "Authorization: ApiKey $ApiKey",
      "-H", "kbn-xsrf: true",
      "-H", "x-elastic-internal-origin: Kibana",
      "-H", "Content-Type: application/json"
    )
    if ($BodyFile) { $args += @("--data-binary", "@$BodyFile") }

    $httpCode = & curl.exe @args
    $body     = Get-Content $tempOut -Raw -ErrorAction SilentlyContinue
    return @{ Code = $httpCode; Body = $body }
  } finally {
    Remove-Item $tempOut -ErrorAction SilentlyContinue
  }
}

# ── Pre-flight: verify connectivity and feature availability ──────────────────
Write-Host "Connecting to: $KibanaUrl" -ForegroundColor Cyan

$status = Invoke-Kibana -Path "/api/status"
if ($status.Code -ne "200") {
  throw "Cannot reach Kibana (HTTP $($status.Code)). Check your KibanaUrl and ApiKey."
}

Write-Host "Kibana reachable. Checking Workflows feature availability..." -ForegroundColor Cyan

$probe = Invoke-Kibana -Path "/api/workflows"
if ($probe.Code -eq "404") {
  Write-Host ""
  Write-Host "ERROR: The Workflows API returned 404." -ForegroundColor Red
  Write-Host ""
  Write-Host "This means one of the following:" -ForegroundColor Yellow
  Write-Host "  1) The Workflows feature is NOT enabled in your project." -ForegroundColor Yellow
  Write-Host "     --> In Kibana: go to Management > Advanced Settings," -ForegroundColor Yellow
  Write-Host "         search for 'workflow' and enable it, then re-run." -ForegroundColor Yellow
  Write-Host ""
  Write-Host "  2) Your Elastic project is not on version 9.3+ (Workflows" -ForegroundColor Yellow
  Write-Host "     requires 9.3 or later). Check your project version at:" -ForegroundColor Yellow
  Write-Host "     $KibanaUrl/app/management/stack/upgrade_assistant" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  3) Your API key may not have the required privileges." -ForegroundColor Yellow
  Write-Host "     Workflows needs: 'manage_workflows' cluster privilege or" -ForegroundColor Yellow
  Write-Host "     a Kibana privilege of 'all' on the Workflows feature." -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Kibana version info:" -ForegroundColor Cyan
  $versionInfo = ($status.Body | ConvertFrom-Json)
  Write-Host "  Version : $($versionInfo.version.number)" -ForegroundColor White
  Write-Host "  Build   : $($versionInfo.version.build_flavor)" -ForegroundColor White
  exit 1
}

if ($probe.Code -eq "401" -or $probe.Code -eq "403") {
  Write-Host "ERROR: API key is invalid or lacks Workflows permissions (HTTP $($probe.Code))." -ForegroundColor Red
  Write-Host "Create a new API key with 'Workflows: All' privilege in Stack Management > API Keys." -ForegroundColor Yellow
  exit 1
}

if ($probe.Code -ne "200") {
  Write-Host "ERROR: Unexpected response from Workflows API (HTTP $($probe.Code)):" -ForegroundColor Red
  Write-Host $probe.Body
  exit 1
}

# ── Parse workflow list ───────────────────────────────────────────────────────
$list  = $probe.Body | ConvertFrom-Json
$items = if ($list -is [System.Array])                         { $list }
         elseif ($list.PSObject.Properties["items"])           { $list.items }
         elseif ($list.PSObject.Properties["workflows"])       { $list.workflows }
         else                                                  { @() }

# ── Export a single workflow by ID ────────────────────────────────────────────
function Export-Workflow {
  param([string]$Id, [string]$Name)

  $r = Invoke-Kibana -Path "/api/workflows/$Id"
  if ($r.Code -ne "200") {
    Write-Warning "Failed to export workflow '$Id' (HTTP $($r.Code)): $($r.Body)"
    return
  }

  $parsed = $r.Body | ConvertFrom-Json
  $yaml   = $parsed.yaml
  if (-not $yaml) {
    Write-Warning "Workflow '$Id' returned no YAML. Saving raw JSON instead."
    $yaml = $r.Body
  }

  $safeName = ($Name -replace '[\\/:*?"<>|]', '_').Trim()
  if (-not $safeName) { $safeName = $Id }
  $outFile  = Join-Path $fullOutDir "$safeName.yaml"
  [System.IO.File]::WriteAllText($outFile, $yaml, [System.Text.Encoding]::UTF8)
  Write-Host "  Saved: $outFile" -ForegroundColor Green
}

# ── Main ──────────────────────────────────────────────────────────────────────
if ($WorkflowId) {
  Write-Host "Exporting single workflow: $WorkflowId" -ForegroundColor Cyan
  Export-Workflow -Id $WorkflowId -Name $WorkflowId

} else {
  if ($items.Count -eq 0) {
    Write-Host "Workflows feature is enabled but no workflows exist in this project yet." -ForegroundColor Yellow
    exit 0
  }

  Write-Host "Found $($items.Count) workflow(s). Exporting to: $fullOutDir" -ForegroundColor Cyan
  foreach ($wf in $items) {
    $id   = $wf.id
    $name = if ($wf.PSObject.Properties["name"]) { $wf.name } else { $id }
    Write-Host "  Exporting: $name ($id)" -ForegroundColor White
    Export-Workflow -Id $id -Name $name
  }

  Write-Host "`nDone. $($items.Count) workflow(s) exported to: $fullOutDir" -ForegroundColor Green
}
