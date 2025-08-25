#!/usr/bin/env bash
set -Eeuo pipefail

# ===== 設定 =====
NS="web-serving"
CONTAINER="web"
WL="web-serving"
USERS=${USERS:-50}
RAMP_UP=${RAMP_UP:-60}
STEADY=${STEADY:-300}
RAMP_DOWN=${RAMP_DOWN:-60}

# ===== 出力準備 =====
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(hexdump -n2 -e '2/1 "%02x"' /dev/urandom)"
BASE="${NS}-${RUN_ID}"

RAW_DIR="dataset/raw"
TMP_DIR="dataset/tmp"
META_DIR="dataset/metadata"
LOG_DIR="logs"
mkdir -p "$RAW_DIR" "$TMP_DIR" "$META_DIR" "$LOG_DIR"

ALL="$TMP_DIR/${BASE}-all.jsonl"
RAW="$RAW_DIR/${BASE}.jsonl"
LOGF="$LOG_DIR/${BASE}.log"
METAF="$META_DIR/${BASE}.json"

: > "$ALL"

log(){ echo "[log $(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

# ===== フェーズ1: tetragon ストリーム開始 =====
SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "start tetragon stream since=$SINCE (ns=$NS, container=$CONTAINER)"

setsid bash -c '
  kubectl -n kube-system logs ds/tetragon -c export-stdout -f --since-time="'"$SINCE"'" 2>"'"$LOGF"'" \
  | jq -rc --arg wl "'"$WL"'" --arg ns "'"$NS"'" --arg cn "'"$CONTAINER"'" "
      . as \$e
      | select(
          \$e.process_tracepoint
          and ((\$e.process_tracepoint.subsys // \$e.process_tracepoint.subsystem) == \"raw_syscalls\")
          and (\$e.process_tracepoint.event == \"sys_exit\")
          and (\$e.process_tracepoint.process.pod.namespace == \$ns)
          and ((\$e.process_tracepoint.process.pod.container.name // \"\") == \$cn)
        )
      | {
          ts: (\$e.time),
          pid: (\$e.process_tracepoint.process.pid // 0),
          pod: (\$e.process_tracepoint.process.pod.name // \"\"),
          container: (\$e.process_tracepoint.process.pod.container.name // \"\"),
          sc: (
            ( \$e.process_tracepoint.args
              | if type==\"array\" and length>0 then .[0].long_arg else \"0\" end
            ) | tonumber
          ),
          wl: \$wl
        }" \
  | tee -a "'"$ALL"'"
' &
MON_GRP=$!

cleanup() {
  log "cleanup: stopping tetragon stream pgid=$MON_GRP"
  kill -TERM -"$MON_GRP" 2>/dev/null || true
  sleep 0.3
  kill -KILL -"$MON_GRP" 2>/dev/null || true
}
trap cleanup EXIT

# ===== フェーズ2: faban 実行 =====
sleep 1
START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "benchmark START_TS=$START_TS"

FABAN="$(kubectl -n "$NS" get pods -l app=faban-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[ -z "$FABAN" ] && FABAN="$(kubectl -n "$NS" get pods -l job-name=faban-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

if [ -z "$FABAN" ]; then
  log "ERROR: faban-client pod not found in namespace '$NS'"
  exit 1
fi
log "faban pod=$FABAN"

kubectl -n "$NS" exec -i "$FABAN" -- \
  /web20_benchmark/run/entrypoint.sh web "$USERS" \
    --oper=run --ramp-up="$RAMP_UP" --steady="$STEADY" --ramp-down="$RAMP_DOWN"
RET=$?
log "faban exec returned code=$RET (expect 0)"

END_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "benchmark END_TS=$END_TS"

cleanup

# ===== フェーズ3: 切り出しと保存 =====
ALL_LINES=$(wc -l < "$ALL" 2>/dev/null || echo 0)
FIRST_TS=$(head -n1 "$ALL" 2>/dev/null | jq -r '.ts' || true)
LAST_TS=$( tail -n1 "$ALL" 2>/dev/null | jq -r '.ts' || true)
log "ALL summary: lines=$ALL_LINES first_ts=${FIRST_TS:-NA} last_ts=${LAST_TS:-NA}"

if [ "$ALL_LINES" -eq 0 ]; then
  log "DONE (NO EVENTS): ALL is empty."
  echo "ALL lines: $ALL_LINES ($ALL)"
  echo "RAW lines: 0 (not created)"
  echo "log:       $LOGF"
  exit 0
fi

jq -Rrc --arg s "$START_TS" --arg e "$END_TS" '
  def toepoch($x):
    ($x | sub("\\.[0-9]+Z$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime);
  def safe_row:
    (fromjson? // empty) as $j
    | ($j.ts | sub("\\.[0-9]+Z$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) as $t
    | select($t >= toepoch($s) and $t <= toepoch($e))
    | $j;
  safe_row
' "$ALL" > "$RAW"

cat > "$METAF" <<EOF
{
  "schema_version": 1,
  "base": "$BASE",
  "namespace": "$NS",
  "workload": "$WL",
  "event": "raw_syscalls:sys_exit",
  "bench": { "users": $USERS, "ramp_up_s": $RAMP_UP, "steady_s": $STEADY, "ramp_down_s": $RAMP_DOWN },
  "monitor_since": "$SINCE",
  "start_ts": "$START_TS",
  "end_ts": "$END_TS",
  "files": { "all": "$ALL", "raw": "$RAW", "log": "$LOGF", "meta": "$METAF" },
  "fields": ["ts","pid","pod","container","sc","wl"]
}
EOF

RAW_LINES=$(wc -l < "$RAW" 2>/dev/null || echo 0)

echo "ALL lines: $ALL_LINES ($ALL)"
echo "RAW lines: $RAW_LINES ($RAW)"
echo "log:       $LOGF"
echo "meta:      $METAF"

if [ "$RAW_LINES" -gt 0 ]; then
  rm -f "$ALL"
  log "DONE (RAW saved, ALL removed)"
else
  log "DONE (RAW empty, ALL kept for debug)"
fi
