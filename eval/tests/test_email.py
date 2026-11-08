import json, pathlib, socket, subprocess, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "scripts"))
import emaillib, run_eval as E

ROOT = pathlib.Path(__file__).resolve().parents[2]
SC = emaillib.load_all()


def test_scenarios():
    assert len(SC) >= 12
    assert sum(s["expect"]["verdict"] == "safe" for s in SC.values()) >= 4
    for s in SC.values():
        for a in s["attachments"]:
            assert (emaillib.ED / "attachments" / a).exists()


def test_phish_visible_text_is_own_domain():
    for k, s in SC.items():
        if s["expect"]["verdict"] == "scam" and k != "paypal_text_href_mismatch":
            ls = emaillib.links(s["body"])
            assert all(l["text"] == l["href"] for l in ls), k
        if s["expect"]["verdict"] == "safe":
            assert all("paypa1" not in l["href"] and "0" not in l["href"].split("/")[2] for l in emaillib.links(s["body"])), k


def test_html_href_differs_from_text():
    m = emaillib.build(SC["paypal_text_href_mismatch"], "me@example.com")
    h = m.get_body(("html",)).get_content()
    assert 'href="https://paypa1-support.com/login?id=88a">https://www.paypal.com/verify<' in h
    assert "](" not in m.get_body(("plain",)).get_content()
    assert m["Reply-To"] == "help@mailbox-relay.biz" and not list(m.iter_attachments())


def test_fake_domains_do_not_resolve():
    ds = set()
    for s in SC.values():
        if s["expect"]["verdict"] != "scam": continue
        ds |= {s["from_address"].split("@")[1]} | ({s["reply_to"].split("@")[1]} if s["reply_to"] else set())
        ds |= {l["href"].split("/")[2] for l in emaillib.links(s["body"])}
    ds -= {"gmail.com", "bit.ly"}
    for d in ds:
        try: socket.gethostbyname(d)
        except OSError: continue
        raise AssertionError(f"{d} resolves")


def test_email_set_and_request_shape():
    rows = E.email_rows()
    assert len(rows) >= 300
    r = E.email_request(next(x for x in rows if x["id"] == "sc-paypal_text_href_mismatch"))
    assert r["channel"] == "email" and r["email"]["links"][0]["href"].startswith("https://paypa1") and r["email"]["replyTo"]


def test_cli_dry_run_never_sends():
    r = subprocess.run([sys.executable, str(ROOT / "scripts/send_test_emails.py"), "--all", "--to", "x@example.com", "--dry-run"], capture_output=True, text=True)
    assert r.returncode == 0 and r.stdout.count("---") >= 12
