# train_rnn.py
from pathlib import Path
import json, numpy as np
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

# ---- 固定シード（再現用）----
SEED = 42
keras.utils.set_random_seed(SEED)

# ---- 入力パス ----
BASE = Path("dataset/npy/merged/five-40gram")
meta = json.load(open(BASE/"meta.json"))
n = int(meta["n"])
num_classes = len(meta["label_map"])

def load_split(split: str):
    X = np.load(BASE/split/"X.npy", mmap_mode="r", allow_pickle=False).astype("int32")
    y = np.load(BASE/split/"y.npy", allow_pickle=False).astype("int32")
    assert X.shape[1] == n and X.shape[0] == y.shape[0], f"shape mismatch in {split}"
    return X, y

X_train, y_train = load_split("train")
X_val,   y_val   = load_split("val")
X_test,  y_test  = load_split("test")

# ---- 語彙サイズ（syscall 最大ID+1）----
vocab = int(max(X_train.max(), X_val.max(), X_test.max())) + 1  # 427 のはず
embed_dim = 64  # ※論文に記載なし：実務的に小さめを仮置き

# ---- モデル（論文パラメータ）----
model = keras.Sequential([
    layers.Input(shape=(n,), dtype="int32"),
    layers.Embedding(input_dim=vocab, output_dim=embed_dim, mask_zero=False),
    layers.LSTM(35, activation="relu", return_sequences=True),
    layers.Dropout(0.2),
    layers.LSTM(80, activation="relu"),
    layers.Dropout(0.2),
    layers.Dense(num_classes, activation="softmax"),
])

model.compile(optimizer="adam",
              loss="sparse_categorical_crossentropy",
              metrics=["accuracy"])

history = model.fit(
    X_train, y_train,
    validation_data=(X_val, y_val),
    epochs=10,            # ※論文に明記がなければ固定でOK（必要なら調整）
    batch_size=1024,
    verbose=2
)

loss, acc = model.evaluate(X_test, y_test, verbose=0)
print(f"[TEST] acc={acc:.4f}  loss={loss:.4f}")

out = Path("models"); out.mkdir(parents=True, exist_ok=True)
model.save(out/"lstm.model.keras")
print("Saved:", out/"lstm.model.keras")
