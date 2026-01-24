# frozen_string_literal: true

# Stripe API Key 設定
#
# 優先順位:
# 1. ENV["STRIPE_SECRET_KEY"]
#    - 本番環境（EC2 / CI / 一時的な鍵差し替え）向け
#    - デプロイ時に環境変数で安全に切り替えられる
#
# 2. Rails credentials (:stripe, :secret_key)
#    - ローカル開発・ステージング向け
#    - リポジトリ外で安全に管理できる
#
# ※ どちらも未設定の場合は Stripe API 呼び出し時に例外が発生する
Stripe.api_key =
  ENV["STRIPE_SECRET_KEY"].presence ||
  Rails.application.credentials.dig(:stripe, :secret_key)

# ネットワークエラー時の自動リトライ回数
# Stripe 公式 SDK の推奨に従い、過度な再試行は避ける
Stripe.max_network_retries = 2
