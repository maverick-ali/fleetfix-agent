param(
  [string]$EsUrl,
  [string]$KibanaUrl,
  [string]$ApiKey,
  [int]$LogCount = 8000,
  [int]$HostCount = 30,
  [switch]$SkipDashboardImport,
  [switch]$SkipWorkflowStep
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Resolve-Path (Join-Path $scriptDir "..")

# Load env.ps1 if args not provided
$envFile = Join-Path $scriptDir "env.ps1"
if ((-not $EsUrl -or -not $KibanaUrl -or -not $ApiKey) -and (Test-Path $envFile)) {
  . $envFile
  if (-not $EsUrl) { $EsUrl = $env:ES_URL }
  if (-not $KibanaUrl) { $KibanaUrl = $env:KIBANA_URL }
  if (-not $ApiKey) { $ApiKey = $env:API_KEY }
}

function Require([string]$name, $value) {
  if (-not $value) { throw "Missing $name. Provide parameter or set in scripts/env.ps1" }
}

Require "ES_URL" $EsUrl
Require "KIBANA_URL" $KibanaUrl
Require "API_KEY" $ApiKey

$EsUrl     = $EsUrl.TrimEnd("/")
$KibanaUrl = $KibanaUrl.TrimEnd("/")

Write-Host "== FleetFix setup ==" -ForegroundColor Cyan
Write-Host "ES_URL     : $EsUrl"
Write-Host "KIBANA_URL : $KibanaUrl"
Write-Host "LogCount   : $LogCount"
Write-Host "HostCount  : $HostCount"

# 1) Create indices
Write-Host "`n[1/7] Creating indices..." -ForegroundColor Cyan
& (Join-Path $scriptDir "create_indices.ps1") -EsUrl $EsUrl -ApiKey $ApiKey

# 2) Generate data
Write-Host "`n[2/7] Generating data..." -ForegroundColor Cyan
& (Join-Path $scriptDir "generate_fleetfix_data.ps1") -LogCount $LogCount -HostCount $HostCount -OutDir (Join-Path $repoRoot "data")
& (Join-Path $scriptDir "generate_fleetfix_runbooks.ps1") -OutDir (Join-Path $repoRoot "data") -Overwrite

# 3) Bulk ingest
Write-Host "`n[3/7] Bulk ingest data..." -ForegroundColor Cyan
& (Join-Path $scriptDir "bulk_ingest.ps1") -EsUrl $EsUrl -ApiKey $ApiKey -Index "fleetfix_logs" -NdjsonPath (Join-Path $repoRoot "data\fleetfix_logs.ndjson")
& (Join-Path $scriptDir "bulk_ingest.ps1") -EsUrl $EsUrl -ApiKey $ApiKey -Index "fleetfix_runbooks" -NdjsonPath (Join-Path $repoRoot "data\fleetfix_runbooks.ndjson")

# 4) Workflows manual step (Option A)
Write-Host "`n[4/7] Workflows (manual, one-time)..." -ForegroundColor Cyan
$workflowId = ""
if (-not $SkipWorkflowStep) {
  Write-Host "1) Kibana -> Stack Management -> Advanced Settings" -ForegroundColor Yellow
  Write-Host "2) Enable: workflows:ui:enabled (save changes, reload Kibana)" -ForegroundColor Yellow
  Write-Host "3) Kibana -> Workflows -> Create workflow from: workflows/fleetfix_create_ticket.yaml" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "After creating the workflow, copy its ID from the browser URL." -ForegroundColor Yellow
  Write-Host "It typically looks like: workflow-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -ForegroundColor Yellow
  Write-Host ""
  $workflowId = Read-Host "Paste workflow id (or leave blank to skip patching for now)"
  $workflowId = $workflowId.Trim()
  if (-not $workflowId) {
    Write-Host "No workflow id provided. We'll import tools/agent, but ticket creation will not work until you wire fleetfix.create_ticket." -ForegroundColor Yellow
  }
} else {
  Write-Host "Skipping workflows step (flag set). Ticket creation will not work until you wire fleetfix.create_ticket." -ForegroundColor Yellow
}

# 5) Import dashboard saved objects (optional)
if (-not $SkipDashboardImport) {
  $dashPath = Join-Path $repoRoot "dashboards\fleetfix_saved_objects.ndjson"
  if (Test-Path $dashPath) {
    Write-Host "`n[5/7] Importing dashboard saved objects..." -ForegroundColor Cyan
    & (Join-Path $scriptDir "import_saved_objects.ps1") -KibanaUrl $KibanaUrl -ApiKey $ApiKey -NdjsonPath $dashPath
  } else {
    Write-Host "`n[5/7] Dashboard export not found at dashboards/fleetfix_saved_objects.ndjson (skipping)" -ForegroundColor Yellow
  }
} else {
  Write-Host "`n[5/7] Skipping dashboard import (flag set)" -ForegroundColor Yellow
}

# 6) Import Agent Builder tools + agent (pass workflow id so workflow tool can be created in this space)
Write-Host "`n[6/7] Importing Agent Builder tools + agent..." -ForegroundColor Cyan
if ($workflowId) {
  & (Join-Path $scriptDir "import_agent_builder.ps1") -KibanaUrl $KibanaUrl -ApiKey $ApiKey -WorkflowId $workflowId
} else {
  & (Join-Path $scriptDir "import_agent_builder.ps1") -KibanaUrl $KibanaUrl -ApiKey $ApiKey
}

# 7) Smoke test
Write-Host "`n[7/7] Running smoke test..." -ForegroundColor Cyan
& (Join-Path $scriptDir "smoke_test.ps1") -KibanaUrl $KibanaUrl -ApiKey $ApiKey

Write-Host "`nSetup complete." -ForegroundColor Green
Write-Host "Open Kibana Agent Builder and chat with 'FleetFix Agent' to verify end-to-end." -ForegroundColor Green
