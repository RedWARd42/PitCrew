import json, pathlib
import pytest
from fastapi.testclient import TestClient
from contracts.models import ScanRequest, ScanResult
from . import engine, email_channel
from .app import app
from .helpers import INTEL

FIX = pathlib.Path(__file__).resolve().parent.parent / "contracts" / "fixtures" / "scan_request_email_phish.json"
client = TestClient(app)


def E(subject="Hello", name="Sam", addr="sam@acme-corp.example", body="Hi, see you at the meeting.", links=(), atts=(), reply=None):
    return ScanRequest(requestId="e", client="android", mode="incoming", channel="email", sender=dict(raw=addr, kind="email", isContact=False),
                       email=dict(subject=subject, fromName=name, fromAddress=addr, replyTo=reply, links=[dict(text=t, href=h) for t, h in links],
                                  attachments=[dict(name=n) for n in atts]),
                       messages=[dict(id="e1", direction="in", text=body)], targetMessageId="e1")


def drones(r):
    return [f.drone for f in engine.scan(r).findings]


def test_hero_email_phish():
    r = ScanRequest(**json.load(open(FIX)))
    res = engine.scan(r)
    ScanResult.model_validate(res.model_dump())
    assert res.verdict == "scam" and res.riskScore >= 90
    assert [f.drone for f in res.findings] == ["angler", "link", "pressure", "impersonator", "carrier"]
    by = {f.drone: f for f in res.findings}
    assert (by["angler"].anchor.messageId, by["angler"].anchor.field) == ("header", "sender")
    assert by["link"].anchor.field == "link" and tuple(by["link"].anchor.span) == (0, 0)
    assert by["pressure"].anchor.field == "body" and by["carrier"].anchor.messageId == "e1"
    assert all(len(f.explanation) <= 280 for f in res.findings)
    assert [a.id for a in res.actions] == ["report_7726", "alert_guardian", "delete"] and res.actions[0].label == "Report phishing"
    assert "email" in res.summary and "text" not in res.summary


def test_hero_via_api():
    r = client.post("/v1/scan", json=json.load(open(FIX)), headers={"X-Swarm-Key": "dev-key"})
    assert r.status_code == 200 and r.json()["verdict"] == "scam"


# ---- sender spoofing
def test_sender_display_name_brand_mismatch():
    f, _ = email_channel.angler(E(name="PayPal", addr="service@some-random-host.example"), INTEL)
    assert f and f.evidence[0].kind == "display_name_brand_mismatch"


def test_sender_lookalike_domain():
    assert email_channel.angler(E(name="Amazon", addr="orders@amazon-order-hold.icu"), INTEL)[0].severity == "high"


def test_sender_reply_to_differs():
    f, _ = email_channel.angler(E(name="PayPal", addr="a@paypa1-support.com", reply="x@evil-relay.biz"), INTEL)
    assert "reply_to_mismatch" in [e.kind for e in f.evidence]


def test_sender_freemail_ceo_fraud():
    f, _ = email_channel.angler(E(name="John Smith CEO", addr="john.ceo@gmail.com", subject="Quick favor", body="Are you available? I need you to buy gift cards, keep this confidential."), INTEL)
    assert f and "free_mail_exec_request" in [e.kind for e in f.evidence]


def test_sender_freemail_brand_claim():
    assert email_channel.angler(E(name="Chase Bank Security", addr="chase.security@gmail.com"), INTEL)[0]


def test_sender_legit_paypal_receipt_clean():
    assert email_channel.angler(E(name="PayPal", addr="service@paypal.com"), INTEL)[0] is None
    assert email_channel.angler(E(name="PayPal", addr="noreply@mail.paypal.com"), INTEL)[0] is None


def test_sender_legit_friend_gmail_clean():
    assert email_channel.angler(E(name="Alex Rivera", addr="alex.rivera@gmail.com", body="Lunch tomorrow?"), INTEL)[0] is None


def test_sender_replyto_esp_ok():
    assert email_channel.angler(E(name="Weekly Digest", addr="news@digest.example", reply="reply@bounce.sendgrid.net"), INTEL)[0] is None


# ---- links
def test_link_text_vs_href_mismatch():
    f, _ = email_channel.link(E(links=[("https://www.paypal.com/verify", "https://evil-host.example/login")]), INTEL)
    assert f and f.evidence[0].kind == "link_text_mismatch" and tuple(f.anchor.span) == (0, 0)


def test_link_span_is_index_of_worst_link():
    f, _ = email_channel.link(E(links=[("Home", "https://www.acme-corp.example"), ("Pay", "https://paypa1-resolution.co/x")]), INTEL)
    assert tuple(f.anchor.span) == (1, 1) and f.evidence[0].kind == "lookalike"


def test_link_every_href_checked_lookalike_new_domain():
    f, _ = email_channel.link(E(links=[("click here", "https://tmobile-bill-update.top/a")]), INTEL)
    assert f and f.severity == "high"


def test_link_shortener():
    f, _ = email_channel.link(E(links=[("Read", "https://bit.ly/3abc")]), INTEL)
    assert f and f.evidence[0].kind == "shortener"


def test_link_brand_text_foreign_href():
    f, _ = email_channel.link(E(links=[("Verify your PayPal account", "https://some-host.example/v")]), INTEL)
    assert f and f.evidence[0].kind == "brand_text_foreign_href"


def test_link_legit_paypal_clean():
    assert email_channel.link(E(links=[("View receipt", "https://www.paypal.com/myaccount/activity")]), INTEL)[0] is None


def test_link_legit_github_clean():
    assert email_channel.link(E(links=[("View it on GitHub", "https://github.com/acme/repo/pull/12"), ("unsubscribe", "https://github.com/notifications/unsubscribe")]), INTEL)[0] is None


def test_link_newsletter_esp_tracking_clean():
    r = E(links=[("www.digest.example/post", "https://digest.us5.list-manage.com/track/click?u=1"), ("Read more", "https://links.sendgrid.net/ls/click?upn=abc")])
    assert email_channel.link(r, INTEL)[0] is None


def test_link_body_fallback_when_no_hrefs():
    f, _ = email_channel.link(E(body="Pay at paypa1-resolution.co/x now"), INTEL)
    assert f and f.anchor.field == "body"


# ---- attachments
@pytest.mark.parametrize("name,ext", [("invoice_4491.html", "web"), ("setup.exe", "danger"), ("payment.zip", "archive"), ("Q3.docm", "macro"), ("scan.iso", "web"), ("screen.scr", "danger")])
def test_carrier_risky(name, ext):
    f, _ = email_channel.carrier(E(atts=[name]), INTEL)
    assert f and f.drone == "carrier" and f.anchor.field == "body"


def test_carrier_double_extension_worst():
    f, s = email_channel.carrier(E(atts=["receipt.pdf.exe"]), INTEL)
    assert s >= 0.99 and "double_extension" in [e.kind for e in f.evidence]


@pytest.mark.parametrize("name", ["invoice_4491.pdf", "report.xlsx", "photo.jpg", "notes.txt"])
def test_carrier_legit_attachments_clean(name):
    assert email_channel.carrier(E(atts=[name]), INTEL)[0] is None


# ---- pressure / impersonator / whole-email verdicts
def test_pressure_email_lexicon():
    f, _ = email_channel.pressure.analyze(E(subject="Password expires today", body="Your password will expire. Verify your account within 24 hours."), INTEL)
    assert f and f.anchor.field == "body"


def test_pressure_ceo_wire():
    assert email_channel.pressure.analyze(E(body="Are you available? Wire the funds today, keep this confidential."), INTEL)[0]


def test_impersonator_from_name_brand_foreign_domain():
    f, _ = email_channel.impersonator(E(name="Netflix Billing", addr="b@netfIix-help.example", links=[("Update", "https://netfIix-help.example/pay")]), INTEL)
    assert f and f.evidence[0].value == "Netflix"


def test_impersonator_legit_brand_clean():
    assert email_channel.impersonator(E(name="Amazon.com", addr="auto-confirm@amazon.com", links=[("Order", "https://www.amazon.com/o/1")]), INTEL)[0] is None


def test_verdict_legit_paypal_receipt_safe():
    r = E(subject="Receipt for your payment to Acme Store", name="PayPal", addr="service@paypal.com", body="You sent a payment of $42.00 to Acme Store. Transaction ID 9XY.",
          links=[("View transaction", "https://www.paypal.com/activity/payment/9XY")], atts=["receipt.pdf"])
    assert engine.scan(r).verdict == "safe"


def test_verdict_github_notification_safe():
    r = E(subject="[acme/repo] Fix typo (#12)", name="octocat", addr="notifications@github.com", body="Merged #12 into main. Reply to this email directly or view it on GitHub.",
          links=[("view it on GitHub", "https://github.com/acme/repo/pull/12#event-1")])
    assert engine.scan(r).verdict == "safe"


def test_verdict_newsletter_known_esp_safe():
    r = E(subject="This week in cooking", name="Digest Weekly", addr="hello@digest.example", reply="hello@digest.example",
          body="Five new recipes this week. Unsubscribe any time.", links=[("Read more", "https://digest.us5.list-manage.com/track/click?u=1"), ("Unsubscribe", "https://digest.us5.list-manage.com/unsubscribe")])
    assert engine.scan(r).verdict == "safe"


def test_verdict_company_internal_safe():
    r = E(subject="Q3 budget review Thursday", name="Dana Lee", addr="dana.lee@acme-corp.example", reply="dana.lee@acme-corp.example",
          body="Attached is the budget. Can we meet Thursday at 2pm?", links=[("Calendar", "https://calendar.acme-corp.example/e/1")], atts=["budget.xlsx"])
    assert engine.scan(r).verdict == "safe"


def test_verdict_ceo_fraud_flagged():
    r = E(subject="Quick favor", name="Robert Hale (CEO)", addr="robert.hale.ceo@gmail.com", body="Are you available? I need you to buy gift cards today. Keep this confidential.")
    assert engine.scan(r).verdict in ("scam", "suspicious")


def test_verdict_invoice_lure_html_only():
    r = E(subject="Invoice attached", name="Accounts", addr="acct@billing-docs.example", body="Please see attached invoice.", atts=["invoice_882.html"])
    assert engine.scan(r).verdict != "safe"


def test_sms_path_unchanged_when_channel_sms():
    r = ScanRequest(**json.load(open(FIX.parent / "scan_request_tmobile_lock.json")))
    assert r.channel == "sms" and len(engine.scan(r).findings) == 4
