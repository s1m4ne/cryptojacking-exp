#!/usr/bin/env bash
# dataset-batch-2.sh — チューニング実験（各ラン DURATION 秒）。区切り＋NS削除は共通化。

set -euo pipefail

DURATION=1000

gap() {
  echo "=========================="
  kubectl delete ns xmrig-noise --ignore-not-found
  kubectl wait --for=delete ns/xmrig-noise --timeout=180s || true
}

# 初期クリーン
gap

# 0%（ldpreload=0 / noise_enable=0 で正基準）
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-0pct-tune  --ldpreload=0 --noise_enable=0 --noise_rate=0
gap

# 20%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-20pct-tune --noise_enable=1 --ldpreload=1 --noise_rate=132
gap

# 30%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-30pct-tune --noise_enable=1 --ldpreload=1 --noise_rate=227
gap

# 40%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-40pct-tune --noise_enable=1 --ldpreload=1 --noise_rate=355
gap

# 50%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-50pct-tune --noise_enable=1 --ldpreload=1 --noise_rate=532
gap

# 60%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-60pct-tune --noise_enable=1 --ldpreload=1 --noise_rate=803
gap

# 70%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-70pct-tune --noise_enable=1 --ldpreload=1 --noise_rate=1258
gap

# 90%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-90pct-tune --noise_enable=1 --ldpreload=1 --noise_rate=4950
gap

echo "ALL RUNS DONE"
echo "=========================="
