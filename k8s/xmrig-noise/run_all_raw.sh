#!/usr/bin/env bash
# run_all_raw.sh — マニフェスト適用 + Job 実行 + Tetragon→jq 収集（raw.jsonl）を一括で実行

set -euo pipefail

# 固定値
NS="xmrig-noise"
TETRA_NS="kube-system"
TETRA_CONTAINER="export-stdout"
JOB="xmrig-noise"

# 既定値
LABEL="${LABEL:-manual}"
DURATION="${DURATION_SEC:-}"            # 必須（CLIで上書き）
NOISE_ENABLE="${NOISE_ENABLE:-1}"
NOISE_RATE_HZ="${NOISE_RATE_HZ:-1000}"
LDPRELOAD_FLAG="${LDPRELOAD_FLAG:-1}"
IMAGE="${IMAGE:-xmrig-noise:latest}"

# 引数パース
while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration=*)     DURATION="${1#*=}";;
    --label=*)        LABEL="${1#*=}";;
    --noise_enable=*) NOISE_ENABLE="${1#*=}";;
    --noise_rate=*)   NOISE_RATE_HZ="${1#*=}";;
    --ldpreload=*)    LDPRELOAD_FLAG="${1#*=}";;
    --image=*)        IMAGE="${1#*=}";;
    -h|--help)
      cat <<USAGE
Usage: $0 --duration=SEC [--label=STR] [--noise_enable=0|1] [--noise_rate=INT] [--ldpreload=0|1] [--image=NAME:TAG]
USAGE
      exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
  shift
done

if [[ -z "${DURATION:-}" ]]; then
  echo "[ERR] --duration=<sec> is required" >&2
  exit 1
fi

# 命名・出力先
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASENAME="xmrig-noise-${LABEL}-${STAMP}"
OUTDIR="runs/${BASENAME}"
OUTFILE="${OUTDIR}/${BASENAME}.jsonl"
SUMMARY_FILE="${OUTDIR}/summary.json"
mkdir -p "${OUTDIR}"

START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[RUN] start_utc=${START_ISO}"
echo "[RUN] ns=${NS} image=${IMAGE} duration=${DURATION}s label=${LABEL}"
echo "[RUN] NOISE_ENABLE=${NOISE_ENABLE} NOISE_RATE_HZ=${NOISE_RATE_HZ} LDPRELOAD_FLAG=${LDPRELOAD_FLAG}"
echo "[RUN] output: ${OUTFILE}"

# LD_PRELOAD の差し込み
if [[ "${LDPRELOAD_FLAG}" == "1" ]]; then
  LDPRELOAD_ENV=$'        - name: LD_PRELOAD\n          value: "/opt/libnoise.so"\n'
else
  LDPRELOAD_ENV=""
fi

# 1) マニフェスト適用（Namespace / ConfigMap / Job / TracingPolicy を一括作成）
cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: xmrig-noise
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: xmrig-config
  namespace: xmrig-noise
data:
  config.json: |
    {
      "autosave": false,
      "cpu": {
        "enabled": true,
        "rx": [0, 1],
        "yield": true,
        "priority": 2,
        "huge-pages": false,
        "asm": true
      },
      "randomx": {
        "mode": "fast",
        "init": 2,
        "1gb-pages": false,
        "rdmsr": false,
        "wrmsr": false,
        "numa": true
      },
      "http": {
        "enabled": true,
        "host": "127.0.0.1",
        "port": 18080,
        "restricted": true
      },
      "pools": [
        {
          "url": "pool.supportxmr.com:443",
          "user": "4B2g9xj9aRfeUbNEhoqopR3n3GaYtpN3cWT8vwXK3iGCLF4jdH8wHD2TCJin6PUXxaUuGYozusUkgANHqsbKQgqc9aChgs5.baseline",
          "pass": "x",
          "tls": true
        }
      ]
    }
---
apiVersion: batch/v1
kind: Job
metadata:
  name: xmrig-noise
  namespace: xmrig-noise
spec:
  template:
    metadata:
      labels:
        app: xmrig-noise
    spec:
      restartPolicy: Never
      containers:
      - name: xmrig-noise
        image: ${IMAGE}
        imagePullPolicy: IfNotPresent
        args: ["--config", "/etc/xmrig/config.json"]
        env:
        - name: NOISE_ENABLE
          value: "${NOISE_ENABLE}"
        - name: NOISE_RATE_HZ
          value: "${NOISE_RATE_HZ}"
${LDPRELOAD_ENV}        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
        volumeMounts:
        - name: cfg
          mountPath: /etc/xmrig
          readOnly: true
      volumes:
      - name: cfg
        configMap:
          name: xmrig-config
---
apiVersion: cilium.io/v1alpha1
kind: TracingPolicyNamespaced
metadata:
  name: xmrig-noise-policy
  namespace: xmrig-noise
spec:
  podSelector:
    matchLabels:
      app: xmrig-noise
  tracepoints:
  - subsystem: raw_syscalls
    event: sys_exit
    args:
    - index: 4
      type: int64
      label: syscall
YAML

# 2) Pod 作成待ち → logs ready 待ち
POD=""
for _ in $(seq 1 120); do
  POD="$(kubectl -n "${NS}" get pods -l job-name=${JOB} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "${POD}" ]] && break
  sleep 1
done
if [[ -z "${POD}" ]]; then
  echo "[ERR] Pod not created" >&2
  exit 1
fi
until kubectl -n "${NS}" logs "${POD}" >/dev/null 2>&1; do
  sleep 1
done
echo "[RUN] pod=${POD} logs=ready"

# 3) jq フィルタ（旧式と完全一致・改行崩れ修正済み）
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
sed -i "s/__NS__/${NS}/g" "$TMP_JQ"

# 4) 収集開始（独立PG）
touch "${OUTFILE}"
echo "[RAW] start: ${OUTFILE}"
setsid bash -lc "
  stdbuf -oL -eL kubectl -n ${TETRA_NS} logs ds/tetragon -c ${TETRA_CONTAINER} -f \
  | jq -c -f '${TMP_JQ}' > '${OUTFILE}'
" &
MON_LEADER=$!
MON_PGID="$(ps -o pgid= "${MON_LEADER}" | tr -d ' ')"

cleanup() {
  kill -TERM "-${MON_PGID}" 2>/dev/null || true
  sleep 1
  kill -KILL "-${MON_PGID}" 2>/dev/null || true
  rm -f "$TMP_JQ" 2>/dev/null || true
}
trap cleanup EXIT

# 5) 所定時間だけ待機
sleep "${DURATION}"

# 5.5) HTTP summary を取得（port-forward → ホストcurl → 片付け） ※軽いリトライ付き
SUMMARY_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
kubectl -n "${NS}" port-forward "pod/${POD}" 18080:18080 >/dev/null 2>&1 &
PF_PID=$!
sleep 1  # forward確立待ち
ok=false
for _ in 1 2 3; do
  if curl -fsS --max-time 2 http://127.0.0.1:18080/2/summary > "${SUMMARY_FILE}"; then
    ok=true; break
  fi
  sleep 1
done
if ! $ok; then echo '{}' > "${SUMMARY_FILE}"; fi
kill "${PF_PID}" 2>/dev/null || true
wait "${PF_PID}" 2>/dev/null || true
echo "[SUMMARY] saved ${SUMMARY_FILE} ($(stat -c%s "${SUMMARY_FILE}") bytes)"

# 6) xmrig を優雅停止（PID1= xmrig を SIGINT） → 終了待ち
kubectl -n "${NS}" exec "${POD}" -- /bin/sh -lc 'kill -INT 1' >/dev/null 2>&1 || true
for _ in $(seq 1 30); do
  phase="$(kubectl -n "${NS}" get pod "${POD}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${phase}" != "Running" ]] && break
  sleep 1
done

END_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[RUN] end_utc=${END_ISO}"

# python script
if ! python3 k8s/xmrig-noise/scripts/analyze_run.py \
      --run-dir "${OUTDIR}" \
      --label "${LABEL}" \
      --noise-enable "${NOISE_ENABLE}" \
      --noise-rate "${NOISE_RATE_HZ}" \
      --ld-preload "${LDPRELOAD_FLAG}" \
      --start-utc "${START_ISO}" \
      --end-utc "${END_ISO}"; then
  echo "[WARN] analyze_run.py failed; run.json not created"
fi

# 7) 監視停止（trap でも止まるが明示的に）
cleanup

# 8) 最少サマリ（標準出力）＋ メトリクス出力
LINES=$(wc -l < "${OUTFILE}" | tr -d ' ')
BYTES=$(stat -c %s "${OUTFILE}" 2>/dev/null || echo 0)
echo "[RAW] done: lines=${LINES} bytes=${BYTES} file=${OUTFILE}"

if [[ -f "${OUTDIR}/run.json" ]]; then
  AVG=$(jq -r '.summary.avg_Hs' "${OUTDIR}/run.json")
  BASIS=$(jq -r '.summary.avg_Hs_basis' "${OUTDIR}/run.json")
  NOISE=$(jq -r '.noise_ratio.ratio_pct' "${OUTDIR}/run.json")
  echo "[METRICS] avg_Hs=${AVG} (${BASIS}), noise_ratio=${NOISE}%"
fi
