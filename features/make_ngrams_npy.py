#!/usr/bin/env python3
import numpy as np
import argparse
import os

def make_ngrams(seq, n):
    """与えられた整数シーケンスから n-gram を生成"""
    X = []
    for i in range(len(seq) - n + 1):
        X.append(seq[i:i+n])
    return np.array(X, dtype=np.int32)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+", help="syscall番号だけのファイル(.sc)")
    parser.add_argument("--n", type=int, default=40, help="n-gramサイズ (デフォルト=40)")
    parser.add_argument("--outdir", default="cache/n40_overlap", help="出力ディレクトリ")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    all_X, all_Y = [], []

    for f in args.files:
        with open(f) as fin:
            seq = [int(line.strip()) for line in fin if line.strip()]
        X = make_ngrams(seq, args.n)

        # ファイル名からラベルを決定
        if "xmrig" in os.path.basename(f):
            Y = np.ones(len(X), dtype=np.int64)
        else:
            Y = np.zeros(len(X), dtype=np.int64)

        all_X.append(X)
        all_Y.append(Y)

        print(f"[OK] {f}: {len(X)} samples")

    X_all = np.vstack(all_X)
    Y_all = np.concatenate(all_Y)

    np.save(os.path.join(args.outdir, f"X_n{args.n}.npy"), X_all)
    np.save(os.path.join(args.outdir, f"Y_n{args.n}.npy"), Y_all)

    print(f"\nSaved: {X_all.shape} -> X_n{args.n}.npy")
    print(f"       {Y_all.shape} -> Y_n{args.n}.npy")

if __name__ == "__main__":
    main()

