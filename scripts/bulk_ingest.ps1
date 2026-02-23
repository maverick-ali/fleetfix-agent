param(
  [Parameter(Mandatory=$true)][string]$EsUrl,
  [Parameter(Mandatory=$true)][string]$ApiKey,
  [Parameter(Mandatory=$true)][string]$Index,
  [Parameter(Mandatory=$true)][string]$NdjsonPath
)

$headers = @{
  Authorization = "ApiKey $ApiKey"
  "Content-Type" = "application/x-ndjson"
}

$tmp = Join-Path ([System.IO.Path]::GetDirectoryName($NdjsonPath)) ("bulk_{0}.ndjson" -f $Index)
"" | Out-File $tmp -Encoding utf8

Get-Content $NdjsonPath | ForEach-Object {
  if ($_.Trim().Length -gt 0) {
    Add-Content $tmp ("{""index"":{""_index"":""$Index""}}") -Encoding utf8
    Add-Content $tmp $_ -Encoding utf8
  }
}

# Bulk ingest
$bulkUrl = "$EsUrl/_bulk?refresh=wait_for"
$response = Invoke-RestMethod -Method POST -Uri $bulkUrl -Headers $headers -InFile $tmp
if ($response.errors -eq $true) {
  Write-Host "Bulk completed with errors. Inspect response.items." -ForegroundColor Yellow
  $response.items | Select-Object -First 5 | ConvertTo-Json -Depth 6
  exit 1
}
Write-Host "Bulk ingest OK -> $Index"