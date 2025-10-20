#!/usr/bin/env bash
# runs-summary.sh — runs/**/run.json を集計し、basename / rate_hz / s15m(→60s→avg_Hs) / ratio_pct を一覧表示
# 使い方:
#   ./runs-summary.sh [--like 'glob'] [RUNS_DIR]
#     --like 'glob' : basename に対するグロブでフィルタ（例: 'xmrig-noise-15m-*pct*'）
#     RUNS_DIR      : 省略時は 'runs'

set -euo pipefail

LIKE=""
RUNS_DIR="runs"

# 引数処理（超シンプル）
while [[ $# -gt 0 ]]; do
  case "$1" in
    --like)
      LIKE="${2:-}"; shift 2;;
    --like=*)
      LIKE="${1#*=}"; shift;;
    *)
      RUNS_DIR="$1"; shift;;
  esac
done

# 対象ファイル列挙
mapfile -t FILES < <(find "${RUNS_DIR}" -type f -name run.json 2>/dev/null | sort)
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No run.json found under '${RUNS_DIR}'" >&2
  exit 1
fi

# ヘッダ + 本体をまとめて column に通す
{
  printf "BASENAME\tRATE_HZ\tS15M_HS\tRATIO_%%\n"
  for f in "${FILES[@]}"; do
    # 1件抽出
    line="$(jq -r '
      . as $r
      | [
          ($r.run_info.basename // ""),
          ($r.run_info.noise.rate_hz // ""),
          (
            $r.summary.hashrate.s15m
            // $r.summary.hashrate.s60
            // $r.summary.avg_Hs
            // ""
          ),
          ($r.noise_ratio.ratio_pct // "")
        ]
      | @tsv
    ' "$f")"

    # グロブフィルタ（指定があれば basename で判定）
    basename="${line%%$'\t'*}"
    if [[ -n "$LIKE" ]]; then
      [[ "$basename" == $LIKE ]] || continue
    fi

    printf "%s\n" "$line"
  done
} | column -t -s $'\t'
