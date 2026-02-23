param(
  [string]$OutDir = "data",
  [switch]$Overwrite
)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$outPath = Join-Path $OutDir "fleetfix_runbooks.ndjson"

if ((Test-Path $outPath) -and (-not $Overwrite)) {
  Write-Host "Runbooks already exist: $outPath (use -Overwrite to regenerate)" -ForegroundColor Yellow
  exit 0
}

$nowIso = (Get-Date).ToUniversalTime().ToString("o")

# Keep runbooks small + high-signal. These are the “KB” docs the agent retrieves.
$runbooks = @(
  @{
    signature="context_canceled"
    title="Enroll fails with context canceled"
    root_causes="Fleet Server unreachable; proxy misconfig; DNS failure; policy fetch timeout."
    fix_steps="1) Verify Fleet Server URL reachable from host`n2) Check proxy environment variables`n3) Validate DNS resolution`n4) Confirm firewall allows outbound traffic`n5) Re-enroll agent with correct flags"
    verify_steps="Confirm agent becomes Healthy`nConfirm no 'context canceled' in latest logs`nCheck policy ack succeeds"
    tags=@("enroll","network","timeout")
    updated_at=$nowIso
  },
  @{
    signature="badrequest_400"
    title="400 BadRequest during enroll"
    root_causes="Wrong enrollment token/API key; malformed URL; mixed Kibana vs Fleet URL."
    fix_steps="1) Regenerate enrollment token`n2) Confirm Fleet URL matches deployment endpoint`n3) Retry enroll with correct token and URL"
    verify_steps="Enroll completes with no 400 errors`nPolicy is applied successfully"
    tags=@("auth","enroll")
    updated_at=$nowIso
  },
  @{
    signature="x509_unknown_authority"
    title="x509: certificate signed by unknown authority"
    root_causes="Custom CA not trusted; TLS interception; incomplete certificate chain."
    fix_steps="1) Install CA certificate into OS trust store`n2) Configure agent with correct CA path`n3) Re-test TLS handshake to Fleet endpoint"
    verify_steps="TLS errors disappear`nEnroll succeeds and policy acks"
    tags=@("tls","cert")
    updated_at=$nowIso
  },
  @{
    signature="stuck_updating"
    title="Agent stuck in Updating"
    root_causes="Blocked artifact registry; slow downloads; policy loop; disk pressure."
    fix_steps="1) Check connectivity to artifact registry`n2) Restart elastic-agent service`n3) Ensure enough disk space`n4) Retry update`n5) Re-enroll if state is unrecoverable"
    verify_steps="Agent transitions to Healthy`nVersion and policy match expected"
    tags=@("upgrade","artifact")
    updated_at=$nowIso
  },
  @{
    signature="permission_denied"
    title="Permission denied / forbidden"
    root_causes="Insufficient privileges for enrollment token; wrong role assignments."
    fix_steps="1) Validate API key/enrollment token permissions`n2) Ensure Fleet and Agent privileges are correct`n3) Recreate token and re-enroll"
    verify_steps="No more forbidden errors`nEnroll + policy ack succeed"
    tags=@("auth","rbac")
    updated_at=$nowIso
  },
  @{
    signature="endpoint_unreachable"
    title="Fleet endpoint unreachable"
    root_causes="Firewall blocks; wrong port; proxy/DNS issues; intermittent network."
    fix_steps="1) Test connectivity (curl) to Fleet endpoint`n2) Open firewall rules`n3) Fix DNS / proxy configuration`n4) Retry enroll"
    verify_steps="Connectivity OK`nEnroll completes"
    tags=@("network")
    updated_at=$nowIso
  },
  @{
    signature="policy_parse_error"
    title="Policy parse error"
    root_causes="Corrupt policy payload; invalid YAML/JSON; incompatible integration config."
    fix_steps="1) Roll back last policy edit`n2) Validate integration settings`n3) Re-apply changes incrementally"
    verify_steps="Policy fetch succeeds`nAgent acknowledges policy"
    tags=@("policy")
    updated_at=$nowIso
  },
  @{
    signature="policy_timeout"
    title="Policy fetch timed out"
    root_causes="Fleet Server overloaded; network instability; proxy timeout."
    fix_steps="1) Check Fleet Server health and logs`n2) Reduce load / scale Fleet Server`n3) Increase proxy timeouts if applicable`n4) Retry enroll"
    verify_steps="Policy fetch succeeds within expected time`nAgent remains Healthy"
    tags=@("fleet-server","timeout")
    updated_at=$nowIso
  }
)

# Write NDJSON (one compact JSON object per line)
"" | Out-File $outPath -Encoding utf8
foreach ($rb in $runbooks) {
  ($rb | ConvertTo-Json -Compress) | Add-Content -Path $outPath -Encoding utf8
}

Write-Host "Generated runbooks -> $outPath"