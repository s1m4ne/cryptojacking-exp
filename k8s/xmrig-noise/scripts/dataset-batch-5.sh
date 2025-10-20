#!/usr/bin/env bash
# dataset-batch-tune5.sh — 0%の最小ノイズ(1Hz)と 30%再調整（各ラン DURATION 秒）。区切り＋NS削除は共通化。

set -euo pipefail

DURATION=1000

gap() {
  echo "=========================="
  kubectl delete ns xmrig-noise --ignore-not-found
  kubectl wait --for=delete ns/xmrig-noise --timeout=180s || true
}

# 初期クリーン
gap

# 0% 最小ノイズ（1Hz）— LD_PRELOADを有効化して1Hzだけ注入
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" \
  --label=15m-0pct-1hz --noise_enable=0 --ldpreload=0 --noise_rate=1
gap

# 30% 再調整（210Hz 再測）
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" \
  --label=15m-30pct-tune5 --noise_enable=1 --ldpreload=1 --noise_rate=210
gap

echo "ALL RUNS DONE"
echo "=========================="
