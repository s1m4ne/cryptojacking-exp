FROM alpine:latest as builder

RUN apk add --no-cache alpine-sdk cmake git libuv-dev openssl-dev hwloc-dev

WORKDIR /app

COPY . .

RUN mkdir build && \
    cd build && \
    cmake .. -DWITH_OPENCL=OFF -DWITH_CUDA=OFF && \
    make -j$(nproc)
FROM alpine:latest
RUN apk add --no-cache libuv libcrypto3 libssl3 hwloc

WORKDIR /app

COPY --from=builder /app/build/xmrig .

RUN chmod +x xmrig

ENTRYPOINT ["/app/xmrig"]
