# Cryptojacking Experiment Benchmarks

Kubernetes 上で CloudSuite ベースの正常ワークロードと XMRig（異常）を動作させ、Tetragon のシステムコールトレース（JSONL）から **学習用データセットを自動生成**・解析するためのリポジトリです。
この README では、既存の収集/実行の概要に加えて、\*\*新しい「JSONL → n-gram データセット作成システム」\*\*の使い方を詳しく説明します。

## 現在のディレクトリ構成（抜粋）

```text
cryptojacking-exp/
├── configs/                 # データセット作成の設定ファイル
│   └── five-40gram.yaml
├── dataset/
│   ├── raw/                 # 収集済み JSONL（各ワークロード）
│   └── npy/
│       ├── workloads/       # ワークロード別（再利用用）
│       └── merged/          # 設定単位で結合
├── features/
│   └── make_dataset.py      # JSONL→n-gram データセット作成スクリプト
└── k8s/                     # 各ワークロードのマニフェストと実行スクリプト
```

## 対象ワークロード

* 正常系: Media Streaming / Web Serving / Data Caching / MariaDB（Database）
* 異常系: XMRig（Cryptojacking）

## 収集環境の要点

* 各ワークロードを Kubernetes 上で実行し、**Tetragon** によりシステムコールを **JSONL** として収集します。
* ウォレットや API キーなどの機密はレポジトリに置かず、**Kubernetes Secret** や環境変数で管理してください。
* 公開環境でのマイニングは規約・法令に抵触する可能性があります。**自己管理下の環境**でのみ実施してください。

---

# JSONL → データセット作成システム

## 概要

収集した JSONL を読み込み、\*\*n-gram フレーム（重複あり、ストライド=1）\*\*を作成し、**train/val/test の三分割**で **NumPy（X.npy, y.npy）＋ meta.json** を出力します。
出力は \*\*ワークロード別（再利用資産）**と、設定ファイル単位での**結合（merged）\*\*の両方を生成します。

### 仕様（要点）

* **トリム**: 先頭/末尾を各 **10%** 除去（ウォームアップ/クールダウン除去）
* **フレーミング**: n-gram（`n` は設定で指定、ストライド=1）
* **ラベル跨ぎ禁止**: フレーム内で pod/job/container などが混在する場合は除外
* **三分割**: train/val/test = **56% / 14% / 30%**
  （実装はまず 70/30、その後 70 側を 80/20 に再分割）
* **ガード帯**: 分割境界の**前後 n フレーム**を破棄（データリーク防止）
* **決定的処理**: シャッフルや乱数は使わず、同じ入力・設定で再現可能
* **ログ**: 標準出力のみ（処理条件・件数・shape・最終一覧）

## 依存関係

```bash
python --version     # 3.9+
pip install numpy pyyaml
```

## 設定ファイルの書き方（最小スキーマ）

```yaml
# configs/five-40gram.yaml の例
framing:
  n: 40                  # フレームサイズ（ストライドは常に1）

workloads:
  - workload: web-serving
    name: Web Serving
    label_id: 1
    paths: ["dataset/raw/web-serving-*.jsonl"]
    target_frames: 35210

  - workload: data-caching
    name: Data Caching
    label_id: 2
    paths: ["dataset/raw/data-caching-*.jsonl"]
    target_frames: 50596

  - workload: media-streaming
    name: Media Streaming
    label_id: 3
    paths: ["dataset/raw/media-streaming-*.jsonl"]
    target_frames: 112003

  - workload: mariadb
    name: MariaDB
    label_id: 4
    paths: ["dataset/raw/database-*.jsonl"]
    target_frames: 43925

  - workload: xmrig
    name: XMRig
    label_id: 5
    paths: ["dataset/raw/xmrig-*.jsonl"]
    # 悪性は XMRig 単独だが、目標サンプル数は XMRig + xmr-stak-cpu の合算値に合わせる
    target_frames: 241043
```

* `framing.n`: n-gram の n
* `workloads[]`:

  * `workload`: 論理名（ディレクトリ名等に使用）
  * `name`: 表示名（任意）
  * `label_id`: 整数ラベル（`y.npy` にそのまま書き出し）
  * `paths`: JSONL のパス（複数/グロブ可）
  * `target_frames`: 採用したいフレーム数（**先頭から**採用。不足時はあるだけ採用）

## 実行方法

```bash
# 設定ファイルを指定して実行
python features/make_dataset.py --config configs/five-40gram.yaml

# 既存の同名出力がある場合
python features/make_dataset.py --config configs/five-40gram.yaml --overwrite
# または設定名の末尾に UTC タイムスタンプを付けて別名出力
python features/make_dataset.py --config configs/five-40gram.yaml --run-suffix auto
```

## 出力レイアウト

```text
dataset/
└── npy
    ├── workloads/
    │   └── <workload>/n{n}-gram/
    │       ├── train/{X.npy, y.npy}
    │       ├── val/{X.npy, y.npy}
    │       ├── test/{X.npy, y.npy}
    │       └── meta.json
    └── merged/
        └── <config_basename>/
            ├── train/{X.npy, y.npy}
            ├── val/{X.npy, y.npy}
            ├── test/{X.npy, y.npy}
            └── meta.json
```

* **X.npy**: 形状 `[N, n]`（n はフレームサイズ）
* **y.npy**: 形状 `[N]` の整数ラベル（`label_id`）
* **\<config\_basename>** は設定ファイル名（拡張子除く）

## ログの例（抜粋）

```text
[INFO] START  - config=configs/five-40gram.yaml, cfg_basename=five-40gram, n=40
[INFO] POLICY - trim=10%/10%, stride=1, split=56/14/30 (70/30→80/20), guard=n
[INFO] INPUT  - workload=web-serving, target_frames=35210, paths=['dataset/raw/web-serving-*.jsonl']
[INFO] TRIM   - workload=web-serving, events_total=562610, trim=[56261,506349) -> 450088
[INFO] FRAME  - workload=web-serving, n=40, F_possible=450049, F_valid=450049
[INFO] SELECT - workload=web-serving, selected=35210
...
===== OUTPUT SUMMARY =====
dataset/npy/merged/five-40gram/train/X.npy   shape=(269992, 40)
dataset/npy/merged/five-40gram/train/y.npy   shape=(269992,)
...
==========================
```

## よくある質問（FAQ）

**Q. target\_frames を指定したのに合計が少し減るのはなぜ？**
A. 分割境界ごとに **ガードとして前後 n フレーム**を破棄します。境界が 2 箇所あるため、合計で **2 × n × 1（前後） = 2n** 減ります。例: n=40 なら **160** 減（さらにトリム/除外の影響で前後する場合あり）。

**Q. val を使わない実験でも val を出力するの？**
A. 常に **train/val/test を出力**します。学習時に val を使わない選択は可能です。

**Q. クラス数は固定？**
A. 設定ファイルの `workloads` の行数がそのままクラス数です。5/6クラスなど**自由に構成**できます。

**Q. 不足（valid < target\_frames）の扱いは？**
A. 現仕様は不足のまま採用し、WARNING と `meta.json` に記録します（将来の upsample は拡張点）。

---

# 参考：ワークロードの収集（最小フロー）

各ワークロードをデプロイ → Tetragon でシステムコールを JSONL として収集 → `dataset/raw/` に配置 → 本ツールでデータセット化、の順に進めます。
例として Media Streaming の最小フロー:

```bash
# データセット展開（PV/PVC）
kubectl apply -f k8s/media-streaming/pv.yaml
kubectl apply -f k8s/media-streaming/pvc.yaml
kubectl apply -f k8s/media-streaming/step1-dataset.yaml

# サーバ起動
kubectl apply -f k8s/media-streaming/step2-server.yaml

# クライアント起動
kubectl apply -f k8s/media-streaming/step3-client.yaml

# トレース＆ベンチ実行（Tetragon 前提）
bash k8s/media-streaming/run_media_streaming_capture.sh
```

同様に他ワークロードは `k8s/<workload>/run_*_capture.sh` を参照してください。

---

# ライセンス / 貢献

PR・Issue 歓迎です。運用やスキーマの拡張（例: upsample、indices.npy の出力、JSON ログ）も提案いただければ対応します。
