// noise.c — 最小ノイズ挿入ライブラリ（LD_PRELOAD用）
// 仕様：
//   - NOISE_ENABLE: 0で完全無効（既定=1）
//   - NOISE_RATE_HZ: 1秒あたりの発行回数（既定=1000）
//       =0 のときは busy（sleepなしで連打）
// ループ内のsyscallは getpid と（必要時の）nanosleep のみ。

#define _GNU_SOURCE
#include <pthread.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <time.h>
#include <stdlib.h>

static int read_env_int(const char *name, int defval) {
    const char *s = getenv(name);
    if (!s || !*s) return defval;
    char *end = NULL;
    long v = strtol(s, &end, 10);
    if (end == s) return defval;            // 変換不可 → 既定
    if (v < 0) v = 0;                       // 負値は0に丸め（=busy）
    if (v > 1000000000L) v = 1000000000L;   // 物理限界でクランプ
    return (int)v;
}

static void* noise_thread(void *arg) {
    (void)arg;

    const int rate_hz = read_env_int("NOISE_RATE_HZ", 1000);

    if (rate_hz == 0) {
        // busy: sleepを呼ばずにsyscallを連打（最悪ケース）
        for (;;) {
            syscall(SYS_getpid);
        }
    } else {
        // sleepあり: 周期 = 1e9 / rate_hz [ns]
        long long ns = 1000000000LL / rate_hz;
        if (ns <= 0) ns = 1; // 高すぎるレートを最小1nsに
        struct timespec ts;
        ts.tv_sec  = (time_t)(ns / 1000000000LL);
        ts.tv_nsec = (long)(ns % 1000000000LL);

        for (;;) {
            syscall(SYS_getpid);
            // EINTR時の残り時間再計算などは行わず、最小実装とする
            nanosleep(&ts, NULL);
        }
    }
    return NULL;
}

__attribute__((constructor))
static void noise_ctor(void) {
    int enable = read_env_int("NOISE_ENABLE", 1);
    if (!enable) return;

    pthread_t tid;
    if (pthread_create(&tid, NULL, noise_thread, NULL) == 0) {
        pthread_detach(tid);
    }
    // 失敗時は静かに無視（副作用最小化）
}
