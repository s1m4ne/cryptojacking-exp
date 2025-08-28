# features/train-mlp.py
from pathlib import Path
import argparse, json, numpy as np, joblib, random
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import accuracy_score, classification_report

SEED = 42
random.seed(SEED); np.random.seed(SEED)

def load_split(base: Path, split: str):
    X = np.load(base/split/"X.npy", allow_pickle=False)    # shape [N, n]
    y = np.load(base/split/"y.npy", allow_pickle=False)    # labels 0..4
    assert X.shape[0] == y.shape[0], f"size mismatch in {split}"
    return X, y

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--merged", default="dataset/npy/merged/five-10gram",
                    help="使用する merged ディレクトリ（five-10gram 他でもOK）")
    ap.add_argument("--out", default="", help="保存先（未指定なら n を読み models/mlp_<n>.joblib）")
    args = ap.parse_args()

    base = Path(args.merged)
    meta = json.load(open(base/"meta.json"))
    n = int(meta["n"]); n_classes = len(meta["label_map"])
    print(f"[INFO] base={base}  n={n}  classes={n_classes}")

    Xtr, ytr = load_split(base, "train")
    Xva, yva = load_split(base, "val")
    Xte, yte = load_split(base, "test")

    # --- MLP (論文準拠: hidden=(100,), relu, adam, lr=0.001、他は既定値) ---
    mlp = MLPClassifier(hidden_layer_sizes=(100,),
                        activation="relu",
                        solver="adam",
                        learning_rate_init=0.001,
                        random_state=SEED)
    mlp.fit(Xtr, ytr)

    for name, X, y in [("val", Xva, yva), ("test", Xte, yte)]:
        pred = mlp.predict(X)
        acc = accuracy_score(y, pred)
        print(f"[{name.upper()}] acc={acc:.4f}")
    print("\n[TEST] classification report:")
    print(classification_report(yte, mlp.predict(Xte), digits=4))

    out = Path(args.out) if args.out else Path(f"models/mlp_{n}.joblib")
    out.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(mlp, out)
    print("Saved:", out)

if __name__ == "__main__":
    main()
