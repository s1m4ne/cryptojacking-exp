#!/usr/bin/env bash

set -euo pipefail

DURATION=1000

gap() {
  echo "=========================="
  kubectl delete ns xmrig-noise --ignore-not-found
  kubectl wait --for=delete ns/xmrig-noise --timeout=180s || true
}

# 初期クリーン
gap

# 20% （線形補間: 124Hz）
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-20pct-tune3 --noise_enable=1 --ldpreload=1 --noise_rate=124
gap

# 30% （線形補間: 211Hz）
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-30pct-tune3 --noise_enable=1 --ldpreload=1 --noise_rate=211
gap

echo "ALL RUNS DONE"
echo "=========================="
