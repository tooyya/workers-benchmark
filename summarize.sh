#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIR="${1:-}"
if [[ -z "$DIR" ]]; then
  DIR="$(ls -dt "$ROOT"/results/*/ 2>/dev/null | head -1)"
  DIR="${DIR%/}"
fi
[[ -d "$DIR" ]] || { echo "Usage: $0 <results-dir>"; exit 1; }

echo "Summary: $DIR"
echo
printf "%-34s %12s %12s %12s %12s\n" "test" "rps" "avg(ms)" "p50(ms)" "p99(ms)"
printf "%-34s %12s %12s %12s %12s\n" "----" "---" "-------" "-------" "-------"
for f in "$DIR"/*.json; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f" .json)"
  jq -r --arg name "$name" '
    [
      $name,
      (.summary.requestsPerSec // 0 | floor),
      ((.summary.average // 0) * 1000),
      ((.latencyPercentiles.p50 // 0) * 1000),
      ((.latencyPercentiles.p99 // 0) * 1000)
    ] | @tsv
  ' "$f" 2>/dev/null | awk -F'\t' '{ printf "%-34s %12d %12.3f %12.3f %12.3f\n", $1, $2, $3, $4, $5 }'
done
