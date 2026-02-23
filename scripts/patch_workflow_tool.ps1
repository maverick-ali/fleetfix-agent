param(
  [Parameter(Mandatory=$true)][string]$KibanaUrl,
  [Parameter(Mandatory=$true)][string]$ApiKey,
  [Parameter(Mandatory=$true)][string]$WorkflowId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$KibanaUrl = $KibanaUrl.TrimEnd("/")

$headers = @{
  Authorization = "ApiKey $ApiKey"
  "kbn-xsrf"    = "true"
  "Content-Type"= "application/json"
}

# Fetch the tool so we preserve its description/tags
$tool = Invoke-RestMethod -Method GET -Uri "$KibanaUrl/api/agent_builder/tools/fleetfix.create_ticket" `
  -Headers @{ Authorization = "ApiKey $ApiKey" }

$payload = @{
  description = $tool.description
  tags = $tool.tags
  configuration = @{
    workflow_id = $WorkflowId
    wait_for_completion = $true
  }
} | ConvertTo-Json -Depth 20 -Compress

Invoke-RestMethod -Method PUT -Uri "$KibanaUrl/api/agent_builder/tools/fleetfix.create_ticket" `
  -Headers $headers -Body $payload | Out-Null

Write-Host "Updated fleetfix.create_ticket workflow_id -> $WorkflowId"
