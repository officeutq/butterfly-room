#!/usr/bin/env sh
set -e

# Rails の PID が残っていたら削除
rm -f tmp/pids/server.pid 2>/dev/null || true

exec "$@"
