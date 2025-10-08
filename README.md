# **1. プロジェクト概要とディレクトリ構成**

## **1.1 目的と全体像**

本リポジトリは、Kubernetes 上で正常系ワークロード（Media Streaming / Web Serving / Data Caching / MariaDB）と異常系ワークロード（XMRig）を再現し、Tetragon によるシステムコールログ（JSON Lines; JSONL）を収集・整形して学習用データセット（n-gram）へ変換し、複数モデルで評価するまでを一貫して行うための実験基盤です。

ワークロードの実行、トレース収集、JSONL 整形、n-gram 生成（NumPy + meta.json の階層出力）、学習と評価（スクリプト類・学習済みモデル同梱）までを、ディレクトリとスクリプト単位で再現可能に整理しています。

## **1.2 トップレベル構成（スナップショット）**

```
cryptojacking-exp/
├── config/                 # ローカル設定（機密は置かない）
├── configs/                # データセット生成・評価の設定 (YAML)
├── dataset/                # 収集JSONLと n-gram 出力
├── eval/                   # 評価結果など（例: results.json）
├── features/               # データ生成・評価・学習スクリプト群
├── images/                 # 参考画像
├── k8s/                    # K8sマニフェストと収集スクリプト
├── logs/                   # 実行ログ（ジョブYAML・ランログ）
├── models/                 # 学習済みモデル
├── values-tetragon.yaml    # Tetragon 用 values（例）
├── README.md
└── wwwroot/                # 静的ファイル
```

## **1.3 ディレクトリツアー**

### **config/**

ローカル実行向けの補助設定を置くための場所です（例: config.json）。ワークロードの既定値やパスなど、ユーザー環境依存の値を置く用途を想定しています。リポジトリの再現性を損なわない範囲で使用し、鍵やウォレット等の機密は保管しない方針です。

### **configs/**

データセット生成・評価に使う設定ファイル群です。five-5gram.yaml 〜 five-50gram.yaml は n-gram のフレーム長（n）と、各ワークロードの入力 JSONL パス（グロブ）や採用フレーム数（target_frames）などを定義します。eval.yaml は評価や集計のプリセットを格納する想定の設定です。

特徴:

- framing（n）、ストライド=1、trim（先頭/末尾のトリム）、split（train/val/test 比率）などを宣言的に管理
- workloads 配列に workload 名、表示名、ラベルID、入力パス、採用フレーム数を列挙
- これらを features/make_dataset.py が読み取り、dataset/npy 階層へ出力します

### **dataset/**

収集済み JSONL と、n-gram 変換後の出力一式を格納します。データ再利用・再実験の中核です。

### **dataset/raw/**

Tetragon から整形して得た JSONL をワークロード別に保存します。行単位のレコードで、基本フィールドは ts, pid, pod, container, sc, wl, tid を採用（Tetragon の process_tracepoint から抽出）。命名例は xmrig-noise-<label>-<UTC>.jsonl のように、一目でワークロード・条件・時刻が分かる形式を採用しています。

### **dataset/npy/**

n-gram 化された NumPy 配列（X.npy）とラベル（y.npy）およびメタ情報（meta.json）を、ワークロード別と設定マージ別の二系統で保存します。構造は次のとおりです。

```
dataset/npy/
├── workloads/
│   └── <workload>/
│       └── n<k>-gram/
│           ├── train/{X.npy, y.npy}
│           ├── val/{X.npy, y.npy}
│           ├── test/{X.npy, y.npy}
│           └── meta.json
└── merged/
    └── <config名>/
        ├── train/{X.npy, y.npy}
        ├── val/{X.npy, y.npy}
        ├── test/{X.npy, y.npy}
        └── meta.json
```

共通仕様:

- X.npy: 形状 [N, n] の整数系列（n はフレーム長）
- y.npy: 形状 [N] の整数ラベル（label_id）
- meta.json: 入力ソース、フレーム仕様（n, stride, trim）、分割比（56/14/30 など）、レコード件数・クラス配分などを記録
    
    ワークロード別（workloads）は単一クラスの再利用素材、設定マージ（merged）は複数クラス統合の最終学習素材として使い分けます。
    

### **eval/**

評価結果や中間産物を置く領域です（例: results.json）。features/eval.py 実行の出力先・集計先として利用します。

### **features/**

データ生成・評価・学習のスクリプト群です。最重要は make_dataset.py と eval.py です。

- make_dataset.py
    
    configs/*.yaml を読み、dataset/raw/*.jsonl から n-gram を作成して dataset/npy/ に出力します。データ整形は決定的で、トリム（先頭/末尾10%）、ストライド=1、ラベル跨ぎ除外、ガード帯（分割境界前後 n フレームを除外）などのルールを実装。CLI 例:
    
    python features/make_dataset.py --config configs/five-40gram.yaml [--overwrite|--run-suffix auto]
    
- eval.py
    
    生成済みデータセットや学習済みモデルを読み、再現評価・指標集計を行うための起点スクリプトです。configs/eval.yaml のプリセットを参照する想定で、結果は eval/ 配下に保存します。
    
- train-dt.py / train-knn.py / train-mlp.py / train-rnn.py / train-svm.py
    
    各モデルの学習スクリプト。入力として dataset/npy/merged/<config>/ か dataset/npy/workloads/... を与え、学習済みモデルを models/ 以下に保存します（乱数シードを固定して再現性を担保）。
    

### **images/**

補助画像の置き場です（例: images/xmrig/）。README や発表資料に貼る図版などを管理します。

### **k8s/**

Kubernetes マニフェストと実行スクリプトをワークロード別に整理しています。各ワークロードには「手順用マニフェスト（step1〜）」「ポリシー（TracingPolicy）」「収集スクリプト（run_*_capture.sh）」などが含まれます。

### **k8s/xmrig-noise/**

XMRig にノイズ注入（LD_PRELOAD）を組み合わせたワークロード。実験で特に重要です。

- images/Dockerfile
    
    XMRig 本体（CPUビルド）と noise.c から libnoise.so をビルド・同梱した最小ランタイムイメージを構築します。
    
- images/entrypoint.sh
    
    BENCH_ARGS など環境変数をそのまま xmrig に渡す薄いラッパ。ログを標準出力へ出し、Job から利用します。
    
- images/noise.c
    
    LD_PRELOAD で常駐する最小ノイズライブラリ。NOISE_ENABLE が 0 の場合は無効化、NOISE_RATE_HZ に応じて getpid を連打（0 で busy）します。副作用最小化のため pthread でデタッチして実行します。
    
- scripts/run_xmrig_noise.sh
    
    ホストで実行する制御スクリプト。Tetragon のログを jq で整形して dataset/raw/ に保存しつつ、Job を kubectl apply 相当で生成。"benchmark finished" を検知したら監視を停止します。--bench、--noise_enable、--noise_rate、--ldpreload、--outfile などの引数で挙動を切り替えます。
    
- xmrig-noise-policy.yaml
    
    Tetragon の Namespaced TracingPolicy（raw_syscalls/sys_exit を追跡、引数 index=4 を syscall 番号として抽出）。
    
- xmrig-noise-deploy.yaml
    
    Job/Deployment テンプレート（最新では Job 形式で使用）。環境変数（BENCH_ARGS、NOISE_*、LD_PRELOAD）は主に run_xmrig_noise.sh から注入します。
    

### **k8s/その他のワークロード**

- media-streaming/、web-serving/、data-caching/、database/ それぞれに、段階的デプロイ用マニフェスト（step*.yaml）と収集スクリプト（run_*_capture.sh）、TracingPolicy（*-policy.yaml）を配置。
- 収集スクリプトは Tetragon の export-stdout コンテナから kubectl logs -f | jq で JSONL を生成する共通パターンを踏襲しています。

### **logs/**

実行時の制御ログと、生成した Job マニフェストのスナップショットを保存します（例: xmrig-noise-<label>-<timestamp>.run.log / .job.yaml）。ベンチ実行条件・環境変数・監視プロセス状態（PGID など）を可視化し、再現性とトラブルシュートに役立ちます。

### **models/**

学習済みモデルを格納します（例: dt_35.joblib, svm_50_all.joblib, lstm.model.keras など）。入力想定は dataset/npy/merged/<config>/ の X.npy（int 系列、RNN は int32）と y.npy。乱数シードはスクリプト内で固定し、同じ入力なら同じ結果が得られる前提です。

### **values-tetragon.yaml**

Tetragon の Helm values の例です。クラスタ環境に合わせて export-stdout の有効化、RBAC、フィルタ設定などを調整する起点として扱います。

### **README.md**

プロジェクトの説明書。収集から学習・評価までの全体フローと実行手順の概要をまとめます（本ドキュメントの章立てを反映して更新予定）。

### **minikube-logs.txt**

Minikube（またはローカルK8s）上の動作ログをまとめたファイルです。ビルドやイメージ転送、Pod 状態の時系列調査に使用します。

### **wwwroot/**

静的ファイル置き場。可視化出力や簡易ダッシュボード、HTML 資料等を配置する用途を想定しています。

## **1.4 重要ファイル早見**

- 設定の起点: configs/*.yaml（n-gram 設計と入力データの宣言）
- データ生成: features/make_dataset.py（JSONL → n-gram → dataset/npy）
- 評価の起点: features/eval.py（configs/eval.yaml を参照する想定）
- 収集の起点: k8s/*/run_*_capture.sh（Tetragon → dataset/raw）
- XMRig+ノイズ: k8s/xmrig-noise/images/{Dockerfile, entrypoint.sh, noise.c}, k8s/xmrig-noise/scripts/run_xmrig_noise.sh
- トレースポリシー: k8s/*/*-policy.yaml（TracingPolicyNamespaced）

## **1.5 実行前提**

- Kubernetes クラスタと kubectl
- Tetragon（export-stdout でログ出力可能な構成）
- Docker 互換ランタイム（ローカルビルド・Minikube へのイメージロード等）
- jq（収集パイプラインで使用）
- Python 3.9+（最低限 numpy, pyyaml、学習用に scikit-learn や tensorflow 等）





# **2. データ収集（Kubernetes + Tetragon）**

## **2.1 目的と全体像**

Kubernetes 上で各ワークロード（CloudSuite 系と XMRig）を実行し、Tetragon が出力する JSON ストリームから **syscall イベントを JSONL 形式で収集**します。整形は jq で行い、出力先はリポジトリ配下の dataset/raw/ です。以降のデータセット生成（n-gram 化）・学習は、この JSONL を入力に進みます。

## **2.2 収集の流れ（標準パイプライン）**

1. Tetragon の export-stdout から生イベントを取得
    
    kubectl -n kube-system logs ds/tetragon -c export-stdout -f
    
2. jq で必要フィールドに整形（timestamp / pid / pod / container / syscall 番号 / wl / tid）
3. dataset/raw/ に .jsonl として保存（ワークロード名とUTCタイムスタンプで命名）
4. 必要に応じて「ベンチマーク開始〜終了」のウィンドウに切り抜き（CloudSuite 系の run_*_capture.sh で実装）

## **2.3 Tetragon の導入と確認**

- 本リポジトリの Helm 設定例は values-tetragon.yaml にあります（標準の export-stdout を前提）。
- 稼働確認

```
kubectl -n kube-system get ds tetragon
kubectl -n kube-system logs ds/tetragon -c export-stdout --since=1m | head
```

- 出力に process_tracepoint 系イベントが流れていれば OK です。

## **2.4 TracingPolicy（収集するイベントの定義）**

- 例（XMRig-noise 用、実ファイル: k8s/xmrig-noise/xmrig-noise-policy.yaml）

```
apiVersion: cilium.io/v1alpha1
kind: TracingPolicyNamespaced
metadata:
  name: xmrig-noise-policy
  namespace: xmrig-noise
spec:
  podSelector:
    matchLabels:
      app: xmrig-noise
  tracepoints:
  - subsystem: raw_syscalls
    event: sys_exit
    args:
    - index: 4
      type: int64
      label: syscall
```

- 
- ポイント
    - podSelector.matchLabels と **Pod/Job 側の metadata.labels.app** を一致させること（一致しないとイベントが取れません）。
    - sys_exit を使うと終了時の syscall 番号が安定して拾えます。必要に応じて sys_enter を別ポリシーで併用可能です。

## **2.5 ラベルと名前空間の方針**

- すべての収集対象 Pod/Job に app: <workload> ラベルを付与
    
    例：app: xmrig-noise, app: server, app: client など
    
- 収集対象の名前空間をワークロードごとに分ける（例：xmrig-noise, media-streaming 等）
- TracingPolicy は **各名前空間に Namespaced で配置**し、その NS 内の対象 Pod に絞り込む

## **2.6 jq フィルタ（採用中の整形仕様）**

- 採用中の最小・安定版（XMRig-noise で実績あり）

```
kubectl -n kube-system logs ds/tetragon -c export-stdout -f | jq -c '
  select(.process_tracepoint? and .process_tracepoint.process.pod.namespace=="xmrig-noise") |
  {
    ts: (.time // .process_tracepoint.time // .ts),
    pid: (.process_tracepoint.process.pid // .process.pid),
    pod: (.process_tracepoint.process.pod.name // .pod // ""),
    container: (.process_tracepoint.process.container.name // .container // ""),
    sc: ((.process_tracepoint.args[0].long_arg // .process_tracepoint.args[0].int_arg // .sc // .nr // .syscall // .id) | tonumber?),
    wl: "xmrig-noise",
    tid: (.process_tracepoint.process.tid // .process.tid)
  }
  | select(.sc != null)
' > dataset/raw/xmrig-noise-<UTC>.jsonl
```

- 
- フィールド仕様
    - ts は複数候補から最初に存在するものを採用（.time → .process_tracepoint.time → .ts）
    - sc は複数型 (long_arg / int_arg / sc / nr / syscall / id) に対応し、tonumber? で安全に整数化
    - wl はワークロードの固定文字列（後段のデータセット化でラベルに使います）

## **2.7 各ワークロードの収集スクリプト（雛形と役割）**

k8s/<workload>/run_*_capture.sh が基本的に同じ骨格を持ちます。例：k8s/data-caching/run_data_caching_capture.sh

- 概要
    - 監視開始（Tetragon → jq → 一時ファイル）
    - 「ベンチマーク開始〜終了」の期間を記録（開始・終了タイムスタンプ）
    - クライアント/サーバのベンチを起動
    - 期間で切り抜き → dataset/raw/<workload>-<UTC>.jsonl へ保存
    - 付帯ログや meta.json、*.log を logs/ や dataset/metadata/ に保存
- ここで使う jq は、上記 2.6 と同一方針（NS と wl をワークロード名に合わせて変更）

## **2.8 XMRig-noise（Job 直接起動）向け最小ワークフロー**

- 実体：k8s/xmrig-noise/scripts/run_xmrig_noise.sh
    - 処理の流れ
        1. 監視開始（Tetragon → jq → 直接 dataset/raw/ へ）
        2. kubectl apply -f - で Job を生成（環境変数で BENCH_ARGS, NOISE_ENABLE, NOISE_RATE_HZ、必要なら LD_PRELOAD=/opt/libnoise.so を注入）
        3. kubectl logs -f pod/<pod> で "benchmark finished" を検知し、監視だけ停止
        4. 生成ファイルを xmrig-noise-<label>-<UTC>.jsonl で確定
- Job は **ラベル付け必須**（TracingPolicy に一致）
    - metadata.labels.app: xmrig-noise
    - spec.template.metadata.labels.app: xmrig-noise
- entrypoint（k8s/xmrig-noise/images/entrypoint.sh）は BENCH_ARGS をそのまま xmrig に渡すだけの最小構成
    
    LD_PRELOAD を付けるかは **Job の環境変数**で制御（noise.c は NOISE_ENABLE=0 ならスレッド起動せず実質無効）
    

## **2.9 出力ファイル命名と置き場所**

- 保存先（共通）：dataset/raw/
- 命名規則例
    - CloudSuite 系：<workload>-<UTC>.jsonl
    - XMRig-noise：xmrig-noise-<任意ラベル>-<UTC>.jsonl
- 例（実リポジトリに含まれるもの）

```
dataset/raw/
  data-caching-20250821T145647Z-7740.jsonl
  media-streaming-20250814T063849Z-8e7d.jsonl
  web-serving-20250820T174201Z-1fa7.jsonl
  xmrig-20250814T143303Z-7370.jsonl
  xmrig-noise-exp1-20251002T193502Z.jsonl
```

## **2.10 k8s ディレクトリの使い分け**

```
k8s/
  data-caching/     # CloudSuite Data Caching: policy と stepX-*.yaml、run_*_capture.sh
  media-streaming/  # CloudSuite Media Streaming: PV/PVC → server → client → run_*_capture.sh
  web-serving/      # DB → memcached → web → faban → run_*_capture.sh
  database/         # MariaDB 系: db.yaml / policy / run_*_capture.sh
  xmrig/            # XMRig 通常・偽装のデプロイとポリシー、run_xmrig_capture.sh
  xmrig-noise/      # ノイズ入り XMRig: Dockerfile/noise.c/entrypoint.sh、Job、policy、run_xmrig_noise.sh
```

- 各 workload ディレクトリに「TracingPolicy」と「実行スクリプト」が揃っているのが基本形です。
- XMRig-noise は **コンテナを自前ビルド**（k8s/xmrig-noise/images/）し、run_xmrig_noise.sh から Job を直接生成する設計です。

## **2.11 運用のコツとトラブルシュート**

- 監視が 0 行になる
    - ラベル不一致（TracingPolicy の podSelector と Pod/Job の metadata.labels の不一致）をまず疑う
    - 名前空間の取り違え（select(.process_tracepoint.process.pod.namespace=="<ns>") と実際の NS が一致しているか）
    - XMRig ベンチは**ユーザ空間中心**で syscall が少ないため、ノイズ無効（LD_PRELOAD 無・NOISE_ENABLE=0）だとイベントは極端に少なくなります
- kubectl logs -f ds/tetragon が途中で止まる
    - フィルタ後段で grep -m1 を使う場合は、上流へ SIGPIPE が返るため終了コードが 141 になることがあります（異常ではありません）
- 大量収集時の安定化
    - -since= を使って直近のみを追う
    - 監視プロセスをプロセスグループで起動して確実に一括停止（setsid / kill -- -PGID）
        
        これは k8s/xmrig-noise/scripts/run_xmrig_noise.sh に実装済みです
        

この章の内容だけで、Tetragon のログストリームから dataset/raw/ へ整形済み JSONL を安全に吐き出せる構成になっています。続く章では、この JSONL を入力に n-gram データセットを生成し、評価まで進めます。





# **3. 収集パイプライン（XMRig + ノイズ注入）**

## **3.1 概要**

本章は、XMRig を Kubernetes Job として起動し、Tetragon のトレースを jq で整形して JSONL に保存する一連の流れをまとめます。ノイズ挿入（noise.c）は LD_PRELOAD による軽量なスレッドで、getpid/nanosleep を発行して意図的にシステムコール密度を上げ、学習用の信号強度を調整できます。

## **3.2 構成要素**

### **3.2.1 コンテナイメージ（k8s/xmrig-noise/images）**

- Dockerfile
    
    ビルド段階で XMRig を CPU 向けに静的ビルドし、同じディレクトリの noise.c から libnoise.so を生成。ランタイム段では最小限の依存のみを入れ、/usr/local/bin/xmrig と /opt/libnoise.so を配置。エントリポイントは後述の entrypoint.sh。
    
- entrypoint.sh
    
    Job の環境変数 BENCH_ARGS をそのまま渡して xmrig を実行するだけの薄いラッパ。出力例：--bench=1M。
    
- noise.c
    
    LD_PRELOAD でロードされる共有ライブラリ。プロセス起動時のコンストラクタで専用スレッドを起動し、環境変数で駆動。
    
    - NOISE_ENABLE（既定 1）: 0 の場合はスレッドを起動せず完全無効化
    - NOISE_RATE_HZ（既定 1000）: 1 秒あたりの発行回数。0 は busy（休まず連打）
    - 実装は syscall(SYS_getpid) と必要に応じて nanosleep のみ。
        
        つまり **LD_PRELOAD を設定し、かつ NOISE_ENABLE=1** のときだけノイズが入ります。
        

### **3.2.2 トレースポリシ（k8s/xmrig-noise/xmrig-noise-policy.yaml）**

- Namespaced TracingPolicy で raw_syscalls/sys_exit を購読。tetragon の export-stdout から JSON をストリーミングし、のちの jq でワークロード名とシスコール番号に整形。

### **3.2.3 実行スクリプト（k8s/xmrig-noise/scripts/run_xmrig_noise.sh）**

- ホストで実行するドライバ。やっていることは次のとおり。
    1. kubectl logs ds/tetragon -f | jq -c … > dataset/raw/*.jsonl をバックグラウンド起動
    2. Job をその場で生成（kubectl apply -f -）し、環境変数を注入
    3. kubectl logs -f pod/<…> | grep -m1 "benchmark finished" でベンチ終了を検知
    4. 監視パイプラインを停止して JSONL を確定
- 重要な引数（例）
    - -bench=1M --noise_enable=1 --noise_rate=1000 --ldpreload=1 --outfile=exp1
    - -bench → BENCH_ARGS に正規化（例: --bench=1M）
    - -noise_enable → NOISE_ENABLE（0/1）
    - -noise_rate → NOISE_RATE_HZ（整数、0 は busy）
    - -ldpreload=1 で LD_PRELOAD=/opt/libnoise.so を Job に注入
    - -outfile は出力ファイル名ラベルに使用

## **3.3 実行手順の例（minikube 前提）**

1. イメージをビルドして minikube へロード

```
docker build --network=host -f k8s/xmrig-noise/images/Dockerfile \
  -t xmrig-noise:latest k8s/xmrig-noise/images
minikube image load xmrig-noise:latest
```

1. ポリシ適用（未適用なら）

```
kubectl apply -f k8s/xmrig-noise/xmrig-noise-policy.yaml
```

1. 収集＋ベンチを一発実行（ホストで）

```
k8s/xmrig-noise/scripts/run_xmrig_noise.sh \
  --bench=1M --noise_enable=1 --noise_rate=1000 --ldpreload=1 --outfile=exp1
```

## **3.4 出力**

- 保存先: dataset/raw/
- 命名規則: xmrig-noise-<label>-<UTC時刻>.jsonl（例: xmrig-noise-exp1-20251002T190952Z.jsonl）
- JSONL の1行構造（整形済み）
    
    {"ts": <ISO8601Z>, "pid": <int>, "pod": "<name>", "container": "<name|empty>", "sc": <int>, "wl": "xmrig-noise", "tid": <int>}
    

## **3.5 運用ノート**

- ベンチマーク終了検知はログの "benchmark finished" をトリガにしています。XMRig がプロンプト待ちになっても監視は止まります。Job 側を Completed にしたい場合は、将来的に entrypoint で同ログを検知して xmrig を明示終了する案が有効です。
- ノイズを無効にすると（LD_PRELOAD 未設定 or NOISE_ENABLE=0）XMRig はユーザ空間中心で動作するため、syscall 密度は大きく減ります。収集テスト時はまずノイズ有効で動作確認するのが安全です。
- Tetragon のコンテナ名は環境により export-stdout か tetragon です。本リポジトリのスクリプトは自動検出ロジックを持ち、export-stdout を優先します。





# **第4章 データセット生成（JSONL → n-gram）**

## **4.1 目的と全体像**

Tetragon が出力した JSONL から、学習用の n-gram フレーム列を作り、ワークロード別と設定（構成）別の両方で NumPy 形式に保存する。実装は再現性と単純さを優先しており、同じ入力と設定から同じ出力が得られる。

- 実体: features/make_dataset.py
- 入力: dataset/raw/<workload-*.jsonl>（グロブ可）
- 出力:
    - ワークロード別: dataset/npy/workloads/<workload>/n{n}-gram/{train,val,test}/{X.npy,y.npy}, meta.json
    - 設定（マージ）別: dataset/npy/merged/<cfg_basename>/{train,val,test}/{X.npy,y.npy}, meta.json

処理方針（抜粋）:

- フレームサイズ n は設定ファイルで指定、ストライドは 1 固定
- 先頭・末尾 10% を自動トリム
- 生成した全フレームから「先頭」より target_frames を採用（不足は警告の上、あるだけ採用）
- 分割は 70/30 → 70 側を 80/20（= train 56%, val 14%, test 30%）
- 各分割境界の前後 n フレームをガードとして破棄（データリーク防止）
- pod/job/container を用いた「ラベル跨ぎ（セグメント跨ぎ）」フレームは採用しない
- すべて標準出力ログのみ。最後に出力ファイル一覧と shape を表示

## **4.2 実行方法（CLI）**

```
# 例：40-gram 設定で実行
python features/make_dataset.py --config configs/five-40gram.yaml

# 既存の同名 merged 出力がある場合の上書き
python features/make_dataset.py --config configs/five-40gram.yaml --overwrite

# 既存がある場合にタイムスタンプを自動付与して別名で出力
python features/make_dataset.py --config configs/five-40gram.yaml --run-suffix auto
```

引数:

- -config <path>: YAML/JSON の設定ファイル（必須）
- -overwrite: dataset/npy/merged/<cfg_basename> が存在するとき削除して再生成
- -run-suffix auto: 競合時に <cfg_basename>-YYYYmmddThhmmZ へ退避して保存

cfg_basename は設定ファイル名（拡張子除く）をサニタイズしたもの。

## **4.3 設定ファイルの形式（YAML/JSON）**

最小スキーマ:

```
framing:
  n: 40                       # フレーム長（ストライドは常に1）

workloads:
  - workload: web-serving     # 論理名（ディレクトリ名等に使用）
    name: Web Serving         # 表示名（任意）
    label_id: 1               # 整数ラベル（y.npy に書き出し）
    paths: ["dataset/raw/web-serving-*.jsonl"]  # 入力ファイルのグロブ
    target_frames: 35210      # 先頭から採用するフレーム数（不足はあるだけ採用）

  - workload: xmrig
    name: XMRig
    label_id: 5
    paths: ["dataset/raw/xmrig-*.jsonl"]
    target_frames: 241043
```

要点:

- 設定ファイルは .yaml/.yml/.json を受け付ける。
- framing.n は必須（整数）。workloads[] は 1 つ以上必要。
- label_id は全ワークロードで重複不可（重複時はエラーで停止）。
- target_frames は「選抜したい上限」。ガード/トリム/除外の結果として不足することがある（WARNING 表示）。

## **4.4 JSONL の想定フォーマットと柔軟な抽出**

本スクリプトは「ゆるく」各値を推定抽出する。生成 AI に設定を作らせる際に重要となる要点を明記する。

### **4.4.1 システムコール番号の抽出**

- int そのもの、または以下のキーから抽出（優先順）:
    - syscall, syscall_id, nr, sc, id
    - ネスト: event.syscall.id, event.id, syscallNumber など
- 文字列の数字 "123" も許容
- 見つからなければ該当行は無視

### **4.4.2 セグメントキー（ラベル跨ぎ検出）**

- pod/job/container などのまとまりを検出して、同一フレーム内で混在しないようにする
- 参照キー例（存在すれば採用・結合してハッシュ化）:
    - pod, job, container_id
    - k8s.pod, k8s.job, k8s.container_id
- 見つからない場合は単一セグメント（0）として扱う

### **4.4.3 タイムスタンプ**

- 秒/ミリ/ナノの曖昧さがあるため、用途は「並び替えの安定化」のみ
- 候補キー: ts, time, timestamp, @timestamp, event.time, event.ts
- 無ければファイル内の出現順をそのまま保持

## **4.5 前処理・フレーミング・選抜**

1. トリム: 入力列の先頭・末尾を各 10% 破棄（ウォームアップ/クールダウン除去）
2. フレーミング: stride=1 の n 連続ウィンドウ（NumPy の sliding_window_view 使用）
3. セグメント一様性: 各ウィンドウ内でセグメントキーが一様でない（= 跨いでいる）フレームは除外
4. 選抜: 生成フレームの先頭から target_frames を採用（不足は WARNING の上であるだけ）

## **4.6 データ分割とガード**

- 基本分割: 70%/30% に分け、70% 側を 80%/20% に再分割
    
    → train: 56%, val: 14%, test: 30%
    
- ガード: 70/30 の境界、80/20 の境界それぞれについて、**前後 n フレーム**を破棄
    
    → 目標フレーム数から **最大 2n**（境界×2）程度の目減りがあり得る
    

## **4.7 出力レイアウトとファイル内容**

### **4.7.1 ワークロード別**

```
dataset/
└── npy/
    └── workloads/
        └── <workload>/               # 例: web-serving, xmrig など
            └── n{n}-gram/            # 例: n40-gram
                ├── train/
                │   ├── X.npy         # shape=(N_train, n)  整数のシステムコールID列
                │   └── y.npy         # shape=(N_train,)    整数ラベル（label_id）
                ├── val/
                │   ├── X.npy         # shape=(N_val, n)
                │   └── y.npy         # shape=(N_val,)
                ├── test/
                │   ├── X.npy         # shape=(N_test, n)
                │   └── y.npy         # shape=(N_test,)
                └── meta.json         # 出力メタ情報
```

meta.json（ワークロード別）の主なフィールド:

- workload, name, label_id, n
- trim_pct（head/tail=0.10）
- guard_frames（= n）
- target_frames
- splits.{train,val,test}.count

### **4.7.2 設定（マージ）別**

```
dataset/
└── npy/
    └── merged/
        └── <cfg_basename>/
            ├── train/{X.npy,y.npy}
            ├── val/{X.npy,y.npy}
            ├── test/{X.npy,y.npy}
            └── meta.json
```

meta.json（マージ側）の主なフィールド:

- config_basename（競合時は -YYYYmmddThhmmZ 付き）
- n
- label_map（{<workload>: <label_id>}）
- workloads（順序は設定ファイルの定義順）
- splits.{train,val,test}.count（縦結合後の件数）

## **4.8 ログ出力とバリデーション**

- ログ例（標準出力）:
    - [INFO] START, POLICY, INPUT, TRIM, FRAME, SELECT, SAVE, MERGE
    - 最終行近くに ===== OUTPUT SUMMARY ===== と各 .npy の shape 一覧
- バリデーション:
    - label_id の重複を事前チェック（重複時はエラー終了）
    - 生成した X.npy の幅が n と一致するかを確認（不一致はエラー）
- 入力ゼロや JSON パース不能行は自動スキップ（必要に応じて WARNING）

## **4.9 代表的な使い方の流れ**

1. dataset/raw/ に各ワークロードの JSONL を集約（ファイル名にワークロード名の接頭辞を付けると管理が楽）
2. configs/*.yaml で framing.n と各 workloads[].paths / target_frames / label_id を記述
3. python features/make_dataset.py --config configs/five-40gram.yaml
4. 生成物を学習スクリプト（例: features/train-*.py）へ渡す
    - ワークロード別を個別学習に、merged を総合学習に利用可能

## **4.10 よくある落とし穴（回避策）**

- 同一 label_id を重複させない
    
    → 設定ファイルを見直し。複数ワークロードを 1 ラベルにまとめたい場合は、設定側でワークロードを統合する。
    
- target_frames に届かない
    
    → トリム/ガード/ラベル跨ぎ除外で減るのは仕様。必要なら target_frames を下げる、または JSONL を増やす。
    
- merged 出力の上書きでエラー
    
    → --overwrite か --run-suffix auto を付けて実行。





# **第5章 評価（features/eval.py）**

## **5.1 目的と位置づけ**

features/eval.py は、作成済みの n-gram データセット（dataset/npy/merged/**）に対して、用意した学習済みモデル群を一括で推論し、主要評価指標を標準出力に表示しつつ JSON へ保存する評価ユーティリティです。実験ごとの精度比較と再現性のある記録を目的とします。

## **5.2 前提（入力と依存）**

### **5.2.1 入力データ**

- 対象は **merged/test** 分割の X.npy, y.npy と meta.json。
    
    例：
    
    - dataset/npy/merged/five-40gram/test/{X.npy,y.npy}（meta.json の n が 40）
    - dataset/npy/merged/five-35gram/test/{X.npy,y.npy}（meta.json の n が 35）
    - 同様に 50, 10, 5 など設定に応じたディレクトリ
- meta.json の n と X.npy.shape[1] を照合して不一致なら停止します（安全チェック）。

### **5.2.2 参照する学習済みモデル**

デフォルトで下表の **モデル⇔データ** 対応を固定で評価します（MODELS リスト）:

| **name** | **kind** | **model_path** | **data_path** | **期待 n** |
| --- | --- | --- | --- | --- |
| rnn_40 | keras | models/lstm.model.keras | dataset/npy/merged/five-40gram | 40 |
| dt_35 | sklearn | models/dt_35.joblib | dataset/npy/merged/five-35gram | 35 |
| svm_50 | sklearn | models/svm_50_all.joblib | dataset/npy/merged/five-50gram | 50 |
| mlp_10 | sklearn | models/mlp_10.joblib | dataset/npy/merged/five-10gram | 10 |
| knn_5 | sklearn | models/knn_5.joblib | dataset/npy/merged/five-5gram | 5 |

> 上記ファイルが存在しない場合は、そのモデル分だけエラーを記録しつつ処理継続します。
> 

### **5.2.3 Python 依存**

- 共通: numpy, joblib, scikit-learn
- Keras モデル使用時のみ: tensorflow（rnn_40 対象）
- メトリクス: scikit-learn（accuracy_score, precision_recall_fscore_support, classification_report）

## **5.3 スクリプトの挙動**

### **5.3.1 モデルとデータのマッピング**

MODELS に定義された順で処理します。各要素は {name, kind, model_path, data_path} を持ち、kind により推論ルートを切り替えます。

- sklearn: joblib.load(model).predict(X)
- keras: tf.keras.models.load_model(model) → 事前に X を int32 へキャスト → predict → argmax

### **5.3.2 ロードと検証**

- load_test(data_path) が meta.json を読み、X.npy, y.npy をロード。
- assert X.shape[1] == meta["n"] で系列長 n の一致を確認。

### **5.3.3 推論と指標算出**

- 予測 y_pred を得たら以下を計算して辞書化します：
    - accuracy
    - precision_weighted, recall_weighted, f1_weighted
    - precision_macro, recall_macro, f1_macro
- 併せて classification_report を標準出力へ整形出力。

### **5.3.4 ログとタイムスタンプ**

- 走行開始・モデルごとの開始/終了・精度が JST の時刻でコンソール出力されます。
- 失敗時は例外の型とメッセージを記録して継続します。

## **5.4 使い方**

### **5.4.1 実行コマンド**

```
python features/eval.py
```

追加の引数は不要です（固定マッピング一括評価）。モデルやデータの配置が表のとおりであれば、そのまま動作します。

### **5.4.2 出力ファイル**

- eval/results.json を生成（親ディレクトリが無ければ自動作成）。
- コンソールには各モデルのサマリ（acc など）と classification_report を出力。

### **5.4.3 results.json の構造（例）**

```
{
  "started_at": "2025-10-03 12:34:56 JST",
  "finished_at": "2025-10-03 12:35:12 JST",
  "results": [
    {
      "name": "rnn_40",
      "kind": "keras",
      "model_path": "models/lstm.model.keras",
      "data_path": "dataset/npy/merged/five-40gram",
      "n": 40,
      "test_N": 123456,
      "started_at": "2025-10-03 12:34:56 JST",
      "finished_at": "2025-10-03 12:35:05 JST",
      "accuracy": 1.0,
      "precision_weighted": 1.0,
      "recall_weighted": 1.0,
      "f1_weighted": 1.0,
      "precision_macro": 1.0,
      "recall_macro": 1.0,
      "f1_macro": 1.0
    },
    {
      "name": "svm_50",
      "kind": "sklearn",
      "model_path": "models/svm_50_all.joblib",
      "data_path": "dataset/npy/merged/five-50gram",
      "error": "FileNotFoundError: ...",
      "started_at": "2025-10-03 12:35:05 JST",
      "finished_at": "2025-10-03 12:35:05 JST"
    }
  ]
}
```

results[].error がある要素は、そのモデルが未配置/不整合でスキップされたことを示します。

## **5.5 よくあるエラーと対処**

- AssertionError: n mismatch: meta.json の n と X.shape[1] が不一致。make_dataset.py で使った設定（例：five-40gram.yaml）に対応する models/* を選んでください。
- FileNotFoundError（モデル/データ）: 対応する model_path または data_path が存在しない。ファイル名とディレクトリを再確認。
- TensorFlow 関連 ImportError: keras モデルを評価する場合のみ tensorflow が必要です。pip install tensorflow を実行。

## **5.6 カスタマイズ**

### **5.6.1 モデルを追加・置換する**

features/eval.py 内の MODELS リストに要素を追加/編集します。例：

```
MODELS.append({
  "name": "rf_40",
  "kind": "sklearn",
  "model_path": "models/rf_40.joblib",
  "data_path": "dataset/npy/merged/five-40gram"
})
```

kind は sklearn または keras を指定。data_path 側の meta.json["n"] とモデルの想定入力長が一致していることを確認してください。

### **5.6.2 データバリアントの評価**

別設定で生成した merged ディレクトリ（例：dataset/npy/merged/five-35gram-20251003T1200Z）を評価したい場合は、該当パスへ data_path を差し替えます。

## **5.7 実行時の注意点**

- メモリ使用量は X.npy (test) の行数と n に依存します。巨大な X.npy を評価する場合は十分なメモリを確保してください（Keras/RNN は特に）。
- Keras 評価時は X を int32 にキャストしてから推論します（Embedding 前提）。他のモデルと混在しても内部で切り替え済みです。
- すべてのモデルを一度に評価する運用を想定していますが、比較対象を限定したい場合は MODELS を減らして実行してください。



# **第6章 ノイズあり（XMRig + LD_PRELOAD）**

## **6.1 概要**

本章は、XMRig 実行プロセスに対して LD_PRELOAD で軽量な「ノイズ発生ライブラリ」を注入し、システムコール頻度を人工的に増やす仕組みをまとめる。ノイズは getpid(2) と必要に応じて nanosleep(2) のみを発行する最小実装で、Tetragon による観測で「高頻度の簡単なシステムコールが連続する」挙動を再現・コントロールできる。Kubernetes では、env で挙動を切り替え、LD_PRELOAD の有無で注入可否を制御する。

## **6.2 noise.c の設計と挙動**

### **6.2.1 動作タイミングとスレッド**

- 共有ライブラリのコンストラクタ（__attribute__((constructor))）で起動。
- 起動時に NOISE_ENABLE を読み、無効なら即座に何もしない。
- 有効時は pthread_create で 1 本のノイズ専用スレッドを生成し pthread_detach。アプリ本体（XMRig）の制御フローには割り込まない。

### **6.2.2 発行するシステムコール**

- メインは syscall(SYS_getpid) をループで発行。
- 休止ありモードでは各ループで nanosleep() を呼ぶ。
- これにより、トレース上は「getpid と nanosleep が交互または偏って現れる」パターンになる。
    - 具体的な syscall 番号はアーキテクチャ依存（例: ARM64 環境では実験ログ上 sc=172 と sc=115 が主に増加）。

### **6.2.3 環境変数の解釈**

- NOISE_ENABLE（既定 1）
    - 0 で完全無効（スレッド未起動、オーバーヘッド無し）。
    - 1 で有効。
- NOISE_RATE_HZ（既定 1000）
    - 1 秒あたりの発行回数。>0 の場合は周期 1e9 / rate_hz ナノ秒で getpid → nanosleep を繰り返す。
    - 0 の場合は busy モード（nanosleep を呼ばず getpid を連打）。CPU を強く消費しうるため注意。
- 読み取りは strtol ベースで実装され、負値は 0（busy）に丸め、極端な大値は 1e9 にクランプ。無効文字列は既定値にフォールバックする。
- 失敗時は静粛に無視（副作用最小化）。コンストラクタやスレッド生成が失敗してもアプリは継続。

### **6.2.4 目標と限界**

- 目的は「監視系にとって分かりやすい、意図的に高頻度の軽量コール」を注入すること。
- アプリ動作やカーネル・ネットワークへの直接的な副作用は最小化しているが、busy モードは CPU を占有しうる。
- 実験環境の CPU/メモリ割当や cgroup 制限に依存して観測されるレートは変化する。

## **6.3 環境変数と起動例**

### **6.3.1 必須・任意の指定**

- LD_PRELOAD：/opt/libnoise.so を指定したときのみノイズが有効候補になる。
- NOISE_ENABLE：1/0 でオン・オフ。
- NOISE_RATE_HZ：レート指定（0 は busy）。

### **6.3.2 代表的な設定例**

- ノイズ無効（既定の XMRig のみ）
    - LD_PRELOAD を未設定、もしくは NOISE_ENABLE=0。
- 1kHz の軽負荷ノイズ
    - LD_PRELOAD=/opt/libnoise.so, NOISE_ENABLE=1, NOISE_RATE_HZ=1000。
- 負荷最大（busy）
    - LD_PRELOAD=/opt/libnoise.so, NOISE_ENABLE=1, NOISE_RATE_HZ=0（nanosleep なし、getpid 連打）。

## **6.4 コンテナイメージとエントリポイント**

### **6.4.1 ビルドと配置**

- k8s/xmrig-noise/images/Dockerfile
    - Stage1 で XMRig をビルド。
    - 同ディレクトリの noise.c を共有ライブラリ libnoise.so にビルドし /opt/libnoise.so へ配置。
- 実行時イメージに XMRig バイナリと libnoise.so をコピー。

### **6.4.2 entrypoint.sh の役割**

- k8s/xmrig-noise/images/entrypoint.sh
    - BENCH_ARGS 等の環境変数を表示し、exec /usr/local/bin/xmrig ${BENCH_ARGS} で XMRig を起動。
    - ノイズ注入自体は LD_PRELOAD により自動で行われ、entrypoint は注入可否を直接判定しない。

## **6.5 実行スクリプトの使い方**

### **6.5.1 run_xmrig_noise.sh**

- パス：k8s/xmrig-noise/scripts/run_xmrig_noise.sh
- 役割：
    - Tetragon の JSONL 監視を開始（dataset/raw/...jsonl へ出力）。
    - kubectl apply -f - で Job を動的生成し、環境変数を埋め込む。
    - XMRig ログから "benchmark finished" を検知したら監視を停止し、JSONL を確定。
- 主要引数例：
    - -bench=1M → BENCH_ARGS=--bench=1M
    - -noise_enable=1、--noise_rate=1000
    - -ldpreload=1（1 で LD_PRELOAD=/opt/libnoise.so を Job に注入）
    - -outfile=exp1（出力ファイル名に反映）
- 出力先：
    - dataset/raw/xmrig-noise-<outfile>-<UTC時刻>.jsonl

### **6.5.2 典型的な起動コマンド**

```
k8s/xmrig-noise/scripts/run_xmrig_noise.sh \
  --bench=1M \
  --noise_enable=1 \
  --noise_rate=1000 \
  --ldpreload=1 \
  --outfile=exp1
```

- 実験ログでは主に getpid と nanosleep 系の syscall が多数観測される。
- ノイズ無効で比較したい場合は --ldpreload=0 または --noise_enable=0 を指定。

## **6.6 トレースポリシーとラベル**

### **6.6.1 ポリシーファイル**

- k8s/xmrig-noise/xmrig-noise-policy.yaml
    - Tetragon の TracingPolicyNamespaced を使用。
    - podSelector.matchLabels.app: xmrig-noise を前提に、対象 Pod を限定。
    - raw_syscalls/sys_exit をフックし、引数（syscall）を抽出して JSONL に出力しやすくしている。

### **6.6.2 Job 側のラベル付与**

- run_xmrig_noise.sh は Job の Pod に labels.app: xmrig-noise を付与する。
- ポリシーの podSelector と一致していることがトレース取得の前提条件。

## **6.7 実験時の注意点とチューニング**

- busy モードは CPU を強く占有するため、XMRig 本体の性能やテストの再現性に影響しうる。まずは NOISE_RATE_HZ=1000 など適度な値から開始する。
- 制御はすべて環境変数で行い、コンテナ再ビルドなしで条件変更できる。
- K8s の resources（requests/limits）を併用してホスト影響度を明確化するのが望ましい。
- 番号はアーキ依存なので、集計や解析時は「番号→名称」マップを環境に合わせて用意すると読みやすい。
- ノイズを切れば、XMRig ベンチ自体はユーザ空間中心の処理で syscall が大幅に減ることが多い。比較実験の対照として使える。




# **第7章 運用ノートとトラブルシュート（重要）**

## **7.1 収集基盤の前提チェック**

### **7.1.1 Tetragon の稼働確認**

- DaemonSet の存在とログ出力用コンテナを確認する。

```
kubectl -n kube-system get ds tetragon -o wide
kubectl -n kube-system get pods -l k8s-app=tetragon
kubectl -n kube-system logs ds/tetragon -c export-stdout --tail=20
```

- values-tetragon.yaml で export-stdout が有効になっていることを前提に、以降の収集は ds/tetragon -c export-stdout をログ源として使用する。

### **7.1.2 ポリシーの対象と Pod ラベル整合**

- k8s/xmrig-noise/xmrig-noise-policy.yaml は podSelector.matchLabels.app: xmrig-noise を対象にしているため、Job の Pod に **必ず** app: xmrig-noise ラベルを付与する。
- 例（Job テンプレートにラベルを付与）:

```
template:
  metadata:
    labels:
      app: xmrig-noise
  spec:
    containers:
    - name: xmrig-noise
      ...
```

- ラベル不一致だと Tetragon のフィルタに引っかからず、JSONL が空になる。

## **7.2 Minikube でのイメージ更新と検証**

### **7.2.1 既存イメージの削除と再ロード**

- Minikube 内の古いローカルイメージを削除してから再ロードする。

```
# Minikube の中の Docker から削除
minikube ssh -- docker images | grep xmrig-noise
minikube ssh -- docker rmi -f xmrig-noise:latest || true

# ホスト側のビルド → Minikube へロード
docker build --network=host -f k8s/xmrig-noise/images/Dockerfile \
  -t xmrig-noise:latest k8s/xmrig-noise/images
minikube image load xmrig-noise:latest
```

### **7.2.2 Digest の目視比較**

```
# ホスト
docker images --digests | grep xmrig-noise

# Minikube 内
minikube ssh -- docker images --digests | grep xmrig-noise
```

Digest が一致していれば、クラスター側に最新が反映されている。

## **7.3 Job/Pod 実行とログ追従の安定化**

### **7.3.1 Pod 検出とログ準備の待機**

- ContainerCreating 中に kubectl logs を叩くと BadRequest になる。以下のように待機を入れる。

```
# Pod 名前の検出（job-name=... ラベルで最初の1つ）
POD=$(kubectl -n xmrig-noise get pods -l job-name=xmrig-noise \
  -o jsonpath='{.items[0].metadata.name}')

# ログが読めるまで待つ
until kubectl -n xmrig-noise logs "$POD" >/dev/null 2>&1; do sleep 1; done
```

### **7.3.2 ベンチ完了の検知と rc=141**

- kubectl logs -f ... | grep -m1 "benchmark finished" は、1行ヒット後に grep が先に終了し、上流の kubectl logs が SIGPIPE を受けて終了コード 141 になることがある。これは異常ではない（検知成功の典型動作）。
- パイプエラーでスクリプト全体が止まらないよう、検知部分は set +o pipefail で覆う。

### **7.3.3 監視プロセスの安全な停止**

- 収集パイプライン（tetragon → jq → jsonl）は setsid で独立プロセスグループとして起動し、終了時は PGID に対して TERM→KILL を送ると漏れがない。

```
# 起動例
setsid bash -c 'kubectl ... -f | jq ... > outfile.jsonl' &
PG_LEADER=$!; PGID=$(ps -o pgid= $PG_LEADER | tr -d ' ')

# 終了例
kill -TERM "-$PGID" 2>/dev/null || true
sleep 1
kill -KILL "-$PGID" 2>/dev/null || true
```

## **7.4 Tetragon → JSONL の取り扱い**

### **7.4.1 収集用 jq フィルタ（本リポジトリの基準）**

- Namespace で絞り、プロセストレースポイントから syscall を抽出。

```
select(.process_tracepoint? and .process_tracepoint.process.pod.namespace=="xmrig-noise") |
{
  ts: (.time // .process_tracepoint.time // .ts),
  pid: (.process_tracepoint.process.pid // .process.pid),
  pod: (.process_tracepoint.process.pod.name // .pod // ""),
  container: (.process_tracepoint.process.container.name // .container // ""),
  sc: ((.process_tracepoint.args[0].long_arg
        // .process_tracepoint.args[0].int64_arg
        // .process_tracepoint.args[0].size_arg
        // .process_tracepoint.args[0].int_arg
        // .sc // .nr // .syscall // .id) | tonumber?),
  wl: "xmrig-noise",
  tid: (.process_tracepoint.process.tid // .process.tid)
}
| select(.sc != null)
```

- 実運用では --since=1s を付けて直近のみを追うと、過去ログの洪水を避けやすい。

### **7.4.2 イベントが少ない/ゼロのとき**

- LD_PRELOAD=0（ノイズ無し）で XMRig のような CPU バウンド処理はシステムコールが極端に少ないのが通常。NOISE_ENABLE=1 と NOISE_RATE_HZ を上げると getpid(2) と nanosleep(2) が増える。
- ポリシーの podSelector ラベル不一致や Namespace ミスでも 0 行になる。ラベルと NS を最優先で確認。

## **7.5 JSONL の検証と要約コマンド**

### **7.5.1 基本の健全性チェック**

```
wc -l dataset/raw/<file>.jsonl
head -n 3 dataset/raw/<file>.jsonl
tail -n 3 dataset/raw/<file>.jsonl
```

### **7.5.2 末尾の不完全行による jq エラー対策**

- ログ切断などで最終行が未完の場合、jq: parse error: Unfinished string at EOF が出る。
- 一時的な回避（未完の最終行を落とす）:

```
head -n -1 dataset/raw/<file>.jsonl > /tmp/fixed.jsonl && mv /tmp/fixed.jsonl dataset/raw/<file>.jsonl
```

### **7.5.3 システムコール頻度の要約**

```
# .sc を集計（多い順）
jq -r '.sc' dataset/raw/<file>.jsonl | sort -n | uniq -c | sort -nr | head

# 具体的な syscalls 例（Linux x86_64/arm64 共通の代表）
# 115=nanosleep, 172=getpid など（実際の番号はアーキによって差異あり）
```

## **7.6 リソースとスループットの注意**

### **7.6.1 requests/limits の指定**

- 例（2 vCPU 固定、メモリ 4Gi）:

```
resources:
  requests:
    cpu: "2"
    memory: "4Gi"
  limits:
    cpu: "2"
    memory: "4Gi"
```

- NOISE_RATE_HZ=0（busy）や高レート指定は CPU 占有が強くなる。ベンチ結果や収集間引きに影響するため、ワークロードと監視負荷のバランスを確認。

## **7.7 よくある症状と対処**

- 症状: kubectl logs が BadRequest（ContainerCreating）
    
    対処: ログ準備の待機ループを挟む（7.3.1）。
    
- 症状: ベンチが動いているのに JSONL が 0 行
    
    対処: ラベル/NS の整合を確認（7.1.2）。LD_PRELOAD と NOISE_ENABLE の値も再確認。
    
- 症状: unsupported non-option argument '1M'
    
    対処: XMRig には BENCH_ARGS=--bench=1M の形で渡す（単なる 1M は不可）。
    
- 症状: Minikube 側に古いイメージが残る
    
    対処: minikube ssh -- docker rmi -f xmrig-noise:latest → minikube image load ...（7.2.1）。
    
- 症状: grep の終了コード 141
    
    対処: 正常。検知専用パイプでは set +o pipefail を使い、モニタは PGID に対して TERM/KILL で落とす（7.3.2–7.3.3）。
    
- 症状: jq がパースエラー
    
    対処: 末尾未完行の削除（7.5.2）。以後はファイルを追記しない前提で解析する。
