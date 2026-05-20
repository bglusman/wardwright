#!/usr/bin/env bash
# Smoke test a Burrito-wrapped Wardwright binary.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/wardwright_binary" >&2
  exit 2
fi

BINARY="$1"
PORT="${WARDWRIGHT_SMOKE_PORT:-$(ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]; server.close')}"
BASE_URL="http://127.0.0.1:${PORT}"
SECRET="${WARDWRIGHT_SECRET_KEY_BASE:-$(openssl rand -base64 64)}"
LOG_FILE="$(mktemp -t wardwright-burrito-smoke.XXXXXX.log)"
SQLITE_STORE="$(mktemp -t wardwright-burrito-smoke.XXXXXX.sqlite3)"

if [ ! -x "$BINARY" ]; then
  echo "binary is not executable: $BINARY" >&2
  exit 2
fi

# Burrito reuses an extracted payload for the same app/version. Remove the
# target binary's install directory so the smoke always validates this build.
INSTALL_DIR="$("$BINARY" maintenance directory)"
case "$INSTALL_DIR" in
  *"/.burrito/wardwright_"*) rm -rf "$INSTALL_DIR" ;;
  *)
    echo "refusing to remove unexpected Burrito install directory: $INSTALL_DIR" >&2
    exit 2
    ;;
esac

"$BINARY" --version

WARDWRIGHT_BIND="127.0.0.1:${PORT}" \
  WARDWRIGHT_SECRET_KEY_BASE="$SECRET" \
  WARDWRIGHT_SQLITE_STORE="$SQLITE_STORE" \
  "$BINARY" serve >"$LOG_FILE" 2>&1 &

PID="$!"
cleanup() {
  kill "$PID" >/dev/null 2>&1 || true
  wait "$PID" >/dev/null 2>&1 || true
  rm -f "$SQLITE_STORE" "$SQLITE_STORE"-shm "$SQLITE_STORE"-wal
}
trap cleanup EXIT

ready=0
for _ in $(seq 1 60); do
  if ! kill -0 "$PID" >/dev/null 2>&1; then
    cat "$LOG_FILE" >&2
    exit 1
  fi

  if curl -fsS "${BASE_URL}/v1/models" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.25
done

if [ "$ready" -ne 1 ]; then
  cat "$LOG_FILE" >&2
  exit 1
fi

curl -fsS "${BASE_URL}/" >/dev/null
curl -fsS "${BASE_URL}/admin" | grep -q "lustre-server-component"
curl -fsS "${BASE_URL}/v1/models" | grep -q "coding-balanced"
curl -fsS "${BASE_URL}/v1/wardwright/models" | grep -q "coding-balanced"
curl -fsS "${BASE_URL}/v1/chat/completions" \
  -H "content-type: application/json" \
  -d '{"model":"coding-balanced","messages":[{"role":"user","content":"burrito smoke"}]}' |
  grep -q '"status":"completed"'

for beam in "gleam@erlang@process" "gleam@json" gleam_stdlib glizzy lustre; do
  if ! find "$INSTALL_DIR/lib" -maxdepth 3 -path "*/ebin/${beam}.beam" -print -quit | grep -q .; then
    echo "packaged release missing ${beam}.beam in $INSTALL_DIR/lib" >&2
    find "$INSTALL_DIR/lib" -maxdepth 3 -type f -name "${beam}.beam" -print >&2
    cat "$LOG_FILE" >&2
    exit 1
  fi
done

if grep -Eq "UndefinedFunctionError|\\{:undef|:undef" "$LOG_FILE"; then
  cat "$LOG_FILE" >&2
  exit 1
fi

echo "Burrito smoke passed for $BINARY"
