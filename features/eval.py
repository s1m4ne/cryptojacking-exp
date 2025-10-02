# features/eval_models_simple.py
# シンプル一括評価: merged/test の X.npy,y.npy を各モデルで評価して、ログ出力＋JSON保存
from pathlib import Path
import json, numpy as np, joblib
from sklearn.metrics import accuracy_score, precision_recall_fscore_support, classification_report
from datetime import datetime
from zoneinfo import ZoneInfo

JST = ZoneInfo("Asia/Tokyo")

# モデル⇔データ対応（固定）
MODELS = [
    {"name":"rnn_40", "kind":"keras",   "model_path":"models/lstm.model.keras",      "data_path":"dataset/npy/merged/five-40gram"},
    {"name":"dt_35",  "kind":"sklearn", "model_path":"models/dt_35.joblib",          "data_path":"dataset/npy/merged/five-35gram"},
    {"name":"svm_50", "kind":"sklearn", "model_path":"models/svm_50_all.joblib",     "data_path":"dataset/npy/merged/five-50gram"},
    {"name":"mlp_10", "kind":"sklearn", "model_path":"models/mlp_10.joblib",         "data_path":"dataset/npy/merged/five-10gram"},
    {"name":"knn_5",  "kind":"sklearn", "model_path":"models/knn_5.joblib",          "data_path":"dataset/npy/merged/five-5gram"},
]

def now_jst_str():
    return datetime.now(JST).strftime("%Y-%m-%d %H:%M:%S %Z")

def now_jst_iso():
    return datetime.now(JST).isoformat()

def load_test(merged_dir: Path):
    meta = json.load(open(merged_dir/"meta.json"))
    X = np.load(merged_dir/"test"/"X.npy", mmap_mode="r", allow_pickle=False)
    y = np.load(merged_dir/"test"/"y.npy", allow_pickle=False)
    assert X.shape[1] == meta["n"], f"n mismatch: X.shape[1]={X.shape[1]} vs meta.n={meta['n']}"
    return X, y, meta

def eval_sklearn(model_path: Path, X, y):
    clf = joblib.load(model_path)
    y_pred = clf.predict(X)
    return y_pred

def eval_keras(model_path: Path, X, y):
    import tensorflow as tf
    X = np.asarray(X, dtype="int32")  # RNNのEmbedding前提でint32に
    model = tf.keras.models.load_model(model_path)
    y_prob = model.predict(X, verbose=0)
    y_pred = y_prob.argmax(axis=1)
    return y_pred

def metrics_dict(y_true, y_pred):
    acc = accuracy_score(y_true, y_pred)
    pw, rw, fw, _ = precision_recall_fscore_support(y_true, y_pred, average="weighted", zero_division=0)
    pm, rm, fm, _ = precision_recall_fscore_support(y_true, y_pred, average="macro", zero_division=0)
    return {
        "accuracy": float(acc),
        "precision_weighted": float(pw),
        "recall_weighted": float(rw),
        "f1_weighted": float(fw),
        "precision_macro": float(pm),
        "recall_macro": float(rm),
        "f1_macro": float(fm),
    }

def main():
    all_results = []
    start_all = now_jst_str()
    print(f"[START] {start_all}  eval 5 models")

    for m in MODELS:
        name = m["name"]; kind = m["kind"]
        model_path = Path(m["model_path"])
        data_path  = Path(m["data_path"])
        try:
            X, y, meta = load_test(data_path)
            start = now_jst_str()
            print(f"[START] {start}  {name}  (n={meta['n']}, test_N={len(y)})")
            if kind == "sklearn":
                y_pred = eval_sklearn(model_path, X, y)
            elif kind == "keras":
                y_pred = eval_keras(model_path, X, y)
            else:
                raise ValueError(f"unknown kind: {kind}")

            md = metrics_dict(y, y_pred)
            done = now_jst_str()
            print(f"[DONE ] {done}  {name}  acc={md['accuracy']:.4f}")
            print(classification_report(y, y_pred, digits=4))

            all_results.append({
                "name": name,
                "kind": kind,
                "model_path": str(model_path),
                "data_path": str(data_path),
                "n": meta["n"],
                "test_N": int(len(y)),
                "started_at": start,
                "finished_at": done,
                **md
            })
        except Exception as e:
            err = f"{type(e).__name__}: {e}"
            print(f"[ERROR] {name}: {err}")
            all_results.append({
                "name": name, "kind": kind,
                "model_path": str(model_path), "data_path": str(data_path),
                "error": err, "started_at": now_jst_str(), "finished_at": now_jst_str()
            })

    out = Path("eval/results.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w") as f:
        json.dump({"started_at": start_all, "finished_at": now_jst_str(), "results": all_results}, f, indent=2)
    print(f"[SAVED] {out}")

if __name__ == "__main__":
    main()
