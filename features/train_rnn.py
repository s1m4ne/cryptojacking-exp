#!/usr/bin/env python3
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models
from sklearn.metrics import classification_report

# ====================
# 1. データ読み込み
# ====================
X_train = np.load("cache/n40_overlap/X_train.npy")
Y_train = np.load("cache/n40_overlap/Y_train.npy")
X_val   = np.load("cache/n40_overlap/X_val.npy")
Y_val   = np.load("cache/n40_overlap/Y_val.npy")
X_test  = np.load("cache/n40_overlap/X_test.npy")
Y_test  = np.load("cache/n40_overlap/Y_test.npy")

print("[INFO] Data loaded:", X_train.shape, Y_train.shape)

# ====================
# 2. モデル構築
# ====================
vocab_size = int(X_train.max()) + 1  # システムコール番号の最大値+1
embedding_dim = 64                   # 埋め込み次元（適当）

model = models.Sequential([
    layers.Embedding(input_dim=vocab_size, output_dim=embedding_dim, input_length=40),
    layers.LSTM(35, return_sequences=True, activation="relu"),
    layers.LSTM(80, activation="relu"),
    layers.Dropout(0.2),
    layers.Dense(1, activation="sigmoid")
])

model.compile(
    optimizer="adam",
    loss="binary_crossentropy",
    metrics=["accuracy"]
)

model.summary()

# ====================
# 3. 学習
# ====================
history = model.fit(
    X_train, Y_train,
    validation_data=(X_val, Y_val),
    epochs=5,
    batch_size=256
)

# ====================
# 4. 評価
# ====================
y_pred = (model.predict(X_test) > 0.5).astype("int32")
print(classification_report(Y_test, y_pred, digits=4))
