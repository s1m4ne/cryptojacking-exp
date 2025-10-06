#!/usr/bin/env bash
# run_xmrig_noise.sh - minimal: BENCH_ARGS 正規化 + Pod/Logs 待ちリトライ + finish検知
# JSONL出力まわりのデバッグログを強化

set -euo pipefail

NS="xmrig-noise"
JOB="xmrig-noise"
IMAGE="xmrig-noise:latest"

# defaults
BENCH_VAL="1M"          # 値だけ保持（--bench=<値> に組み立て）
NOISE_ENABLE="1"
NOISE_RATE_HZ="1000"
OUTLABEL="manual"
LDPRELOAD_FLAG="0"      # 1なら LD_PRELOAD=/opt/libnoise.so を入れる

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bench=*)        BENCH_VAL="${1#*=}";;
    --noise_enable=*) NOISE_ENABLE="${1#*=}";;
    --noise_rate=*)   NOISE_RATE_HZ="${1#*=}";;
    --outfile=*)      OUTLABEL="${1#*=}";;
    --ldpreload=*)    LDPRELOAD_FLAG="${1#*=}";;
    -h|--help)
      echo "Usage: $0 --bench=1M --noise_enable=0|1 --noise_rate=INT --outfile=LABEL [--ldpreload=0|1]"
      exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
  shift
done

# normalize --bench
if [[ "$BENCH_VAL" == --bench=* ]]; then
  BENCH_ARGS="$BENCH_VAL"
else
  BENCH_ARGS="--bench=$BENCH_VAL"
fi

BASE="$HOME/cryptojacking-exp"
RAW_DIR="$BASE/dataset/raw"
LOG_DIR="$BASE/logs"
mkdir -p "$RAW_DIR" "$LOG_DIR"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTFILE="$RAW_DIR/xmrig-noise-${OUTLABEL}-${STAMP}.jsonl"
RUNLOG="$LOG_DIR/xmrig-noise-${OUTLABEL}-${STAMP}.run.log"

echo "[INFO] NS=$NS JOB=$JOB IMAGE=$IMAGE" | tee -a "$RUNLOG"
echo "[INFO] BENCH_ARGS=$BENCH_ARGS NOISE_ENABLE=$NOISE_ENABLE NOISE_RATE_HZ=$NOISE_RATE_HZ LDPRELOAD=$LDPRELOAD_FLAG" | tee -a "$RUNLOG"
echo "[INFO] OUTFILE=$OUTFILE" | tee -a "$RUNLOG"

# ensure ns & clean previous job
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" | tee -a "$RUNLOG"
kubectl -n "$NS" delete job "$JOB" --ignore-not-found >/dev/null 2>&1 || true

# --- JSONL 監視開始（jqフィルタは“あなたの式”に完全一致）---
TMP_JQ="$(mktemp)"
cat > "$TMP_JQ" <<'JQ'
select(.process_tracepoint? and .process_tracepoint.process.pod.namespace=="__NS__") |
{
  ts: (.time // .process_tracepoint.time // .ts),
  pid: (.process_tracepoint.process.pid // .process.pid),
  pod: (.process_tracepoint.process.pod.name // .pod // ""),
  container: (.process_tracepoint.process.container.name // .container // ""),
  sc: ((.process_tracepoint.args[0].long_arg // .process_tracepoint.args[0].int_arg // .sc // .nr // .syscall // .id) | tonumber?),
  wl: "__NS__",
  tid: (.process_tracepoint.process.tid // .process.tid)
}
| select(.sc != null)
JQ
# NSを埋め込む
sed -i "s/__NS__/$NS/g" "$TMP_JQ"

# デバッグのため jq フィルタ全文とハッシュをログに落とす
echo "[MON] jq filter (exact):" | tee -a "$RUNLOG"
sed 's/^/[MON]   /' "$TMP_JQ" | tee -a "$RUNLOG"
echo "[MON] jq sha1=$(sha1sum "$TMP_JQ" | awk '{print $1}')" | tee -a "$RUNLOG"

# 監視プロセス起動（独立PG）。開始直後の行数とファイルサイズをログ化
touch "$OUTFILE"
LINES0=$(wc -l < "$OUTFILE" | tr -d ' ')
BYTES0=$(stat -c %s "$OUTFILE" 2>/dev/null || echo 0)
echo "[MON] start tetragon→jq → $OUTFILE (lines=$LINES0 bytes=$BYTES0)" | tee -a "$RUNLOG"

setsid bash -c "kubectl -n kube-system logs ds/tetragon -c export-stdout -f 2>>'$RUNLOG' | jq -c -f '$TMP_JQ' > '$OUTFILE'" &
MON_LEADER=$!
MON_PGID="$(ps -o pgid= "$MON_LEADER" | tr -d ' ')"
echo "[MON] monitor PGID=$MON_PGID (leader PID=$MON_LEADER)" | tee -a "$RUNLOG"
trap 'kill -TERM "-$MON_PGID" 2>/dev/null || true; rm -f "$TMP_JQ" 2>/dev/null || true' EXIT

# build job manifest
if [[ "$LDPRELOAD_FLAG" == "1" ]]; then
  LDPRELOAD_ENV=$'        - name: LD_PRELOAD\n          value: "/opt/libnoise.so"\n'
else
  LDPRELOAD_ENV=""
fi

cat <<YAML | kubectl apply -f - | tee -a "$RUNLOG"
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB
  namespace: $NS
  labels:
    app: xmrig-noise
spec:
  template:
    metadata:
      labels:
        app: xmrig-noise
    spec:
      restartPolicy: Never
      containers:
      - name: xmrig-noise
        image: $IMAGE
        imagePullPolicy: IfNotPresent
        env:
        - name: NOISE_ENABLE
          value: "$NOISE_ENABLE"
        - name: NOISE_RATE_HZ
          value: "$NOISE_RATE_HZ"
        - name: BENCH_ARGS
          value: "$BENCH_ARGS"
$LDPRELOAD_ENV
YAML
# wait pod appears
POD=""
for i in $(seq 1 120); do
  POD=$(kubectl -n "$NS" get pods -l job-name="$JOB" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [[ -n "$POD" ]] && break
  sleep 1
done
[[ -n "$POD" ]] || { echo "[ERR] pod not created" | tee -a "$RUNLOG"; kill -TERM "-$MON_PGID" 2>/dev/null; exit 1; }
echo "[INFO] pod=$POD" | tee -a "$RUNLOG"

# wait logs ready (avoid ContainerCreating errors)
until kubectl -n "$NS" logs "$POD" >/dev/null 2>&1; do
  sleep 1
done
echo "[INFO] logs are ready" | tee -a "$RUNLOG"

# wait until "benchmark finished" appears
set +o pipefail
set +e
kubectl -n "$NS" logs -f "pod/$POD" | grep -m1 -F "benchmark finished"
GREP_RC=$?
set -e
set -o pipefail
echo "[INFO] grep finished rc=$GREP_RC" | tee -a "$RUNLOG"

# --- 監視停止とJSONLサマリ（デバッグログ厚め） ---
kill -TERM "-$MON_PGID" 2>/dev/null || true
sleep 1
kill -KILL "-$MON_PGID" 2>/dev/null || true
echo "[MON] monitor(PGID=$MON_PGID) stopped" | tee -a "$RUNLOG"

LINES=$(wc -l < "$OUTFILE" | tr -d ' ')
BYTES=$(stat -c %s "$OUTFILE" 2>/dev/null || echo 0)
echo "[MON] outfile stats: lines=$LINES bytes=$BYTES path=$OUTFILE" | tee -a "$RUNLOG"

if [[ "$LINES" -gt 0 ]]; then
  echo "[MON] outfile head(1):" | tee -a "$RUNLOG"
  head -n 1 "$OUTFILE" | sed 's/^/[MON]   /' | tee -a "$RUNLOG"
  echo "[MON] outfile tail(3):" | tee -a "$RUNLOG"
  tail -n 3 "$OUTFILE" | sed 's/^/[MON]   /' | tee -a "$RUNLOG"
else
  echo "[WARN] no events captured. Check: namespace='$NS', LD_PRELOAD=$LDPRELOAD_FLAG, noise_enable=$NOISE_ENABLE, jq filter." | tee -a "$RUNLOG"
fi

echo "[DONE] JSONL: $OUTFILE (lines=$LINES)" | tee -a "$RUNLOG"
