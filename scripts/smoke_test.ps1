param(
  [Parameter(Mandatory=$true)][string]$KibanaUrl,
  [Parameter(Mandatory=$true)][string]$ApiKey
)

$headers = @{ Authorization = "ApiKey $ApiKey"; "kbn-xsrf" = "true"; "Content-Type"="application/json" }

Write-Host "1) Tool1: detect clusters"
$body1 = @{ tool_id="fleetfix.detect_failure_clusters"; tool_params=@{ lookback="24 hours"; host_name="*"; limit=5 } } | ConvertTo-Json -Depth 10
Invoke-RestMethod -Method POST -Uri "$KibanaUrl/api/agent_builder/tools/_execute" -Headers $headers -Body $body1 | Out-Null

Write-Host "2) Tool3: exact runbook"
$body3 = @{ tool_id="fleetfix.get_runbook_by_signature"; tool_params=@{ signature="context_canceled" } } | ConvertTo-Json -Depth 10
Invoke-RestMethod -Method POST -Uri "$KibanaUrl/api/agent_builder/tools/_execute" -Headers $headers -Body $body3 | Out-Null

Write-Host "3) Agent converse"
$chat = @{ agent_id="fleetfix_agent"; input="Get runbook for context_canceled" } | ConvertTo-Json -Depth 10
Invoke-RestMethod -Method POST -Uri "$KibanaUrl/api/agent_builder/converse" -Headers $headers -Body $chat | Out-Null

Write-Host "Smoke test OK"