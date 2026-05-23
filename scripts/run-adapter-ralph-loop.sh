#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
retry_delay_seconds="${RALPH_RETRY_DELAY_SECONDS:-${RALPH_INTERVAL_SECONDS:-900}}"
state_dir="$(cd "$repo_root" && git rev-parse --git-path ralph-runs/adapter-install-validation)"
sentinel="$state_dir/complete"
log_file="$state_dir/runner.log"
prompt_file="docs/ralph-runs/adapter-install-validation-loop-prompt.md"
lock_dir="$state_dir/lock"

mkdir -p "$state_dir"

if ! command -v codex >/dev/null 2>&1; then
  echo "codex is required for the adapter Ralph loop" >&2
  exit 127
fi

if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "adapter Ralph loop already appears to be running: $lock_dir" >&2
  exit 75
fi

cleanup() {
  rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "adapter Ralph loop runner started at $(date -Iseconds)" >>"$log_file"
echo "repo: $repo_root" >>"$log_file"
echo "retry_delay_seconds: $retry_delay_seconds" >>"$log_file"

while [[ ! -f "$sentinel" ]]; do
  started_at="$(date -Iseconds)"
  echo "[$started_at] starting iteration" >>"$log_file"

  if {
    cat "$repo_root/$prompt_file"
    printf '\n\nRun one iteration using the Ralph loop prompt above.\n'
  } | codex exec \
    --cd "$repo_root" \
    --sandbox danger-full-access \
    --ask-for-approval never \
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

  if [[ -f "$sentinel" ]]; then
    break
  fi
done

echo "adapter Ralph loop runner stopped at $(date -Iseconds)" >>"$log_file"
