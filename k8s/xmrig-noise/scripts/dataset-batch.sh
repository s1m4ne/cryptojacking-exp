#!/usr/bin/env bash

kubectl delete ns xmrig-noise
kubectl wait --for=delete ns/xmrig-noise --timeout=180s || true

k8s/xmrig-noise/scripts/run-collect.sh \
  --duration=300 --label=test-800hz \
  --noise_enable=1 --ldpreload=1 --noise_rate=800

kubectl delete ns xmrig-noise
kubectl wait --for=delete ns/xmrig-noise --timeout=180s || true

k8s/xmrig-noise/scripts/run-collect.sh \
  --duration=300 --label=test-1500hz \
  --noise_enable=1 --ldpreload=1 --noise_rate=1500

kubectl delete ns xmrig-noise
kubectl wait --for=delete ns/xmrig-noise --timeout=180s || true

k8s/xmrig-noise/scripts/run-collect.sh \
  --duration=300 --label=test-2000hz \
  --noise_enable=1 --ldpreload=1 --noise_rate=2000

