param(
  [int]$LogCount = 5000,
  [int]$HostCount = 25,
  [string]$OutDir = "data"
)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$signatures = @(
  @{ sig="context_canceled"; msg="enroll failed: context canceled after waiting for policy" },
  @{ sig="badrequest_400"; msg="status 400 BadRequest: invalid API key format" },
  @{ sig="x509_unknown_authority"; msg="x509: certificate signed by unknown authority" },
  @{ sig="stuck_updating"; msg="agent stuck in Updating state for > 20 minutes" },
  @{ sig="permission_denied"; msg="action forbidden: insufficient privileges" },
  @{ sig="endpoint_unreachable"; msg="cannot reach fleet server: dial tcp timeout" },
  @{ sig="policy_parse_error"; msg="failed parsing policy: unexpected token" },
  @{ sig="policy_timeout"; msg="policy fetch timed out" }
)

$hosts = 1..$HostCount | ForEach-Object { "win-agent-{0:D2}" -f $_ }
$now = Get-Date
$start = $now.AddDays(-30)

$logPath = Join-Path $OutDir "fleetfix_logs.ndjson"
"" | Out-File $logPath -Encoding utf8

for ($i=0; $i -lt $LogCount; $i++) {
  $sigObj = $signatures | Get-Random
  $host1 = $hosts | Get-Random
  $ts = $start.AddSeconds((Get-Random -Minimum 0 -Maximum ([int]($now-$start).TotalSeconds)))
  $iso = $ts.ToUniversalTime().ToString("o")

  $doc = @{
    "@timestamp" = $iso
    "log.level" = @("error","warn") | Get-Random
    "host.name" = $host1
    "agent.id" = "a-{0:D2}" -f ([int]($host1.Split("-")[-1]))
    "service.name" = @("elastic-agent","fleet-server") | Get-Random
    "event.dataset" = @("elastic_agent","fleet_server") | Get-Random
    "error.signature" = $sigObj.sig
    "message" = $sigObj.msg
  } | ConvertTo-Json -Compress

  Add-Content -Path $logPath -Value $doc -Encoding utf8
}

Write-Host "Generated $LogCount logs -> $logPath"