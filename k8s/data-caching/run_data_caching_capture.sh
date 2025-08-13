#!/usr/bin/env bash
set -Eeuo pipefail

NS="data-caching"

# ベンチ設定（環境変数で上書き可）
SCALE=${SCALE:-6}            # S&W/RPS/TH で使う S
WORKERS=${WORKERS:-4}
SERVER_MEMORY=${SERVER_MEMORY:-2048}
GET_RATIO=${GET_RATIO:-0.8}
CONNECTION=${CONNECTION:-200}
INTERVAL=${INTERVAL:-1}
MODE=${MODE:-TH}             # TH or RPS
RPS=${RPS:-100000}
DURATION=${DURATION:-60}     # TH/RPS 実行秒数
PREPARE=${PREPARE:-1}        # 1=事前に S&W 実施（安全）
PREPARE_TIMEOUT=${PREPARE_TIMEOUT:-120}

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(hexdump -n2 -e '2/1 "%02x"' /dev/urandom)"
BASE="data-caching-${RUN_ID}"

RAW_DIR="dataset/raw"
TMP_DIR="dataset/tmp"
META_DIR="dataset/metadata"
LOG_DIR="logs"
mkdir -p "$RAW_DIR" "$TMP_DIR" "$META_DIR" "$LOG_DIR"

ALL="$TMP_DIR/${BASE}-all.jsonl"
RAW="$RAW_DIR/${BASE}.jsonl"
LOG="$LOG_DIR/${BASE}.log"
META="$META_DIR/${BASE}.json"

SINCE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
kubectl -n kube-system logs ds/tetragon -c export-stdout -f --since-time="$SINCE" 2>"$LOG" \
| jq -c '
  select(.process_tracepoint?
         and .process_tracepoint.subsys=="raw_syscalls"
         and .process_tracepoint.event=="sys_exit"
         and .process_tracepoint.process.pod.namespace=="data-caching"
         and (.process_tracepoint.process.pod.name|startswith("server-"))) |
  {
    ts: .time,
    pid: .process_tracepoint.process.pid,
    pod: .process_tracepoint.process.pod.name,
    container: .process_tracepoint.process.pod.container.name,
    sc: ((.process_tracepoint.args[0].long_arg)|tonumber),
    wl: "data-caching"
  }' | tee "$ALL" &
MON_PID=$!

cleanup() { kill "$MON_PID" 2>/dev/null || true; wait "$MON_PID" 2>/dev/null || true; }
trap cleanup EXIT

SERVER=$(kubectl -n "$NS" get pod -l app=server -o jsonpath='{.items[0].metadata.name}')
for i in {1..25}; do
  kubectl -n "$NS" exec "$SERVER" -- sh -lc 'true' || true
  sleep 0.2
  if [ -s "$ALL" ]; then break; fi
done

CLIENT=$(kubectl -n "$NS" get pod -l app=client -o jsonpath='{.items[0].metadata.name}')
kubectl -n "$NS" exec "$CLIENT" -- sh -lc '
  base=/usr/src/memcached/memcached_client
  mkdir -p "$base/docker_servers"
  echo "server, 11211" > "$base/docker_servers/docker_servers.txt"
  ln -sf docker_servers/docker_servers.txt "$base/docker_servers.txt"
  head -n1 "$base/docker_servers/docker_servers.txt"
' >/dev/null

if [ "$PREPARE" = "1" ]; then
  kubectl -n "$NS" exec -it "$CLIENT" -- \
    timeout "$PREPARE_TIMEOUT" /entrypoint.sh --m=S\&W --S="$SCALE" --D="$SERVER_MEMORY" --w="$WORKERS" --T="$INTERVAL" || true
fi

START_TS="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
if [ "$MODE" = "TH" ]; then
  kubectl -n "$NS" exec -it "$CLIENT" -- \
    timeout "$DURATION" /entrypoint.sh --m=TH --S="$SCALE" --w="$WORKERS" --D="$SERVER_MEMORY" --g="$GET_RATIO" --c="$CONNECTION" --T="$INTERVAL" || true
else
  kubectl -n "$NS" exec -it "$CLIENT" -- \
    timeout "$DURATION" /entrypoint.sh --m=RPS --S="$SCALE" --g="$GET_RATIO" --c="$CONNECTION" --w="$WORKERS" --T="$INTERVAL" --r="$RPS" || true
fi
END_TS="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"

cleanup

jq -c --arg s "$START_TS" --arg e "$END_TS" \
  'select(.ts >= $s and .ts <= $e)' "$ALL" > "$RAW"

cat > "$META" <<EOF
{
  "schema_version": 1,
  "base": "$BASE",
  "namespace": "$NS",
  "workload": "data-caching",
  "event": "raw_syscalls:sys_exit",
  "bench": {
    "mode": "$MODE",
    "duration_s": $DURATION,
    "scale": $SCALE,
    "workers": $WORKERS,
    "server_memory_mb": $SERVER_MEMORY,
    "get_ratio": $GET_RATIO,
    "connections": $CONNECTION,
    "interval_s": $INTERVAL,
    "rps": $RPS,
    "prepare": $PREPARE,
    "prepare_timeout_s": $PREPARE_TIMEOUT
  },
  "monitor_since": "$SINCE",
  "start_ts": "$START_TS",
  "end_ts": "$END_TS",
  "files": { "raw": "$RAW", "log": "$LOG" },
  "fields": ["ts","pid","pod","container","sc","wl"]
}
EOF

COUNT=$(wc -l < "$RAW" | tr -d ' ')
echo "raw:  $RAW"
echo "log:  $LOG"
echo "meta: $META"
echo "syscalls (events): $COUNT"

rm -f "$ALL"
