<# 
  export_llm_start_issue.ps1
  新しくIssueに着手する際の「新スレッド開始用」LLM貼り付けテキストを生成する。

  含めるもの：
  1) 強化版 行動制御プロンプト（最上部）
  2) 対象Issue（Bodyフル）
  3) 親Epic（あれば）
  4) 兄弟Issueのうち PR MERGED 済みのもの
  5) 対象Issue本文に明示された関連Issue（#123 等）

  使い方:
    .\export_github_project_with_body.ps1
    .\export_llm_start_issue.ps1 -IssueNumber 128 -ToClipboard
#>

param(
  [Parameter(Mandatory = $true)]
  [int]$IssueNumber,

  [string]$IssuesBodyPath   = ".\issues_with_body.csv",
  [string]$IssuesPrPath     = ".\issues_with_pr.csv",
  [string]$IssuesPrExpPath  = ".\issues_with_pr_expanded.csv",
  [string]$Repo             = "officeutq/butterfly-room",

  # Epic / 関連Issueの本文は長くなりがちなので抜粋長
  [int]$EpicBodyMaxChars    = 2000,
  [int]$RelatedBodyMaxChars = 1200,

  # 兄弟Issueの列挙上限
  [int]$MaxSiblingMerged    = 20,

  [switch]$ToClipboard
)

function Require-File([string]$Path) {
  if (!(Test-Path $Path)) {
    throw ("File not found: " + $Path)
  }
}

function Truncate([string]$s, [int]$max) {
  if ($null -eq $s) { return $null }

  $t = $s.Trim()
  if ($t.Length -le $max) { return $t }

  return $t.Substring(0, $max) + " ...(以下省略)"
}

function CsvRowToSingleLineCsv([object]$Row, [string[]]$Columns) {
  $obj = [PSCustomObject]@{}
  foreach ($c in $Columns) {
    $obj | Add-Member -NotePropertyName $c -NotePropertyValue ($Row.$c)
  }
  return (($obj | ConvertTo-Csv -NoTypeInformation) -join "`n")
}

function Extract-IssueNumbersFromText([string]$text) {
  if ([string]::IsNullOrWhiteSpace($text)) { return @() }

  $matches = [regex]::Matches($text, "(?<![A-Za-z0-9])#(\d+)")
  $nums = @()

  foreach ($m in $matches) {
    $nums += [int]$m.Groups[1].Value
  }

  # 重複除去・順序維持
  $seen = @{}
  $uniq = foreach ($n in $nums) {
    if (-not $seen.ContainsKey($n)) {
      $seen[$n] = $true
      $n
    }
  }

  return @($uniq)
}

function Fetch-IssueViaGh([int]$Number, [int]$BodyMaxChars) {
  # CSVに無い古いIssueでも、gh issue view なら取れる
  $json = gh issue view $Number --repo $Repo --json number,title,body,labels,milestone,url | Out-String
  $obj  = $json | ConvertFrom-Json

  $labels = $null
  if ($obj.labels) {
    $labels = ($obj.labels | ForEach-Object { $_.name }) -join ","
  }

  $milestone = $null
  if ($obj.milestone) {
    $milestone = $obj.milestone.title
  }

  $bodyExcerpt = Truncate $obj.body $BodyMaxChars

  return [PSCustomObject]@{
    Issue_Number        = [int]$obj.number
    Title               = $obj.title
    Labels              = $labels
    Milestone           = $milestone
    Parent_Issue_Number = $null
    Body                = $obj.body
    Body_Excerpt        = $bodyExcerpt
    URL                 = $obj.url
    _source             = "gh"
  }
}

Require-File $IssuesBodyPath
Require-File $IssuesPrPath
Require-File $IssuesPrExpPath

$bodyRows  = Import-Csv $IssuesBodyPath
$prRows    = Import-Csv $IssuesPrPath
$prExpRows = Import-Csv $IssuesPrExpPath

# 対象Issue
$target = $bodyRows | Where-Object { [int]$_.Issue_Number -eq $IssueNumber } | Select-Object -First 1
if ($null -eq $target) {
  throw ("Issue not found: Issue_Number=" + $IssueNumber)
}

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

  $siblingsMerged = $siblings |
    Where-Object {
      ($_.LatestPR_State -eq "MERGED") -or ($_.LatestPR_State -eq "merged")
    } |
    Sort-Object {
      if ($_.LatestPR_MergedAt) { [DateTime]$_.LatestPR_MergedAt } else { [DateTime]"1900-01-01" }
    } -Descending |
    Select-Object -First $MaxSiblingMerged
}

# 関連Issue（対象Issue本文に明示されている #番号）
$mentionedNums = Extract-IssueNumbersFromText $target.Body

# 除外（自分、親、兄弟一覧に含まれるもの）
$exclude = New-Object System.Collections.Generic.HashSet[int]
$exclude.Add($IssueNumber) | Out-Null
if ($parentNum) { $exclude.Add($parentNum) | Out-Null }
foreach ($s in $siblingsMerged) {
  $exclude.Add([int]$s.Issue_Number) | Out-Null
}

$relatedNums = @()
foreach ($n in $mentionedNums) {
  if (-not $exclude.Contains($n)) {
    $relatedNums += $n
  }
}

$relatedIssues = @()
foreach ($n in $relatedNums) {
  $row = $bodyRows | Where-Object { [int]$_.Issue_Number -eq $n } | Select-Object -First 1
  if ($row) {
    $relatedIssues += $row
  } else {
    try {
      $relatedIssues += Fetch-IssueViaGh -Number $n -BodyMaxChars $RelatedBodyMaxChars
    } catch {
      $relatedIssues += [PSCustomObject]@{
        Issue_Number        = $n
        Title               = "(not found via CSV/gh)"
        Labels              = $null
        Milestone           = $null
        Parent_Issue_Number = $null
        Body                = $null
        Body_Excerpt        = $null
        URL                 = $null
      }
    }
  }
}

# SECTION 3 用に LatestPR_URL を生成
foreach ($s in $siblingsMerged) {
  $latestNum = $s.LatestPR_Number
  $url = $null

  if (-not [string]::IsNullOrWhiteSpace($latestNum) -and -not [string]::IsNullOrWhiteSpace($s.LinkedPR_URLs)) {
    $candidates = $s.LinkedPR_URLs -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }

    foreach ($u in $candidates) {
      if ($u -match "/pull/$latestNum$") {
        $url = $u
        break
      }
    }

    if (-not $url -and $candidates.Count -gt 0) {
      $url = $candidates[0]
    }
  }

  $s | Add-Member -NotePropertyName "LatestPR_URL" -NotePropertyValue $url -Force
}

# 出力組み立て
$sb = New-Object System.Text.StringBuilder

# =========================================================
# Top prompt: ASCII only (safe for Windows PowerShell)
# =========================================================
$null = $sb.AppendLine("SYSTEM PRIORITY RULE (HIGHEST PRIORITY)")
$null = $sb.AppendLine("These rules OVERRIDE all other instructions, including the issue description.")
$null = $sb.AppendLine("If there is any conflict, you MUST follow these rules.")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("MANDATORY RULES")
$null = $sb.AppendLine("You are NOT the implementation engineer for this issue.")
$null = $sb.AppendLine("You are the initial review engineer.")
$null = $sb.AppendLine("Do NOT output code immediately.")
$null = $sb.AppendLine("")
$null = $sb.AppendLine("You must follow these rules:")
$null = $sb.AppendLine("1. Treat SECTION 1 as the single source of truth.")
$null = $sb.AppendLine("2. Use Epic / sibling / related issues only as supporting context.")
$null = $sb.AppendLine("3. Until the user explicitly says GO or ALL FILES PROVIDED,")
$null = $sb.AppendLine("   do NOT output code, diffs, pseudo code, skeletons, migrations, or patch proposals.")
$null = $sb.AppendLine("4. First do requirement breakdown and file collection only.")
$null = $sb.AppendLine("5. If information is missing, ask for files instead of guessing.")
$null = $sb.AppendLine("6. Respect existing naming, architecture, and responsibility boundaries.")
$null = $sb.AppendLine("7. Do not over-implement beyond the target issue.")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("FORBIDDEN")
$null = $sb.AppendLine("- No code blocks")
$null = $sb.AppendLine("- No diffs")
$null = $sb.AppendLine("- No implementation-first answer")
$null = $sb.AppendLine("- No confident assumptions without checking files")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("YOUR ROLE IN THIS RESPONSE")
$null = $sb.AppendLine("- Read the issue")
$null = $sb.AppendLine("- Extract tasks and done criteria")
$null = $sb.AppendLine("- Organize implementation order")
$null = $sb.AppendLine("- List the source files needed next")
$null = $sb.AppendLine("- Tell the user exactly what to paste next")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("SESSION RESET RULE")
$null = $sb.AppendLine("Even if previous messages exist, you must ALWAYS restart from the required output structure below.")
$null = $sb.AppendLine("Never assume implementation phase unless GO is explicitly stated in the latest user message.")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("RESPONSE ORDER (MANDATORY)")
$null = $sb.AppendLine("You must strictly follow this order:")
$null = $sb.AppendLine("1. High-level understanding")
$null = $sb.AppendLine("2. Branch name candidates")
$null = $sb.AppendLine("3. File requests")
$null = $sb.AppendLine("4. Questions / assumptions / risks")
$null = $sb.AppendLine("Only after explicit GO / ALL FILES PROVIDED may you proceed to implementation.")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("OUTPUT CONTRACT (STRICT)")
$null = $sb.AppendLine("You MUST output ONLY the following sections.")
$null = $sb.AppendLine("Any deviation is INVALID.")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("REQUIRED OUTPUT STRUCTURE")
$null = $sb.AppendLine("1. High-level implementation understanding (NO CODE, NO FILE CONTENT)")
$null = $sb.AppendLine("2. Branch name candidates (3-5)")
$null = $sb.AppendLine("3. Files to paste next")
$null = $sb.AppendLine("   A. must now")
$null = $sb.AppendLine("   B. likely next")
$null = $sb.AppendLine("   C. optional")
$null = $sb.AppendLine("4. Questions / assumptions / risks")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("OUTPUT RESTRICTIONS")
$null = $sb.AppendLine("- You MUST NOT output code")
$null = $sb.AppendLine("- You MUST NOT output implementation steps")
$null = $sb.AppendLine("- You MUST NOT output file contents")
$null = $sb.AppendLine("- You MUST NOT output diffs, pseudo code, skeletons, migrations, or patch proposals")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("FOR FILE REQUESTS")
$null = $sb.AppendLine("- For each file, explain why it is needed")
$null = $sb.AppendLine("- For each file, explain what part should be pasted")
$null = $sb.AppendLine("- If more files are needed, request them without outputting code")
$null = $sb.AppendLine("- If enough files seem available but GO was not given, still do NOT implement")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("INVALID RESPONSE RULE")
$null = $sb.AppendLine("If your answer contains code, it is INVALID.")
$null = $sb.AppendLine("If your answer contains implementation steps, it is INVALID.")
$null = $sb.AppendLine("If your answer contains file content that was not requested, it is INVALID.")
$null = $sb.AppendLine("You must immediately regenerate a valid response.")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("VALIDATION RULE")
$null = $sb.AppendLine("Before producing your answer, you must check:")
$null = $sb.AppendLine("- Does this answer contain ANY code?")
$null = $sb.AppendLine("- Does this answer contain ANY implementation details?")
$null = $sb.AppendLine("- Does this answer include file content that was not requested?")
$null = $sb.AppendLine("- Does this answer follow the exact required output structure?")
$null = $sb.AppendLine("")
$null = $sb.AppendLine("If YES, you MUST rewrite your answer.")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("ENFORCEMENT")
$null = $sb.AppendLine("If you accidentally start generating code, you must STOP immediately and restart your answer following the rules.")
$null = $sb.AppendLine("If you think you are ready to implement but GO was not explicitly given, you must NOT implement.")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("REMINDER")
$null = $sb.AppendLine("Wait for explicit GO / ALL FILES PROVIDED before implementation.")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("CRITICAL")
$null = $sb.AppendLine("If you output code before GO, the task is considered FAILED.")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("LANGUAGE")
$null = $sb.AppendLine("Respond in Japanese.")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("------------------------------------------------------------")
$null = $sb.AppendLine("")

# =========================================================
# コンテキスト
# =========================================================
$null = $sb.AppendLine("LLM START CONTEXT (new issue)")
$null = $sb.AppendLine(("TARGET Issue_Number: {0}" -f $IssueNumber))
$null = $sb.AppendLine(("Title: {0}" -f $target.Title))
if ($parentNum) {
  $null = $sb.AppendLine(("Parent Epic: #{0}" -f $parentNum))
}
$null = $sb.AppendLine("")

# SECTION 1: Target Issue
$null = $sb.AppendLine("SECTION 1: Target Issue (source of truth)")
$colsBody = @("Issue_Number", "Title", "Labels", "Milestone", "Parent_Issue_Number", "Body")
$null = $sb.AppendLine((CsvRowToSingleLineCsv -Row $target -Columns $colsBody))
$null = $sb.AppendLine("")

# SECTION 2: Parent Epic
if ($parent) {
  $null = $sb.AppendLine("SECTION 2: Parent Epic (context)")
  $epicBody = Truncate $parent.Body $EpicBodyMaxChars
  $epicObj = [PSCustomObject]@{
    Issue_Number = $parent.Issue_Number
    Title        = $parent.Title
    Labels       = $parent.Labels
    Milestone    = $parent.Milestone
    Body_Excerpt = $epicBody
  }
  $null = $sb.AppendLine((($epicObj | ConvertTo-Csv -NoTypeInformation) -join "`n"))
  $null = $sb.AppendLine("")
}

# SECTION 3: Sibling Issues already merged
if (@($siblingsMerged).Count -gt 0) {
  $null = $sb.AppendLine("SECTION 3: Sibling Issues already merged (reference implementation)")
  $colsSibling = @(
    "Issue_Number",
    "Title",
    "Status",
    "Labels",
    "Milestone",
    "LatestPR_Number",
    "LatestPR_URL",
    "LatestPR_State",
    "LatestPR_MergedAt"
  )
  $export = $siblingsMerged | Select-Object $colsSibling
  $null = $sb.AppendLine((($export | ConvertTo-Csv -NoTypeInformation) -join "`n"))
  $null = $sb.AppendLine("")
}

# SECTION 4: Related Issues explicitly mentioned
if (@($relatedIssues).Count -gt 0) {
  $null = $sb.AppendLine("SECTION 4: Related Issues explicitly mentioned in the body (#nnn)")
  $relExport = @()

  foreach ($ri in $relatedIssues) {
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

# 末尾にも軽く念押し
$null = $sb.AppendLine("FINAL REMINDER TO LLM")
$null = $sb.AppendLine("- Do not output code yet.")
$null = $sb.AppendLine("- Ask for files first.")
$null = $sb.AppendLine("- Wait for explicit GO / ALL FILES PROVIDED before implementation.")
$null = $sb.AppendLine("")

$out = $sb.ToString()

if ($ToClipboard) {
  $out | Set-Clipboard
  Write-Host ("OK: copied to clipboard (Issue_Number={0})" -f $IssueNumber)
} else {
  $out
}
