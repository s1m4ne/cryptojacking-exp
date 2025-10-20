#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# eval-noise.py
# 悪性=正例の二値評価（Precision / Recall / F1 / FPR + 混同行列）を、固定モデル群に対して一括実行。
# データセットは --label で指定し、各モデルの n に合わせて
#   dataset/npy/merged/<label>-<n>gram
# を自動参照する。標準出力の [START]/[DONE]/[SAVED] などの体裁は現行に極力合わせる。

from pathlib import Path
import argparse
import json
import re
import numpy as np
import joblib
from sklearn.metrics import precision_recall_fscore_support, confusion_matrix
from datetime import datetime
from zoneinfo import ZoneInfo

JST = ZoneInfo("Asia/Tokyo")

# モデル⇔n（モデルは固定 / data_path は実行時に label から組み立て）
MODELS = [
    {"name": "rnn_40", "kind": "keras",   "model_path": "models/lstm.model.keras",  "n": 40},
    {"name": "dt_35",  "kind": "sklearn", "model_path": "models/dt_35.joblib",      "n": 35},
    {"name": "svm_50", "kind": "sklearn", "model_path": "models/svm_50_all.joblib", "n": 50},
    {"name": "mlp_10", "kind": "sklearn", "model_path": "models/mlp_10.joblib",     "n": 10},
    {"name": "knn_5",  "kind": "sklearn", "model_path": "models/knn_5.joblib",      "n": 5},
]

DATA_ROOT = "dataset/npy/merged"  # 変更しない（最小変更方針）

def now_jst_str():
    return datetime.now(JST).strftime("%Y-%m-%d %H:%M:%S %Z")

def now_jst_iso():
    return datetime.now(JST).isoformat()

def parse_args():
    ap = argparse.ArgumentParser(description="Binary eval (malicious vs non-malicious) for fixed models on a labeled dataset")
    ap.add_argument("--label", required=True, help="dataset label (e.g., 15m-40pct)")
    return ap.parse_args()

def build_data_path(label: str, n: int) -> Path:
    # <DATA_ROOT>/<label>-<n>gram
    return Path(DATA_ROOT) / f"{label}-{n}gram"

def load_test(merged_dir: Path):
    meta = json.load(open(merged_dir / "meta.json"))
    X = np.load(merged_dir / "test" / "X.npy", mmap_mode="r", allow_pickle=False)
    y = np.load(merged_dir / "test" / "y.npy", allow_pickle=False)
    assert X.shape[1] == meta["n"], f"n mismatch: X.shape[1]={X.shape[1]} vs meta.n={meta['n']}"
    return X, y, meta

def eval_sklearn(model_path: Path, X):
    clf = joblib.load(model_path)
    y_pred = clf.predict(X)
    return y_pred

def eval_keras(model_path: Path, X):
    import tensorflow as tf
    X = np.asarray(X, dtype="int32")  # RNNのEmbedding前提でint32に
    model = tf.keras.models.load_model(model_path)
    y_prob = model.predict(X, verbose=0)
    y_pred = y_prob.argmax(axis=1)
    return y_pred

def find_malicious_id(label_map: dict) -> tuple[int, str]:
    """
    label_map から悪性ラベルの id を推定する。
    優先順位: キーに 'xmrig' / 'xmr' / 'noise' / 'malicious' / 'mining'
    該当なしなら ValueError
    """
    patterns = ["xmrig", "xmr", "noise", "malicious", "mining"]
    # まずキーで探す
    for k, v in label_map.items():
        lk = k.lower()
        if any(p in lk for p in patterns):
            return int(v), k
    # 次に逆引き（値→キー）でもう一度（保険）
    inv = {int(v): k for k, v in label_map.items()}
    for vid, k in inv.items():
        lk = k.lower()
        if any(p in lk for p in patterns):
            return vid, k
    raise ValueError("malicious_id not found in label_map")

def bin_metrics(y_true_bin: np.ndarray, y_pred_bin: np.ndarray):
    # confusion matrix
    tn, fp, fn, tp = confusion_matrix(y_true_bin, y_pred_bin, labels=[0,1]).ravel()
    # P/R/F1（ゼロ割は0扱い）
    p, r, f1, _ = precision_recall_fscore_support(
        y_true_bin, y_pred_bin, average="binary", zero_division=0
    )
    # FPR
    fpr = fp / (fp + tn) if (fp + tn) > 0 else 0.0
    return {
        "precision": float(p),
        "recall": float(r),     # = TPR
        "f1": float(f1),
        "fpr": float(fpr),
        "tp": int(tp), "fp": int(fp), "fn": int(fn), "tn": int(tn),
        "support_pos": int(tp + fn),
        "support_neg": int(tn + fp),
    }

def main():
    args = parse_args()
    label = args.label

    all_results = []
    start_all = now_jst_str()
    print(f"[START] {start_all}  eval {len(MODELS)} models")

    for m in MODELS:
        name = m["name"]; kind = m["kind"]
        model_path = Path(m["model_path"])
        data_path  = build_data_path(label, int(m["n"]))
        try:
            X, y, meta = load_test(data_path)
            # 悪性=正例の id を決める
            mal_id, mal_key = find_malicious_id(meta.get("label_map", {}))

            start = now_jst_str()
            print(f"[START] {start}  {name}  (n={meta['n']}, test_N={len(y)})")

            if kind == "sklearn":
                y_pred = eval_sklearn(model_path, X)
            elif kind == "keras":
                y_pred = eval_keras(model_path, X)
            else:
                raise ValueError(f"unknown kind: {kind}")

            # 二値化
            y_true_bin = (y == mal_id).astype(int)
            y_pred_bin = (y_pred == mal_id).astype(int)

            bm = bin_metrics(y_true_bin, y_pred_bin)

            done = now_jst_str()
            print(f"[DONE ] {done}  {name}")
            print(f"[BINARY] {name}  P={bm['precision']:.4f}  R={bm['recall']:.4f}  F1={bm['f1']:.4f}  FPR={bm['fpr']:.4f}  TP={bm['tp']} FP={bm['fp']} FN={bm['fn']} TN={bm['tn']}")

            all_results.append({
                "name": name,
                "kind": kind,
                "model_path": str(model_path),
                "data_path": str(data_path),
                "label": label,
                "n": meta["n"],
                "test_N": int(len(y)),
                "started_at": start,
                "finished_at": done,
                "binary_metrics": {
                    "positive_class": mal_key,
                    "positive_id": int(mal_id),
                    "threshold": "argmax",
                    "precision": bm["precision"],
                    "recall": bm["recall"],
                    "f1": bm["f1"],
                    "fpr": bm["fpr"],
                    "support_pos": bm["support_pos"],
                    "support_neg": bm["support_neg"],
                },
                "confusion_matrix": {
                    "tp": bm["tp"], "fp": bm["fp"], "fn": bm["fn"], "tn": bm["tn"]
                }
            })
        except Exception as e:
            err = f"{type(e).__name__}: {e}"
            print(f"[ERROR] {name}: {err}")
            all_results.append({
                "name": name, "kind": kind,
                "model_path": str(model_path), "data_path": str(data_path),
                "label": label,
                "error": err, "started_at": now_jst_str(), "finished_at": now_jst_str()
            })

    out_dir = Path("eval")
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{label}-results.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"started_at": start_all, "finished_at": now_jst_str(),
                   "label": label, "data_root": DATA_ROOT, "results": all_results}, f, indent=2)
    print(f"[SAVED] {out}")

if __name__ == "__main__":
    main()
