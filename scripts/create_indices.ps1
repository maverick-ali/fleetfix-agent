param(
  [Parameter(Mandatory=$true)][string]$EsUrl,
  [Parameter(Mandatory=$true)][string]$ApiKey
)

$headers = @{
  Authorization = "ApiKey $ApiKey"
  "Content-Type" = "application/json"
}

function Index-Exists($indexName) {
  try {
    Invoke-WebRequest -Method HEAD -Uri "$EsUrl/$indexName" -Headers @{ Authorization = "ApiKey $ApiKey" } -UseBasicParsing | Out-Null
    return $true
  } catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) { return $false }
    throw
  }
}

function Create-Index($indexName, $bodyObj) {
  if (Index-Exists $indexName) {
    Write-Host "Index exists, skipping: $indexName" -ForegroundColor Yellow
    return
  }
  $json = $bodyObj | ConvertTo-Json -Depth 50
  Invoke-RestMethod -Method PUT -Uri "$EsUrl/$indexName" -Headers $headers -Body $json | Out-Null
  Write-Host "Created index: $indexName" -ForegroundColor Green
}

Create-Index "fleetfix_logs" @{
  mappings = @{
    properties = @{
      "@timestamp" = @{ type="date" }
      "message" = @{ type="text" }
      "log.level" = @{ type="keyword" }
      "host.name" = @{ type="keyword" }
      "agent.id" = @{ type="keyword" }
      "service.name" = @{ type="keyword" }
      "event.dataset" = @{ type="keyword" }
      "error.signature" = @{ type="keyword" }
    }
  }
}

Create-Index "fleetfix_runbooks" @{
  mappings = @{
    properties = @{
      "signature" = @{ type="keyword" }
      "title" = @{ type="text" }
      "root_causes" = @{ type="text" }
      "fix_steps" = @{ type="text" }
      "verify_steps" = @{ type="text" }
      "tags" = @{ type="keyword" }
      "updated_at" = @{ type="date" }
    }
  }
}

Create-Index "fleetfix_tickets" @{
  mappings = @{
    properties = @{
      "created_at" = @{ type="date" }
      "title" = @{ type="text" }
      "severity" = @{ type="keyword" }
      "signature" = @{ type="keyword" }
      "status" = @{ type="keyword" }
      "recommended_steps" = @{ type="text" }
      "raw_log_sample" = @{ type="text" }
      "host.name" = @{ type="keyword" }
    }
  }
}