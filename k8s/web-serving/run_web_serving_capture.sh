#!/usr/bin/env bash
set -Eeuo pipefail

NS="web-serving"
USERS=${USERS:-50}
RAMP_UP=${RAMP_UP:-60}
STEADY=${STEADY:-300}
RAMP_DOWN=${RAMP_DOWN:-60}

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(hexdump -n2 -e '2/1 "%02x"' /dev/urandom)"
BASE="web-serving-${RUN_ID}"

RAW_DIR="dataset/raw"
TMP_DIR="dataset/tmp"
META_DIR="dataset/metadata"
LOG_DIR="logs"
mkdir -p "$RAW_DIR" "$TMP_DIR" "$META_DIR" "$LOG_DIR"

ALL="$TMP_DIR/${BASE}-all.jsonl"      # 監視全体（後で削除）
RAW="$RAW_DIR/${BASE}.jsonl"          # ベンチ区間のみ（最終成果物）
LOG="$LOG_DIR/${BASE}.log"
META="$META_DIR/${BASE}.json"

SINCE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
kubectl -n kube-system logs ds/tetragon -c export-stdout -f --since-time="$SINCE" 2>"$LOG" \
| jq -c '
  select(.process_tracepoint?
         and .process_tracepoint.subsys=="raw_syscalls"
         and .process_tracepoint.event=="sys_exit"
         and .process_tracepoint.process.pod.namespace=="web-serving"
         and (.process_tracepoint.process.pod.name|startswith("web-"))) |
  {
    ts: .time,
    pid: .process_tracepoint.process.pid,
    pod: .process_tracepoint.process.pod.name,
    container: .process_tracepoint.process.pod.container.name,
    sc: ((.process_tracepoint.args[0].long_arg)|tonumber),
    wl: "web-serving"
  }' | tee "$ALL" &
MON_PID=$!

cleanup() { kill "$MON_PID" 2>/dev/null || true; wait "$MON_PID" 2>/dev/null || true; }
trap cleanup EXIT

WEB=$(kubectl -n "$NS" get pod -l app=web -o jsonpath='{.items[0].metadata.name}')
for i in {1..25}; do
  kubectl -n "$NS" exec "$WEB" -- sh -lc 'true' || true
  sleep 0.2
  if [ -s "$ALL" ]; then break; fi
done

START_TS="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
FABAN=$(kubectl -n "$NS" get pod -l app=faban-client -o jsonpath='{.items[0].metadata.name}')
kubectl -n "$NS" exec -it "$FABAN" -- \
  /web20_benchmark/run/entrypoint.sh web "$USERS" \
    --oper=run --ramp-up="$RAMP_UP" --steady="$STEADY" --ramp-down="$RAMP_DOWN"
END_TS="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"

cleanup

jq -c --arg s "$START_TS" --arg e "$END_TS" \
  'select(.ts >= $s and .ts <= $e)' "$ALL" > "$RAW"

cat > "$META" <<EOF
{
  "schema_version": 1,
  "base": "$BASE",
  "namespace": "$NS",
  "workload": "web-serving",
  "event": "raw_syscalls:sys_exit",
  "bench": { "users": $USERS, "ramp_up_s": $RAMP_UP, "steady_s": $STEADY, "ramp_down_s": $RAMP_DOWN },
  "monitor_since": "$SINCE",
  "start_ts": "$START_TS",
  "end_ts": "$END_TS",
  "files": { "raw": "$RAW", "log": "$LOG" },
  "fields": ["ts","pid","pod","container","sc","wl"]
}
EOF

# 総件数（=システムコール数）を表示
COUNT=$(wc -l < "$RAW" | tr -d ' ')
echo "raw:  $RAW"
echo "log:  $LOG"
echo "meta: $META"
echo "syscalls (events): $COUNT"

rm -f "$ALL"
