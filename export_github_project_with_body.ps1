<# 
  Export GitHub Project TSV and enrich with:
  - Issue body  -> issues_with_body.csv
  - PR details + PR body (linked PRs, possibly multiple) -> 
      * issues_with_pr.csv (1 issue per row, PR fields aggregated)
      * issues_with_pr_expanded.csv (1 issue x 1 PR per row)
  使い方
  [GitHub]
  Projects > 該当の Board > 該当の View > Export view data
  ダウンロードしたファイルを
  `project_export.tsv`
  にリネームして、ルートフォルダに置く
  [PowerShell]
  `cd c:\dev\butterfly-room`
  `.\export_github_project_with_body.ps1`
#>

# ===== 設定ここだけ変更 =====
$Repo   = "officeutq/butterfly-room"  # owner/repo
$InTsv  = ".\project_export.tsv"      # Projects Export TSV
$OutIssuesBody   = ".\issues_with_body.csv"
$OutIssuesPr     = ".\issues_with_pr.csv"
$OutIssuesPrExp  = ".\issues_with_pr_expanded.csv"
$Limit = 1000
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

  # 相対パスを必ず「今の場所」を基準にした絶対パスへ
  $fullPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))

  $csvLines = $Objects | ConvertTo-Csv -NoTypeInformation
  $utf8Bom  = New-Object System.Text.UTF8Encoding($true) # BOMあり
  [System.IO.File]::WriteAllLines($fullPath, $csvLines, $utf8Bom)
}

function Get-IssueNumberFromUrl {
  param([string] $Url)
  if ($null -eq $Url) { return $null }
  if ($Url -match "/issues/(\d+)$") { return [int]$Matches[1] }
  return $null
}

function Get-PrNumberFromUrl {
  param([string] $Url)
  if ($null -eq $Url) { return $null }
  if ($Url -match "/pull/(\d+)$") { return [int]$Matches[1] }
  return $null
}

function Split-PrUrls {
  param([string] $Raw)

  if ([string]::IsNullOrWhiteSpace($Raw)) { return @() }

  # Projects export の表現揺れに対応：
  # - 改行区切り
  # - カンマ区切り
  # - スペース区切り（念のため）
  # いずれでも URL だけ抜き取る
  $urls = @()

  # まずはURLを正規表現で抽出（最も堅い）
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
  # \p{C} は「制御文字・未割当など」全般なので、改行/タブ以外を落とす
  $s = $s -replace "[\x00-\x08\x0B\x0C\x0E-\x1F]", ""
  return $s
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

# 4-A) issues_with_body.csv（Issue本文を付ける）
$issuesWithBody = foreach ($r in $rows) {
  $issueUrl = $r.URL
  $body = $null

  if ($issueUrl -and $issueByUrl.ContainsKey($issueUrl)) {
    $body = $issueByUrl[$issueUrl].body
  } else {
    $n = Get-IssueNumberFromUrl $issueUrl
    if ($n -ne $null -and $issueByNum.ContainsKey($n)) {
      $body = $issueByNum[$n].body
    }
  }

  [PSCustomObject]@{
    Title                  = $r.Title
    URL                    = $r.URL
    Assignees              = $r.Assignees
    Status                 = $r.Status
    "Linked pull requests" = $r."Linked pull requests"
    "Sub-issues progress"  = $r."Sub-issues progress"
    Labels                 = $r.Labels
    Milestone              = $r.Milestone
    "Parent issue"         = $r."Parent issue"
    Body                   = $body
  }
}

Write-CsvUtf8Bom -Path $OutIssuesBody -Objects $issuesWithBody
Write-Host "OK: wrote -> $OutIssuesBody"

# 4-B) issues_with_pr.csv（1Issue=1行、PRはまとめて）
$issuesWithPr = foreach ($r in $rows) {
  $rawPr = $r."Linked pull requests"
  $prUrls = Split-PrUrls $rawPr
  $prObjs = @($prUrls | ForEach-Object { Resolve-Pr $_ } | Where-Object { $_ -ne $null })

  # 集約（複数PRをセル内で見やすく）
  $prNumbers = ($prObjs | ForEach-Object { $_.number }) -join ","
  $prTitles  = ($prObjs | ForEach-Object { $_.title })  -join " | "
  $prStates  = ($prObjs | ForEach-Object { $_.state })  -join ","
  $prUrlsAgg = ($prObjs | ForEach-Object { $_.url })    -join ","
  $prMergedAts = ($prObjs | ForEach-Object { $_.mergedAt }) -join ","
  $prBodies  = ($prObjs | ForEach-Object { Sanitize-ForCsv $_.body }) -join "`n---`n"

  [PSCustomObject]@{
    Title                 = $r.Title
    URL                   = $r.URL
    Assignees             = $r.Assignees
    Status                = $r.Status
    Labels                = $r.Labels
    Milestone             = $r.Milestone
    "Parent issue"        = $r."Parent issue"
    "Sub-issues progress" = $r."Sub-issues progress"

    LinkedPR_Count = $prObjs.Count
    LinkedPR_Numbers = $prNumbers
    LinkedPR_URLs    = $prUrlsAgg
    LinkedPR_States  = $prStates
    LinkedPR_Titles  = $prTitles
    LinkedPR_MergedAts = $prMergedAts
    LinkedPR_Bodies  = $prBodies
  }
}

Write-CsvUtf8Bom -Path $OutIssuesPr -Objects $issuesWithPr
Write-Host "OK: wrote -> $OutIssuesPr"

# 4-C) issues_with_pr_expanded.csv（1Issue×1PR=1行で展開）
$issuesWithPrExpanded = foreach ($r in $rows) {
  $rawPr = $r."Linked pull requests"
  $prUrls = Split-PrUrls $rawPr

  if ($prUrls.Count -eq 0) {
    # PRなしの行も残したいなら1行出す（分析上便利）
    [PSCustomObject]@{
      Issue_Title   = $r.Title
      Issue_URL     = $r.URL
      Issue_Status  = $r.Status
      Issue_Labels  = $r.Labels
      Issue_Milestone = $r.Milestone
      Issue_Parent  = $r."Parent issue"
      PR_Number     = $null
      PR_Title      = $null
      PR_URL        = $null
      PR_State      = $null
      PR_MergedAt   = $null
      PR_Base       = $null
      PR_Head       = $null
      PR_Author     = $null
      PR_Labels     = $null
      PR_Body       = $null
    }
    continue
  }

  foreach ($u in $prUrls) {
    $pr = Resolve-Pr $u
    [PSCustomObject]@{
      Issue_Title     = $r.Title
      Issue_URL       = $r.URL
      Issue_Status    = $r.Status
      Issue_Labels    = $r.Labels
      Issue_Milestone = $r.Milestone
      Issue_Parent    = $r."Parent issue"

      PR_Number  = if ($pr) { $pr.number } else { Get-PrNumberFromUrl $u }
      PR_Title   = if ($pr) { $pr.title } else { $null }
      PR_URL     = $u
      PR_State   = if ($pr) { $pr.state } else { $null }
      PR_MergedAt= if ($pr) { $pr.mergedAt } else { $null }
      PR_Base    = if ($pr) { $pr.baseRefName } else { $null }
      PR_Head    = if ($pr) { $pr.headRefName } else { $null }
      PR_Author  = if ($pr) { $pr.author.login } else { $null }
      PR_Labels  = if ($pr) { ($pr.labels | ForEach-Object { $_.name }) -join "," } else { $null }
      PR_Body    = if ($pr) { Sanitize-ForCsv $pr.body } else { $null }
    }
  }
}

Write-CsvUtf8Bom -Path $OutIssuesPrExp -Objects $issuesWithPrExpanded
Write-Host "OK: wrote -> $OutIssuesPrExp"
