import json, pathlib, re, socket, subprocess, sys
import yaml
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import run_eval as E

ROOT = pathlib.Path(__file__).resolve().parents[2]
SC = [yaml.safe_load(p.read_text(encoding="utf-8")) for p in sorted((ROOT / "scenarios").glob("*.yaml"))]


def test_sender_kind():
    assert [E.sender_kind(s) for s in ["4695550182", "+1 (469) 555-0182", "62884", "a@b.co", "18335550188", "AMAZON"]] == \
        ["long_code", "long_code", "short_code", "email", "toll_free", "alphanumeric"]


def test_ece_perfect_and_worst():
    assert E.ece([0.0, 1.0], [0, 1])[0] == 0
    assert E.ece([1.0, 1.0], [0, 0])[0] == 1


def test_metrics_basic():
    rows = [{"id": "a", "label": "scam", "category": "x"}, {"id": "b", "label": "legit", "category": "y"}]
    m = E.metrics(rows, [True, True], [.9, .8])
    assert m["legit_false_positive_rate"] == 1.0 and m["worst_errors"] == ["b"] and m["per_category"]["x"]["recall"] == 1.0


def test_splits_disjoint():
    d = ROOT / "data/synthetic"
    ids = {n: {json.loads(l)["id"] for l in (d / f"{n}.jsonl").read_text().splitlines()} for n in ("train", "val", "test")}
    assert not (ids["train"] & ids["val"]) and not (ids["train"] & ids["test"]) and not (ids["val"] & ids["test"])
    allr = [json.loads(l) for l in (d / "all.jsonl").read_text().splitlines()]
    assert len(allr) >= 1500 and set(allr[0]) == {"id", "text", "sender", "label", "category"}
    assert 0.35 <= sum(r["label"] == "legit" for r in allr) / len(allr) <= 0.5


def test_scenarios():
    ids = {s["id"] for s in SC}
    need = {"tmobile_account_lock", "toll_unpaid", "usps_redelivery", "otp_harvest", "grandkid_giftcards", "wrong_number_crypto",
            "job_offer_whatsapp", "bank_fraud_alert_callback", "irs_threat", "prize_winner", "robocall"}
    assert len(SC) >= 20 and need <= ids
    assert sum(s["expect"]["verdict"] == "safe" for s in SC) >= 5
    w = next(s for s in SC if s["id"] == "wrong_number_crypto")
    assert len(w["steps"]) == 6 and all(st["delay"] == 5 for st in w["steps"][1:])
    assert all(s["sender"] and s["steps"] and "verdict" in s["expect"] for s in SC)


def test_scam_domains_do_not_resolve():
    text = " ".join(st.get("text", "") for s in SC for st in s["steps"]) + (ROOT / "data/synthetic/all.jsonl").read_text()
    doms = set(re.findall(r"\b((?:[a-z0-9]+-)+[a-z0-9]+\.(?:co|top|xyz|info|click|link|support|cc))\b", text))
    assert doms
    for d in sorted(doms)[:60]:
        try:
            socket.gethostbyname(d)
        except OSError:
            continue
        raise AssertionError(f"{d} resolves")


def test_inject_dry_run():
    r = subprocess.run([sys.executable, str(ROOT / "scripts/inject.py"), "tmobile_account_lock", "--dry-run"], capture_output=True, text=True)
    assert r.returncode == 0 and "adb emu sms send 4695550182 T-Mobile: your line" in r.stdout
