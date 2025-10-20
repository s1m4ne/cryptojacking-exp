#!/usr/bin/env bash
# dataset-batch-tune6.sh — 30%/40% 再調整（各ラン DURATION 秒）。区切り＋NS削除は共通化。

set -euo pipefail

DURATION=1000

gap() {
  echo "=========================="
  kubectl delete ns xmrig-noise --ignore-not-found
  kubectl wait --for=delete ns/xmrig-noise --timeout=180s || true
}

# 初期クリーン
gap

# 30% 再調整（210Hz 再測）
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" \
  --label=15m-30pct-tune6 --noise_enable=1 --ldpreload=1 --noise_rate=210
gap

# 40% 再調整（337Hz 再測）
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" \
  --label=15m-40pct-tune6 --noise_enable=1 --ldpreload=1 --noise_rate=337
gap

echo "ALL RUNS DONE"
echo "=========================="
