<#
.SYNOPSIS
  Railsプロジェクトのディレクトリ/ファイル構成をツリー文字列として生成し、
  クリップボードにコピーするスクリプト。

.PURPOSE / 使いどころ
  - 04_Rails設計.md の「1.1 ディレクトリ/クラス構成」に貼る素材を自動生成する
  - レビュー時に「どこに何があるか」をテキストで共有する

.OUTPUT
  例（クリップボードに入る）:
    app/
      controllers/
        application_controller.rb
        booths_controller.rb
        admin/
          base_controller.rb
          booths_controller.rb
      views/
        booths/
          show.html.erb
    config/
      routes.rb
      initializers/
        devise.rb

.HOW TO USE
  1) このファイル(copy_app_tree.ps1)をリポジトリ直下に置く
  2) PowerShellでリポジトリ直下に移動して実行
       powershell -ExecutionPolicy Bypass -File .\copy_app_tree.ps1
  3) クリップボードにコピーされたツリーを Markdown に貼り付ける

.CUSTOMIZE（ここだけ編集すればOK）
  - $Targets      : 出力したいトップディレクトリ（例: app, config）
  - $Extensions   : 出力したい拡張子（例: .rb .js .erb .yml）
  - $MaxDepth     : 深さ制限（0=無制限。長すぎる場合は 5〜8 くらい推奨）
  - $IncludeEmptyDirs : 空ディレクトリも出すなら $true（通常は $false）

.NOTES
  - Windows向け（Set-Clipboard を使用）
  - "  "（スペース2つ）でインデントする（Markdown貼り付け向け）
#>

# ========= ここを編集（設定） =========
$Root = (Get-Location).Path

# 出力したいディレクトリ（リポジトリ直下からの相対パス）
$Targets = @("app", "config")

# 出力したい拡張子（必要に応じて追加）
$Extensions = @(".rb", ".js", ".erb", ".yml")

# 深さ制限（0=無制限）
$MaxDepth = 6

# 空ディレクトリも出す？
$IncludeEmptyDirs = $false
# ====================================

function Get-Indent([int]$level) { return ("  " * $level) }

$lines = New-Object System.Collections.Generic.List[string]

function Add-Dir([string]$dirPath, [int]$level) {
  $name = Split-Path $dirPath -Leaf
  $lines.Add("$(Get-Indent $level)$name/")

  $dirs = Get-ChildItem -LiteralPath $dirPath -Directory -Force | Sort-Object Name
  $files = Get-ChildItem -LiteralPath $dirPath -File -Force |
    Where-Object { $Extensions -contains $_.Extension } |
    Sort-Object Name

  $hasChildren = ($dirs.Count -gt 0) -or ($files.Count -gt 0)
  if (-not $IncludeEmptyDirs -and -not $hasChildren) { return }

  if ($MaxDepth -gt 0 -and $level -ge $MaxDepth) { return }

  foreach ($d in $dirs) { Add-Dir $d.FullName ($level + 1) }
  foreach ($f in $files) { $lines.Add("$(Get-Indent ($level + 1))$($f.Name)") }
}

foreach ($t in $Targets) {
  $targetPath = Join-Path $Root $t
  if (-not (Test-Path -LiteralPath $targetPath)) {
    Write-Warning "Skip (not found): $targetPath"
    continue
  }

  # 複数ターゲットを見やすく区切る
  if ($lines.Count -gt 0) { $lines.Add("") }
  Add-Dir $targetPath 0
}

$text = ($lines -join "`n").TrimEnd() + "`n"
Set-Clipboard -Value $text
Write-Host "Copied tree to clipboard: $($lines.Count) lines"
