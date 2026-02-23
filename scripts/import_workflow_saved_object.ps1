param(
  [Parameter(Mandatory=$true)][string]$KibanaUrl,
  [Parameter(Mandatory=$true)][string]$ApiKey,
  [string]$NdjsonPath = "workflows/fleetfix_workflow_saved_objects.ndjson",
  [string]$MatchTitleContains = "fleetfix_create_ticket"
)

if (-not (Test-Path $NdjsonPath)) {
  throw "Workflow saved object file not found: $NdjsonPath"
}

# Import saved objects (multipart/form-data). kbn-xsrf is required. :contentReference[oaicite:5]{index=5}
$respJson = curl.exe -sS -X POST "$KibanaUrl/api/saved_objects/_import?overwrite=true" `
  -H "kbn-xsrf: true" `
  -H "Authorization: ApiKey $ApiKey" `
  -F "file=@$NdjsonPath"

$resp = $respJson | ConvertFrom-Json

if (-not $resp.success) {
  $errs = ($resp.errors | ConvertTo-Json -Depth 10)
  throw "Workflow saved objects import failed: $errs"
}

# Find the workflow object in successResults
# Prefer meta.title match; fall back to any object containing the match string.
$hit = $resp.successResults | Where-Object {
  $_.meta -and $_.meta.title -and ($_.meta.title -like "*$MatchTitleContains*")
} | Select-Object -First 1

if (-not $hit) {
  # fallback: any result with a title
  $hit = $resp.successResults | Where-Object { $_.meta -and $_.meta.title } | Select-Object -First 1
}

if (-not $hit) { throw "Imported saved objects, but couldn't locate workflow result in successResults." }

# Use destinationId if present (IDs may change across spaces). :contentReference[oaicite:6]{index=6}
$workflowId = if ($hit.destinationId) { $hit.destinationId } else { $hit.id }

Write-Host "Workflow imported: type=$($hit.type) title=$($hit.meta.title) id=$workflowId"
$workflowId