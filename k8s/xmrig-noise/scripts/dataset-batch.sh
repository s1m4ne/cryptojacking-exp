#!/usr/bin/env bash
# dataset-sweep.sh — 単純羅列版（各ラン DURATION 秒）。区切り＋NS削除は共通化。

set -euo pipefail

DURATION=1000

gap() {
  echo "=========================="
  kubectl delete ns xmrig-noise --ignore-not-found
  kubectl wait --for=delete ns/xmrig-noise --timeout=180s || true
}

# 初期クリーン
gap

# 0%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-0pct-0  --noise_enable=1 --ldpreload=1 --noise_rate=0
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-0pct-1  --noise_enable=1 --ldpreload=1 --noise_rate=0   # 基準
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-0pct-2  --noise_enable=1 --ldpreload=1 --noise_rate=2
gap

# 10%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-10pct-0 --noise_enable=1 --ldpreload=1 --noise_rate=50
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-10pct-1 --noise_enable=1 --ldpreload=1 --noise_rate=53   # 基準
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-10pct-2 --noise_enable=1 --ldpreload=1 --noise_rate=56
gap

# 20%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-20pct-0 --noise_enable=1 --ldpreload=1 --noise_rate=117
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-20pct-1 --noise_enable=1 --ldpreload=1 --noise_rate=120  # 基準
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-20pct-2 --noise_enable=1 --ldpreload=1 --noise_rate=123
gap

# 30%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-30pct-0 --noise_enable=1 --ldpreload=1 --noise_rate=200
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-30pct-1 --noise_enable=1 --ldpreload=1 --noise_rate=205  # 基準
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-30pct-2 --noise_enable=1 --ldpreload=1 --noise_rate=210
gap

# 40%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-40pct-0 --noise_enable=1 --ldpreload=1 --noise_rate=313
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-40pct-1 --noise_enable=1 --ldpreload=1 --noise_rate=319  # 基準
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-40pct-2 --noise_enable=1 --ldpreload=1 --noise_rate=326
gap

# 50%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-50pct-0 --noise_enable=1 --ldpreload=1 --noise_rate=470
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-50pct-1 --noise_enable=1 --ldpreload=1 --noise_rate=479  # 基準
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-50pct-2 --noise_enable=1 --ldpreload=1 --noise_rate=489
gap

# 60%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-60pct-0 --noise_enable=1 --ldpreload=1 --noise_rate=704
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-60pct-1 --noise_enable=1 --ldpreload=1 --noise_rate=719  # 基準
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-60pct-2 --noise_enable=1 --ldpreload=1 --noise_rate=734
gap

# 70%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-70pct-0 --noise_enable=1 --ldpreload=1 --noise_rate=1091
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-70pct-1 --noise_enable=1 --ldpreload=1 --noise_rate=1119 # 基準
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-70pct-2 --noise_enable=1 --ldpreload=1 --noise_rate=1145
gap

# 80%
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-80pct-0 --noise_enable=1 --ldpreload=1 --noise_rate=1857
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-80pct-1 --noise_enable=1 --ldpreload=1 --noise_rate=1916 # 基準
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-80pct-2 --noise_enable=1 --ldpreload=1 --noise_rate=1977
gap

# 90%（低め2本＋基準）
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-90pct-0 --noise_enable=1 --ldpreload=1 --noise_rate=3886
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-90pct-1 --noise_enable=1 --ldpreload=1 --noise_rate=4311 # 基準
gap
k8s/xmrig-noise/scripts/run-collect.sh --duration="${DURATION}" --label=15m-90pct-2 --noise_enable=1 --ldpreload=1 --noise_rate=4085
gap

echo "ALL RUNS DONE"
echo "=========================="
