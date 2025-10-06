# syntax=docker/dockerfile:1

# ===== build stage =====
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git build-essential cmake \
    libuv1-dev libssl-dev libhwloc-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
# XMRig を安定版タグで取得
RUN git clone --branch v6.24.0 https://github.com/xmrig/xmrig.git .

# CPUビルド（OpenCL/CUDA無効）
RUN cmake -S . -B build \
      -DWITH_OPENCL=OFF -DWITH_CUDA=OFF -DWITH_HWLOC=ON \
      -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j"$(nproc)"

# noise.c（この Dockerfile と同じディレクトリ）から libnoise.so をビルド
COPY noise.c /src/noise.c
RUN gcc -O2 -fPIC -Wall -Wextra -fno-omit-frame-pointer -D_GNU_SOURCE \
      -shared -pthread /src/noise.c -o /src/libnoise.so

# ===== runtime stage =====
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 実行に必要な最小ランタイム
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates libuv1 libssl3 libhwloc15 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /work

# バイナリとノイズSOを配置（※有効化は起動時に LD_PRELOAD で）
COPY --from=builder /src/build/xmrig /usr/local/bin/xmrig
COPY --from=builder /src/libnoise.so /opt/libnoise.so

# entrypoint.sh を配置
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# エントリーポイントを xmrig から entrypoint.sh に変更
ENTRYPOINT ["/entrypoint.sh"]
