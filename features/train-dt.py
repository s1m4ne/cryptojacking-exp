# features/train-dt.py
from pathlib import Path
import argparse, json, numpy as np
from sklearn.tree import DecisionTreeClassifier
from sklearn.metrics import accuracy_score, classification_report
import joblib
import os, random

SEED = 42
random.seed(SEED); np.random.seed(SEED)

def load_split(base: Path, split: str):
    X = np.load(base/split/"X.npy", allow_pickle=False)
    y = np.load(base/split/"y.npy", allow_pickle=False)
    assert X.shape[0] == y.shape[0], f"size mismatch in {split}"
    return X, y

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--merged", default="dataset/npy/merged/five-40gram",
                    help="使用する merged ディレクトリ（five-40gram or five-35gram）")
    ap.add_argument("--out", default="models/dt.joblib")
    args = ap.parse_args()

    base = Path(args.merged)
    meta = json.load(open(base/"meta.json"))
    print(f"[INFO] n={meta['n']} / classes={len(meta['label_map'])} / base={base}")

    Xtr, ytr = load_split(base, "train")
    Xva, yva = load_split(base, "val")
    Xte, yte = load_split(base, "test")

    # --- Decision Tree (論文準拠: Criterion=Gini, Splitter=Best, その他デフォルト) ---
    dt = DecisionTreeClassifier(criterion="gini", splitter="best", random_state=SEED)
    dt.fit(Xtr, ytr)

    # 検証＆テスト
    for name, X, y in [("val", Xva, yva), ("test", Xte, yte)]:
        pred = dt.predict(X)
        acc = accuracy_score(y, pred)
        print(f"[{name.upper()}] acc={acc:.4f}")
    print("\n[TEST] classification report:")
    print(classification_report(yte, dt.predict(Xte), digits=4))

    # 保存
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(dt, out)
    print("Saved:", out)

if __name__ == "__main__":
    main()
