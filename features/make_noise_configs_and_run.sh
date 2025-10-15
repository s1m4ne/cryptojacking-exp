#!/usr/bin/env bash
# make_noise_configs_and_run.sh
# =============================================================================
# make_noise_configs_and_run.sh — 使い方 / Usage
# -----------------------------------------------------------------------------
# 目的:
#   Python（make_dataset.py）を変更せずに、n ∈ {5,10,35,40,50} の5種類の
#   設定ファイルを自動生成し、その数だけ make_dataset.py を順に実行します。
#
# 配置:
#   このファイルはリポジトリ直下からの相対パスで呼ばれる想定です。
#   例) features/make_noise_configs_and_run.sh
#   ※ リポジトリのルート（cryptojacking-exp/）で実行してください。
#
# 前提:
#   - Bash が利用可能であること
#   - Python 3.x（スクリプト内で python コマンドを使用）
#   - features/make_dataset.py が存在すること
#   - PyYAML がインストール済み（生成する設定は YAML）
#
# 生成物:
#   - 設定ファイル: configs/<prefix>/<prefix>-{5,10,35,40,50}gram.yaml
#   - データセット: dataset/npy/merged/<prefix>-{5,10,35,40,50}gram/
#
# 引数:
#   1) <prefix>                : 設定ファイル名のプレフィックス（例: 15m-1000hz）
#   2) "<xmrig_jsonl_paths>"   : XMRig の JSONL パス
#                                - 単一のグロブ 例) "dataset/raw/xmrig-noise-1000hz-*.jsonl"
#                                - カンマ区切り複数 例) "p1.jsonl,p2.jsonl"
#                                - 必ず引用符で囲むこと（シェル展開対策）
#
# 付与すべき権限:
#   chmod +x features/make_noise_configs_and_run.sh
#
# 実行例:
#   # ベースライン実験（提示された runs ディレクトリを使用）
#   ./features/make_noise_configs_and_run.sh \
#     15m-baseline \
#     "runs/xmrig-noise-15m-baseline-20251009T150738Z/xmrig-noise-15m-baseline-20251009T150738Z.jsonl"
#
#   # 別の例（1000Hz、グロブを使用）
#   ./features/make_noise_configs_and_run.sh \
#     15m-1000hz \
#     "runs/xmrig-noise-15m-1000hz-20251009T152637Z/xmrig-noise-15m-1000hz-20251009T152637Z.jsonl"
#
# 注意:
#   - 衝突回避や上書き確認は行いません（同じ prefix で再実行すると上書きされます）。
#   - prefix は英数字・ハイフン・アンダースコア等の素直な文字列推奨です。
#   - 正常系ワークロードの raw パスはスクリプト内の固定値を使用します。
# =============================================================================
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <prefix> \"<xmrig_jsonl_paths>\""
  echo "  <xmrig_jsonl_paths> は単一グロブ or カンマ区切りで複数指定可（必ず引用符で囲む）"
  exit 1
fi

PREFIX="$1"
XMRIG_ARG="$2"

# make_dataset.py の相対パス（必要ならここだけ調整）
MAKE_DATASET="features/make_dataset.py"

# n-gram の固定集合
N_LIST=(5 10 35 40 50)

# configs/<prefix>/ を作成
CONFIG_DIR="configs/${PREFIX}"
mkdir -p "${CONFIG_DIR}"

# カンマ区切り対応 & YAML用のエスケープ
IFS=',' read -r -a XMRIG_ARR <<< "${XMRIG_ARG}"
XMRIG_YAML_ITEMS=()
for p in "${XMRIG_ARR[@]}"; do
  # 前後の空白を軽く除去
  p="${p#"${p%%[![:space:]]*}"}"
  p="${p%"${p##*[![:space:]]}"}"
  # YAML/JSON 風に簡易エスケープ
  p="${p//\\/\\\\}"
  p="${p//\"/\\\"}"
  XMRIG_YAML_ITEMS+=( "\"${p}\"" )
done
XMRIG_PATHS_YAML=$(IFS=', '; echo "${XMRIG_YAML_ITEMS[*]}")

echo "[INFO] prefix=${PREFIX}"
echo "[INFO] xmrig paths=[${XMRIG_PATHS_YAML}]"
echo "[INFO] configs will be written to: ${CONFIG_DIR}"

for n in "${N_LIST[@]}"; do
  CFG_PATH="${CONFIG_DIR}/${PREFIX}-${n}gram.yaml"

  cat > "${CFG_PATH}" <<YAML
framing:
  n: ${n}

workloads:
  - workload: web-serving
    name: Web Serving
    label_id: 0
    paths: ["dataset/raw/web-serving-*.jsonl"]
    target_frames: 35210

  - workload: data-caching
    name: Data Caching
    label_id: 1
    paths: ["dataset/raw/data-caching-*.jsonl"]
    target_frames: 50596

  - workload: media-streaming
    name: Media Streaming
    label_id: 2
    paths: ["dataset/raw/media-streaming-*.jsonl"]
    target_frames: 112003

  - workload: mariadb
    name: MariaDB
    label_id: 3
    paths: ["dataset/raw/database-*.jsonl"]
    target_frames: 43925

  - workload: xmrig
    name: XMRig
    label_id: 4
    paths: [${XMRIG_PATHS_YAML}]
    target_frames: 241043
YAML

  echo "[INFO] generated: ${CFG_PATH}"
  echo "[INFO] running: python ${MAKE_DATASET} --config ${CFG_PATH}"
  python "${MAKE_DATASET}" --config "${CFG_PATH}"
done

echo "[INFO] done. merged outputs should be under dataset/npy/merged/${PREFIX}-*gram/"
