#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-local}"
DURATION="${DURATION:-30s}"
CONCURRENCY="${CONCURRENCY:-200}"
WARMUP_DURATION="${WARMUP_DURATION:-5s}"
WARMUP_CONCURRENCY="${WARMUP_CONCURRENCY:-50}"

TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT/results/$TS-$MODE"
mkdir -p "$OUT_DIR"
echo "Output dir: $OUT_DIR"

ENDPOINTS=(
  "GET / root"
  "GET /json json"
  "GET /params/42 params"
  "POST /echo echo"
)

run_oha() {
  local label="$1" base="$2" method="$3" path="$4" suffix="$5"
  local out="$OUT_DIR/${label}__${suffix}.json"
  echo "  -> $method $path"
  local extra=()
  if [[ "$method" == "POST" ]]; then
    extra=(-m POST -d '{"hello":"world"}' -T application/json)
  fi
  oha -z "$WARMUP_DURATION" -c "$WARMUP_CONCURRENCY" --no-tui ${extra[@]+"${extra[@]}"} "$base$path" >/dev/null 2>&1
  oha -z "$DURATION" -c "$CONCURRENCY" --no-tui --output-format json ${extra[@]+"${extra[@]}"} "$base$path" >"$out"
}

bench_target() {
  local label="$1" base="$2"
  echo "==> $label  ($base)"
  for ep in "${ENDPOINTS[@]}"; do
    read -r method path suffix <<<"$ep"
    run_oha "$label" "$base" "$method" "$path" "$suffix"
  done
}

wait_ready() {
  local base="$1"
  for _ in $(seq 1 120); do
    if curl -fsS "$base/" >/dev/null 2>&1; then return 0; fi
    sleep 0.5
  done
  return 1
}

# Recursively kill a process and its descendants.
killtree() {
  local pid="$1"
  local child
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    killtree "$child"
  done
  kill "$pid" 2>/dev/null || true
}

PIDS=()
cleanup() {
  for pid in ${PIDS[@]+"${PIDS[@]}"}; do
    killtree "$pid"
  done
}
trap cleanup EXIT INT TERM

run_local_app() {
  local label="$1" port="$2" workdir="$3"
  shift 3
  local base="http://127.0.0.1:$port"
  echo
  echo "Starting $label..."
  ( cd "$workdir" && exec "$@" ) > "$OUT_DIR/$label.log" 2>&1 &
  local pid=$!
  PIDS+=("$pid")
  if ! wait_ready "$base"; then
    echo "  !! $label failed to start (see $OUT_DIR/$label.log)"
    killtree "$pid"
    return 1
  fi
  bench_target "$label" "$base"
  killtree "$pid"
  wait "$pid" 2>/dev/null || true
}

if [[ "$MODE" == "local" ]]; then
  run_local_app workerd-hono   8787 "$ROOT/apps/workerd-hono"   bunx wrangler dev --port 8787 --ip 127.0.0.1
  run_local_app workerd-elysia 8788 "$ROOT/apps/workerd-elysia" bunx wrangler dev --port 8788 --ip 127.0.0.1
  run_local_app bun-hono       3000 "$ROOT/apps/bun-hono"       bun run index.ts
  run_local_app bun-elysia     3001 "$ROOT/apps/bun-elysia"     bun run index.ts
elif [[ "$MODE" == "remote" ]]; then
  if [[ ! -f "$ROOT/targets.remote.json" ]]; then
    echo "targets.remote.json not found. Copy targets.remote.example.json and fill in URLs."
    exit 1
  fi
  while IFS=$'\t' read -r label base; do
    bench_target "$label" "$base"
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$ROOT/targets.remote.json")
else
  echo "Usage: $0 [local|remote]"
  exit 1
fi

echo
echo "Done. Results: $OUT_DIR"
echo "Run:  $ROOT/summarize.sh $OUT_DIR"
