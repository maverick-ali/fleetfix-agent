param(
  [Parameter(Mandatory=$true)][string]$KibanaUrl,
  [Parameter(Mandatory=$true)][string]$ApiKey,
  [string]$AgentId = "fleetfix_agent",
  [string]$OutDir = "."
)

$ErrorActionPreference = "Stop"
$headers = @{ Authorization = "ApiKey $ApiKey"; "kbn-xsrf" = "true" }

function Write-Utf8NoBom([string]$path, [string]$content) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "agent_builder/tools")   | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "agent_builder/agents") | Out-Null

# -------- Export tools (create-safe shape) --------
$toolsResp = Invoke-RestMethod -Method GET -Uri "$KibanaUrl/api/agent_builder/tools" -Headers $headers
$tools = $toolsResp.results

$tools | Where-Object { $_.id -like "fleetfix.*" } | ForEach-Object {
  $id = $_.id
  $tool = Invoke-RestMethod -Method GET -Uri "$KibanaUrl/api/agent_builder/tools/$id" -Headers $headers

  # Create Tool schema: id, type, description, tags, configuration (ONLY)
  # Params for ES|QL tools must live in configuration.params (not top-level). :contentReference[oaicite:3]{index=3}
  $payload = [ordered]@{
    id = $tool.id
    type = $tool.type
    description = $tool.description
    tags = $tool.tags
    configuration = $tool.configuration
  }

  $json = $payload | ConvertTo-Json -Depth 100
  $outPath = Join-Path $OutDir "agent_builder/tools/$id.json"
  Write-Utf8NoBom $outPath $json

  Write-Host "Exported tool: $id"
}

# -------- Export agent (create-safe shape) --------
$agent = Invoke-RestMethod -Method GET -Uri "$KibanaUrl/api/agent_builder/agents/$AgentId" -Headers $headers

# Create Agent schema: id, name, description, labels, avatar_color, avatar_symbol, configuration :contentReference[oaicite:4]{index=4}
$agentPayload = [ordered]@{
  id = $agent.id
  name = $agent.name
  description = $agent.description
  labels = $agent.labels
  avatar_color = $agent.avatar_color
  avatar_symbol = $agent.avatar_symbol
  configuration = $agent.configuration
}

$agentJson = $agentPayload | ConvertTo-Json -Depth 100
$agentOutPath = Join-Path $OutDir "agent_builder/agents/$AgentId.json"
Write-Utf8NoBom $agentOutPath $agentJson

Write-Host "Exported agent: $AgentId"
Write-Host "Export complete."