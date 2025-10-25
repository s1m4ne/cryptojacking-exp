#!/usr/bin/env bash
# avg_tables.sh — 15m-<pct>pct-r{1,2,3}-2-results.json から4指標の平均を出力
# 使い方: リポジトリ直下で `bash avg_tables.sh`

set -euo pipefail

EVAL_DIR="eval"

# 出力順（表示名 → 内部モデル名）
declare -A CODE=(
  ["Decision Tree"]="dt_35"
  ["MLP"]="mlp_10"
  ["kNN"]="knn_5"
  ["RNN"]="rnn_40"
  ["SVM"]="svm_50"
)
ORDER=("Decision Tree" "MLP" "kNN" "RNN" "SVM")

avg_row() {
  local model_code="$1"; shift
  local files=( "$@" )
  local sum_r=0 sum_fpr=0 sum_p=0 sum_f1=0 cnt=0

  # 各ファイルから該当モデルの4指標をTSVで吸い出し → 和を取る
  while IFS=$'\t' read -r r fpr p f1; do
    [[ -z "${r:-}" ]] && continue
    sum_r=$(awk -v a="$sum_r"  -v b="$r"  'BEGIN{print a+b}')
    sum_fpr=$(awk -v a="$sum_fpr" -v b="$fpr" 'BEGIN{print a+b}')
    sum_p=$(awk -v a="$sum_p"  -v b="$p"  'BEGIN{print a+b}')
    sum_f1=$(awk -v a="$sum_f1" -v b="$f1" 'BEGIN{print a+b}')
    cnt=$((cnt+1))
  done < <(jq -r --arg m "$model_code" '
      .results[] | select(.name == $m) | .binary_metrics
      | [.recall, .fpr, .precision, .f1] | @tsv
    ' "${files[@]}" 2>/dev/null || true)

  if [[ $cnt -eq 0 ]]; then
    # データなし
    printf "N/A,N/A,N/A,N/A"
  else
    # 平均して百分率に（小数2桁）
    awk -v r="$sum_r" -v fpr="$sum_fpr" -v p="$sum_p" -v f1="$sum_f1" -v c="$cnt" 'BEGIN{
      ar = r/c*100; afpr = fpr/c*100; ap = p/c*100; af1 = f1/c*100;
      printf("%.2f%%,%.2f%%,%.2f%%,%.2f%%", ar, afpr, ap, af1);
    }'
  fi
}

for pct in 0 10 20 30 40 50 60 70 80 90; do
  files=()
  for r in r1-2 r2-2 r3-2; do
    f="${EVAL_DIR}/15m-${pct}pct-${r}-results.json"
    [[ -f "$f" ]] && files+=("$f")
  done

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "=== Noise ${pct}% ==="
    echo "(no files found under ${EVAL_DIR}/ for ${pct}%)"
    echo
    continue
  fi

  echo "=== Noise ${pct}% ==="
  echo "Model,Recall(TPR),FPR,Precision,F1"
  for disp in "${ORDER[@]}"; do
    code="${CODE[$disp]}"
    row=$(avg_row "$code" "${files[@]}")
    echo "${disp},${row}"
  done
  echo
done

