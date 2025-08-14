# Cryptojacking Experiment Benchmarks

このリポジトリは、Kubernetes 上で複数のワークロード（正常系・異常系）を動作させ、
Tetragon によるシステムコール監視を行い、データセットを生成するための構成とスクリプトをまとめたものです。

### 実験目的
- 各種ベンチマークワークロードを再現（CloudSuite ベースのものを含む）
- 正常系ワークロード（例: media-streaming, web-serving, data-caching, database）
- 異常系ワークロード（例: xmrig マイニング、spoofed バージョン）
- システムコールトレースを JSONL として収集
- 生成データを機械学習・検知モデルに利用可能な形式で保存

### ディレクトリ構成
```
cryptojacking-exp/
├── dataset/                # 実行後に生成されるデータセット
│   ├── raw/                 # ベンチ区間のみの JSONL
│   ├── tmp/                 # 全監視期間の一時ファイル
│   └── metadata/            # 実験メタ情報(JSON)
├── logs/                   # 実行時ログ（クライアント/サーバ別）
├── k8s/
│   ├── media-streaming/     # CloudSuite Media Streaming ベンチ用マニフェスト
│   ├── web-serving/         # Web Serving ベンチ用マニフェスト
│   ├── data-caching/        # Data Caching ベンチ用マニフェスト
│   ├── database/            # MariaDB + Sysbench ベンチ用マニフェスト
│   └── xmrig/               # XMRig マイニング（spoofed含む）
├── analyzer/               # データ解析用スクリプト
└── wwwroot/                # Web 静的ファイル（必要に応じて）
```

### ワークロード概要

1. Media Streaming
- 元イメージ: cloudsuite/media-streaming:dataset + cloudsuite/media-streaming:server + client
- 目的: 動画配信サーバの負荷生成とアクセスパターン収集
- run_media_streaming_capture.sh によりトレーシング & ベンチ実行

3. Web Serving
- 構成: DB + Memcached + Web + Faban Client
- 目的: Web サービスのスループット測定

5. Data Caching
- 構成: Memcached Server + Client
- 目的: キャッシュシステムの負荷試験

6. Database
- 構成: MariaDB Server + Sysbench Client
- 目的: データベースの読み書き性能測定

8. XMRig (Cryptojacking)
- 構成: XMRig マイニングコンテナ（通常版・偽装版）
- 目的: 悪意あるワークロードのシステムコールパターン収集
- 注意: ウォレット情報は config/ ディレクトリに置き、.gitignore 済み（Git追跡禁止）


### 実行の流れ（例: media-streaming）
1.	Namespace 作成 & データセット展開
```
kubectl apply -f k8s/media-streaming/pv.yaml
kubectl apply -f k8s/media-streaming/pvc.yaml
kubectl apply -f k8s/media-streaming/step1-dataset.yaml
```

2.	サーバ起動
```
kubectl apply -f k8s/media-streaming/step2-server.yaml
```

3.	クライアント起動
```
kubectl apply -f k8s/media-streaming/step3-client.yaml
```

4.	トレーシング & ベンチ実行
```
bash k8s/media-streaming/run_media_streaming_capture.sh
```

### セキュリティ上の注意
- config/ 以下のウォレットや秘密情報は Git 管理外
- 過去の履歴からも削除済み（git-filter-repo 利用）
- 公開環境でマイニングを行う場合、利用規約違反・法的リスクがあるため必ず自己管理環境で実行


### 参考
- CloudSuite Official
- MariaDB
- Sysbench
- Tetragon
