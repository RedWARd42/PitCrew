"""Impersonator drone: brand named in body but sender/link do not belong to that brand."""
import re
from .common import mk, target_msg
from . import links


def brands_in(text: str, intel):
    found = []
    for b in intel.brands:
        for a in b["aliases"]:
            short = len(a) <= 3 and a.isalpha()  # "UPS", "IRS": case-sensitive to avoid "ups and downs"
            m = re.search(rf"(?<![\w-]){re.escape(a.upper() if short else a)}(?![\w-])", text, 0 if short else re.I)
            if m:
                found.append((b, m))
                break
    return found


def analyze(req, intel):
    msg = target_msg(req)
    if msg.direction != "in":
        return None, 0.0
    urls = links.extract_urls(msg.text, intel)
    best = (0.0, None)
    for b, m in brands_in(msg.text, intel):
        score, why = 0.0, []
        if req.sender.kind in ("long_code", "email", "alphanumeric", "toll_free", "unknown") and not req.sender.isContact:
            score += 0.5
            why.append(("sender_not_brand", req.sender.kind, "heuristic"))
        bad = [u for u in urls if not any(u[0] == d or u[0].endswith("." + d) for d in b["domains"])]
        if bad:
            score += 0.5
            why.append(("link_not_brand", links.reg_domain(bad[0][0]), "intel"))
        if score > best[0]:
            best = (score, (b, m, why))
    score, info = best
    if info is None or score < 0.5:
        return None, score
    b, m, why = info
    from .explain import template
    tp = template("impersonator", dict(brand=b["brand"], phone=b["officialPhone"] if b["verified"] else None))
    return mk("impersonator", score, tp["title"], tp["explanation"], [("brand", b["brand"], "intel")] + why,
              dict(messageId=msg.id, field="body", span=(m.start(), m.end())), tp.get("change")), score
