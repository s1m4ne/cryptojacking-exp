# features/train-knn.py
from pathlib import Path
import argparse, json, numpy as np, joblib
from sklearn.neighbors import KNeighborsClassifier
from sklearn.metrics import accuracy_score, classification_report

def load_split(base: Path, split: str):
    X = np.load(base/split/"X.npy", allow_pickle=False)   # shape [N, n]
    y = np.load(base/split/"y.npy", allow_pickle=False)   # labels (0..4想定)
    assert X.shape[0] == y.shape[0], f"size mismatch in {split}"
    return X, y

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--merged", default="dataset/npy/merged/five-5gram",
                    help="使用する merged ディレクトリ（five-5gram など）")
    ap.add_argument("--out", default="", help="保存先（未指定なら n を読み models/knn_<n>.joblib）")
    args = ap.parse_args()

    base = Path(args.merged)
    meta = json.load(open(base/"meta.json"))
    n = int(meta["n"]); n_classes = len(meta["label_map"])
    print(f"[INFO] base={base}  n={n}  classes={n_classes}")

    Xtr, ytr = load_split(base, "train")
    Xva, yva = load_split(base, "val")
    Xte, yte = load_split(base, "test")

    # --- KNN (論文準拠): k=5, uniform, Minkowski(p=2)=Euclidean ---
    knn = KNeighborsClassifier(n_neighbors=5, weights="uniform", metric="minkowski", p=2)
    knn.fit(Xtr, ytr)

    for name, X, y in [("val", Xva, yva), ("test", Xte, yte)]:
        pred = knn.predict(X)
        print(f"[{name.upper()}] acc={accuracy_score(y, pred):.4f}")
    print("\n[TEST] classification report:")
    print(classification_report(yte, knn.predict(Xte), digits=4))

    out = Path(args.out) if args.out else Path(f"models/knn_{n}.joblib")
    out.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(knn, out)
    print("Saved:", out)

if __name__ == "__main__":
    main()
