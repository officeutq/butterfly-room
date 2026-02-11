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
    $relatedIssues += $row
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
if (@($siblingsMerged).Count -gt 0) {
  $null = $sb.AppendLine("SECTION 3: Sibling Issues already merged (reference implementation)")
  $colsSibling = @("Issue_Number","Title","Status","Labels","Milestone","LatestPR_Number","LatestPR_State","LatestPR_MergedAt")
  $export = $siblingsMerged | Select-Object $colsSibling
  $null = $sb.AppendLine((($export | ConvertTo-Csv -NoTypeInformation) -join "`n"))
  $null = $sb.AppendLine("")
}

# 4) 関連Issue（本文で明示）
if ($relatedIssues.Count -gt 0) {
  $null = $sb.AppendLine("SECTION 4: Related Issues explicitly mentioned in the body (#nnn)")
  $relExport = @()
  foreach ($ri in $relatedIssues) {
    $relExport += [PSCustomObject]@{
      Issue_Number = $ri.Issue_Number
      Title = $ri.Title
      Labels = $ri.Labels
      Milestone = $ri.Milestone
      Parent_Issue_Number = $ri.Parent_Issue_Number
      Body_Excerpt = Truncate $ri.Body $RelatedBodyMaxChars
    }
  }
  $null = $sb.AppendLine((($relExport | ConvertTo-Csv -NoTypeInformation) -join "`n"))
  $null = $sb.AppendLine("")
}

# LLMへの指示（新規着手専用）
$null = $sb.AppendLine("INSTRUCTIONS TO LLM")
$null = $sb.AppendLine("1) Read SECTION 1 as the source of truth. Extract tasks + Done criteria and order them.")
$null = $sb.AppendLine("2) Use SECTION 2 (Epic) to align scope/priority and avoid over-implementation.")
$null = $sb.AppendLine("3) Use SECTION 3 (merged siblings) to match existing patterns, naming, and architecture.")
$null = $sb.AppendLine("4) Use SECTION 4 (related) to avoid conflicts/duplication and respect dependencies.")
$null = $sb.AppendLine("5) Output: implementation plan, likely affected files, and starter code skeletons.")
$null = $sb.AppendLine("")

$out = $sb.ToString()

if ($ToClipboard) {
  $out | Set-Clipboard
  Write-Host ("OK: copied to clipboard (Issue_Number={0})" -f $IssueNumber)
} else {
  $out
}
