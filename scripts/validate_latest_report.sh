#!/usr/bin/env bash
set -euo pipefail
# Validate structure of latest runs/*/report.json (minimal check)
cd "$(dirname "$0")/.."
if ! ls runs >/dev/null 2>&1; then
  echo "No runs directory" >&2; exit 1
fi
latest=$(ls -1t runs | head -n1)
report="runs/$latest/report.json"
[ -f "$report" ] || { echo "Report not found: $report" >&2; exit 1; }
if command -v jq >/dev/null 2>&1; then
  jq 'has("status") and has("run_id") and has("start_iso") and has("end_iso") and has("kernel")' "$report" | grep -q true || { echo "Report missing required fields" >&2; exit 1; }
  jq . "$report"
else
  # Fallback: simple grep checks
  for key in status run_id start_iso end_iso kernel; do
    grep -q "\"$key\"" "$report" || { echo "Missing key: $key" >&2; exit 1; }
  done
  cat "$report"
fi
