param(
  [Parameter(Mandatory=$true)][string]$KibanaUrl,
  [Parameter(Mandatory=$true)][string]$ApiKey,
  [string]$NdjsonPath = "dashboards/fleetfix_saved_objects.ndjson"
)

# Use curl.exe for multipart
curl.exe -sS -X POST "$KibanaUrl/api/saved_objects/_import?overwrite=true" `
  -H "kbn-xsrf: true" `
  -H "Authorization: ApiKey $ApiKey" `
  -F "file=@$NdjsonPath"