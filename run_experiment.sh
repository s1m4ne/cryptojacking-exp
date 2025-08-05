#!/bin/bash

# --- 設定項目 ---
# このスクリプトで使う変数（実験ごとにここだけ変更すれば良い）
IMAGE_NAME="my-spoofed-xmrig"
IMAGE_TAG="v1"
DEPLOYMENT_YAML="k8s/xmrig-spoofed-deploy.yaml"
DEPLOYMENT_NAME="xmrig-spoofed"
NAMESPACE="xmrig"
SOURCE_DIR="src/xmrig"

# スクリプトがエラーになったら、その時点で処理を中断する設定
set -e

# --- ここから自動化プロセス ---

echo "--- [STEP 1/5] Deleting old Deployment... ---"
# --ignore-not-found=true を付けることで、初回実行時などにリソースが存在しなくてもエラーにならない
kubectl delete deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE} --ignore-not-found=true

echo "\n--- [STEP 2/5] Building new Docker image: ${IMAGE_NAME}:${IMAGE_TAG} ---"
# XMRigのソースコードディレクトリに移動してビルド
(cd ${SOURCE_DIR} && docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .)

echo "\n--- [STEP 3/5] Loading image into Minikube... ---"
minikube image load ${IMAGE_NAME}:${IMAGE_TAG}

echo "\n--- [STEP 4/5] Applying new Deployment... ---"
kubectl apply -f ${DEPLOYMENT_YAML}

echo "\n--- [STEP 5/5] Waiting for Deployment to be ready... ---"
# rollout status で、デプロイが完了するのを待機する
kubectl rollout status deployment/${DEPLOYMENT_NAME} -n ${NAMESPACE}

echo "\n✅ All steps completed successfully!"
echo "You can now start monitoring the pod in namespace '${NAMESPACE}'."
