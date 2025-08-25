#!/usr/bin/env python3
import numpy as np
import argparse
import os
from sklearn.model_selection import train_test_split

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--indir", default="cache/n40_overlap", help="入力ディレクトリ")
    parser.add_argument("--outdir", default="cache/n40_overlap", help="出力ディレクトリ")
    parser.add_argument("--test_size", type=float, default=0.30, help="test 割合 (デフォルト 0.3)")
    parser.add_argument("--val_size", type=float, default=0.14, help="val 割合 (train からの割合)")
    parser.add_argument("--seed", type=int, default=42, help="乱数シード")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    X = np.load(os.path.join(args.indir, "X_n40.npy"))
    Y = np.load(os.path.join(args.indir, "Y_n40.npy"))

    print(f"[INFO] Loaded: X={X.shape}, Y={Y.shape}")

    # train+val / test に分割
    X_trainval, X_test, Y_trainval, Y_test = train_test_split(
        X, Y, test_size=args.test_size, random_state=args.seed, stratify=Y
    )

    # train / val に分割
    val_ratio = args.val_size / (1 - args.test_size)
    X_train, X_val, Y_train, Y_val = train_test_split(
        X_trainval, Y_trainval, test_size=val_ratio, random_state=args.seed, stratify=Y_trainval
    )

    # 保存
    np.save(os.path.join(args.outdir, "X_train.npy"), X_train)
    np.save(os.path.join(args.outdir, "Y_train.npy"), Y_train)
    np.save(os.path.join(args.outdir, "X_val.npy"), X_val)
    np.save(os.path.join(args.outdir, "Y_val.npy"), Y_val)
    np.save(os.path.join(args.outdir, "X_test.npy"), X_test)
    np.save(os.path.join(args.outdir, "Y_test.npy"), Y_test)

    print(f"[INFO] Saved splits -> {args.outdir}")
    print(f" train: {X_train.shape}, val: {X_val.shape}, test: {X_test.shape}")

if __name__ == "__main__":
    main()
