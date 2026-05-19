#!/usr/bin/env bash
# Require docs, screenshots, or an explicit acknowledgement when UI files change.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

MODE="range"
BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staged)
      MODE="staged"
      shift
      ;;
    --base)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "missing value for --base" >&2
        exit 2
      fi
      BASE="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$MODE" == "staged" ]]; then
  changed_files="$(git diff --cached --name-only --diff-filter=ACMRD)"
else
  if [[ -z "$BASE" ]]; then
    if [[ -n "${GITHUB_BASE_REF:-}" ]] && git rev-parse --verify "origin/${GITHUB_BASE_REF}" >/dev/null 2>&1; then
      BASE="origin/${GITHUB_BASE_REF}"
    elif git rev-parse --verify HEAD^ >/dev/null 2>&1; then
      BASE="HEAD^"
    else
      BASE="HEAD"
    fi
  fi

  changed_files="$(git diff --name-only --diff-filter=ACMRD "${BASE}...HEAD" 2>/dev/null || git diff --name-only --diff-filter=ACMRD "${BASE}" HEAD)"
fi

if [[ -z "$changed_files" ]]; then
  exit 0
fi

ui_changes="$(printf '%s\n' "$changed_files" | grep -E '^(app/src/wardwright/lustre_(workbench|model_access).*\.gleam|app/lib/wardwright_web/(live|components|controllers?|templates?|layouts?)/|app/lib/wardwright_web/(lustre_workbench_controller|lustre_model_access_(controller|socket|data)|policy_projection_live|model_api_keys_live|layouts)\.ex|app/priv/static/assets/|app/assets/)' || true)"

if [[ -z "$ui_changes" ]]; then
  exit 0
fi

ui_doc_evidence="$(printf '%s\n' "$changed_files" | grep -E '^(README\.md|docs/.*\.(md|png|jpg|jpeg|webp|gif)|docs/ui-change-acknowledgements/)' || true)"

if [[ -n "$ui_doc_evidence" ]]; then
  exit 0
fi

cat >&2 <<'MSG'
UI files changed without docs, screenshots, or an explicit acknowledgement.

Update README/docs, update screenshots under docs/assets, or add a short
acknowledgement file under docs/ui-change-acknowledgements/ explaining why no
user-facing docs/screenshot change is needed.
MSG

printf '\nUI files:\n%s\n' "$ui_changes" >&2
exit 1
