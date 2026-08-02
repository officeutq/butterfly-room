$ErrorActionPreference = "Stop"

$query = [Console]::In.ReadToEnd() | ConvertFrom-Json
if ($query.profile -ne "butterfly-room-staging" -or $query.region -ne "ap-northeast-1") {
  throw "The listener check only permits the staging profile in ap-northeast-1."
}

$json = aws elbv2 describe-rules `
  --listener-arn $query.listener_arn `
  --profile $query.profile `
  --region $query.region `
  --no-cli-pager `
  --output json

if ($LASTEXITCODE -ne 0) {
  throw "Unable to inspect listener rules with the configured staging profile."
}

$rules = ($json | ConvertFrom-Json).Rules
$occupied = $rules | Where-Object { $_.Priority -eq [string]$query.priority }
$sameHost = $false

foreach ($rule in $occupied) {
  foreach ($condition in $rule.Conditions) {
    if ($condition.Field -eq "host-header" -and $condition.Values -contains $query.hostname) {
      $sameHost = $true
    }
  }
}

$available = ($null -eq $occupied) -or $sameHost
@{
  available = $available.ToString().ToLowerInvariant()
  priority  = [string]$query.priority
} | ConvertTo-Json -Compress
