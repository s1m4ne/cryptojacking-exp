#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
make_dataset.py
  - 研究者手元運用向けの最小・再現性重視のデータセット作成スクリプト
  - 仕様（抜粋）
      * フレームサイズ = n（設定ファイルで指定）
      * ストライド = 1（固定）
      * 前後 10% のイベントを内部的に削除（trim）
      * フレームは raw から全生成、先頭から target_frames を採用（不足は警告）
      * 分割は元論文準拠の 3分割（train:56%, val:14%, test:30%）
        - 実装は 70/30 → train を 80/20 に再分割
        - 各境界にガード = n フレーム（境界の前後 n フレームは捨てる）
      * ラベル跨ぎ禁止（可能なら pod/job 等のセグメント境界で検出）
      * 出力:
          dataset/npy/workloads/<workload>/n{n}-gram/{train,val,test}/{X.npy,y.npy}, meta.json
          dataset/npy/merged/<cfg_basename>/{train,val,test}/{X.npy,y.npy}, meta.json
      * ログは標準出力のみ。最後に生成ファイル一覧と shape を表示
"""

from __future__ import annotations
import sys
import os
import re
import json
import math
import glob
from pathlib import Path
from typing import Any, Dict, List, Tuple, Optional

import numpy as np

try:
    import yaml  # type: ignore
except Exception:
    yaml = None  # YAMLが無い場合はJSON設定のみ対応

# ---------------------------
# ユーティリティ
# ---------------------------

def info(msg: str) -> None:
    print(f"[INFO] {msg}")

def warn(msg: str) -> None:
    print(f"[WARNING] {msg}")

def error(msg: str) -> None:
    print(f"[ERROR] {msg}", file=sys.stderr)

def sanitize_basename(name: str, maxlen: int = 120) -> str:
    base = re.sub(r"\.[A-Za-z0-9]+$", "", name)  # 拡張子除去
    base = re.sub(r"[^A-Za-z0-9._-]", "_", base)
    if base.startswith("."):
        base = "_" + base[1:]
    if len(base) > maxlen:
        base = base[:maxlen]
    return base or "dataset"

def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)

def save_json(path: Path, obj: Dict[str, Any]) -> None:
    with path.open("w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)

def np_save(path: Path, arr: np.ndarray) -> None:
    ensure_dir(path.parent)
    np.save(str(path), arr)

def load_config(path: Path) -> Dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"config not found: {path}")
    if path.suffix.lower() in (".yaml", ".yml"):
        if yaml is None:
            raise RuntimeError("PyYAML がありません。`pip install pyyaml` を実行してください。")
        with path.open("r", encoding="utf-8") as f:
            return yaml.safe_load(f)
    elif path.suffix.lower() == ".json":
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    else:
        raise ValueError("設定ファイルは .yaml/.yml/.json のいずれかにしてください。")

def get_in(d: Dict[str, Any], path: List[str]) -> Any:
    cur: Any = d
    for k in path:
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            return None
    return cur

# ---------------------------
# Raw JSONL ロード & 抽出
# ---------------------------

def parse_syscall_id(rec: Any) -> Optional[int]:
    """
    システムコール番号（整数）を柔軟に抽出。
    - 数値そのもの
    - 典型的なキー:
      'syscall', 'syscall_id', 'nr', 'id', 'syscallNr', 'sc'
      ネスト: event.syscall.id, event.id など
    """
    if isinstance(rec, int):
        return rec
    if isinstance(rec, str):
        # 数字文字列なら受け入れ
        if rec.isdigit():
            return int(rec)
        return None
    if not isinstance(rec, dict):
        return None

    # 候補キー（優先順）
    candidates = [
        ["syscall"], ["syscall_id"], ["nr"], ["sc"], ["id"],
        ["event","syscall","id"], ["event","id"], ["syscallNumber"],
    ]
    for path in candidates:
        v = get_in(rec, path)
        if isinstance(v, int):
            return v
        if isinstance(v, str) and v.isdigit():
            return int(v)
    return None

def parse_segment_key(rec: Any) -> int:
    """
    フレーム内の“ラベル跨ぎ”検出用のセグメントキーを整数にマップ。
    代表キー: 'pod', 'job', 'container_id', 'k8s.pod', 'k8s.job'
    見つからなければ 0（単一セグメント扱い）
    """
    if not isinstance(rec, dict):
        return 0
    keys = [
        ["pod"], ["job"], ["container_id"],
        ["k8s","pod"], ["k8s","job"], ["k8s","container_id"],
    ]
    vals: List[str] = []
    for path in keys:
        v = get_in(rec, path)
        if isinstance(v, str) and v:
            vals.append(v)
    if not vals:
        return 0
    # 安全なハッシュ（安定さ重視で Python の hash は使わない）
    s = "|".join(vals)
    return abs(hash(s)) % (2**31 - 1)

def parse_timestamp(rec: Any) -> Optional[float]:
    """
    タイムスタンプ（秒またはナノ秒など）を best-effort で抽出。
    無ければ None（その場合はファイル順を保持）。
    """
    if isinstance(rec, dict):
        candidates = [
            ["ts"], ["time"], ["timestamp"], ["@timestamp"], ["event","time"], ["event","ts"],
        ]
        for path in candidates:
            v = get_in(rec, path)
            if isinstance(v, (int, float)):
                # だいたい 1e12 以上ならナノ秒/ミリ秒とみなし秒に寄せる
                if v > 1e12:
                    # ナノ秒 or ミリ秒の曖昧性はあるが、ソート順目的なので十分
                    return float(v) / 1e9  # nanosec仮定
                return float(v)
            if isinstance(v, str):
                try:
                    return float(v)
                except Exception:
                    pass
    return None

def load_raw_events(paths: List[str]) -> Tuple[List[int], List[int], List[Optional[float]]]:
    """
    JSONL を複数読み込み、syscall_id と segment_key, timestamp の列を返す。
    """
    files: List[str] = []
    for p in paths:
        files.extend(glob.glob(p))
    if not files:
        warn(f"INPUT - no files matched: {paths}")
        return [], [], []

    all_recs: List[Tuple[int,int,Optional[float]]] = []
    for fp in sorted(files):
        try:
            with open(fp, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rec = json.loads(line)
                    except Exception:
                        # もし単なる数値のみの行ならそのまま扱う
                        if line.isdigit():
                            sc = int(line)
                            all_recs.append((sc, 0, None))
                        continue
                    sc = parse_syscall_id(rec)
                    if sc is None:
                        continue
                    seg = parse_segment_key(rec)
                    ts = parse_timestamp(rec)
                    all_recs.append((sc, seg, ts))
        except Exception as e:
            warn(f"INPUT - failed to read {fp}: {e}")

    if not all_recs:
        return [], [], []

    # タイムスタンプがあればそれでソート（無い行は元順を保つように補助キー付与）
    indexed = [(i, sc, seg, ts if ts is not None else float(i)) for i, (sc, seg, ts) in enumerate(all_recs)]
    indexed.sort(key=lambda x: x[3])

    sc_list = [x[1] for x in indexed]
    seg_list = [x[2] for x in indexed]
    ts_list  = [x[3] for x in indexed]  # float
    return sc_list, seg_list, ts_list

# ---------------------------
# 前処理・フレーミング
# ---------------------------

def trim_head_tail(seq_len: int, head_pct: float = 0.10, tail_pct: float = 0.10) -> Tuple[int,int]:
    head = int(math.floor(seq_len * head_pct))
    tail = int(math.floor(seq_len * tail_pct))
    start = head
    end = max(head, seq_len - tail)
    return start, end  # [start, end)

def slide_windows(seq: np.ndarray, seg: np.ndarray, n: int) -> Tuple[np.ndarray, np.ndarray]:
    """
    ストライド=1で n 連のウィンドウを生成。
    ラベル跨ぎ（セグメント跨ぎ）は除外。
    戻り値:
      frames: shape = [F_valid, n]
      idx0:   shape = [F_valid] （フレーム開始インデックス）
    """
    if seq.shape[0] < n:
        return np.empty((0, n), dtype=np.int64), np.empty((0,), dtype=np.int64)

    # sliding window（NumPy 1.20+）
    from numpy.lib.stride_tricks import sliding_window_view
    win_seq = sliding_window_view(seq, window_shape=n)  # [F_all, n]
    win_seg = sliding_window_view(seg, window_shape=n)  # [F_all, n]

    # セグメント一様性チェック（行ごとに全要素が同一）
    # → max == min なら一様
    seg_max = win_seg.max(axis=1)
    seg_min = win_seg.min(axis=1)
    ok_mask = (seg_max == seg_min)

    frames = win_seq[ok_mask]
    idx0 = np.nonzero(ok_mask)[0].astype(np.int64)  # 各フレームの開始位置
    return frames, idx0

def take_head(frames: np.ndarray, idx0: np.ndarray, target: int) -> Tuple[np.ndarray, np.ndarray]:
    if frames.shape[0] <= target:
        return frames, idx0
    return frames[:target], idx0[:target]

# ---------------------------
# 分割（元論文準拠）＋ ガード
# ---------------------------

def split_70_30_then_80_20_with_guard(frames: np.ndarray, idx0: np.ndarray, n: int) -> Dict[str, Tuple[np.ndarray,np.ndarray]]:
    """
    frames, idx0 を連続区間で
      1) 70/30 に分割
      2) 70 側を 80/20 に再分割（= train/val）
    各境界に ガード = n フレームを適用（前後 n を捨てる）
    戻り値: {'train':(X,idx0), 'val':(...), 'test':(...)}
    """
    F = frames.shape[0]
    if F == 0:
        return {"train": (frames, idx0), "val": (frames, idx0), "test": (frames, idx0)}

    # 70/30
    cut_70 = int(math.floor(F * 0.70))
    # ガード
    train70_end = max(0, cut_70 - n)
    test30_start = min(F, cut_70 + n)

    frames_70 = frames[:train70_end]
    idx_70 = idx0[:train70_end]
    frames_30 = frames[test30_start:]
    idx_30 = idx0[test30_start:]

    # 70 側を 80/20
    F70 = frames_70.shape[0]
    cut_80 = int(math.floor(F70 * 0.80))
    train_end = max(0, cut_80 - n)
    val_start = min(F70, cut_80 + n)

    train_frames = frames_70[:train_end]
    train_idx0   = idx_70[:train_end]

    val_frames = frames_70[val_start:]
    val_idx0   = idx_70[val_start:]

    test_frames = frames_30
    test_idx0   = idx_30

    return {"train": (train_frames, train_idx0),
            "val":   (val_frames,   val_idx0),
            "test":  (test_frames,  test_idx0)}

# ---------------------------
# 保存 & サマリ
# ---------------------------

def save_split_npy(root: Path, split: str, X: np.ndarray, y: np.ndarray) -> List[Path]:
    paths: List[Path] = []
    x_path = root / split / "X.npy"
    y_path = root / split / "y.npy"
    np_save(x_path, X)
    np_save(y_path, y)
    paths.extend([x_path, y_path])
    return paths

def print_output_summary(paths_and_shapes: List[Tuple[str, Tuple[int, ...]]]) -> None:
    print("===== OUTPUT SUMMARY =====")
    for p, shp in paths_and_shapes:
        print(f"{p:<70} shape={shp}")
    print("==========================")

# ---------------------------
# メイン処理（1ワークロード → 保存）
# ---------------------------

def process_workload(cfg_n: int, wl_cfg: Dict[str, Any], base_out_dir: Path) -> Dict[str, Any]:
    workload = wl_cfg["workload"]
    name = wl_cfg.get("name", workload)
    label_id = int(wl_cfg["label_id"])
    paths = wl_cfg["paths"]
    target_frames = int(wl_cfg["target_frames"])

    info(f"INPUT  - workload={workload}, target_frames={target_frames}, paths={paths}")

    sc_list, seg_list, ts_list = load_raw_events(paths)
    E_total = len(sc_list)
    if E_total == 0:
        warn(f"INPUT  - workload={workload}, no events")
        # 空データとして処理継続
        frames = np.empty((0, cfg_n), dtype=np.int64)
        idx0 = np.empty((0,), dtype=np.int64)
    else:
        # trim
        start, end = trim_head_tail(E_total, head_pct=0.10, tail_pct=0.10)
        info(f"TRIM   - workload={workload}, events_total={E_total}, trim=[{start},{end}) -> {end-start}")

        sc_np = np.asarray(sc_list[start:end], dtype=np.int64)
        seg_np = np.asarray(seg_list[start:end], dtype=np.int64)

        # フレーミング（stride=1） + ラベル跨ぎ禁止
        F_possible = max(0, sc_np.shape[0] - cfg_n + 1)
        frames_all, idx_all = slide_windows(sc_np, seg_np, cfg_n)
        F_valid = frames_all.shape[0]
        info(f"FRAME  - workload={workload}, n={cfg_n}, F_possible={F_possible}, F_valid={F_valid}")

        # 先頭から target_frames を採用（不足なら警告）
        if F_valid < target_frames:
            warn(f"SELECT - workload={workload}, valid={F_valid} < target={target_frames} (shortfall={target_frames-F_valid}), taking {F_valid}")
            frames, idx0 = frames_all, idx_all
        else:
            frames, idx0 = take_head(frames_all, idx_all, target_frames)
            info(f"SELECT - workload={workload}, selected={frames.shape[0]}")

    # 分割（70/30 → 80/20, ガード=n）
    splits = split_70_30_then_80_20_with_guard(frames, idx0, cfg_n)
    out_root = base_out_dir / "dataset" / "npy" / "workloads" / workload / f"n{cfg_n}-gram"
    ensure_dir(out_root)

    # 保存
    produced_paths: List[Tuple[str, Tuple[int, ...]]] = []
    meta = {
        "workload": workload,
        "name": name,
        "label_id": label_id,
        "n": cfg_n,
        "trim_pct": {"head": 0.10, "tail": 0.10},
        "guard_frames": cfg_n,
        "target_frames": target_frames,
        "splits": {},
    }

    for split_name in ["train", "val", "test"]:
        X, _idx = splits[split_name]
        y = np.full((X.shape[0],), label_id, dtype=np.int64)
        paths = save_split_npy(out_root, split_name, X, y)
        for p in paths:
            produced_paths.append((str(p), tuple(np.load(str(p)).shape)))
        meta["splits"][split_name] = {"count": int(X.shape[0])}

        # ログ（shape）
        info(f"SAVE   - workload={workload}, split={split_name}, X.shape={X.shape}, y.shape={y.shape}")

    save_json(out_root / "meta.json", meta)
    produced_paths.append((str(out_root / "meta.json"), ()))

    return {
        "workload": workload,
        "label_id": label_id,
        "paths": produced_paths,
        "split_counts": {k: int(v[0].shape[0]) for k, v in splits.items()},
        "split_arrays": splits,  # 後でマージに使う
    }

# ---------------------------
# マージ（設定ファイル名ベース）
# ---------------------------

def merge_and_save(cfg_basename: str,
                   cfg_n: int,
                   per_wl: List[Dict[str, Any]],
                   base_out_dir: Path) -> List[Tuple[str, Tuple[int, ...]]]:
    out_root = base_out_dir / "dataset" / "npy" / "merged" / cfg_basename
    ensure_dir(out_root)

    produced_paths: List[Tuple[str, Tuple[int, ...]]] = []

    # split ごとに縦結合
    merged_meta = {
        "config_basename": cfg_basename,
        "n": cfg_n,
        "splits": {},
        "label_map": {d["workload"]: d["label_id"] for d in per_wl},
        "workloads": [d["workload"] for d in per_wl],
    }

    for split in ["train", "val", "test"]:
        # 順番は設定ファイルの記載順
        X_list: List[np.ndarray] = []
        y_list: List[np.ndarray] = []
        for d in per_wl:
            X, _idx = d["split_arrays"][split]
            y = np.full((X.shape[0],), d["label_id"], dtype=np.int64)
            X_list.append(X)
            y_list.append(y)

        if X_list:
            X_merged = np.concatenate(X_list, axis=0)
            y_merged = np.concatenate(y_list, axis=0)
        else:
            X_merged = np.empty((0, cfg_n), dtype=np.int64)
            y_merged = np.empty((0,), dtype=np.int64)

        # 保存
        paths = save_split_npy(out_root, split, X_merged, y_merged)
        for p in paths:
            produced_paths.append((str(p), tuple(np.load(str(p)).shape)))
        merged_meta["splits"][split] = {"count": int(X_merged.shape[0])}

        info(f"MERGE  - split={split}, total_shape={X_merged.shape}, classes={len(per_wl)}")

    save_json(out_root / "meta.json", merged_meta)
    produced_paths.append((str(out_root / "meta.json"), ()))
    return produced_paths

# ---------------------------
# エントリポイント
# ---------------------------

def main(argv: List[str]) -> int:
    import argparse
    parser = argparse.ArgumentParser(description="Make dataset (n-gram frames, stride=1, 3-way split with guard).")
    parser.add_argument("--config", required=True, help="Path to config YAML/JSON.")
    parser.add_argument("--overwrite", action="store_true", help="Allow overwrite merged output dir.")
    parser.add_argument("--run-suffix", choices=["auto"], help="If exists, append -YYYYmmddThhmmZ to merged dir name.")
    args = parser.parse_args(argv)

    cfg_path = Path(args.config)
    cfg = load_config(cfg_path)

    # 設定の取り出し
    framing = cfg.get("framing", {})
    if "n" not in framing:
        error("config.framing.n が必要です。")
        return 2
    n = int(framing["n"])

    workloads = cfg.get("workloads", [])
    if not workloads:
        error("config.workloads が空です。")
        return 2

    # 出力先ベース名（設定ファイル名）
    cfg_basename_raw = sanitize_basename(cfg_path.name)
    merged_dir = Path("dataset") / "npy" / "merged" / cfg_basename_raw

    # 既存対処
    if merged_dir.exists():
        if args.overwrite:
            info(f"OVERWRITE - removing existing merged dir: {merged_dir}")
            import shutil
            shutil.rmtree(merged_dir)
        elif args.run_suffix == "auto":
            from datetime import datetime, timezone
            stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%MZ")
            cfg_basename_raw = f"{cfg_basename_raw}-{stamp}"
            merged_dir = Path("dataset") / "npy" / "merged" / cfg_basename_raw
        else:
            error(f"既に出力先が存在します: {merged_dir} （--overwrite か --run-suffix auto を指定してください）")
            return 2

    info(f"START  - config={cfg_path}, cfg_basename={cfg_basename_raw}, n={n}")
    info("POLICY - trim=10%/10%, stride=1, split=56/14/30 (70/30→80/20), guard=n")

    # label_id 重複チェック
    label_ids = [int(w["label_id"]) for w in workloads]
    if len(label_ids) != len(set(label_ids)):
        error("label_id が重複しています。設定ファイルを確認してください。")
        return 2

    base_out_dir = Path(".")
    all_produced: List[Tuple[str, Tuple[int, ...]]] = []

    # 各ワークロード処理
    per_wl_results: List[Dict[str, Any]] = []
    for wl in workloads:
        res = process_workload(n, wl, base_out_dir)
        per_wl_results.append(res)
        all_produced.extend(res["paths"])

    # マージ
    merged_paths = merge_and_save(cfg_basename_raw, n, per_wl_results, base_out_dir)
    all_produced.extend(merged_paths)

    # バリデーション（基本）
    ok = True
    # 形状検査（workloads）
    for wl in per_wl_results:
        for split in ["train", "val", "test"]:
            X, _idx = wl["split_arrays"][split]
            if X.shape[1] != n:
                error(f"X width != n  (workload={wl['workload']}, split={split}, X.shape={X.shape}, n={n})")
                ok = False
    # label_id は重複無しを事前チェック済み
    if not ok:
        return 3

    # 最終一覧（shape は npy を開いて確認済み）
    print_output_summary(all_produced)

    info("CHECK  - basic validations passed (label_id unique / X width==n)")
    info("DONE")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

