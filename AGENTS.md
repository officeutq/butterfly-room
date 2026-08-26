# AGENTS.md

## 開発ルール

* 仕様が不明な場合は、推測で大きく作り込まず、最小実装に留める
* 既存ドキュメントと矛盾する実装をしない
* 実装前に関連ドキュメントを確認する
* 不要な抽象化を増やさない
* 既存の責務分離を崩さない
* 既存の命名、ディレクトリ構成、実装スタイルに合わせる

## 作業開始前チェック

作業開始前に必ず以下を確認する。

```bash
git status --short
git branch --show-current
```

未コミット変更、未追跡ファイル、作業中ブランチがある場合は、既存変更を上書き・削除・整形しない。

既存変更が今回作業に関係するか判断できない場合は、作業前に状況を報告する。

既存ブランチで作業している場合でも、`main` へ直接コミットしない。

## 重要な設計前提

実装時は、以下の Phase1 前提を壊さないこと。

* 売上はドリンクの消化確定分のみとする
* 未消化・返却済みドリンクを売上に含めない
* 金銭処理・状態変更は Service（業務処理を集約するクラス）に集約する
* Controller（リクエストを受ける層）は認可、Service 呼び出し、レスポンスに留める
* DB transaction（データベースの一連処理）は Service 側で扱う
* 配信は stream_session（配信セッション）単位で扱う
* standby（配信準備中）では viewer（視聴者）を join（参加）させない
* Stage（Amazon IVS の配信ルーム実体）作成は publisher（配信者）起点に限定する
* ブース紐づけは Phase1 では確定後変更不可
* 履歴データは物理削除せず、論理削除・アーカイブで扱う

## 関連ドキュメント確認ルール

実装前に、変更対象に応じて以下を確認する。

* Rails / Service / Controller / 金銭処理: `04_Rails設計.md`
* Phase1 の業務仕様・不変条件: `02_要件定義書.md`, `03_基本設計_Phase1.md`
* 配信・IVS・stream_session・join 制御: `05_WebRTC 配信シグナリング設計.md`
* 配信映像・canvas・viewer 表示: `06_配信映像設計.md`
* 導線・current_booth / current_store: `07_モード導線設計.md`
* 画面加工・Banuba: `08_画面加工設計.md`
* 現在の構成確認: `09_最新ディレクトリ構成.md`

ただし、ドキュメントだけで判断せず、必ず現在の実コードを確認すること。

## 実コード確認の方針

症状だけから原因を断定せず、修正前に必ず関連する実コードを確認すること。

特にバグ調査、デバッグ表示追加、設計判断では、以下を確認する。

* 呼び出し元と呼び出し先の実装
* 型定義、インターフェース、公開 API
* 状態の所有者と更新箇所
* 表示している debug 値が、実行時に利用している同じインスタンスから来ているか
* initialize / start / setInput / setDetector などの lifecycle（初期化から破棄までの流れ）順序
* 既存の guard（防御条件）、early return（早期終了）、error handling（エラー処理）

現在の実装と矛盾する原因断定、提案、修正をしないこと。

完了報告では、確認した主なファイルや呼び出し経路を簡潔に記載すること。

## Git運用ルール

* 作業開始前に、必ず目的に応じた作業ブランチを作成する
* `main` ブランチへ直接コミットしない
* ブランチ名は以下の形式を基本とする

```text
docs/内容
feature/内容
fix/内容
chore/内容
```

* 変更後はコミットする
* コミット後、リモートへ push する
* push 後、Pull Request（変更取り込み依頼）を作成する
* PR 本文には変更内容と確認結果を記載する
* Issue がある場合は `Closes #xxx` を含める

ただし、ユーザーが「調査のみ」「コミットしない」「push しない」「PR を作らない」と明示した場合は、その指示を優先する。

## Issue作成ルール

親Epic+子Issueで作成する

* Projects：Butterfly Room Board
* Milestone：フェーズ2
* Epicのラベル：epic
* 子Issueのラベル：適宜選んで
* 子IssueのParent issue：親Epicを指定

既存Issueの書式と親子関係の付け方を確認してから作成する

## Pull Request 作成ルール

Pull Request 作成時は、まずローカルの `gh` CLI（GitHub 操作用コマンド）の認証を利用すること。

`gh` を試す前に、GitHub App ベースの PR 作成を試行しないこと。

推奨フロー:

```bash
git push -u origin <branch-name>
gh pr create --title "<title>" --body-file pr-body.md
```

`gh` の認証が利用できない、または失敗した場合は、エラー内容を明確に報告すること。

## GitHub CLI 文字化け防止ルール

PR タイトル、PR 本文、Issue コメントなど日本語を `gh` CLI に渡す場合は、PowerShell の pipe や既定エンコーディングに依存しない。

推奨フロー:

```bash
gh pr create --title "日本語タイトル" --body-file pr-body.md
gh pr edit <number> --body-file pr-body.md
```

Codex（コード編集エージェント）が PR 本文を作る場合は、UTF-8 の本文ファイルを作成して `--body-file` を使うこと。

PowerShell here-string をそのまま `gh` へ pipe しないこと。

## 言語ルール

PR タイトル、PR 本文、Issue コメント、完了報告は原則として日本語で記載する。

例:

* Summary → 変更内容
* Testing → 確認内容
* Manual Testing → 手動確認事項

ただし、API 名、型名、コード識別子、CLI コマンド、package 名、npm script 名は英語のままとする。

コミットメッセージも原則として日本語で記載する。

## 日本語・用語ルールの補足

英語の専門用語やアルファベット表記を使う場合は、初出で日本語の説明を併記する。

例:

* Service（業務処理を集約するクラス）
* Controller（リクエストを受ける層）
* viewer（視聴者）
* publisher（配信者）
* Stage（Amazon IVS の配信ルーム実体）
* lifecycle（初期化から破棄までの流れ）
* guard（防御条件）
* debug（デバッグ情報）

ただし、API 名、型名、クラス名、メソッド名、ファイル名、CLI コマンドは英語のままでよい。

## Codexへの依頼方針

Codex への依頼は、原則として以下の形式で行う。

```text
目的
実装内容
変更してよい範囲
変更してはいけない範囲
確認コマンド
完了条件
```

依頼内容に明記されていない大きな設計変更、別機能の追加、不要なリファクタリングは行わないこと。

## 確認コマンド方針

変更後は、変更範囲に応じて実行可能な確認を行う。

最低限:

```bash
git diff --check
git status --short
```

Rails の model（モデル）、Service、Controller、routing（ルーティング）を変更した場合は、関連するテストを優先して実行する。

JavaScript / CSS / asset（静的資産）を変更した場合は、関連する build（ビルド）または既存の確認コマンドを実行する。

テストコマンドが不明な場合は、既存の README、bin、package、Gemfile、CI 設定を確認してから実行する。

実行できなかった確認がある場合は、理由を完了報告に明記する。

## 完了報告

作業完了時は、以下を日本語で報告する。

```text
変更内容
- ...

確認内容
- ...

確認した主な実コード
- ...

PR
- ...
```

確認できなかった項目、未実施のテスト、判断に迷った点がある場合は隠さず記載する。
