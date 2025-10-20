#!/usr/bin/env bash
# build_then_eval_noise.sh
# 目的: すべてのラベルのデータセットを先に作成 → まとめて評価
# 実行: リポジトリのルートで `bash build_then_eval_noise.sh`
set -euo pipefail

# ===== ユーティリティ =====
build_path() {
  local run_id="$1"
  echo "runs/${run_id}/${run_id}.jsonl"
}

ensure_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "[ERR] not found: $path" >&2
    exit 1
  fi
}

make_one() {
  local label="$1"
  local run_id="$2"
  local path; path="$(build_path "$run_id")"

  echo "[$(date '+%F %T')] [MAKE] LABEL=${label}"
  echo "  RUN = ${run_id}"
  echo "  PATH= ${path}"
  ensure_exists "$path"

  # データセット作成のみ（評価はしない）
  ./features/make_noise_configs_and_run.sh "${label}" "${path}"
  echo
}

eval_one() {
  local label="$1"
  echo "[$(date '+%F %T')] [EVAL] LABEL=${label}"
  python3 features/eval-noise.py --label "${label}"
  echo
}

# ===== 対象リスト（label run_id）=====
declare -a pairs=()

# 0%
pairs+=("15m-0pct-r1-2 xmrig-noise-15m-0pct-batch8-r2-20251019T211243Z")
pairs+=("15m-0pct-r2-2 xmrig-noise-15m-0pct-2-20251015T190804Z")
pairs+=("15m-0pct-r3-2 xmrig-noise-15m-0pct-batch7-r2-20251018T200048Z")

# 10%
pairs+=("15m-10pct-r1-2 xmrig-noise-15m-10pct-batch7-r3-20251018T230655Z")
pairs+=("15m-10pct-r2-2 xmrig-noise-15m-10pct-2-20251015T195849Z")
pairs+=("15m-10pct-r3-2 xmrig-noise-15m-10pct-batch8-r3-20251020T001843Z")

# 20%
pairs+=("15m-20pct-r1-2 xmrig-noise-15m-20pct-batch7-r3-20251018T232349Z")
pairs+=("15m-20pct-r2-2 xmrig-noise-15m-20pct-batch8-r1-20251019T185726Z")
pairs+=("15m-20pct-r3-2 xmrig-noise-15m-20pct-tune3-20251016T075334Z")

# 30%
pairs+=("15m-30pct-r1-2 xmrig-noise-15m-30pct-tune5-20251016T090629Z")
pairs+=("15m-30pct-r2-2 xmrig-noise-15m-30pct-batch7-r2-20251018T205131Z")
pairs+=("15m-30pct-r3-2 xmrig-noise-15m-30pct-batch7-r3-20251018T234043Z")

# 40%
pairs+=("15m-40pct-r1-2 xmrig-noise-15m-40pct-batch7-r1-20251018T181914Z")
pairs+=("15m-40pct-r2-2 xmrig-noise-15m-40pct-batch7-r2-20251018T210825Z")
pairs+=("15m-40pct-r3-2 xmrig-noise-15m-40pct-batch7-r3-20251018T235738Z")

# 50%
pairs+=("15m-50pct-r1-2 xmrig-noise-15m-50pct-batch7-r2-20251018T212519Z")
pairs+=("15m-50pct-r2-2 xmrig-noise-15m-50pct-tune2-20251016T063023Z")
pairs+=("15m-50pct-r3-2 xmrig-noise-15m-50pct-batch7-r3-20251019T001433Z")

# 60%
pairs+=("15m-60pct-r1-2 xmrig-noise-15m-60pct-batch8-r3-20251020T014312Z")
pairs+=("15m-60pct-r2-2 xmrig-noise-15m-60pct-tune2-20251016T064717Z")
pairs+=("15m-60pct-r3-2 xmrig-noise-15m-60pct-batch7-r3-20251019T003128Z")

# 70%
pairs+=("15m-70pct-r1-2 xmrig-noise-15m-70pct-batch8-r3-20251020T020010Z")
pairs+=("15m-70pct-r2-2 xmrig-noise-15m-70pct-2-20251016T010318Z")
pairs+=("15m-70pct-r3-2 xmrig-noise-15m-70pct-batch7-r2-20251018T215910Z")

# 80%
pairs+=("15m-80pct-r1-2 xmrig-noise-15m-80pct-0-20251016T012016Z")
pairs+=("15m-80pct-r2-2 xmrig-noise-15m-80pct-1-20251016T013712Z")
pairs+=("15m-80pct-r3-2 xmrig-noise-15m-80pct-batch8-r3-20251020T021707Z")

# 90%
pairs+=("15m-90pct-r1-2 xmrig-noise-15m-90pct-batch8-r3-20251020T023405Z")
pairs+=("15m-90pct-r2-2 xmrig-noise-15m-90pct-tune-20251016T050332Z")
pairs+=("15m-90pct-r3-2 xmrig-noise-15m-90pct-2-20251016T024502Z")

# ===== フェーズ1: 全データセット作成 =====
# echo "========== PHASE 1: MAKE (datasets only) =========="
# for entry in "${pairs[@]}"; do
#   read -r label run_id <<< "${entry}"
#   make_one "${label}" "${run_id}"
# done

# ===== フェーズ2: まとめて評価 =====
echo "========== PHASE 2: EVAL (all labels) =========="
for entry in "${pairs[@]}"; do
  read -r label run_id <<< "${entry}"
  eval_one "${label}"
done

echo "========== ALL DONE =========="

