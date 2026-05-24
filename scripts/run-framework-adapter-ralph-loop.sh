#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
retry_delay_seconds="${RALPH_RETRY_DELAY_SECONDS:-${RALPH_INTERVAL_SECONDS:-900}}"
idle_delay_seconds="${RALPH_IDLE_DELAY_SECONDS:-300}"
state_dir="$(cd "$repo_root" && git rev-parse --git-path ralph-runs/framework-adapter-validation)"
sentinel="$state_dir/complete"
log_file="$state_dir/runner.log"
prompt_file="docs/ralph-runs/framework-adapter-validation-loop-prompt.md"
lock_dir="$state_dir/lock"

mkdir -p "$state_dir"

if ! command -v codex >/dev/null 2>&1; then
  echo "codex is required for the framework adapter Ralph loop" >&2
  exit 127
fi

if ! mkdir "$lock_dir" 2>/dev/null; then
  existing_pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
  if [[ -z "$existing_pid" ]] || ! kill -0 "$existing_pid" 2>/dev/null; then
    rm -rf "$lock_dir"
    mkdir "$lock_dir"
  else
    echo "framework adapter Ralph loop already appears to be running: $lock_dir" >&2
    exit 75
  fi
fi

if [[ ! -d "$lock_dir" ]]; then
  echo "framework adapter Ralph loop already appears to be running: $lock_dir" >&2
  exit 75
fi
echo "$$" >"$lock_dir/pid"

cleanup() {
  rm -f "$lock_dir/pid" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "framework adapter Ralph loop runner started at $(date -Iseconds)" >>"$log_file"
echo "repo: $repo_root" >>"$log_file"
echo "retry_delay_seconds: $retry_delay_seconds" >>"$log_file"
echo "idle_delay_seconds: $idle_delay_seconds" >>"$log_file"

while true; do
  if [[ -f "$sentinel" ]]; then
    echo "[$(date -Iseconds)] completion sentinel present; idling" >>"$log_file"
    sleep "$idle_delay_seconds"
    continue
  fi

  started_at="$(date -Iseconds)"
  echo "[$started_at] starting iteration" >>"$log_file"

  if {
    cat "$repo_root/$prompt_file"
    printf '\n\nRun one iteration using the Ralph loop prompt above.\n'
  } | codex exec \
    --cd "$repo_root" \
    --sandbox danger-full-access \
    --dangerously-bypass-approvals-and-sandbox \
    - >>"$log_file" 2>&1; then
    echo "[$(date -Iseconds)] iteration completed" >>"$log_file"
  else
    status=$?
    echo "[$(date -Iseconds)] iteration failed with status $status" >>"$log_file"
    if [[ ! -f "$sentinel" ]]; then
      echo "[$(date -Iseconds)] sleeping $retry_delay_seconds seconds before retry" >>"$log_file"
      sleep "$retry_delay_seconds"
    fi
  fi

done
