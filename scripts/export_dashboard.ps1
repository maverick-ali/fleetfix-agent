param(
  [Parameter(Mandatory=$true)][string]$KibanaUrl,
  [Parameter(Mandatory=$true)][string]$ApiKey,
  [string]$DashboardTitle = "FleetFix - Ops Overview",
  [string]$OutPath = "dashboards/fleetfix_saved_objects.ndjson"
)

$headers = @{ Authorization = "ApiKey $ApiKey"; "kbn-xsrf" = "true" }

# Find dashboard by title
$findUrl = "$KibanaUrl/api/saved_objects/_find?type=dashboard&search_fields=title&search=" + [uri]::EscapeDataString($DashboardTitle)
$find = Invoke-RestMethod -Method GET -Uri $findUrl -Headers $headers
if ($find.total -lt 1) { throw "Dashboard not found: $DashboardTitle" }

$dashId = $find.saved_objects[0].id
Write-Host "Found dashboard id: $dashId"

# Export dashboard + references
$exportUrl = "$KibanaUrl/api/saved_objects/_export"
$body = @{
  objects = @(@{ type="dashboard"; id=$dashId })
  includeReferencesDeep = $true
  excludeExportDetails = $true
} | ConvertTo-Json -Depth 10

New-Item -ItemType Directory -Force -Path (Split-Path $OutPath) | Out-Null
Invoke-WebRequest -Method POST -Uri $exportUrl -Headers $headers -ContentType "application/json" -Body $body -OutFile $OutPath | Out-Null
Write-Host "Exported saved objects -> $OutPath"