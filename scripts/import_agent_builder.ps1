param(
  [Parameter(Mandatory=$true)][string]$KibanaUrl,
  [Parameter(Mandatory=$true)][string]$ApiKey,
  # Optional: when provided, we will wire any workflow tool's configuration.workflow_id to this value before creating/updating.
  [string]$WorkflowId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$KibanaUrl = $KibanaUrl.TrimEnd("/")

$headers = @{
  Authorization = "ApiKey $ApiKey"
  "kbn-xsrf"    = "true"
  "Content-Type" = "application/json"
}

function Invoke-Kbn($method, $url, $bodyObj = $null) {
  if ($null -eq $bodyObj) {
    return Invoke-RestMethod -Method $method -Uri $url -Headers $headers
  }
  $json = $bodyObj | ConvertTo-Json -Depth 100 -Compress
  return Invoke-RestMethod -Method $method -Uri $url -Headers $headers -Body $json
}

function Tool-Exists($id) {
  try {
    Invoke-RestMethod -Method GET -Uri "$KibanaUrl/api/agent_builder/tools/$id" -Headers $headers | Out-Null
    return $true
  } catch { return $false }
}

function Agent-Exists($id) {
  try {
    Invoke-RestMethod -Method GET -Uri "$KibanaUrl/api/agent_builder/agents/$id" -Headers $headers | Out-Null
    return $true
  } catch { return $false }
}

function Upsert-ToolFromObject($obj, [string]$sourcePath) {
  $id = $obj.id
  if (-not $obj.configuration) { throw "Tool '$id' missing configuration in $sourcePath" }
  if (-not $obj.type) { throw "Tool '$id' missing type in $sourcePath" }

  # Special handling: workflow tools must reference an existing workflow in THIS space.
  if ($obj.type -eq "workflow") {
    if ($WorkflowId) {
      $obj.configuration.workflow_id = $WorkflowId
    } else {
      Write-Host "Skipping workflow tool '$id' because -WorkflowId was not provided (required for new spaces)." -ForegroundColor Yellow
      return
    }
  }

  if (Tool-Exists $id) {
    $payload = [ordered]@{
      tags = $obj.tags
      description = $obj.description
      configuration = $obj.configuration
    }
    Invoke-Kbn "PUT" "$KibanaUrl/api/agent_builder/tools/$id" $payload | Out-Null
    Write-Host "Updated tool: $id" -ForegroundColor Green
  } else {
    $payload = [ordered]@{
      id = $obj.id
      type = $obj.type
      tags = $obj.tags
      description = $obj.description
      configuration = $obj.configuration
    }
    Invoke-Kbn "POST" "$KibanaUrl/api/agent_builder/tools" $payload | Out-Null
    Write-Host "Created tool: $id" -ForegroundColor Green
  }
}

function Upsert-Agent($agentObj, [string]$sourcePath) {
  $agentId = $agentObj.id
  if (-not $agentObj.configuration) { throw "Agent missing configuration in $sourcePath" }
  if (-not $agentObj.name -or -not $agentObj.description) { throw "Agent missing name/description in $sourcePath" }

  if (Agent-Exists $agentId) {
    $payload = [ordered]@{
      name = $agentObj.name
      description = $agentObj.description
      labels = $agentObj.labels
      avatar_color = $agentObj.avatar_color
      avatar_symbol = $agentObj.avatar_symbol
      configuration = $agentObj.configuration
    }
    Invoke-Kbn "PUT" "$KibanaUrl/api/agent_builder/agents/$agentId" $payload | Out-Null
    Write-Host "Updated agent: $agentId" -ForegroundColor Green
  } else {
    $payload = [ordered]@{
      id = $agentObj.id
      name = $agentObj.name
      description = $agentObj.description
      labels = $agentObj.labels
      avatar_color = $agentObj.avatar_color
      avatar_symbol = $agentObj.avatar_symbol
      configuration = $agentObj.configuration
    }
    Invoke-Kbn "POST" "$KibanaUrl/api/agent_builder/agents" $payload | Out-Null
    Write-Host "Created agent: $agentId" -ForegroundColor Green
  }
}

# ---- Import tools first ----
Get-ChildItem "agent_builder/tools" -Filter "*.json" -File | ForEach-Object {
  $file = $_
  try {
    $obj = Get-Content $file.FullName -Raw | ConvertFrom-Json
    Upsert-ToolFromObject $obj $file.FullName
  } catch {
    $err = $_
    Write-Host "FAILED tool import: $($file.Name)" -ForegroundColor Red
    Write-Host $err.Exception.Message -ForegroundColor Red
    throw
  }
}

# ---- Import agent ----
$agentPath = "agent_builder/agents/fleetfix_agent.json"
$agentObj = Get-Content $agentPath -Raw | ConvertFrom-Json
Upsert-Agent $agentObj $agentPath

Write-Host "Import complete." -ForegroundColor Cyan
