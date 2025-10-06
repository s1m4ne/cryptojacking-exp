#!/usr/bin/env bash
# entrypoint.sh - XMRig benchmark launcher with optional noise injection

set -euo pipefail

echo "[INFO] Starting entrypoint.sh"
echo "[INFO] BENCH_ARGS=${BENCH_ARGS:-"(none)"}"
echo "[INFO] NOISE_ENABLE=${NOISE_ENABLE:-1}"
echo "[INFO] NOISE_RATE_HZ=${NOISE_RATE_HZ:-1000}"

# xmrig 実行
exec /usr/local/bin/xmrig ${BENCH_ARGS:-}
