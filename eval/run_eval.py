#!/usr/bin/env python
"""Baseline (TF-IDF+LR) vs Swarm (/v1/scan) on the test split, or --thread for multi-message scenarios.
python eval/run_eval.py [--url http://127.0.0.1:8000] [--limit N] [--thread]"""
import argparse, json, os, pathlib, re, sys, time, uuid
import requests, yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA, SCEN, OUT = ROOT / "data/synthetic", ROOT / "scenarios", ROOT / "eval"
FLAGGED = {"scam", "suspicious"}  # positive class


def load(name):
    return [json.loads(l) for l in (DATA / f"{name}.jsonl").read_text(encoding="utf-8").splitlines() if l]


def sender_kind(s):
    d = re.sub(r"\D", "", s)
    n = d[1:] if len(d) == 11 and d[0] == "1" else d
    if "@" in s: return "email"
    if len(n) == 10 and n[:3] in {"800", "833", "844", "855", "866", "877", "888"}: return "toll_free"
    if s.isdigit() and 5 <= len(s) <= 6: return "short_code"
    if len(n) == 10: return "long_code"
    if re.search(r"[A-Za-z]", s): return "alphanumeric"
    return "unknown"


def build_request(texts, sender, client="web", rid=None):
    kind = sender_kind(sender)
    snd = {"raw": sender, "kind": kind, "isContact": False}
    if kind == "long_code":
        snd["e164"] = "+1" + re.sub(r"\D", "", sender)[-10:]
    return {"requestId": rid or str(uuid.uuid4()), "client": client, "mode": "incoming", "sender": snd,
            "messages": [{"id": f"m{i + 1}", "direction": "in", "text": t} for i, t in enumerate(texts)],
            "targetMessageId": f"m{len(texts)}", "locale": "en-US", "redactions": []}


def scan(url, req):
    h = {"X-Swarm-Key": os.environ["SWARM_API_KEY"]} if os.environ.get("SWARM_API_KEY") else {}
    t = time.perf_counter()
    r = requests.post(f"{url}/v1/scan", json=req, headers=h, timeout=30)
    r.raise_for_status()
    return r.json(), (time.perf_counter() - t) * 1000


def ece(probs, ys, bins=10):
    """Expected calibration error of P(scam) vs outcome; returns (ece, [(mean_conf, observed_rate, n)])."""
    e, rel = 0.0, []
    for b in range(bins):
        idx = [i for i, p in enumerate(probs) if p >= b / bins and (p < (b + 1) / bins or b == bins - 1)]
        if not idx: continue
        conf, acc = sum(probs[i] for i in idx) / len(idx), sum(ys[i] for i in idx) / len(idx)
        e += len(idx) / len(probs) * abs(conf - acc)
        rel.append((conf, acc, len(idx)))
    return e, rel


def prf(tp, fp, fn):
    p = tp / (tp + fp) if tp + fp else 0.0
    r = tp / (tp + fn) if tp + fn else 0.0
    return {"precision": round(p, 3), "recall": round(r, 3), "f1": round(2 * p * r / (p + r), 3) if p + r else 0.0}


def metrics(rows, pred, prob):
    """rows: dicts with id/label/category; pred: flagged bools; prob: P(scam) floats."""
    y = [r["label"] == "scam" for r in rows]
    tp = sum(a and b for a, b in zip(y, pred)); fp = sum((not a) and b for a, b in zip(y, pred))
    fn = sum(a and not b for a, b in zip(y, pred)); legit = y.count(False)
    per = {}
    for c in sorted({r["category"] for r in rows}):
        ci = [i for i, r in enumerate(rows) if r["category"] == c]
        if y[ci[0]]:  # one-vs-legit: this category's scams against all legit rows
            ctp = sum(pred[i] for i in ci)
            per[c] = {**prf(ctp, fp, len(ci) - ctp), "n": len(ci)}
        else:
            per[c] = {"false_positive_rate": round(sum(pred[i] for i in ci) / len(ci), 3), "n": len(ci)}
    e, rel = ece(prob, y)
    err = sorted(range(len(rows)), key=lambda i: -abs(prob[i] - y[i]))
    return {"n": len(rows), "accuracy": round(sum(a == b for a, b in zip(y, pred)) / len(rows), 3),
            "overall": prf(tp, fp, fn), "legit_false_positive_rate": round(fp / legit, 3) if legit else None,
            "ece": round(e, 3), "reliability": rel, "per_category": per,
            "worst_errors": [rows[i]["id"] for i in err if pred[i] != y[i]][:10]}


def baseline(train, rows):
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.linear_model import LogisticRegression
    from sklearn.pipeline import make_pipeline
    m = make_pipeline(TfidfVectorizer(ngram_range=(1, 2), sublinear_tf=True), LogisticRegression(max_iter=1000))
    m.fit([r["text"] for r in train], [r["label"] == "scam" for r in train])
    t = time.perf_counter()
    prob = [float(p) for p in m.predict_proba([r["text"] for r in rows])[:, 1]]
    return prob, (time.perf_counter() - t) * 1000 / len(rows)


def run_swarm(url, rows):
    prob, pred, lat = [], [], []
    for r in rows:
        res, ms = scan(url, build_request([r["text"]], r["sender"]))
        prob.append(res["riskScore"] / 100); pred.append(res["verdict"] in FLAGGED); lat.append(ms)
    return prob, pred, lat


def pct(xs, q):
    s = sorted(xs)
    return round(s[min(len(s) - 1, int(q * len(s)))], 1)


def reliability_png(path, series):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return False
    plt.figure(figsize=(4.5, 4.5)); plt.plot([0, 1], [0, 1], "k--", lw=1, label="perfect")
    for name, rel in series.items():
        if rel: plt.plot([c for c, _, _ in rel], [a for _, a, _ in rel], "o-", label=name)
    plt.xlabel("predicted P(scam)"); plt.ylabel("observed scam rate"); plt.legend(); plt.title("Reliability")
    plt.tight_layout(); plt.savefig(path, dpi=130); plt.close()
    return True


def thread_eval(url):
    """Per multi-message scenario: risk after each message and the first turn flagged (drift detection turn)."""
    out = {}
    for p in sorted(SCEN.glob("*.yaml")):
        s = yaml.safe_load(p.read_text(encoding="utf-8"))
        texts = [st["text"] for st in s["steps"] if "text" in st and "sender" not in st]
        if len(texts) < 2: continue
        risks, first = [], None
        for k in range(1, len(texts) + 1):
            res, _ = scan(url, build_request(texts[:k], s["sender"]))
            risks.append(res["riskScore"])
            if first is None and res["verdict"] in FLAGGED: first = k
        out[s["id"]] = {"turns": len(texts), "risk_series": risks, "detection_turn": first, "expected": s["expect"]["verdict"],
                        "ok": (first is not None) == (s["expect"]["verdict"] in FLAGGED)}
    return out


def email_request(e):
    return {"requestId": str(uuid.uuid4()), "client": "web", "mode": "incoming", "channel": "email",
            "sender": {"raw": e["fromAddress"], "kind": "email", "isContact": False},
            "email": {"subject": e["subject"], "fromName": e["fromName"], "fromAddress": e["fromAddress"],
                      **({"replyTo": e["replyTo"]} if e.get("replyTo") else {}), "links": e["links"], "attachments": e["attachments"]},
            "messages": [{"id": "e1", "direction": "in", "text": e["text"]}], "targetMessageId": "e1", "locale": "en-US", "redactions": []}


def email_rows():
    """Generated set + scenarios, as the same dict shape."""
    sys.path.insert(0, str(ROOT / "scripts"))
    import emaillib
    rows = [json.loads(l) for l in (DATA / "emails.jsonl").read_text(encoding="utf-8").splitlines() if l]
    for k, s in emaillib.load_all().items():
        rows.append(dict(id=f"sc-{k}", label="scam" if s["expect"]["verdict"] == "scam" else "legit", category="scenario",
                         fromName=s["from_name"], fromAddress=s["from_address"], replyTo=s.get("reply_to"), subject=s["subject"],
                         text=emaillib.plain(s["body"]), links=emaillib.links(s["body"]),
                         attachments=[{"name": a} for a in s["attachments"]], drones=s["expect"]["drones"]))
    return rows


def email_eval(url, limit=None):
    rows = email_rows()[:limit]
    pred, prob, lat, hit, tot = [], [], [], {}, {}
    for r in rows:
        res, ms = scan(url, email_request(r))
        pred.append(res["verdict"] in FLAGGED); prob.append(res["riskScore"] / 100); lat.append(ms)
        got = {f["drone"] for f in res.get("findings", [])}
        if r["label"] == "scam":
            for d in r["drones"]:
                tot[d] = tot.get(d, 0) + 1; hit[d] = hit.get(d, 0) + (d in got)
    m = metrics(rows, pred, prob)
    m["drone_hit_rate"] = {d: {"hit": hit[d], "n": tot[d], "rate": round(hit[d] / tot[d], 3)} for d in sorted(tot)}
    m["latency_ms"] = {"p50": pct(lat, .5), "p95": pct(lat, .95)}
    return m


def md(rep):
    L = [f"# Signal Swarm eval ({rep['generated']})", f"Test rows: {rep['n']} | backend: {rep['url']}", "",
         "| system | accuracy | precision | recall | F1 | legit FPR | ECE | p50 ms | p95 ms |", "|---|---|---|---|---|---|---|---|---|"]
    for k, v in rep["systems"].items():
        o = v["overall"]
        L.append(f"| {k} | {v['accuracy']} | {o['precision']} | {o['recall']} | {o['f1']} | {v['legit_false_positive_rate']} | {v['ece']} | {v['latency_ms']['p50']} | {v['latency_ms']['p95']} |")
    for k, v in rep["systems"].items():
        L += ["", f"## {k}: per category", "| category | n | P | R | F1 / FPR |", "|---|---|---|---|---|"]
        for c, m in v["per_category"].items():
            L.append(f"| {c} | {m['n']} | {m.get('precision', '-')} | {m.get('recall', '-')} | {m.get('f1', m.get('false_positive_rate'))} |")
        L += ["", f"Worst errors (ids): {', '.join(v['worst_errors']) or 'none'}"]
    L += ["", "Per-category precision is one-vs-legit (a category's scams against all legit rows). Positive = verdict scam or suspicious; P(scam) = riskScore/100.",
          "Data is synthetic (stand-in for the T-Mobile set).", ""]
    if rep.get("reliability_png"): L += ["![reliability](reliability.png)", ""]
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=os.environ.get("SWARM_URL", "http://127.0.0.1:8000"))
    ap.add_argument("--limit", type=int)
    ap.add_argument("--thread", action="store_true")
    ap.add_argument("--email", action="store_true")
    a = ap.parse_args()
    if a.email:
        m = email_eval(a.url, a.limit)
        (OUT / "email_report.json").write_text(json.dumps(m, indent=1))
        print(f"n={m['n']} accuracy={m['accuracy']} {m['overall']} legit_FPR={m['legit_false_positive_rate']} ECE={m['ece']} latency={m['latency_ms']}")
        for d, v in m["drone_hit_rate"].items(): print(f"  drone {d:12} {v['hit']}/{v['n']} = {v['rate']}")
        return
    if a.thread:
        res = thread_eval(a.url)
        (OUT / "thread_report.json").write_text(json.dumps(res, indent=1))
        for k, v in res.items():
            print(f"{k:24} detect@{v['detection_turn']}/{v['turns']} risks={v['risk_series']} {'ok' if v['ok'] else 'MISS'}")
        return
    test = load("test")[:a.limit]
    bprob, bms = baseline(load("train"), test)
    sprob, spred, slat = run_swarm(a.url, test)
    systems = {"baseline_tfidf_lr": {**metrics(test, [p >= .5 for p in bprob], bprob), "latency_ms": {"p50": round(bms, 2), "p95": round(bms, 2)}},
               "swarm": {**metrics(test, spred, sprob), "latency_ms": {"p50": pct(slat, .5), "p95": pct(slat, .95)}}}
    png = reliability_png(OUT / "reliability.png", {k: v["reliability"] for k, v in systems.items()})
    rep = {"generated": time.strftime("%Y-%m-%d %H:%M"), "url": a.url, "n": len(test), "systems": systems, "reliability_png": png}
    (OUT / "report.json").write_text(json.dumps(rep, indent=1))
    (OUT / "report.md").write_text(md(rep), encoding="utf-8")
    print(md(rep).split("\n\n")[0])


if __name__ == "__main__":
    main()
