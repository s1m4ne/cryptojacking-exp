#!/usr/bin/env bash
set -Eeuo pipefail

# ===== 設定（環境変数で上書き可）=====
NS="${NS:-xmrig}"
DEPLOY_YAML="${DEPLOY_YAML:-k8s/xmrig/xmrig-deploy.yaml}"

# どれくらい掘って記録するか（秒）
CAPTURE_SECS="${CAPTURE_SECS:-120}"
# 起動から「cpu READY」行が出るまで待つ最大時間（秒）
WAIT_READY="${WAIT_READY:-180}"

# ===== 出力先 =====
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(hexdump -n2 -e '2/1 "%02x"' /dev/urandom)"
BASE="xmrig-${RUN_ID}"

RAW_DIR="dataset/raw"
TMP_DIR="dataset/tmp"
META_DIR="dataset/metadata"
LOG_DIR="logs"
mkdir -p "$RAW_DIR" "$TMP_DIR" "$META_DIR" "$LOG_DIR"

ALL="$TMP_DIR/${BASE}-all.jsonl"     # 監視全体（後で削除）
RAW="$RAW_DIR/${BASE}.jsonl"         # 切り出し後（成果物）
LOG="$LOG_DIR/${BASE}.log"           # Tetragon 側ログ（stderr）
APPLOG="$LOG_DIR/${BASE}-xmrig.log"  # XMRig のアプリログ
META="$META_DIR/${BASE}.json"

# ===== 前提（NS/ConfigMap/Deployment）=====
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null
# ConfigMap が無いと Pod が CrashLoop するので事前チェック（無ければ終了）
kubectl -n "$NS" get configmap xmrig-config >/dev/null

# ===== Tetragon 監視開始 =====
SINCE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
kubectl -n kube-system logs ds/tetragon -c export-stdout -f --since-time="$SINCE" 2>"$LOG" \
| jq -c '
  select(.process_tracepoint?
         and .process_tracepoint.subsys=="raw_syscalls"
         and .process_tracepoint.event=="sys_exit"
         and .process_tracepoint.process.pod.namespace=="'"$NS"'"
         and (.process_tracepoint.process.pod.name|startswith("xmrig-"))) |
  {
    ts: .time,
    pid: .process_tracepoint.process.pid,
    pod: .process_tracepoint.process.pod.name,
    container: .process_tracepoint.process.pod.container.name,
    sc: ((.process_tracepoint.args[0].long_arg)|tonumber),
    wl: "xmrig"
  }' | tee "$ALL" &
MON_PID=$!

cleanup() {
  kill "$MON_PID" 2>/dev/null || true; wait "$MON_PID" 2>/dev/null || true
  kill "$APP_PID" 2>/dev/null || true; wait "$APP_PID" 2>/dev/null || true
}
trap cleanup EXIT

# ===== XMRig を起動（デプロイ適用 or リスタート）=====
if kubectl -n "$NS" get deploy/xmrig >/dev/null 2>&1; then
  kubectl -n "$NS" rollout restart deploy/xmrig
else
  kubectl apply -f "$DEPLOY_YAML"
fi
kubectl -n "$NS" rollout status deploy/xmrig --timeout="${WAIT_READY}s"

# ===== アプリログの保存（起動時刻から）=====
# since-time を Tetragon と合わせることで、Pod 再作成直後のログから保存できる
kubectl -n "$NS" logs -f deploy/xmrig --since-time="$SINCE" | tee "$APPLOG" &
APP_PID=$!

# ===== 「cpu READY」行を待つ（なければフォールバック）=====
START_TS=""
for ((i=0; i<WAIT_READY; i++)); do
  if LINE="$(grep -m1 -E 'cpu[[:space:]]+READY' "$APPLOG" || true)"; then
    if [ -n "$LINE" ]; then
      START_TS="$(printf '%s\n' "$LINE" | sed -E 's/^\[([^]]+)\].*/\1/; s/ /T/; s/$/Z/')"
      break
    fi
  fi
  sleep 1
done
if [ -z "${START_TS:-}" ]; then
  # 初期化中の最初の目印（use pool）があればそれ、無ければ監視開始時刻
  if LINE="$(grep -m1 -E 'use pool ' "$APPLOG" || true)"; then
    START_TS="$(printf '%s\n' "$LINE" | sed -E 's/^\[([^]]+)\].*/\1/; s/ /T/; s/$/Z/')"
  else
    START_TS="$SINCE"
  fi
fi

# ===== 観測時間だけ待つ =====
sleep "$CAPTURE_SECS"
END_TS="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"

# ===== 停止＆切り出し =====
cleanup
trap - EXIT

jq -c --arg s "$START_TS" --arg e "$END_TS" \
  'select(.ts >= $s and .ts <= $e)' "$ALL" > "$RAW"

cat > "$META" <<EOF
{
  "schema_version": 1,
  "base": "$BASE",
  "namespace": "$NS",
  "workload": "xmrig",
  "event": "raw_syscalls:sys_exit",
  "bench": {
    "capture_secs": $CAPTURE_SECS,
    "wait_ready_secs": $WAIT_READY
  },
  "monitor_since": "$SINCE",
  "start_ts": "$START_TS",
  "end_ts": "$END_TS",
  "files": { "raw": "$RAW", "log": "$LOG", "applog": "$APPLOG" },
  "fields": ["ts","pid","pod","container","sc","wl"]
}
EOF

COUNT=$(wc -l < "$RAW" | tr -d ' ')
echo "raw:    $RAW"
echo "log:    $LOG"
echo "applog: $APPLOG"
echo "meta:   $META"
echo "syscalls (events): $COUNT"

rm -f "$ALL"
