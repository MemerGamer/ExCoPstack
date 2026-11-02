#!/usr/bin/env bash
# Test for the HTTP 418 endpoint. Runs api.php under PHP's built-in server with a
# stubbed vendor/autoload.php, so neither composer nor the xlsx storage is needed.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
port="${PORT:-18418}"
trap 'kill "${pid:-}" 2>/dev/null || true; rm -rf "$tmp"' EXIT

mkdir -p "$tmp/vendor"
echo '<?php' > "$tmp/vendor/autoload.php"
cp "$here/api.php" "$tmp/api.php"

EXCEL_STORAGE_PATH="$tmp/storage" php -S "127.0.0.1:$port" -t "$tmp" "$tmp/api.php" >"$tmp/server.log" 2>&1 &
pid=$!
for _ in $(seq 50); do
  curl -s -o /dev/null "http://127.0.0.1:$port/" && break
  sleep 0.1
done

fail=0
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected $2, got $3"; fail=1; fi
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

check "GET /api/teapot is 418" 418 "$(code "http://127.0.0.1:$port/api/teapot")"
check "GET /api/coffee is 418" 418 "$(code "http://127.0.0.1:$port/api/coffee")"
check "POST /api/teapot is 418" 418 "$(code -X POST "http://127.0.0.1:$port/api/teapot")"
check "418 body" "error,im-a-teapot" "$(curl -s "http://127.0.0.1:$port/api/teapot")"
check "unknown path still 404" 404 "$(code "http://127.0.0.1:$port/api/nope")"

exit $fail
