#!/usr/bin/env bash
# dataset-batch-3.sh — チューニング実験 第2弾（各ラン DURATION 秒）。区切り＋NS削除は共通化。

set -euo pipefail

DURATION=1000

gap() {
  echo "=========================="
  kubectl delete ns xmrig-noise --ignore-not-found
  kubectl wait --for=delete ns/xmrig-noise --timeout=180s || true
}

# 初期クリーン
gap

# 20%（補間: 126Hz）
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-20pct-tune2 --noise_enable=1 --ldpreload=1 --noise_rate=126
gap

# 30%（補間: 215Hz）
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-30pct-tune2 --noise_enable=1 --ldpreload=1 --noise_rate=215
gap

# 40%（補間: 337Hz）
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-40pct-tune2 --noise_enable=1 --ldpreload=1 --noise_rate=337
gap

# 50%（補間: 502Hz）
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-50pct-tune2 --noise_enable=1 --ldpreload=1 --noise_rate=502
gap

# 60%（補間: 757Hz）
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-60pct-tune2 --noise_enable=1 --ldpreload=1 --noise_rate=757
gap

echo "ALL RUNS DONE"
echo "=========================="
