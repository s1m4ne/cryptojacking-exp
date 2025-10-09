# syntax=docker/dockerfile:1

# ===== build stage =====
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git build-essential cmake \
    libuv1-dev libssl-dev libhwloc-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --branch v6.24.0 https://github.com/xmrig/xmrig.git .

RUN cmake -S . -B build \
      -DWITH_OPENCL=OFF -DWITH_CUDA=OFF -DWITH_HWLOC=ON \
      -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j"$(nproc)"

COPY noise.c /src/noise.c
RUN gcc -O2 -fPIC -Wall -Wextra -fno-omit-frame-pointer -D_GNU_SOURCE \
      -shared -pthread /src/noise.c -o /src/libnoise.so

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates libuv1 libssl3 libhwloc15 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /work

COPY --from=builder /src/build/xmrig /usr/local/bin/xmrig
COPY --from=builder /src/libnoise.so /opt/libnoise.so

ENTRYPOINT ["/usr/local/bin/xmrig"]
