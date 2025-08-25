#!/usr/bin/env bash
# run_data_caching_capture.sh
# Collect raw_syscalls tracepoint events for the data-caching (memcached) workload
# and cut out just the benchmark window, mirroring media-streaming's stable flow.

set -Eeuo pipefail

# ====== Tunables (env override OK) ============================================
NS="data-caching"
SERVER_SVC=${SERVER_SVC:-server}      # Service hostname written to docker_servers.txt
PORT=${PORT:-11211}

# Tetragon event side
EVENT=${EVENT:-sys_enter}             # sys_enter (default) / sys_exit (switch if you add policy)
# Note: subsys/event fields may not be present due to fieldFilters, so jq doesn't rely on them.

# Client bench params (defaults reflect your manual runs)
S=${S:-6}         # shard/bucket size used to pick twitter_dataset_?x
D=${D:-2048}
W=${W:-4}
T=${T:-1}
G=${G:-0.8}
C=${C:-200}
R=${R:-100000}
TH_DUR=${TH_DUR:-60}
RPS_DUR=${RPS_DUR:-20}

CLIENT_LABEL=${CLIENT_LABEL:-app=client}
SERVER_LABEL=${SERVER_LABEL:-app=server}

# ====== Paths & filenames =====================================================
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(hexdump -n2 -e '2/1 "%02x"' /dev/urandom)"
BASE="data-caching-${RUN_ID}"

RAW_DIR="dataset/raw"
TMP_DIR="dataset/tmp"
META_DIR="dataset/metadata"
LOG_DIR="logs"
mkdir -p "$RAW_DIR" "$TMP_DIR" "$META_DIR" "$LOG_DIR"

ALL="$TMP_DIR/${BASE}-all.jsonl"           # full span raw JSONL (deleted at end)
RAW="$RAW_DIR/${BASE}.jsonl"               # benchmark window cutout
LOG="$LOG_DIR/${BASE}.log"                 # stderr of the collector (kubectl+jq)
CLIENT_LOG="$LOG_DIR/${BASE}-client.log"   # client run log
META="$META_DIR/${BASE}.json"

# ====== Find Tetragon container name =========================================
TETRA_CONT=$(
  kubectl -n kube-system get pods -l 'app.kubernetes.io/name=tetragon' \
    -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null \
  | tr ' ' '\n' | grep -m1 -E '^export-stdout$|^tetragon$' || true
)
if [ -z "${TETRA_CONT:-}" ]; then
  echo "[ERR] tetragon containers not found (export-stdout / tetragon)" >&2
  exit 1
fi

# ====== Start monitor stream (since now; avoid old logs) ======================
SINCE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
kubectl -n kube-system logs ds/tetragon -c "${TETRA_CONT}" -f --since-time="$SINCE" 2>"$LOG" \
| jq -c '
  select(.process_tracepoint?
         and (.process_tracepoint.process.pod.container.name == "server")
         and (.process_tracepoint.process.pod.name | startswith("server-")))
  | {
      ts: .time,
      pid: .process_tracepoint.process.pid,
      pod: .process_tracepoint.process.pod.name,
      container: .process_tracepoint.process.pod.container.name,
      sc: (try ((.process_tracepoint.args[0].long_arg
                 // .process_tracepoint.args[0].int64_arg
                 // .process_tracepoint.args[0].size_arg
                 // .process_tracepoint.args[0].int_arg) | tonumber) catch null),
      wl: "data-caching"
    }' | tee "$ALL" &
MON_PID=$!

cleanup() { kill "$MON_PID" 2>/dev/null || true; wait "$MON_PID" 2>/dev/null || true; }
trap cleanup EXIT

# ====== Quick liveness poke & wait until stream has content ===================
SERVER=$(kubectl -n "$NS" get pod -l "$SERVER_LABEL" -o jsonpath='{.items[0].metadata.name}')
for i in $(seq 1 25); do
  kubectl -n "$NS" exec "$SERVER" -- sh -lc 'true' || true
  sleep 0.2
  if [ -s "$ALL" ]; then break; fi
done

# ====== Benchmark window: start ==============================================
START_TS="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
CLIENT=$(kubectl -n "$NS" get pod -l "$CLIENT_LABEL" -o jsonpath='{.items[0].metadata.name}')

# Prepare docker_servers for memcached client
kubectl -n "$NS" exec -i "$CLIENT" -- sh -lc '
  base=/usr/src/memcached/memcached_client
  mkdir -p "$base/docker_servers"
  printf "%s, %s\n" "'"$SERVER_SVC"'" "'"$PORT"'" > "$base/docker_servers/docker_servers.txt"
  ln -sf docker_servers/docker_servers.txt "$base/docker_servers.txt"
  head -n1 "$base/docker_servers/docker_servers.txt"
' >>"$CLIENT_LOG" 2>&1 || true

# S&W (setup & warm)
kubectl -n "$NS" exec -i "$CLIENT" -- \
  /entrypoint.sh --m=S\&W --S="$S" --D="$D" --w="$W" --T="$T" \
  >>"$CLIENT_LOG" 2>&1 || true

# (optional) sanity check of dataset presence
kubectl -n "$NS" exec -i "$CLIENT" -- \
  sh -lc "ls -lh /usr/src/memcached/twitter_dataset/twitter_dataset_${S}x || true" \
  >>"$CLIENT_LOG" 2>&1 || true

# Throughput (TH)
kubectl -n "$NS" exec -i "$CLIENT" -- \
  timeout "$TH_DUR" /entrypoint.sh --m=TH --S="$S" --w="$W" --D="$D" --g="$G" --c="$C" --T="$T" \
  >>"$CLIENT_LOG" 2>&1 || true

# Requests-per-second (RPS)
kubectl -n "$NS" exec -i "$CLIENT" -- \
  timeout "$RPS_DUR" /entrypoint.sh --m=RPS --S="$S" --g="$G" --c="$C" --w="$W" --T="$T" --r="$R" \
  >>"$CLIENT_LOG" 2>&1 || true

# ====== Benchmark window: end & stop monitor =================================
END_TS="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
cleanup

# ====== Cut out just the benchmark window ====================================
# fromjson? drops incomplete lines safely
jq -cR --arg s "$START_TS" --arg e "$END_TS" \
  'fromjson? | select(.) | select(.ts >= $s and .ts <= $e)' "$ALL" > "$RAW"

# ====== Metadata ==============================================================
cat > "$META" <<EOF
{
  "schema_version": 1,
  "base": "$BASE",
  "namespace": "$NS",
  "workload": "data-caching",
  "event": "raw_syscalls:${EVENT}",
  "bench": {
    "server": "$SERVER_SVC",
    "port": $PORT,
    "S": $S, "D": $D, "w": $W, "T": $T,
    "TH": {"g": $G, "c": $C, "dur_s": $TH_DUR},
    "RPS": {"g": $G, "c": $C, "w": $W, "T": $T, "r": $R, "dur_s": $RPS_DUR}
  },
  "monitor_since": "$SINCE",
  "start_ts": "$START_TS",
  "end_ts": "$END_TS",
  "files": { "raw": "$RAW", "log": "$LOG", "client": "$CLIENT_LOG" },
  "fields": ["ts","pid","pod","container","sc","wl"]
}
EOF

# ====== Summary ===============================================================
COUNT=$(wc -l < "$RAW" | tr -d ' ')
echo "raw:    $RAW"
echo "log:    $LOG"
echo "client: $CLIENT_LOG"
echo "meta:   $META"
echo "syscalls (events): $COUNT"

# cleanup tmp
rm -f "$ALL"
