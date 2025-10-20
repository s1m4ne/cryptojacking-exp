#!/usr/bin/env bash
# make_and_eval_from_runs.sh — 指定 runs から一括で dataset 作成 → 評価（シンプル列挙）

set -euo pipefail

echo "[PHASE] MAKE DATASETS (10 labels)"
# 0%
features/make_noise_configs_and_run.sh 15m-0pct \
"runs/xmrig-noise-15m-0pct-2-20251015T190804Z/xmrig-noise-15m-0pct-2-20251015T190804Z.jsonl"
echo "======================================"
echo "[DONE] make 15m-0pct"

# 10%
features/make_noise_configs_and_run.sh 15m-10pct \
"runs/xmrig-noise-15m-10pct-1-20251015T194154Z/xmrig-noise-15m-10pct-1-20251015T194154Z.jsonl"
echo "======================================"
echo "[DONE] make 15m-10pct"

# 20%
features/make_noise_configs_and_run.sh 15m-20pct \
"runs/xmrig-noise-15m-20pct-tune3-20251016T075334Z/xmrig-noise-15m-20pct-tune3-20251016T075334Z.jsonl"
echo "======================================"
echo "[DONE] make 15m-20pct"

# 30%
features/make_noise_configs_and_run.sh 15m-30pct \
"runs/xmrig-noise-15m-30pct-tune6-20251016T143114Z/xmrig-noise-15m-30pct-tune6-20251016T143114Z.jsonl"
echo "======================================"
echo "[DONE] make 15m-30pct"

# 40%
features/make_noise_configs_and_run.sh 15m-40pct \
"runs/xmrig-noise-15m-40pct-tune2-20251016T061330Z/xmrig-noise-15m-40pct-tune2-20251016T061330Z.jsonl"
echo "======================================"
echo "[DONE] make 15m-40pct"

# 50%
features/make_noise_configs_and_run.sh 15m-50pct \
"runs/xmrig-noise-15m-50pct-tune2-20251016T063023Z/xmrig-noise-15m-50pct-tune2-20251016T063023Z.jsonl"
echo "======================================"
echo "[DONE] make 15m-50pct"

# 60%
features/make_noise_configs_and_run.sh 15m-60pct \
"runs/xmrig-noise-15m-60pct-tune2-20251016T064717Z/xmrig-noise-15m-60pct-tune2-20251016T064717Z.jsonl"
echo "======================================"
echo "[DONE] make 15m-60pct"

# 70%
features/make_noise_configs_and_run.sh 15m-70pct \
"runs/xmrig-noise-15m-70pct-2-20251016T010318Z/xmrig-noise-15m-70pct-2-20251016T010318Z.jsonl"
echo "======================================"
echo "[DONE] make 15m-70pct"

# 80%
features/make_noise_configs_and_run.sh 15m-80pct \
"runs/xmrig-noise-15m-80pct-1-20251016T013712Z/xmrig-noise-15m-80pct-1-20251016T013712Z.jsonl"
echo "======================================"
echo "[DONE] make 15m-80pct"

# 90%
features/make_noise_configs_and_run.sh 15m-90pct \
"runs/xmrig-noise-15m-90pct-tune-20251016T050332Z/xmrig-noise-15m-90pct-tune-20251016T050332Z.jsonl"
echo "======================================"
echo "[DONE] make 15m-90pct"

echo "[PHASE DONE] MAKE DATASETS"
echo "======================================"

echo "[PHASE] EVAL DATASETS (10 labels)"
python3 features/eval-noise.py --label 15m-0pct
echo "======================================"; echo "[DONE] eval 15m-0pct"

python3 features/eval-noise.py --label 15m-10pct
echo "======================================"; echo "[DONE] eval 15m-10pct"

python3 features/eval-noise.py --label 15m-20pct
echo "======================================"; echo "[DONE] eval 15m-20pct"

python3 features/eval-noise.py --label 15m-30pct
echo "======================================"; echo "[DONE] eval 15m-30pct"

python3 features/eval-noise.py --label 15m-40pct
echo "======================================"; echo "[DONE] eval 15m-40pct"

python3 features/eval-noise.py --label 15m-50pct
echo "======================================"; echo "[DONE] eval 15m-50pct"

python3 features/eval-noise.py --label 15m-60pct
echo "======================================"; echo "[DONE] eval 15m-60pct"

python3 features/eval-noise.py --label 15m-70pct
echo "======================================"; echo "[DONE] eval 15m-70pct"

python3 features/eval-noise.py --label 15m-80pct
echo "======================================"; echo "[DONE] eval 15m-80pct"

python3 features/eval-noise.py --label 15m-90pct
echo "======================================"; echo "[DONE] eval 15m-90pct"

echo "[ALL DONE] make → eval completed for 10 labels"
echo "======================================"
