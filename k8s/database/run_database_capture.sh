#!/usr/bin/env bash
set -Eeuo pipefail

# ===== 設定（環境変数で上書き可）=====
NS="database"

# sysbench パラメータ
TABLES=${TABLES:-8}
TABLE_SIZE=${TABLE_SIZE:-100000}
THREADS=${THREADS:-8}
TIME=${TIME:-60}
PREPARE=${PREPARE:-1}             # 1=毎回prepare、0=スキップ
PREPARE_TIMEOUT=${PREPARE_TIMEOUT:-300}

# 出力先
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(hexdump -n2 -e '2/1 "%02x"' /dev/urandom)"
BASE="database-${RUN_ID}"

RAW_DIR="dataset/raw"
TMP_DIR="dataset/tmp"
META_DIR="dataset/metadata"
LOG_DIR="logs"
mkdir -p "$RAW_DIR" "$TMP_DIR" "$META_DIR" "$LOG_DIR"

ALL="$TMP_DIR/${BASE}-all.jsonl"   # 監視全体（後で削除）
RAW="$RAW_DIR/${BASE}.jsonl"       # ベンチ区間のみ（最終成果物）
LOG="$LOG_DIR/${BASE}.log"
META="$META_DIR/${BASE}.json"

# ===== Tetragon 監視開始 =====
SINCE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
kubectl -n kube-system logs ds/tetragon -c export-stdout -f --since-time="$SINCE" 2>"$LOG" \
| jq -c '
  select(.process_tracepoint?
         and .process_tracepoint.subsys=="raw_syscalls"
         and .process_tracepoint.event=="sys_exit"
         and .process_tracepoint.process.pod.namespace=="'"$NS"'"
         and (.process_tracepoint.process.pod.name|startswith("mariadb-"))) |
  {
    ts: .time,
    pid: .process_tracepoint.process.pid,
    pod: .process_tracepoint.process.pod.name,
    container: .process_tracepoint.process.pod.container.name,
    sc: ((.process_tracepoint.args[0].long_arg)|tonumber),
    wl: "database"
  }' | tee "$ALL" &
MON_PID=$!

cleanup() { kill "$MON_PID" 2>/dev/null || true; wait "$MON_PID" 2>/dev/null || true; }
trap cleanup EXIT

# ===== 対象Podの準備待ち =====
SB="$(kubectl -n "$NS" get pod -l app=sysbench -o jsonpath='{.items[0].metadata.name}')"

# MariaDB に接続可能になるまで待つ
for i in {1..30}; do
  if kubectl -n "$NS" exec "$SB" -- sh -lc 'mysql -hmariadb -uroot -prootpass -e "SELECT 1"' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# 監視のウォームアップ用に軽いクエリを1回
kubectl -n "$NS" exec "$SB" -- sh -lc 'mysql -hmariadb -uroot -prootpass -e "DO 1"' >/dev/null 2>&1 || true

# 監視ファイルに1行でも入るまで最大5秒だけ待つ（任意）
for i in {1..25}; do
  [ -s "$ALL" ] && break
  sleep 0.2
done

# ===== 必要ならデータ準備（prepare）=====
if [ "$PREPARE" = "1" ]; then
  kubectl -n "$NS" exec -it "$SB" -- \
    timeout "$PREPARE_TIMEOUT" sysbench oltp_read_write --db-driver=mysql \
      --mysql-host=mariadb --mysql-db=bench \
      --mysql-user=sbtest --mysql-password=sbpass \
      --tables="$TABLES" --table-size="$TABLE_SIZE" prepare || true
fi

# ===== ベンチ本番 =====
START_TS="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
kubectl -n "$NS" exec -it "$SB" -- \
  sysbench oltp_read_write --db-driver=mysql \
    --mysql-host=mariadb --mysql-db=bench \
    --mysql-user=sbtest --mysql-password=sbpass \
    --tables="$TABLES" --table-size="$TABLE_SIZE" \
    --threads="$THREADS" --time="$TIME" --report-interval=5 run
END_TS="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"

# ===== 監視停止 & 切り出し =====
cleanup

jq -c --arg s "$START_TS" --arg e "$END_TS" \
  'select(.ts >= $s and .ts <= $e)' "$ALL" > "$RAW"

cat > "$META" <<EOF
{
  "schema_version": 1,
  "base": "$BASE",
  "namespace": "$NS",
  "workload": "database",
  "event": "raw_syscalls:sys_exit",
  "bench": {
    "tables": $TABLES,
    "table_size": $TABLE_SIZE,
    "threads": $THREADS,
    "time_s": $TIME,
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
