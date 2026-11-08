import json, logging, pathlib, time
import pytest
from fastapi.testclient import TestClient
from contracts.models import ScanResult
from . import bootstrap_data, engine, explain
from .app import app
from .helpers import req, sender

FIX = pathlib.Path(__file__).resolve().parent.parent / "contracts" / "fixtures"
H = {"X-Swarm-Key": "dev-key"}
client = TestClient(app)


def post(body, headers=H):
    return client.post("/v1/scan", json=body, headers=headers)


def hero():
    return json.load(open(FIX / "scan_request_tmobile_lock.json"))


def scan_obj(r):
    return engine.scan(r)


def test_auth_required_and_healthz_exempt():
    assert post(hero(), headers={}).status_code == 401
    assert post(hero(), headers={"X-Swarm-Key": "nope"}).status_code == 401
    h = client.get("/v1/healthz")
    assert h.status_code == 200 and h.json() == {"ok": True, "classifier": "fallback", "llm": False}


def test_hero_matches_fixture_shape():
    r = post(hero())
    assert r.status_code == 200
    res = ScanResult.model_validate(r.json())
    fx = ScanResult.model_validate(json.load(open(FIX / "scan_result_tmobile_lock.json")))
    assert res.verdict == "scam" and res.riskScore >= 90 and res.requestId == fx.requestId
    assert [f.drone for f in res.findings] == ["angler", "link", "pressure", "impersonator"]
    for a, b in zip(res.findings, fx.findings):
        assert (a.anchor.messageId, a.anchor.field) == (b.anchor.messageId, b.anchor.field)
    assert len({f.drone for f in res.findings}) == len(res.findings)
    ids = [a.id for a in res.actions]
    assert ids[0] == "report_7726" and "call_official" in ids and res.actions[1].payload == {"number": "611"}
    assert res.category.id == "account_suspension" and res.category.source == "fallback"
    assert res.privacy.retained is False and res.privacy.llmUsed is False
    text = hero()["messages"][0]["text"]
    link = next(f for f in res.findings if f.drone == "link")
    assert text[slice(*link.anchor.span)] == "t-mobi1e-acct-verify.co/a8f"
    imp = next(f for f in res.findings if f.drone == "impersonator")
    assert tuple(imp.anchor.span) == tuple(fx.findings[3].anchor.span)


def test_legit_short_code_bank_alert_is_safe():
    res = scan_obj(req("Chase: Debit card ending 4821 was used for $23.10 at Target. Reply STOP to opt out.", sender("33789", "short_code")))
    assert res.verdict == "safe" and res.findings == [] and res.actions == [] and res.category is None


def test_legit_otp_delivery_is_safe():
    res = scan_obj(req("Your Amazon verification code is <CODE:6>. Don't share it with anyone.", sender("22000", "short_code")))
    assert res.verdict == "safe"


def test_otp_request_is_scam_or_suspicious():
    res = scan_obj(req("Hi this is support. Please reply with the 6 digit code we just sent you to cancel the request", sender("+13125550111")))
    assert res.verdict in ("scam", "suspicious") and res.findings and res.category.id == "otp_request"


def test_wrong_number_crypto_thread_is_suspicious():
    t = [("in", "Hi, is this Anna? We met at the conference"), ("out", "Sorry, wrong number"), ("in", "Oh sorry! You seem nice though, where are you from?"),
         ("out", "Dallas"), ("in", "I make good returns on a crypto trading platform, my uncle taught me. Want to try?")]
    res = scan_obj(req(t, sender("+13125550166")))
    assert res.verdict == "suspicious" and "drift" in [f.drone for f in res.findings]
    assert res.riskSeries and len(res.riskSeries) == 5 and res.riskSeries[-1] == 1.0


def test_outgoing_draft_otp_warden():
    r = req([("in", "Reply with the code you got to keep your account"), ("out", "My code is <CODE:6>")], sender("+14695550182"), "outgoing_draft")
    res = scan_obj(r)
    assert [f.drone for f in res.findings] == ["warden"] and res.findings[0].anchor.field == "compose"
    assert res.verdict == "suspicious" and [a.id for a in res.actions] == ["dont_send", "send_anyway"]
    ScanResult.model_validate(res.model_dump())


def test_outgoing_draft_benign():
    res = scan_obj(req([("out", "see you at 7")], sender("+14695550100"), "outgoing_draft"))
    assert res.verdict == "safe" and res.findings == []


def test_friend_message_is_safe():
    res = scan_obj(req("running late, be there in 10", sender("+12145550100", contact=True)))
    assert res.verdict == "safe"


def test_invalid_request_does_not_echo_text():
    bad = hero()
    bad["messages"][0]["text"] = "SECRET-BODY-TEXT"
    bad["client"] = "nope"
    r = post(bad)
    assert r.status_code == 422 and "SECRET-BODY-TEXT" not in r.text


def test_guardian_alert_tolerates_photon_down(monkeypatch):
    monkeypatch.setenv("PHOTON_URL", "http://127.0.0.1:9")
    r = client.post("/v1/guardian/alert", json={"requestId": "x", "category": "Smishing", "riskScore": 94, "userAlias": "Sam"}, headers=H)
    assert r.status_code == 200 and r.json() == {"sent": False}


def test_guardian_forwards_without_text(monkeypatch):
    seen = {}

    class R:
        is_success = True

    def fake(url, json=None, **k):
        seen.update(url=url, json=json, headers=k.get("headers"))
        return R()

    monkeypatch.setattr("backend.app.httpx.post", fake)
    r = client.post("/v1/guardian/alert", json={"requestId": "x", "category": "Smishing", "riskScore": 94, "userAlias": "Sam", "text": "LEAK"}, headers=H)
    assert r.json() == {"sent": True} and seen["url"].endswith("/internal/guardian-alert") and "LEAK" not in str(seen["json"])
    assert seen["headers"]["X-Swarm-Key"] == "dev-key"


def test_feedback_and_bundle():
    assert client.post("/v1/feedback", json={"requestId": "x", "label": "scam"}, headers=H).status_code == 204
    b = client.get("/v1/reputation/bundle", headers=H).json()
    assert b["salt"] and b["hashes"] and b["version"]
    assert client.get("/v1/reputation/bundle").status_code == 401


def test_no_message_text_in_logs(caplog):
    caplog.set_level(logging.DEBUG)
    body = hero()
    body["messages"][0]["text"] = "ZEBRA-MARKER T-Mobile: suspended in 2 hrs verify t-mobi1e-acct-verify.co/a8f"
    post(body)
    assert "ZEBRA-MARKER" not in caplog.text and "t-mobi1e" not in caplog.text
    assert any("requestId" in r.getMessage() for r in caplog.records)


def test_latency_without_llm():
    post(hero())  # warm
    t = []
    for _ in range(20):
        s = time.perf_counter()
        assert post(hero()).status_code == 200
        t.append((time.perf_counter() - s) * 1000)
    assert sorted(t)[int(len(t) * 0.95) - 1] < 150


def test_holdout_accuracy_on_fresh_bootstrap():
    ok = n = 0
    for d, _, labels in bootstrap_data.generate(seed=123):
        from contracts.models import ScanRequest
        if len(labels) > 1:
            continue
        v = engine.scan(ScanRequest(**d)).verdict
        ok += (v in ("scam", "suspicious")) == bool(labels[0][0])
        n += 1
    assert ok / n > 0.95


def test_llm_never_changes_verdict(monkeypatch):
    monkeypatch.setenv("LLM_DISABLED", "0")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "k")

    class R:
        def json(self):
            return {"content": [{"text": json.dumps({d: {"title": "T", "explanation": "E", "whatWouldChangeMyMind": "W"} for d in ["angler", "link", "pressure", "impersonator"]})}]}

    monkeypatch.setattr(explain.httpx, "post", lambda *a, **k: R())
    from contracts.models import ScanRequest
    res = engine.scan(ScanRequest(**hero()))
    assert res.privacy.llmUsed and res.verdict == "scam" and res.findings[0].title == "T" and res.findings[0].severity == "high"


def test_llm_failure_falls_back_to_templates(monkeypatch):
    monkeypatch.setenv("LLM_DISABLED", "0")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "k")

    def boom(*a, **k):
        raise TimeoutError

    monkeypatch.setattr(explain.httpx, "post", boom)
    from contracts.models import ScanRequest
    res = engine.scan(ScanRequest(**hero()))
    assert not res.privacy.llmUsed and res.findings[1].title == "Lookalike domain"
