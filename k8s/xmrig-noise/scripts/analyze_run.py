#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
analyze_run.py
runs/<basename>/ の {summary.json, *.jsonl} を読み、run.json を出力（窓別ハッシュレートも出力）
"""

import argparse, json, os
from glob import glob
from collections import defaultdict, Counter

NAMESPACE = "xmrig-noise"

def parse_args():
    p = argparse.ArgumentParser(description="Summarize a mining run into run.json")
    p.add_argument("--run-dir", required=True)
    p.add_argument("--label")
    p.add_argument("--noise-enable", type=int, choices=[0,1], dest="noise_enable")
    p.add_argument("--noise-rate", type=int, dest="noise_rate")
    p.add_argument("--ld-preload", type=int, choices=[0,1], dest="ld_preload")
    p.add_argument("--start-utc", dest="start_utc")
    p.add_argument("--end-utc", dest="end_utc")
    p.add_argument("--noise-thresh", type=float, default=0.95)
    p.add_argument("--noise-balance-low", type=float, default=0.4)
    p.add_argument("--noise-balance-high", type=float, default=0.6)
    p.add_argument("--worker-thresh", type=float, default=0.95)
    return p.parse_args()

def read_json(path):
    if not os.path.exists(path): return {}
    with open(path, "r", encoding="utf-8") as f: return json.load(f)

def pick(d, dotted_paths):
    for path in dotted_paths:
        cur = d; ok = True
        for k in path.split("."):
            if isinstance(cur, dict) and k in cur: cur = cur[k]
            else: ok = False; break
        if ok: return cur
    return None

def find_files(run_dir):
    summary_path = os.path.join(run_dir, "summary.json")
    candidates = glob(os.path.join(run_dir, "*.jsonl"))
    raw_path = max(candidates, key=lambda p: os.path.getsize(p), default=None)
    return summary_path, raw_path

def summarize_summary(summary_path, run_dir):
    d = read_json(summary_path)

    # 窓別ハッシュレート
    s10 = s60 = s15m = highest = None
    if isinstance(d.get("hashrate", {}).get("total"), list):
        arr = d["hashrate"]["total"]
        if len(arr) >= 1: s10  = arr[0]
        if len(arr) >= 2: s60  = arr[1]
        if len(arr) >= 3: s15m = arr[2]
    highest = d.get("hashrate", {}).get("highest")

    # 稼働秒 & プールワーク（accepted share の難易度合計）
    uptime = pick(d, ["uptime", "connection.uptime"])
    pwh    = pick(d, ["results.hashes_total", "connection.hashes_total"])
    try: uptime = int(uptime) if uptime is not None else 0
    except: uptime = 0
    try: pwh = int(pwh) if pwh is not None else 0
    except: pwh = 0

    # 代表平均H/s（優先: 60s → 10s → pwh/uptime）
    basis = None
    if isinstance(s60, (int, float)):
        avg = float(s60); basis = "60s"
    elif isinstance(s10, (int, float)):
        avg = float(s10); basis = "10s"
    else:
        avg = (pwh / uptime) if uptime > 0 else 0.0; basis = "pool_work"

    return {
        "uptime_sec": uptime,
        "pool_work_hashes": pwh,                # わかりやすい名称
        "total_hashes": pwh,                    # 互換のため残す
        "hashrate": {
            "s10": s10,
            "s60": s60,
            "s15m": s15m,
            "highest": highest
        },
        "avg_Hs": round(avg, 2),
        "avg_Hs_basis": basis,
        "source": os.path.relpath(summary_path, run_dir) if summary_path else None
    }

def stream_counts(raw_path):
    counts = defaultdict(Counter); events_total = 0
    if not raw_path or not os.path.exists(raw_path): return counts, events_total
    with open(raw_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try: rec = json.loads(line)
            except: continue
            tid = rec.get("tid"); sc = rec.get("sc")
            if tid is None or sc is None: continue
            tid = str(tid)
            try: sc = int(sc)
            except: continue
            counts[tid][sc] += 1; events_total += 1
    return counts, events_total

def build_tid_summary(counts):
    items = []
    for tid, ctr in counts.items():
        total = sum(ctr.values())
        top3 = [{"sc": sc, "n": n, "pct": round((n/total*100.0) if total else 0.0, 1)}
                for sc, n in ctr.most_common(3)]
        items.append((tid, total, top3))
    items.sort(key=lambda x:(-x[1], x[0]))
    return [{"tid": tid, "total": total, "top3": top3} for tid, total, top3 in items]

def label_tids(counts, noise_thresh=0.95, balance_low=0.4, balance_high=0.6, worker_thresh=0.95):
    noise_tids=[]; worker_tids=[]; other_tids=[]
    for tid, ctr in counts.items():
        total = sum(ctr.values())
        if total==0: other_tids.append(tid); continue
        n115, n172, n124 = ctr.get(115,0), ctr.get(172,0), ctr.get(124,0)
        s = n115 + n172
        noise_major = (s/total)>=noise_thresh
        balance_ok = (s>0 and balance_low <= (n115/s) <= balance_high)
        is_noise = noise_major and balance_ok
        is_worker = (n124/total) >= worker_thresh
        (noise_tids if is_noise else worker_tids if is_worker else other_tids).append(tid)
    noise_calls = sum(sum(counts[t].values()) for t in noise_tids)
    worker_calls = sum(sum(counts[t].values()) for t in worker_tids)
    return {"noise_tids":noise_tids, "worker_tids":worker_tids, "other_tids":other_tids,
            "noise_calls":noise_calls, "worker_calls":worker_calls}

def derive_label_from_basename(basename):
    parts = basename.split("-")
    if len(parts)>=4 and parts[0]=="xmrig" and parts[1]=="noise":
        return "-".join(parts[2:-1]) or None
    if len(parts)>=3 and parts[0]=="xmrig" and parts[1]=="noise":
        return parts[2]
    return None

def main():
    args = parse_args()
    run_dir = args.run_dir.rstrip("/")
    summary_path, raw_path = find_files(run_dir)
    basename = os.path.basename(run_dir)

    summary = summarize_summary(summary_path, run_dir)
    counts, events_total = stream_counts(raw_path)
    tid_summary = build_tid_summary(counts)

    lab = label_tids(counts, args.noise_thresh, args.noise_balance_low, args.noise_balance_high, args.worker_thresh)
    denom = (lab["noise_calls"] + lab["worker_calls"])
    noise_ratio_pct = (lab["noise_calls"]/denom*100.0) if denom>0 else 0.0
    noise_ratio_overall_pct = (lab["noise_calls"]/events_total*100.0) if events_total>0 else 0.0

    label = args.label or derive_label_from_basename(basename)

    run_info = {
        "basename": basename,
        "namespace": NAMESPACE,
        "label": label,
        "start_utc": args.start_utc,
        "end_utc": args.end_utc,
        "duration_sec": None,
        "image": None,
        "resources": None,
        "noise": {"enable": args.noise_enable, "rate_hz": args.noise_rate, "ld_preload": args.ld_preload},
        "http_summary_time_utc": None
    }

    run_json = {
        "run_info": run_info,
        "summary": summary,
        "tid_summary": tid_summary,
        "labels": {"worker_tids": lab["worker_tids"], "noise_tids": lab["noise_tids"], "other_tids": lab["other_tids"]},
        "noise_ratio": {
            "noise_calls": lab["noise_calls"],
            "worker_calls": lab["worker_calls"],
            "ratio_pct": round(noise_ratio_pct, 1),
            "overall_pct": round(noise_ratio_overall_pct, 1),
            "rule": "noise≡(115+172)>=95% & 40–60% / worker≡124>=95%"
        },
        "events_total": events_total,
        "files": {
            "raw_jsonl": os.path.relpath(raw_path, run_dir) if raw_path else None,
            "summary_json": os.path.relpath(summary_path, run_dir) if summary_path else None,
            "run_json": "run.json"
        }
    }

    out_path = os.path.join(run_dir, "run.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(run_json, f, ensure_ascii=False, indent=2)

    print(f"[OK] wrote {out_path}")
    print(f"  events_total={events_total} avg_Hs={summary['avg_Hs']}({summary['avg_Hs_basis']}) noise_ratio={run_json['noise_ratio']['ratio_pct']}% (overall {run_json['noise_ratio']['overall_pct']}%)")

if __name__ == "__main__":
    main()
