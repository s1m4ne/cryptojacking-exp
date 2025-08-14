#!/usr/bin/env bash
set -Eeuo pipefail

NS="media-streaming"
SERVER_SVC=${SERVER_SVC:-server}
PROCS=${PROCS:-4}
VIDEO_COUNT=${VIDEO_COUNT:-1000}
RATE=${RATE:-10}
MODE=${MODE:-PT}
CLIENT_LABEL=${CLIENT_LABEL:-app=client}
SERVER_LABEL=${SERVER_LABEL:-app=server}

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(hexdump -n2 -e '2/1 "%02x"' /dev/urandom)"
BASE="media-streaming-${RUN_ID}"

RAW_DIR="dataset/raw"
TMP_DIR="dataset/tmp"
META_DIR="dataset/metadata"
LOG_DIR="logs"
mkdir -p "$RAW_DIR" "$TMP_DIR" "$META_DIR" "$LOG_DIR"

ALL="$TMP_DIR/${BASE}-all.jsonl"     # 全期間の生JSONL（後で削除）
RAW="$RAW_DIR/${BASE}.jsonl"         # ベンチ期間のみを抽出した成果物
LOG="$LOG_DIR/${BASE}.log"           # Tetragon 収集側のstderr
CLIENT_LOG="$LOG_DIR/${BASE}-client.log"   # client 実行ログ
META="$META_DIR/${BASE}.json"

# Tetragon のログを吐くコンテナ名を自動判定（export-stdout が無ければ tetragon を使う）
TETRA_CONT=$(
  kubectl -n kube-system get pods -l 'app.kubernetes.io/name=tetragon' \
    -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null \
  | tr ' ' '\n' | grep -m1 -E '^export-stdout$|^tetragon$' || true
)
if [ -z "${TETRA_CONT:-}" ]; then
  echo "[ERR] tetragon containers not found (export-stdout / tetragon)" >&2
  exit 1
fi

SINCE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
kubectl -n kube-system logs ds/tetragon -c "${TETRA_CONT}" -f --since-time="$SINCE" 2>"$LOG" \
| jq -c '
  select(.process_tracepoint?
         and .process_tracepoint.subsys=="raw_syscalls"
         and .process_tracepoint.event=="sys_exit"
         and .process_tracepoint.process.pod.namespace=="'"$NS"'"
         and (.process_tracepoint.process.pod.name|startswith("server-"))) |
  {
    ts: .time,
    pid: .process_tracepoint.process.pid,
    pod: .process_tracepoint.process.pod.name,
    container: .process_tracepoint.process.pod.container.name,
    sc: ((.process_tracepoint.args[0].long_arg)|tonumber),
    wl: "media-streaming"
  }' | tee "$ALL" &
MON_PID=$!

cleanup() { kill "$MON_PID" 2>/dev/null || true; wait "$MON_PID" 2>/dev/null || true; }
trap cleanup EXIT

# 監視ストリームが流れ始めたことを軽く確認
SERVER=$(kubectl -n "$NS" get pod -l "$SERVER_LABEL" -o jsonpath='{.items[0].metadata.name}')
for i in {1..25}; do
  kubectl -n "$NS" exec "$SERVER" -- sh -lc 'true' || true
  sleep 0.2
  if [ -s "$ALL" ]; then break; fi
done

START_TS="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
CLIENT=$(kubectl -n "$NS" get pod -l "$CLIENT_LABEL" -o jsonpath='{.items[0].metadata.name}')

# TTYなし(-iのみ)で client を実行し、混線を避けて専用ログへ出す
kubectl -n "$NS" exec -i "$CLIENT" -- \
  /root/docker-entrypoint.sh "$SERVER_SVC" "$PROCS" "$VIDEO_COUNT" "$RATE" "$MODE" \
  >>"$CLIENT_LOG" 2>&1 || true

END_TS="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
cleanup

# fromjson? で未完行を無視して、期間で切り出し
jq -cR --arg s "$START_TS" --arg e "$END_TS" \
  'fromjson? | select(.) | select(.ts >= $s and .ts <= $e)' "$ALL" > "$RAW"

cat > "$META" <<EOF
{
  "schema_version": 1,
  "base": "$BASE",
  "namespace": "$NS",
  "workload": "media-streaming",
  "event": "raw_syscalls:sys_exit",
  "bench": {
    "server": "$SERVER_SVC",
    "processes": $PROCS,
    "video_count": $VIDEO_COUNT,
    "rate_vps": $RATE,
    "mode": "$MODE"
  },
  "monitor_since": "$SINCE",
  "start_ts": "$START_TS",
  "end_ts": "$END_TS",
  "files": { "raw": "$RAW", "log": "$LOG", "client": "$CLIENT_LOG" },
  "fields": ["ts","pid","pod","container","sc","wl"]
}
EOF

COUNT=$(wc -l < "$RAW" | tr -d ' ')
echo "raw:    $RAW"
echo "log:    $LOG"
echo "client: $CLIENT_LOG"
echo "meta:   $META"
echo "syscalls (events): $COUNT"

rm -f "$ALL"
