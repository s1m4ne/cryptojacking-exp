# features/train-svm.py
from pathlib import Path
import argparse, json, numpy as np, joblib, random
from sklearn.svm import SVC
from sklearn.metrics import accuracy_score, classification_report

SEED = 42
random.seed(SEED); np.random.seed(SEED)

def load_split(base: Path, split: str):
    X = np.load(base/split/"X.npy", allow_pickle=False)   # shape [N, n]
    y = np.load(base/split/"y.npy", allow_pickle=False)   # labels 0..4
    assert X.shape[0] == y.shape[0], f"size mismatch in {split}"
    return X, y

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--merged", default="dataset/npy/merged/five-50gram",
                    help="使用する merged ディレクトリ（five-50gram 等）")
    ap.add_argument("--out", default="models/svm_50_all.joblib")
    args = ap.parse_args()

    base = Path(args.merged)
    meta = json.load(open(base/"meta.json"))
    n = meta["n"]; n_classes = len(meta["label_map"])
    print(f"[INFO] base={base}  n={n}  classes={n_classes}")

    Xtr, ytr = load_split(base, "train")
    Xva, yva = load_split(base, "val")
    Xte, yte = load_split(base, "test")
    print(f"[INFO] train size = {len(Xtr)}  val = {len(Xva)}  test = {len(Xte)}")

    # --- SVM (論文準拠: RBF, C=1.0, gamma='scale') ---
    # probability=False（既定）で計算軽量化。random_stateは一応固定。
    svm = SVC(kernel="rbf", C=1.0, gamma="scale", random_state=SEED)
    svm.fit(Xtr, ytr)

    for name, X, y in [("val", Xva, yva), ("test", Xte, yte)]:
        pred = svm.predict(X)
        acc = accuracy_score(y, pred)
        print(f"[{name.upper()}] acc={acc:.4f}")
    print("\n[TEST] classification report:")
    print(classification_report(yte, svm.predict(Xte), digits=4))

    out = Path(args.out); out.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(svm, out)
    print("Saved:", out)

if __name__ == "__main__":
    main()
