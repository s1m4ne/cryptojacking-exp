#!/usr/bin/env bash
# make_and_eval_noise.sh — データセット作成 → 二値評価 をラベル共通で直列実行（シンプル版）
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <label> \"<xmrig_jsonl_paths>\"" >&2
  echo "  e.g.) $0 15m-1000hz \"runs/xmrig-noise-15m-1000hz-*/xmrig-noise-15m-1000hz-*.jsonl\"" >&2
  exit 1
fi

LABEL="$1"
XMRIG_PATHS="$2"

echo "[MAKE] ${LABEL}"
./features/make_noise_configs_and_run.sh "${LABEL}" "${XMRIG_PATHS}"

echo "=========================="
echo "[EVAL] ${LABEL}"
python3 features/eval-noise.py --label "${LABEL}"
echo "=========================="
echo "[DONE] label=${LABEL}"
