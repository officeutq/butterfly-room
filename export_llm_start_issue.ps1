<# 
  export_llm_start_issue.ps1
  新しくIssueに着手する際の「新スレッド開始用」LLM貼り付けテキストを生成する。

  含めるもの：
  1) 対象Issue（Bodyフル）
  2) 親Epic（あれば）
  3) 兄弟Issueのうち PR MERGED 済みのもの
  4) 対象Issue本文に明示された関連Issue（#123 等）

  CSV生成（今まで通り）
  .\export_github_project_with_body.ps1

  新規着手Issueの「新スレッド開始用」をコピー
  .\export_llm_start_issue.ps1 -IssueNumber 128 -ToClipboard
#>

param(
  [Parameter(Mandatory=$true)]
  [int]$IssueNumber,

  [string]$IssuesBodyPath = ".\issues_with_body.csv",
  [string]$IssuesPrPath   = ".\issues_with_pr.csv",
  [string]$IssuesPrExpPath= ".\issues_with_pr_expanded.csv",
  [string]$Repo = "officeutq/butterfly-room",
  # Epic / 関連Issueの本文は長くなりがちなので抜粋にするならここで調整
  [int]$EpicBodyMaxChars     = 2000,
  [int]$RelatedBodyMaxChars  = 1200,

  # 兄弟Issueの列挙上限（多すぎると読めないので）
  [int]$MaxSiblingMerged     = 20,

  [switch]$ToClipboard
)

function Require-File([string]$Path) {
  if (!(Test-Path $Path)) { throw ("File not found: " + $Path) }
}

function Truncate([string]$s, [int]$max) {
  if ($null -eq $s) { return $null }
  $t = $s.Trim()
  if ($t.Length -le $max) { return $t }
  return $t.Substring(0, $max) + "..."
}

function CsvRowToSingleLineCsv([object]$Row, [string[]]$Columns) {
  $obj = [PSCustomObject]@{}
  foreach ($c in $Columns) { $obj | Add-Member -NotePropertyName $c -NotePropertyValue ($Row.$c) }
  ($obj | ConvertTo-Csv -NoTypeInformation) -join "`n"
}

function Extract-IssueNumbersFromText([string]$text) {
  if ([string]::IsNullOrWhiteSpace($text)) { return @() }
  $matches = [regex]::Matches($text, "(?<![A-Za-z0-9])#(\d+)")
  $nums = @()
  foreach ($m in $matches) { $nums += [int]$m.Groups[1].Value }
  # 重複除去・順序維持
  $seen = @{}
  $uniq = foreach ($n in $nums) { if (-not $seen.ContainsKey($n)) { $seen[$n] = $true; $n } }
  return @($uniq)
}

function Fetch-IssueViaGh([int]$Number, [int]$BodyMaxChars) {
  # Projects(CSV)に無い古いIssueでも、gh issue view なら取れる
  $json = gh issue view $Number --repo $Repo --json number,title,body,labels,milestone,url | Out-String
  $obj  = $json | ConvertFrom-Json

  $labels = $null
  if ($obj.labels) { $labels = ($obj.labels | ForEach-Object { $_.name }) -join "," }

  $milestone = $null
  if ($obj.milestone) { $milestone = $obj.milestone.title }

  $body = Truncate $obj.body $BodyMaxChars

  # CSV行と似た形にして後段の出力を共通化する
  return [PSCustomObject]@{
    Issue_Number        = [int]$obj.number
    Title               = $obj.title
    Labels              = $labels
    Milestone           = $milestone
    Parent_Issue_Number = $null   # Projects外なので不明（必要なら後で拡張）
    Body                = $obj.body
    Body_Excerpt         = $body
    URL                 = $obj.url
    _source             = "gh"    # デバッグ用（任意）
  }
}

Require-File $IssuesBodyPath
Require-File $IssuesPrPath
Require-File $IssuesPrExpPath

$bodyRows = Import-Csv $IssuesBodyPath
$prRows   = Import-Csv $IssuesPrPath
$prExpRows= Import-Csv $IssuesPrExpPath

# 対象Issue
$target = $bodyRows | Where-Object { [int]$_.Issue_Number -eq $IssueNumber } | Select-Object -First 1
if ($null -eq $target) { throw ("Issue not found: Issue_Number=" + $IssueNumber) }

# 親Epic
$parentNum = $null
if (-not [string]::IsNullOrWhiteSpace($target.Parent_Issue_Number)) {
  $parentNum = [int]$target.Parent_Issue_Number
}
$parent = $null
if ($parentNum) {
  $parent = $bodyRows | Where-Object { [int]$_.Issue_Number -eq $parentNum } | Select-Object -First 1
}

# 対象IssueのPRサマリ
$targetPr = $prRows | Where-Object { [int]$_.Issue_Number -eq $IssueNumber } | Select-Object -First 1

# 兄弟Issue（同じParent_Issue_Number）で PR MERGED 済み
$siblingsMerged = @()
if ($parentNum) {
  $siblings = $prRows | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_.Parent_Issue_Number) -and
    ([int]$_.Parent_Issue_Number -eq $parentNum) -and
    ([int]$_.Issue_Number -ne $IssueNumber)
  }

  # MERGED判定：LatestPR_State が "MERGED"（あなたの既存CSVの前提）
  $siblingsMerged = $siblings | Where-Object {
    ($_.LatestPR_State -eq "MERGED") -or ($_.LatestPR_State -eq "merged") # 念のため
  } | Sort-Object {
    # MergedAt 新しい順（空は後ろ）
    if ($_.LatestPR_MergedAt) { [DateTime]$_.LatestPR_MergedAt } else { [DateTime]"1900-01-01" }
  } -Descending | Select-Object -First $MaxSiblingMerged
}

# 関連Issue（対象Issue本文に明示されている #番号）
$mentionedNums = Extract-IssueNumbersFromText $target.Body

# 除外（自分、親、兄弟一覧に含まれるもの）
$exclude = New-Object System.Collections.Generic.HashSet[int]
$exclude.Add($IssueNumber) | Out-Null
if ($parentNum) { $exclude.Add($parentNum) | Out-Null }
foreach ($s in $siblingsMerged) { $exclude.Add([int]$s.Issue_Number) | Out-Null }

$relatedNums = @()
foreach ($n in $mentionedNums) {
  if (-not $exclude.Contains($n)) { $relatedNums += $n }
}

$relatedIssues = @()
foreach ($n in $relatedNums) {
  $row = $bodyRows | Where-Object { [int]$_.Issue_Number -eq $n } | Select-Object -First 1
  if ($row) {
    # CSVにあるものはそのまま（Bodyはフル、excerptは出力時にtruncate）
    $relatedIssues += $row
  } else {
    # CSVに無いもの（Projectsに載ってない古いIssue等）は gh で補完
    try {
      $relatedIssues += Fetch-IssueViaGh -Number $n -BodyMaxChars $RelatedBodyMaxChars
    } catch {
      # 取れない場合でも番号だけは残す（出力が破綻しないように）
      $relatedIssues += [PSCustomObject]@{
        Issue_Number        = $n
        Title               = "(not found via CSV/gh)"
        Labels              = $null
        Milestone           = $null
        Parent_Issue_Number = $null
        Body                = $null
        Body_Excerpt         = $null
        URL                 = $null
      }
    }
  }
}

# 出力組み立て
$sb = New-Object System.Text.StringBuilder

$null = $sb.AppendLine("LLM START CONTEXT (new issue)")
$null = $sb.AppendLine(("TARGET Issue_Number: {0}" -f $IssueNumber))
$null = $sb.AppendLine(("Title: {0}" -f $target.Title))
if ($parentNum) { $null = $sb.AppendLine(("Parent Epic: #{0}" -f $parentNum)) }
$null = $sb.AppendLine("")

# 1) 対象Issue（正本）
$null = $sb.AppendLine("SECTION 1: Target Issue (spec source of truth)")
$colsBody = @("Issue_Number","Title","Labels","Milestone","Parent_Issue_Number","Body")
$null = $sb.AppendLine((CsvRowToSingleLineCsv -Row $target -Columns $colsBody))
$null = $sb.AppendLine("")

# 2) 親Epic
if ($parent) {
  $null = $sb.AppendLine("SECTION 2: Parent Epic (context)")
  $epicBody = Truncate $parent.Body $EpicBodyMaxChars
  $epicObj = [PSCustomObject]@{
    Issue_Number = $parent.Issue_Number
    Title = $parent.Title
    Labels = $parent.Labels
    Milestone = $parent.Milestone
    Body_Excerpt = $epicBody
  }
  $null = $sb.AppendLine((($epicObj | ConvertTo-Csv -NoTypeInformation) -join "`n"))
  $null = $sb.AppendLine("")
}

# 3) 兄弟Issue（PR済）
# SECTION 3 用に LatestPR_URL を生成して付与（issues_with_pr.csv には LatestPR_URL 列が無いので）
foreach ($s in $siblingsMerged) {
  $latestNum = $s.LatestPR_Number
  $url = $null

  if (-not [string]::IsNullOrWhiteSpace($latestNum) -and -not [string]::IsNullOrWhiteSpace($s.LinkedPR_URLs)) {
    $candidates = $s.LinkedPR_URLs -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($u in $candidates) {
      if ($u -match "/pull/$latestNum$") { $url = $u; break }
    }
    if (-not $url -and $candidates.Count -gt 0) { $url = $candidates[0] } # フォールバック
  }

  # 既存オブジェクトに列を生やす
  $s | Add-Member -NotePropertyName "LatestPR_URL" -NotePropertyValue $url -Force
}

if (@($siblingsMerged).Count -gt 0) {
  $null = $sb.AppendLine("SECTION 3: Sibling Issues already merged (reference implementation; PR URL is for human reference)")
  $colsSibling = @("Issue_Number","Title","Status","Labels","Milestone","LatestPR_Number","LatestPR_URL","LatestPR_State","LatestPR_MergedAt")
  $export = $siblingsMerged | Select-Object $colsSibling
  $null = $sb.AppendLine((($export | ConvertTo-Csv -NoTypeInformation) -join "`n"))
  $null = $sb.AppendLine("")
}

# 4) 関連Issue（本文で明示）
if (@($relatedIssues).Count -gt 0) {
  $null = $sb.AppendLine("SECTION 4: Related Issues explicitly mentioned in the body (#nnn)")
  $relExport = @()
  foreach ($ri in $relatedIssues) {
    # CSV行は Body を持つ。gh補完行は Body_Excerpt を持たせているので、あれば優先する
    $excerpt = $null
    if ($ri.PSObject.Properties.Name -contains "Body_Excerpt" -and -not [string]::IsNullOrWhiteSpace($ri.Body_Excerpt)) {
      $excerpt = $ri.Body_Excerpt
    } else {
      $excerpt = Truncate $ri.Body $RelatedBodyMaxChars
    }

    $relExport += [PSCustomObject]@{
      Issue_Number        = $ri.Issue_Number
      Title               = $ri.Title
      Labels              = $ri.Labels
      Milestone           = $ri.Milestone
      Parent_Issue_Number = $ri.Parent_Issue_Number
      Body_Excerpt        = $excerpt
    }
  }
  $null = $sb.AppendLine((($relExport | ConvertTo-Csv -NoTypeInformation) -join "`n"))
  $null = $sb.AppendLine("")
}

# LLMへの指示（新規着手専用）
# - SECTION 1 を「仕様の正本」として扱わせる
# - SECTION 2（親Epic）でスコープ暴走を防ぐ
# - SECTION 3（兄弟MERGED）で既存実装パターンに寄せる
# - SECTION 4（関連Issue）で依存・重複・衝突を避ける
# - さらに「ブランチ名候補」「貼り付け対象ファイル一覧」「貼り付け用コード」を必ず出させる
$null = $sb.AppendLine("INSTRUCTIONS TO LLM")
# 仕様→タスク分解→実装順の決定
$null = $sb.AppendLine("1) Read SECTION 1 as the source of truth. Extract tasks + Done criteria and order them.")
# Epicの目的に沿わせ、やりすぎ（過剰実装）を防ぐ
$null = $sb.AppendLine("2) Use SECTION 2 (Epic) to align scope/priority and avoid over-implementation.")
# 既にマージされた兄弟Issueの実装パターン（命名・責務・構造）に合わせる
$null = $sb.AppendLine("3) Use SECTION 3 (merged siblings) to match existing patterns, naming, and architecture.")
$null = $sb.AppendLine("   - Note: PR URL in SECTION 3 is for human reference only (LLM cannot open it).")
# 本文で明示された関連Issueの整合（依存・重複・衝突）を考慮する
$null = $sb.AppendLine("4) If SECTION 4 exists, use it (related) to avoid conflicts/duplication and respect dependencies.")
$null = $sb.AppendLine("")
# ブランチ名候補（Issue番号込み、prefixは improve/ feature/ fix/ chore/ を優先）
$null = $sb.AppendLine("5) Propose Git branch name candidates (3-5) using this repo conventions.")
$null = $sb.AppendLine("   - Prefer prefixes: improve/, feature/, fix/, chore/")
$null = $sb.AppendLine("   - Include the Issue number (e.g. improve/80-video-resolution)")
$null = $sb.AppendLine("")
# 実装で「中身を貼る」可能性が高いファイル一覧をA/B/Cで分類してチェックリスト化
$null = $sb.AppendLine("6) Provide a checklist of file paths to edit/create for implementation.")
$null = $sb.AppendLine("   - Group by: (A) must edit/create, (B) likely, (C) optional")
$null = $sb.AppendLine("   - For each file: explain WHY it changes and WHAT to paste/change (1-2 lines).")
$null = $sb.AppendLine("")
# (A)必須ファイルは、貼り付け可能なコードブロックを出す（全体 or 最小差分 + 挿入位置）
$null = $sb.AppendLine("7) For (A) must files, output paste-ready code blocks.")
$null = $sb.AppendLine("   - Prefer complete file content when small.")
$null = $sb.AppendLine("   - If the file is large, show minimal diff chunks and specify exact insertion points.")
$null = $sb.AppendLine("")
# 出力順を固定して、毎回のやりとりを安定させる
$null = $sb.AppendLine("Output order must be:")
$null = $sb.AppendLine("(1) Implementation plan")
$null = $sb.AppendLine("(2) Branch name candidates")
$null = $sb.AppendLine("(3) Files checklist (A/B/C)")
$null = $sb.AppendLine("(4) Paste-ready code blocks (A only)")
$null = $sb.AppendLine("(5) Pitfalls / verification steps")
$null = $sb.AppendLine("")

$out = $sb.ToString()

if ($ToClipboard) {
  $out | Set-Clipboard
  Write-Host ("OK: copied to clipboard (Issue_Number={0})" -f $IssueNumber)
} else {
  $out
}
