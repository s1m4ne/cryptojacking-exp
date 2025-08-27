# **Cryptojacking Experiment Benchmarks**

  

Kubernetes 上で複数のワークロード（正常系・異常系）を動作させ、Tetragon によるシステムコール監視でデータセットを生成・解析するための構成とスクリプトをまとめたリポジトリです。生成データは機械学習（n-gram 特徴量、RNN など）に利用できます。

---

## **実験目的**

- CloudSuite ベースを含む複数ワークロードの再現（media-streaming / web-serving / data-caching / database / xmrig）
    
- 正常系・異常系（cryptojacking）のシステムコールトレース収集（JSONL）
    
- 収集データの前処理・特徴量化と学習用フォーマット化
    

---

## **リポジトリ構成（現状）**

```
cryptojacking-exp/
├── analyzer/                # 解析スクリプト
│   └── 5gram_analyzer.py
├── cache/                   # 特徴量キャッシュ（npy 等）※Git管理外推奨
│   └── n40_overlap/...
├── config/                  # 実行設定（秘密情報は置かない／追跡しない）
├── dataroot/                # 実験用のルート（必要に応じてマウント先等）
├── dataset/                 # 生成データ（raw/tmp/metadata/syscalls）※Git管理外
│   ├── raw/                 # 各ワークロードのJSONL
│   ├── tmp/                 # 全期間の一時ファイル
│   ├── metadata/            # 実験メタ情報
│   └── syscalls/            # 整形済みシステムコール系列
├── features/                # 特徴量生成・分割・学習
│   ├── make_ngrams_npy.py
│   ├── split_dataset.py
│   └── train_rnn.py
├── k8s/                     # 各ワークロードのK8sマニフェストと実行スクリプト
│   ├── data-caching/        # policy / step1-2 / run_*.sh
│   ├── database/            # policy / db.yaml / run_*.sh
│   ├── media-streaming/     # pv/pvc/step1-3 / run_*.sh
│   ├── web-serving/         # step1-4 / run_*.sh / policy
│   └── xmrig/               # 通常版・偽装版のデプロイ/ポリシー/実行
├── logs/                    # 実行ログ（Git管理外）
├── values-tetragon.yaml     # Tetragon の Helm values 等
└── wwwroot/                 # 静的ファイル（必要に応じて）
```

> メモ: .gitignore により dataset/, cache/, logs/, config/, config.backup*/, wallet/, venv/.venv/env/, __pycache__/ は **Git管理外**（ローカルのみ保持）です。

---

## **主要ワークロード**

- **Media Streaming**
    
    CloudSuite の dataset/server/client で配信負荷を再現。k8s/media-streaming/run_media_streaming_capture.sh がトレースと実行を統合。
    
- **Web Serving**
    
    DB + Memcached + Web + Faban Client の構成でスループットを測定。
    
- **Data Caching**
    
    Memcached サーバとクライアントでキャッシュ性能を測定。
    
- **Database**
    
    MariaDB + Sysbench で読み書き性能を測定。
    
- **XMRig (Cryptojacking)**
    
    通常版／偽装版を含むマイニングワークロードで、攻撃系のシステムコールパターンを収集。
    
    ※ ウォレット等の機密は config/ に置かず、環境変数や外部 Secret を利用してください。
    

---

## **実行例（Media Streaming）**

```
# 1) データセット展開（PV/PVC）
kubectl apply -f k8s/media-streaming/pv.yaml
kubectl apply -f k8s/media-streaming/pvc.yaml
kubectl apply -f k8s/media-streaming/step1-dataset.yaml

# 2) サーバ起動
kubectl apply -f k8s/media-streaming/step2-server.yaml

# 3) クライアント起動
kubectl apply -f k8s/media-streaming/step3-client.yaml

# 4) トレース＆ベンチ実行（Tetragon 前提）
bash k8s/media-streaming/run_media_streaming_capture.sh
```

他ワークロードも各ディレクトリの run_*_capture.sh を参照してください。

---

## **生成データと学習**

```
# n-gram 特徴量生成（例）
python features/make_ngrams_npy.py

# データセット分割
python features/split_dataset.py

# RNN の学習
python features/train_rnn.py
```

- 生成された .npy や学習済みモデルは cache/ 等に保存され、Git には含めません。
    
- analyzer/5gram_analyzer.py で簡易解析が可能です。
    

---

## **セキュリティと公開ポリシー**

- 機密情報（ウォレット・認証情報・個人データ）は **コミット禁止**。必要なら Kubernetes Secret / 環境変数を使用。
    
- 大容量の生成物やログは **ローカル専用**（.gitignore 済み）。
    
- 公開環境でのマイニングは規約・法令違反の可能性があり、自己管理下の環境でのみ実行してください。
    

---

## **補足（.gitignore による管理外パス）**

```
# 仮想環境 / キャッシュ
venv/ .venv/ env/ __pycache__/

# 生成物・ログ・機密
dataset/ cache/ logs/ wallet/ config/ config.backup*/
```

必要に応じて !<path> で個別に公開したいファイル（例: dataset/README.md）だけ除外解除できます。
