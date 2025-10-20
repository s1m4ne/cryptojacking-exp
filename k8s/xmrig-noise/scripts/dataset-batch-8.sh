#!/usr/bin/env bash
# dataset-batch-8.sh — 0→90% を 3周まわす（各ラン DURATION 秒）。区切り＋NS削除は共通化。

set -euo pipefail

DURATION=1000

gap() {
  echo "======================================"
  kubectl delete ns xmrig-noise --ignore-not-found
  kubectl wait --for=delete ns/xmrig-noise --timeout=180s || true
}

# Hz マップ（batch8 提案）
hz_0=1
hz_10=55
hz_20=126
hz_30=212
hz_40=340
hz_50=510
hz_60=770
hz_70=1170
hz_80=1950
hz_90=5050

# 初期クリーン
gap

############
# Round 1  #
############
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-0pct-batch8-r1  --noise_enable=1 --ldpreload=1 --noise_rate=${hz_0}
echo "[DONE] r1 0%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-10pct-batch8-r1 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_10}
echo "[DONE] r1 10%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-20pct-batch8-r1 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_20}
echo "[DONE] r1 20%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-30pct-batch8-r1 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_30}
echo "[DONE] r1 30%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-40pct-batch8-r1 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_40}
echo "[DONE] r1 40%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-50pct-batch8-r1 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_50}
echo "[DONE] r1 50%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-60pct-batch8-r1 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_60}
echo "[DONE] r1 60%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-70pct-batch8-r1 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_70}
echo "[DONE] r1 70%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-80pct-batch8-r1 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_80}
echo "[DONE] r1 80%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-90pct-batch8-r1 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_90}
echo "[DONE] r1 90%"; gap

############
# Round 2  #
############
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-0pct-batch8-r2  --noise_enable=1 --ldpreload=1 --noise_rate=${hz_0}
echo "[DONE] r2 0%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-10pct-batch8-r2 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_10}
echo "[DONE] r2 10%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-20pct-batch8-r2 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_20}
echo "[DONE] r2 20%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-30pct-batch8-r2 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_30}
echo "[DONE] r2 30%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-40pct-batch8-r2 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_40}
echo "[DONE] r2 40%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-50pct-batch8-r2 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_50}
echo "[DONE] r2 50%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-60pct-batch8-r2 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_60}
echo "[DONE] r2 60%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-70pct-batch8-r2 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_70}
echo "[DONE] r2 70%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-80pct-batch8-r2 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_80}
echo "[DONE] r2 80%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-90pct-batch8-r2 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_90}
echo "[DONE] r2 90%"; gap

############
# Round 3  #
############
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-0pct-batch8-r3  --noise_enable=1 --ldpreload=1 --noise_rate=${hz_0}
echo "[DONE] r3 0%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-10pct-batch8-r3 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_10}
echo "[DONE] r3 10%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-20pct-batch8-r3 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_20}
echo "[DONE] r3 20%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-30pct-batch8-r3 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_30}
echo "[DONE] r3 30%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-40pct-batch8-r3 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_40}
echo "[DONE] r3 40%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-50pct-batch8-r3 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_50}
echo "[DONE] r3 50%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-60pct-batch8-r3 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_60}
echo "[DONE] r3 60%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-70pct-batch8-r3 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_70}
echo "[DONE] r3 70%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-80pct-batch8-r3 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_80}
echo "[DONE] r3 80%"; gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-90pct-batch8-r3 --noise_enable=1 --ldpreload=1 --noise_rate=${hz_90}
echo "[DONE] r3 90%"; gap

echo "[ALL DONE] dataset-batch-8"
echo "======================================"
