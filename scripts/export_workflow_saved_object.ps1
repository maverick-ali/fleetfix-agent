param(
  [Parameter(Mandatory=$true)][string]$KibanaUrl,
  [Parameter(Mandatory=$true)][string]$ApiKey,
  [string]$OutPath = "workflows\export_all_saved_objects.ndjson"
)

$ErrorActionPreference = "Stop"
$KibanaUrl = $KibanaUrl.TrimEnd("/")

$headers = @{
  Authorization = "ApiKey $ApiKey"
  "kbn-xsrf"    = "true"
}

# Saved Objects export API: must include `type` or `objects` in JSON body. :contentReference[oaicite:1]{index=1}
$payload = @{
  type = "*"
  includeReferencesDeep = $true
  excludeExportDetails = $true
} | ConvertTo-Json -Compress

New-Item -ItemType Directory -Force -Path (Split-Path $OutPath) | Out-Null

Invoke-WebRequest `
  -Method POST `
  -Uri "$KibanaUrl/api/saved_objects/_export" `
  -Headers $headers `
  -ContentType "application/json" `
  -Body $payload `
  -OutFile $OutPath

Write-Host "Wrote: $OutPath (bytes=$((Get-Item $OutPath).Length))"