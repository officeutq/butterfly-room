<# 
  Export GitHub Project TSV and enrich for LLM usage (ChatGPT貼り付け最適化)

  出力：
  1) issues_with_body.csv
     - Issue仕様の正本（Issue Bodyあり）
     - できるだけ「仕様理解」に必要なものだけ

  2) issues_with_pr.csv
     - 進捗索引（軽量）
     - PR本文は入れない（expanded に寄せる）

  3) issues_with_pr_expanded.csv
     - 1 Issue x 1 PR で展開（分析/レビュー用）
     - PR本文は「抜粋（Excerpt）」を基本（全文は必要な時だけ切替）

  使い方：
  [GitHub]
    Projects > 該当の Board > 該当の View > Export view data
    ダウンロードしたファイルを project_export.tsv にリネームしてルートへ置く
  [PowerShell]
    cd c:\dev\butterfly-room
    .\export_github_project_with_body.ps1
#>

# ===== 設定ここだけ変更 =====
$Repo   = "officeutq/butterfly-room"  # owner/repo
$InTsv  = ".\project_export.tsv"      # Projects Export TSV

$OutIssuesBody   = ".\issues_with_body.csv"
$OutIssuesPr     = ".\issues_with_pr.csv"
$OutIssuesPrExp  = ".\issues_with_pr_expanded.csv"

$Limit = 1000

# PR本文の扱い（LLM向けデフォルトは excerpt）
# - "excerpt" : 抜粋のみ（おすすめ）
# - "full"    : 全文（重い。必要な時だけ）
$PrBodyMode = "full"

# 抜粋の最大文字数（excerpt時）
$PrBodyExcerptMax = 600
# ===========================

# --- 文字化け対策（Windows PowerShell 5.1でも gh のUTF-8出力を受けやすくする）---
chcp 65001 | Out-Null
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding           = [System.Text.UTF8Encoding]::new()
# -------------------------------------------------------------------------------

function Write-CsvUtf8Bom {
  param(
    [Parameter(Mandatory=$true)] [string] $Path,
    [Parameter(Mandatory=$true)] $Objects
  )

  $fullPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
  $csvLines = $Objects | ConvertTo-Csv -NoTypeInformation
  $utf8Bom  = New-Object System.Text.UTF8Encoding($true) # BOMあり
  [System.IO.File]::WriteAllLines($fullPath, $csvLines, $utf8Bom)
}

function Get-IssueNumberFromUrl {
  param([string] $Url)
  if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
  if ($Url -match "/issues/(\d+)$") { return [int]$Matches[1] }
  return $null
}

function Get-PrNumberFromUrl {
  param([string] $Url)
  if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
  if ($Url -match "/pull/(\d+)$") { return [int]$Matches[1] }
  return $null
}

function Split-PrUrls {
  param([string] $Raw)
  if ([string]::IsNullOrWhiteSpace($Raw)) { return @() }

  $urls = @()
  $matches = [regex]::Matches($Raw, "https://github\.com/[^/\s]+/[^/\s]+/pull/\d+")
  foreach ($m in $matches) { $urls += $m.Value }

  # 重複除去・順序維持
  $seen = @{}
  $uniq = foreach ($u in $urls) {
    if (-not $seen.ContainsKey($u)) { $seen[$u] = $true; $u }
  }
  return @($uniq)
}

function Sanitize-ForCsv {
  param([string] $s)
  if ($null -eq $s) { return $null }
  # NUL などの制御文字を除去（改行とタブは残す）
  $s = $s -replace "[\x00-\x08\x0B\x0C\x0E-\x1F]", ""
  return $s
}

function Get-BodyExcerpt {
  param([string] $Body, [int] $MaxChars)
  if ([string]::IsNullOrWhiteSpace($Body)) { return $null }
  $b = Sanitize-ForCsv $Body
  $b = $b.Trim()
  if ($b.Length -le $MaxChars) { return $b }
  return $b.Substring(0, $MaxChars) + "…"
}

function Get-TextSha256 {
  param([string] $Text)
  if ($null -eq $Text) { return $null }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $hash = $sha.ComputeHash($bytes)
  return ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
}

function Get-ParentIssueNumberFromAny {
  param([string] $Raw)
  if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }

  # 1) URL形式
  if ($Raw -match "https://github\.com/[^/\s]+/[^/\s]+/issues/(\d+)") { return [int]$Matches[1] }
  # 2) #123 形式
  if ($Raw -match "#(\d+)") { return [int]$Matches[1] }

  return $null
}

# 1) TSV 読み込み
if (!(Test-Path $InTsv)) {
  throw "TSV が見つかりません: $InTsv"
}
$rows = Import-Csv -Path $InTsv -Delimiter "`t"

# 2) Issue 一覧（本文込み）を取得して辞書化
$tmpIssuesJson = Join-Path $PSScriptRoot "_issues.json"
gh issue list --repo $Repo --state all --limit $Limit --json number,title,url,body `
  | Set-Content -Path $tmpIssuesJson -Encoding utf8
$issues = Get-Content -Path $tmpIssuesJson -Raw -Encoding utf8 | ConvertFrom-Json

$issueByUrl = @{}
$issueByNum = @{}
foreach ($i in $issues) {
  if ($i.url)    { $issueByUrl[$i.url] = $i }
  if ($i.number) { $issueByNum[[int]$i.number] = $i }
}

# 3) PR 一覧（本文込み）を取得して辞書化
$tmpPrsJson = Join-Path $PSScriptRoot "_prs.json"
gh pr list --repo $Repo --state all --limit $Limit --json number,title,url,state,isDraft,createdAt,mergedAt,baseRefName,headRefName,author,assignees,labels,body `
  | Set-Content -Path $tmpPrsJson -Encoding utf8
$prs = Get-Content -Path $tmpPrsJson -Raw -Encoding utf8 | ConvertFrom-Json

$prByUrl = @{}
$prByNum = @{}
foreach ($p in $prs) {
  if ($p.url)    { $prByUrl[$p.url] = $p }
  if ($p.number) { $prByNum[[int]$p.number] = $p }
}

function Resolve-Pr {
  param([string] $PrUrl)
  if ([string]::IsNullOrWhiteSpace($PrUrl)) { return $null }
  if ($prByUrl.ContainsKey($PrUrl)) { return $prByUrl[$PrUrl] }

  $pn = Get-PrNumberFromUrl $PrUrl
  if ($pn -ne $null -and $prByNum.ContainsKey($pn)) { return $prByNum[$pn] }
  return $null
}

function Resolve-IssueBody {
  param([string] $IssueUrl)
  if ([string]::IsNullOrWhiteSpace($IssueUrl)) { return $null }

  if ($issueByUrl.ContainsKey($IssueUrl)) { return $issueByUrl[$IssueUrl].body }
  $n = Get-IssueNumberFromUrl $IssueUrl
  if ($n -ne $null -and $issueByNum.ContainsKey($n)) { return $issueByNum[$n].body }

  return $null
}

# -----------------------------
# 4-A) issues_with_body.csv（Issue仕様の正本）
# -----------------------------
$issuesWithBody = foreach ($r in $rows) {
  $issueUrl = $r.URL
  $issueNum = Get-IssueNumberFromUrl $issueUrl
  $parentNum = Get-ParentIssueNumberFromAny $r."Parent issue"
  $body = Resolve-IssueBody $issueUrl

  [PSCustomObject]@{
    Issue_Number            = $issueNum
    Title                   = $r.Title
    URL                     = $r.URL
    Status                  = $r.Status
    Labels                  = $r.Labels
    Milestone               = $r.Milestone
    Parent_Issue_Number     = $parentNum
    Parent_Issue_Raw        = $r."Parent issue"
    "Sub-issues progress"   = $r."Sub-issues progress"
    Body                    = $body
  }
}

Write-CsvUtf8Bom -Path $OutIssuesBody -Objects $issuesWithBody
Write-Host "OK: wrote -> $OutIssuesBody"

# -----------------------------
# 4-B) issues_with_pr.csv（LLM用：軽量索引。PR本文は入れない）
# -----------------------------
$issuesWithPr = foreach ($r in $rows) {
  $issueUrl = $r.URL
  $issueNum = Get-IssueNumberFromUrl $issueUrl
  $parentNum = Get-ParentIssueNumberFromAny $r."Parent issue"

  $rawPr = $r."Linked pull requests"
  $prUrls = Split-PrUrls $rawPr
  $prObjs = @($prUrls | ForEach-Object { Resolve-Pr $_ } | Where-Object { $_ -ne $null })

  # mergedAtで新しい順（nullは後ろ）
  $prObjsSorted = $prObjs | Sort-Object `
    @{ Expression = { if ($_.mergedAt) { [DateTime]$_.mergedAt } else { [DateTime]"1900-01-01" } }; Descending = $true }

  $prNumbers = ($prObjsSorted | ForEach-Object { $_.number }) -join ","
  $prTitles  = ($prObjsSorted | ForEach-Object { $_.title })  -join " | "
  $prStates  = ($prObjsSorted | ForEach-Object { $_.state })  -join ","
  $prUrlsAgg = ($prObjsSorted | ForEach-Object { $_.url })    -join ","
  $prMergedAts = ($prObjsSorted | ForEach-Object { $_.mergedAt }) -join ","

  $latestPr = $prObjsSorted | Select-Object -First 1

  [PSCustomObject]@{
    Issue_Number          = $issueNum
    Title                 = $r.Title
    URL                   = $r.URL
    Status                = $r.Status
    Labels                = $r.Labels
    Milestone             = $r.Milestone
    Parent_Issue_Number   = $parentNum
    "Sub-issues progress" = $r."Sub-issues progress"

    LinkedPR_Count        = $prObjsSorted.Count
    LinkedPR_Numbers      = $prNumbers
    LinkedPR_URLs         = $prUrlsAgg
    LinkedPR_States       = $prStates
    LinkedPR_Titles       = $prTitles
    LinkedPR_MergedAts    = $prMergedAts

    LatestPR_Number       = if ($latestPr) { $latestPr.number } else { $null }
    LatestPR_State        = if ($latestPr) { $latestPr.state } else { $null }
    LatestPR_MergedAt     = if ($latestPr) { $latestPr.mergedAt } else { $null }
  }
}

Write-CsvUtf8Bom -Path $OutIssuesPr -Objects $issuesWithPr
Write-Host "OK: wrote -> $OutIssuesPr"

# -----------------------------
# 4-C) issues_with_pr_expanded.csv（LLM用：PR本文はここに集約）
# -----------------------------
$issuesWithPrExpanded = foreach ($r in $rows) {
  $issueUrl = $r.URL
  $issueNum = Get-IssueNumberFromUrl $issueUrl
  $parentNum = Get-ParentIssueNumberFromAny $r."Parent issue"

  $rawPr = $r."Linked pull requests"
  $prUrls = Split-PrUrls $rawPr

  if ($prUrls.Count -eq 0) {
    # PRなしの行も残す（進捗チェックに便利）
    [PSCustomObject]@{
      Issue_Number        = $issueNum
      Issue_Title         = $r.Title
      Issue_URL           = $r.URL
      Issue_Status        = $r.Status
      Issue_Labels        = $r.Labels
      Issue_Milestone     = $r.Milestone
      Parent_Issue_Number = $parentNum

      PR_Number           = $null
      PR_Title            = $null
      PR_URL              = $null
      PR_State            = $null
      PR_MergedAt         = $null
      PR_Base             = $null
      PR_Head             = $null
      PR_Author           = $null
      PR_Labels           = $null

      PR_Body_Length      = $null
      PR_Body_Hash        = $null
      PR_Body_Excerpt     = $null
      PR_Body_Full        = $null
    }
    continue
  }

  foreach ($u in $prUrls) {
    $pr = Resolve-Pr $u

    $bodyFull = $null
    $bodyExcerpt = $null
    $bodyLen = $null
    $bodyHash = $null

    if ($pr) {
      $b = Sanitize-ForCsv $pr.body
      $bodyLen  = if ($b) { $b.Length } else { 0 }
      $bodyHash = if ($b) { Get-TextSha256 $b } else { $null }

      if ($PrBodyMode -eq "full") {
        $bodyFull = $b
        $bodyExcerpt = Get-BodyExcerpt -Body $b -MaxChars $PrBodyExcerptMax
      } else {
        $bodyExcerpt = Get-BodyExcerpt -Body $b -MaxChars $PrBodyExcerptMax
      }
    }

    [PSCustomObject]@{
      Issue_Number        = $issueNum
      Issue_Title         = $r.Title
      Issue_URL           = $r.URL
      Issue_Status        = $r.Status
      Issue_Labels        = $r.Labels
      Issue_Milestone     = $r.Milestone
      Parent_Issue_Number = $parentNum

      PR_Number  = if ($pr) { $pr.number } else { Get-PrNumberFromUrl $u }
      PR_Title   = if ($pr) { $pr.title } else { $null }
      PR_URL     = $u
      PR_State   = if ($pr) { $pr.state } else { $null }
      PR_MergedAt= if ($pr) { $pr.mergedAt } else { $null }
      PR_Base    = if ($pr) { $pr.baseRefName } else { $null }
      PR_Head    = if ($pr) { $pr.headRefName } else { $null }
      PR_Author  = if ($pr) { $pr.author.login } else { $null }
      PR_Labels  = if ($pr) { ($pr.labels | ForEach-Object { $_.name }) -join "," } else { $null }

      PR_Body_Length  = $bodyLen
      PR_Body_Hash    = $bodyHash
      PR_Body_Excerpt = $bodyExcerpt
      PR_Body_Full    = $bodyFull  # fullモード以外はnull
    }
  }
}

Write-CsvUtf8Bom -Path $OutIssuesPrExp -Objects $issuesWithPrExpanded
Write-Host "OK: wrote -> $OutIssuesPrExp"
