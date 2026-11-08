import pytest
from . import attachments, drift, impersonation, links, pressure, sender, warden
from .helpers import INTEL, req, sender as S


def f(mod, *a, **k):
    return mod.analyze(req(*a, **k), INTEL)[0]


# ---- links
@pytest.mark.parametrize("url", ["t-mobi1e-acct-verify.co/a8f", "https://paypa1-resolution.co/x", "usps-redelivery-pkg.top/p", "chase-secure-verify.top",
                                 "amazon-order-hold.icu", "bankofamerlca.com", "tmobile-bill-update.top"])
def test_links_flags_lookalikes(url):
    r = f(links, f"Please check {url} now")
    assert r and r.drone == "link" and r.severity == "high"


def test_links_span_and_evidence():
    t = "T-Mobile: your line will be suspended in 2 hrs. Verify: t-mobi1e-acct-verify.co/a8f"
    r = f(links, t)
    assert t[slice(*r.anchor.span)] == "t-mobi1e-acct-verify.co/a8f"
    assert {"kind": "domain_age_days", "value": "3", "source": "intel"} in [e.model_dump() for e in r.evidence]


@pytest.mark.parametrize("url", ["https://www.t-mobile.com/bill", "chase.com/mfa", "usps.com/track", "amazon.co.uk/orders", "my.t-mobile.com", "example-clinic.org/visit", "paypal.me/sam"])
def test_links_legit_brand_and_plain_domains_clean(url):
    assert f(links, f"See {url} for details") is None


def test_links_shortener_medium():
    r = f(links, "look at bit.ly/3xYz")
    assert r.severity in ("medium", "low") and r.evidence[0].kind == "shortener"


def test_links_punycode_and_ip():
    assert "punycode" in [e.kind for e in f(links, "go to http://xn--pypal-4ve.com/login").evidence]
    assert f(links, "open http://192.168.4.7/verify").evidence[0].kind == "ip_host"


def test_links_ignores_non_urls_and_emails():
    assert f(links, "Mr.Smith said hi. Contact a@b.com. Version 3.5 ok") is None
    assert f(links, "no links here") is None


def test_links_short_brand_not_substring():
    assert f(links, "see groups.com/info or cups.com") is None  # 'ups' inside another word is fine


# ---- pressure
def test_pressure_threat_deadline_span():
    t = "T-Mobile: your line will be suspended in 2 hrs. Verify now"
    r = f(pressure, t)
    assert r.drone == "pressure" and t[slice(*r.anchor.span)] == "suspended in 2 hrs"


@pytest.mark.parametrize("t", ["Your account is locked. Act now or face a fine", "Don't tell anyone, buy gift cards today", "URGENT: final notice, pay within 24 hours or legal action",
                               "Keep this between us and send bitcoin", "Failure to respond will result in arrest today"])
def test_pressure_scams(t):
    assert f(pressure, t)


@pytest.mark.parametrize("t", ["Your code 482913 expires in 10 minutes.", "Dinner at 7 tonight?", "Can you venmo me $20 for pizza?", "Your package arrives today.",
                               "Reminder: appointment tomorrow at 3pm", "Call me asap, no rush really"])
def test_pressure_legit_look_alikes_clean(t):
    assert f(pressure, t) is None


def test_pressure_classifier_only_path():
    r = pressure.analyze(req("hello"), INTEL, dict(category_id="otp_request", label="One-Time-Code Request", prob=0.9))[0]
    assert r and r.evidence[0].source == "classifier"


# ---- sender
def test_sender_long_code_brand_first_time():
    r = f(sender, "T-Mobile: pay your bill", S("+14695550182"))
    assert r.severity == "high" and r.anchor.messageId == "header"
    assert "complaints" in [e.kind for e in r.evidence]


def test_sender_short_code_bank_clean():
    assert f(sender, "Chase: card ending 4821 used for $23.10", S("33789", "short_code")) is None


def test_sender_contact_clean():
    assert f(sender, "T-Mobile: hi", S("+12145550100", contact=True)) is None


def test_sender_email_gateway():
    r = f(sender, "FRM:bob@x.example your prize", S("FRM:bob@x.example", "email"))
    assert r and "email_gateway" in [e.kind for e in r.evidence]


def test_sender_not_first_time_when_thread_has_outgoing():
    r = sender.analyze(req([("out", "hi"), ("in", "yo")], S("+12145550100")), INTEL)
    assert r[0] is None


def test_sender_toll_free_with_brand():
    assert f(sender, "Amazon: your order is held", S("+18885550150", "toll_free"))


def test_sender_incoming_plain_stranger_below_threshold_or_low():
    r = f(sender, "hey are you free tonight?", S("+12145550100"))
    assert r is None or r.severity == "low"


# ---- impersonator
def test_impersonator_t_mobile_verified_phone():
    t = "T-Mobile: your line will be suspended. Verify: t-mobi1e-acct-verify.co/a8f"
    r = f(impersonation, t, S("+14695550182"))
    assert r.drone == "impersonator" and t[slice(*r.anchor.span)] == "T-Mobile" and "611" in r.explanation


def test_impersonator_unverified_brand_no_phone():
    r = f(impersonation, "USPS: parcel held, pay at usps-redelivery-pkg.top/p", S())
    assert r and "611" not in r.explanation and "official app or website" in r.explanation


def test_impersonator_legit_short_code_brand_link_clean():
    assert f(impersonation, "Chase: bill ready at chase.com/bill", S("33789", "short_code")) is None


def test_impersonator_short_code_but_foreign_link():
    assert f(impersonation, "Chase: verify at chase-secure-verify.top", S("33789", "short_code"))


def test_impersonator_ups_case_sensitive():
    assert f(impersonation, "ups and downs of life, see you at 5", S()) is None
    assert f(impersonation, "UPS: delivery failed", S())


def test_impersonator_contact_clean():
    assert f(impersonation, "Amazon: my cousin", S(contact=True)) is None


# ---- warden
@pytest.mark.parametrize("t,kind", [("my code is <CODE:6>", "otp_in_draft"), ("the code: 482913", "otp_in_draft"), ("123-45-6789", "ssn_in_draft"),
                                    ("card 4242 4242 4242 4242", "card_in_draft"), ("the password is hunter2", "password_in_draft"), ("<CARD>", "card_in_draft"),
                                    ("gift card code ABCD1234EFGH", "giftcard_in_draft")])
def test_warden_hits(t, kind):
    r = warden.analyze(req([("out", t)], mode="outgoing_draft"), INTEL)[0]
    assert r and r.evidence[0].kind == kind and r.anchor.field == "compose" and r.anchor.messageId == "draft"
    assert r.evidence[0].value.startswith("<")  # secrets are masked, never echoed


@pytest.mark.parametrize("t", ["see you at 7", "I owe you 20 dollars", "4111 1111 1111 1112", "call 555 0100", "happy 2026!"])
def test_warden_clean(t):
    assert warden.analyze(req([("out", t)], mode="outgoing_draft"), INTEL)[0] is None


def test_warden_thread_asks_for_code_bare_digits():
    r = req([("in", "please send me the code you received"), ("out", "839201")], mode="outgoing_draft")
    assert warden.analyze(r, INTEL)[0].severity == "high"


def test_warden_ignores_incoming():
    assert warden.analyze(req("code <CODE:6>"), INTEL)[0] is None


def test_warden_contact_without_ask_is_medium():
    r = req([("out", "my code is <CODE:6>")], S(contact=True), "outgoing_draft")
    assert warden.analyze(r, INTEL)[0].severity == "medium"


# ---- drift / attachments
CRYPTO = [("in", "Hi, is this Anna?"), ("out", "wrong number"), ("in", "You seem nice, where are you from?"), ("in", "I do USDT investing, great profit")]


def test_drift_escalation_and_series():
    r = req(CRYPTO)
    fnd, _ = drift.analyze(r, INTEL)
    assert fnd.drone == "drift" and drift.series(r)[0] == [0.15, 0.15, 0.15, 1.0]


def test_drift_needs_two_messages():
    assert drift.analyze(req("is this Anna? invest in crypto"), INTEL)[0] is None


def test_drift_friendly_chat_clean():
    assert drift.analyze(req([("in", "how was your day?"), ("out", "good"), ("in", "nice to meet you btw")]), INTEL)[0] is None


def test_drift_money_between_friends_single_stage_clean():
    assert drift.analyze(req([("in", "can you transfer me the rent"), ("out", "sure"), ("in", "thanks")]), INTEL)[0] is None


def test_drift_three_stages_high():
    t = CRYPTO[:3] + [("in", "message me on whatsapp"), ("in", "send the usdt to my wallet")]
    assert drift.analyze(req(t), INTEL)[0].severity == "high"


def test_attachments_stub():
    assert attachments.analyze(req("x"), INTEL) == (None, 0.0)
