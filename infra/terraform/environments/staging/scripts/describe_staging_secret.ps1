$ErrorActionPreference = "Stop"

$query = [Console]::In.ReadToEnd() | ConvertFrom-Json
if ($query.profile -ne "butterfly-room-staging" -or $query.region -ne "ap-northeast-1") {
  throw "The secret lookup only permits the staging profile in ap-northeast-1."
}

if ([string]::IsNullOrWhiteSpace($query.secret_name) -or -not $query.secret_name.StartsWith("butterflyve/staging/")) {
  throw "The secret lookup only permits a name under butterflyve/staging/."
}

$json = aws secretsmanager describe-secret `
  --secret-id $query.secret_name `
  --profile $query.profile `
  --region $query.region `
  --query "{arn:ARN,name:Name}" `
  --no-cli-pager `
  --output json

if ($LASTEXITCODE -ne 0) {
  throw "Unable to inspect the configured staging secret."
}

$secret = $json | ConvertFrom-Json
if ($secret.name -ne $query.secret_name -or [string]::IsNullOrWhiteSpace($secret.arn)) {
  throw "The configured staging secret did not resolve to the expected name and ARN."
}

@{
  arn  = [string]$secret.arn
  name = [string]$secret.name
} | ConvertTo-Json -Compress
