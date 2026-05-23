#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
interval_seconds="${RALPH_INTERVAL_SECONDS:-900}"
state_dir="$repo_root/.git/ralph-runs/adapter-install-validation"
sentinel="$state_dir/complete"
log_file="$state_dir/runner.log"
prompt_file="docs/ralph-runs/adapter-install-validation-loop-prompt.md"
lock_dir="$state_dir/lock"

mkdir -p "$state_dir"

if ! command -v opencode >/dev/null 2>&1; then
  echo "opencode is required for the adapter Ralph loop" >&2
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
echo "interval_seconds: $interval_seconds" >>"$log_file"

while [[ ! -f "$sentinel" ]]; do
  started_at="$(date -Iseconds)"
  echo "[$started_at] starting iteration" >>"$log_file"

  if opencode run \
    --dir "$repo_root" \
    --title "Wardwright adapter install validation Ralph loop" \
    --file "$repo_root/$prompt_file" \
    --dangerously-skip-permissions \
    "Run one iteration using the attached Ralph loop prompt." >>"$log_file" 2>&1; then
    echo "[$(date -Iseconds)] iteration completed" >>"$log_file"
  else
    status=$?
    echo "[$(date -Iseconds)] iteration failed with status $status" >>"$log_file"
  fi

  if [[ -f "$sentinel" ]]; then
    break
  fi

  echo "[$(date -Iseconds)] sleeping $interval_seconds seconds" >>"$log_file"
  sleep "$interval_seconds"
done

echo "adapter Ralph loop runner stopped at $(date -Iseconds)" >>"$log_file"
