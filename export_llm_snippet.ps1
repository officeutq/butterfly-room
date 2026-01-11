<# 
  LLM貼り付け用：Issue番号から CSV 3種を抜粋してテンプレ生成

  前提（同ディレクトリにCSVがある）：
    - .\issues_with_body.csv
    - .\issues_with_pr.csv
    - .\issues_with_pr_expanded.csv

  使い方：
    # 未着手想定（PRがなければPRセクションは出ない）
    .\export_llm_snippet.ps1 -IssueNumber 8 -Mode new -ToClipboard

    # 実装途中/レビュー想定（PRセクションも含めて出す）
    .\export_llm_snippet.ps1 -IssueNumber 8 -Mode ongoing -ToClipboard
#>

param(
  [Parameter(Mandatory=$true)]
  [int]$IssueNumber,

  [ValidateSet("new","ongoing","review")]
  [string]$Mode = "new",

  [string]$IssuesBodyPath = ".\issues_with_body.csv",
  [string]$IssuesPrPath   = ".\issues_with_pr.csv",
  [string]$IssuesPrExpPath= ".\issues_with_pr_expanded.csv",

  [int]$PrExcerptMax = 800,

  [switch]$ToClipboard
)

function Require-File([string]$Path) {
  if (!(Test-Path $Path)) { throw ("File not found: " + $Path) }
}

function CsvRowToSingleLineCsv([object]$Row, [string[]]$Columns) {
  $obj = [PSCustomObject]@{}
  foreach ($c in $Columns) {
    $obj | Add-Member -NotePropertyName $c -NotePropertyValue ($Row.$c)
  }
  ($obj | ConvertTo-Csv -NoTypeInformation) -join "`n"
}

function Truncate([string]$s, [int]$max) {
  if ($null -eq $s) { return $null }
  $t = $s.Trim()
  if ($t.Length -le $max) { return $t }
  return $t.Substring(0, $max) + "..."
}

Require-File $IssuesBodyPath
Require-File $IssuesPrPath
Require-File $IssuesPrExpPath

$bodyRows = Import-Csv $IssuesBodyPath
$prRows   = Import-Csv $IssuesPrPath
$prExpRows= Import-Csv $IssuesPrExpPath

$bodyRow = $bodyRows | Where-Object { [int]$_.Issue_Number -eq $IssueNumber } | Select-Object -First 1
if ($null -eq $bodyRow) {
  throw ("Issue not found in issues_with_body.csv: Issue_Number=" + $IssueNumber)
}

$prRow = $prRows | Where-Object { [int]$_.Issue_Number -eq $IssueNumber } | Select-Object -First 1

$prExp = $prExpRows |
  Where-Object { ([int]$_.Issue_Number -eq $IssueNumber) -and (-not [string]::IsNullOrWhiteSpace($_.PR_Number)) }

$prExpFormatted = @()
foreach ($r in $prExp) {
  $excerpt = $null
  if ($r.PSObject.Properties.Name -contains "PR_Body_Excerpt") {
    $excerpt = $r.PR_Body_Excerpt
  } elseif ($r.PSObject.Properties.Name -contains "PR_Body") {
    $excerpt = $r.PR_Body
  }
  $r.PR_Body_Excerpt = Truncate $excerpt $PrExcerptMax
  $prExpFormatted += $r
}

$colsPrSummary = @(
  "Issue_Number","Title","Status","Labels","Milestone","Parent_Issue_Number",
  "LinkedPR_Count","LinkedPR_Numbers","LatestPR_State","LatestPR_MergedAt"
)

$colsPrExp = @(
  "Issue_Number","PR_Number","PR_Title","PR_State","PR_MergedAt","PR_URL","PR_Body_Excerpt"
)

$colsBody = @(
  "Issue_Number","Title","Labels","Milestone","Parent_Issue_Number","Body"
)

$title = $bodyRow.Title
$parent = $bodyRow.Parent_Issue_Number
$milestone = $bodyRow.Milestone

$includePr = $false
switch ($Mode) {
  "new"     { $includePr = $false }
  "ongoing" { $includePr = $true }
  "review"  { $includePr = $true }
}

$hasPr = ($prExpFormatted.Count -gt 0) -or ($prRow -and [int]$prRow.LinkedPR_Count -gt 0)

$sb = New-Object System.Text.StringBuilder

$null = $sb.AppendLine("TARGET ISSUE")
$null = $sb.AppendLine(("Issue_Number: {0}" -f $IssueNumber))
$null = $sb.AppendLine(("Title: {0}" -f $title))
if (-not [string]::IsNullOrWhiteSpace($parent))   { $null = $sb.AppendLine(("Parent_Issue_Number: {0}" -f $parent)) }
if (-not [string]::IsNullOrWhiteSpace($milestone)){ $null = $sb.AppendLine(("Milestone: {0}" -f $milestone)) }
$null = $sb.AppendLine("")

if ($prRow) {
  $null = $sb.AppendLine("SECTION 1: issues_with_pr.csv (single row)")
  $null = $sb.AppendLine((CsvRowToSingleLineCsv -Row $prRow -Columns $colsPrSummary))
  $null = $sb.AppendLine("")
}

if ($includePr -and $prExpFormatted.Count -gt 0) {
  $null = $sb.AppendLine("SECTION 2: issues_with_pr_expanded.csv (PR rows)")
  $export = $prExpFormatted | Select-Object $colsPrExp
  $null = $sb.AppendLine((($export | ConvertTo-Csv -NoTypeInformation) -join "`n"))
  $null = $sb.AppendLine("")
} elseif ($Mode -eq "new" -and $hasPr) {
  $null = $sb.AppendLine("NOTE: This issue already has linked PR(s). Consider reviewing them first.")
  $null = $sb.AppendLine("")
}

$null = $sb.AppendLine("SECTION 3: issues_with_body.csv (single row)")
$null = $sb.AppendLine((CsvRowToSingleLineCsv -Row $bodyRow -Columns $colsBody))
$null = $sb.AppendLine("")

$null = $sb.AppendLine("INSTRUCTIONS")
$null = $sb.AppendLine("1) Decide current status (not-started / in-progress / done / partial).")
$null = $sb.AppendLine("2) Extract tasks + done criteria from Body, and order them for implementation.")
$null = $sb.AppendLine("3) List likely affected files/classes.")
$null = $sb.AppendLine("4) Provide starter code skeletons (service/controller/migration) and pitfalls.")

$out = $sb.ToString()

if ($ToClipboard) {
  $out | Set-Clipboard
  Write-Host ("OK: copied to clipboard (Issue_Number={0}, Mode={1})" -f $IssueNumber, $Mode)
} else {
  $out
}