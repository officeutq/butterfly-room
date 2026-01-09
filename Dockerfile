FROM ruby:3.3-slim

ENV LANG=C.UTF-8 TZ=Asia/Tokyo \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 BUNDLE_RETRY=3 \
    PATH="/usr/local/bundle/bin:${PATH}" \
    EDITOR=vi

# 必要パッケージ
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential libpq-dev curl git nodejs npm \
    pkg-config libyaml-dev \
    vim-tiny \
  && rm -rf /var/lib/apt/lists/*

# 作業ディレクトリ
WORKDIR /app

# 余談: Windows との改行差異対策（GitはLF推奨）
# RUN git config --global core.autocrlf input

# エントリポイント
COPY bin/entrypoint.sh /usr/bin/entrypoint.sh
# CRLF→LF に正規化し、実行権限を付与
RUN sed -i 's/\r$//' /usr/bin/entrypoint.sh && chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/entrypoint.sh"]

# ★ Rails と Bundler をグローバルに導入
RUN gem update --system -N \
 && gem install bundler -N \
 && gem install rails -v "~> 8.0" -N \
 && gem install foreman -N

# デフォルト起動（開発）
CMD ["bash", "-lc", "bin/dev"]
