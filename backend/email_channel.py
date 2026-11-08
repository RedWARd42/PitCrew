"""Email (Gmail) analyzers. Anchors: sender -> header/sender; link -> field "link" with span=(i, i) where i is the
INDEX into email.links (not a character offset); everything else -> field "body" on the email's message id."""
import re
from . import impersonation, links, pressure
from .common import mk, target_msg
from .explain import template

RISK_EXT = {"exe": "danger", "scr": "danger", "js": "danger", "vbs": "danger", "jar": "danger", "lnk": "danger", "apk": "danger", "bat": "danger", "msi": "danger",
            "html": "web", "htm": "web", "iso": "web", "img": "web", "svg": "web",
            "zip": "archive", "rar": "archive", "7z": "archive",
            "docm": "macro", "xlsm": "macro", "pptm": "macro"}
RISK_SCORE = {"danger": 0.9, "web": 0.8, "archive": 0.6, "macro": 0.7}
DOC_EXT = {"pdf", "doc", "docx", "xls", "xlsx", "txt", "jpg", "png"}
LURE = re.compile(r"invoice|receipt|payment|statement|remittance|purchase.?order|scan|voicemail", re.I)
CEO = pressure.EMAIL_RX[-1][1]


def _dom(addr: str) -> str:
    return addr.rsplit("@", 1)[-1].lower().strip(" <>")


def _is_esp(host, intel):
    return any(host == d or host.endswith("." + d) for d in intel.domains["espDomains"])


def _brand_owns(host, b):
    return any(host == d or host.endswith("." + d) for d in b["domains"])


def angler(req, intel):
    e, msg = req.email, target_msg(req)
    dom = _dom(e.fromAddress)
    rd = links.reg_domain(dom)
    score, ev, f = 0.0, [], {"domain": rd}
    brands = impersonation.brands_in(e.fromName, intel)
    owner = next((b for b in intel.brands if _brand_owns(dom, b)), None)
    if brands and not owner and not any(_brand_owns(dom, b) for b, _ in brands):
        score += 0.6
        f["brand"] = brands[0][0]["brand"]
        ev.append(("display_name_brand_mismatch", f"{e.fromName} <{dom}>", "heuristic"))
    b = None if owner else links.lookalike(rd, intel)
    if b:
        score += 0.8
        f.setdefault("brand", b["brand"])
        ev.append(("lookalike_sender_domain", f"{rd} ~ {b['domains'][0]}", "intel"))
    free = dom in intel.domains["freeMail"]
    if free and CEO.search(e.subject + " " + msg.text):
        score += 0.5
        f["exec"] = True
        ev.append(("free_mail_exec_request", dom, "heuristic"))
    if e.replyTo:
        rdom = links.reg_domain(_dom(e.replyTo))
        if rdom != rd and not _is_esp(_dom(e.replyTo), intel):
            score += 0.35
            f["reply"] = rdom
            ev.append(("reply_to_mismatch", rdom, "heuristic"))
    age = intel.whois.get(rd)
    if age is not None and age < 30:
        score += 0.4
        ev.append(("domain_age_days", str(age), "intel"))
    if rd.rsplit(".", 1)[-1] in intel.domains["riskyTlds"] and score:
        score += 0.2
        ev.append(("risky_tld", "." + rd.rsplit(".", 1)[-1], "intel"))
    score = min(score, 1.0)
    if score < 0.5:
        return None, score
    t = template("angler_email", f)
    return mk("angler", score, t["title"], t["explanation"], ev, dict(messageId="header", field="sender"), t.get("change")), score


def link(req, intel):
    e, msg = req.email, target_msg(req)
    best = (0.0, None)
    for i, lk in enumerate(e.links):
        m = re.match(r"(?i)^(?:https?://)?([^/\s:?#]+)", lk.href)
        if not m:
            continue
        host = m.group(1).lower().removeprefix("www.")
        rd = links.reg_domain(host)
        score, ev, b, age = links.score_url(host, lk.href, intel)
        mism = None
        shown = links.extract_urls(lk.text, intel)
        if shown and not _is_esp(host, intel):
            srd = links.reg_domain(shown[0][0])
            if srd != rd and not host.endswith("." + srd):
                mism = (srd, rd)
                score = max(score, 0.9)
                ev.insert(0, ("link_text_mismatch", f"{srd} -> {rd}", "heuristic"))
        elif not shown and not _is_esp(host, intel):
            for bb, _ in impersonation.brands_in(lk.text, intel):
                if not _brand_owns(host, bb):
                    score = max(score, 0.6)
                    ev.insert(0, ("brand_text_foreign_href", f"{bb['brand']} -> {rd}", "heuristic"))
                    break
        if score > best[0]:
            best = (score, (i, host, b, age, ev, mism))
    score, info = best
    if info is None or score < 0.4:
        # no hrefs available: fall back to URLs typed in the body
        if not e.links:
            f, s = links.analyze(req, intel)
            if f:
                f.anchor.field = "body"
            return f, s
        return None, score
    i, host, b, age, ev, mism = info
    if mism:
        t = template("link_email", dict(mismatch=True, shown=mism[0], real=mism[1]))
    else:
        t = links.link_template(host, b, age, intel)
    return mk("link", score, t["title"], t["explanation"], ev, dict(messageId=msg.id, field="link", span=(i, i)), t.get("change")), score


def carrier(req, intel):
    msg = target_msg(req)
    best = (0.0, None)
    for a in req.email.attachments:
        parts = a.name.lower().rsplit(".", 2)
        ext = parts[-1] if len(parts) > 1 else ""
        risk = RISK_EXT.get(ext)
        if not risk:
            continue
        score = RISK_SCORE[risk]
        ev = [("risky_extension", "." + ext, "heuristic")]
        if len(parts) == 3 and parts[1] in DOC_EXT:
            score += 0.1
            ev.append(("double_extension", a.name, "heuristic"))
        lure = bool(LURE.search(a.name))
        if lure:
            score += 0.1
            ev.append(("lure_name", a.name, "heuristic"))
        if score > best[0]:
            best = (min(score, 1.0), (a.name, risk, lure, ev))
    score, info = best
    if info is None:
        return None, 0.0
    name, risk, lure, ev = info
    t = template("carrier", dict(name=name, risk=risk, lure=lure))
    return mk("carrier", score, t["title"], t["explanation"], ev, dict(messageId=msg.id, field="body"), t.get("change")), score


def impersonator(req, intel):
    e, msg = req.email, target_msg(req)
    dom = _dom(e.fromAddress)
    best = (0.0, None)
    for where, text, base in (("fromName", e.fromName, 0.6), ("subject", e.subject, 0.5)):
        for b, m in impersonation.brands_in(text, intel):
            score, why = 0.0, []
            if not _brand_owns(dom, b):
                score += base
                why.append(("sender_not_brand", links.reg_domain(dom), "heuristic"))
            bad = [lk for lk in e.links if not _is_esp(_dom(lk.href.split("//")[-1].split("/")[0]), intel)
                   and not _brand_owns(_dom(lk.href.split("//")[-1].split("/")[0]), b)]
            if bad:
                score += 0.4
                why.append(("link_not_brand", links.reg_domain(_dom(bad[0].href.split("//")[-1].split("/")[0])), "intel"))
            if score > best[0]:
                best = (min(score, 1.0), (b, why))
    score, info = best
    if info is None or score < 0.5:
        return None, score
    b, why = info
    bm = impersonation.brands_in(msg.text, intel)
    span = next((m.span() for bb, m in bm if bb is b), None)
    t = template("impersonator", dict(brand=b["brand"], phone=b["officialPhone"] if b["verified"] else None))
    return mk("impersonator", score, t["title"], t["explanation"], [("brand", b["brand"], "intel")] + why,
              dict(messageId=msg.id, field="body", span=span), t.get("change")), score


def analyze(req, intel, clf_out):
    return {"angler": angler(req, intel), "link": link(req, intel), "pressure": pressure.analyze(req, intel, clf_out),
            "impersonator": impersonator(req, intel), "carrier": carrier(req, intel)}


W = dict(angler=0.6, link=0.7, pressure=0.5, impersonator=0.5, carrier=0.6)


def probability(res: dict, clf_prob: float) -> float:
    """Noisy-OR of analyzer scores (rule-based; the SMS-trained ensemble is not used for email). Classifier only adds if confident."""
    q = 1.0
    for k, w in W.items():
        q *= 1 - w * min(1.0, res[k][1] if res[k][0] else res[k][1] * 0.3)
    q *= 1 - 0.4 * max(0.0, 2 * (clf_prob - 0.5))
    return 1 - q
