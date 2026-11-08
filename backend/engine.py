"""Scan engine: analyzers -> calibrated ensemble -> verdict -> findings/actions/explanations."""
import functools, pathlib, time
import joblib
import numpy as np
from sklearn.calibration import CalibratedClassifierCV
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import cross_val_predict
from contracts.models import Action, Category, Privacy, ScanRequest, ScanResult
from . import email_channel, attachments, bootstrap_data, classifier, drift, explain, impersonation, intel_data, links, pressure, sender, warden
from .common import target_msg

MODEL_VERSION = "swarm-fallback-1"
ENSEMBLE = pathlib.Path(__file__).parent / "models" / "ensemble.joblib"
ORDER = ["angler", "link", "pressure", "impersonator", "warden", "drift", "carrier"]
GENERIC_CHANGE = "If you know who sent this and expected it, you can mark it safe."


def run_analyzers(req: ScanRequest, intel, clf_out: dict):
    res = {"angler": sender.analyze(req, intel), "link": links.analyze(req, intel), "pressure": pressure.analyze(req, intel, clf_out),
           "impersonator": impersonation.analyze(req, intel), "warden": warden.analyze(req, intel), "drift": drift.analyze(req, intel),
           "carrier": attachments.analyze(req, intel)}
    return res


def vector(clf_p: float, res: dict, req) -> list[float]:
    s = lambda k: res[k][1]
    return [clf_p, s("angler"), s("link"), s("pressure"), s("impersonator"), s("drift"), float(len(req.messages) > 1)]


def verdict_of(p: float) -> str:
    return "scam" if p >= 0.85 else "suspicious" if p >= 0.6 else "unsure" if p >= 0.4 else "safe"


def train_all():
    """Train classifier + calibrated ensemble on the bootstrap corpus and persist both."""
    intel = intel_data.load()
    data = bootstrap_data.generate(seed=0)
    reqs = [ScanRequest(**d[0]) for d in data]
    texts = [classifier.thread_text(r) for r in reqs]
    cats = [d[1] for d in data]
    pipe = classifier.train(texts, cats)
    clf = classifier.Classifier(pipe)
    # out-of-fold classifier probabilities so the ensemble does not learn from a leaky feature
    oof = cross_val_predict(classifier.make_pipeline(), texts, cats, cv=5, method="predict_proba")
    legit_i = list(pipe.classes_).index(bootstrap_data.LEGIT)
    X, y = [], []
    for r, d, pr in zip(reqs, data, oof):
        res = run_analyzers(r, intel, clf.predict(classifier.thread_text(r)))
        v = vector(float(1 - pr[legit_i]), res, r)
        for label, copies in d[2]:
            X += [v] * copies
            y += [label] * copies
    X, y = np.array(X), np.array(y)
    cal = CalibratedClassifierCV(LogisticRegression(C=4, max_iter=500), method="isotonic" if len(y) > 1000 else "sigmoid", cv=5).fit(X, y)
    joblib.dump(cal, ENSEMBLE)
    return clf, cal


@functools.lru_cache(maxsize=1)
def models():
    if classifier.MODEL.exists() and ENSEMBLE.exists():
        return classifier.Classifier(joblib.load(classifier.MODEL)), joblib.load(ENSEMBLE)
    return train_all()


def scan(req: ScanRequest) -> ScanResult:
    t0 = time.perf_counter()
    intel = intel_data.load()
    clf, ens = models()
    msg = target_msg(req)
    email = req.channel == "email" and req.email is not None
    out = clf.predict((req.email.subject + " . " + msg.text) if email else classifier.thread_text(req))
    if email:
        res = email_channel.analyze(req, intel, out)
        p = email_channel.probability(res, out["prob"])
    else:
        res = run_analyzers(req, intel, out)
        p = float(ens.predict_proba([vector(out["prob"], res, req)])[0][1])
    p = min(max(p, 0.02), 0.98)  # never claim certainty
    findings = [res[d][0] for d in ORDER if res.get(d) and res[d][0]]
    outgoing = not email and req.mode == "outgoing_draft"
    if outgoing:  # the draft is judged on what is about to be sent
        w = res["warden"]
        p = max(0.88 if w[0] and w[0].severity == "high" else 0.65, w[1] * 0.93) if w[0] else min(p, 0.2)
        findings = [res["warden"][0]] if w[0] else []
    verdict = "suspicious" if outgoing and findings else verdict_of(p)  # a draft is a warning, not an accusation
    if verdict == "safe":
        findings = []
    elif verdict == "unsure":
        findings = [f.model_copy(update={"whatWouldChangeMyMind": f.whatWouldChangeMyMind or GENERIC_CHANGE}) for f in findings]
    cat = None
    if verdict != "safe":
        if email:
            cat = Category(id="email_phishing", label="Phishing Email", source=classifier.SOURCE)
        elif outgoing and findings:
            kind = findings[0].evidence[0].kind
            cid = "otp_request" if kind.startswith("otp") else "sensitive_data"
            cat = Category(id=cid, label=bootstrap_data.CAT_LABELS.get(cid, "Sensitive Data in Draft"), source=classifier.SOURCE)
        elif out["category_id"] != bootstrap_data.LEGIT:
            cat = Category(id=out["category_id"], label=bootstrap_data.CAT_LABELS[out["category_id"]], source=classifier.SOURCE)
    brand = next((b for b in intel.brands if findings and any(f.drone == "impersonator" and f.evidence[0].value == b["brand"] for f in findings)), None)
    findings, llm_used = explain.llm_rewrite(findings, msg.text, cat and cat.label)
    from .actions import build_actions
    return ScanResult(
        requestId=req.requestId, verdict=verdict, riskScore=round(100 * p), confidence=round(max(p, 1 - p), 2), category=cat,
        summary=explain.summary(verdict, cat and cat.label, brand and brand["brand"], req.mode, findings, "email" if email else "text"), findings=findings,
        actions=build_actions(verdict, brand, req.mode, req.channel if email else "sms"), riskSeries=drift.series(req)[0] if len(req.messages) >= 2 and not outgoing and not email else None,
        privacy=Privacy(fieldsReceived=["sender", "email.subject", "email.links", "email.attachments", "messages[].text"] if email else ["sender", "messages[].text"], llmUsed=llm_used),
        latencyMs=round((time.perf_counter() - t0) * 1000), modelVersion=MODEL_VERSION)
